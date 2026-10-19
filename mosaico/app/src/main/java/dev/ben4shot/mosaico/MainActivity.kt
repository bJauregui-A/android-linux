package dev.ben4shot.mosaico

import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.time.LocalTime
import java.time.format.DateTimeFormatter

// Colores por defecto de Hyprland sobre fondo Catppuccin Mocha.
private val Fondo = Color(0xFF11111B)
private val Panel = Color(0xFF1E1E2E)
private val Texto = Color(0xFFCDD6F4)
private val Apagado = Color(0xFF6C7086)
private val Inactivo = Color(0xFF595959)
private val BordeActivo = Brush.linearGradient(listOf(Color(0xFF33CCFF), Color(0xFF00FF99)))
private val Forma = RoundedCornerShape(10.dp)
private val Mono = FontFamily.Monospace

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val escritorios = Escritorios(this)
        setContent { Mosaico(escritorios) }
    }

    @Composable
    private fun Mosaico(escritorios: Escritorios) {
        var apps by remember { mutableStateOf(emptyList<App>()) }
        var actual by remember { mutableIntStateOf(escritorios.actual) }
        var busqueda by remember { mutableStateOf("") }
        // Lugar del escritorio actual que se está llenando; null = el buscador solo abre apps.
        var asignando by remember { mutableStateOf<Lugar?>(null) }
        // Fuerza a releer los lugares del escritorio después de asignar uno.
        var version by remember { mutableIntStateOf(0) }

        LaunchedEffect(Unit) { apps = withContext(Dispatchers.Default) { cargarApps(this@MainActivity) } }

        fun cambiar(n: Int) {
            actual = n.coerceIn(1, NUM_ESCRITORIOS)
            escritorios.actual = actual
        }

        Column(
            Modifier.fillMaxSize().background(Fondo).systemBarsPadding().imePadding().padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Barra(actual, ::cambiar)
            val resultados = filtrar(apps, busqueda)
            Buscador(
                texto = busqueda,
                pista = if (asignando != null) "app para ${asignando!!.titulo.lowercase()}…" else "abrir…",
                alCambiar = { busqueda = it },
                alEnter = { resultados.firstOrNull()?.let { abrir(this@MainActivity, it.componente) }; busqueda = "" },
            )
            if (busqueda.isBlank() && asignando == null) {
                key(version) {
                    PanelEscritorio(
                        n = actual,
                        lugares = Lugar.entries.associateWith { l -> escritorios.app(actual, l)?.let { c -> apps.find { it.componente == c } } },
                        modifier = Modifier.weight(1f).pointerInput(actual) {
                            var arrastre = 0f
                            detectHorizontalDragGestures(
                                onDragStart = { arrastre = 0f },
                                onDragEnd = { if (arrastre < -120) cambiar(actual + 1) else if (arrastre > 120) cambiar(actual - 1) },
                            ) { _, d -> arrastre += d }
                        },
                        alTocar = { asignando = it },
                        alMantener = { escritorios.asignar(actual, it, null); version++ },
                        alAbrir = { abrirEscritorio(this@MainActivity, escritorios, actual) },
                    )
                }
            } else {
                ListaApps(resultados, Modifier.weight(1f)) { app, accion ->
                    val lugar = asignando
                    if (lugar != null) {
                        escritorios.asignar(actual, lugar, app.componente)
                        asignando = null
                        version++
                    } else accion(app.componente)
                    busqueda = ""
                }
                if (asignando != null) Etiqueta("cancelar", Modifier.combinedClickable { asignando = null; busqueda = "" })
            }
        }
    }

    // ── Barra superior tipo waybar ───────────────────────────────────────────────

    @Composable
    private fun Barra(actual: Int, alCambiar: (Int) -> Unit) {
        var hora by remember { mutableStateOf("") }
        var bateria by remember { mutableIntStateOf(0) }
        LaunchedEffect(Unit) {
            while (true) {
                hora = LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm"))
                bateria = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                    ?.getIntExtra(BatteryManager.EXTRA_LEVEL, 0) ?: 0
                delay(10_000)
            }
        }
        Row(
            Modifier.fillMaxWidth().clip(Forma).background(Panel).padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            for (n in 1..NUM_ESCRITORIOS) {
                val activo = n == actual
                Box(
                    Modifier.size(28.dp).clip(Forma)
                        .then(if (activo) Modifier.border(2.dp, BordeActivo, Forma) else Modifier)
                        .combinedClickable { alCambiar(n) },
                    contentAlignment = Alignment.Center,
                ) { Text("$n", color = if (activo) Texto else Apagado, fontFamily = Mono, fontSize = 14.sp) }
            }
            Spacer(Modifier.weight(1f))
            Text("$bateria%", color = Texto, fontFamily = Mono, fontSize = 14.sp)
            Text(hora, color = Texto, fontFamily = Mono, fontSize = 14.sp)
        }
    }

    // ── Buscador tipo rofi ───────────────────────────────────────────────────────

    @Composable
    private fun Buscador(texto: String, pista: String, alCambiar: (String) -> Unit, alEnter: () -> Unit) {
        Box(Modifier.fillMaxWidth().clip(Forma).background(Panel).border(2.dp, BordeActivo, Forma).padding(12.dp)) {
            if (texto.isEmpty()) Text(pista, color = Apagado, fontFamily = Mono)
            BasicTextField(
                value = texto,
                onValueChange = alCambiar,
                singleLine = true,
                textStyle = TextStyle(color = Texto, fontFamily = Mono, fontSize = 16.sp),
                cursorBrush = SolidColor(Color(0xFF33CCFF)),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                keyboardActions = KeyboardActions(onGo = { alEnter() }),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }

    @Composable
    private fun ListaApps(apps: List<App>, modifier: Modifier, alElegir: (App, (ComponentName) -> Unit) -> Unit) {
        LazyColumn(modifier.fillMaxWidth().clip(Forma).background(Panel)) {
            items(apps, key = { it.componente.flattenToString() }) { app ->
                var menu by remember { mutableStateOf(false) }
                Box {
                    FilaApp(app, Modifier.combinedClickable(
                        onClick = { alElegir(app) { abrir(this@MainActivity, it) } },
                        onLongClick = { menu = true },
                    ))
                    DropdownMenu(menu, onDismissRequest = { menu = false }, containerColor = Panel) {
                        listOf<Pair<String, (ComponentName) -> Unit>>(
                            "Pantalla completa" to { abrir(this@MainActivity, it) },
                            "Al lado (dividida)" to { abrirAlLado(this@MainActivity, it) },
                            "Flotante" to { abrirFlotante(this@MainActivity, it) },
                        ).forEach { (titulo, accion) ->
                            DropdownMenuItem(
                                text = { Text(titulo, color = Texto, fontFamily = Mono) },
                                onClick = { menu = false; alElegir(app, accion) },
                            )
                        }
                    }
                }
            }
        }
    }

    @Composable
    private fun FilaApp(app: App, modifier: Modifier = Modifier) {
        Row(
            modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Image(app.icono, null, Modifier.size(32.dp))
            Spacer(Modifier.width(12.dp))
            Text(app.nombre, color = Texto, fontFamily = Mono)
        }
    }

    // ── Escritorio: dos mitades + flotante ───────────────────────────────────────

    @Composable
    private fun PanelEscritorio(
        n: Int,
        lugares: Map<Lugar, App?>,
        modifier: Modifier,
        alTocar: (Lugar) -> Unit,
        alMantener: (Lugar) -> Unit,
        alAbrir: () -> Unit,
    ) {
        Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.weight(1f).fillMaxWidth()) {
                Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Ventana(Lugar.PRINCIPAL, lugares[Lugar.PRINCIPAL], Modifier.weight(1f), alTocar, alMantener)
                    Ventana(Lugar.SECUNDARIA, lugares[Lugar.SECUNDARIA], Modifier.weight(1f), alTocar, alMantener)
                }
                Ventana(
                    Lugar.FLOTANTE, lugares[Lugar.FLOTANTE],
                    Modifier.align(Alignment.Center).fillMaxWidth(0.6f).height(110.dp),
                    alTocar, alMantener, opaca = true,
                )
            }
            Etiqueta("▶ abrir escritorio $n", Modifier.fillMaxWidth().border(2.dp, BordeActivo, Forma).combinedClickable(onClick = alAbrir))
        }
    }

    @Composable
    private fun Ventana(
        lugar: Lugar,
        app: App?,
        modifier: Modifier,
        alTocar: (Lugar) -> Unit,
        alMantener: (Lugar) -> Unit,
        opaca: Boolean = false,
    ) {
        Box(
            modifier.fillMaxWidth().clip(Forma)
                .background(if (opaca) Panel else Panel.copy(alpha = 0.6f))
                .border(2.dp, if (app != null) BordeActivo else SolidColor(Inactivo), Forma)
                .combinedClickable(onClick = { alTocar(lugar) }, onLongClick = { alMantener(lugar) }),
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                if (app != null) {
                    Image(app.icono, null, Modifier.size(40.dp))
                    Text(app.nombre, color = Texto, fontFamily = Mono)
                } else Text("+", color = Apagado, fontFamily = Mono, fontSize = 24.sp)
                Text(lugar.titulo.lowercase(), color = Apagado, fontFamily = Mono, fontSize = 12.sp)
            }
        }
    }

    @Composable
    private fun Etiqueta(texto: String, modifier: Modifier = Modifier) {
        Box(modifier.clip(Forma).background(Panel).padding(12.dp), contentAlignment = Alignment.Center) {
            Text(texto, color = Texto, fontFamily = Mono)
        }
    }
}
