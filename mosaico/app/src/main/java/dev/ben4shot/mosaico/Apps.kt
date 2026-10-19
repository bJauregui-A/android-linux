package dev.ben4shot.mosaico

import android.content.ComponentName
import android.content.Context
import android.content.pm.LauncherApps
import android.os.Process
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.core.graphics.drawable.toBitmap
import java.text.Normalizer

class App(val nombre: String, val componente: ComponentName, val icono: ImageBitmap)

/** Apps con ícono en el cajón, ordenadas por nombre. Lento (íconos): llamar fuera del hilo principal. */
fun cargarApps(ctx: Context): List<App> {
    val la = ctx.getSystemService(LauncherApps::class.java)
    val tam = (48 * ctx.resources.displayMetrics.density).toInt()
    return la.getActivityList(null, Process.myUserHandle())
        .filter { it.componentName.packageName != ctx.packageName }
        .map { App(it.label.toString(), it.componentName, it.getIcon(0).toBitmap(tam, tam).asImageBitmap()) }
        .sortedBy { it.nombre.lowercase() }
}

/** Sin mayúsculas ni acentos: "Brújula" -> "brujula". */
private fun normalizar(s: String) =
    Normalizer.normalize(s.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "")

/** Filtro tipo rofi: primero los que empiezan con la búsqueda, después los que la contienen. */
fun filtrar(apps: List<App>, busqueda: String): List<App> {
    val q = normalizar(busqueda.trim())
    if (q.isEmpty()) return apps
    val (empiezan, resto) = apps.map { it to normalizar(it.nombre) }
        .filter { (_, n) -> q in n }
        .partition { (_, n) -> n.startsWith(q) }
    return (empiezan + resto).map { it.first }
}
