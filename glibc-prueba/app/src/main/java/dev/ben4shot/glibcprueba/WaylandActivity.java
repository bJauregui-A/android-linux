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
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.style.ForegroundColorSpan;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.File;
import java.nio.file.Files;
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
    private String instanciaId;
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
        String idExtra = getIntent().getStringExtra(TerminalService.EXTRA_INSTANCIA_ID);
        if (idExtra == null) idExtra = SistemaLinux.seleccionado(this);
        instanciaId = idExtra;

        // Primera vez (APK autoinstalable): la terminal con el instalador; al terminar vuelve aquí
        AdaptadorInstalacion instalacion = SistemaLinux.adaptador(this, instanciaId);
        if (!instalacion.instalada(this) && instalacion.instaladorDisponible(this)) {
            Intent i = new Intent(this, TerminalActivity.class);
            i.putExtra(TerminalService.EXTRA_INSTANCIA_ID, instanciaId);
            startActivity(i);
            finish();
            return;
        }
        // Si el entorno seleccionado es sin-entorno, redirigir directamente a la terminal interactiva
        if ("sin-entorno".equals(SistemaLinux.leerEscritorio(this, instanciaId))) {
            Intent i = new Intent(this, TerminalActivity.class);
            i.putExtra(TerminalService.EXTRA_INSTANCIA_ID, instanciaId);
            startActivity(i);
            finish();
            return;
        }
        Wayland.iniciarPara(this, instanciaId);
        // El escritorio elegido arranca solo si aún no está corriendo.
        startForegroundService(new Intent(this, TerminalService.class)
                .setAction(TerminalService.INICIAR_ESCRITORIO)
                .putExtra(TerminalService.EXTRA_INSTANCIA_ID, instanciaId));
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
        raiz.setClipChildren(false);
        raiz.setClipToPadding(false);
        raiz.addView(vista, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));

        contenedorControles = crearControlesFlotantes();
        FrameLayout.LayoutParams paramsControles = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
        raiz.addView(contenedorControles, paramsControles);

        overlayArranque = crearOverlayArranque();
        FrameLayout.LayoutParams paramsOverlay = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT);
        raiz.addView(overlayArranque, paramsOverlay);
        iniciarMonitoreoArranque();

        raiz.setOnApplyWindowInsetsListener((v, insets) -> {
            android.graphics.Insets ime = insets.getInsets(WindowInsets.Type.ime());
            altoIme = ime.bottom;
            if (altoIme > 0) {
                mostrarBarra(true);
                if (barraTeclas != null && barraTeclas.getVisibility() == View.VISIBLE) {
                    int limiteY = v.getHeight() - altoIme - barraTeclas.getHeight() - dp(8);
                    if (barraTeclas.getTop() > limiteY) {
                        FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) barraTeclas.getLayoutParams();
                        lp.topMargin = Math.max(dp(20), limiteY);
                        barraTeclas.setLayoutParams(lp);
                    }
                }
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
        FrameLayout contenedor = new FrameLayout(this) {
            @Override
            public boolean onTouchEvent(MotionEvent event) {
                // Toques que no sean sobre la barra o el botón FAB pasan libremente a Wayland
                return false;
            }
        };
        contenedor.setClipChildren(false);
        contenedor.setClipToPadding(false);

        // 1. Botón flotante discreto (FAB) para reabrir la barra cuando está minimizada (arrastrable)
        TextView fab = new TextView(this);
        fab.setText("⌨");
        fab.setTextSize(18);
        fab.setTextColor(Color.WHITE);
        fab.setGravity(Gravity.CENTER);
        fab.setBackground(crearFondo(0xbb0f172a, 0x6638bdf8, dp(20), dp(1)));
        fab.setElevation(dp(6));
        FrameLayout.LayoutParams lpFab = new FrameLayout.LayoutParams(dp(40), dp(40));
        lpFab.gravity = Gravity.TOP | Gravity.START;
        fab.setLayoutParams(lpFab);
        fab.setVisibility(View.GONE);

        fab.post(() -> {
            View p = (View) fab.getParent();
            if (p != null) {
                int initFabX = p.getWidth() - dp(40 + 16);
                int initFabY = p.getHeight() - dp(40 + 20);
                FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) fab.getLayoutParams();
                lp.leftMargin = initFabX;
                lp.topMargin = initFabY;
                fab.setLayoutParams(lp);
            }
        });

        View.OnTouchListener arrastreFab = new View.OnTouchListener() {
            private float startX, startY;
            private int initLeft, initTop;
            private boolean moviendo;

            @Override
            public boolean onTouch(View v, MotionEvent e) {
                switch (e.getActionMasked()) {
                    case MotionEvent.ACTION_DOWN:
                        startX = e.getRawX();
                        startY = e.getRawY();
                        initLeft = fab.getLeft();
                        initTop = fab.getTop();
                        moviendo = false;
                        return true;

                    case MotionEvent.ACTION_MOVE:
                        float diff = (float) Math.hypot(e.getRawX() - startX, e.getRawY() - startY);
                        if (!moviendo && diff > dp(5)) {
                            moviendo = true;
                        }
                        if (moviendo) {
                            int nx = (int) (initLeft + (e.getRawX() - startX));
                            int ny = (int) (initTop + (e.getRawY() - startY));
                            View p = (View) fab.getParent();
                            if (p != null) {
                                int maxX = Math.max(0, p.getWidth() - fab.getWidth());
                                int maxY = Math.max(0, p.getHeight() - fab.getHeight() - altoIme);
                                nx = Math.max(0, Math.min(maxX, nx));
                                ny = Math.max(dp(20), Math.min(maxY - dp(6), ny));
                            }
                            fab.layout(nx, ny, nx + fab.getWidth(), ny + fab.getHeight());
                            FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) fab.getLayoutParams();
                            lp.leftMargin = nx;
                            lp.topMargin = ny;
                            fab.setLayoutParams(lp);
                        }
                        return true;

                    case MotionEvent.ACTION_UP:
                        if (!moviendo) {
                            mostrarBarra(true);
                        }
                        return true;
                }
                return false;
            }
        };
        fab.setOnTouchListener(arrastreFab);
        botonAlternar = fab;
        contenedor.addView(fab);

        // 2. Barra flotante tipo "Pill" (arrastrable libremente por toda la pantalla en X y Y sin cortes)
        LinearLayout marcoBarra = new LinearLayout(this) {
            private float downX, downY;
            private int initLeft, initTop;
            private boolean arrastrando;

            private void moverA(float rawX, float rawY) {
                int nx = (int) (initLeft + (rawX - downX));
                int ny = (int) (initTop + (rawY - downY));
                View p = (View) getParent();
                if (p != null) {
                    int maxX = Math.max(0, p.getWidth() - getWidth());
                    int maxY = Math.max(0, p.getHeight() - getHeight() - altoIme);
                    nx = Math.max(0, Math.min(maxX, nx));
                    ny = Math.max(dp(20), Math.min(maxY - dp(6), ny));
                }
                layout(nx, ny, nx + getWidth(), ny + getHeight());
                FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) getLayoutParams();
                lp.leftMargin = nx;
                lp.topMargin = ny;
                setLayoutParams(lp);
            }

            @Override
            public boolean onInterceptTouchEvent(MotionEvent ev) {
                switch (ev.getActionMasked()) {
                    case MotionEvent.ACTION_DOWN:
                        downX = ev.getRawX();
                        downY = ev.getRawY();
                        initLeft = getLeft();
                        initTop = getTop();
                        arrastrando = false;
                        break;

                    case MotionEvent.ACTION_MOVE:
                        float dx = ev.getRawX() - downX;
                        float dy = ev.getRawY() - downY;
                        float absDx = Math.abs(dx);
                        float absDy = Math.abs(dy);
                        if (!arrastrando && absDy > dp(6) && absDy > absDx * 0.5f) {
                            arrastrando = true;
                            return true;
                        }
                        break;

                    case MotionEvent.ACTION_UP:
                    case MotionEvent.ACTION_CANCEL:
                        arrastrando = false;
                        break;
                }
                return super.onInterceptTouchEvent(ev);
            }

            @Override
            public boolean onTouchEvent(MotionEvent ev) {
                switch (ev.getActionMasked()) {
                    case MotionEvent.ACTION_DOWN:
                        downX = ev.getRawX();
                        downY = ev.getRawY();
                        initLeft = getLeft();
                        initTop = getTop();
                        arrastrando = false;
                        return true;

                    case MotionEvent.ACTION_MOVE:
                        float dist = (float) Math.hypot(ev.getRawX() - downX, ev.getRawY() - downY);
                        if (!arrastrando && dist > dp(3)) {
                            arrastrando = true;
                        }
                        if (arrastrando) {
                            moverA(ev.getRawX(), ev.getRawY());
                        }
                        return true;

                    case MotionEvent.ACTION_UP:
                    case MotionEvent.ACTION_CANCEL:
                        arrastrando = false;
                        return true;
                }
                return super.onTouchEvent(ev);
            }
        };
        marcoBarra.setOrientation(LinearLayout.HORIZONTAL);
        marcoBarra.setGravity(Gravity.CENTER_VERTICAL);
        marcoBarra.setBackground(crearFondo(0xee0f172a, 0x4438bdf8, dp(16), dp(1)));
        marcoBarra.setElevation(dp(8));
        marcoBarra.setPadding(dp(5), dp(4), dp(5), dp(4));

        int anchoBarra = Math.min((int) (getResources().getDisplayMetrics().widthPixels * 0.88f), dp(360));
        FrameLayout.LayoutParams lpMarco = new FrameLayout.LayoutParams(
                anchoBarra, FrameLayout.LayoutParams.WRAP_CONTENT);
        lpMarco.gravity = Gravity.TOP | Gravity.START;
        marcoBarra.setLayoutParams(lpMarco);

        marcoBarra.post(() -> {
            View p = (View) marcoBarra.getParent();
            if (p != null) {
                int initX = Math.max(0, (p.getWidth() - marcoBarra.getWidth()) / 2);
                int initY = Math.max(0, p.getHeight() - marcoBarra.getHeight() - dp(18));
                FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) marcoBarra.getLayoutParams();
                lp.leftMargin = initX;
                lp.topMargin = initY;
                marcoBarra.setLayoutParams(lp);
            }
        });

        // Manija de arrastre a la izquierda
        TextView handle = new TextView(this);
        handle.setText("⠿");
        handle.setTextSize(16);
        handle.setTextColor(0xff94a3b8);
        handle.setGravity(Gravity.CENTER);
        handle.setPadding(dp(12), dp(8), dp(12), dp(8));
        handle.setBackground(crearFondo(0xff16202c, 0x33ffffff, dp(8), dp(1)));
        LinearLayout.LayoutParams lpH = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lpH.rightMargin = dp(4);
        marcoBarra.addView(handle, lpH);
        handle.setOnTouchListener((v, ev) -> {
            marcoBarra.onTouchEvent(ev);
            return true;
        });

        // Centro: Scroll horizontal con las teclas
        HorizontalScrollView scroll = new HorizontalScrollView(this);
        scroll.setFillViewport(false);
        scroll.setHorizontalScrollBarEnabled(false);
        scroll.setOverScrollMode(View.OVER_SCROLL_NEVER);

        LinearLayout fila = new LinearLayout(this);
        fila.setOrientation(LinearLayout.HORIZONTAL);
        fila.setGravity(Gravity.CENTER_VERTICAL);

        String[] teclas = {"⌨", "⛶", "ESC", "TAB", "CTRL", "ALT", "SUPER", "←", "↓", "↑", "→", "SALIR"};
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
        LinearLayout.LayoutParams lpScroll = new LinearLayout.LayoutParams(0, -2, 1.0f);
        lpScroll.rightMargin = dp(4);
        marcoBarra.addView(scroll, lpScroll);

        // Botón minimizar SIEMPRE fijo a la derecha fuera del scroll
        TextView btnMin = new TextView(this);
        btnMin.setText("▼");
        btnMin.setSingleLine(true);
        btnMin.setGravity(Gravity.CENTER);
        btnMin.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        btnMin.setTextSize(12);
        btnMin.setPadding(dp(11), dp(7), dp(11), dp(7));
        btnMin.setTextColor(0xff94a3b8);
        btnMin.setBackground(crearFondo(0xff16202c, 0x33ffffff, dp(8), dp(1)));
        btnMin.setOnClickListener(v -> mostrarBarra(false));
        LinearLayout.LayoutParams lpMin = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        marcoBarra.addView(btnMin, lpMin);

        barraTeclas = marcoBarra;
        contenedor.addView(marcoBarra);

        return contenedor;
    }

    private void mostrarBarra(boolean mostrar) {
        if (barraTeclas == null || botonAlternar == null) return;
        if (mostrar) {
            // Se abre exactamente en la posición donde está el botón FAB
            View p = (View) barraTeclas.getParent();
            int pW = p != null ? p.getWidth() : getResources().getDisplayMetrics().widthPixels;
            int pH = p != null ? p.getHeight() : getResources().getDisplayMetrics().heightPixels;
            int fabL = botonAlternar.getLeft();
            int fabT = botonAlternar.getTop();
            int barraW = barraTeclas.getWidth() > 0 ? barraTeclas.getWidth() : dp(340);
            int barraH = barraTeclas.getHeight() > 0 ? barraTeclas.getHeight() : dp(48);

            int nx = Math.max(0, Math.min(pW - barraW, fabL + botonAlternar.getWidth() - barraW));
            int ny = Math.max(dp(20), Math.min(pH - barraH - altoIme, fabT));

            FrameLayout.LayoutParams lpB = (FrameLayout.LayoutParams) barraTeclas.getLayoutParams();
            lpB.leftMargin = nx;
            lpB.topMargin = ny;
            barraTeclas.setLayoutParams(lpB);

            barraTeclas.setVisibility(View.VISIBLE);
            botonAlternar.setVisibility(View.GONE);
        } else {
            // Se minimiza exactamente en la misma posición (en el extremo derecho de la barra donde está ▼)
            View p = (View) botonAlternar.getParent();
            int pW = p != null ? p.getWidth() : getResources().getDisplayMetrics().widthPixels;
            int pH = p != null ? p.getHeight() : getResources().getDisplayMetrics().heightPixels;
            int bL = barraTeclas.getLeft();
            int bT = barraTeclas.getTop();
            int bW = barraTeclas.getWidth();
            int bH = barraTeclas.getHeight();

            int fabX = Math.max(0, Math.min(pW - botonAlternar.getWidth(), bL + bW - botonAlternar.getWidth()));
            int fabY = Math.max(dp(20), Math.min(pH - botonAlternar.getHeight() - altoIme, bT + Math.max(0, (bH - botonAlternar.getHeight()) / 2)));

            FrameLayout.LayoutParams lpF = (FrameLayout.LayoutParams) botonAlternar.getLayoutParams();
            lpF.leftMargin = fabX;
            lpF.topMargin = fabY;
            botonAlternar.setLayoutParams(lpF);

            barraTeclas.setVisibility(View.GONE);
            botonAlternar.setVisibility(View.VISIBLE);
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

    private View overlayArranque;
    private TextView textoBootLog;
    private LinearLayout panelRescate;
    private ScrollView scrollBootLog;
    private TextView tituloArranque;
    private int lineasLeidasBoot = 0;
    private boolean arranqueFinalizado = false;
    private final Handler handlerBoot = new Handler(Looper.getMainLooper());
    private final Runnable comprobadorArranque = new Runnable() {
        @Override
        public void run() {
            if (isFinishing() || isDestroyed()) return;
            actualizarEstadoArranque();
            if (!arranqueFinalizado) {
                handlerBoot.postDelayed(this, 150);
            }
        }
    };

    private View crearOverlayArranque() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setBackgroundColor(0xff0b0f14);
        layout.setPadding(dp(20), dp(36), dp(20), dp(20));

        SistemaLinux.Instancia inst = SistemaLinux.instancia(this, instanciaId);
        String nombreInst = inst != null ? inst.nombre : (instanciaId != null ? instanciaId : "arch-principal");
        tituloArranque = new TextView(this);
        tituloArranque.setText("❯ INICIANDO ENTORNO: [" + nombreInst + "]");
        tituloArranque.setTextColor(0xff58a6ff);
        tituloArranque.setTextSize(14);
        tituloArranque.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        layout.addView(tituloArranque);

        TextView sub = new TextView(this);
        sub.setText("Comprobando servicios y servidor gráfico Wayland...");
        sub.setTextColor(0xff8b949e);
        sub.setTextSize(11);
        sub.setTypeface(Typeface.MONOSPACE);
        LinearLayout.LayoutParams lpSub = new LinearLayout.LayoutParams(-1, -2);
        lpSub.topMargin = dp(4);
        lpSub.bottomMargin = dp(14);
        layout.addView(sub, lpSub);

        scrollBootLog = new ScrollView(this);
        scrollBootLog.setFillViewport(true);
        textoBootLog = new TextView(this);
        textoBootLog.setTextColor(0xffe6edf3);
        textoBootLog.setTextSize(11);
        textoBootLog.setTypeface(Typeface.MONOSPACE);
        textoBootLog.setLineSpacing(dp(2), 1.0f);
        scrollBootLog.addView(textoBootLog, new FrameLayout.LayoutParams(-1, -2));

        LinearLayout.LayoutParams lpScroll = new LinearLayout.LayoutParams(-1, 0, 1.0f);
        layout.addView(scrollBootLog, lpScroll);

        panelRescate = new LinearLayout(this);
        panelRescate.setOrientation(LinearLayout.VERTICAL);
        panelRescate.setVisibility(View.GONE);
        panelRescate.setPadding(0, dp(12), 0, 0);

        TextView errAviso = new TextView(this);
        errAviso.setText("✖ El entorno no pudo iniciar. Puedes entrar a la consola para repararlo:");
        errAviso.setTextColor(0xffff7b72);
        errAviso.setTextSize(12);
        errAviso.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        panelRescate.addView(errAviso);

        LinearLayout botones = new LinearLayout(this);
        botones.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams lpBotones = new LinearLayout.LayoutParams(-1, -2);
        lpBotones.topMargin = dp(10);
        botones.setLayoutParams(lpBotones);

        TextView btnConsola = new TextView(this);
        btnConsola.setText("❯ CONSOLA DE RESCATE [" + nombreInst + "]");
        btnConsola.setTextColor(0xff00e676);
        btnConsola.setTextSize(12);
        btnConsola.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        btnConsola.setBackground(crearFondo(0xff16202c, 0xff00e676, dp(6), dp(1)));
        btnConsola.setPadding(dp(14), dp(8), dp(14), dp(8));
        btnConsola.setClickable(true);
        btnConsola.setOnClickListener(v -> {
            Intent i = new Intent(WaylandActivity.this, TerminalActivity.class);
            i.putExtra(TerminalService.EXTRA_INSTANCIA_ID, instanciaId);
            startActivity(i);
            finish();
        });
        botones.addView(btnConsola);

        View sep = new View(this);
        sep.setLayoutParams(new LinearLayout.LayoutParams(dp(10), 1));
        botones.addView(sep);

        TextView btnVolver = new TextView(this);
        btnVolver.setText("✕ VOLVER");
        btnVolver.setTextColor(0xff8b949e);
        btnVolver.setTextSize(12);
        btnVolver.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        btnVolver.setBackground(crearFondo(0xff16202c, 0xff30363d, dp(6), dp(1)));
        btnVolver.setPadding(dp(14), dp(8), dp(14), dp(8));
        btnVolver.setClickable(true);
        btnVolver.setOnClickListener(v -> volverAlInicio());
        botones.addView(btnVolver);

        panelRescate.addView(botones);
        layout.addView(panelRescate);

        return layout;
    }

    private void iniciarMonitoreoArranque() {
        arranqueFinalizado = false;
        lineasLeidasBoot = 0;
        handlerBoot.removeCallbacks(comprobadorArranque);
        handlerBoot.post(comprobadorArranque);
    }

    private void actualizarEstadoArranque() {
        File raizInstancia = SistemaLinux.raiz(this, instanciaId);
        File dirRun = new File(raizInstancia, Wayland.runtimeDir().substring(1));
        File fBoot = new File(dirRun, "linux-session-boot.log");
        File fEstado = new File(dirRun, "linux-session.estado");

        if (fBoot.exists()) {
            try {
                List<String> lineas = Files.readAllLines(fBoot.toPath());
                if (lineas.size() > lineasLeidasBoot) {
                    SpannableStringBuilder sb = new SpannableStringBuilder();
                    for (int i = 0; i < lineas.size(); i++) {
                        String l = lineas.get(i);
                        l = l.replaceAll("\u001B\\[[;\\d]*m", "");
                        int inicioLinea = sb.length();
                        sb.append(l).append("\n");

                        if (l.contains("[  OK  ]")) {
                            int idx = l.indexOf("[  OK  ]");
                            sb.setSpan(new ForegroundColorSpan(0xff00e676), inicioLinea + idx, inicioLinea + idx + 8, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                        } else if (l.contains("[FAILED]")) {
                            int idx = l.indexOf("[FAILED]");
                            sb.setSpan(new ForegroundColorSpan(0xffff5252), inicioLinea + idx, inicioLinea + idx + 8, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                        } else if (l.contains("[ INFO ]")) {
                            int idx = l.indexOf("[ INFO ]");
                            sb.setSpan(new ForegroundColorSpan(0xff40c4ff), inicioLinea + idx, inicioLinea + idx + 8, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                        }
                    }
                    textoBootLog.setText(sb);
                    lineasLeidasBoot = lineas.size();
                    if (scrollBootLog != null) {
                        scrollBootLog.post(() -> scrollBootLog.fullScroll(View.FOCUS_DOWN));
                    }
                }
            } catch (Exception ignored) { }
        }

        if (fEstado.exists()) {
            try {
                String estado = Files.readString(fEstado.toPath()).trim();
                if (estado.startsWith("LISTO:")) {
                    arranqueFinalizado = true;
                    if (overlayArranque != null && overlayArranque.getVisibility() == View.VISIBLE) {
                        textoBootLog.append("\n[  OK  ] Sesión gráfica lista. Conectando pantalla...");
                        overlayArranque.animate()
                                .alpha(0f)
                                .setDuration(350)
                                .withEndAction(() -> overlayArranque.setVisibility(View.GONE));
                    }
                } else if (estado.startsWith("FALLO:")) {
                    arranqueFinalizado = true;
                    if (tituloArranque != null) {
                        tituloArranque.setText("✖ ERROR AL INICIAR ENTORNO");
                        tituloArranque.setTextColor(0xffff5252);
                    }
                    if (panelRescate != null) {
                        panelRescate.setVisibility(View.VISIBLE);
                    }
                    if (scrollBootLog != null) {
                        scrollBootLog.post(() -> scrollBootLog.fullScroll(View.FOCUS_DOWN));
                    }
                }
            } catch (Exception ignored) { }
        }
    }

    @Override
    protected void onDestroy() {
        handlerBoot.removeCallbacks(comprobadorArranque);
        super.onDestroy();
    }

    private void volverAlInicio() {
        Intent i = new Intent(this, SistemaActivity.class);
        i.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        startActivity(i);
        finish();
    }

    private void mostrarMenuSalida() {
        SistemaLinux.Instancia inst = SistemaLinux.instancia(this, instanciaId);
        String nombre = inst != null ? inst.nombre : "Linux";
        new AlertDialog.Builder(this)
                .setTitle("✦ Menú de Sesión (" + nombre + ")")
                .setMessage("¿Deseas volver al inicio manteniendo la sesión abierta en segundo plano, o cerrar la sesión por completo?")
                .setPositiveButton("Volver al inicio (en fondo)", (d, w) -> {
                    volverAlInicio();
                })
                .setNegativeButton("✕ Cerrar sesión", (d, w) -> {
                    Wayland.ventana(null, 0, 0, 0, 0);
                    Intent i = new Intent(this, TerminalService.class)
                            .setAction(TerminalService.CERRAR_INSTANCIA)
                            .putExtra(TerminalService.EXTRA_INSTANCIA_ID, instanciaId);
                    startService(i);
                    volverAlInicio();
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
                // Al ser la barra flotante, la superficie solo descuenta la altura del teclado virtual
                alto = Math.max(200, altoPadre - altoIme);
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
