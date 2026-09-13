package app.chatterkey.android;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.ContextThemeWrapper;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;

import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.concurrent.ExecutorService;

/** Device-rendered fixtures only: no live editor, microphone, credentials or provider calls. */
public final class KeyboardDeviceChecks extends Instrumentation {
    @Override
    public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        start();
    }

    @Override
    public void onStart() {
        Bundle result = new Bundle();
        try {
            if (CoreBridge.catalog().getJSONArray("providers").length() != 2)
                throw new AssertionError("Shared native core catalog did not load");
            Throwable[] failure = new Throwable[1];
            runOnMainSync(
                    () -> {
                        try {
                            checkUsage();
                            checkSettings(360, 780, 1f);
                            checkSettings(320, 640, 1.3f);
                            checkLayout(360, 1f, false, "keyboard-portrait");
                            checkLayout(320, 1.3f, false, "keyboard-small-large-text");
                            checkLayout(640, 1f, true, "keyboard-landscape");
                        } catch (Throwable error) {
                            failure[0] = error;
                        }
                    });
            if (failure[0] != null)
                throw new AssertionError("Keyboard rendering failed", failure[0]);
            result.putString(
                    "stream",
                    "Native core loaded; portrait/small-large-text/landscape key geometry, symbol"
                            + " pages, voice-state bounds, dashboard/settings fixtures and local"
                            + " counter privacy/reset checks passed. No live editor/audio/network"
                            + " used.\n");
            finish(Activity.RESULT_OK, result);
        } catch (Throwable error) {
            result.putString("stream", android.util.Log.getStackTraceString(error));
            finish(Activity.RESULT_CANCELED, result);
        }
    }

    private void checkUsage() throws Exception {
        android.content.SharedPreferences prefs =
                getTargetContext().getSharedPreferences("fixture.usage", Context.MODE_PRIVATE);
        try {
            prefs.edit().clear().commit();
            UsageStore store = new UsageStore(prefs);
            if (store.enabled()) throw new AssertionError("Usage must be opt-in");
            store.typed(9);
            if (store.total().typed() != 0) throw new AssertionError("Paused counter changed");
            org.json.JSONObject response =
                    CoreBridge.execute(
                            new org.json.JSONObject()
                                    .put("operation", "response")
                                    .put("status", 200)
                                    .put("settings", new SettingsStore(prefs).settings("google")),
                            "{\"choices\":[{\"message\":{\"content\":\"नमस्ते hello\"},\"finish_reason\":\"stop\"}]}"
                                    .getBytes(java.nio.charset.StandardCharsets.UTF_8));
            if (response.getLong("wordCount") != 2)
                throw new AssertionError("Native shared-core word count missing or incorrect");
            store.setEnabled(true);
            long revision = store.revision();
            store.typed(3);
            store.voice(5, 2200, false, revision);
            store.voice(900, 1800, true, revision);
            UsageStore.Totals totals = new UsageStore(prefs).total();
            if (totals.typed() != 3
                    || totals.voice() != 5
                    || totals.dictations() != 1
                    || totals.edits() != 1
                    || totals.millis() != 4000)
                throw new AssertionError("Typed/dictation/edit aggregates are incorrect");
            for (Object value : prefs.getAll().values())
                if (!(value instanceof Long) && !(value instanceof Boolean))
                    throw new AssertionError("Non-aggregate content in usage storage");
            if (store.today().voice() != 5 || store.week().typed() != 3)
                throw new AssertionError("Period totals incorrect");
            String old = "day." + java.time.LocalDate.now().minusDays(35) + ".typed";
            prefs.edit().putLong(old, 30).apply();
            store.typed(1);
            if (prefs.contains(old)) throw new AssertionError("Old daily bucket not pruned");
            store.clear();
            store.voice(100, 1000, false, revision);
            if (store.total().voice() != 0 || store.total().typed() != 0 || !store.enabled())
                throw new AssertionError("Clear resurrected stale counts or changed consent");
            store.setEnabled(false);
            store.voice(5, 1000, false, store.revision());
            if (store.total().dictations() != 0)
                throw new AssertionError("Opt-out did not stop counts");
            android.view.inputmethod.EditorInfo info = new android.view.inputmethod.EditorInfo();
            info.inputType = android.text.InputType.TYPE_CLASS_TEXT;
            if (!UsageStore.allowed(info)) throw new AssertionError("Ordinary editor excluded");
            info.imeOptions = android.view.inputmethod.EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING;
            if (UsageStore.allowed(info)) throw new AssertionError("Private editor counted");
            info.imeOptions = 0;
            info.inputType |= android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD;
            if (UsageStore.allowed(info) || UsageStore.allowed(null))
                throw new AssertionError("Password/unknown editor counted");
        } finally {
            getTargetContext().deleteSharedPreferences("fixture.usage");
        }
    }

    private void checkSettings(int widthDp, int heightDp, float fontScale) throws Exception {
        android.content.SharedPreferences prefs =
                getTargetContext().getSharedPreferences("fixture.settings", Context.MODE_PRIVATE);
        android.content.SharedPreferences counters =
                getTargetContext().getSharedPreferences("fixture.dashboard", Context.MODE_PRIVATE);
        try {
            prefs.edit().clear().commit();
            counters.edit().clear().commit();
            UsageStore usage = new UsageStore(counters);
            usage.setEnabled(true);
            usage.typed(1248);
            usage.voice(864, 735000, false, usage.revision());
            for (int i = 1; i <= 6; i++)
                counters.edit()
                        .putLong("day." + java.time.LocalDate.now().minusDays(i) + ".typed", i * 35)
                        .putLong(
                                "day." + java.time.LocalDate.now().minusDays(i) + ".voice",
                                (7 - i) * 42)
                        .apply();
            Configuration config =
                    new Configuration(getTargetContext().getResources().getConfiguration());
            config.fontScale = fontScale;
            Context context =
                    new ContextThemeWrapper(
                            getTargetContext().createConfigurationContext(config),
                            android.R.style.Theme_Material_Light_NoActionBar);
            SettingsView activity = new SettingsView(context);
            SettingsStore settings = new SettingsStore(prefs);
            View root = activity.createContent(settings, usage, () -> {});
            int width = Math.round(widthDp * context.getResources().getDisplayMetrics().density);
            int height = Math.round(heightDp * context.getResources().getDisplayMetrics().density);
            String name = "settings-" + widthDp;
            renderScreen(root, width, height, name + "-dashboard");
            if (find(root, "Dashboard").getLineCount() != 1)
                throw new AssertionError("Bottom navigation label wraps");
            find(root, "Settings").performClick();
            renderScreen(root, width, height, name + "-provider");
            android.widget.EditText model = (android.widget.EditText) field(activity, "model");
            model.setText("fixture-audio-model");
            find(root, "Dashboard").performClick();
            find(root, "Settings").performClick();
            if (!model.getText().toString().equals("fixture-audio-model"))
                throw new AssertionError("Tabs discarded unsaved settings");
            find(root, "Save settings").performClick();
            if (!settings.settings("google").getString("model").equals("fixture-audio-model"))
                throw new AssertionError("Settings save failed");
            if (settings.settings("openRouter").getString("model").equals("fixture-audio-model"))
                throw new AssertionError("Provider preferences leaked");
            find(root, "Instructions & vocabulary").performClick();
            renderScreen(root, width, height, name + "-advanced-top");
            android.widget.ScrollView[] pages =
                    (android.widget.ScrollView[]) field(activity, "pages");
            android.graphics.Rect visible = new android.graphics.Rect();
            Button save = find(root, "Save settings");
            save.getDrawingRect(visible);
            ((ViewGroup) pages[1].getChildAt(0)).offsetDescendantRectToMyCoords(save, visible);
            pages[1].scrollTo(0, Math.max(0, visible.bottom - pages[1].getHeight()));
            save(root, name + "-advanced-bottom");
            save.getDrawingRect(visible);
            pages[1].offsetDescendantRectToMyCoords(save, visible);
            visible.offset(-pages[1].getScrollX(), -pages[1].getScrollY());
            if (visible.top < 0 || visible.bottom > pages[1].getHeight())
                throw new AssertionError("Save cannot be reached by scrolling");
            find(root, "Practice").performClick();
            renderScreen(root, width, height, name + "-practice");
            if ((((android.widget.EditText) field(activity, "credential")).getImeOptions()
                            & android.view.inputmethod.EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING)
                    == 0) throw new AssertionError("Settings field allows personalized learning");
        } finally {
            getTargetContext().deleteSharedPreferences("fixture.settings");
            getTargetContext().deleteSharedPreferences("fixture.dashboard");
        }
    }

    private void renderScreen(View root, int width, int height, String name) throws Exception {
        root.measure(
                View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY));
        root.layout(0, 0, width, height);
        root.getViewTreeObserver().dispatchOnPreDraw();
        save(root, name);
        checkBounds(root);
    }

    private void checkLayout(int widthDp, float fontScale, boolean landscape, String name)
            throws Exception {
        Configuration config =
                new Configuration(getTargetContext().getResources().getConfiguration());
        config.fontScale = fontScale;
        config.orientation =
                landscape
                        ? Configuration.ORIENTATION_LANDSCAPE
                        : Configuration.ORIENTATION_PORTRAIT;
        Context context =
                new ContextThemeWrapper(
                        getTargetContext().createConfigurationContext(config),
                        android.R.style.Theme_Material_Light_NoActionBar);
        ChatterKeyService service = new ChatterKeyService();
        Method attach = ContextWrapper.class.getDeclaredMethod("attachBaseContext", Context.class);
        attach.setAccessible(true);
        attach.invoke(service, context);
        try {
            View root = service.onCreateInputView();
            // This isolated service intentionally has no editor connection. Render the ordinary
            // idle UI.
            ((View) field(service, "status")).setVisibility(View.GONE);
            Button mic = (Button) field(service, "mic");
            mic.setEnabled(true);
            mic.setAlpha(1);
            int width = Math.round(widthDp * context.getResources().getDisplayMetrics().density);
            render(root, width, name);
            Button space = find(root, "English (India)");
            Button q = find(root, "q");
            if (space == null || q == null || space.getWidth() < q.getWidth() * 3)
                throw new AssertionError("Spacebar must be substantially wider than a letter");
            int[] idleMic = new int[2];
            mic.getLocationInWindow(idleMic);
            int idleHeight = root.getMeasuredHeight();
            KeyboardLayout layout = (KeyboardLayout) field(service, "layout");
            layout.toggleSymbols();
            invoke(service, "buildKeys");
            render(root, width, name + "-symbols");
            if (find(root, "₹") == null)
                throw new AssertionError("English India rupee key missing");
            layout.shift(SystemClock.uptimeMillis());
            invoke(service, "buildKeys");
            render(root, width, name + "-symbols-2");
            if (find(root, "\\") == null) throw new AssertionError("Second symbol page missing");
            layout.reset(false);
            invoke(service, "buildKeys");
            setPhase(service, "RECORDING");
            Field started = service.getClass().getDeclaredField("recordingStartedAt");
            started.setAccessible(true);
            started.setLong(service, SystemClock.elapsedRealtime() - 12000);
            invoke(service, "refresh");
            render(root, width, name + "-recording");
            int[] recordingMic = new int[2];
            mic.getLocationInWindow(recordingMic);
            if (idleHeight != root.getMeasuredHeight() || idleMic[1] != recordingMic[1])
                throw new AssertionError(
                        "Mic must not move underneath a held finger: idle="
                                + idleHeight
                                + " recording="
                                + root.getMeasuredHeight());
            setPhase(service, "PROCESSING");
            invoke(service, "refresh");
            render(root, width, name + "-processing");
            if (mic.isEnabled()) throw new AssertionError("Mic must be disabled during processing");
            VoiceFeedbackView feedback = new VoiceFeedbackView(context, () -> .7);
            feedback.state(true, false, true, SystemClock.elapsedRealtime() - 12000);
            feedback.measure(
                    View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(
                            Math.round(150 * context.getResources().getDisplayMetrics().density),
                            View.MeasureSpec.EXACTLY));
            feedback.layout(0, 0, feedback.getMeasuredWidth(), feedback.getMeasuredHeight());
            save(feedback, name + "-audio-level");
        } finally {
            ((ExecutorService) field(service, "captureWorker")).shutdownNow();
            ((ExecutorService) field(service, "networkWorker")).shutdownNow();
        }
    }

    private void render(View root, int width, String name) throws Exception {
        root.measure(
                View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
        root.layout(0, 0, width, root.getMeasuredHeight());
        root.getViewTreeObserver().dispatchOnPreDraw();
        save(root, name);
        checkBounds(root);
    }

    private void checkBounds(View view) {
        if (!(view instanceof ViewGroup)) return;
        ViewGroup group = (ViewGroup) view;
        for (int i = 0; i < group.getChildCount(); i++) {
            View child = group.getChildAt(i);
            if (child.getVisibility() == View.GONE) continue;
            if (child.getLeft() < 0
                    || child.getTop() < 0
                    || child.getRight() > group.getWidth()
                    || (!(group instanceof android.widget.ScrollView)
                            && child.getBottom() > group.getHeight()))
                throw new AssertionError(
                        "Child escapes keyboard bounds: " + child.getClass().getSimpleName());
            if (child instanceof Button
                    && child.getVisibility() == View.VISIBLE
                    && child.getWidth() <= 0) throw new AssertionError("Invisible-size key");
            if (child instanceof Button && child.getVisibility() == View.VISIBLE) {
                Button key = (Button) child;
                if (key.getText().length() > 0
                        && (key.getLayout() == null || key.getLayout().getEllipsisCount(0) > 0))
                    throw new AssertionError(
                            "Key label clipped: "
                                    + key.getText()
                                    + " width="
                                    + key.getWidth()
                                    + " textSize="
                                    + key.getTextSize());
            }
            if (child instanceof android.widget.TextView
                    && !(child instanceof android.widget.EditText)
                    && child.getVisibility() == View.VISIBLE) {
                android.widget.TextView text = (android.widget.TextView) child;
                if (text.getLayout() != null
                        && text.getLayout().getHeight()
                                > text.getHeight()
                                        - text.getCompoundPaddingTop()
                                        - text.getCompoundPaddingBottom())
                    throw new AssertionError("Text height clipped: " + text.getText());
            }
            checkBounds(child);
        }
    }

    private Button find(View view, String text) {
        if (view instanceof Button && ((Button) view).getText().toString().equals(text))
            return (Button) view;
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) {
                Button found = find(group.getChildAt(i), text);
                if (found != null) return found;
            }
        }
        return null;
    }

    private void save(View view, String name) throws Exception {
        Bitmap image =
                Bitmap.createBitmap(view.getWidth(), view.getHeight(), Bitmap.Config.ARGB_8888);
        try {
            view.draw(new Canvas(image));
            File destination = new File(getTargetContext().getCacheDir(), name + ".png");
            try (FileOutputStream output = new FileOutputStream(destination)) {
                if (!image.compress(Bitmap.CompressFormat.PNG, 100, output))
                    throw new AssertionError("Fixture encoding failed");
            }
        } finally {
            image.recycle();
        }
    }

    private Object field(Object owner, String name) throws Exception {
        Field field = owner.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field.get(owner);
    }

    private void invoke(Object owner, String name) throws Exception {
        Method method = owner.getClass().getDeclaredMethod(name);
        method.setAccessible(true);
        method.invoke(owner);
    }

    @SuppressWarnings({"unchecked", "rawtypes"})
    private void setPhase(ChatterKeyService service, String value) throws Exception {
        Field phase = service.getClass().getDeclaredField("phase");
        phase.setAccessible(true);
        phase.set(service, Enum.valueOf((Class) phase.getType(), value));
    }
}
