/* fsync de Wine/Proton sin futex_waitv: el seccomp de las apps de Android
   mata futex_waitv (449) con SIGSYS (la glibc responde ENOSYS) y Wine cae a
   la sincronización por wineserver.  Este LD_PRELOAD atrapa syscall(449, ...)
   y la hace con futex (98), que sí está permitida:
   - sonda de Wine (sin futex): -1/EINVAL, como el kernel → "fsync: up and running".
   - 1 futex: FUTEX_WAIT_BITSET con el plazo absoluto en el reloj pedido.
   - varios: con futex no se puede esperar en varias direcciones, pero Wine
     siempre avisa con syscall(__NR_futex, FUTEX_WAKE), que también pasa por
     aquí: cada aviso sube un contador compartido entre todos los procesos
     (/dev/shm/futexv-<uid>) y despierta a los que esperan en él.  El que
     espera en varios lee el contador, revisa los valores y duerme en el
     contador: si llega un aviso entre medio, el contador ya cambió y no se
     duerme (no se pierden avisos).  Igual revisa cada 50 ms por si acaso.
   Valores que no coinciden → EAGAIN; plazo vencido → ETIMEDOUT (como el kernel).
   Compilar: gcc -O2 -shared -fPIC -o ~/.local/lib/libshim-futex.so shim-futex.c
   Prueba: steam/prueba-futexv.c.  */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#include <dlfcn.h>
#include <linux/futex.h>
#include <sys/mman.h>
#include <sys/syscall.h>

#ifndef __NR_futex_waitv
# define __NR_futex_waitv 449
#endif
#define FUTEX2_SIZE_U32 0x02
#define FUTEX2_PRIVATE FUTEX_PRIVATE_FLAG
#define REVISAR_NS 50000000L	/* espera máxima entre revisiones con varios futex */

static long (*real_syscall) (long, ...);

/* Página compartida: contador de avisos y cuántos esperan en él.  */
struct global
{
  uint32_t seq;
  uint32_t esperando;
};
static struct global *global;

static struct global *
obtener_global (void)
{
  struct global *g = __atomic_load_n (&global, __ATOMIC_ACQUIRE);
  if (g != NULL)
    return g;
  char ruta[64];
  snprintf (ruta, sizeof ruta, "/dev/shm/futexv-%u", (unsigned) getuid ());
  int fd = open (ruta, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
  if (fd < 0)
    return NULL;
  void *m = MAP_FAILED;
  if (ftruncate (fd, 4096) == 0)
    m = mmap (NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  close (fd);
  if (m == MAP_FAILED)
    return NULL;
  struct global *nada = NULL;
  if (!__atomic_compare_exchange_n (&global, &nada, m, 0,
				    __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE))
    {
      munmap (m, 4096);	/* otro hilo ganó */
      return nada;
    }
  return m;
}

static long
futex (void *uaddr, int op, uint32_t val, const struct timespec *ts,
       uint32_t val3)
{
  return real_syscall (__NR_futex, uaddr, op, val, ts, NULL, val3);
}

static int
vencido (const struct timespec *a, const struct timespec *b)
{
  return a->tv_sec > b->tv_sec
	 || (a->tv_sec == b->tv_sec && a->tv_nsec >= b->tv_nsec);
}

static long
futex_waitv (struct futex_waitv *w, unsigned int n, unsigned int flags,
	     const struct timespec *plazo, clockid_t reloj)
{
  if (n == 0 || n > FUTEX_WAITV_MAX || flags != 0 || w == NULL)
    {
      errno = EINVAL;
      return -1;
    }
  if (plazo != NULL && reloj != CLOCK_MONOTONIC && reloj != CLOCK_REALTIME)
    {
      errno = EINVAL;
      return -1;
    }
  for (unsigned int i = 0; i < n; i++)
    if ((w[i].flags & ~(FUTEX2_PRIVATE | 3)) != 0
	|| (w[i].flags & 3) != FUTEX2_SIZE_U32)
      {
	errno = EINVAL;	/* solo futex de 32 bits, como el kernel hoy */
	return -1;
      }
  /* FUTEX_WAIT_BITSET: plazo absoluto, en CLOCK_MONOTONIC salvo con
     FUTEX_CLOCK_REALTIME.  */
  int op_reloj = reloj == CLOCK_REALTIME ? FUTEX_CLOCK_REALTIME : 0;

  if (n == 1)
    {
      int op = FUTEX_WAIT_BITSET | op_reloj
	       | (w[0].flags & FUTEX2_PRIVATE ? FUTEX_PRIVATE_FLAG : 0);
      long r = futex ((void *) (uintptr_t) w[0].uaddr, op, (uint32_t) w[0].val,
		      plazo, FUTEX_BITSET_MATCH_ANY);
      return r == 0 ? 0 : -1;	/* errno: EAGAIN, ETIMEDOUT, EINTR */
    }

  struct global *g = obtener_global ();
  if (g == NULL)
    {
      errno = ENOMEM;
      return -1;
    }
  __atomic_add_fetch (&g->esperando, 1, __ATOMIC_SEQ_CST);
  long r;
  for (;;)
    {
      uint32_t s = __atomic_load_n (&g->seq, __ATOMIC_SEQ_CST);
      unsigned int i;
      for (i = 0; i < n; i++)
	if (__atomic_load_n ((uint32_t *) (uintptr_t) w[i].uaddr,
			     __ATOMIC_SEQ_CST) != (uint32_t) w[i].val)
	  break;
      if (i < n)
	{
	  /* Algún valor cambió: el kernel devuelve EAGAIN si ya era distinto al
	     entrar y el índice si lo despertaron después; Wine trata igual
	     ambos (vuelve a revisar sus objetos).  */
	  errno = EAGAIN;
	  r = -1;
	  break;
	}
      struct timespec ahora, hasta;
      clock_gettime (reloj, &ahora);
      if (plazo != NULL && vencido (&ahora, plazo))
	{
	  errno = ETIMEDOUT;
	  r = -1;
	  break;
	}
      hasta = ahora;
      hasta.tv_nsec += REVISAR_NS;
      if (hasta.tv_nsec >= 1000000000L)
	{
	  hasta.tv_sec++;
	  hasta.tv_nsec -= 1000000000L;
	}
      if (plazo != NULL && vencido (&hasta, plazo))
	hasta = *plazo;
      r = futex (&g->seq, FUTEX_WAIT_BITSET | op_reloj, s, &hasta,
		 FUTEX_BITSET_MATCH_ANY);
      if (r < 0 && errno == EINTR)
	break;
      /* despertado, contador ya distinto (EAGAIN) o revisión periódica
	 (ETIMEDOUT): volver a mirar los valores y el plazo real */
    }
  __atomic_sub_fetch (&g->esperando, 1, __ATOMIC_SEQ_CST);
  return r;
}

/* Después de cada FUTEX_WAKE de alguien: avisar a los que esperan en varios.  */
static void
avisar (void)
{
  struct global *g = obtener_global ();
  if (g == NULL)
    return;
  __atomic_add_fetch (&g->seq, 1, __ATOMIC_SEQ_CST);
  if (__atomic_load_n (&g->esperando, __ATOMIC_SEQ_CST) != 0)
    futex (&g->seq, FUTEX_WAKE, INT_MAX, NULL, 0);
}

long
syscall (long numero, ...)
{
  va_list ap;
  va_start (ap, numero);
  long a0 = va_arg (ap, long), a1 = va_arg (ap, long), a2 = va_arg (ap, long);
  long a3 = va_arg (ap, long), a4 = va_arg (ap, long), a5 = va_arg (ap, long);
  va_end (ap);

  if (real_syscall == NULL)
    real_syscall = (long (*) (long, ...)) dlsym (RTLD_NEXT, "syscall");

  if (numero == __NR_futex_waitv)
    return futex_waitv ((struct futex_waitv *) a0, (unsigned int) a1,
			(unsigned int) a2, (const struct timespec *) a3,
			(clockid_t) a4);

  long r = real_syscall (numero, a0, a1, a2, a3, a4, a5);
  if (numero == __NR_futex)
    {
      int cmd = (int) a1 & FUTEX_CMD_MASK;
      if (cmd == FUTEX_WAKE || cmd == FUTEX_WAKE_BITSET
	  || cmd == FUTEX_REQUEUE || cmd == FUTEX_CMP_REQUEUE
	  || cmd == FUTEX_WAKE_OP)
	{
	  int e = errno;
	  avisar ();
	  errno = e;
	}
    }
  return r;
}

__attribute__ ((constructor)) static void
iniciar (void)
{
  real_syscall = (long (*) (long, ...)) dlsym (RTLD_NEXT, "syscall");
}
