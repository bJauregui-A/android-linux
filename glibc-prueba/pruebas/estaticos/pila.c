/* B17: la capa traduce las rutas de un estático en el manejador de SIGSYS (parche 0023). Un programa Go no escribe
   TPIDR_EL0 (queda en 0), corre sus goroutines en pilas chicas de su heap y deja una pila de señales de 32 KB, también de
   su heap. La traducción usa ~29 KB de pila: si el manejador la hace sobre la pila de la goroutine, o sobre la de
   señales, pisa lo que hay debajo ("alloc unmarked", caídas en el GC).
   Sin libc, como Go: puntero de hilo en 0, syscalls crudas, trabajo sobre una pila de goroutine de 16 KB y una
   sigaltstack de 32 KB, cada una entre canarios.
     pila            un hilo
     pila hilos      varios hilos (clone crudo con CLONE_VM, como newosproc de Go), cada uno con sus pilas
   Sale con 0 si ningún canario cambió; si no, dice cuántos bytes se pisaron en cada pila y sale con 1.
   Sin .bss: el cargador de la capa mapea mal un segmento solo-bss (desplazamiento fuera del archivo), así que el estado
   va en un mmap.  */
typedef unsigned long u64;
#define GOR (16 * 1024)
#define ALT (32 * 1024)
#define CANARIO (64 * 1024)
#define HILOS 4
#define VUELTAS 200

static long
sc (long nr, long a, long b, long c, long d, long e, long f)
{
  register long x8 __asm__ ("x8") = nr, x0 __asm__ ("x0") = a, x1 __asm__ ("x1") = b, x2 __asm__ ("x2") = c,
    x3 __asm__ ("x3") = d, x4 __asm__ ("x4") = e, x5 __asm__ ("x5") = f;
  __asm__ volatile ("svc 0" : "+r" (x0) : "r" (x8), "r" (x1), "r" (x2), "r" (x3), "r" (x4), "r" (x5) : "memory");
  return x0;
}
#define NR_write 64
#define NR_openat 56
#define NR_close 57
#define NR_mmap 222
#define NR_exit 93
#define NR_exit_group 94
#define NR_clone 220
#define NR_sigaltstack 132
#define NR_nanosleep 101

static void
escribir (const char *s)
{
  long n = 0;
  while (s[n]) n++;
  sc (NR_write, 1, (long) s, n, 0, 0, 0);
}

static void
numero (long v)
{
  char b[24]; int i = 23; b[i] = 0;
  do { b[--i] = '0' + v % 10; v /= 10; } while (v);
  escribir (b + i);
}

/* [canario bajo][pila de tam bytes][canario alto]; la pila se llena con 0xB6 para medir cuánto se usó */
struct region { unsigned char *base; long tam; };

static void
region_nueva (struct region *r, long tam)
{
  r->tam = tam;
  r->base = (unsigned char *) sc (NR_mmap, 0, 2 * CANARIO + tam, 3, 0x22, -1, 0);
  for (long i = 0; i < 2 * CANARIO + tam; i++)
    r->base[i] = (i < CANARIO || i >= CANARIO + tam) ? 0xA5 : 0xB6;
}

static unsigned char *
region_cima (struct region *r)
{
  return r->base + CANARIO + r->tam;
}

static void
region_activar_altstack (struct region *r)
{
  struct { void *sp; int flags; u64 size; } ss = { r->base + CANARIO, 0, r->tam };
  long rc = sc (NR_sigaltstack, (long) &ss, 0, 0, 0, 0, 0);
  if (rc) { escribir ("sigaltstack falló: "); numero (-rc); escribir ("\n"); }
}

static long
region_pisados (struct region *r)
{
  long n = 0;
  for (long i = 0; i < 2 * CANARIO + r->tam; i++)
    if ((i < CANARIO || i >= CANARIO + r->tam) && r->base[i] != 0xA5) n++;
  return n;
}

/* Bytes de la pila que se tocaron, contados desde la cima */
static long
region_uso (struct region *r)
{
  long i = 0;
  while (i < r->tam && r->base[CANARIO + i] == 0xB6) i++;
  return r->tam - i;
}

/* Rutas largas con muchos ".." y "." que la capa tiene que resolver y traducir; ninguna existe, da igual: se
   traduce antes de que el kernel diga ENOENT.  */
void __attribute__ ((used, noinline))
trabajo (void)
{
  static const char ruta[] = "/usr/bin/../lib/./../share/./../bin/../../usr/./lib/../../etc/./../usr/share/../lib/../bin/bash";
  static const char larga[] =
    "/usr/lib/../lib/../lib/../lib/../lib/../lib/../lib/../lib/../lib/../lib/../lib/../lib/../lib/../lib/../lib/../lib/../lib/../etc/os-release";
  for (int i = 0; i < VUELTAS; i++)
    {
      long fd = sc (NR_openat, -100, (long) ruta, 0, 0, 0, 0);
      if (fd >= 0) sc (NR_close, fd, 0, 0, 0, 0, 0);
      fd = sc (NR_openat, -100, (long) larga, 0, 0, 0, 0);
      if (fd >= 0) sc (NR_close, fd, 0, 0, 0, 0, 0);
    }
}

/* en_pila_goroutine (f, tope): f () con la pila en tope */
void en_pila_goroutine (void (*) (void), void *);
__asm__ (".text\n.type en_pila_goroutine, %function\nen_pila_goroutine:\n"
         "\tstp x29, x30, [sp, #-16]!\n\tmov x29, sp\n\tmov sp, x1\n\tblr x0\n\tmov sp, x29\n\tldp x29, x30, [sp], #16\n\tret\n");

struct estado { struct region gor[HILOS + 1], alt[HILOS + 1]; volatile int terminados; };
static struct estado *est;

static void
faena (int n)
{
  region_activar_altstack (&est->alt[n]);
  en_pila_goroutine (trabajo, region_cima (&est->gor[n]));
}

void __attribute__ ((used, noinline))
hilo (int n)
{
  faena (n);
  __atomic_add_fetch (&est->terminados, 1, __ATOMIC_SEQ_CST);
  sc (NR_exit, 0, 0, 0, 0, 0, 0);
}

/* clone crudo (CLONE_VM|FS|FILES|SIGHAND|THREAD|SYSVSEM): el hijo corre hilo(n) en su pila y no vuelve */
static void
lanzar (int n)
{
  unsigned char *pila = (unsigned char *) sc (NR_mmap, 0, 64 * 1024, 3, 0x22, -1, 0);
  register long x0 __asm__ ("x0") = 0x50f00;
  register long x1 __asm__ ("x1") = (long) (pila + 64 * 1024);
  register long x2 __asm__ ("x2") = 0, x3 __asm__ ("x3") = 0, x4 __asm__ ("x4") = 0;
  register long x8 __asm__ ("x8") = NR_clone;
  register long x5 __asm__ ("x5") = n;
  __asm__ volatile ("svc 0\n\tcbnz x0, 1f\n\tmov x0, x5\n\tbl hilo\n1:"
                    : "+r" (x0) : "r" (x1), "r" (x2), "r" (x3), "r" (x4), "r" (x5), "r" (x8) : "memory", "x30");
}

void
_start_c (long argc, char **argv)
{
  __asm__ volatile ("msr tpidr_el0, xzr");
  int hilos = argc > 1 && argv[1][0] == 'h', n = hilos ? HILOS : 0;
  est = (struct estado *) sc (NR_mmap, 0, 4096, 3, 0x22, -1, 0);
  for (int i = 0; i <= n; i++) { region_nueva (&est->gor[i], GOR); region_nueva (&est->alt[i], ALT); }
  for (int i = 1; i <= n; i++) lanzar (i);
  faena (0);
  while (__atomic_load_n (&est->terminados, __ATOMIC_SEQ_CST) < n)
    { long ts[2] = { 0, 1000000 }; sc (NR_nanosleep, (long) ts, 0, 0, 0, 0, 0); }
  long malos = 0, gor_max = 0, alt_max = 0;
  for (int i = 0; i <= n; i++)
    {
      long g = region_pisados (&est->gor[i]), a = region_pisados (&est->alt[i]);
      if (g || a)
        {
          malos++;
          escribir ("FALLA hilo "); numero (i); escribir (": canario pisado, pila de goroutine "); numero (g);
          escribir (" bytes, pila de señales "); numero (a); escribir (" bytes\n");
        }
      if (region_uso (&est->gor[i]) > gor_max) gor_max = region_uso (&est->gor[i]);
      if (region_uso (&est->alt[i]) > alt_max) alt_max = region_uso (&est->alt[i]);
    }
  escribir ("uso máximo: pila de goroutine "); numero (gor_max); escribir (" de 16384, pila de señales ");
  numero (alt_max); escribir (" de 32768 bytes\n");
  if (malos) sc (NR_exit_group, 1, 0, 0, 0, 0, 0);
  escribir ("OK canarios intactos\n");
  sc (NR_exit_group, 0, 0, 0, 0, 0, 0);
}

__asm__ (".global _start\n_start:\n\tldr x0, [sp]\n\tadd x1, sp, #8\n\tmov x2, sp\n\tand x2, x2, #-16\n\tmov sp, x2\n\tbl _start_c\n");
