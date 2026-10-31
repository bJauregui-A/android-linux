/* Abre un archivo con la syscall que se pida y dice cómo salió (B96).
     abrir <openat|openat2> <ruta> <rd|wr|rdwr> [excl]
   Imprime "ok" o el texto del error.  "excl" suma O_CREAT|O_EXCL.  Es lo que el shell no puede hacer:
   llamar a openat2 y pedir O_EXCL sobre un archivo que existe.  */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

struct how { uint64_t flags, mode, resolve; };

int
main (int argc, char **argv)
{
  if (argc < 4)
    return 2;
  int flags = !strcmp (argv[3], "rd") ? O_RDONLY
	      : !strcmp (argv[3], "wr") ? O_WRONLY : O_RDWR;
  if (argc > 4 && !strcmp (argv[4], "excl"))
    flags |= O_CREAT | O_EXCL;
  long r;
  if (!strcmp (argv[1], "openat2"))
    {
      struct how h = { flags, 0644, 0 };
      r = syscall (SYS_openat2, AT_FDCWD, argv[2], &h, sizeof h);
    }
  else
    r = syscall (SYS_openat, AT_FDCWD, argv[2], flags, 0644);
  puts (r >= 0 ? "ok" : strerror (errno));
  return 0;
}
