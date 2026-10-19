package dev.ben4shot.mosaico

import android.app.Activity
import android.app.ActivityOptions
import android.content.ComponentName
import android.content.Intent
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.lsposed.hiddenapibypass.HiddenApiBypass

private const val TAG = "Mosaico"

// WindowConfiguration.WINDOWING_MODE_FREEFORM: lo que usan las ventanas flotantes de HyperOS.
private const val MODO_FLOTANTE = 5

// Lo que tarda el sistema en terminar la animación de una ventana antes de abrir la siguiente.
private const val PAUSA_MS = 700L

private fun intentDe(componente: ComponentName) = Intent(Intent.ACTION_MAIN)
    .addCategory(Intent.CATEGORY_LAUNCHER)
    .setComponent(componente)
    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)

private fun lanzar(activity: Activity, intent: Intent, opciones: ActivityOptions? = null) {
    Log.i(TAG, "abrir ${intent.component?.flattenToShortString()} flags=0x${intent.flags.toString(16)} opciones=$opciones")
    runCatching { activity.startActivity(intent, opciones?.toBundle()) }
        .onFailure { Log.w(TAG, "no se pudo abrir ${intent.component}", it) }
}

/** Pantalla completa, como cualquier launcher. */
fun abrir(activity: Activity, componente: ComponentName) = lanzar(activity, intentDe(componente))

/**
 * Pantalla dividida: la app se abre en la mitad opuesta a Mosaico. Lo que se abra después desde Mosaico
 * reemplaza a Mosaico en su mitad.
 */
fun abrirAlLado(activity: Activity, componente: ComponentName) =
    lanzar(activity, intentDe(componente).addFlags(Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT))

/** Ventana flotante centrada (70 % del ancho, 45 % del alto). */
fun abrirFlotante(activity: Activity, componente: ComponentName) {
    val pantalla = activity.windowManager.maximumWindowMetrics.bounds
    val ancho = pantalla.width() * 7 / 10
    val alto = pantalla.height() * 45 / 100
    val x = (pantalla.width() - ancho) / 2
    val y = (pantalla.height() - alto) / 2
    val opciones = ActivityOptions.makeBasic().setLaunchBounds(Rect(x, y, x + ancho, y + alto))
    runCatching { HiddenApiBypass.invoke(ActivityOptions::class.java, opciones, "setLaunchWindowingMode", MODO_FLOTANTE) }
        .onFailure { Log.w(TAG, "setLaunchWindowingMode no disponible", it) }
    lanzar(activity, intentDe(componente), opciones)
}

/**
 * Abre el escritorio completo. La flotante va primero: lo que se abre desde una mitad de la pantalla dividida
 * HyperOS lo mete en esa mitad aunque pida ventana flotante. Después la secundaria al lado de Mosaico y la principal
 * reemplaza a Mosaico en su mitad (arriba). Con un solo lugar ocupado se abre a pantalla completa.
 */
fun abrirEscritorio(activity: Activity, escritorios: Escritorios, n: Int) {
    val principal = escritorios.app(n, Lugar.PRINCIPAL)
    val secundaria = escritorios.app(n, Lugar.SECUNDARIA)
    val flotante = escritorios.app(n, Lugar.FLOTANTE)
    val pasos = buildList<() -> Unit> {
        if (flotante != null) add { abrirFlotante(activity, flotante) }
        when {
            principal != null && secundaria != null -> {
                add { abrirAlLado(activity, secundaria) }
                add { abrir(activity, principal) }
            }
            principal != null -> add { abrir(activity, principal) }
            secundaria != null -> add { abrir(activity, secundaria) }
        }
    }
    val handler = Handler(Looper.getMainLooper())
    pasos.forEachIndexed { i, paso -> handler.postDelayed(paso, i * PAUSA_MS) }
}
