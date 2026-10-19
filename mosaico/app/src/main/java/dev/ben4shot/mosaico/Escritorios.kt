package dev.ben4shot.mosaico

import android.content.ComponentName
import android.content.Context

/** Lugares de un escritorio: dos mitades de la pantalla dividida y una ventana flotante encima. */
enum class Lugar(val titulo: String) { PRINCIPAL("Principal"), SECUNDARIA("Secundaria"), FLOTANTE("Flotante") }

const val NUM_ESCRITORIOS = 5

/** Qué app va en cada lugar de cada escritorio. Se guarda en SharedPreferences como "<n>.<lugar>" = componente. */
class Escritorios(ctx: Context) {
    private val prefs = ctx.getSharedPreferences("escritorios", Context.MODE_PRIVATE)

    fun app(escritorio: Int, lugar: Lugar): ComponentName? =
        prefs.getString(clave(escritorio, lugar), null)?.let(ComponentName::unflattenFromString)

    fun asignar(escritorio: Int, lugar: Lugar, componente: ComponentName?) {
        prefs.edit().apply {
            if (componente == null) remove(clave(escritorio, lugar))
            else putString(clave(escritorio, lugar), componente.flattenToString())
        }.apply()
    }

    var actual: Int
        get() = prefs.getInt("actual", 1)
        set(v) = prefs.edit().putInt("actual", v).apply()

    private fun clave(escritorio: Int, lugar: Lugar) = "$escritorio.${lugar.name.lowercase()}"
}
