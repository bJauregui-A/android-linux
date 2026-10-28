#!/usr/bin/bash
# El sandbox de contenido de Firefox necesita android.js (rutas reales del prefijo para su broker): sin él no lee las
# fuentes y cada proceso de contenido muere con SIGSEGV ("no fonts"), y ninguna web carga. primer-arranque.sh solo lo
# escribía si Firefox ya estaba instalado y solo en /usr/lib/firefox: quien lo instalaba después, o firefox-esr en
# Debian, quedaba sin él. escritorios/comun/firefox-ajustes lo escribe al abrir cada sesión.
# Corre en el PC con un árbol de mentira:  pruebas/escritorios/firefox.sh
cd "$(dirname "$0")/../.." || exit 1
fallas=0
caso() { if eval "$2"; then echo "OK    $1"; else echo "FALLA $1"; fallas=$((fallas + 1)); fi; }
S=escritorios/comun/firefox-ajustes
[ -x $S ] || { echo "FALLA no existe $S ejecutable"; echo "fallas: 1"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# plantilla como la arma apk/capa.py: @P@ = el prefijo de armado
mkdir -p "$T/plantilla"
sed 's|@P@|dev.ben4shot.glibcprueba.sdk36/files/archlinux|g' android/firefox-android.js > "$T/plantilla/firefox-android.js"
correr() {  # correr <raíz>: el script sobre esa raíz, con HOME dentro de ella (ldconfig de mentira: anota que corrió)
  mkdir -p "$1/home/user"
  FIREFOX_LDCONFIG="touch $1/ldconfig-corrio" FIREFOX_RAIZ=$1 FIREFOX_PLANTILLA=$T/plantilla/firefox-android.js HOME=$1/home/user \
    GLIBC_PREFIX=/data/user/0/dev.ben4shot.glibcprueba.sdk36/files/instancias/prueba-1 $S
}
ARCH=$T/arch; FF=$ARCH/usr/lib/firefox/browser/defaults/preferences
mkdir -p "$FF" "$ARCH/usr/share/applications" "$ARCH/etc/ld.so.conf.d"
sed 's|@P@|dev.ben4shot.glibcprueba.sdk36/files/archlinux|g' android/android-prefijo.conf > "$ARCH/etc/ld.so.conf.d/android-prefijo.conf"
printf '[Desktop Entry]\nExec=/usr/lib/firefox/firefox %%u\n' > "$ARCH/usr/share/applications/firefox.desktop"
correr "$ARCH"; rc=$?
caso "sale con 0"  '[ $rc -eq 0 ]'
caso "Arch: escribe android.js en las preferencias de Firefox"  '[ -s $FF/android.js ]'
caso "android.js lleva el prefijo de la instancia, no el de armado"  \
  'grep -q "files/instancias/prueba-1/usr/" $FF/android.js && ! grep -q "files/archlinux" $FF/android.js'
# El lanzador con GPU (/usr/local/bin/firefox) no dibuja en X11 directo hasta B36 (ventana vacía): no se crea aquí.
caso "no crea un firefox.desktop (lo hace solo primer-arranque.sh)"  '[ ! -e $ARCH/home/user/.local/share/applications/firefox.desktop ]'

# El broker de los procesos RDD/Utility (decodificar AAC/H.264 con el ffmpeg del sistema) arma su lista de bibliotecas
# desde ld.so.conf: con el prefijo de armado niega abrir libavcodec y ningún video se reproduce.
LD=$ARCH/etc/ld.so.conf.d/android-prefijo.conf
caso "android-prefijo.conf lleva el prefijo de la instancia"  \
  'grep -q "^/data/user/0/dev.ben4shot.glibcprueba.sdk36/files/instancias/prueba-1/usr/lib$" $LD && ! grep -q "files/archlinux" $LD'
caso "corre ldconfig cuando cambió android-prefijo.conf"  '[ -e $ARCH/ldconfig-corrio ]'
rm -f "$ARCH/ldconfig-corrio"

touch -d '2026-01-01' "$FF/android.js"
correr "$ARCH"
caso "otra sesión no reescribe android.js si ya está al día"  '[ "$(stat -c %Y $FF/android.js)" = "$(date -d 2026-01-01 +%s)" ]'
caso "otra sesión no vuelve a correr ldconfig si android-prefijo.conf ya está al día"  '[ ! -e $ARCH/ldconfig-corrio ]'

DEB=$T/debian; FE=$DEB/usr/lib/firefox-esr/browser/defaults/preferences
mkdir -p "$FE"
correr "$DEB"; rc=$?
caso "Debian: escribe android.js en las preferencias de firefox-esr"  '[ $rc -eq 0 ] && grep -q "files/instancias/prueba-1/usr/" $FE/android.js'

NADA=$T/nada; mkdir -p "$NADA"
correr "$NADA"; rc=$?
caso "sin Firefox no crea nada y sale con 0"  '[ $rc -eq 0 ] && [ ! -e $NADA/usr/lib ] && [ ! -e $NADA/home/user/.local ]'

caso "sesion-android corre firefox-ajustes"  'grep -q "comun/firefox-ajustes" escritorios/sesion-android'
caso "primer-arranque.sh usa firefox-ajustes en vez de su bloque propio"  \
  'grep -q "comun/firefox-ajustes" apk/primer-arranque.sh && ! grep -q "^FF=/usr/lib/firefox" apk/primer-arranque.sh'

# El lanzador con GPU (mesa-gl/firefox → /usr/local/bin/firefox; el panel lo halla primero en el PATH) saltaba la GPU en
# X11 directo porque Zink por drisw dejaba la ventana vacía. Con DRI3 en el servidor, con-gpu elige kopper ahí (B36, Paso
# 1, prueba 16): el lanzador ya no hace excepción.
L=mesa-gl/firefox
caso "el lanzador con GPU no hace excepción en X11 directo"  '! grep -q "x11-directo" $L'

# El lanzador (/usr/local/bin/firefox) tiene que llegar a las instancias que ya existen al abrirlas, como sesion-android.
caso "la capa de sesión lleva mesa-gl/firefox"  'grep -q "\"mesa-gl/firefox\"" app/build.gradle.kts'
caso "CapaSesion lo pone en /usr/local/bin/firefox"  \
  'grep -A1 "\"mesa-gl/firefox\"" app/src/main/java/dev/ben4shot/glibcprueba/CapaSesion.java | grep -q "usr/local/bin/firefox"'

echo "fallas: $fallas"
[ $fallas -eq 0 ]
