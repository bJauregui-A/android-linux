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
import java.util.List;

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
    private TerminalView vistaTerminal;
    private TerminalSession sesionConsola;
    private int tamLetra;
    private boolean ctrl, alt;
    private TextView botonCtrl, botonAlt;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        LinearLayout raiz = new LinearLayout(this);
        raiz.setOrientation(LinearLayout.VERTICAL);
        raiz.setBackgroundColor(FONDO_OSCURO);
        raiz.setPadding(dp(14), dp(16), dp(14), dp(10));

        // Cabecera de la sección de entornos (con botón compacto para crear nueva instancia)
        LinearLayout cabeceraInstancias = new LinearLayout(this);
        cabeceraInstancias.setOrientation(LinearLayout.HORIZONTAL);
        cabeceraInstancias.setGravity(Gravity.CENTER_VERTICAL);

        TextView tituloSeccion = texto("❯ ENTORNOS DISPONIBLES (INSTANCIAS)", 13, true, ACCENTO_CIAN);
        cabeceraInstancias.addView(tituloSeccion, new LinearLayout.LayoutParams(0, -2, 1.0f));

        TextView btnCrear = crearBotonChip("＋ CREAR", ACCENTO_PURPURA, this::mostrarDialogoCreacion);
        cabeceraInstancias.addView(btnCrear);

        LinearLayout.LayoutParams lpCab = new LinearLayout.LayoutParams(-1, -2);
        lpCab.bottomMargin = dp(10);
        raiz.addView(cabeceraInstancias, lpCab);

        // Contenedor scrollable para las tarjetas de instancias
        ScrollView scrollInstancias = new ScrollView(this);
        scrollInstancias.setFillViewport(true);
        contenedorInstancias = new LinearLayout(this);
        contenedorInstancias.setOrientation(LinearLayout.VERTICAL);
        scrollInstancias.addView(contenedorInstancias);

        // Altura adaptable para las instancias: máximo ~200dp para no tapar la consola
        LinearLayout.LayoutParams lpScrollInst = new LinearLayout.LayoutParams(-1, -2);
        lpScrollInst.bottomMargin = dp(10);
        raiz.addView(scrollInstancias, lpScrollInst);

        // Cabecera de la consola real
        TextView tituloConsola = texto("❯ CONSOLA REAL (files/)", 12, true, ACCENTO_VERDE);
        LinearLayout.LayoutParams lpTitConsola = new LinearLayout.LayoutParams(-1, -2);
        lpTitConsola.bottomMargin = dp(6);
        raiz.addView(tituloConsola, lpTitConsola);

        // Vista de la terminal de Termux conectada a una shell /system/bin/sh interactiva
        vistaTerminal = new TerminalView(this, null);
        vistaTerminal.setTerminalViewClient(this);
        vistaTerminal.setFocusable(true);
        vistaTerminal.setFocusableInTouchMode(true);
        tamLetra = (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, 12, getResources().getDisplayMetrics());
        vistaTerminal.setTextSize(tamLetra);
        vistaTerminal.setTypeface(Typeface.MONOSPACE);

        LinearLayout contenedorTerminal = new LinearLayout(this);
        contenedorTerminal.setOrientation(LinearLayout.VERTICAL);
        contenedorTerminal.setBackground(crearFondo(0xff0a0e14, BORDE_NORMAL, dp(8), dp(1)));
        contenedorTerminal.setPadding(dp(6), dp(6), dp(6), dp(6));
        contenedorTerminal.addView(vistaTerminal, new LinearLayout.LayoutParams(-1, 0, 1.0f));
        contenedorTerminal.addView(filaTeclas(), new LinearLayout.LayoutParams(-1, -2));

        raiz.addView(contenedorTerminal, new LinearLayout.LayoutParams(-1, 0, 1.0f));

        // Ajuste dinámico para barras del sistema y teclado virtual (IME)
        raiz.setOnApplyWindowInsetsListener((v, insets) -> {
            android.graphics.Insets i = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.ime());
            v.setPadding(i.left + dp(14), i.top + dp(10), i.right + dp(14), i.bottom + dp(6));
            return WindowInsets.CONSUMED;
        });

        setContentView(raiz);

        actualizarLista();
        iniciarConsola();
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
        File filesDir = getFilesDir();
        String cwd = filesDir.getAbsolutePath();
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
        vistaTerminal.attachSession(sesionConsola);
        vistaTerminal.onScreenUpdated();
    }

    private LinearLayout filaTeclas() {
        LinearLayout fila = new LinearLayout(this);
        fila.setBackgroundColor(0xff121820);
        String[] teclas = {"⌨", "ESC", "TAB", "CTRL", "ALT", "←", "↓", "↑", "→"};
        for (String t : teclas) {
            TextView b = new TextView(this);
            b.setText(t);
            b.setTextColor(TEXTO_CLARO);
            b.setTypeface(Typeface.MONOSPACE);
            b.setGravity(Gravity.CENTER);
            b.setPadding(0, dp(8), 0, dp(8));
            b.setOnClickListener(v -> tecla(t));
            if (t.equals("CTRL")) botonCtrl = b;
            if (t.equals("ALT")) botonAlt = b;
            fila.addView(b, new LinearLayout.LayoutParams(0, -2, 1.0f));
        }
        return fila;
    }

    private void tecla(String t) {
        if (vistaTerminal == null) return;
        switch (t) {
            case "⌨":
                vistaTerminal.requestFocus();
                getSystemService(InputMethodManager.class).showSoftInput(vistaTerminal, 0);
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
        if (botonCtrl != null) botonCtrl.setBackgroundColor(ctrl ? 0xff3d6aa5 : 0);
        if (botonAlt != null) botonAlt.setBackgroundColor(alt ? 0xff3d6aa5 : 0);
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
        card.setBackground(crearFondo(
                activa ? PANEL_ACTIVO : PANEL_CARD,
                activa ? BORDE_ACTIVO : BORDE_NORMAL,
                dp(8),
                activa ? dp(2) : dp(1)));

        LinearLayout.LayoutParams lpCard = new LinearLayout.LayoutParams(-1, -2);
        lpCard.bottomMargin = dp(8);
        card.setLayoutParams(lpCard);

        // Header de la tarjeta: Badge de Estado y Título
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);

        TextView tagActivo = textoBadge(activa ? "● [ ACTIVO ]" : "○ [ INACTIVO ]", activa ? ACCENTO_VERDE : TEXTO_MUTED);
        header.addView(tagActivo);

        TextView tagInst = textoBadge(instalada ? "LISTO" : "PENDIENTE", instalada ? ACCENTO_CIAN : ACCENTO_AMBAR);
        LinearLayout.LayoutParams lpInst = new LinearLayout.LayoutParams(-2, -2);
        lpInst.leftMargin = dp(8);
        header.addView(tagInst, lpInst);

        boolean corriendo = TerminalService.tieneSesionActiva() && inst.id.equals(TerminalService.instanciaActivaId());
        if (corriendo) {
            TextView tagCorriendo = textoBadge("● EN EJECUCIÓN", ACCENTO_VERDE);
            LinearLayout.LayoutParams lpCorr = new LinearLayout.LayoutParams(-2, -2);
            lpCorr.leftMargin = dp(8);
            header.addView(tagCorriendo, lpCorr);
        }

        card.addView(header);

        // Nombre de la instancia y ruta
        TextView nombre = texto("❯ [" + index + "] " + inst.nombre, 15, true, activa ? TEXTO_CLARO : 0xffcbd5e1);
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

        // Botón INICIAR ESCRITORIO o VOLVER si ya está corriendo
        String textoBoton = corriendo ? "▶ VOLVER" : "▶ ESCRITORIO";
        TextView btnIniciar = crearBotonChip(textoBoton, ACCENTO_VERDE, () -> {
            activarYEjecutar(inst.id, true);
        });
        acciones.addView(btnIniciar);

        acciones.addView(espacioHorizontal(dp(8)));

        // Botón TERMINAL
        TextView btnTerminal = crearBotonChip(">_ TERMINAL", ACCENTO_AZUL, () -> {
            activarYEjecutar(inst.id, false);
        });
        acciones.addView(btnTerminal);

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
            }
        });

        return card;
    }

    private void activarYEjecutar(String id, boolean escritorio) {
        SistemaLinux.seleccionarInstancia(this, id);
        if (escritorio) {
            startActivity(new Intent(this, WaylandActivity.class));
        } else {
            startActivity(new Intent(this, TerminalActivity.class));
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
        rbArch.setText("Arch Linux ARM (Probado y funcional)");
        rbArch.setTextColor(TEXTO_CLARO);
        rbArch.setTypeface(Typeface.MONOSPACE);
        rbArch.setChecked(true);
        rg.addView(rbArch);

        RadioButton rbDebian = new RadioButton(this);
        rbDebian.setText("Debian ARM64 (Próximamente)");
        rbDebian.setTextColor(TEXTO_MUTED);
        rbDebian.setTypeface(Typeface.MONOSPACE);
        rbDebian.setEnabled(false);
        rg.addView(rbDebian);

        RadioButton rbUbuntu = new RadioButton(this);
        rbUbuntu.setText("Ubuntu ARM64 (Próximamente)");
        rbUbuntu.setTextColor(TEXTO_MUTED);
        rbUbuntu.setTypeface(Typeface.MONOSPACE);
        rbUbuntu.setEnabled(false);
        rg.addView(rbUbuntu);

        layout.addView(rg);

        TextView lblNombre = texto("❯ 2. Nombre del Entorno:", 13, true, ACCENTO_CIAN);
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
            dialog.dismiss();
            try {
                SistemaLinux.Instancia nueva = SistemaLinux.crearInstancia(this, nom, SistemaLinux.ARCH);
                actualizarLista();
                activarYEjecutar(nueva.id, false);
            } catch (Exception e) {
                Toast.makeText(this, "Error: " + e.getMessage(), Toast.LENGTH_LONG).show();
            }
        });
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
