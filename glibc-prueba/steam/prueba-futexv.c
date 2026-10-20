/* Prueba de shim-futex.c sin Wine: lo que fsync le pide a futex_waitv.
   gcc -O2 -o /tmp/prueba-futexv prueba-futexv.c
   LD_PRELOAD=~/.local/lib/libshim-futex.so /tmp/prueba-futexv  */
#define _GNU_SOURCE
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <linux/futex.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>

#ifndef __NR_futex_waitv
# define __NR_futex_waitv 449
#endif

static int fallas;

static double
ms (clockid_t c)
{
  struct timespec t;
  clock_gettime (c, &t);
  return t.tv_sec * 1e3 + t.tv_nsec / 1e6;
}

static struct timespec
en (clockid_t c, int mseg)
{
  struct timespec t;
  clock_gettime (c, &t);
  t.tv_nsec += (long) mseg * 1000000L;
  t.tv_sec += t.tv_nsec / 1000000000L;
  t.tv_nsec %= 1000000000L;
  return t;
}

static long
esperar (uint32_t **f, uint32_t *val, int n, int priv, struct timespec *ts,
	 clockid_t c)
{
  struct futex_waitv w[8];
  memset (w, 0, sizeof w);
  for (int i = 0; i < n; i++)
    {
      w[i].uaddr = (uintptr_t) f[i];
      w[i].val = val[i];
      w[i].flags = 2 /* FUTEX2_SIZE_U32 */ | (priv ? FUTEX_PRIVATE_FLAG : 0);
    }
  return syscall (__NR_futex_waitv, w, n, 0, ts, c);
}

static void
ver (const char *que, int ok, double t)
{
  printf ("%s %-48s %7.1f ms\n", ok ? "ok   " : "FALLA", que, t);
  fallas += !ok;
}

/* Hijo: tras `tras` ms cambia *f y lo despierta (como el wake de fsync).  */
static void
despertar_luego (uint32_t *f, int tras)
{
  if (fork () == 0)
    {
      usleep (tras * 1000);
      __atomic_store_n (f, 1, __ATOMIC_SEQ_CST);
      syscall (SYS_futex, f, FUTEX_WAKE, INT_MAX, NULL, NULL, 0);
      _exit (0);
    }
}

int
main (void)
{
  uint32_t *m = mmap (NULL, 4096, PROT_READ | PROT_WRITE,
		      MAP_SHARED | MAP_ANONYMOUS, -1, 0);
  uint32_t *f[3] = { &m[0], &m[16], &m[32] }, v[3] = { 0, 0, 0 };
  long r;
  int e;
  double t0;

  r = syscall (__NR_futex_waitv, NULL, 0, 0, NULL, 0);
  e = errno;
  ver ("sonda de Wine → EINVAL", r == -1 && e == EINVAL, 0);

  clockid_t relojes[2] = { CLOCK_MONOTONIC, CLOCK_REALTIME };
  const char *nombre[2] = { "MONOTONIC", "REALTIME" };
  for (int k = 0; k < 2; k++)
    {
      char s[64];
      struct timespec ts = en (relojes[k], 150);
      t0 = ms (CLOCK_MONOTONIC);
      r = esperar (f, v, 1, 1, &ts, relojes[k]);
      e = errno;
      t0 = ms (CLOCK_MONOTONIC) - t0;
      snprintf (s, sizeof s, "1 futex, plazo 150 ms %s → ETIMEDOUT", nombre[k]);
      ver (s, r == -1 && e == ETIMEDOUT && t0 > 140 && t0 < 250, t0);

      ts = en (relojes[k], 300);
      t0 = ms (CLOCK_MONOTONIC);
      r = esperar (f, v, 3, 0, &ts, relojes[k]);
      e = errno;
      t0 = ms (CLOCK_MONOTONIC) - t0;
      snprintf (s, sizeof s, "3 futex, plazo 300 ms %s → ETIMEDOUT", nombre[k]);
      ver (s, r == -1 && e == ETIMEDOUT && t0 > 290 && t0 < 400, t0);
    }

  m[0] = 7;
  r = esperar (f, v, 1, 1, NULL, 0);
  e = errno;
  ver ("1 futex, valor distinto → EAGAIN", r == -1 && e == EAGAIN, 0);
  r = esperar (f, v, 3, 0, NULL, 0);
  e = errno;
  ver ("3 futex, valor distinto → EAGAIN", r == -1 && e == EAGAIN, 0);
  m[0] = 0;

  despertar_luego (f[0], 80);
  t0 = ms (CLOCK_MONOTONIC);
  r = esperar (f, v, 1, 0, NULL, 0);
  t0 = ms (CLOCK_MONOTONIC) - t0;
  ver ("1 futex, despertado a los 80 ms (otro proceso)", r == 0 && t0 < 100, t0);
  wait (NULL);
  m[0] = 0;

  for (int i = 0; i < 3; i++)
    {
      char s[64];
      int tras = i == 2 ? 400 : 80;	/* 400: más que la revisión de 50 ms */
      despertar_luego (f[i], tras);
      struct timespec ts = en (CLOCK_MONOTONIC, 2000);
      t0 = ms (CLOCK_MONOTONIC);
      r = esperar (f, v, 3, 0, i == 1 ? &ts : NULL, CLOCK_MONOTONIC);
      e = errno;
      t0 = ms (CLOCK_MONOTONIC) - t0;
      snprintf (s, sizeof s, "3 futex, despierta el %d a los %d ms%s", i, tras,
		i == 1 ? " (plazo 2 s)" : "");
      /* el kernel daría el índice; el shim, EAGAIN o 0: Wine trata igual */
      ver (s, (r >= 0 || e == EAGAIN) && t0 > tras - 5 && t0 < tras + 15, t0);
      wait (NULL);
      m[16 * i] = 0;
    }

  printf (fallas ? "%d FALLAS\n" : "todo bien\n", fallas);
  return fallas != 0;
}
