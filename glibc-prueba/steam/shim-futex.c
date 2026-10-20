#define _GNU_SOURCE
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <stdint.h>
#include <stdarg.h>
#include <time.h>
#include <dlfcn.h>
#include <linux/futex.h>
#include <sys/syscall.h>

/* Android seccomp bloquea futex_waitv (449) con SIGSYS.
   Este shim intercepta syscall(449, ...) para activar WINEFSYNC en Proton:
   - Responde a la sonda inicial de wineserver/ntdll (ret -1, errno EINVAL).
   - Para 1 futex: delega a __NR_futex con FUTEX_WAIT_BITSET (permitida).
   - Para múltiples futexes: verifica si alguno cambió; si no, espera breve.  */

#ifndef __NR_futex_waitv
# define __NR_futex_waitv 449
#endif

static long (*real_syscall)(long number, ...);

long syscall(long number, ...)
{
  va_list args;
  va_start(args, number);
  long a0 = va_arg(args, long);
  long a1 = va_arg(args, long);
  long a2 = va_arg(args, long);
  long a3 = va_arg(args, long);
  long a4 = va_arg(args, long);
  long a5 = va_arg(args, long);
  va_end(args);

  if (number == __NR_futex_waitv)
    {
      struct futex_waitv *waiters = (struct futex_waitv *) a0;
      unsigned int nr_waiters = (unsigned int) a1;
      unsigned int flags = (unsigned int) a2;
      void *timeout = (void *) a3;
      int clockid = (int) a4;

      if (nr_waiters == 0 || waiters == NULL || flags != 0)
        {
          errno = EINVAL;
          return -1;
        }

      if (nr_waiters == 1)
        {
          int op = FUTEX_WAIT_BITSET | (waiters[0].flags & FUTEX_PRIVATE_FLAG);
          if (clockid == 1 /* CLOCK_MONOTONIC */)
            op |= FUTEX_CLOCK_REALTIME;
          return real_syscall(__NR_futex, waiters[0].uaddr, op,
                              (uint32_t) waiters[0].val, timeout, NULL,
                              0xffffffff /* FUTEX_BITSET_MATCH_ANY */);
        }

      /* Múltiples futexes: comprobar primero si alguno ya cambió */
      for (unsigned int i = 0; i < nr_waiters; i++)
        {
          volatile uint32_t *p = (volatile uint32_t *) (uintptr_t) waiters[i].uaddr;
          if (*p != (uint32_t) waiters[i].val)
            return (long) i;
        }

      /* Si ninguno cambió, espera breve en el primero */
      struct timespec ts = { .tv_sec = 0, .tv_nsec = 1000000 }; /* 1 ms */
      return real_syscall(__NR_futex, waiters[0].uaddr, FUTEX_WAIT_BITSET,
                          (uint32_t) waiters[0].val, &ts, NULL, 0xffffffff);
    }

  if (!real_syscall)
    real_syscall = (long (*)(long, ...)) dlsym(RTLD_NEXT, "syscall");

  return real_syscall(number, a0, a1, a2, a3, a4, a5);
}

__attribute__((constructor))
static void init(void)
{
  real_syscall = (long (*)(long, ...)) dlsym(RTLD_NEXT, "syscall");
}
