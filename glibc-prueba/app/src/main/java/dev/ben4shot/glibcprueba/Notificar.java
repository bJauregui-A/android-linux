package dev.ben4shot.glibcprueba;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.os.Build;
import android.os.Process;
import android.text.Html;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

// Notificaciones D-Bus de Linux → Android. android-notificaciones (android/ en el repo) toma
// org.freedesktop.Notifications en el bus de sesión de sway, se conecta a
// /run/android-notificar.sock del prefijo y queda conectado. Una línea JSON por mensaje:
//   Linux → app: {"op":"mostrar","id","app","titulo","cuerpo","urgencia","acciones":[[clave,texto]...]}
//                {"op":"cerrar","id"}
//   app → Linux: {"op":"accion","id","clave"} (tocar la notificación = "default")
//                {"op":"cerrada","id"} (descartada en Android)
// Tocar abre el escritorio (WaylandActivity), que avisa con clic().
class Notificar {
    private static final String TAG = "NOTIFICAR";
    private static final String ETIQUETA = "linux";
    private static final String DESCARTE = "dev.ben4shot.glibcprueba.DESCARTE";
    static final String EXTRA_ID = "notificacion";
    static final String EXTRA_CLAVE = "accion";
    // WaylandActivity está exportada: sin esto cualquier app podría inventar clics
    private static final String EXTRA_SECRETO = "secreto";
    private static final String SECRETO = java.util.UUID.randomUUID().toString();
    // urgencia D-Bus 0/1/2 → canal
    private static final String[] CANALES = {"linux-baja", "linux", "linux-urgente"};

    private static Context ctx;
    private static NotificationManager nm;
    private static LocalServerSocket servidor;
    // dueño del descriptor del servidor (ver Mandos)
    private static LocalSocket enlazado;
    private static OutputStream cliente; // el daemon conectado, o null

    static synchronized void iniciar(Context c) {
        if (servidor != null) return;
        ctx = c.getApplicationContext();
        nm = ctx.getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(CANALES[0], "Linux (baja)", NotificationManager.IMPORTANCE_LOW));
        nm.createNotificationChannel(new NotificationChannel(CANALES[1], "Linux", NotificationManager.IMPORTANCE_DEFAULT));
        nm.createNotificationChannel(new NotificationChannel(CANALES[2], "Linux (urgente)", NotificationManager.IMPORTANCE_HIGH));
        ctx.registerReceiver(new BroadcastReceiver() {
            @Override
            public void onReceive(Context c, Intent i) {
                enviar("cerrada", i.getIntExtra(EXTRA_ID, 0), null);
            }
        }, new IntentFilter(DESCARTE), Build.VERSION.SDK_INT >= 33 ? Context.RECEIVER_NOT_EXPORTED : 0);
        File socket = new File(c.getFilesDir(), TerminalService.PREFIJO + "/run/android-notificar.sock");
        try {
            socket.getParentFile().mkdirs();
            socket.delete();
            enlazado = new LocalSocket(LocalSocket.SOCKET_STREAM);
            enlazado.bind(new LocalSocketAddress(socket.getPath(), LocalSocketAddress.Namespace.FILESYSTEM));
            servidor = new LocalServerSocket(enlazado.getFileDescriptor());
            new Thread(Notificar::aceptar, "notificar").start();
        } catch (Exception e) {
            Log.e(TAG, "socket", e);
        }
    }

    private static void aceptar() {
        while (true) {
            try (LocalSocket c = servidor.accept()) {
                if (c.getPeerCredentials().getUid() != Process.myUid()) continue;
                // un daemon nuevo (sway reiniciado): las de antes ya no tienen a quién avisar
                nm.cancelAll();
                synchronized (Notificar.class) { cliente = c.getOutputStream(); }
                BufferedReader r = new BufferedReader(new InputStreamReader(c.getInputStream(),
                        StandardCharsets.UTF_8));
                String linea;
                while ((linea = r.readLine()) != null) {
                    try {
                        recibir(new JSONObject(linea));
                    } catch (Exception e) {
                        Log.w(TAG, linea, e);
                    }
                }
            } catch (Exception e) {
                Log.w(TAG, "cliente", e);
            }
            synchronized (Notificar.class) { cliente = null; }
            // sin daemon nadie recibe los clics: se quitan
            for (android.service.notification.StatusBarNotification n : nm.getActiveNotifications())
                if (ETIQUETA.equals(n.getTag())) nm.cancel(ETIQUETA, n.getId());
        }
    }

    private static void recibir(JSONObject m) throws Exception {
        int id = m.getInt("id");
        if ("cerrar".equals(m.getString("op"))) {
            nm.cancel(ETIQUETA, id);
            return;
        }
        int urgencia = Math.max(0, Math.min(2, m.optInt("urgencia", 1)));
        String app = m.optString("app");
        String titulo = m.optString("titulo");
        CharSequence cuerpo = Html.fromHtml(m.optString("cuerpo"), Html.FROM_HTML_MODE_COMPACT);
        Notification.Builder b = new Notification.Builder(ctx, CANALES[urgencia])
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(titulo.isEmpty() ? app : titulo)
                .setContentText(cuerpo)
                .setStyle(new Notification.BigTextStyle().bigText(cuerpo))
                .setContentIntent(clic(id, "default"))
                .setDeleteIntent(PendingIntent.getBroadcast(ctx, id,
                        new Intent(DESCARTE).setPackage(ctx.getPackageName()).putExtra(EXTRA_ID, id),
                        PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT))
                .setAutoCancel(true);
        if (!app.isEmpty() && !titulo.isEmpty()) b.setSubText(app);
        JSONArray acciones = m.optJSONArray("acciones");
        if (acciones != null) {
            // Android muestra hasta 3 botones; "default" es tocar la notificación
            for (int i = 0, n = 0; i < acciones.length() && n < 3; i++) {
                JSONArray a = acciones.getJSONArray(i);
                if ("default".equals(a.getString(0))) continue;
                b.addAction(new Notification.Action.Builder(null, a.getString(1),
                        clic(id, a.getString(0))).build());
                n++;
            }
        }
        nm.notify(ETIQUETA, id, b.build());
    }

    // Tocar o un botón: abre el escritorio y avisa la acción a Linux (WaylandActivity → clic)
    private static PendingIntent clic(int id, String clave) {
        Intent i = new Intent(ctx, WaylandActivity.class)
                .setAction("notificacion:" + id + ":" + clave) // un PendingIntent distinto por botón
                .putExtra(EXTRA_ID, id)
                .putExtra(EXTRA_CLAVE, clave)
                .putExtra(EXTRA_SECRETO, SECRETO);
        return PendingIntent.getActivity(ctx, id, i,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    static void clic(Intent i) {
        // nm == null: la app murió y volvió; ese daemon ya no existe
        if (i == null || !i.hasExtra(EXTRA_ID) || nm == null
                || !SECRETO.equals(i.getStringExtra(EXTRA_SECRETO))) return;
        int id = i.getIntExtra(EXTRA_ID, 0);
        nm.cancel(ETIQUETA, id);
        enviar("accion", id, i.getStringExtra(EXTRA_CLAVE));
    }

    private static void enviar(String op, int id, String clave) {
        new Thread(() -> {
            try {
                JSONObject m = new JSONObject().put("op", op).put("id", id);
                if (clave != null) m.put("clave", clave);
                synchronized (Notificar.class) {
                    if (cliente == null) return;
                    cliente.write((m + "\n").getBytes(StandardCharsets.UTF_8));
                    cliente.flush();
                }
            } catch (Exception e) {
                Log.w(TAG, op, e);
            }
        }, "notificar-enviar").start();
    }
}
