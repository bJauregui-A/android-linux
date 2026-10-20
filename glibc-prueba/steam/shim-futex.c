/* fsync de Wine/Proton sin futex_waitv: el seccomp de las apps de Android
   mata futex_waitv (449) con SIGSYS (la glibc responde ENOSYS) y Wine cae a
   la sincronización por wineserver.  Este LD_PRELOAD atrapa syscall(449, ...)
   y la hace con futex (98), que sí está permitida:
   - sonda de Wine (sin futex): -1/EINVAL, como el kernel → "fsync: up and running".
   - 1 futex: FUTEX_WAIT_BITSET con el plazo absoluto en el reloj pedido.
   - varios: con futex no se puede esperar en varias direcciones, pero Wine
     siempre avisa con syscall(__NR_futex, FUTEX_WAKE), que también pasa por
     aquí.  El que espera en varios toma un puesto en una tabla compartida
     entre procesos (/dev/shm/futexv2-<uid>), anota una marca de 256 bits con
     las direcciones que espera y duerme en el contador de su puesto.  Cada
     FUTEX_WAKE recorre la tabla y despierta solo a los puestos cuya marca
     tiene el bit de esa dirección (falsos positivos 1/128 con 2 futex:
     vuelven a revisar y a dormir).  La marca se publica antes de revisar
     los valores, así que no se pierden avisos; igual se revisa cada 50 ms.
     (La v1 tenía un solo contador para todos: cada aviso despertaba a los 48
     hilos de ATLYSS que esperaban y el juego bajó a 4-5 fps.)
     Clave de una dirección, como la del kernel: futex privado → (proceso,
     dirección); compartido en un archivo mapeado con MAP_SHARED (la memoria
     de fsync, que wineserver y el juego ven en direcciones distintas) →
     (inodo, desplazamiento en el archivo), sacado de /proc/self/maps.
   Valores que no coinciden → EAGAIN; plazo vencido → ETIMEDOUT (como el kernel).
   Compilar: gcc -O2 -shared -fPIC -o ~/.local/lib/libshim-futex.so shim-futex.c
   Prueba: steam/prueba-futexv.c.  */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
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
#define NPUESTOS 1024

static long (*real_syscall) (long, ...);

struct puesto
{
  uint32_t seq;		/* el dueño duerme aquí; el que avisa lo sube */
  int32_t tid;		/* 0 = libre */
  int32_t tgid;
  uint32_t pad;
  uint64_t marca[4];	/* bits de las claves de lo que espera (256) */
};

struct tabla
{
  uint32_t usados;	/* puestos que se han usado alguna vez (para recorrer) */
  uint32_t pad[3];
  struct puesto p[NPUESTOS];
};
static struct tabla *tabla;

static long
futex (void *uaddr, int op, uint32_t val, const struct timespec *ts,
       uint32_t val3)
{
  return real_syscall (__NR_futex, uaddr, op, val, ts, NULL, val3);
}

static struct tabla *
obtener_tabla (void)
{
  struct tabla *t = __atomic_load_n (&tabla, __ATOMIC_ACQUIRE);
  if (t != NULL)
    return t;
  char ruta[64];
  snprintf (ruta, sizeof ruta, "/dev/shm/futexv2-%u", (unsigned) getuid ());
  int fd = open (ruta, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
  if (fd < 0)
    return NULL;
  void *m = MAP_FAILED;
  if (ftruncate (fd, sizeof (struct tabla)) == 0)
    m = mmap (NULL, sizeof (struct tabla), PROT_READ | PROT_WRITE, MAP_SHARED,
	      fd, 0);
  close (fd);
  if (m == MAP_FAILED)
    return NULL;
  struct tabla *nada = NULL;
  if (!__atomic_compare_exchange_n (&tabla, &nada, m, 0,
				    __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE))
    {
      munmap (m, sizeof (struct tabla));	/* otro hilo ganó */
      return nada;
    }
  return m;
}

/* Mapeos MAP_SHARED de archivos del proceso, leídos de /proc/self/maps.
   Se reemplaza entero (sin liberar el viejo: alguien puede estar leyéndolo)
   cuando una dirección compartida no aparece.  */
struct mapeo
{
  uintptr_t ini, fin;
  uint64_t inodo, desp;
};
struct mapeos
{
  int n;
  pid_t pid;
  struct timespec leido;
  struct mapeo m[];
};
static struct mapeos *mapeos;

static struct mapeos *
leer_mapeos (void)
{
  int fd = open ("/proc/self/maps", O_RDONLY | O_CLOEXEC);
  if (fd < 0)
    return NULL;
  size_t cap = 1 << 20, len = 0;
  char *buf = mmap (NULL, cap, PROT_READ | PROT_WRITE,
		    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (buf == MAP_FAILED)
    {
      close (fd);
      return NULL;
    }
  ssize_t r;
  while (len < cap - 1 && (r = read (fd, buf + len, cap - 1 - len)) > 0)
    len += r;
  close (fd);
  buf[len] = 0;
  int n = 0;
  for (char *l = buf; *l; l++)
    n += *l == '\n';
  size_t tam = sizeof (struct mapeos) + (n + 1) * sizeof (struct mapeo);
  struct mapeos *ms = mmap (NULL, tam, PROT_READ | PROT_WRITE,
			    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (ms == MAP_FAILED)
    {
      munmap (buf, cap);
      return NULL;
    }
  ms->n = 0;
  ms->pid = getpid ();
  clock_gettime (CLOCK_MONOTONIC, &ms->leido);
  for (char *l = buf; *l;)
    {
      /* ini-fin perm desp dev inodo ruta */
      char *e;
      uintptr_t ini = strtoull (l, &e, 16);
      uintptr_t fin = strtoull (e + 1, &e, 16);
      char compartido = e[4];
      uint64_t desp = strtoull (e + 6, &e, 16);
      while (*e == ' ')
	e++;
      while (*e && *e != ' ')
	e++;	/* dev */
      uint64_t inodo = strtoull (e, &e, 10);
      if (compartido == 's' && inodo != 0)
	ms->m[ms->n++] = (struct mapeo) { ini, fin, inodo, desp };
      while (*e && *e != '\n')
	e++;
      l = *e ? e + 1 : e;
    }
  munmap (buf, cap);
  return ms;
}

static uint64_t
mezclar (uint64_t x)
{
  x += 0x9e3779b97f4a7c15ULL;
  x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
  x = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
  return x ^ (x >> 31);
}

static unsigned int
bit_clave (uintptr_t a, int privado)
{
  if (!privado)
    for (int intento = 0; intento < 2; intento++)
      {
	struct mapeos *ms = __atomic_load_n (&mapeos, __ATOMIC_ACQUIRE);
	if (ms != NULL && ms->pid == getpid ())
	  for (int i = 0; i < ms->n; i++)
	    if (a >= ms->m[i].ini && a < ms->m[i].fin)
	      return mezclar (ms->m[i].inodo * 0x100000001b3ULL
			      ^ (ms->m[i].desp + (a - ms->m[i].ini))) & 255;
	if (intento == 1)
	  break;
	/* No está: releer, salvo que se haya leído hace menos de 10 ms (una
	   dirección compartida en memoria anónima volvería a fallar siempre).  */
	struct timespec ahora;
	clock_gettime (CLOCK_MONOTONIC, &ahora);
	if (ms != NULL && ms->pid == getpid ()
	    && (ahora.tv_sec - ms->leido.tv_sec) * 1000000000L
	       + ahora.tv_nsec - ms->leido.tv_nsec < 10000000L)
	  break;
	struct mapeos *nuevo = leer_mapeos ();
	if (nuevo == NULL)
	  break;
	__atomic_store_n (&mapeos, nuevo, __ATOMIC_RELEASE);
      }
  /* privado, o compartido en memoria anónima del proceso (el kernel también
     lo identifica por proceso y dirección) */
  return mezclar ((uint64_t) getpid () << 48 ^ a) & 255;
}

/* Libera los puestos de hilos que murieron esperando.  */
static void
recuperar (struct tabla *t)
{
  uint32_t n = __atomic_load_n (&t->usados, __ATOMIC_ACQUIRE);
  for (uint32_t i = 0; i < n && i < NPUESTOS; i++)
    {
      struct puesto *p = &t->p[i];
      int32_t tid = __atomic_load_n (&p->tid, __ATOMIC_ACQUIRE);
      if (tid != 0
	  && real_syscall (__NR_tgkill, p->tgid, tid, 0) == -1 && errno == ESRCH)
	{
	  for (int k = 0; k < 4; k++)
	    __atomic_store_n (&p->marca[k], 0, __ATOMIC_SEQ_CST);
	  __atomic_compare_exchange_n (&p->tid, &tid, 0, 0, __ATOMIC_SEQ_CST,
				       __ATOMIC_SEQ_CST);
	}
    }
}

static struct puesto *
tomar_puesto (struct tabla *t)
{
  int32_t yo = gettid ();
  for (int vuelta = 0; vuelta < 2; vuelta++)
    {
      for (uint32_t k = 0; k < NPUESTOS; k++)
	{
	  uint32_t i = (yo + k) % NPUESTOS;
	  int32_t libre = 0;
	  if (__atomic_load_n (&t->p[i].tid, __ATOMIC_RELAXED) == 0
	      && __atomic_compare_exchange_n (&t->p[i].tid, &libre, yo, 0,
					      __ATOMIC_SEQ_CST,
					      __ATOMIC_RELAXED))
	    {
	      t->p[i].tgid = getpid ();
	      uint32_t u = __atomic_load_n (&t->usados, __ATOMIC_RELAXED);
	      while (u < i + 1
		     && !__atomic_compare_exchange_n (&t->usados, &u, i + 1, 1,
						      __ATOMIC_SEQ_CST,
						      __ATOMIC_RELAXED))
		;
	      return &t->p[i];
	    }
	}
      recuperar (t);
    }
  return NULL;
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

  struct tabla *t = obtener_tabla ();
  struct puesto *p = t != NULL ? tomar_puesto (t) : NULL;
  if (p != NULL)
    {
      uint64_t marca[4] = { 0 };
      for (unsigned int i = 0; i < n; i++)
	{
	  unsigned int b = bit_clave (w[i].uaddr, w[i].flags & FUTEX2_PRIVATE);
	  marca[b / 64] |= 1ULL << (b % 64);
	}
      for (int k = 0; k < 4; k++)
	__atomic_store_n (&p->marca[k], marca[k], __ATOMIC_SEQ_CST);
    }
  long r;
  for (;;)
    {
      uint32_t s = p != NULL ? __atomic_load_n (&p->seq, __ATOMIC_SEQ_CST) : 0;
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
      /* sin puesto (tabla llena o sin /dev/shm): mirar cada 1 ms */
      hasta.tv_nsec += p != NULL ? REVISAR_NS : 1000000L;
      if (hasta.tv_nsec >= 1000000000L)
	{
	  hasta.tv_sec++;
	  hasta.tv_nsec -= 1000000000L;
	}
      if (plazo != NULL && vencido (&hasta, plazo))
	hasta = *plazo;
      if (p != NULL)
	r = futex (&p->seq, FUTEX_WAIT_BITSET | op_reloj, s, &hasta,
		   FUTEX_BITSET_MATCH_ANY);
      else
	r = real_syscall (__NR_clock_nanosleep, reloj, TIMER_ABSTIME, &hasta,
			  NULL);
      if (r < 0 && errno == EINTR)
	break;
      /* despertado, contador ya distinto (EAGAIN) o revisión periódica
	 (ETIMEDOUT): volver a mirar los valores y el plazo real */
    }
  if (p != NULL)
    {
      int e = errno;
      for (int k = 0; k < 4; k++)
	__atomic_store_n (&p->marca[k], 0, __ATOMIC_SEQ_CST);
      __atomic_store_n (&p->tid, 0, __ATOMIC_SEQ_CST);
      errno = e;
    }
  return r;
}

/* Después de un FUTEX_WAKE en `a`: despertar a los que esperan en varios
   futex y tienen esa dirección en su marca.  */
static void
avisar (uintptr_t a, int privado)
{
  struct tabla *t = obtener_tabla ();
  if (t == NULL)
    return;
  uint32_t n = __atomic_load_n (&t->usados, __ATOMIC_SEQ_CST);
  if (n == 0)
    return;
  unsigned int b = bit_clave (a, privado);
  uint64_t bit = 1ULL << (b % 64);
  for (uint32_t i = 0; i < n && i < NPUESTOS; i++)
    if (__atomic_load_n (&t->p[i].marca[b / 64], __ATOMIC_SEQ_CST) & bit)
      {
	__atomic_add_fetch (&t->p[i].seq, 1, __ATOMIC_SEQ_CST);
	futex (&t->p[i].seq, FUTEX_WAKE, 1, NULL, 0);
      }
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
      int privado = ((int) a1 & FUTEX_PRIVATE_FLAG) != 0;
      if (cmd == FUTEX_WAKE || cmd == FUTEX_WAKE_BITSET || cmd == FUTEX_WAKE_OP
	  || cmd == FUTEX_REQUEUE || cmd == FUTEX_CMP_REQUEUE)
	{
	  int e = errno;
	  avisar ((uintptr_t) a0, privado);
	  if (cmd != FUTEX_WAKE && cmd != FUTEX_WAKE_BITSET)
	    avisar ((uintptr_t) a4, privado);	/* uaddr2 */
	  errno = e;
	}
    }
  return r;
}

__attribute__ ((constructor)) static void
iniciar (void)
{
  real_syscall = (long (*) (long, ...)) dlsym (RTLD_NEXT, "syscall");
  struct tabla *t = obtener_tabla ();
  if (t != NULL)
    recuperar (t);
}
