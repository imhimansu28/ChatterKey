package app.chatterkey.android;

import org.json.JSONObject;

import java.nio.charset.StandardCharsets;

final class CoreBridge {
    static {
        System.loadLibrary("chatterkey_jni");
    }

    private CoreBridge() {}

    private static native byte[] call(byte[] input, byte[] audio);

    static JSONObject execute(JSONObject input, byte[] bytes) throws Exception {
        byte[] output = call(input.toString().getBytes(StandardCharsets.UTF_8), bytes);
        if (output == null)
            throw new IllegalStateException("Shared processing core returned no result.");
        JSONObject envelope = new JSONObject(new String(output, StandardCharsets.UTF_8));
        if (!envelope.optBoolean("ok"))
            throw new IllegalStateException(envelope.optString("error", "Processing failed."));
        return envelope.getJSONObject("value");
    }

    static JSONObject catalog() throws Exception {
        return execute(new JSONObject().put("operation", "catalog"), null);
    }
}
