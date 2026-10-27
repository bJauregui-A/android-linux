/* Binario static-pie (como el wine-preloader de Wine 11): se reubica solo al
   arrancar, escribiendo en su RELRO.  Si el cargador ya lo reubicó y protegió
   ese RELRO, se cae con SIGSEGV (SEGV_ACCERR) o los punteros quedan corridos.
   La tabla va en .data.rel.ro: necesita reubicación R_AARCH64_RELATIVE.  */
#include <stdio.h>

static const char *const tabla[] = { "pie", "-ok" };

int
main (void)
{
  printf ("%s%s\n", tabla[0], tabla[1]);
  return 0;
}
