package dev.ben4shot.glibcprueba;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import android.webkit.MimeTypeMap;

import java.io.File;
import java.io.FileNotFoundException;

// Archivos del prefijo Linux para otras apps de Android, solo lectura y solo los que se
// les pasan con FLAG_GRANT_READ_URI_PERMISSION (Abrir.java): content://<paquete>.archivos/<ruta
// de Linux>. No exportado: sin permiso concedido nadie puede pedir nada.
public class Archivos extends ContentProvider {
    static Uri uri(Context c, String ruta) {
        return new Uri.Builder().scheme("content").authority(c.getPackageName() + ".archivos")
                .path(ruta).build();
    }

    // Ruta de Linux ya resuelta (android-abrir hace realpath: los enlaces del prefijo apuntan a
    // rutas de Linux, aquí no se pueden seguir) → archivo real: lo de Android (/storage,
    // /sdcard) tal cual, el resto dentro del prefijo. Sin "..": no sale de ahí.
    static File real(Context c, String ruta) {
        if (ruta == null || !ruta.startsWith("/") || ("/" + ruta + "/").contains("/../")) return null;
        if (ruta.startsWith("/storage/") || ruta.startsWith("/sdcard/")) return new File(ruta);
        return new File(SistemaLinux.raizSeleccionada(c), ruta);
    }

    static String tipo(String nombre) {
        int i = nombre.lastIndexOf('.');
        String t = i < 0 ? null : MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(nombre.substring(i + 1).toLowerCase());
        return t != null ? t : "application/octet-stream";
    }

    private File archivo(Uri u) throws FileNotFoundException {
        File f = real(getContext(), u.getPath());
        if (f == null || !f.isFile()) throw new FileNotFoundException(u.toString());
        return f;
    }

    @Override
    public boolean onCreate() { return true; }

    @Override
    public ParcelFileDescriptor openFile(Uri u, String modo) throws FileNotFoundException {
        if (!"r".equals(modo)) throw new SecurityException("solo lectura");
        return ParcelFileDescriptor.open(archivo(u), ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Override
    public String getType(Uri u) { return tipo(u.getLastPathSegment()); }

    // Nombre y tamaño: lo que piden los visores al abrir un content://
    @Override
    public Cursor query(Uri u, String[] columnas, String sel, String[] args, String orden) {
        File f;
        try {
            f = archivo(u);
        } catch (FileNotFoundException e) {
            return null;
        }
        if (columnas == null) columnas = new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE};
        MatrixCursor c = new MatrixCursor(columnas);
        Object[] fila = new Object[columnas.length];
        for (int i = 0; i < columnas.length; i++)
            fila[i] = OpenableColumns.DISPLAY_NAME.equals(columnas[i]) ? f.getName()
                    : OpenableColumns.SIZE.equals(columnas[i]) ? (Object) f.length() : null;
        c.addRow(fila);
        return c;
    }

    @Override
    public Uri insert(Uri u, ContentValues v) { throw new UnsupportedOperationException(); }

    @Override
    public int delete(Uri u, String s, String[] a) { throw new UnsupportedOperationException(); }

    @Override
    public int update(Uri u, ContentValues v, String s, String[] a) { throw new UnsupportedOperationException(); }
}
