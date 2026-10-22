package dev.ben4shot.glibcprueba;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.ShortcutInfo;
import android.content.pm.ShortcutManager;
import android.graphics.drawable.Icon;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
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
import android.view.View;
import android.view.ViewConfiguration;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputMethodManager;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.text.Normalizer;
import java.util.HashSet;
import java.util.List;

// Pantalla Wayland: SurfaceView donde el anfitrión dibuja la ventana Linux.
// Tacto: toque = clic, arrastrar = clic sostenido, mantener = clic derecho,
// dos dedos = scroll, tres o más = deslizar (gesto de sway: cambiar de escritorio). Teclado: caracteres -> teclas de la distribución de
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
    private View contenedorControles;
    private View barraTeclas;
    private View botonAlternar;
    private int altoIme = 0;

    // Gesto en curso
    private final Handler handler = new Handler(Looper.getMainLooper());
    private float inicioX, inicioY, ultX, ultY;
    private boolean arrastrando, desplazando, deslizando, gestoUsado;
    // Al levantar o poner un dedo el centro salta: el siguiente MOVE solo lo toma
    private boolean recentrar;
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

    // tocar una notificación de Linux (Notificar) con el escritorio ya abierto
    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        Notificar.clic(intent);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // Primera vez (APK autoinstalable): la terminal con el instalador; al terminar vuelve aquí
        AdaptadorInstalacion instalacion = SistemaLinux.adaptadorSeleccionado(this);
        if (!instalacion.instalada(this) && instalacion.instaladorDisponible(this)) {
            startActivity(new Intent(this, TerminalActivity.class));
            finish();
            return;
        }
        // Si el entorno seleccionado es sin-entorno, redirigir directamente a la terminal interactiva
        java.io.File fEsc = new java.io.File(SistemaLinux.raizSeleccionada(this), "var/lib/arch-android/escritorio");
        try {
            if (fEsc.exists() && "sin-entorno".equals(java.nio.file.Files.readString(fEsc.toPath()).trim())) {
                startActivity(new Intent(this, TerminalActivity.class));
                finish();
                return;
            }
        } catch (Exception ignorada) { }
        Wayland.iniciar(this);
        // El escritorio elegido arranca solo si aún no está corriendo.
        startForegroundService(new Intent(this, TerminalService.class).setAction(TerminalService.INICIAR_ESCRITORIO));
        atajoTerminal();
        Notificar.clic(getIntent());

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
                startService(new Intent(WaylandActivity.this, TerminalService.class)
                        .setAction(TerminalService.REAJUSTAR_PANTALLA));
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

        FrameLayout raiz = new FrameLayout(this);
        raiz.setBackgroundColor(Color.BLACK);
        raiz.addView(vista, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));

        contenedorControles = crearControlesFlotantes();
        FrameLayout.LayoutParams paramsControles = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT);
        paramsControles.gravity = Gravity.BOTTOM;
        raiz.addView(contenedorControles, paramsControles);

        raiz.setOnApplyWindowInsetsListener((v, insets) -> {
            android.graphics.Insets ime = insets.getInsets(WindowInsets.Type.ime());
            altoIme = ime.bottom;
            contenedorControles.setTranslationY(-altoIme);
            if (altoIme > 0) {
                mostrarBarra(true);
            }
            return WindowInsets.CONSUMED;
        });
        setContentView(raiz);
        inmersivo();
        vista.requestFocus();
    }

    // Pantalla completa: sin barras de Android (se asoman deslizando desde el borde) y
    // también bajo el recorte de la cámara, así sway recibe los 1080×2340 del panel.
    private void inmersivo() {
        getWindow().getAttributes().layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS;
        WindowInsetsController c = getWindow().getInsetsController();
        if (c == null) return;
        c.hide(WindowInsets.Type.systemBars());
        c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
    }

    @Override
    protected void onResume() {
        super.onResume();
        inmersivo();
        reconectarVentana();
    }

    private void reconectarVentana() {
        if (vista != null && vista.getHolder() != null && vista.getHolder().getSurface() != null
                && vista.getHolder().getSurface().isValid()) {
            int ancho = vista.getWidth();
            int alto = vista.getHeight();
            if (ancho > 0 && alto > 0) {
                DisplayMetrics dm = getResources().getDisplayMetrics();
                Wayland.ventana(vista.getHolder().getSurface(), ancho, alto,
                        Math.round(ancho / dm.xdpi * 25.4f), Math.round(alto / dm.ydpi * 25.4f));
                startService(new Intent(this, TerminalService.class)
                        .setAction(TerminalService.REAJUSTAR_PANTALLA));
            }
        }
    }

    @Override
    public void onWindowFocusChanged(boolean foco) {
        super.onWindowFocusChanged(foco);
        if (foco) {
            inmersivo();
            reconectarVentana();
        }
        Portapapeles.foco(this, foco);
        if (!foco) Mandos.soltarTodo();
    }

    // Mandos: van a Linux como /dev/input/event0 (Mandos.java), no como teclado ni mouse.
    @Override
    public boolean dispatchGenericMotionEvent(MotionEvent e) {
        return Mandos.movimiento(e) || super.dispatchGenericMotionEvent(e);
    }

    // --- tacto ---

    private void tacto(MotionEvent e) {
        int slop = ViewConfiguration.get(this).getScaledTouchSlop();
        switch (e.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                inicioX = ultX = e.getX();
                inicioY = ultY = e.getY();
                arrastrando = desplazando = deslizando = recentrar = gestoUsado = false;
                Wayland.mover(ultX, ultY);
                handler.postDelayed(mantener, MANTENER_MS);
                break;
            case MotionEvent.ACTION_POINTER_DOWN:
                handler.removeCallbacks(mantener);
                if (arrastrando) Wayland.boton(BTN_IZQ, false);
                arrastrando = false;
                if (e.getPointerCount() >= 3 && !deslizando) {
                    if (desplazando) Wayland.eje(0, 0);
                    desplazando = false;
                    deslizando = true;
                    Wayland.gesto(0, e.getPointerCount(), 0, 0);
                } else if (!deslizando) {
                    desplazando = true;
                }
                recentrar = true;
                break;
            case MotionEvent.ACTION_POINTER_UP:
                recentrar = true;
                break;
            case MotionEvent.ACTION_MOVE:
                if (desplazando || deslizando) {
                    float cx = centroX(e), cy = centroY(e);
                    if (recentrar) {
                        recentrar = false;
                    } else if (deslizando) {
                        Wayland.gesto(1, 0, cx - ultX, cy - ultY);
                    } else {
                        // natural: el dedo sube -> el contenido sube (scroll hacia abajo)
                        Wayland.eje((ultX - cx) * SCROLL, (ultY - cy) * SCROLL);
                    }
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
                } else if (deslizando) {
                    Wayland.gesto(2, 0, 0, 0);
                } else if (desplazando) {
                    Wayland.eje(0, 0);
                } else if (!gestoUsado) {
                    Wayland.boton(BTN_IZQ, true);
                    Wayland.boton(BTN_IZQ, false);
                }
                arrastrando = desplazando = deslizando = false;
                break;
            case MotionEvent.ACTION_CANCEL:
                handler.removeCallbacks(mantener);
                if (arrastrando) Wayland.boton(BTN_IZQ, false);
                if (desplazando) Wayland.eje(0, 0);
                if (deslizando) Wayland.gesto(3, 0, 0, 0);
                arrastrando = desplazando = deslizando = false;
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

    // --- controles flotantes y fila de teclas ---

    private View crearControlesFlotantes() {
        FrameLayout contenedor = new FrameLayout(this);
        contenedor.setClipChildren(false);
        contenedor.setClipToPadding(false);

        // 1. Botón flotante discreto (FAB) para reabrir la barra cuando está minimizada
        TextView fab = new TextView(this);
        fab.setText("⌨");
        fab.setTextSize(18);
        fab.setTextColor(Color.WHITE);
        fab.setGravity(Gravity.CENTER);
        fab.setBackground(crearFondo(0xbb0f172a, 0x6638bdf8, dp(20), dp(1)));
        fab.setElevation(dp(6));
        fab.setClickable(true);
        FrameLayout.LayoutParams lpFab = new FrameLayout.LayoutParams(dp(40), dp(40));
        lpFab.gravity = Gravity.BOTTOM | Gravity.END;
        lpFab.rightMargin = dp(16);
        lpFab.bottomMargin = dp(16);
        fab.setLayoutParams(lpFab);
        fab.setVisibility(View.GONE);
        fab.setOnClickListener(v -> mostrarBarra(true));
        botonAlternar = fab;
        contenedor.addView(fab);

        // 2. Barra flotante tipo "Pill"
        FrameLayout marcoBarra = new FrameLayout(this);
        marcoBarra.setBackground(crearFondo(0xee0f172a, 0x4438bdf8, dp(16), dp(1)));
        marcoBarra.setElevation(dp(8));
        marcoBarra.setPadding(dp(6), dp(5), dp(6), dp(5));
        FrameLayout.LayoutParams lpMarco = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT);
        lpMarco.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
        lpMarco.bottomMargin = dp(12);
        lpMarco.leftMargin = dp(10);
        lpMarco.rightMargin = dp(10);
        marcoBarra.setLayoutParams(lpMarco);

        HorizontalScrollView scroll = new HorizontalScrollView(this);
        scroll.setFillViewport(false);
        scroll.setHorizontalScrollBarEnabled(false);
        scroll.setOverScrollMode(View.OVER_SCROLL_NEVER);

        LinearLayout fila = new LinearLayout(this);
        fila.setOrientation(LinearLayout.HORIZONTAL);
        fila.setGravity(Gravity.CENTER_VERTICAL);

        String[] teclas = {"⌨", "⛶", "ESC", "TAB", "CTRL", "ALT", "SUPER", "←", "↓", "↑", "→", "SALIR", "▼"};
        for (String t : teclas) {
            TextView b = new TextView(this);
            b.setText(t);
            b.setSingleLine(true);
            b.setGravity(Gravity.CENTER);
            b.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
            b.setTextSize(12);
            b.setPadding(dp(12), dp(7), dp(12), dp(7));

            if (t.equals("SALIR")) {
                b.setTextColor(0xffff6b6b);
                b.setBackground(crearFondo(0xff2a1616, 0x66ff6b6b, dp(8), dp(1)));
            } else if (t.equals("▼")) {
                b.setTextColor(0xff94a3b8);
                b.setBackground(crearFondo(0xff16202c, 0x33ffffff, dp(8), dp(1)));
            } else {
                b.setTextColor(0xfff8fafc);
                b.setBackground(crearFondo(0xff1e293b, 0x22ffffff, dp(8), dp(1)));
            }

            if (t.equals("CTRL")) botonCtrl = b;
            if (t.equals("ALT")) botonAlt = b;
            if (t.equals("SUPER")) botonSuper = b;

            b.setOnClickListener(v -> botonFila(t));

            LinearLayout.LayoutParams lpBtn = new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            lpBtn.rightMargin = dp(4);
            fila.addView(b, lpBtn);
        }

        scroll.addView(fila, new FrameLayout.LayoutParams(-2, -2));
        marcoBarra.addView(scroll, new FrameLayout.LayoutParams(-2, -2));
        barraTeclas = marcoBarra;
        contenedor.addView(marcoBarra);

        return contenedor;
    }

    private void mostrarBarra(boolean mostrar) {
        if (barraTeclas != null && botonAlternar != null) {
            barraTeclas.setVisibility(mostrar ? View.VISIBLE : View.GONE);
            botonAlternar.setVisibility(mostrar ? View.GONE : View.VISIBLE);
        }
    }

    private void botonFila(String t) {
        switch (t) {
            case "⌨":
                vista.requestFocus();
                getSystemService(InputMethodManager.class).showSoftInput(vista, 0);
                return;
            case "⛶":
                reajustar();
                return;
            case "SALIR":
                mostrarMenuSalida();
                return;
            case "▼":
                mostrarBarra(false);
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

    private void mostrarMenuSalida() {
        SistemaLinux.Instancia inst = SistemaLinux.instanciaSeleccionada(this);
        String nombre = inst != null ? inst.nombre : "Linux";
        new AlertDialog.Builder(this)
                .setTitle("✦ Menú de Sesión (" + nombre + ")")
                .setMessage("¿Deseas salir de la pantalla manteniendo la sesión abierta en segundo plano, o cerrar la sesión por completo?")
                .setPositiveButton("Salir (mantener en fondo)", (d, w) -> {
                    finish();
                })
                .setNegativeButton("✕ Cerrar sesión", (d, w) -> {
                    Wayland.ventana(null, 0, 0, 0, 0);
                    startService(new Intent(this, TerminalService.class).setAction(TerminalService.CERRAR_SESION));
                    finish();
                })
                .setNeutralButton("Cancelar", null)
                .show();
    }

    private void reajustar() {
        inmersivo();
        if (vista != null && vista.getHolder().getSurface() != null) {
            android.view.View padre = (android.view.View) vista.getParent();
            int ancho = padre != null && padre.getWidth() > 0 ? padre.getWidth() : vista.getWidth();
            int altoPadre = padre != null && padre.getHeight() > 0 ? padre.getHeight() : vista.getHeight();
            WindowInsets insets = vista.getRootWindowInsets();
            if (insets != null) {
                altoIme = insets.getInsets(WindowInsets.Type.ime()).bottom;
            }
            int alto = altoPadre;
            FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) vista.getLayoutParams();
            if (altoIme > 0) {
                int barraH = (barraTeclas != null && barraTeclas.getVisibility() == View.VISIBLE) ? barraTeclas.getHeight() : 0;
                alto = Math.max(200, altoPadre - altoIme - barraH);
                if (lp.height != alto) {
                    lp.height = alto;
                    lp.gravity = Gravity.TOP;
                    vista.setLayoutParams(lp);
                }
            } else {
                if (lp.height != FrameLayout.LayoutParams.MATCH_PARENT) {
                    lp.height = FrameLayout.LayoutParams.MATCH_PARENT;
                    lp.gravity = Gravity.NO_GRAVITY;
                    vista.setLayoutParams(lp);
                }
            }
            if (ancho > 0 && alto > 0) {
                DisplayMetrics dm = getResources().getDisplayMetrics();
                Wayland.ventana(vista.getHolder().getSurface(), ancho, alto,
                        Math.round(ancho / dm.xdpi * 25.4f), Math.round(alto / dm.ydpi * 25.4f));
            }
        }
        startService(new Intent(this, TerminalService.class)
                .setAction(TerminalService.REAJUSTAR_PANTALLA));
    }

    private void marcar() {
        if (botonCtrl != null) {
            botonCtrl.setBackground(crearFondo(ctrl ? 0xff0284c7 : 0xff1e293b, ctrl ? 0xff38bdf8 : 0x22ffffff, dp(8), dp(1)));
        }
        if (botonAlt != null) {
            botonAlt.setBackground(crearFondo(alt ? 0xff0284c7 : 0xff1e293b, alt ? 0xff38bdf8 : 0x22ffffff, dp(8), dp(1)));
        }
        if (botonSuper != null) {
            botonSuper.setBackground(crearFondo(sup ? 0xff0284c7 : 0xff1e293b, sup ? 0xff38bdf8 : 0x22ffffff, dp(8), dp(1)));
        }
    }

    private GradientDrawable crearFondo(int colorFondo, int colorBorde, int radio, int grosorBorde) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(colorFondo);
        g.setCornerRadius(radio);
        if (grosorBorde > 0) g.setStroke(grosorBorde, colorBorde);
        return g;
    }

    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
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
    // scancodes físicos enviados crudos y aún pulsados: su soltar va crudo pase lo que pase
    private final HashSet<Integer> crudas = new HashSet<>();

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
        // Letras y espacio están en el mismo lugar en US y latam (y los números sin
        // Shift): van crudas, con su pulsar y soltar reales, para que un juego vea la
        // tecla mantenida (W para caminar). Antes eran pulsar+soltar al instante y
        // luego las repeticiones de Android: avanzaba a tirones.
        int kc = e.getKeyCode();
        boolean shift = (e.getMetaState() & KeyEvent.META_SHIFT_MASK) != 0;
        if (crudas.contains(sc) || (abajo && ((kc >= KeyEvent.KEYCODE_A && kc <= KeyEvent.KEYCODE_Z)
                || kc == KeyEvent.KEYCODE_SPACE || (!shift && kc >= KeyEvent.KEYCODE_0 && kc <= KeyEvent.KEYCODE_9)))) {
            if (e.getRepeatCount() == 0) {
                if (abajo) crudas.add(sc); else crudas.remove(sc);
                Wayland.tecla(sc, abajo);
            }
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
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            mostrarMenuSalida();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent e) {
        if (Mandos.tecla(e)) return true;
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

    // Mantener pulsado el ícono -> "Terminal": rescate si sway no arranca.
    private void atajoTerminal() {
        ShortcutInfo atajo = new ShortcutInfo.Builder(this, "terminal")
                .setShortLabel("Terminal")
                .setIcon(Icon.createWithResource(this, android.R.drawable.ic_menu_manage))
                .setIntent(new Intent(Intent.ACTION_MAIN).setClass(this, TerminalActivity.class))
                .build();
        getSystemService(ShortcutManager.class).setDynamicShortcuts(List.of(atajo));
    }
}
