/*

Copyright 1993, 1998  The Open Group

Permission to use, copy, modify, distribute, and sell this software and its
documentation for any purpose is hereby granted without fee, provided that
the above copyright notice appear in all copies and that both that
copyright notice and this permission notice appear in supporting
documentation.

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE OPEN GROUP BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

Except as contained in this notice, the name of The Open Group shall
not be used in advertising or otherwise to promote the sale, use or
other dealings in this Software without prior written authorization
from The Open Group.

*/

#ifdef HAVE_DIX_CONFIG_H
#include <dix-config.h>
#endif

#include <X11/X.h>
#include "mi.h"
#include <X11/Xproto.h>
#include "scrnintstr.h"
#include "inputstr.h"
#include <X11/Xos.h>
#include "mipointer.h"
#include "xkbsrv.h"
#include <X11/keysym.h>
#include "xserver-properties.h"
#include "exevents.h"
#include "extinit.h"
#include "android.h"
#include <unistd.h>
#include <android/native_window.h>

static DeviceIntPtr teclado, puntero;
static ValuatorMask *mask;     /* opaca: se reserva una vez y se reutiliza */

void
ProcessInputEvents(void)
{
    mieqProcessInputEvents();
}

void
DDXRingBell(int volume, int pitch, int duration)
{
}

#define VFB_MIN_KEY 8
#define VFB_MAX_KEY 255

static int
vfbKeybdProc(DeviceIntPtr pDevice, int onoff)
{
    DevicePtr pDev = (DevicePtr) pDevice;

    switch (onoff) {
    case DEVICE_INIT:
        {
        /* latam, igual que en Wayland; los mapas salen de -xkbdir (assets del APK) */
        XkbRMLVOSet rmlvo = { "evdev", "pc105", "latam", "", "" };

        InitKeyboardDeviceStruct(pDevice, &rmlvo, NULL, NULL);
    }
        break;
    case DEVICE_ON:
        pDev->on = TRUE;
        break;
    case DEVICE_OFF:
        pDev->on = FALSE;
        break;
    case DEVICE_CLOSE:
        break;
    }
    return Success;
}

static int
vfbMouseProc(DeviceIntPtr pDevice, int onoff)
{
#define NBUTTONS 7
#define NAXES 2

    BYTE map[NBUTTONS + 1];
    DevicePtr pDev = (DevicePtr) pDevice;
    Atom btn_labels[NBUTTONS] = { 0 };
    Atom axes_labels[NAXES] = { 0 };

    switch (onoff) {
    case DEVICE_INIT:
        map[1] = 1;
        map[2] = 2;
        map[3] = 3;
        map[4] = 4;     /* rueda: 4 arriba, 5 abajo, 6 izquierda, 7 derecha */
        map[5] = 5;
        map[6] = 6;
        map[7] = 7;

        btn_labels[0] = XIGetKnownProperty(BTN_LABEL_PROP_BTN_LEFT);
        btn_labels[1] = XIGetKnownProperty(BTN_LABEL_PROP_BTN_MIDDLE);
        btn_labels[2] = XIGetKnownProperty(BTN_LABEL_PROP_BTN_RIGHT);
        btn_labels[3] = XIGetKnownProperty(BTN_LABEL_PROP_BTN_WHEEL_UP);
        btn_labels[4] = XIGetKnownProperty(BTN_LABEL_PROP_BTN_WHEEL_DOWN);
        btn_labels[5] = XIGetKnownProperty(BTN_LABEL_PROP_BTN_HWHEEL_LEFT);
        btn_labels[6] = XIGetKnownProperty(BTN_LABEL_PROP_BTN_HWHEEL_RIGHT);

        axes_labels[0] = XIGetKnownProperty(AXIS_LABEL_PROP_ABS_X);
        axes_labels[1] = XIGetKnownProperty(AXIS_LABEL_PROP_ABS_Y);

        InitPointerDeviceStruct(pDev, map, NBUTTONS, btn_labels,
                                (PtrCtrlProcPtr) NoopDDA,
                                GetMotionHistorySize(), NAXES, axes_labels);
        /* puntero absoluto: Android manda coordenadas de pantalla, no movimientos */
        InitValuatorAxisStruct(pDevice, 0, axes_labels[0], 0, androidAncho() - 1, 10000, 0, 10000, Absolute);
        InitValuatorAxisStruct(pDevice, 1, axes_labels[1], 0, androidAlto() - 1, 10000, 0, 10000, Absolute);
        break;

    case DEVICE_ON:
        pDev->on = TRUE;
        break;

    case DEVICE_OFF:
        pDev->on = FALSE;
        break;

    case DEVICE_CLOSE:
        break;
    }
    return Success;

#undef NBUTTONS
#undef NAXES
}

/* Rueda: la vista manda unidades de Wayland; cada PASO_RUEDA acumulado es un clic de botón 4-7. */
#define PASO_RUEDA 10.0f

static void
clic(int boton)
{
    valuator_mask_zero(mask);
    QueuePointerEvents(puntero, ButtonPress, boton, 0, mask);
    QueuePointerEvents(puntero, ButtonRelease, boton, 0, mask);
}

static void
rueda(float dx, float dy)
{
    static float ax, ay;

    if (dx == 0 && dy == 0) {
        ax = ay = 0;
        return;
    }
    ax += dx;
    ay += dy;
    for (; ay >= PASO_RUEDA; ay -= PASO_RUEDA)
        clic(5);
    for (; ay <= -PASO_RUEDA; ay += PASO_RUEDA)
        clic(4);
    for (; ax >= PASO_RUEDA; ax -= PASO_RUEDA)
        clic(7);
    for (; ax <= -PASO_RUEDA; ax += PASO_RUEDA)
        clic(6);
}

static void
procesar(const struct mensaje *m)
{

    switch (m->tipo) {
    case MSG_TECLA:
        /* evdev + 8 = keycode X */
        QueueKeyboardEvents(teclado, m->b ? KeyPress : KeyRelease, m->a + 8);
        break;
    case MSG_MOVER:
        valuator_mask_set_range(mask, 0, 2, (const int[]) { (int) m->x, (int) m->y });
        QueuePointerEvents(puntero, MotionNotify, 0, POINTER_ABSOLUTE | POINTER_SCREEN, mask);
        break;
    case MSG_BOTON:
        /* BTN_LEFT 0x110, BTN_RIGHT 0x111, BTN_MIDDLE 0x112 -> botones X 1, 3, 2 */
        {
            static const int x11[] = { 1, 3, 2 };
            int i = m->a - 0x110;

            if (i >= 0 && i < 3) {
                valuator_mask_zero(mask);
                QueuePointerEvents(puntero, m->b ? ButtonPress : ButtonRelease, x11[i], 0, mask);
            }
        }
        break;
    case MSG_EJE:
        rueda(m->x, m->y);
        break;
    }
}

static void
leerEntrada(int fd, int ready, void *data)
{
    struct mensaje m;
    ssize_t n;

    while ((n = read(fd, &m, sizeof(m))) == sizeof(m))
        procesar(&m);
    if (n == 0)                 /* la app cerró su extremo: no habrá más entrada */
        RemoveNotifyFd(fd);
}

static void
leerVentanas(int fd, int ready, void *data)
{
    struct ANativeWindow *w;

    while (read(fd, &w, sizeof(w)) == sizeof(w))
        androidVentana(w);
}

void
InitInput(int argc, char *argv[])
{
    DeviceIntPtr p, k;
    Atom xiclass;

    p = AddInputDevice(serverClient, vfbMouseProc, TRUE);
    k = AddInputDevice(serverClient, vfbKeybdProc, TRUE);
    xiclass = MakeAtom(XI_MOUSE, sizeof(XI_MOUSE) - 1, TRUE);
    AssignTypeAndName(p, xiclass, "Xvfb mouse");
    xiclass = MakeAtom(XI_KEYBOARD, sizeof(XI_KEYBOARD) - 1, TRUE);
    AssignTypeAndName(k, xiclass, "Xvfb keyboard");
    mask = valuator_mask_new(2);
    teclado = k;
    puntero = p;
    (void) mieqInit();
    SetNotifyFd(android_entrada, leerEntrada, X_NOTIFY_READ, NULL);
    SetNotifyFd(android_ventanas[0], leerVentanas, X_NOTIFY_READ, NULL);
}

void
CloseInput(void)
{
    RemoveNotifyFd(android_entrada);
    RemoveNotifyFd(android_ventanas[0]);
    mieqFini();
}
