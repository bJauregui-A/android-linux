/* ¿Un proceso es de la instancia con raíz `raiz`?  Mismo criterio que
   Pausa.deLaInstancia: su cwd está dentro de la raíz, o la raíz aparece en su
   cmdline (con los NUL cambiados por espacios) seguida de '/', espacio o fin.  */
#ifndef INSTANCIA_H
#define INSTANCIA_H

#include <stdbool.h>

bool de_la_instancia (const char *cwd, const char *cmdline, const char *raiz);

#endif
