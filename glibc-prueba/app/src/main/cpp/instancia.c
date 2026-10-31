#include "instancia.h"

#include <string.h>

bool
de_la_instancia (const char *cwd, const char *cmdline, const char *raiz)
{
  size_t n = strlen (raiz);
  if (n == 0)
    return false;
  if (cwd != NULL && strncmp (cwd, raiz, n) == 0 && (cwd[n] == '\0' || cwd[n] == '/'))
    return true;
  if (cmdline == NULL)
    return false;
  for (const char *p = strstr (cmdline, raiz); p != NULL; p = strstr (p + 1, raiz))
    if (p[n] == '\0' || p[n] == '/' || p[n] == ' ')
      return true;
  return false;
}
