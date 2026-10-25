/* Binario estático para C19 (B26): no usa la glibc de la instancia, así que
   sus syscalls llegan por la capa seccomp propia (parche 0015).
     estatico ls <dir>          lista <dir> ordenado, uno por línea
     estatico execveat <dir> <ruta-relativa> [args...]
   (execveat abre <dir> y ejecuta <ruta-relativa> respecto a él.)  */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

extern char **environ;

int
main (int argc, char **argv)
{
  if (argc >= 3 && !strcmp (argv[1], "ls"))
    {
      struct dirent **l;
      int n = scandir (argv[2], &l, NULL, alphasort);
      if (n < 0)
	{
	  perror (argv[2]);
	  return 1;
	}
      for (int i = 0; i < n; i++)
	if (strcmp (l[i]->d_name, ".") && strcmp (l[i]->d_name, ".."))
	  puts (l[i]->d_name);
      return 0;
    }
  if (argc >= 4 && !strcmp (argv[1], "execveat"))
    {
      int fd = open (argv[2], O_PATH | O_DIRECTORY);
      if (fd < 0)
	{
	  perror (argv[2]);
	  return 1;
	}
      syscall (SYS_execveat, fd, argv[3], argv + 3, environ, 0);
      perror ("execveat");
      return 1;
    }
  fprintf (stderr, "uso: estatico ls <dir> | execveat <dir> <ruta> [args]\n");
  return 2;
}
