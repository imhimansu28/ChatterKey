package app.chatterkey.android;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.UUID;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

final class SettingsStore {
    private static final String ALIAS = "chatterkey.provider-credentials.v1";
    private final SharedPreferences preferences;

    SettingsStore(Context context) {
        this(context.getSharedPreferences("chatterkey", Context.MODE_PRIVATE));
    }

    SettingsStore(SharedPreferences preferences) {
        this.preferences = preferences;
    }

    String provider() {
        return preferences.getString("provider", "google");
    }

    JSONObject settings(String provider) throws Exception {
        JSONObject catalog = CoreBridge.catalog();
        JSONArray providers = catalog.getJSONArray("providers");
        JSONObject connection = null;
        for (int i = 0; i < providers.length(); i++) {
            if (providers.getJSONObject(i).getString("id").equals(provider))
                connection = providers.getJSONObject(i);
        }
        if (connection == null) throw new IllegalArgumentException("Unsupported connection.");
        String saved = preferences.getString("settings." + provider, null);
        if (saved != null) return new JSONObject(saved);
        return new JSONObject()
                .put("provider", provider)
                .put("model", connection.getString("model"))
                .put("systemPrompt", catalog.getString("defaultPrompt"))
                .put("outputMode", "translateEnglish")
                .put("smartPolish", true)
                .put("spokenCommandsEnabled", true)
                .put("personalDictionary", new JSONArray())
                .put("voiceSnippets", new JSONArray())
                .put("costRates", catalog.getJSONObject("defaultRates"));
    }

    String credential(String provider) throws Exception {
        String encoded = preferences.getString("credential." + provider, "");
        if (encoded.isEmpty()) return "";
        String[] parts = encoded.split(":", -1);
        if (parts.length != 2)
            throw new IllegalStateException(
                    "Saved credential is unreadable; re-enter it in Settings.");
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(
                Cipher.DECRYPT_MODE,
                key(false),
                new GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)));
        cipher.updateAAD(provider.getBytes(StandardCharsets.UTF_8));
        return new String(
                cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), StandardCharsets.UTF_8);
    }

    void save(JSONObject settings, String credential) throws Exception {
        String provider = settings.getString("provider");
        if (!provider.equals("google") && !provider.equals("openRouter"))
            throw new IllegalArgumentException("Unsupported connection.");
        if (settings.getString("model").trim().isEmpty())
            throw new IllegalArgumentException("Enter an audio-capable model ID.");
        String encrypted = "";
        if (!credential.trim().isEmpty()) {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key(true));
            cipher.updateAAD(provider.getBytes(StandardCharsets.UTF_8));
            encrypted =
                    Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP)
                            + ":"
                            + Base64.encodeToString(
                                    cipher.doFinal(
                                            credential.trim().getBytes(StandardCharsets.UTF_8)),
                                    Base64.NO_WRAP);
        }
        if (!preferences
                .edit()
                .putString("provider", provider)
                .putString("settings." + provider, settings.toString())
                .putString("credential." + provider, encrypted)
                .commit()) throw new IllegalStateException("Settings could not be saved.");
    }

    private SecretKey key(boolean create) throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        if (store.containsAlias(ALIAS)) return (SecretKey) store.getKey(ALIAS, null);
        if (!create)
            throw new IllegalStateException(
                    "Credential key unavailable. Re-enter this provider key in Settings.");
        KeyGenerator generator =
                KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(
                new KeyGenParameterSpec.Builder(
                                ALIAS,
                                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .build());
        return generator.generateKey();
    }

    static JSONArray entries(String text, boolean snippets) throws Exception {
        JSONArray entries = new JSONArray();
        for (String line : text.split("\n")) {
            if (line.trim().isEmpty()) continue;
            int split = line.indexOf("=>");
            if (split <= 0 || line.substring(split + 2).trim().isEmpty())
                throw new IllegalArgumentException(
                        "Use one spoken phrase => replacement per line.");
            entries.put(
                    new JSONObject()
                            .put("id", UUID.randomUUID().toString())
                            .put(snippets ? "cue" : "spoken", line.substring(0, split).trim())
                            .put(
                                    snippets ? "content" : "replacement",
                                    line.substring(split + 2).trim().replace("\\n", "\n")));
        }
        return entries;
    }

    static String displayEntries(JSONArray values, boolean snippets) throws Exception {
        StringBuilder result = new StringBuilder();
        for (int i = 0; i < values.length(); i++) {
            JSONObject value = values.getJSONObject(i);
            result.append(value.getString(snippets ? "cue" : "spoken"))
                    .append(" => ")
                    .append(
                            value.getString(snippets ? "content" : "replacement")
                                    .replace("\n", "\\n"))
                    .append('\n');
        }
        return result.toString();
    }
}
