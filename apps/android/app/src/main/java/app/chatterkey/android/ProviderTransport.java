package app.chatterkey.android;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.URL;
import java.util.Iterator;
import java.util.concurrent.CancellationException;

import javax.net.ssl.HttpsURLConnection;

final class ProviderTransport {
    private volatile HttpsURLConnection connection;
    private volatile boolean cancelled;

    void cancel() {
        cancelled = true;
        HttpsURLConnection active = connection;
        if (active != null) active.disconnect();
    }

    JSONObject process(
            JSONObject settings, String credential, byte[] audio, String selected, double duration)
            throws Exception {
        JSONObject input =
                new JSONObject()
                        .put("operation", "request")
                        .put("settings", settings)
                        .put("credential", credential);
        if (selected != null) input.put("selectedText", selected);
        JSONObject request = CoreBridge.execute(input, audio);
        checkCancellation();
        URL url = new URL(request.getString("url"));
        if (!url.getProtocol().equals("https")
                || !(url.getHost().equals("generativelanguage.googleapis.com")
                        || url.getHost().equals("openrouter.ai"))) {
            throw new IllegalStateException("Provider endpoint rejected.");
        }
        HttpsURLConnection active = (HttpsURLConnection) url.openConnection();
        connection = active;
        try {
            checkCancellation();
            active.setInstanceFollowRedirects(false);
            active.setUseCaches(false);
            active.setConnectTimeout(40_000);
            active.setReadTimeout(40_000);
            active.setRequestMethod("POST");
            active.setDoOutput(true);
            JSONObject headers = request.getJSONObject("headers");
            for (Iterator<String> names = headers.keys(); names.hasNext(); ) {
                String name = names.next();
                active.setRequestProperty(name, headers.getString(name));
            }
            active.setRequestProperty("Connection", "close");
            byte[] body =
                    request.getString("body").getBytes(java.nio.charset.StandardCharsets.UTF_8);
            // Streaming mode disallows automatic authentication/redirect replay of the body.
            active.setFixedLengthStreamingMode(body.length);
            try (OutputStream output = active.getOutputStream()) {
                output.write(body);
            }
            checkCancellation();
            int status = active.getResponseCode();
            InputStream stream = status >= 400 ? active.getErrorStream() : active.getInputStream();
            ByteArrayOutputStream response = new ByteArrayOutputStream();
            if (stream != null)
                try (InputStream source = stream) {
                    byte[] buffer = new byte[8192];
                    int count;
                    while ((count = source.read(buffer)) != -1) {
                        checkCancellation();
                        if (response.size() + count > 1_000_000)
                            throw new IllegalStateException("Provider response is too large.");
                        response.write(buffer, 0, count);
                    }
                }
            checkCancellation();
            input.remove("credential");
            input.put("operation", "response")
                    .put("status", status)
                    .put("durationSeconds", duration);
            return CoreBridge.execute(input, response.toByteArray());
        } finally {
            active.disconnect();
            connection = null;
        }
    }

    private void checkCancellation() {
        if (cancelled || Thread.currentThread().isInterrupted()) throw new CancellationException();
    }
}
