package dev.ben4shot.glibcprueba;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.util.SparseIntArray;
import android.view.Gravity;
import android.view.KeyCharacterMap;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.ViewConfiguration;
import android.view.WindowInsets;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputMethodManager;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.text.Normalizer;

// Pantalla Wayland: SurfaceView donde el anfitrión dibuja la ventana Linux.
// Tacto: toque = clic, arrastrar = clic sostenido, mantener = clic derecho,
// dos dedos = scroll. Teclado: caracteres -> teclas de la distribución de
// Distribucion.java (latam, generada con xkbcommon; la misma que usa sway).
public class WaylandActivity extends Activity {
    // evdev (linux/input-event-codes.h)
    private static final int SHIFT = 42, CTRL = 29, ALT = 56, ALTGR = 100, SUPER = 125;
    private static final int BTN_IZQ = 0x110, BTN_DER = 0x111;
    private static final int MANTENER_MS = 450;
    // px de dedo -> unidades de scroll de Wayland (una rueda ~ 15)
    private static final float SCROLL = 0.35f;

    private SurfaceView vista;
    private TextView botonCtrl, botonAlt, botonSuper;
    private boolean ctrl, alt, sup;

    // Gesto en curso
    private final Handler handler = new Handler(Looper.getMainLooper());
    private float inicioX, inicioY, ultX, ultY;
    private boolean arrastrando, desplazando, gestoUsado;
    private final Runnable mantener = () -> {
        if (arrastrando || desplazando) return;
        gestoUsado = true;
        Wayland.boton(BTN_DER, true);
        Wayland.boton(BTN_DER, false);
    };

    // Teclas sin carácter: código de Android -> evdev
    private static final SparseIntArray TECLAS = new SparseIntArray();
    // carácter -> evdev | 0x10000 Shift | 0x20000 AltGr
    private static final SparseIntArray CARACTERES = new SparseIntArray();
    // carácter suelto -> su combinante (para escribirlo con tecla muerta + espacio)
    private static final SparseIntArray SUELTOS = new SparseIntArray();

    static {
        for (int i = 0; i + 1 < Distribucion.TABLA.length; i += 2) {
            CARACTERES.put(Distribucion.TABLA[i], Distribucion.TABLA[i + 1]);
        }
        CARACTERES.put('\n', 28);
        CARACTERES.put('\t', 15);
        SUELTOS.put('^', 0x302);
        SUELTOS.put('`', 0x300);
        SUELTOS.put('~', 0x303);
        SUELTOS.put('´', 0x301);
        SUELTOS.put('¨', 0x308);

        int[][] t = {
                {KeyEvent.KEYCODE_ENTER, 28}, {KeyEvent.KEYCODE_NUMPAD_ENTER, 28},
                {KeyEvent.KEYCODE_DEL, 14}, {KeyEvent.KEYCODE_FORWARD_DEL, 111},
                {KeyEvent.KEYCODE_TAB, 15}, {KeyEvent.KEYCODE_ESCAPE, 1},
                {KeyEvent.KEYCODE_DPAD_UP, 103}, {KeyEvent.KEYCODE_DPAD_DOWN, 108},
                {KeyEvent.KEYCODE_DPAD_LEFT, 105}, {KeyEvent.KEYCODE_DPAD_RIGHT, 106},
                {KeyEvent.KEYCODE_SHIFT_LEFT, SHIFT}, {KeyEvent.KEYCODE_SHIFT_RIGHT, 54},
                {KeyEvent.KEYCODE_CTRL_LEFT, CTRL}, {KeyEvent.KEYCODE_CTRL_RIGHT, 97},
                {KeyEvent.KEYCODE_ALT_LEFT, ALT}, {KeyEvent.KEYCODE_ALT_RIGHT, ALTGR},
                {KeyEvent.KEYCODE_META_LEFT, SUPER}, {KeyEvent.KEYCODE_META_RIGHT, 126},
                {KeyEvent.KEYCODE_MOVE_HOME, 102}, {KeyEvent.KEYCODE_MOVE_END, 107},
                {KeyEvent.KEYCODE_PAGE_UP, 104}, {KeyEvent.KEYCODE_PAGE_DOWN, 109},
                {KeyEvent.KEYCODE_INSERT, 110},
        };
        for (int[] p : t) TECLAS.put(p[0], p[1]);
        for (int i = 0; i < 10; i++) TECLAS.put(KeyEvent.KEYCODE_F1 + i, 59 + i);
        TECLAS.put(KeyEvent.KEYCODE_F11, 87);
        TECLAS.put(KeyEvent.KEYCODE_F12, 88);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Wayland.iniciar(this);

        vista = new SurfaceView(this) {
            @Override
            public boolean onCheckIsTextEditor() { return true; }

            @Override
            public InputConnection onCreateInputConnection(EditorInfo info) {
                // TYPE_NULL: el teclado manda eventos de tecla en vez de texto compuesto
                info.inputType = EditorInfo.TYPE_NULL;
                info.imeOptions = EditorInfo.IME_FLAG_NO_FULLSCREEN;
                return new BaseInputConnection(this, false) {
                    @Override
                    public boolean commitText(CharSequence texto, int pos) {
                        escribir(texto);
                        return true;
                    }

                    @Override
                    public boolean deleteSurroundingText(int antes, int despues) {
                        for (int i = 0; i < antes; i++) pulsar(14);
                        return true;
                    }
                };
            }
        };
        vista.setFocusable(true);
        vista.setFocusableInTouchMode(true);
        vista.getHolder().addCallback(new SurfaceHolder.Callback() {
            @Override
            public void surfaceCreated(SurfaceHolder h) { }

            @Override
            public void surfaceChanged(SurfaceHolder h, int formato, int ancho, int alto) {
                DisplayMetrics dm = getResources().getDisplayMetrics();
                Wayland.ventana(h.getSurface(), ancho, alto,
                        Math.round(ancho / dm.xdpi * 25.4f), Math.round(alto / dm.ydpi * 25.4f));
            }

            @Override
            public void surfaceDestroyed(SurfaceHolder h) {
                Wayland.ventana(null, 0, 0, 0, 0);
            }
        });
        vista.setOnTouchListener((v, e) -> {
            tacto(e);
            return true;
        });

        LinearLayout raiz = new LinearLayout(this);
        raiz.setOrientation(LinearLayout.VERTICAL);
        raiz.setBackgroundColor(Color.BLACK);
        raiz.addView(vista, new LinearLayout.LayoutParams(-1, 0, 1));
        raiz.addView(filaTeclas(), new LinearLayout.LayoutParams(-1, -2));
        raiz.setOnApplyWindowInsetsListener((v, insets) -> {
            android.graphics.Insets i = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.ime());
            v.setPadding(i.left, i.top, i.right, i.bottom);
            return WindowInsets.CONSUMED;
        });
        setContentView(raiz);
        vista.requestFocus();
    }

    // --- tacto ---

    private void tacto(MotionEvent e) {
        int slop = ViewConfiguration.get(this).getScaledTouchSlop();
        switch (e.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                inicioX = ultX = e.getX();
                inicioY = ultY = e.getY();
                arrastrando = desplazando = gestoUsado = false;
                Wayland.mover(ultX, ultY);
                handler.postDelayed(mantener, MANTENER_MS);
                break;
            case MotionEvent.ACTION_POINTER_DOWN:
                handler.removeCallbacks(mantener);
                if (arrastrando) Wayland.boton(BTN_IZQ, false);
                arrastrando = false;
                desplazando = true;
                ultX = centroX(e);
                ultY = centroY(e);
                break;
            case MotionEvent.ACTION_MOVE:
                if (desplazando) {
                    float cx = centroX(e), cy = centroY(e);
                    // natural: el dedo sube -> el contenido sube (scroll hacia abajo)
                    Wayland.eje((ultX - cx) * SCROLL, (ultY - cy) * SCROLL);
                    ultX = cx;
                    ultY = cy;
                } else if (!gestoUsado) {
                    if (!arrastrando && Math.hypot(e.getX() - inicioX, e.getY() - inicioY) > slop) {
                        handler.removeCallbacks(mantener);
                        arrastrando = true;
                        Wayland.boton(BTN_IZQ, true);
                    }
                    if (arrastrando) Wayland.mover(e.getX(), e.getY());
                }
                break;
            case MotionEvent.ACTION_UP:
                handler.removeCallbacks(mantener);
                if (arrastrando) {
                    Wayland.boton(BTN_IZQ, false);
                } else if (desplazando) {
                    Wayland.eje(0, 0);
                } else if (!gestoUsado) {
                    Wayland.boton(BTN_IZQ, true);
                    Wayland.boton(BTN_IZQ, false);
                }
                arrastrando = desplazando = false;
                break;
            case MotionEvent.ACTION_CANCEL:
                handler.removeCallbacks(mantener);
                if (arrastrando) Wayland.boton(BTN_IZQ, false);
                if (desplazando) Wayland.eje(0, 0);
                arrastrando = desplazando = false;
                break;
        }
    }

    private static float centroX(MotionEvent e) {
        float s = 0;
        for (int i = 0; i < e.getPointerCount(); i++) s += e.getX(i);
        return s / e.getPointerCount();
    }

    private static float centroY(MotionEvent e) {
        float s = 0;
        for (int i = 0; i < e.getPointerCount(); i++) s += e.getY(i);
        return s / e.getPointerCount();
    }

    // --- fila de teclas ---

    private LinearLayout filaTeclas() {
        LinearLayout fila = new LinearLayout(this);
        fila.setBackgroundColor(0xff1a1a1a);
        String[] teclas = {"⌨", "ESC", "TAB", "CTRL", "ALT", "SUPER", "←", "↓", "↑", "→"};
        for (String t : teclas) {
            TextView b = new TextView(this);
            b.setText(t);
            b.setTextColor(Color.WHITE);
            b.setTypeface(Typeface.MONOSPACE);
            b.setGravity(Gravity.CENTER);
            b.setPadding(0, 24, 0, 24);
            b.setOnClickListener(v -> botonFila(t));
            if (t.equals("CTRL")) botonCtrl = b;
            if (t.equals("ALT")) botonAlt = b;
            if (t.equals("SUPER")) botonSuper = b;
            fila.addView(b, new LinearLayout.LayoutParams(0, -2, 1));
        }
        return fila;
    }

    private void botonFila(String t) {
        switch (t) {
            case "⌨":
                vista.requestFocus();
                getSystemService(InputMethodManager.class).showSoftInput(vista, 0);
                return;
            case "CTRL": ctrl = !ctrl; Wayland.tecla(CTRL, ctrl); marcar(); return;
            case "ALT": alt = !alt; Wayland.tecla(ALT, alt); marcar(); return;
            case "SUPER": sup = !sup; Wayland.tecla(SUPER, sup); marcar(); return;
            case "ESC": pulsar(1); return;
            case "TAB": pulsar(15); return;
            case "←": pulsar(105); return;
            case "↓": pulsar(108); return;
            case "↑": pulsar(103); return;
            case "→": pulsar(106); return;
        }
    }

    private void marcar() {
        botonCtrl.setBackgroundColor(ctrl ? 0xff3d6aa5 : 0);
        botonAlt.setBackgroundColor(alt ? 0xff3d6aa5 : 0);
        botonSuper.setBackgroundColor(sup ? 0xff3d6aa5 : 0);
    }

    // Los modificadores de la fila valen para una sola tecla, como en la terminal.
    private void soltarModificadores() {
        if (ctrl) Wayland.tecla(CTRL, false);
        if (alt) Wayland.tecla(ALT, false);
        if (sup) Wayland.tecla(SUPER, false);
        if (ctrl || alt || sup) {
            ctrl = alt = sup = false;
            marcar();
        }
    }

    // --- teclado ---

    private void pulsar(int codigo) {
        Wayland.tecla(codigo, true);
        Wayland.tecla(codigo, false);
        soltarModificadores();
    }

    // valor de la tabla: evdev | 0x10000 Shift | 0x20000 AltGr
    // Shift del teclado físico apretado (scancode, o 0)
    private int shiftFisico;

    private void pulsarTabla(int v) {
        boolean shift = (v & 0x10000) != 0, altgr = (v & 0x20000) != 0;
        // El carácter manda: Shift/AltGr quedan como pide la tabla durante la tecla
        boolean soltarFisico = shiftFisico != 0 && !shift;
        boolean ponerShift = shift && shiftFisico == 0;
        if (soltarFisico) Wayland.tecla(shiftFisico, false);
        if (ponerShift) Wayland.tecla(SHIFT, true);
        if (altgr) Wayland.tecla(ALTGR, true);
        Wayland.tecla(v & 0xffff, true);
        Wayland.tecla(v & 0xffff, false);
        if (altgr) Wayland.tecla(ALTGR, false);
        if (ponerShift) Wayland.tecla(SHIFT, false);
        if (soltarFisico) Wayland.tecla(shiftFisico, true);
    }

    // Teclado físico (distribución US u otra, la que Android tenga configurada):
    // los caracteres se traducen a latam con la tabla; modificadores y teclas sin
    // carácter van crudas (atajos de sway, flechas...).
    private void teclaFisica(KeyEvent e) {
        boolean abajo = e.getAction() == KeyEvent.ACTION_DOWN;
        int sc = e.getScanCode();
        if (KeyEvent.isModifierKey(e.getKeyCode())) {
            if (sc == SHIFT || sc == 54) shiftFisico = abajo ? sc : 0;
            if (sc == ALTGR) sc = ALT;	// en un teclado US el Alt derecho es Alt, no AltGr
            if (e.getRepeatCount() == 0) Wayland.tecla(sc, abajo);
            return;
        }
        int sinCtrlAlt = e.getMetaState() & ~(KeyEvent.META_CTRL_MASK | KeyEvent.META_ALT_MASK | KeyEvent.META_META_MASK);
        int c = TECLAS.get(e.getKeyCode(), -1) >= 0 ? 0 : e.getUnicodeChar(sinCtrlAlt);
        if (c == 0 || (c & KeyCharacterMap.COMBINING_ACCENT) != 0) {
            // las repeticiones las hace el cliente (repeat_info de sway)
            if (e.getRepeatCount() == 0) Wayland.tecla(sc, abajo);
            return;
        }
        // con carácter: Android ya repite la tecla mantenida
        if (abajo) escribir(new String(Character.toChars(c)));
    }

    private void escribir(CharSequence texto) {
        texto.codePoints().forEach(this::escribirCaracter);
        soltarModificadores();
    }

    private void escribirCaracter(int c) {
        int v = CARACTERES.get(c, -1);
        if (v >= 0) {
            pulsarTabla(v);
            return;
        }
        // ^ ` ~ sueltos: tecla muerta + espacio
        int muerta = CARACTERES.get(SUELTOS.get(c, -1), -1);
        if (muerta >= 0) {
            pulsarTabla(muerta);
            pulsarTabla(CARACTERES.get(' '));
            return;
        }
        // á, ü, ê...: tecla muerta + letra base
        String d = Normalizer.normalize(new String(Character.toChars(c)), Normalizer.Form.NFD);
        if (d.codePointCount(0, d.length()) == 2) {
            int base = d.codePointAt(0), marca = d.codePointAt(Character.charCount(base));
            int vb = CARACTERES.get(base, -1), vm = CARACTERES.get(marca, -1);
            if (vb >= 0 && vm >= 0) {
                pulsarTabla(vm);
                pulsarTabla(vb);
            }
        }
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent e) {
        int k = e.getKeyCode();
        if (k == KeyEvent.KEYCODE_BACK || k == KeyEvent.KEYCODE_VOLUME_UP || k == KeyEvent.KEYCODE_VOLUME_DOWN) {
            return super.dispatchKeyEvent(e);
        }
        boolean abajo = e.getAction() == KeyEvent.ACTION_DOWN;
        // Teclado físico: el scancode es el código evdev
        if (e.getScanCode() > 0 && e.getDevice() != null && !e.getDevice().isVirtual()
                && e.getAction() != KeyEvent.ACTION_MULTIPLE) {
            teclaFisica(e);
            return true;
        }
        if (e.getAction() == KeyEvent.ACTION_MULTIPLE && e.getCharacters() != null) {
            escribir(e.getCharacters());
            return true;
        }
        // Teclado virtual: los modificadores sueltos no se reenvían (el carácter ya
        // trae su Shift/AltGr de la tabla); Ctrl/Alt se toman del estado del evento.
        if (KeyEvent.isModifierKey(k)) return true;
        int codigo = TECLAS.get(k, -1);
        if (codigo >= 0) {
            if (abajo) {
                conModificadores(e, true);
                Wayland.tecla(codigo, true);
                Wayland.tecla(codigo, false);
                conModificadores(e, false);
                soltarModificadores();
            }
            return true;
        }
        int sinCtrlAlt = e.getMetaState() & ~(KeyEvent.META_CTRL_MASK | KeyEvent.META_ALT_MASK | KeyEvent.META_META_MASK);
        int c = e.getUnicodeChar(sinCtrlAlt);
        if (c == 0) return super.dispatchKeyEvent(e);
        if (abajo) {
            conModificadores(e, true);
            escribir(new String(Character.toChars(c)));
            conModificadores(e, false);
        }
        return true;
    }

    // Shift (solo para teclas sin carácter), Ctrl, Alt y Meta del estado del evento.
    private void conModificadores(KeyEvent e, boolean pulsar) {
        if (e.isShiftPressed() && TECLAS.get(e.getKeyCode(), -1) >= 0) Wayland.tecla(SHIFT, pulsar);
        if (e.isCtrlPressed()) Wayland.tecla(CTRL, pulsar);
        if (e.isAltPressed()) Wayland.tecla(ALT, pulsar);
        if (e.isMetaPressed()) Wayland.tecla(SUPER, pulsar);
    }
}
