package dev.ben4shot.glibcprueba;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.IBinder;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowInsets;
import android.view.inputmethod.InputMethodManager;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.termux.terminal.TerminalSession;
import com.termux.view.TerminalView;
import com.termux.view.TerminalViewClient;

// Terminal a pantalla completa: la vista de Termux (solo el emulador) conectada a la
// sesión de bash que mantiene TerminalService. Fila de teclas extra abajo.
public class TerminalActivity extends Activity implements TerminalViewClient {
    private static final String TAG = "TERMINAL";

    private TerminalView vista;
    private TerminalService servicio;
    private int tamLetra;
    private boolean ctrl, alt;
    private TextView botonCtrl, botonAlt;

    private final ServiceConnection conexion = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder binder) {
            servicio = ((TerminalService.Local) binder).servicio();
            servicio.setVista(vista);
            vista.attachSession(servicio.sesion());
            vista.requestFocus();
        }

        @Override
        public void onServiceDisconnected(ComponentName name) { servicio = null; }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != 0) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 0);
        }

        vista = new TerminalView(this, null);
        vista.setTerminalViewClient(this);
        vista.setFocusable(true);
        vista.setFocusableInTouchMode(true);
        tamLetra = (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, 12, getResources().getDisplayMetrics());
        vista.setTextSize(tamLetra);
        vista.setTypeface(Typeface.MONOSPACE);

        LinearLayout raiz = new LinearLayout(this);
        raiz.setOrientation(LinearLayout.VERTICAL);
        raiz.setBackgroundColor(Color.BLACK);
        raiz.addView(vista, new LinearLayout.LayoutParams(-1, 0, 1));
        raiz.addView(filaTeclas(), new LinearLayout.LayoutParams(-1, -2));
        // edge-to-edge (targetSdk 35+): dejar espacio a las barras del sistema y al teclado
        raiz.setOnApplyWindowInsetsListener((v, insets) -> {
            android.graphics.Insets i = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.ime());
            v.setPadding(i.left, i.top, i.right, i.bottom);
            return WindowInsets.CONSUMED;
        });
        setContentView(raiz);

        Intent intent = new Intent(this, TerminalService.class);
        startForegroundService(intent);
        bindService(intent, conexion, Context.BIND_AUTO_CREATE);
    }

    @Override
    protected void onDestroy() {
        if (servicio != null) servicio.setVista(null);
        unbindService(conexion);
        super.onDestroy();
    }

    private LinearLayout filaTeclas() {
        LinearLayout fila = new LinearLayout(this);
        fila.setBackgroundColor(0xff1a1a1a);
        String[] teclas = {"⌨", "ESC", "TAB", "CTRL", "ALT", "-", "/", "|", "~", "←", "↓", "↑", "→", "SALIR"};
        for (String t : teclas) {
            TextView b = new TextView(this);
            b.setText(t);
            b.setTextColor(t.equals("SALIR") ? 0xffff6b6b : Color.WHITE);
            b.setTypeface(Typeface.MONOSPACE, t.equals("SALIR") ? Typeface.BOLD : Typeface.NORMAL);
            b.setGravity(Gravity.CENTER);
            b.setPadding(0, 24, 0, 24);
            b.setOnClickListener(v -> tecla(t));
            if (t.equals("CTRL")) botonCtrl = b;
            if (t.equals("ALT")) botonAlt = b;
            fila.addView(b, new LinearLayout.LayoutParams(0, -2, 1));
        }
        return fila;
    }

    private void tecla(String t) {
        switch (t) {
            case "⌨":
                vista.requestFocus();
                getSystemService(InputMethodManager.class).showSoftInput(vista, 0);
                return;
            case "SALIR":
                mostrarMenuSalida();
                return;
            case "CTRL": ctrl = !ctrl; marcar(); return;
            case "ALT": alt = !alt; marcar(); return;
            case "ESC": codigo(KeyEvent.KEYCODE_ESCAPE); return;
            case "TAB": codigo(KeyEvent.KEYCODE_TAB); return;
            case "←": codigo(KeyEvent.KEYCODE_DPAD_LEFT); return;
            case "↓": codigo(KeyEvent.KEYCODE_DPAD_DOWN); return;
            case "↑": codigo(KeyEvent.KEYCODE_DPAD_UP); return;
            case "→": codigo(KeyEvent.KEYCODE_DPAD_RIGHT); return;
            default: vista.inputCodePoint(t.codePointAt(0), false, false);
        }
    }

    private void mostrarMenuSalida() {
        SistemaLinux.Instancia inst = SistemaLinux.instanciaSeleccionada(this);
        String nombre = inst != null ? inst.nombre : "Linux";
        new AlertDialog.Builder(this)
                .setTitle("✦ Terminal (" + nombre + ")")
                .setMessage("¿Deseas salir manteniendo la sesión en segundo plano, o cerrar la sesión por completo?")
                .setPositiveButton("Salir (mantener en fondo)", (d, w) -> {
                    finish();
                })
                .setNegativeButton("✕ Cerrar sesión", (d, w) -> {
                    startService(new Intent(this, TerminalService.class).setAction(TerminalService.CERRAR_SESION));
                    finish();
                })
                .setNeutralButton("Cancelar", null)
                .show();
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            mostrarMenuSalida();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    private void codigo(int keyCode) {
        vista.onKeyDown(keyCode, new KeyEvent(KeyEvent.ACTION_DOWN, keyCode));
    }

    private void marcar() {
        botonCtrl.setBackgroundColor(ctrl ? 0xff3d6aa5 : 0);
        botonAlt.setBackgroundColor(alt ? 0xff3d6aa5 : 0);
    }

    // Enter con la sesión terminada cierra la terminal (y el servicio si no queda sway).
    private boolean cerrarSiTermino(TerminalSession s) {
        if (s == null || s.isRunning()) return false;
        if (servicio != null) servicio.cerrarSesion();
        finish();
        return true;
    }

    // --- TerminalViewClient ---

    @Override
    public float onScale(float escala) {
        if (escala < 0.9f || escala > 1.1f) {
            int dp = Math.max(6, Math.min(48, Math.round(tamLetra * (escala > 1 ? 1.1f : 0.9f))));
            if (dp != tamLetra) {
                tamLetra = dp;
                vista.setTextSize(tamLetra);
            }
            return 1.0f;
        }
        return escala;
    }

    @Override
    public void onSingleTapUp(MotionEvent e) {
        vista.requestFocus();
        getSystemService(InputMethodManager.class).showSoftInput(vista, 0);
    }

    @Override
    public boolean shouldBackButtonBeMappedToEscape() { return false; }

    @Override
    public boolean shouldEnforceCharBasedInput() { return true; }

    @Override
    public boolean shouldUseCtrlSpaceWorkaround() { return false; }

    @Override
    public boolean isTerminalViewSelected() { return true; }

    @Override
    public void copyModeChanged(boolean copyMode) { }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent e, TerminalSession s) {
        if (keyCode == KeyEvent.KEYCODE_ENTER) return cerrarSiTermino(s);
        return false;
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent e) { return false; }

    @Override
    public boolean onLongPress(MotionEvent e) { return false; }

    // CTRL/ALT de la fila se aplican a una sola tecla, como en Termux
    @Override
    public boolean readControlKey() {
        boolean r = ctrl;
        if (r) { ctrl = false; marcar(); }
        return r;
    }

    @Override
    public boolean readAltKey() {
        boolean r = alt;
        if (r) { alt = false; marcar(); }
        return r;
    }

    @Override
    public boolean readShiftKey() { return false; }

    @Override
    public boolean readFnKey() { return false; }

    @Override
    public boolean onCodePoint(int codePoint, boolean ctrlDown, TerminalSession s) {
        if (codePoint == '\n' || codePoint == '\r') return cerrarSiTermino(s);
        return false;
    }

    @Override
    public void onEmulatorSet() { }

    @Override
    public void logError(String tag, String msg) { Log.e(TAG, tag + ": " + msg); }

    @Override
    public void logWarn(String tag, String msg) { Log.w(TAG, tag + ": " + msg); }

    @Override
    public void logInfo(String tag, String msg) { Log.i(TAG, tag + ": " + msg); }

    @Override
    public void logDebug(String tag, String msg) { }

    @Override
    public void logVerbose(String tag, String msg) { }

    @Override
    public void logStackTraceWithMessage(String tag, String msg, Exception e) { Log.e(TAG, tag + ": " + msg, e); }

    @Override
    public void logStackTrace(String tag, Exception e) { Log.e(TAG, tag, e); }
}
