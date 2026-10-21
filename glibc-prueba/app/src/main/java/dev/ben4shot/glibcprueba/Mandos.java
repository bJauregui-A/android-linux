package dev.ben4shot.glibcprueba;

import android.content.Context;
import android.hardware.input.InputManager;
import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.util.Log;
import android.util.SparseIntArray;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;

import android.system.ErrnoException;
import android.system.Os;
import android.system.OsConstants;
import android.system.StructPollfd;

import java.io.File;
import java.io.FileDescriptor;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;

// Mandos Android → Linux. Sin root no hay /dev/input ni uinput: mientras Android tenga un
// mando conectado, aquí se escucha en un socket Unix en el /dev/input del prefijo
// ("event0") y a cada programa que lo abre se le mandan struct input_event (24 bytes).
// La glibc (parche 0013) convierte el open() en connect() y responde los ioctl EVIOC*
// como un mando de Xbox 360 (xpad); por eso los códigos de aquí son los de xpad.
// Lo que el programa escribe (vibración, EV_FF) por ahora se descarta.
class Mandos {
    private static final String TAG = "MANDOS";
    private static final int EV_SYN = 0, EV_KEY = 1, EV_ABS = 3;
    private static final int ABS_X = 0, ABS_Y = 1, ABS_Z = 2, ABS_RX = 3, ABS_RY = 4, ABS_RZ = 5,
            ABS_HAT0X = 0x10, ABS_HAT0Y = 0x11;
    private static final SparseIntArray BOTONES = new SparseIntArray();
    static {
        BOTONES.put(KeyEvent.KEYCODE_BUTTON_A, 0x130);
        BOTONES.put(KeyEvent.KEYCODE_BUTTON_B, 0x131);
        BOTONES.put(KeyEvent.KEYCODE_BUTTON_X, 0x133);
        BOTONES.put(KeyEvent.KEYCODE_BUTTON_Y, 0x134);
        BOTONES.put(KeyEvent.KEYCODE_BUTTON_L1, 0x136);
        BOTONES.put(KeyEvent.KEYCODE_BUTTON_R1, 0x137);
        BOTONES.put(KeyEvent.KEYCODE_BUTTON_SELECT, 0x13a);
        BOTONES.put(KeyEvent.KEYCODE_BUTTON_START, 0x13b);
        BOTONES.put(KeyEvent.KEYCODE_BUTTON_MODE, 0x13c);
        BOTONES.put(KeyEvent.KEYCODE_BUTTON_THUMBL, 0x13d);
        BOTONES.put(KeyEvent.KEYCODE_BUTTON_THUMBR, 0x13e);
    }

    private static File socket;
    private static LocalServerSocket servidor;
    // dueño del descriptor del servidor: si se lo lleva el GC, su finalizador lo cierra
    private static LocalSocket enlazado;
    // descriptores no bloqueantes: un programa que abre el mando y no lee no frena a los demás
    // (como evdev: si su cola se llena, pierde eventos)
    private static final List<FileDescriptor> clientes = new ArrayList<>();
    private static Handler envio;
    // último valor mandado de cada eje (no repetir los que no cambian)
    private static final SparseIntArray ejes = new SparseIntArray();
    // la cruceta como teclas (algunos mandos no mandan HAT_X/HAT_Y)
    private static int cruzX, cruzY;

    static synchronized void iniciar(Context c) {
        if (envio != null) return;
        socket = new File(SistemaLinux.raizSeleccionada(c), "dev/input/event0");
        HandlerThread h = new HandlerThread("mandos");
        h.start();
        envio = new Handler(h.getLooper());
        InputManager im = c.getSystemService(InputManager.class);
        im.registerInputDeviceListener(new InputManager.InputDeviceListener() {
            public void onInputDeviceAdded(int id) { revisar(); }
            public void onInputDeviceRemoved(int id) { revisar(); }
            public void onInputDeviceChanged(int id) { revisar(); }
        }, new Handler(Looper.getMainLooper()));
        revisar();
    }

    static boolean esMando(InputDevice d) {
        if (d == null || d.isVirtual()) return false;
        int s = d.getSources();
        return (s & InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD
                || (s & InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK;
    }

    // Abre o cierra el socket según haya o no un mando conectado.
    private static void revisar() {
        boolean hay = false;
        for (int id : InputDevice.getDeviceIds()) hay |= esMando(InputDevice.getDevice(id));
        boolean fHay = hay;
        envio.post(() -> { if (fHay) abrir(); else cerrar(); });
    }

    private static void abrir() {
        if (servidor != null) return;
        try {
            socket.getParentFile().mkdirs();
            socket.delete();
            enlazado = new LocalSocket(LocalSocket.SOCKET_STREAM);
            enlazado.bind(new LocalSocketAddress(socket.getPath(), LocalSocketAddress.Namespace.FILESYSTEM));
            servidor = new LocalServerSocket(enlazado.getFileDescriptor());
            LocalServerSocket srv = servidor;
            new Thread(() -> aceptar(srv), "mandos-aceptar").start();
            Log.i(TAG, "mando conectado: " + socket);
        } catch (Exception e) {
            Log.e(TAG, "abrir", e);
        }
    }

    private static void cerrar() {
        if (servidor == null) return;
        socket.delete();
        try { servidor.close(); } catch (Exception ignored) { }
        try { enlazado.close(); } catch (Exception ignored) { }
        servidor = null;
        enlazado = null;
        synchronized (clientes) {
            for (FileDescriptor f : clientes) try { Os.shutdown(f, OsConstants.SHUT_RDWR); } catch (Exception ignored) { }
            clientes.clear();
        }
        Log.i(TAG, "sin mando");
    }

    private static void aceptar(LocalServerSocket srv) {
        while (srv == servidor) {
            try {
                LocalSocket c = srv.accept();
                FileDescriptor fd = c.getFileDescriptor();
                Os.fcntlInt(fd, OsConstants.F_SETFL, Os.fcntlInt(fd, OsConstants.F_GETFL, 0) | OsConstants.O_NONBLOCK);
                int pid = c.getPeerCredentials().getPid();
                Log.i(TAG, "abierto por pid " + pid);
                synchronized (clientes) { clientes.add(fd); }
                InputStream in = new java.io.FileInputStream(fd);
                // vibración y demás escrituras del programa: se descartan; fin = cerró
                new Thread(() -> {
                    byte[] b = new byte[256];
                    StructPollfd p = new StructPollfd();
                    p.fd = fd;
                    p.events = (short) OsConstants.POLLIN;
                    try {
                        while (true) {
                            Os.poll(new StructPollfd[]{p}, -1);
                            if (Os.read(fd, b, 0, b.length) <= 0) break;
                        }
                    } catch (Exception ignored) { }
                    synchronized (clientes) { clientes.remove(fd); }
                    Log.i(TAG, "cerrado por pid " + pid);
                    try { c.close(); } catch (Exception ignored) { }
                }, "mandos-cliente").start();
            } catch (Exception e) {
                if (srv == servidor) Log.w(TAG, "accept", e);
                return;
            }
        }
    }

    // --- desde WaylandActivity (hilo de la interfaz) ---

    static boolean tecla(KeyEvent e) {
        if (!esMando(e.getDevice())) return false;
        boolean abajo = e.getAction() == KeyEvent.ACTION_DOWN;
        if (e.getAction() == KeyEvent.ACTION_MULTIPLE) return true;
        if (abajo && e.getRepeatCount() > 0) return true;
        int k = e.getKeyCode();
        int b = BOTONES.get(k, -1);
        if (b >= 0) {
            mandar(new int[]{EV_KEY, b, abajo ? 1 : 0});
            return true;
        }
        switch (k) {
            // gatillos como botón (si el mando también los manda como eje, gana el eje)
            case KeyEvent.KEYCODE_BUTTON_L2: eje(ABS_Z, abajo ? 255 : 0); return true;
            case KeyEvent.KEYCODE_BUTTON_R2: eje(ABS_RZ, abajo ? 255 : 0); return true;
            case KeyEvent.KEYCODE_DPAD_LEFT: cruzX = abajo ? -1 : (cruzX == -1 ? 0 : cruzX); eje(ABS_HAT0X, cruzX); return true;
            case KeyEvent.KEYCODE_DPAD_RIGHT: cruzX = abajo ? 1 : (cruzX == 1 ? 0 : cruzX); eje(ABS_HAT0X, cruzX); return true;
            case KeyEvent.KEYCODE_DPAD_UP: cruzY = abajo ? -1 : (cruzY == -1 ? 0 : cruzY); eje(ABS_HAT0Y, cruzY); return true;
            case KeyEvent.KEYCODE_DPAD_DOWN: cruzY = abajo ? 1 : (cruzY == 1 ? 0 : cruzY); eje(ABS_HAT0Y, cruzY); return true;
        }
        // otros botones del mando (BACK que algunos mandan para Select, etc.): no al teclado
        return KeyEvent.isGamepadButton(k);
    }

    static boolean movimiento(MotionEvent e) {
        if ((e.getSource() & InputDevice.SOURCE_JOYSTICK) != InputDevice.SOURCE_JOYSTICK
                || e.getAction() != MotionEvent.ACTION_MOVE || !esMando(e.getDevice())) return false;
        List<Integer> ev = new ArrayList<>();
        palanca(ev, ABS_X, e.getAxisValue(MotionEvent.AXIS_X));
        palanca(ev, ABS_Y, e.getAxisValue(MotionEvent.AXIS_Y));
        palanca(ev, ABS_RX, e.getAxisValue(MotionEvent.AXIS_Z));
        palanca(ev, ABS_RY, e.getAxisValue(MotionEvent.AXIS_RZ));
        gatillo(ev, ABS_Z, Math.max(e.getAxisValue(MotionEvent.AXIS_LTRIGGER), e.getAxisValue(MotionEvent.AXIS_BRAKE)));
        gatillo(ev, ABS_RZ, Math.max(e.getAxisValue(MotionEvent.AXIS_RTRIGGER), e.getAxisValue(MotionEvent.AXIS_GAS)));
        InputDevice d = e.getDevice();
        if (d.getMotionRange(MotionEvent.AXIS_HAT_X) != null) {
            agregar(ev, ABS_HAT0X, Math.round(e.getAxisValue(MotionEvent.AXIS_HAT_X)));
            agregar(ev, ABS_HAT0Y, Math.round(e.getAxisValue(MotionEvent.AXIS_HAT_Y)));
        }
        if (!ev.isEmpty()) {
            int[] a = new int[ev.size()];
            for (int i = 0; i < a.length; i++) a[i] = ev.get(i);
            mandar(a);
        }
        return true;
    }

    // Al perder el foco: soltar todo (si no, un botón queda apretado en el juego).
    static void soltarTodo() {
        List<Integer> ev = new ArrayList<>();
        for (int i = 0; i < BOTONES.size(); i++) { ev.add(EV_KEY); ev.add(BOTONES.valueAt(i)); ev.add(0); }
        for (int a : new int[]{ABS_X, ABS_Y, ABS_Z, ABS_RX, ABS_RY, ABS_RZ, ABS_HAT0X, ABS_HAT0Y}) agregar(ev, a, 0);
        cruzX = cruzY = 0;
        int[] arr = new int[ev.size()];
        for (int i = 0; i < arr.length; i++) arr[i] = ev.get(i);
        mandar(arr);
    }

    private static void palanca(List<Integer> ev, int abs, float v) {
        agregar(ev, abs, Math.max(-32768, Math.min(32767, Math.round(v * 32767))));
    }

    private static void gatillo(List<Integer> ev, int abs, float v) {
        agregar(ev, abs, Math.max(0, Math.min(255, Math.round(v * 255))));
    }

    private static void eje(int abs, int v) {
        List<Integer> ev = new ArrayList<>();
        agregar(ev, abs, v);
        if (!ev.isEmpty()) mandar(new int[]{ev.get(0), ev.get(1), ev.get(2)});
    }

    private static void agregar(List<Integer> ev, int abs, int v) {
        if (ejes.get(abs, Integer.MIN_VALUE) == v) return;
        ejes.put(abs, v);
        ev.add(EV_ABS); ev.add(abs); ev.add(v);
    }

    // tríos (tipo, código, valor) + SYN_REPORT, a todos los programas que tengan el mando abierto
    private static void mandar(int[] t) {
        Handler h = envio;
        if (h == null) return;
        h.post(() -> {
            synchronized (clientes) {
                if (clientes.isEmpty()) return;
            }
            long us = System.nanoTime() / 1000;
            ByteBuffer b = ByteBuffer.allocate((t.length / 3 + 1) * 24).order(ByteOrder.LITTLE_ENDIAN);
            for (int i = 0; i + 2 < t.length; i += 3) evento(b, us, t[i], t[i + 1], t[i + 2]);
            evento(b, us, EV_SYN, 0, 0);
            synchronized (clientes) {
                for (int i = clientes.size() - 1; i >= 0; i--) {
                    try {
                        // a medias desalinearía los input_event: mejor cerrarle el mando
                        if (Os.write(clientes.get(i), b.array(), 0, b.position()) < b.position()) {
                            Os.shutdown(clientes.get(i), OsConstants.SHUT_RDWR);
                            clientes.remove(i);
                        }
                    }
                    catch (ErrnoException e) {
                        if (e.errno != OsConstants.EAGAIN) clientes.remove(i);
                    }
                    catch (Exception e) { clientes.remove(i); }
                }
            }
        });
    }

    private static void evento(ByteBuffer b, long us, int tipo, int codigo, int valor) {
        b.putLong(us / 1000000).putLong(us % 1000000)
                .putShort((short) tipo).putShort((short) codigo).putInt(valor);
    }
}
