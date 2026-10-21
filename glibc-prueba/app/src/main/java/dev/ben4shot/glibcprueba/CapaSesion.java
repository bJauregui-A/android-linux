package dev.ben4shot.glibcprueba;

import android.content.Context;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.security.MessageDigest;
import java.util.zip.GZIPInputStream;

// Actualiza solo perfiles y supervisores gestionados por la app; nunca reemplaza el rootfs entero.
final class CapaSesion {
    private static final String TAG = "SESION";
    private static final String ASSET = "session-layer.tgz";
    private static final byte[] BLOQUE = new byte[512];

    private CapaSesion() { }

    static synchronized boolean actualizar(Context contexto, AdaptadorInstalacion instalacion,
                                           File raiz) {
        File estado = new File(raiz, instalacion.estadoSesion().substring(1));
        File version = new File(estado, "session-layer.sha256");
        try {
            estado.mkdirs();
            String hash = hashAsset(contexto);
            if (hash.equals(leer(version))) return true;
            extraer(contexto, raiz, instalacion.perfilesSesion());
            File temporal = new File(estado, version.getName() + ".tmp");
            try (FileOutputStream out = new FileOutputStream(temporal)) {
                out.write((hash + "\n").getBytes(java.nio.charset.StandardCharsets.US_ASCII));
                out.getFD().sync();
            }
            mover(temporal, version);
            Log.i(TAG, "capa de sesión actualizada: " + hash);
            return true;
        } catch (Exception e) {
            Log.e(TAG, "no se pudo actualizar la capa de sesión; no se inicia un perfil antiguo", e);
            return false;
        }
    }

    private static String leer(File archivo) {
        try (FileInputStream in = new FileInputStream(archivo)) {
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            byte[] buffer = new byte[128];
            for (int n; (n = in.read(buffer)) != -1; ) bytes.write(buffer, 0, n);
            return new String(bytes.toByteArray(), java.nio.charset.StandardCharsets.US_ASCII).trim();
        } catch (IOException ignorada) {
            return "";
        }
    }

    private static String hashAsset(Context contexto) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream in = contexto.getAssets().open(ASSET)) {
            byte[] buffer = new byte[8192];
            for (int n; (n = in.read(buffer)) != -1; ) digest.update(buffer, 0, n);
        }
        StringBuilder hex = new StringBuilder(64);
        for (byte b : digest.digest()) hex.append(String.format(java.util.Locale.ROOT, "%02x", b & 0xff));
        return hex.toString();
    }

    private static void extraer(Context contexto, File raiz, String perfiles) throws IOException {
        try (GZIPInputStream in = new GZIPInputStream(contexto.getAssets().open(ASSET))) {
            while (leerBloque(in)) {
                if (todosCero(BLOQUE)) break;
                String nombre = cadena(BLOQUE, 0, 100);
                String prefijo = cadena(BLOQUE, 345, 155);
                if (!prefijo.isEmpty()) nombre = prefijo + "/" + nombre;
                long modo = octal(BLOQUE, 100, 8);
                long tamano = octal(BLOQUE, 124, 12);
                int tipo = BLOQUE[156] & 0xff;
                File destino = destino(raiz, perfiles, nombre);
                if (destino != null && tipo == '5') {
                    destino.mkdirs();
                } else if (destino != null && (tipo == 0 || tipo == '0')) {
                    escribir(in, destino, tamano, modo);
                } else {
                    saltar(in, tamano);
                }
                long relleno = (512 - (tamano % 512)) % 512;
                saltar(in, relleno);
            }
        }
    }

    private static File destino(File raiz, String perfiles, String nombre) {
        String relativo;
        if (nombre.equals("apk/primer-arranque.sh")) {
            relativo = "usr/local/share/arch-android/primer-arranque.sh";
        } else if (nombre.equals("escritorios/sesion-android")) {
            relativo = "usr/local/bin/sesion-android";
        } else if (nombre.equals("escritorios/autostart-android")) {
            relativo = "usr/local/bin/autostart-android";
        } else if (nombre.equals("escritorios/recorrer-escritorios")) {
            relativo = "usr/local/bin/recorrer-escritorios";
        } else if (nombre.equals("escritorios") || nombre.startsWith("escritorios/")) {
            String cola = nombre.equals("escritorios") ? "" : nombre.substring("escritorios/".length());
            relativo = perfiles.substring(1) + (cola.isEmpty() ? "" : "/" + cola);
        } else {
            return null;
        }
        File archivo = new File(raiz, relativo);
        String canonRaiz;
        String canonArchivo;
        try {
            canonRaiz = raiz.getCanonicalPath() + File.separator;
            canonArchivo = archivo.getCanonicalPath();
        } catch (IOException e) {
            return null;
        }
        return canonArchivo.startsWith(canonRaiz) ? archivo : null;
    }

    private static void escribir(InputStream in, File destino, long tamano, long modo) throws IOException {
        File padre = destino.getParentFile();
        if (padre == null || !padre.mkdirs() && !padre.isDirectory())
            throw new IOException("no se pudo crear " + padre);
        File temporal = new File(padre, destino.getName() + ".session-new");
        try (FileOutputStream out = new FileOutputStream(temporal)) {
            copiarExacto(in, out, tamano);
            out.getFD().sync();
        }
        mover(temporal, destino);
        if (!destino.setExecutable((modo & 0111) != 0, false))
            throw new IOException("no se pudo fijar modo ejecutable de " + destino);
    }

    private static void mover(File origen, File destino) throws IOException {
        try {
            java.nio.file.Files.move(origen.toPath(), destino.toPath(),
                    java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                    java.nio.file.StandardCopyOption.ATOMIC_MOVE);
        } catch (java.nio.file.AtomicMoveNotSupportedException e) {
            java.nio.file.Files.move(origen.toPath(), destino.toPath(),
                    java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        }
    }

    private static boolean leerBloque(InputStream in) throws IOException {
        int leidos = 0;
        while (leidos < BLOQUE.length) {
            int n = in.read(BLOQUE, leidos, BLOQUE.length - leidos);
            if (n < 0) {
                if (leidos == 0) return false;
                throw new IOException("cabecera tar incompleta");
            }
            leidos += n;
        }
        return true;
    }

    private static String cadena(byte[] bloque, int inicio, int largo) {
        int fin = inicio;
        while (fin < inicio + largo && bloque[fin] != 0) fin++;
        return new String(bloque, inicio, fin - inicio, java.nio.charset.StandardCharsets.UTF_8);
    }

    private static long octal(byte[] bloque, int inicio, int largo) throws IOException {
        long valor = 0;
        boolean digito = false;
        for (int i = inicio; i < inicio + largo && bloque[i] != 0; i++) {
            int c = bloque[i] & 0xff;
            if (c == ' ' && !digito) continue;
            if (c < '0' || c > '7') throw new IOException("campo octal tar inválido");
            digito = true;
            valor = (valor << 3) + c - '0';
        }
        return valor;
    }

    private static boolean todosCero(byte[] bytes) {
        for (byte b : bytes) if (b != 0) return false;
        return true;
    }

    private static void copiarExacto(InputStream in, FileOutputStream out, long tamano) throws IOException {
        byte[] buffer = new byte[8192];
        while (tamano > 0) {
            int n = in.read(buffer, 0, (int) Math.min(buffer.length, tamano));
            if (n < 0) throw new IOException("archivo tar truncado");
            out.write(buffer, 0, n);
            tamano -= n;
        }
    }

    private static void saltar(InputStream in, long tamano) throws IOException {
        long restante = tamano;
        byte[] buffer = new byte[4096];
        while (restante > 0) {
            long n = in.skip(restante);
            if (n <= 0) {
                int leido = in.read(buffer, 0, (int) Math.min(buffer.length, restante));
                if (leido < 0) throw new IOException("archivo tar truncado");
                n = leido;
            }
            restante -= n;
        }
    }
}
