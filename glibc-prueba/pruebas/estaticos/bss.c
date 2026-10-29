/* B17: ELF mínimo, sin libc, con un segmento LOAD solo-.bss (p_filesz = 0, desplazamiento fuera del archivo). El kernel lo
   carga bien; el rtld de glibc mapeaba 64 KB del archivo desde el desplazamiento 0, más allá del final, y al tocar esas
   páginas daba SIGBUS.  Escribe y lee su .bss: sale con 0 si sirve.  */
static char vacio[4096];

static long
sc (long nr, long a, long b, long c)
{
  register long x8 __asm__ ("x8") = nr, x0 __asm__ ("x0") = a, x1 __asm__ ("x1") = b, x2 __asm__ ("x2") = c;
  __asm__ volatile ("svc 0" : "+r" (x0) : "r" (x8), "r" (x1), "r" (x2) : "memory");
  return x0;
}

void
_start_c (void)
{
  for (int i = 0; i < 4096; i++) vacio[i] = i & 0x7f;
  long suma = 0;
  for (int i = 0; i < 4096; i++) suma += vacio[i];
  static const char ok[] = "OK .bss en un segmento propio\n";
  if (suma != 260096) sc (94, 1, 0, 0);
  sc (64, 1, (long) ok, sizeof ok - 1);
  sc (94, 0, 0, 0);
}

__asm__ (".global _start\n_start:\n\tmov x0, sp\n\tand x0, x0, #-16\n\tmov sp, x0\n\tbl _start_c\n");
