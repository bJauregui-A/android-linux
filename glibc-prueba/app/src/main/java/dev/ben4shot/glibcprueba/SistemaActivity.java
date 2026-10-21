package dev.ben4shot.glibcprueba;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.util.List;

// Interfaz estilo AI CLI para el inicio de la app: listar instancias existentes, crear nuevas,
// y lanzar el escritorio Wayland o la terminal de mantenimiento para cada una.
public class SistemaActivity extends Activity {
    private static final int FONDO_OSCURO = 0xff090d13;
    private static final int PANEL_CARD = 0xff121820;
    private static final int PANEL_ACTIVO = 0xff16202c;
    private static final int BORDE_ACTIVO = 0xff38ef7d;  // Esmeralda brillante
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
    private TextView statBadge;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(FONDO_OSCURO);

        LinearLayout raiz = new LinearLayout(this);
        raiz.setOrientation(LinearLayout.VERTICAL);
        raiz.setPadding(dp(18), dp(24), dp(18), dp(24));
        scroll.addView(raiz);

        // Header AI CLI Banner
        raiz.addView(bannerHeader());

        // Fila de estadísticas/badges de hardware y estado
        statBadge = textoBadge("● CONSULTANDO ESTADO...", ACCENTO_CIAN);
        LinearLayout filaStats = new LinearLayout(this);
        filaStats.setOrientation(LinearLayout.HORIZONTAL);
        filaStats.addView(statBadge);
        filaStats.addView(espacioHorizontal(dp(8)));
        filaStats.addView(textoBadge("⚡ GPU: TURNIP + ZINK", ACCENTO_PURPURA));
        filaStats.addView(espacioHorizontal(dp(8)));
        filaStats.addView(textoBadge("◈ ARM64", TEXTO_MUTED));
        LinearLayout.LayoutParams lpStats = new LinearLayout.LayoutParams(-1, -2);
        lpStats.topMargin = dp(14);
        lpStats.bottomMargin = dp(18);
        raiz.addView(filaStats, lpStats);

        // Botón destacado: + CREAR NUEVO ENTORNO
        raiz.addView(botonCrearEntorno());

        // Separador y título de lista de instancias
        TextView tituloSeccion = texto("❯ ENTORNOS DISPONIBLES (INSTANCIAS)", 13, true, ACCENTO_CIAN);
        LinearLayout.LayoutParams lpTit = new LinearLayout.LayoutParams(-1, -2);
        lpTit.topMargin = dp(24);
        lpTit.bottomMargin = dp(10);
        raiz.addView(tituloSeccion, lpTit);

        contenedorInstancias = new LinearLayout(this);
        contenedorInstancias.setOrientation(LinearLayout.VERTICAL);
        raiz.addView(contenedorInstancias, new LinearLayout.LayoutParams(-1, -2));

        // Pie de consola
        TextView footer = texto("user@android:~$ █  (Toca un entorno para activarlo)", 12, false, TEXTO_MUTED);
        LinearLayout.LayoutParams lpFoot = new LinearLayout.LayoutParams(-1, -2);
        lpFoot.topMargin = dp(24);
        raiz.addView(footer, lpFoot);

        setContentView(scroll);
        actualizarLista();
    }

    @Override
    protected void onResume() {
        super.onResume();
        actualizarLista();
    }

    private View bannerHeader() {
        LinearLayout banner = new LinearLayout(this);
        banner.setOrientation(LinearLayout.VERTICAL);
        banner.setBackground(crearFondo(0xff0d141f, ACCENTO_AZUL, dp(8), dp(1)));
        banner.setPadding(dp(14), dp(12), dp(14), dp(12));

        TextView topBorder = texto("╭──────────────────────────────────────────────────────────╮", 11, true, ACCENTO_PURPURA);
        TextView title = texto("  ✦ ANTIGRAVITY  •  ANDROID LINUX CLI", 15, true, TEXTO_CLARO);
        TextView sub = texto("  Gestor de Entornos Autónomo  /  Multi-Instancia", 12, false, ACCENTO_CIAN);
        TextView bottomBorder = texto("╰──────────────────────────────────────────────────────────╯", 11, true, ACCENTO_PURPURA);

        banner.addView(topBorder);
        banner.addView(title);
        banner.addView(sub);
        banner.addView(bottomBorder);

        TextView prompt = texto("user@android:~$ linux-instances --interactive", 13, true, ACCENTO_VERDE);
        LinearLayout.LayoutParams lpP = new LinearLayout.LayoutParams(-1, -2);
        lpP.topMargin = dp(10);
        banner.addView(prompt, lpP);

        return banner;
    }

    private View botonCrearEntorno() {
        LinearLayout btn = new LinearLayout(this);
        btn.setOrientation(LinearLayout.HORIZONTAL);
        btn.setGravity(Gravity.CENTER_VERTICAL);
        btn.setBackground(crearFondo(0xff182232, ACCENTO_PURPURA, dp(8), dp(2)));
        btn.setPadding(dp(16), dp(12), dp(16), dp(12));
        btn.setClickable(true);
        btn.setFocusable(true);

        TextView icono = texto("✦ ", 16, true, ACCENTO_PURPURA);
        TextView lbl = texto("＋ CREAR NUEVO ENTORNO (INSTANCIA)", 14, true, TEXTO_CLARO);
        btn.addView(icono);
        btn.addView(lbl);

        btn.setOnClickListener(v -> mostrarDialogoCreacion());
        return btn;
    }

    private void actualizarLista() {
        if (contenedorInstancias == null) return;
        contenedorInstancias.removeAllViews();

        List<SistemaLinux.Instancia> instancias = SistemaLinux.listarInstancias(this);
        SistemaLinux.Instancia activa = SistemaLinux.instanciaSeleccionada(this);

        if (statBadge != null) {
            statBadge.setText("● " + instancias.size() + (instancias.size() == 1 ? " INSTANCIA" : " INSTANCIAS"));
        }

        for (int i = 0; i < instancias.size(); i++) {
            SistemaLinux.Instancia inst = instancias.get(i);
            boolean esActiva = inst.id.equals(activa.id);
            AdaptadorInstalacion adp = SistemaLinux.adaptador(this, inst);
            boolean instalada = adp.instalada(this);

            contenedorInstancias.addView(crearTarjetaInstancia(inst, i + 1, esActiva, instalada));
        }
    }

    private View crearTarjetaInstancia(SistemaLinux.Instancia inst, int index, boolean activa, boolean instalada) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(16), dp(14), dp(16), dp(14));
        card.setBackground(crearFondo(
                activa ? PANEL_ACTIVO : PANEL_CARD,
                activa ? BORDE_ACTIVO : BORDE_NORMAL,
                dp(10),
                activa ? dp(2) : dp(1)));

        LinearLayout.LayoutParams lpCard = new LinearLayout.LayoutParams(-1, -2);
        lpCard.bottomMargin = dp(14);
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

        card.addView(header);

        // Nombre de la instancia
        TextView nombre = texto("❯ [" + index + "] " + inst.nombre, 16, true, activa ? TEXTO_CLARO : 0xffcbd5e1);
        LinearLayout.LayoutParams lpNombre = new LinearLayout.LayoutParams(-1, -2);
        lpNombre.topMargin = dp(8);
        card.addView(nombre, lpNombre);

        // Metadatos
        String distroStr = SistemaLinux.ARCH.equals(inst.distroId) ? "Arch Linux ARM" : inst.distroId;
        TextView meta1 = texto("    Distro: " + distroStr + " • arm64-v8a", 12, false, TEXTO_MUTED);
        TextView meta2 = texto("    Ruta:   files/" + inst.rutaRelativa, 12, false, TEXTO_MUTED);
        card.addView(meta1);
        card.addView(meta2);

        // Botones de acción dentro de la tarjeta
        LinearLayout acciones = new LinearLayout(this);
        acciones.setOrientation(LinearLayout.HORIZONTAL);
        acciones.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout.LayoutParams lpAcc = new LinearLayout.LayoutParams(-1, -2);
        lpAcc.topMargin = dp(12);
        acciones.setLayoutParams(lpAcc);

        // Botón INICIAR ESCRITORIO
        TextView btnIniciar = crearBotonChip("▶ ESCRITORIO", ACCENTO_VERDE, () -> {
            activarYEjecutar(inst.id, true);
        });
        acciones.addView(btnIniciar);

        acciones.addView(espacioHorizontal(dp(8)));

        // Botón TERMINAL
        TextView btnTerminal = crearBotonChip(">_ TERMINAL", ACCENTO_AZUL, () -> {
            activarYEjecutar(inst.id, false);
        });
        acciones.addView(btnTerminal);

        // Botón ELIMINAR (solo si hay más de 1 instancia)
        List<SistemaLinux.Instancia> todas = SistemaLinux.listarInstancias(this);
        if (todas.size() > 1 && !"archlinux".equals(inst.rutaRelativa)) {
            acciones.addView(espacioHorizontal(dp(8)));
            TextView btnBorrar = crearBotonChip("✕ BORRAR", ACCENTO_ROJO, () -> {
                confirmarEliminar(inst);
            });
            acciones.addView(btnBorrar);
        }

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
        // Si hay una sesión anterior corriendo, la detenemos limpiamente al cambiar
        stopService(new Intent(this, TerminalService.class));
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
                .setPositiveButton("✦ CREAR E INSTALAR", null)
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
                // Abrir la terminal para que inicie la instalación interactiva con el nuevo diseño CLI
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
}
