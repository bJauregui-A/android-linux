/* Prueba de SysV IPC emulado (glibc 0008): semáforos y memoria compartida.
   gcc -O2 -o /tmp/sysv sysv.c && /tmp/sysv  */
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ipc.h>
#include <sys/sem.h>
#include <sys/shm.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static int fallas;
#define OK(c, ...) do { if (c) printf ("ok    " __VA_ARGS__); \
  else { fallas++; printf ("FALLA " __VA_ARGS__); printf ("      errno=%s\n", strerror (errno)); } \
  printf ("\n"); } while (0)

static double
seg (void)
{
  struct timespec t;
  clock_gettime (CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec / 1e9;
}

int
main (void)
{
  /* Semáforo privado.  */
  int s = semget (IPC_PRIVATE, 2, IPC_CREAT | 0600);
  OK (s >= 0, "semget privado (id %d)", s);
  OK (semctl (s, 0, SETVAL, 3) == 0 && semctl (s, 0, GETVAL) == 3, "SETVAL/GETVAL");
  struct sembuf op = { 0, -2, 0 };
  OK (semop (s, &op, 1) == 0 && semctl (s, 0, GETVAL) == 1, "semop -2");
  op.sem_op = -5; op.sem_flg = IPC_NOWAIT;
  OK (semop (s, &op, 1) == -1 && errno == EAGAIN, "IPC_NOWAIT da EAGAIN");
  struct timespec lim = { 0, 200000000 };
  op.sem_flg = 0;
  double t0 = seg ();
  OK (semtimedop (s, &op, 1, &lim) == -1 && errno == EAGAIN && seg () - t0 > 0.15,
      "semtimedop vence a los %.2f s", seg () - t0);
  struct semid_ds ds;
  OK (semctl (s, 0, IPC_STAT, &ds) == 0 && ds.sem_nsems == 2, "IPC_STAT (nsems %lu)",
      (unsigned long) ds.sem_nsems);

  /* Clave: IPC_EXCL.  */
  key_t k = 0x5afe0000 + getpid ();
  int a = semget (k, 1, IPC_CREAT | IPC_EXCL | 0666);
  int b = semget (k, 1, IPC_CREAT | IPC_EXCL | 0666);
  OK (a >= 0 && b == -1 && errno == EEXIST, "clave con IPC_EXCL: EEXIST la 2ª vez");
  OK (semget (k, 1, 0) == a, "semget de la clave existente da el mismo id");

  /* Entre procesos: el hijo espera, el padre suelta.  */
  semctl (a, 0, SETVAL, 0);
  pid_t h = fork ();
  if (h == 0)
    {
      struct sembuf o = { 0, -1, 0 };
      _exit (semop (a, &o, 1) == 0 ? 0 : 1);
    }
  usleep (300000);
  OK (semctl (a, 0, GETNCNT) == 1, "GETNCNT ve al hijo esperando");
  struct sembuf mas = { 0, 1, 0 };
  semop (a, &mas, 1);
  int st;
  t0 = seg ();
  waitpid (h, &st, 0);
  OK (WIFEXITED (st) && WEXITSTATUS (st) == 0, "hijo despertado en %.3f s", seg () - t0);

  /* SEM_UNDO: el hijo toma el semáforo y muere sin soltarlo.  */
  semctl (a, 0, SETVAL, 1);
  h = fork ();
  if (h == 0)
    {
      struct sembuf o = { 0, -1, SEM_UNDO };
      semop (a, &o, 1);
      _exit (0);
    }
  waitpid (h, &st, 0);
  struct sembuf menos = { 0, -1, 0 };
  t0 = seg ();
  lim.tv_sec = 3; lim.tv_nsec = 0;
  OK (semtimedop (a, &menos, 1, &lim) == 0, "SEM_UNDO de un proceso muerto se aplica (%.2f s)", seg () - t0);

  OK (semctl (a, 0, IPC_RMID) == 0, "IPC_RMID");
  OK (semget (k, 1, 0) == -1 && errno == ENOENT, "la clave ya no existe");
  OK (semop (a, &mas, 1) == -1 && errno == EINVAL, "semop sobre id borrado: EINVAL");
  semctl (s, 0, IPC_RMID);

  /* Memoria compartida.  */
  int m = shmget (IPC_PRIVATE, 1 << 20, IPC_CREAT | 0600);
  OK (m >= 0, "shmget 1 MB (id %d)", m);
  char *p = shmat (m, NULL, 0);
  OK (p != (void *) -1, "shmat");
  strcpy (p + 500000, "hola desde el padre");
  OK (shmctl (m, IPC_RMID, NULL) == 0, "IPC_RMID con el segmento pegado");
  h = fork ();
  if (h == 0)
    {
      /* Linux deja pegar por id un segmento borrado que sigue en uso
	 (así lo usan MIT-SHM / Xwayland).  */
      char *q = shmat (m, NULL, 0);
      if (q == (void *) -1)
	_exit (2);
      int bien = strcmp (q + 500000, "hola desde el padre") == 0;
      strcpy (q + 10, "y el hijo");
      shmdt (q);
      _exit (bien ? 0 : 1);
    }
  waitpid (h, &st, 0);
  OK (WIFEXITED (st) && WEXITSTATUS (st) == 0, "el hijo pega el segmento por id y lee (status %d)",
      WEXITSTATUS (st));
  OK (strcmp (p + 10, "y el hijo") == 0, "el padre ve lo que escribió el hijo");
  struct shmid_ds sd;
  OK (shmctl (m, IPC_STAT, &sd) == 0 && sd.shm_nattch == 1 && sd.shm_segsz == 1 << 20,
      "IPC_STAT: nattch %lu, tamaño %zu", (unsigned long) sd.shm_nattch, sd.shm_segsz);
  OK (shmdt (p) == 0, "shmdt");
  OK (shmat (m, NULL, 0) == (void *) -1, "tras soltar el último, el segmento ya no existe");

  printf (fallas ? "\n%d FALLAS\n" : "\nTODO BIEN\n", fallas);
  return fallas != 0;
}
