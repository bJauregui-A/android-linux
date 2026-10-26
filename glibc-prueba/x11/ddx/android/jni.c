/* B11: entrada JNI del servidor X11 en el proceso :x11. Java nunca toca el estado del servidor. */
#include <jni.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

int dix_main(int argc, char *argv[], char *envp[]);
extern char **environ;

static char **args;
static int nargs;

static void *hilo_servidor(void *p)
{
    dix_main(nargs, args, environ);
    return NULL;
}

/* iniciar(String[] argumentos): arranca el bucle del servidor en un hilo propio. */
JNIEXPORT void JNICALL
Java_dev_ben4shot_glibcprueba_ServicioX11_iniciar(JNIEnv *env, jclass cls, jobjectArray argumentos)
{
    pthread_t t;
    int i, n = (*env)->GetArrayLength(env, argumentos);

    args = calloc(n + 2, sizeof(char *));
    args[0] = strdup("Xandroid");
    for (i = 0; i < n; i++) {
        jstring s = (*env)->GetObjectArrayElement(env, argumentos, i);
        const char *c = (*env)->GetStringUTFChars(env, s, NULL);
        args[i + 1] = strdup(c);
        (*env)->ReleaseStringUTFChars(env, s, c);
    }
    nargs = n + 1;
    pthread_create(&t, NULL, hilo_servidor, NULL);
    pthread_detach(t);
}
