/* B11: lo que comparten los hilos JNI (Binder) y el hilo del servidor. */
#ifndef ANDROID_X11_H
#define ANDROID_X11_H

struct ANativeWindow;

/* La app escribe mensajes de este tamaño (20 bytes, little endian) en el socket; el servidor los lee en su hilo.
 * Mismo formato en ServicioX11.enviar (Java). */
enum { MSG_TECLA, MSG_MOVER, MSG_BOTON, MSG_EJE };
struct mensaje {
    int tipo;
    int a, b;
    float x, y;
};

extern int android_entrada;     /* socket de la app (SOCK_SEQPACKET), lo lee el servidor */
extern int android_ventanas[2]; /* tubería interna: punteros ANativeWindow* de Binder al servidor */

void androidVentana(struct ANativeWindow *nueva);
int androidAncho(void);
int androidAlto(void);

#endif
