package dev.ben4shot.glibcprueba;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.system.ErrnoException;
import android.system.Os;
import android.system.OsConstants;
import android.system.StructPollfd;
import android.system.StructStat;
import android.util.Log;

import java.io.File;
import java.io.FileDescriptor;

// Audio Linux → Android. PipeWire (dentro de sway) tiene un sink "Android" de
// module-pipe-tunnel que escribe PCM S16LE 48 kHz estéreo en /tmp/audio-android
// (sway/pipewire/10-android.conf); aquí se lee ese FIFO y se toca con un AudioTrack.
//  - El FIFO se abre O_RDWR: no bloquea si PipeWire aún no lo abrió y no da EOF si se reinicia.
//  - Pipe chico (F_SETPIPE_SZ): si los relojes se separan, lo que sobra lo descarta PipeWire
//    (EAGAIN) en vez de acumular latencia.
//  - Tras 2 s de silencio se pausa el AudioTrack (batería); vuelve con la primera muestra.
class Audio {
    private static final String TAG = "AUDIO";
    private static final String FIFO = "tmp/audio-android";
    private static final int TASA = 48000, F_SETPIPE_SZ = 1031, PIPE = 16384;
    private static TerminalService servicio;
    private static Thread hilo;

    static synchronized void iniciar(TerminalService s) {
        servicio = s;
        if (hilo != null && hilo.isAlive()) return;
        hilo = new Thread(Audio::tocar, "audio");
        hilo.setPriority(Thread.MAX_PRIORITY);
        hilo.start();
    }

    private static void tocar() {
        File fifo = new File(SistemaLinux.raizSeleccionada(servicio), FIFO);
        int min = AudioTrack.getMinBufferSize(TASA, AudioFormat.CHANNEL_OUT_STEREO,
                AudioFormat.ENCODING_PCM_16BIT);
        AudioTrack pista = new AudioTrack.Builder()
                .setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_GAME)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setAudioFormat(new AudioFormat.Builder().setSampleRate(TASA)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).build())
                .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                .setBufferSizeInBytes(min * 2)
                .build();
        byte[] buf = new byte[4096];
        while (servicio.escritorioVivo()) {
            FileDescriptor fd = null;
            try {
                // PipeWire lo crea al cargar el módulo; esperar a que exista
                if (!fifo.exists()) { Thread.sleep(1000); continue; }
                fd = Os.open(fifo.getPath(), OsConstants.O_RDWR | OsConstants.O_CLOEXEC, 0);
                long inodo = Os.fstat(fd).st_ino;
                try { Os.fcntlInt(fd, F_SETPIPE_SZ, PIPE); } catch (ErrnoException e) { Log.w(TAG, "pipe", e); }
                Log.i(TAG, "leyendo " + fifo);
                long ultimoSonido = 0;
                StructPollfd p = new StructPollfd();
                p.fd = fd;
                p.events = (short) OsConstants.POLLIN;
                while (servicio.escritorioVivo()) {
                    if (Os.poll(new StructPollfd[]{p}, 1000) == 0) {
                        if (pista.getPlayState() == AudioTrack.PLAYSTATE_PLAYING
                                && System.currentTimeMillis() - ultimoSonido > 2000) {
                            pista.pause(); pista.flush();
                        }
                        // PipeWire reiniciado: el FIFO es otro
                        StructStat st = fifo.exists() ? Os.stat(fifo.getPath()) : null;
                        if (st == null || st.st_ino != inodo) break;
                        continue;
                    }
                    int n = Os.read(fd, buf, 0, buf.length);
                    if (n <= 0) continue;
                    if (!silencio(buf, n)) ultimoSonido = System.currentTimeMillis();
                    else if (System.currentTimeMillis() - ultimoSonido > 2000) {
                        if (pista.getPlayState() == AudioTrack.PLAYSTATE_PLAYING) { pista.pause(); pista.flush(); }
                        continue;
                    }
                    if (pista.getPlayState() != AudioTrack.PLAYSTATE_PLAYING) pista.play();
                    pista.write(buf, 0, n & ~3);
                }
            } catch (Exception e) {
                Log.w(TAG, "audio", e);
                try { Thread.sleep(1000); } catch (InterruptedException ignored) { }
            } finally {
                if (fd != null) try { Os.close(fd); } catch (ErrnoException ignored) { }
            }
        }
        pista.release();
        Log.i(TAG, "fin");
    }

    private static boolean silencio(byte[] b, int n) {
        for (int i = 0; i < n; i++) if (b[i] != 0) return false;
        return true;
    }
}
