package dev.ben4shot.glibcprueba;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

// Entrada de la app: elegir qué instalación Linux abrir. Las distribuciones futuras se muestran
// para hacer explícito el alcance del selector, pero no se pueden elegir antes de tener rootfs.
public class SistemaActivity extends Activity {
    private static final int FONDO = 0xff0b100d;
    private static final int PANEL = 0xff101812;
    private static final int TEXTO = 0xffd6e5d8;
    private static final int VERDE = 0xff8be28b;
    private static final int CIAN = 0xff77d7c3;
    private static final int AMBAR = 0xffd5a95f;
    private static final int APAGADO = 0xff68756b;
    private LinearLayout lista;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(FONDO);
        LinearLayout contenido = new LinearLayout(this);
        contenido.setOrientation(LinearLayout.VERTICAL);
        contenido.setPadding(dp(22), dp(30), dp(22), dp(24));
        scroll.addView(contenido);

        contenido.addView(texto("ANDROID LINUX  /  GESTOR DE SESION", 12, true, CIAN));
        TextView prompt = texto("user@android:~$ linux --list", 17, true, VERDE);
        LinearLayout.LayoutParams promptParams = new LinearLayout.LayoutParams(-1, -2);
        promptParams.topMargin = dp(22);
        contenido.addView(prompt, promptParams);

        TextView ayuda = texto("Selecciona una instalación Linux persistente.", 14, false, TEXTO);
        LinearLayout.LayoutParams ap = new LinearLayout.LayoutParams(-1, -2);
        ap.topMargin = dp(8);
        ap.bottomMargin = dp(20);
        contenido.addView(ayuda, ap);

        lista = new LinearLayout(this);
        lista.setOrientation(LinearLayout.VERTICAL);
        contenido.addView(lista, new LinearLayout.LayoutParams(-1, -2));
        actualizarOpciones();

        TextView pie = texto("# Debian y Ubuntu requieren un rootfs y adaptador propios.",
                12, false, APAGADO);
        LinearLayout.LayoutParams pp = new LinearLayout.LayoutParams(-1, -2);
        pp.topMargin = dp(4);
        contenido.addView(pie, pp);
        setContentView(scroll);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (lista != null) actualizarOpciones();
    }

    private void actualizarOpciones() {
        lista.removeAllViews();
        String elegido = SistemaLinux.seleccionado(this);
        for (SistemaLinux.Opcion o : SistemaLinux.opciones(this)) {
            LinearLayout tarjeta = new LinearLayout(this);
            tarjeta.setOrientation(LinearLayout.VERTICAL);
            tarjeta.setGravity(Gravity.CENTER_VERTICAL);
            tarjeta.setPadding(dp(16), dp(13), dp(16), dp(13));
            tarjeta.setBackground(fondoOpcion(o.disponible && o.id.equals(elegido), o.disponible));
            tarjeta.setEnabled(o.disponible);
            tarjeta.setClickable(o.disponible);

            boolean activo = o.id.equals(elegido) && o.disponible;
            int color = o.disponible ? TEXTO : APAGADO;
            TextView nombre = texto((activo ? "> " : "  ") + o.nombre, 17, true, color);
            TextView detalle = texto("    " + o.arquitectura + "  |  " + o.estado, 12, false,
                    o.disponible ? CIAN : APAGADO);
            tarjeta.addView(nombre);
            LinearLayout.LayoutParams dpDetalle = new LinearLayout.LayoutParams(-1, -2);
            dpDetalle.topMargin = dp(5);
            tarjeta.addView(detalle, dpDetalle);
            if (activo) {
                TextView estado = texto("    [ ACTIVO ]  tocar para iniciar", 11, true, VERDE);
                LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-1, -2);
                sp.topMargin = dp(8);
                tarjeta.addView(estado, sp);
            } else if (!o.disponible) {
                TextView estado = texto("    [ NO DISPONIBLE ]", 11, true, AMBAR);
                LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-1, -2);
                sp.topMargin = dp(8);
                tarjeta.addView(estado, sp);
            }
            if (o.disponible) tarjeta.setOnClickListener(v -> abrir(o.id));
            LinearLayout.LayoutParams tp = new LinearLayout.LayoutParams(-1, -2);
            tp.bottomMargin = dp(12);
            lista.addView(tarjeta, tp);
        }
    }

    private void abrir(String id) {
        SistemaLinux.seleccionar(this, id);
        startActivity(new Intent(this, WaylandActivity.class));
        finish();
    }

    private TextView texto(String s, int sp, boolean negrita, int color) {
        TextView v = new TextView(this);
        v.setText(s);
        v.setTextSize(sp);
        v.setTextColor(color);
        v.setTypeface(Typeface.MONOSPACE, negrita ? Typeface.BOLD : Typeface.NORMAL);
        return v;
    }

    private GradientDrawable fondoOpcion(boolean activo, boolean disponible) {
        GradientDrawable fondo = new GradientDrawable();
        fondo.setColor(PANEL);
        fondo.setCornerRadius(dp(4));
        fondo.setStroke(dp(1), activo ? VERDE : disponible ? 0xff34483a : 0xff273129);
        return fondo;
    }

    private int dp(int valor) {
        return Math.round(valor * getResources().getDisplayMetrics().density);
    }
}
