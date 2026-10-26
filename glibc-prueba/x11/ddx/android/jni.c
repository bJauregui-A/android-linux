/* B11: arranque JNI del servidor X11 en el proceso :x11. La entrada (teclas, puntero) llega por un socket
 * que la app le pasa a ServicioX11; Binder solo sirve para conectar y para entregar la Surface. */
#include <jni.h>
#include <android/native_window_jni.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "android.h"

int dix_main(int argc, char *argv[], char *envp[]);
extern char **environ;
extern const char *XkbBinDirectory;

int android_entrada = -1;
int android_ventanas[2] = { -1, -1 };

static char **args;
static int nargs;

static void *hilo_servidor(void *p)
{
    dix_main(nargs, args, environ);
    return NULL;
}

/* iniciar(String[] argumentos, int entrada): arranca el bucle del servidor en un hilo propio.
 * "entrada" es el extremo del servidor del socketpair (el servidor lo cierra al terminar). */
JNIEXPORT void JNICALL
Java_dev_ben4shot_glibcprueba_ServicioX11_iniciar(JNIEnv *env, jclass cls, jobjectArray argumentos, jint entrada)
{
    pthread_t t;
    int i, n = (*env)->GetArrayLength(env, argumentos);

    /* el servidor ejecuta <XkbBinDirectory>/xkbcomp: la app deja ahí un enlace a libxkbcomp.so */
    if (getenv("X11_XKB_BIN"))
        XkbBinDirectory = strdup(getenv("X11_XKB_BIN"));
    /* el stderr del proceso :x11 no va a ningún lado: lo que diga el servidor queda en X11_LOG */
    if (getenv("X11_LOG")) {
        int f = open(getenv("X11_LOG"), O_WRONLY | O_CREAT | O_TRUNC, 0600);

        if (f >= 0) {
            dup2(f, 2);
            dup2(f, 1);
            close(f);
        }
    }
    if (pipe(android_ventanas) != 0)
        return;
    fcntl(android_ventanas[0], F_SETFL, O_NONBLOCK);
    android_entrada = entrada;
    fcntl(android_entrada, F_SETFL, O_NONBLOCK);

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

/* ventana(Surface s): null = la ventana se fue. El servidor suelta la anterior. */
JNIEXPORT void JNICALL
Java_dev_ben4shot_glibcprueba_ServicioX11_ventana(JNIEnv *env, jclass cls, jobject surface)
{
    struct ANativeWindow *w = surface ? ANativeWindow_fromSurface(env, surface) : NULL;

    if (android_ventanas[1] >= 0)
        (void) write(android_ventanas[1], &w, sizeof(w));
}
