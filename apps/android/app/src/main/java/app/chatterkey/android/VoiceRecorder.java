package app.chatterkey.android;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Future;

final class VoiceRecorder {
    static final int SAMPLE_RATE = 16_000;
    static final int MAX_SECONDS = 120;
    private volatile boolean recording;
    private volatile float level;
    private AudioRecord recorder;
    private Future<byte[]> captured;

    void start(Context context, ExecutorService worker, Runnable ended) {
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED) {
            throw new SecurityException("Microphone permission is required.");
        }
        int minimum =
                AudioRecord.getMinBufferSize(
                        SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
        if (minimum <= 0)
            throw new IllegalStateException("Microphone does not support 16 kHz PCM audio.");
        AudioRecord device =
                new AudioRecord(
                        MediaRecorder.AudioSource.MIC,
                        SAMPLE_RATE,
                        AudioFormat.CHANNEL_IN_MONO,
                        AudioFormat.ENCODING_PCM_16BIT,
                        Math.max(minimum * 2, 8192));
        if (device.getState() != AudioRecord.STATE_INITIALIZED) {
            device.release();
            throw new IllegalStateException("Microphone unavailable.");
        }
        try {
            device.startRecording();
            if (device.getRecordingState() != AudioRecord.RECORDSTATE_RECORDING)
                throw new IllegalStateException("Microphone did not start.");
        } catch (RuntimeException error) {
            device.release();
            throw error;
        }
        recorder = device;
        recording = true;
        try {
            captured =
                    worker.submit(
                            () -> {
                                ByteArrayOutputStream pcm = new ByteArrayOutputStream();
                                byte[] buffer = new byte[4096];
                                try {
                                    while (recording
                                            && pcm.size() < MAX_SECONDS * SAMPLE_RATE * 2) {
                                        int count =
                                                device.read(
                                                        buffer,
                                                        0,
                                                        Math.min(
                                                                buffer.length,
                                                                MAX_SECONDS * SAMPLE_RATE * 2
                                                                        - pcm.size()));
                                        if (count < 0 && recording)
                                            throw new IllegalStateException(
                                                    "Microphone interrupted. Retry explicitly.");
                                        if (count > 0) {
                                            level = audioLevel(buffer, count);
                                            pcm.write(buffer, 0, count);
                                        }
                                    }
                                    return wav(pcm.toByteArray());
                                } finally {
                                    if (recording) ended.run();
                                }
                            });
        } catch (RuntimeException error) {
            stop();
            release();
            throw error;
        }
    }

    Future<byte[]> stop() {
        recording = false;
        level = 0;
        if (recorder != null) {
            try {
                recorder.stop();
            } catch (IllegalStateException ignored) {
                /* Device may have disconnected. */
            }
        }
        return captured;
    }

    void release() {
        if (recorder != null) {
            recorder.release();
            recorder = null;
        }
        captured = null;
    }

    float level() {
        return level;
    }

    static float audioLevel(byte[] pcm, int count) {
        double sum = 0;
        int samples = count / 2;
        if (samples == 0) return 0;
        for (int i = 0; i < samples * 2; i += 2) {
            short sample = (short) ((pcm[i] & 0xff) | (pcm[i + 1] << 8));
            double value = sample / 32768.0;
            sum += value * value;
        }
        return (float) Math.min(1, Math.sqrt(sum / samples) * 4);
    }

    static byte[] wav(byte[] pcm) {
        if (pcm.length % 2 != 0)
            throw new IllegalArgumentException("PCM samples must be 16-bit aligned.");
        ByteBuffer result = ByteBuffer.allocate(44 + pcm.length).order(ByteOrder.LITTLE_ENDIAN);
        result.put(new byte[] {'R', 'I', 'F', 'F'})
                .putInt(36 + pcm.length)
                .put(new byte[] {'W', 'A', 'V', 'E', 'f', 'm', 't', ' '});
        result.putInt(16)
                .putShort((short) 1)
                .putShort((short) 1)
                .putInt(SAMPLE_RATE)
                .putInt(SAMPLE_RATE * 2)
                .putShort((short) 2)
                .putShort((short) 16)
                .put(new byte[] {'d', 'a', 't', 'a'})
                .putInt(pcm.length)
                .put(pcm);
        return result.array();
    }
}
