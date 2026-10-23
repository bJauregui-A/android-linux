package dev.ben4shot.glibcprueba;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.InputType;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowInsets;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import com.termux.terminal.TerminalSession;
import com.termux.terminal.TerminalSessionClient;
import com.termux.view.TerminalView;
import com.termux.view.TerminalViewClient;

import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

// Pantalla principal de la app: lista de entornos Linux (instancias) disponibles y
// consola shell real y funcional abierta en la carpeta superior (files/) para recorrer
// e inspeccionar las instancias y archivos del sistema.
public class SistemaActivity extends Activity implements TerminalViewClient, TerminalSessionClient {
    private static final String TAG = "SISTEMA";

    private static final int FONDO_OSCURO = 0xff090d13;
    private static final int PANEL_CARD = 0xff121820;
    private static final int PANEL_ACTIVO = 0xff16202c;
    private static final int BORDE_ACTIVO = 0xff38ef7d;
    private static final int BORDE_NORMAL = 0xff253041;
    private static final int BORDE_BOTON = 0xff32435b;
    private static final int TEXTO_CLARO = 0xfff0f6fc;
    private static final int TEXTO_MUTED = 0xff8b949e;
    private static final int ACCENTO_CIAN = 0xff39c5bb;
    private static final int ACCENTO_AZUL = 0xff58a6ff;
    private static final int ACCENTO_PURPURA = 0xffbc8cff;
    private static final int ACCENTO_VERDE = 0xff3fb950;
    private static final int ACCENTO_ROJO = 0xfff85149;
    private static final int ACCENTO_AMBAR = 0xffd29922;

    private LinearLayout contenedorInstancias;
    private FrameLayout overlayConsola;
    private TextView titOverlay;
    private TerminalView vistaTerminal;
    private TerminalSession sesionConsola;
    private int tamLetra;
    private boolean ctrl, alt;
    private TextView botonCtrl, botonAlt;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        FrameLayout raiz = new FrameLayout(this);
        raiz.setBackgroundColor(FONDO_OSCURO);

        LinearLayout raizPrincipal = new LinearLayout(this);
        raizPrincipal.setOrientation(LinearLayout.VERTICAL);
        raizPrincipal.setBackgroundColor(FONDO_OSCURO);

        // Cabecera de la sección de entornos (con botón compacto para crear nueva instancia)
        LinearLayout cabeceraInstancias = new LinearLayout(this);
        cabeceraInstancias.setOrientation(LinearLayout.HORIZONTAL);
        cabeceraInstancias.setGravity(Gravity.CENTER_VERTICAL);

        TextView tituloSeccion = texto("❯ ENTORNOS DISPONIBLES (INSTANCIAS)", 13, true, ACCENTO_CIAN);
        cabeceraInstancias.addView(tituloSeccion, new LinearLayout.LayoutParams(0, -2, 1.0f));

        TextView btnRed = crearBotonChip("⇄ RED", ACCENTO_AMBAR, this::mostrarDialogoPortForward);
        cabeceraInstancias.addView(btnRed);

        cabeceraInstancias.addView(espacioHorizontal(dp(8)));

        TextView btnCrear = crearBotonChip("＋ CREAR", ACCENTO_PURPURA, this::mostrarDialogoCreacion);
        cabeceraInstancias.addView(btnCrear);

        LinearLayout.LayoutParams lpCab = new LinearLayout.LayoutParams(-1, -2);
        lpCab.bottomMargin = dp(10);
        raizPrincipal.addView(cabeceraInstancias, lpCab);

        // Contenedor scrollable para las tarjetas de instancias
        ScrollView scrollInstancias = new ScrollView(this);
        scrollInstancias.setFillViewport(true);
        contenedorInstancias = new LinearLayout(this);
        contenedorInstancias.setOrientation(LinearLayout.VERTICAL);
        scrollInstancias.addView(contenedorInstancias);

        // Ocupa el espacio principal de la pantalla
        LinearLayout.LayoutParams lpScrollInst = new LinearLayout.LayoutParams(-1, 0, 1.0f);
        lpScrollInst.bottomMargin = dp(10);
        raizPrincipal.addView(scrollInstancias, lpScrollInst);

        // Apartado de consola (toca para abrir el overlay flotante)
        LinearLayout apartadoConsola = new LinearLayout(this);
        apartadoConsola.setOrientation(LinearLayout.HORIZONTAL);
        apartadoConsola.setGravity(Gravity.CENTER_VERTICAL);
        apartadoConsola.setBackground(crearFondo(PANEL_CARD, BORDE_NORMAL, dp(10), dp(1)));
        apartadoConsola.setPadding(dp(14), dp(12), dp(14), dp(12));
        apartadoConsola.setClickable(true);
        apartadoConsola.setFocusable(true);

        LinearLayout infoConsola = new LinearLayout(this);
        infoConsola.setOrientation(LinearLayout.VERTICAL);

        TextView titConsola = texto("❯ CONSOLA DEL SISTEMA (files/)", 12, true, ACCENTO_VERDE);
        infoConsola.addView(titConsola);

        TextView subConsola = texto("Terminal interactiva (/system/bin/sh) • Toca para abrir", 11, false, TEXTO_MUTED);
        LinearLayout.LayoutParams lpSub = new LinearLayout.LayoutParams(-2, -2);
        lpSub.topMargin = dp(2);
        infoConsola.addView(subConsola, lpSub);

        apartadoConsola.addView(infoConsola, new LinearLayout.LayoutParams(0, -2, 1.0f));

        TextView btnAbrirConsola = textoBadge("▶ ABRIR", ACCENTO_VERDE);
        btnAbrirConsola.setPadding(dp(12), dp(6), dp(12), dp(6));
        apartadoConsola.addView(btnAbrirConsola);

        apartadoConsola.setOnClickListener(v -> mostrarOverlayConsola(true));

        LinearLayout.LayoutParams lpApartado = new LinearLayout.LayoutParams(-1, -2);
        lpApartado.bottomMargin = dp(4);
        raizPrincipal.addView(apartadoConsola, lpApartado);

        raiz.addView(raizPrincipal, new FrameLayout.LayoutParams(-1, -1));

        // Overlay de la consola (oculto por defecto con scrim semi-transparente)
        overlayConsola = new FrameLayout(this);
        overlayConsola.setVisibility(View.GONE);
        overlayConsola.setBackgroundColor(0xb3000000);
        overlayConsola.setClickable(true);
        overlayConsola.setFocusable(true);
        overlayConsola.setOnClickListener(v -> mostrarOverlayConsola(false));

        // Panel flotante de la consola con bordes redondeados y sombra
        LinearLayout panelConsola = new LinearLayout(this);
        panelConsola.setOrientation(LinearLayout.VERTICAL);
        panelConsola.setBackground(crearFondo(0xff0d131b, BORDE_NORMAL, dp(16), dp(1)));
        panelConsola.setClipToOutline(true);
        panelConsola.setElevation(dp(12));
        panelConsola.setClickable(true);
        panelConsola.setOnClickListener(v -> {});

        // Cabecera del panel overlay
        LinearLayout cabeceraOverlay = new LinearLayout(this);
        cabeceraOverlay.setOrientation(LinearLayout.HORIZONTAL);
        cabeceraOverlay.setGravity(Gravity.CENTER_VERTICAL);
        cabeceraOverlay.setPadding(dp(14), dp(10), dp(12), dp(10));
        cabeceraOverlay.setBackgroundColor(0xff121924);

        titOverlay = texto("❯ CONSOLA", 12, true, ACCENTO_VERDE);
        cabeceraOverlay.addView(titOverlay, new LinearLayout.LayoutParams(0, -2, 1.0f));

        TextView btnCerrarOverlay = crearBotonChip("✕ CERRAR", ACCENTO_ROJO, () -> mostrarOverlayConsola(false));
        cabeceraOverlay.addView(btnCerrarOverlay);

        panelConsola.addView(cabeceraOverlay, new LinearLayout.LayoutParams(-1, -2));

        // Vista de la terminal de Termux conectada a una shell /system/bin/sh interactiva
        vistaTerminal = new TerminalView(this, null);
        vistaTerminal.setTerminalViewClient(this);
        vistaTerminal.setFocusable(true);
        vistaTerminal.setFocusableInTouchMode(true);
        tamLetra = (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, 12, getResources().getDisplayMetrics());
        vistaTerminal.setTextSize(tamLetra);
        vistaTerminal.setTypeface(Typeface.MONOSPACE);

        LinearLayout.LayoutParams lpTerm = new LinearLayout.LayoutParams(-1, 0, 1.0f);
        lpTerm.setMargins(dp(6), dp(4), dp(6), dp(4));
        panelConsola.addView(vistaTerminal, lpTerm);

        panelConsola.addView(filaTeclas(), new LinearLayout.LayoutParams(-1, -2));

        FrameLayout.LayoutParams lpPanel = new FrameLayout.LayoutParams(-1, -1);
        lpPanel.setMargins(dp(8), dp(24), dp(8), dp(8));
        overlayConsola.addView(panelConsola, lpPanel);

        raiz.addView(overlayConsola, new FrameLayout.LayoutParams(-1, -1));

        // Ajuste dinámico para barras del sistema y teclado virtual (IME)
        raiz.setOnApplyWindowInsetsListener((v, insets) -> {
            android.graphics.Insets i = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.ime());
            raizPrincipal.setPadding(i.left + dp(14), i.top + dp(10), i.right + dp(14), i.bottom + dp(6));
            overlayConsola.setPadding(i.left, i.top, i.right, i.bottom);
            return WindowInsets.CONSUMED;
        });

        setContentView(raiz);

        actualizarLista();
        iniciarConsola();
        RedManager.actualizar(this);
    }

    private void mostrarOverlayConsola(boolean mostrar) {
        if (overlayConsola == null) return;
        if (mostrar) {
            overlayConsola.setVisibility(View.VISIBLE);
            if (sesionConsola == null || !sesionConsola.isRunning()) {
                iniciarConsola();
            } else if (vistaTerminal != null) {
                vistaTerminal.onScreenUpdated();
            }
            if (vistaTerminal != null) {
                vistaTerminal.requestFocus();
                vistaTerminal.post(() -> {
                    InputMethodManager imm = getSystemService(InputMethodManager.class);
                    if (imm != null) imm.showSoftInput(vistaTerminal, 0);
                });
            }
        } else {
            if (vistaTerminal != null) {
                InputMethodManager imm = getSystemService(InputMethodManager.class);
                if (imm != null) imm.hideSoftInputFromWindow(vistaTerminal.getWindowToken(), 0);
            }
            overlayConsola.setVisibility(View.GONE);
        }
    }

    @Override
    public void onBackPressed() {
        if (overlayConsola != null && overlayConsola.getVisibility() == View.VISIBLE) {
            mostrarOverlayConsola(false);
            return;
        }
        super.onBackPressed();
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            if (overlayConsola != null && overlayConsola.getVisibility() == View.VISIBLE) {
                mostrarOverlayConsola(false);
                return true;
            }
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    protected void onResume() {
        super.onResume();
        actualizarLista();
        if (sesionConsola == null || !sesionConsola.isRunning()) {
            iniciarConsola();
        } else if (vistaTerminal != null) {
            vistaTerminal.onScreenUpdated();
        }
    }

    @Override
    protected void onDestroy() {
        if (sesionConsola != null) {
            sesionConsola.finishIfRunning();
            sesionConsola = null;
        }
        super.onDestroy();
    }

    private void iniciarConsola() {
        if (sesionConsola != null && sesionConsola.isRunning()) {
            sesionConsola.finishIfRunning();
        }
        String instId = SistemaLinux.seleccionado(this);
        if (instId == null) instId = "arch-principal";
        SistemaLinux.Instancia inst = SistemaLinux.instancia(this, instId);
        String nombreInst = inst != null ? inst.nombre : instId;
        if (titOverlay != null) {
            titOverlay.setText("❯ CONSOLA: [" + nombreInst + "]");
        }

        AdaptadorInstalacion adaptador = SistemaLinux.adaptador(this, instId);
        File prefijo = adaptador.raiz(this);
        File binBash = new File(prefijo, "usr/bin/bash");
        File binZsh = new File(prefijo, "usr/bin/zsh");

        if (adaptador.instalada(this) && (binZsh.exists() || binBash.exists())) {
            String cargador = adaptador.cargador(this);
            String homeRel = adaptador.home(prefijo);
            File homeDir = new File(prefijo, homeRel);
            String shell = binZsh.exists() ? "/usr/bin/zsh" : "/usr/bin/bash";
            List<String> envList = new ArrayList<>();
            envList.add("PATH=/usr/local/bin:/usr/bin:/bin:/system/bin");
            envList.add("HOME=" + homeDir.getAbsolutePath());
            envList.add("USER=" + adaptador.usuario(prefijo));
            envList.add("SHELL=" + shell);
            envList.add("TERM=xterm-256color");
            envList.add("GLIBC_PREFIX=" + prefijo.getAbsolutePath());
            envList.add("TMPDIR=/tmp");
            String[] args = new String[]{shell, "-i"};
            sesionConsola = new TerminalSession(cargador, homeDir.getAbsolutePath(), args, envList.toArray(new String[0]), 5000, this);
        } else {
            String cwd = prefijo.exists() ? prefijo.getAbsolutePath() : getFilesDir().getAbsolutePath();
            String[] env = new String[]{
                    "PATH=/system/bin:/system/xbin",
                    "HOME=" + cwd,
                    "TERM=xterm-256color",
                    "TMPDIR=" + getCacheDir().getAbsolutePath(),
                    "ANDROID_DATA=" + System.getenv("ANDROID_DATA"),
                    "ANDROID_ROOT=" + System.getenv("ANDROID_ROOT")
            };
            String[] args = new String[]{"sh", "-i"};
            sesionConsola = new TerminalSession("/system/bin/sh", cwd, args, env, 5000, this);
        }
        vistaTerminal.attachSession(sesionConsola);
        vistaTerminal.onScreenUpdated();
    }

    private View filaTeclas() {
        HorizontalScrollView scroll = new HorizontalScrollView(this);
        scroll.setFillViewport(false);
        scroll.setHorizontalScrollBarEnabled(false);
        scroll.setBackgroundColor(0xff101721);

        LinearLayout fila = new LinearLayout(this);
        fila.setOrientation(LinearLayout.HORIZONTAL);
        fila.setGravity(Gravity.CENTER_VERTICAL);
        fila.setPadding(dp(4), dp(4), dp(4), dp(4));

        String[] teclas = {"⌨", "ESC", "TAB", "CTRL", "ALT", "←", "↓", "↑", "→", "▼"};
        for (String t : teclas) {
            TextView b = new TextView(this);
            b.setText(t);
            b.setSingleLine(true);
            b.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
            b.setTextSize(12);
            b.setGravity(Gravity.CENTER);
            b.setPadding(dp(12), dp(6), dp(12), dp(6));
            if (t.equals("▼")) {
                b.setTextColor(ACCENTO_ROJO);
                b.setBackground(crearFondo(0xff2a1616, 0x66ff6b6b, dp(6), dp(1)));
            } else {
                b.setTextColor(TEXTO_CLARO);
                b.setBackground(crearFondo(0xff16202c, 0x22ffffff, dp(6), dp(1)));
            }
            b.setOnClickListener(v -> tecla(t));
            if (t.equals("CTRL")) botonCtrl = b;
            if (t.equals("ALT")) botonAlt = b;

            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
            lp.rightMargin = dp(4);
            fila.addView(b, lp);
        }
        scroll.addView(fila, new FrameLayout.LayoutParams(-2, -2));
        return scroll;
    }

    private void tecla(String t) {
        if (vistaTerminal == null) return;
        switch (t) {
            case "⌨":
                vistaTerminal.requestFocus();
                getSystemService(InputMethodManager.class).showSoftInput(vistaTerminal, 0);
                return;
            case "▼":
                mostrarOverlayConsola(false);
                return;
            case "CTRL": ctrl = !ctrl; marcarModificadores(); return;
            case "ALT": alt = !alt; marcarModificadores(); return;
            case "ESC": codigo(KeyEvent.KEYCODE_ESCAPE); return;
            case "TAB": codigo(KeyEvent.KEYCODE_TAB); return;
            case "←": codigo(KeyEvent.KEYCODE_DPAD_LEFT); return;
            case "↓": codigo(KeyEvent.KEYCODE_DPAD_DOWN); return;
            case "↑": codigo(KeyEvent.KEYCODE_DPAD_UP); return;
            case "→": codigo(KeyEvent.KEYCODE_DPAD_RIGHT); return;
            default: vistaTerminal.inputCodePoint(t.codePointAt(0), false, false);
        }
    }

    private void codigo(int keyCode) {
        if (vistaTerminal != null) {
            vistaTerminal.onKeyDown(keyCode, new KeyEvent(KeyEvent.ACTION_DOWN, keyCode));
        }
    }

    private void marcarModificadores() {
        if (botonCtrl != null) {
            botonCtrl.setBackground(crearFondo(ctrl ? 0xff0284c7 : 0xff16202c, ctrl ? 0xff38bdf8 : 0x22ffffff, dp(6), dp(1)));
        }
        if (botonAlt != null) {
            botonAlt.setBackground(crearFondo(alt ? 0xff0284c7 : 0xff16202c, alt ? 0xff38bdf8 : 0x22ffffff, dp(6), dp(1)));
        }
    }

    private void actualizarLista() {
        if (contenedorInstancias == null) return;
        contenedorInstancias.removeAllViews();

        List<SistemaLinux.Instancia> instancias = SistemaLinux.listarInstancias(this);
        SistemaLinux.Instancia activa = SistemaLinux.instanciaSeleccionada(this);

        if (instancias.isEmpty()) {
            TextView vacio = texto("  No hay entornos creados. Toca '＋ CREAR' para instalar uno nuevo.", 12, false, TEXTO_MUTED);
            LinearLayout.LayoutParams lpV = new LinearLayout.LayoutParams(-1, -2);
            lpV.topMargin = dp(8);
            lpV.bottomMargin = dp(8);
            contenedorInstancias.addView(vacio, lpV);
            return;
        }

        for (int i = 0; i < instancias.size(); i++) {
            SistemaLinux.Instancia inst = instancias.get(i);
            boolean esActiva = activa != null && inst.id.equals(activa.id);
            AdaptadorInstalacion adp = SistemaLinux.adaptador(this, inst);
            boolean instalada = adp.instalada(this);

            contenedorInstancias.addView(crearTarjetaInstancia(inst, i + 1, esActiva, instalada));
        }
    }

    private View crearTarjetaInstancia(SistemaLinux.Instancia inst, int index, boolean activa, boolean instalada) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(14), dp(10), dp(14), dp(10));
        boolean corriendo = TerminalService.estaCorriendo(inst.id);
        boolean tieneTerm = TerminalService.tieneTerminal(inst.id);
        boolean tieneEsc = TerminalService.tieneEscritorio(inst.id);

        card.setBackground(crearFondo(
                corriendo ? PANEL_ACTIVO : PANEL_CARD,
                corriendo ? BORDE_ACTIVO : BORDE_NORMAL,
                dp(8),
                corriendo ? dp(2) : dp(1)));

        LinearLayout.LayoutParams lpCard = new LinearLayout.LayoutParams(-1, -2);
        lpCard.bottomMargin = dp(8);
        card.setLayoutParams(lpCard);

        // Header de la tarjeta: Badges limpios (Consola, En ejecución, Pendiente)
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);

        String idEsc = SistemaLinux.leerEscritorio(this, inst.id);
        boolean esSinEntorno = "sin-entorno".equals(idEsc);

        if (esSinEntorno) {
            TextView tagTipo = textoBadge("CONSOLA", ACCENTO_AMBAR);
            header.addView(tagTipo);
        }

        if (corriendo) {
            TextView tagCorriendo = textoBadge("● EN EJECUCIÓN", ACCENTO_VERDE);
            LinearLayout.LayoutParams lpCorr = new LinearLayout.LayoutParams(-2, -2);
            if (header.getChildCount() > 0) lpCorr.leftMargin = dp(8);
            header.addView(tagCorriendo, lpCorr);
        }

        if (!instalada) {
            TextView tagPend = textoBadge("PENDIENTE INSTALACIÓN", 0xffffb703);
            LinearLayout.LayoutParams lpPend = new LinearLayout.LayoutParams(-2, -2);
            if (header.getChildCount() > 0) lpPend.leftMargin = dp(8);
            header.addView(tagPend, lpPend);
        }

        if (header.getChildCount() > 0) {
            card.addView(header);
        }

        // Nombre de la instancia y ruta
        TextView nombre = texto("❯ [" + index + "] " + inst.nombre, 15, true, corriendo ? TEXTO_CLARO : 0xffcbd5e1);
        LinearLayout.LayoutParams lpNombre = new LinearLayout.LayoutParams(-1, -2);
        lpNombre.topMargin = dp(4);
        card.addView(nombre, lpNombre);

        String distroStr = SistemaLinux.ARCH.equals(inst.distroId) ? "Arch Linux ARM" : inst.distroId;
        TextView meta = texto("    files/" + inst.rutaRelativa + "  •  " + distroStr, 11, false, TEXTO_MUTED);
        card.addView(meta);

        // Botones de acción dentro de la tarjeta
        LinearLayout acciones = new LinearLayout(this);
        acciones.setOrientation(LinearLayout.HORIZONTAL);
        acciones.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout.LayoutParams lpAcc = new LinearLayout.LayoutParams(-1, -2);
        lpAcc.topMargin = dp(8);
        acciones.setLayoutParams(lpAcc);

        if (esSinEntorno) {
            String textoBoton = tieneTerm ? "▶ CONSOLA (ACTIVA)" : "▶ CONSOLA";
            TextView btnConsola = crearBotonChip(textoBoton, ACCENTO_VERDE, () -> {
                activarYEjecutar(inst.id, false);
            });
            acciones.addView(btnConsola);
        } else {
            // Botón INICIAR ESCRITORIO o VOLVER si ya está corriendo
            String textoBoton = tieneEsc ? "▶ VOLVER" : "▶ ESCRITORIO";
            TextView btnIniciar = crearBotonChip(textoBoton, ACCENTO_VERDE, () -> {
                activarYEjecutar(inst.id, true);
            });
            acciones.addView(btnIniciar);

            acciones.addView(espacioHorizontal(dp(8)));

            // Botón TERMINAL
            String textoTerminal = tieneTerm ? ">_ TERMINAL (ACTIVA)" : ">_ TERMINAL";
            TextView btnTerminal = crearBotonChip(textoTerminal, ACCENTO_AZUL, () -> {
                activarYEjecutar(inst.id, false);
            });
            acciones.addView(btnTerminal);
        }

        // Botón ELIMINAR
        acciones.addView(espacioHorizontal(dp(8)));
        TextView btnBorrar = crearBotonChip("✕ BORRAR", ACCENTO_ROJO, () -> {
            confirmarEliminar(inst);
        });
        acciones.addView(btnBorrar);

        card.addView(acciones);

        // Al tocar la tarjeta, se activa
        card.setClickable(true);
        card.setOnClickListener(v -> {
            if (!activa) {
                SistemaLinux.seleccionarInstancia(this, inst.id);
                actualizarLista();
                iniciarConsola();
            } else {
                activarYEjecutar(inst.id, !esSinEntorno);
            }
        });

        return card;
    }

    private void activarYEjecutar(String id, boolean escritorio) {
        SistemaLinux.seleccionarInstancia(this, id);
        if (escritorio) {
            if ("sin-entorno".equals(SistemaLinux.leerEscritorio(this, id))) {
                Intent i = new Intent(this, TerminalActivity.class);
                i.putExtra(TerminalService.EXTRA_INSTANCIA_ID, id);
                startActivity(i);
                return;
            }
            Intent i = new Intent(this, WaylandActivity.class);
            i.putExtra(TerminalService.EXTRA_INSTANCIA_ID, id);
            startActivity(i);
        } else {
            Intent i = new Intent(this, TerminalActivity.class);
            i.putExtra(TerminalService.EXTRA_INSTANCIA_ID, id);
            startActivity(i);
        }
    }

    private void confirmarEliminar(SistemaLinux.Instancia inst) {
        new AlertDialog.Builder(this)
                .setTitle("Eliminar entorno")
                .setMessage("¿Eliminar definitivamente el entorno '" + inst.nombre + "' y todos sus archivos en files/" + inst.rutaRelativa + "?")
                .setPositiveButton("Eliminar", (d, w) -> {
                    SistemaLinux.eliminarInstancia(this, inst.id);
                    actualizarLista();
                    Toast.makeText(this, "Entorno eliminado", Toast.LENGTH_SHORT).show();
                })
                .setNegativeButton("Cancelar", null)
                .show();
    }

    private void mostrarDialogoCreacion() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(dp(22), dp(18), dp(22), dp(18));
        layout.setBackgroundColor(FONDO_OSCURO);

        TextView banner = texto("╭─ ✦ NUEVO ENTORNO LINUX ─────────────────────╮", 11, true, ACCENTO_PURPURA);
        layout.addView(banner);

        TextView lblDistro = texto("❯ 1. Selecciona la Distribución Base:", 13, true, ACCENTO_CIAN);
        LinearLayout.LayoutParams lp1 = new LinearLayout.LayoutParams(-1, -2);
        lp1.topMargin = dp(12);
        layout.addView(lblDistro, lp1);

        RadioGroup rg = new RadioGroup(this);
        RadioButton rbArch = new RadioButton(this);
        rbArch.setId(View.generateViewId());
        rbArch.setText("Arch Linux ARM (Probado y funcional)");
        rbArch.setTextColor(TEXTO_CLARO);
        rbArch.setTypeface(Typeface.MONOSPACE);
        rbArch.setChecked(true);
        rg.addView(rbArch);

        RadioButton rbDebian = new RadioButton(this);
        rbDebian.setId(View.generateViewId());
        rbDebian.setText("Debian ARM64 (Próximamente)");
        rbDebian.setTextColor(TEXTO_MUTED);
        rbDebian.setTypeface(Typeface.MONOSPACE);
        rbDebian.setEnabled(false);
        rg.addView(rbDebian);

        RadioButton rbUbuntu = new RadioButton(this);
        rbUbuntu.setId(View.generateViewId());
        rbUbuntu.setText("Ubuntu ARM64 (Próximamente)");
        rbUbuntu.setTextColor(TEXTO_MUTED);
        rbUbuntu.setTypeface(Typeface.MONOSPACE);
        rbUbuntu.setEnabled(false);
        rg.addView(rbUbuntu);

        layout.addView(rg);

        TextView lblTipo = texto("❯ 2. Tipo de Entorno:", 13, true, ACCENTO_CIAN);
        LinearLayout.LayoutParams lpTipo = new LinearLayout.LayoutParams(-1, -2);
        lpTipo.topMargin = dp(14);
        layout.addView(lblTipo, lpTipo);

        RadioGroup rgTipo = new RadioGroup(this);
        RadioButton rbGrafico = new RadioButton(this);
        rbGrafico.setId(View.generateViewId());
        rbGrafico.setText("Con Entorno Gráfico (Wayland / GPU Turnip)");
        rbGrafico.setTextColor(TEXTO_CLARO);
        rbGrafico.setTypeface(Typeface.MONOSPACE);
        rbGrafico.setChecked(true);
        rgTipo.addView(rbGrafico);

        RadioButton rbConsola = new RadioButton(this);
        rbConsola.setId(View.generateViewId());
        rbConsola.setText("Consola pura / Servidor (Headless, sin GPU)");
        rbConsola.setTextColor(TEXTO_CLARO);
        rbConsola.setTypeface(Typeface.MONOSPACE);
        rgTipo.addView(rbConsola);
        layout.addView(rgTipo);

        TextView lblNombre = texto("❯ 3. Nombre del Entorno:", 13, true, ACCENTO_CIAN);
        LinearLayout.LayoutParams lp2 = new LinearLayout.LayoutParams(-1, -2);
        lp2.topMargin = dp(14);
        layout.addView(lblNombre, lp2);

        EditText input = new EditText(this);
        input.setHint("ej: arch-desarrollo");
        input.setHintTextColor(0xff556272);
        input.setTextColor(TEXTO_CLARO);
        input.setTypeface(Typeface.MONOSPACE);
        input.setTextSize(14);
        input.setBackground(crearFondo(0xff16202c, BORDE_BOTON, dp(6), dp(1)));
        input.setPadding(dp(12), dp(10), dp(12), dp(10));
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        layout.addView(input);

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setView(layout)
                .setPositiveButton("✦ CREAR", null)
                .setNegativeButton("CANCELAR", null)
                .create();

        dialog.show();

        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            String nom = input.getText().toString().trim();
            if (nom.isEmpty()) {
                input.setError("Ingresa un nombre");
                return;
            }
            boolean esConsola = rbConsola.isChecked();
            dialog.dismiss();
            try {
                SistemaLinux.Instancia nueva = SistemaLinux.crearInstancia(this, nom, SistemaLinux.ARCH);
                if (esConsola) {
                    SistemaLinux.escribirEscritorio(this, nueva.id, "sin-entorno");
                }
                actualizarLista();
                activarYEjecutar(nueva.id, false);
            } catch (Exception e) {
                Toast.makeText(this, "Error: " + e.getMessage(), Toast.LENGTH_LONG).show();
            }
        });
    }

    private void mostrarDialogoPortForward() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(dp(18), dp(16), dp(18), dp(16));
        layout.setBackgroundColor(FONDO_OSCURO);

        TextView banner = texto("╭─ ✦ GESTOR DE RED Y PUERTOS ──────────────────╮", 11, true, ACCENTO_AMBAR);
        layout.addView(banner);

        // Barra de pestañas / secciones
        LinearLayout barraTabs = new LinearLayout(this);
        barraTabs.setOrientation(LinearLayout.HORIZONTAL);
        barraTabs.setGravity(Gravity.CENTER_HORIZONTAL);
        LinearLayout.LayoutParams lpTabs = new LinearLayout.LayoutParams(-1, -2);
        lpTabs.topMargin = dp(8);
        lpTabs.bottomMargin = dp(8);
        layout.addView(barraTabs, lpTabs);

        final int[] tabActiva = {0}; // 0: Maquinas/IPs, 1: Subredes, 2: Forwarding
        final LinearLayout[] vistasTabs = new LinearLayout[3];

        Runnable[] actualizarTabs = new Runnable[1];

        for (int i = 0; i < 3; i++) {
            final int tIdx = i;
            TextView tabBtn = new TextView(this);
            tabBtn.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
            tabBtn.setTextSize(11);
            tabBtn.setPadding(dp(8), dp(6), dp(8), dp(6));
            tabBtn.setGravity(Gravity.CENTER);
            if (i == 0) tabBtn.setText("⊞ MÁQUINAS / IPS");
            else if (i == 1) tabBtn.setText("⑂ SUBREDES");
            else tabBtn.setText("⇄ REENVÍO PUERTOS");

            LinearLayout.LayoutParams lpT = new LinearLayout.LayoutParams(0, -2, 1.0f);
            if (i > 0) lpT.leftMargin = dp(4);
            barraTabs.addView(tabBtn, lpT);

            tabBtn.setOnClickListener(v -> {
                tabActiva[0] = tIdx;
                if (actualizarTabs[0] != null) actualizarTabs[0].run();
            });
        }

        // Contenedor principal de pestañas
        LinearLayout contPestañas = new LinearLayout(this);
        contPestañas.setOrientation(LinearLayout.VERTICAL);
        layout.addView(contPestañas, new LinearLayout.LayoutParams(-1, dp(260)));

        // --- PESTAÑA 0: MÁQUINAS E IPS ---
        vistasTabs[0] = new LinearLayout(this);
        vistasTabs[0].setOrientation(LinearLayout.VERTICAL);

        ScrollView scrollIps = new ScrollView(this);
        LinearLayout contIps = new LinearLayout(this);
        contIps.setOrientation(LinearLayout.VERTICAL);
        scrollIps.addView(contIps);
        vistasTabs[0].addView(scrollIps, new LinearLayout.LayoutParams(-1, -1));

        Runnable recargarIps = () -> {
            contIps.removeAllViews();
            List<SistemaLinux.Instancia> insts = SistemaLinux.listarInstancias(this);
            List<RedManager.Subred> subs = RedManager.listarSubredes(this);
            Map<String, RedManager.AsignacionIp> asigs = RedManager.listarAsignaciones(this);

            if (insts.isEmpty()) {
                contIps.addView(texto("  No hay entornos creados.", 11, false, TEXTO_MUTED));
                return;
            }

            for (SistemaLinux.Instancia inst : insts) {
                LinearLayout tarjeta = new LinearLayout(this);
                tarjeta.setOrientation(LinearLayout.VERTICAL);
                tarjeta.setPadding(dp(10), dp(8), dp(10), dp(8));
                tarjeta.setBackground(crearFondo(0xff16202c, BORDE_NORMAL, dp(6), dp(1)));

                TextView titInst = texto("● " + inst.nombre + " (" + inst.id + ")", 12, true, ACCENTO_VERDE);
                tarjeta.addView(titInst);

                LinearLayout filaCfg = new LinearLayout(this);
                filaCfg.setOrientation(LinearLayout.HORIZONTAL);
                filaCfg.setGravity(Gravity.CENTER_VERTICAL);
                filaCfg.setPadding(0, dp(4), 0, 0);

                // Selector de subred
                android.widget.Spinner spSub = new android.widget.Spinner(this);
                List<String> nomSubs = new ArrayList<>();
                int selSubIdx = 0;
                RedManager.AsignacionIp asigActual = asigs.get(inst.id);
                for (int sIdx = 0; sIdx < subs.size(); sIdx++) {
                    RedManager.Subred s = subs.get(sIdx);
                    nomSubs.add(s.nombre + " [" + s.cidr + "]");
                    if (asigActual != null && s.id.equals(asigActual.subredId)) {
                        selSubIdx = sIdx;
                    }
                }
                android.widget.ArrayAdapter<String> subAdp = new android.widget.ArrayAdapter<>(
                        this, android.R.layout.simple_spinner_dropdown_item, nomSubs);
                spSub.setAdapter(subAdp);
                spSub.setSelection(selSubIdx);
                filaCfg.addView(spSub, new LinearLayout.LayoutParams(0, -2, 1.0f));

                // Campo de IP
                EditText inIp = new EditText(this);
                inIp.setText(RedManager.ipParaInstancia(this, inst.id));
                inIp.setTextColor(TEXTO_CLARO);
                inIp.setTypeface(Typeface.MONOSPACE);
                inIp.setTextSize(12);
                inIp.setBackground(crearFondo(0xff0d131a, BORDE_BOTON, dp(6), dp(1)));
                inIp.setPadding(dp(8), dp(4), dp(8), dp(4));
                LinearLayout.LayoutParams lpInIp = new LinearLayout.LayoutParams(dp(110), -2);
                lpInIp.leftMargin = dp(4);
                lpInIp.rightMargin = dp(4);
                filaCfg.addView(inIp, lpInIp);

                // Botón guardar IP
                TextView btnSaveIp = crearBotonChip("💾", ACCENTO_CIAN, () -> {
                    String ipVal = inIp.getText().toString().trim();
                    int subIdx = spSub.getSelectedItemPosition();
                    String subId = (subIdx >= 0 && subIdx < subs.size()) ? subs.get(subIdx).id : "sub_default";
                    if (!ipVal.isEmpty()) {
                        RedManager.asignarIp(this, inst.id, subId, ipVal);
                        Toast.makeText(this, "IP asignada a " + inst.nombre + ": " + ipVal, Toast.LENGTH_SHORT).show();
                    }
                });
                filaCfg.addView(btnSaveIp);

                tarjeta.addView(filaCfg);

                LinearLayout.LayoutParams lpT = new LinearLayout.LayoutParams(-1, -2);
                lpT.bottomMargin = dp(6);
                contIps.addView(tarjeta, lpT);
            }
        };

        // --- PESTAÑA 1: SUBREDES ---
        vistasTabs[1] = new LinearLayout(this);
        vistasTabs[1].setOrientation(LinearLayout.VERTICAL);

        ScrollView scrollSubs = new ScrollView(this);
        LinearLayout contSubs = new LinearLayout(this);
        contSubs.setOrientation(LinearLayout.VERTICAL);
        scrollSubs.addView(contSubs);
        vistasTabs[1].addView(scrollSubs, new LinearLayout.LayoutParams(-1, dp(150)));

        Runnable[] recargarSubs = new Runnable[1];
        recargarSubs[0] = () -> {
            contSubs.removeAllViews();
            List<RedManager.Subred> subs = RedManager.listarSubredes(this);
            for (RedManager.Subred s : subs) {
                LinearLayout fSub = new LinearLayout(this);
                fSub.setOrientation(LinearLayout.HORIZONTAL);
                fSub.setGravity(Gravity.CENTER_VERTICAL);
                fSub.setPadding(dp(8), dp(6), dp(8), dp(6));
                fSub.setBackground(crearFondo(0xff16202c, BORDE_NORMAL, dp(6), dp(1)));

                TextView inf = texto("⑂ " + s.nombre + " (" + s.cidr + ")", 12, true, ACCENTO_CIAN);
                fSub.addView(inf, new LinearLayout.LayoutParams(0, -2, 1.0f));

                if (subs.size() > 1) {
                    TextView btnDel = crearBotonChip("✕", ACCENTO_ROJO, () -> {
                        RedManager.eliminarSubred(this, s.id);
                        recargarSubs[0].run();
                        recargarIps.run();
                    });
                    fSub.addView(btnDel);
                }

                LinearLayout.LayoutParams lpF = new LinearLayout.LayoutParams(-1, -2);
                lpF.bottomMargin = dp(4);
                contSubs.addView(fSub, lpF);
            }
        };

        TextView titNuevaSub = texto("❯ Crear nueva subred:", 12, true, ACCENTO_AMBAR);
        LinearLayout.LayoutParams lpTNS = new LinearLayout.LayoutParams(-1, -2);
        lpTNS.topMargin = dp(6);
        vistasTabs[1].addView(titNuevaSub, lpTNS);

        LinearLayout formSub = new LinearLayout(this);
        formSub.setOrientation(LinearLayout.HORIZONTAL);
        formSub.setGravity(Gravity.CENTER_VERTICAL);

        EditText inNomSub = new EditText(this);
        inNomSub.setHint("Nombre (ej. Servidores)");
        inNomSub.setHintTextColor(0xff556272);
        inNomSub.setTextColor(TEXTO_CLARO);
        inNomSub.setTypeface(Typeface.MONOSPACE);
        inNomSub.setTextSize(12);
        inNomSub.setBackground(crearFondo(0xff16202c, BORDE_BOTON, dp(6), dp(1)));
        inNomSub.setPadding(dp(8), dp(6), dp(8), dp(6));
        formSub.addView(inNomSub, new LinearLayout.LayoutParams(0, -2, 1.2f));

        EditText inCidrSub = new EditText(this);
        inCidrSub.setHint("CIDR (10.0.1.0/24)");
        inCidrSub.setHintTextColor(0xff556272);
        inCidrSub.setTextColor(TEXTO_CLARO);
        inCidrSub.setTypeface(Typeface.MONOSPACE);
        inCidrSub.setTextSize(12);
        inCidrSub.setBackground(crearFondo(0xff16202c, BORDE_BOTON, dp(6), dp(1)));
        inCidrSub.setPadding(dp(8), dp(6), dp(8), dp(6));
        LinearLayout.LayoutParams lpCidr = new LinearLayout.LayoutParams(0, -2, 1.0f);
        lpCidr.leftMargin = dp(4);
        lpCidr.rightMargin = dp(4);
        formSub.addView(inCidrSub, lpCidr);

        TextView btnCrearSub = crearBotonChip("＋ CREAR", ACCENTO_VERDE, () -> {
            String nom = inNomSub.getText().toString().trim();
            String cidr = inCidrSub.getText().toString().trim();
            if (nom.isEmpty() || cidr.isEmpty()) {
                Toast.makeText(this, "Completa nombre y rango CIDR", Toast.LENGTH_SHORT).show();
                return;
            }
            RedManager.agregarSubred(this, nom, cidr);
            inNomSub.setText("");
            inCidrSub.setText("");
            recargarSubs[0].run();
            recargarIps.run();
            Toast.makeText(this, "Subred creada: " + nom, Toast.LENGTH_SHORT).show();
        });
        formSub.addView(btnCrearSub);

        LinearLayout.LayoutParams lpFSub = new LinearLayout.LayoutParams(-1, -2);
        lpFSub.topMargin = dp(4);
        vistasTabs[1].addView(formSub, lpFSub);

        // --- PESTAÑA 2: PORT FORWARDING ---
        vistasTabs[2] = new LinearLayout(this);
        vistasTabs[2].setOrientation(LinearLayout.VERTICAL);

        android.widget.CheckBox cbHabilitado = new android.widget.CheckBox(this);
        cbHabilitado.setText("Habilitar reenvío activo");
        cbHabilitado.setTextColor(TEXTO_CLARO);
        cbHabilitado.setTypeface(Typeface.MONOSPACE);
        cbHabilitado.setChecked(RedManager.esHabilitado(this));
        cbHabilitado.setOnCheckedChangeListener((bv, isChecked) -> RedManager.setHabilitado(this, isChecked));
        vistasTabs[2].addView(cbHabilitado);

        // Sección especial: SSH Puerto 22 real (Wi-Fi directo sin root)
        LinearLayout boxP22 = new LinearLayout(this);
        boxP22.setOrientation(LinearLayout.VERTICAL);
        boxP22.setPadding(dp(8), dp(6), dp(8), dp(6));
        boxP22.setBackground(crearFondo(0xff131f2d, BORDE_NORMAL, dp(6), dp(1)));

        LinearLayout filaP22Header = new LinearLayout(this);
        filaP22Header.setOrientation(LinearLayout.HORIZONTAL);
        filaP22Header.setGravity(Gravity.CENTER_VERTICAL);

        TextView tituloP22 = texto("⚡ SSH PUERTO 22 (WI-FI SIN ROOT)", 11, true, ACCENTO_CIAN);
        filaP22Header.addView(tituloP22, new LinearLayout.LayoutParams(0, -2, 1.0f));

        TextView badgeP22 = texto(RedManager.estaProxy22Activo() ? "● ACTIVO" : "○ INACTIVO", 10, true,
                RedManager.estaProxy22Activo() ? ACCENTO_VERDE : TEXTO_MUTED);
        filaP22Header.addView(badgeP22);
        boxP22.addView(filaP22Header);

        TextView descP22 = texto("Proxy shell UID 2000 en 0.0.0.0:22. Conecta directo: ssh user@<ip>", 10, false, TEXTO_MUTED);
        LinearLayout.LayoutParams lpDescP22 = new LinearLayout.LayoutParams(-1, -2);
        lpDescP22.topMargin = dp(2);
        lpDescP22.bottomMargin = dp(4);
        boxP22.addView(descP22, lpDescP22);

        LinearLayout filaP22Acciones = new LinearLayout(this);
        filaP22Acciones.setOrientation(LinearLayout.HORIZONTAL);
        filaP22Acciones.setGravity(Gravity.CENTER_VERTICAL);

        TextView lblDest = texto("Destino: ", 11, false, TEXTO_MUTED);
        filaP22Acciones.addView(lblDest);

        android.widget.Spinner spinP22 = new android.widget.Spinner(this);
        List<SistemaLinux.Instancia> instsP22 = SistemaLinux.listarInstancias(this);
        List<String> nombresP22 = new ArrayList<>();
        int selIdx = 0;
        String curTarget = RedManager.obtenerProxy22Target(this);
        for (int i = 0; i < instsP22.size(); i++) {
            SistemaLinux.Instancia inst = instsP22.get(i);
            nombresP22.add(inst.nombre + " (" + RedManager.ipParaInstancia(this, inst.id) + ")");
            if (inst.id.equals(curTarget)) selIdx = i;
        }
        android.widget.ArrayAdapter<String> adaptP22 = new android.widget.ArrayAdapter<>(
                this, android.R.layout.simple_spinner_dropdown_item, nombresP22);
        spinP22.setAdapter(adaptP22);
        if (selIdx >= 0 && selIdx < nombresP22.size()) spinP22.setSelection(selIdx);
        spinP22.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(android.widget.AdapterView<?> parent, View view, int position, long id) {
                if (position >= 0 && position < instsP22.size()) {
                    RedManager.setProxy22Target(SistemaActivity.this, instsP22.get(position).id);
                }
            }
            @Override
            public void onNothingSelected(android.widget.AdapterView<?> parent) { }
        });
        filaP22Acciones.addView(spinP22, new LinearLayout.LayoutParams(0, -2, 1.0f));

        TextView btnRefrescoP22 = crearBotonChip("REVISAR", BORDE_BOTON, () -> {
            boolean activo = RedManager.estaProxy22Activo();
            badgeP22.setText(activo ? "● ACTIVO" : "○ INACTIVO");
            badgeP22.setTextColor(activo ? ACCENTO_VERDE : TEXTO_MUTED);
        });
        filaP22Acciones.addView(btnRefrescoP22);

        boxP22.addView(filaP22Acciones);

        LinearLayout.LayoutParams lpBoxP22 = new LinearLayout.LayoutParams(-1, -2);
        lpBoxP22.topMargin = dp(4);
        lpBoxP22.bottomMargin = dp(6);
        vistasTabs[2].addView(boxP22, lpBoxP22);

        ScrollView scrollReglas = new ScrollView(this);
        LinearLayout contReglas = new LinearLayout(this);
        contReglas.setOrientation(LinearLayout.VERTICAL);
        scrollReglas.addView(contReglas);
        vistasTabs[2].addView(scrollReglas, new LinearLayout.LayoutParams(-1, dp(130)));

        Runnable[] recargarReglas = new Runnable[1];
        recargarReglas[0] = () -> {
            contReglas.removeAllViews();
            List<RedManager.Regla> reglas = RedManager.listarReglas(this);
            if (reglas.isEmpty()) {
                contReglas.addView(texto("  No hay reglas de reenvío activas.", 11, false, TEXTO_MUTED));
            } else {
                for (RedManager.Regla r : reglas) {
                    LinearLayout fila = new LinearLayout(this);
                    fila.setOrientation(LinearLayout.HORIZONTAL);
                    fila.setGravity(Gravity.CENTER_VERTICAL);
                    fila.setPadding(dp(8), dp(6), dp(8), dp(6));
                    fila.setBackground(crearFondo(0xff16202c, BORDE_NORMAL, dp(6), dp(1)));

                    String ipInst = RedManager.ipParaInstancia(this, r.instanciaId);
                    TextView info = texto(":" + r.puertoExterno + " ➜ " + r.instanciaId + " (" + ipInst + "):" + r.puertoInterno, 11, true, r.activa ? ACCENTO_VERDE : TEXTO_MUTED);
                    fila.addView(info, new LinearLayout.LayoutParams(0, -2, 1.0f));

                    TextView btnDel = crearBotonChip("✕", ACCENTO_ROJO, () -> {
                        reglas.remove(r);
                        RedManager.guardarReglas(this, reglas);
                        RedManager.actualizar(this);
                        recargarReglas[0].run();
                    });
                    fila.addView(btnDel);

                    LinearLayout.LayoutParams lpFila = new LinearLayout.LayoutParams(-1, -2);
                    lpFila.bottomMargin = dp(4);
                    contReglas.addView(fila, lpFila);
                }
            }
        };

        LinearLayout formFwd = new LinearLayout(this);
        formFwd.setOrientation(LinearLayout.HORIZONTAL);
        formFwd.setGravity(Gravity.CENTER_VERTICAL);

        EditText inExt = new EditText(this);
        inExt.setHint("Ext(8022)");
        inExt.setHintTextColor(0xff556272);
        inExt.setTextColor(TEXTO_CLARO);
        inExt.setTypeface(Typeface.MONOSPACE);
        inExt.setTextSize(12);
        inExt.setInputType(InputType.TYPE_CLASS_NUMBER);
        inExt.setBackground(crearFondo(0xff16202c, BORDE_BOTON, dp(6), dp(1)));
        inExt.setPadding(dp(6), dp(6), dp(6), dp(6));
        formFwd.addView(inExt, new LinearLayout.LayoutParams(dp(80), -2));

        TextView flecha = texto(" ➜ ", 12, true, TEXTO_MUTED);
        formFwd.addView(flecha);

        List<SistemaLinux.Instancia> insts = SistemaLinux.listarInstancias(this);
        android.widget.Spinner spinInst = new android.widget.Spinner(this);
        List<String> nombresInst = new ArrayList<>();
        for (SistemaLinux.Instancia i : insts) nombresInst.add(i.nombre + " (" + RedManager.ipParaInstancia(this, i.id) + ")");
        android.widget.ArrayAdapter<String> adapter = new android.widget.ArrayAdapter<>(
                this, android.R.layout.simple_spinner_dropdown_item, nombresInst);
        spinInst.setAdapter(adapter);
        formFwd.addView(spinInst, new LinearLayout.LayoutParams(0, -2, 1.0f));

        EditText inInt = new EditText(this);
        inInt.setHint("Int(22)");
        inInt.setHintTextColor(0xff556272);
        inInt.setTextColor(TEXTO_CLARO);
        inInt.setTypeface(Typeface.MONOSPACE);
        inInt.setTextSize(12);
        inInt.setInputType(InputType.TYPE_CLASS_NUMBER);
        inInt.setBackground(crearFondo(0xff16202c, BORDE_BOTON, dp(6), dp(1)));
        inInt.setPadding(dp(6), dp(6), dp(6), dp(6));
        formFwd.addView(inInt, new LinearLayout.LayoutParams(dp(70), -2));

        TextView btnAddFwd = crearBotonChip("＋ AGREGAR", ACCENTO_VERDE, () -> {
            String sExt = inExt.getText().toString().trim();
            String sInt = inInt.getText().toString().trim();
            int idx = spinInst.getSelectedItemPosition();
            if (sExt.isEmpty() || sInt.isEmpty() || idx < 0 || idx >= insts.size()) {
                Toast.makeText(this, "Completa los campos", Toast.LENGTH_SHORT).show();
                return;
            }
            try {
                int pExt = Integer.parseInt(sExt);
                int pInt = Integer.parseInt(sInt);
                String instId = insts.get(idx).id;
                List<RedManager.Regla> reglas = RedManager.listarReglas(this);
                reglas.add(new RedManager.Regla(String.valueOf(System.currentTimeMillis()), pExt, instId, pInt, true));
                RedManager.guardarReglas(this, reglas);
                RedManager.actualizar(this);
                inExt.setText("");
                inInt.setText("");
                recargarReglas[0].run();
                Toast.makeText(this, "Regla: :" + pExt + " ➜ " + instId + ":" + pInt, Toast.LENGTH_SHORT).show();
            } catch (Exception ex) {
                Toast.makeText(this, "Puerto inválido", Toast.LENGTH_SHORT).show();
            }
        });
        formFwd.addView(btnAddFwd);

        LinearLayout.LayoutParams lpFFwd = new LinearLayout.LayoutParams(-1, -2);
        lpFFwd.topMargin = dp(6);
        vistasTabs[2].addView(formFwd, lpFFwd);

        // Coordinador de visibilidad de pestañas
        actualizarTabs[0] = () -> {
            for (int i = 0; i < 3; i++) {
                TextView tBtn = (TextView) barraTabs.getChildAt(i);
                boolean activa = (i == tabActiva[0]);
                tBtn.setBackground(crearFondo(activa ? 0xff162638 : 0xff101720, activa ? ACCENTO_CIAN : BORDE_BOTON, dp(6), dp(1)));
                tBtn.setTextColor(activa ? ACCENTO_CIAN : TEXTO_MUTED);
            }
            contPestañas.removeAllViews();
            contPestañas.addView(vistasTabs[tabActiva[0]], new LinearLayout.LayoutParams(-1, -1));
            if (tabActiva[0] == 0) recargarIps.run();
            else if (tabActiva[0] == 1) recargarSubs[0].run();
            else if (tabActiva[0] == 2) recargarReglas[0].run();
        };

        actualizarTabs[0].run();

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setView(layout)
                .setPositiveButton("CERRAR", null)
                .create();
        dialog.show();
    }

    private TextView crearBotonChip(String texto, int colorAcento, Runnable accion) {
        TextView b = new TextView(this);
        b.setText(texto);
        b.setTextColor(colorAcento);
        b.setTextSize(12);
        b.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        b.setBackground(crearFondo(0xff101721, colorAcento, dp(6), dp(1)));
        b.setPadding(dp(12), dp(6), dp(12), dp(6));
        b.setClickable(true);
        b.setOnClickListener(v -> accion.run());
        return b;
    }

    private TextView textoBadge(String t, int color) {
        TextView b = new TextView(this);
        b.setText(t);
        b.setTextColor(color);
        b.setTextSize(11);
        b.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        b.setBackground(crearFondo(0xff141d27, color, dp(4), dp(1)));
        b.setPadding(dp(8), dp(3), dp(8), dp(3));
        return b;
    }

    private TextView texto(String contenido, float sp, boolean negrita, int color) {
        TextView t = new TextView(this);
        t.setText(contenido);
        t.setTextSize(sp);
        t.setTypeface(Typeface.MONOSPACE, negrita ? Typeface.BOLD : Typeface.NORMAL);
        t.setTextColor(color);
        return t;
    }

    private View espacioHorizontal(int w) {
        View v = new View(this);
        v.setLayoutParams(new LinearLayout.LayoutParams(w, 1));
        return v;
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

    // --- TerminalViewClient ---

    @Override
    public float onScale(float escala) {
        if (escala < 0.9f || escala > 1.1f) {
            int nuevo = Math.max(6, Math.min(48, Math.round(tamLetra * (escala > 1 ? 1.1f : 0.9f))));
            if (nuevo != tamLetra) {
                tamLetra = nuevo;
                if (vistaTerminal != null) vistaTerminal.setTextSize(tamLetra);
            }
            return 1.0f;
        }
        return escala;
    }

    @Override
    public void onSingleTapUp(MotionEvent e) {
        if (vistaTerminal != null) {
            vistaTerminal.requestFocus();
            getSystemService(InputMethodManager.class).showSoftInput(vistaTerminal, 0);
        }
    }

    @Override public boolean shouldBackButtonBeMappedToEscape() { return false; }
    @Override public boolean shouldEnforceCharBasedInput() { return true; }
    @Override public boolean shouldUseCtrlSpaceWorkaround() { return false; }
    @Override public boolean isTerminalViewSelected() { return true; }
    @Override public void copyModeChanged(boolean copyMode) { }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent e, TerminalSession s) {
        if (keyCode == KeyEvent.KEYCODE_ENTER && (s == null || !s.isRunning())) {
            iniciarConsola();
            return true;
        }
        return false;
    }

    @Override public boolean onKeyUp(int keyCode, KeyEvent e) { return false; }
    @Override public boolean onLongPress(MotionEvent e) { return false; }

    @Override
    public boolean readControlKey() {
        boolean r = ctrl;
        if (r) { ctrl = false; marcarModificadores(); }
        return r;
    }

    @Override
    public boolean readAltKey() {
        boolean r = alt;
        if (r) { alt = false; marcarModificadores(); }
        return r;
    }

    @Override public boolean readShiftKey() { return false; }
    @Override public boolean readFnKey() { return false; }

    @Override
    public boolean onCodePoint(int codePoint, boolean ctrlDown, TerminalSession s) {
        if ((codePoint == '\n' || codePoint == '\r') && (s == null || !s.isRunning())) {
            iniciarConsola();
            return true;
        }
        return false;
    }

    @Override public void onEmulatorSet() { }

    // --- TerminalSessionClient ---

    @Override
    public void onTextChanged(TerminalSession s) {
        if (vistaTerminal != null) vistaTerminal.onScreenUpdated();
    }

    @Override public void onTitleChanged(TerminalSession s) { }

    @Override
    public void onSessionFinished(TerminalSession s) {
        if (vistaTerminal != null) vistaTerminal.onScreenUpdated();
    }

    @Override
    public void onCopyTextToClipboard(TerminalSession s, String texto) {
        getSystemService(ClipboardManager.class).setPrimaryClip(ClipData.newPlainText("consola", texto));
    }

    @Override
    public void onPasteTextFromClipboard(TerminalSession s) {
        ClipData clip = getSystemService(ClipboardManager.class).getPrimaryClip();
        if (clip == null || clip.getItemCount() == 0) return;
        CharSequence texto = clip.getItemAt(0).coerceToText(this);
        if (texto != null && s.getEmulator() != null) s.getEmulator().paste(texto.toString());
    }

    @Override public void onBell(TerminalSession s) { }
    @Override public void onColorsChanged(TerminalSession s) { if (vistaTerminal != null) vistaTerminal.invalidate(); }
    @Override public void onTerminalCursorStateChange(boolean visible) { }
    @Override public Integer getTerminalCursorStyle() { return 0; }

    @Override public void logError(String tag, String msg) { Log.e(TAG, tag + ": " + msg); }
    @Override public void logWarn(String tag, String msg) { Log.w(TAG, tag + ": " + msg); }
    @Override public void logInfo(String tag, String msg) { Log.i(TAG, tag + ": " + msg); }
    @Override public void logDebug(String tag, String msg) { }
    @Override public void logVerbose(String tag, String msg) { }
    @Override public void logStackTraceWithMessage(String tag, String msg, Exception e) { Log.e(TAG, tag + ": " + msg, e); }
    @Override public void logStackTrace(String tag, Exception e) { Log.e(TAG, tag, e); }
}
