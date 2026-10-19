package dev.ben4shot.glibcprueba;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;

// Ejecuta files/test.sh desde el proceso de la app (con su seccomp y SELinux)
// y escribe la salida en pantalla y en logcat (tag GLIBC).
public class MainActivity extends Activity {
    private static final String TAG = "GLIBC";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        TextView out = new TextView(this);
        out.setTextIsSelectable(true);
        out.setTypeface(android.graphics.Typeface.MONOSPACE);
        ScrollView scroll = new ScrollView(this);
        scroll.addView(out);
        setContentView(scroll);

        new Thread(() -> {
            String result = run();
            runOnUiThread(() -> out.setText(result));
        }).start();
    }

    private String run() {
        File script = new File(getFilesDir(), "test.sh");
        StringBuilder sb = new StringBuilder();
        Log.i(TAG, "=== inicio " + getPackageName() + " targetSdk=" + getApplicationInfo().targetSdkVersion);
        if (!script.exists()) {
            Log.i(TAG, "falta " + script);
            return "falta " + script;
        }
        try {
            ProcessBuilder pb = new ProcessBuilder("/system/bin/sh", script.getAbsolutePath());
            pb.directory(getFilesDir());
            pb.redirectErrorStream(true);
            pb.environment().put("APP_FILES", getFilesDir().getAbsolutePath());
            pb.environment().put("NATIVE_DIR", getApplicationInfo().nativeLibraryDir);
            Process p = pb.start();
            try (BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()))) {
                String line;
                while ((line = r.readLine()) != null) {
                    Log.i(TAG, line);
                    sb.append(line).append('\n');
                }
            }
            int code = p.waitFor();
            Log.i(TAG, "=== fin exit=" + code);
            sb.append("exit=").append(code);
        } catch (Exception e) {
            Log.e(TAG, "error", e);
            sb.append(e);
        }
        return sb.toString();
    }
}
