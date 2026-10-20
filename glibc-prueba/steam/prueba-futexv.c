/* Prueba de shim-futex.c sin Wine: lo que fsync le pide a futex_waitv.
   gcc -O2 -pthread -o /tmp/prueba-futexv prueba-futexv.c
   LD_PRELOAD=~/.local/lib/libshim-futex.so /tmp/prueba-futexv  */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdlib.h>
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

/* Hilo que espera en sus 2 futex privados hasta que cambie alguno.  */
static void *
esperador (void *arg)
{
  uint32_t (*ev)[16] = arg;
  uint32_t *f[2] = { ev[0], ev[1] }, v[2] = { 0, 0 };
  while (__atomic_load_n (f[1], __ATOMIC_SEQ_CST) == 0)
    esperar (f, v, 2, 1, NULL, 0);
  return NULL;
}

/* Cambios de contexto voluntarios de todos los hilos (despertares).  */
static long
cambios (void)
{
  long total = 0;
  DIR *d = opendir ("/proc/self/task");
  struct dirent *de;
  while ((de = readdir (d)) != NULL)
    {
      char ruta[300], l[128];
      snprintf (ruta, sizeof ruta, "/proc/self/task/%s/status", de->d_name);
      FILE *f = fopen (ruta, "r");
      if (f == NULL)
	continue;
      while (fgets (l, sizeof l, f))
	if (strncmp (l, "voluntary_ctxt_switches:", 24) == 0)
	  total += atol (l + 24);
      fclose (f);
    }
  closedir (d);
  return total;
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

  /* Memoria de fsync: archivo de /dev/shm que el otro proceso (wineserver)
     ve en otra dirección: la clave debe ser (inodo, desplazamiento).  */
  {
    char ruta[64];
    snprintf (ruta, sizeof ruta, "/dev/shm/prueba-futexv-%d", getpid ());
    int fd = open (ruta, O_RDWR | O_CREAT, 0600);
    ftruncate (fd, 8192);
    uint32_t *a = mmap (NULL, 8192, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    uint32_t *g[3] = { &a[0], &a[1024], &a[2047] };
    if (fork () == 0)
      {
	void *estorbo = mmap (NULL, 1 << 20, PROT_READ,
			      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	uint32_t *b = mmap (NULL, 8192, PROT_READ | PROT_WRITE, MAP_SHARED, fd,
			    0);
	(void) estorbo;
	usleep (80000);
	__atomic_store_n (&b[1024], 1, __ATOMIC_SEQ_CST);
	syscall (SYS_futex, &b[1024], FUTEX_WAKE, INT_MAX, NULL, NULL, 0);
	_exit (b == a);	/* misma dirección: la prueba no probaría nada */
      }
    t0 = ms (CLOCK_MONOTONIC);
    r = esperar (g, v, 3, 0, NULL, 0);
    e = errno;
    t0 = ms (CLOCK_MONOTONIC) - t0;
    int st;
    wait (&st);
    ver ("3 futex en archivo, despierta otro proceso en otra dirección",
	 WEXITSTATUS (st) == 0 && (r >= 0 || e == EAGAIN) && t0 < 95, t0);
    unlink (ruta);
  }

  /* Muchos esperando en varios (como los hilos de Unity) y avisos a otra
     cosa: no deben despertarse (la v1 despertaba a todos con cada aviso).  */
  {
    enum { HILOS = 40, AVISOS = 20000 };
    static uint32_t ev[HILOS][2][16], otro;
    pthread_t h[HILOS];
    for (int i = 0; i < HILOS; i++)
      pthread_create (&h[i], NULL, esperador, ev[i]);
    usleep (200000);
    long antes = cambios ();
    t0 = ms (CLOCK_MONOTONIC);
    for (int i = 0; i < AVISOS; i++)
      syscall (SYS_futex, &otro, FUTEX_WAKE_PRIVATE, 1, NULL, NULL, 0);
    t0 = ms (CLOCK_MONOTONIC) - t0;
    long extra = cambios () - antes;
    for (int i = 0; i < HILOS; i++)
      {
	__atomic_store_n (&ev[i][1][0], 1, __ATOMIC_SEQ_CST);
	syscall (SYS_futex, &ev[i][1][0], FUTEX_WAKE_PRIVATE, 1, NULL, NULL, 0);
      }
    for (int i = 0; i < HILOS; i++)
      pthread_join (h[i], NULL);
    char s[80];
    snprintf (s, sizeof s, "%d hilos esperando, %d avisos a otro: %ld despertares",
	      HILOS, AVISOS, extra);
    /* falsos positivos: alguno puede compartir el bit de "otro" (1 de cada
       ~128 por futex); la v1 daba 40 por aviso */
    ver (s, extra < AVISOS * 2, t0);
  }

  printf (fallas ? "%d FALLAS\n" : "todo bien\n", fallas);
  return fallas != 0;
}
