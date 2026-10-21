package dev.ben4shot.glibcprueba;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

// Entrada de la app: elegir qué instalación Linux abrir. Las distribuciones futuras se muestran
// para hacer explícito el alcance del selector, pero no se pueden elegir antes de tener rootfs.
public class SistemaActivity extends Activity {
    private static final int FONDO = 0xff101216;
    private static final int TARJETA = 0xff20242b;
    private static final int TEXTO = 0xfff4f5f7;
    private static final int SECUNDARIO = 0xffb8c0cc;
    private LinearLayout lista;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(FONDO);
        LinearLayout contenido = new LinearLayout(this);
        contenido.setOrientation(LinearLayout.VERTICAL);
        contenido.setPadding(dp(24), dp(36), dp(24), dp(24));
        scroll.addView(contenido);

        contenido.addView(texto("Sistema Linux", 28, true, TEXTO));
        TextView ayuda = texto("Elige una instalación para abrirla. Cada sistema conserva sus propios archivos.",
                15, false, SECUNDARIO);
        LinearLayout.LayoutParams ap = new LinearLayout.LayoutParams(-1, -2);
        ap.topMargin = dp(10);
        ap.bottomMargin = dp(24);
        contenido.addView(ayuda, ap);

        lista = new LinearLayout(this);
        lista.setOrientation(LinearLayout.VERTICAL);
        contenido.addView(lista, new LinearLayout.LayoutParams(-1, -2));
        actualizarOpciones();

        TextView pie = texto("Debian y Ubuntu se habilitarán cuando tengan una instalación separada y probada.",
                13, false, SECUNDARIO);
        LinearLayout.LayoutParams pp = new LinearLayout.LayoutParams(-1, -2);
        pp.topMargin = dp(10);
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
            tarjeta.setPadding(dp(18), dp(15), dp(18), dp(15));
            tarjeta.setBackgroundColor(o.disponible ? TARJETA : 0xff181a1e);
            tarjeta.setEnabled(o.disponible);
            tarjeta.setClickable(o.disponible);

            TextView nombre = texto(o.nombre, 19, true, o.disponible ? TEXTO : 0xff777d86);
            TextView detalle = texto(o.arquitectura + " · " + o.estado, 14, false,
                    o.disponible ? SECUNDARIO : 0xff777d86);
            tarjeta.addView(nombre);
            LinearLayout.LayoutParams dpDetalle = new LinearLayout.LayoutParams(-1, -2);
            dpDetalle.topMargin = dp(5);
            tarjeta.addView(detalle, dpDetalle);
            if (o.id.equals(elegido) && o.disponible) {
                TextView activo = texto("Seleccionado", 12, true, 0xff8ac7ff);
                LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-1, -2);
                sp.topMargin = dp(8);
                tarjeta.addView(activo, sp);
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
        if (negrita) v.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return v;
    }

    private int dp(int valor) {
        return Math.round(valor * getResources().getDisplayMetrics().density);
    }
}
