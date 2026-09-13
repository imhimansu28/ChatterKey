package app.chatterkey.android;

import android.Manifest;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.inputmethodservice.InputMethodService;
import android.os.Handler;
import android.os.Looper;
import android.os.PersistableBundle;
import android.os.SystemClock;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.style.BackgroundColorSpan;
import android.text.style.StrikethroughSpan;
import android.text.style.UnderlineSpan;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputMethodManager;
import android.widget.*;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

public final class ChatterKeyService extends InputMethodService {
    private enum Phase {
        IDLE,
        RECORDING,
        PROCESSING,
        REVIEW,
        ERROR
    }

    private Phase phase = Phase.IDLE;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService captureWorker = Executors.newSingleThreadExecutor();
    private final ExecutorService networkWorker = Executors.newSingleThreadExecutor();
    private final MicGesture gesture = new MicGesture();
    private long session, attempt;
    private int selectionStart = -1, selectionEnd = -1;
    private VoiceRecorder recorder;
    private ProviderTransport transport;
    private Future<?> networkTask;
    private InputTarget target;
    private JSONObject settings, preview;
    private byte[] retryAudio;
    private String proposed;
    private final KeyboardLayout layout = new KeyboardLayout();
    private long recordingStartedAt;
    private UsageStore usage;
    private final UsageStore.TypedWords typedWords = new UsageStore.TypedWords();
    private boolean usageAllowed;
    private long usageRevision;
    private static final int INK = 0xff252738, MUTED = 0xff676b80, ACCENT = 0xff6256d9;
    private static final int SURFACE = 0xffedf0f5, KEY = 0xffffffff, UTILITY = 0xffdfe4ee;

    private enum Icon {
        MIC,
        STOP,
        SHIFT,
        DELETE,
        ENTER,
        MORE,
        CLOSE
    }

    private VoiceFeedbackView voiceFeedback;
    private LinearLayout voicePanel;
    private TextView brand, subtitle;
    private Button menu, cancel;
    private KeyButton repeatingDelete;
    private final Runnable deleteRepeat =
            new Runnable() {
                @Override
                public void run() {
                    if (repeatingDelete == null
                            || !repeatingDelete.isPressed()
                            || !repeatingDelete.isShown()
                            || phase != Phase.IDLE) {
                        stopDeleteRepeat();
                        return;
                    }
                    delete();
                    main.postDelayed(this, 65);
                }
            };
    private LinearLayout root, keyboard, reviewPanel, recovery;
    private TextView status;
    private Button mic, stop, apply, retry, copy;
    private CheckBox acknowledgement;
    private final List<Button> typingButtons = new ArrayList<>();
    private final Runnable pendingTap = () -> handle(gesture.expire());
    private final Runnable recordingLimit = this::finishRecording;
    private final Runnable deadline =
            () -> {
                if (phase == Phase.PROCESSING)
                    failCurrent(
                            "Processing timed out. Retry is explicit and may incur another"
                                    + " charge.");
            };

    @Override
    public View onCreateInputView() {
        stopDeleteRepeat();
        typingButtons.clear();
        root = column();
        root.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        root.setPadding(dp(4), dp(4), dp(4), dp(5));
        root.setBackground(rounded(SURFACE, 20));
        LinearLayout toolbar = row();
        toolbar.setGravity(Gravity.CENTER_VERTICAL);
        root.addView(toolbar, new LinearLayout.LayoutParams(-1, dp(54)));
        FrameLayout tools = new FrameLayout(this);
        toolbar.addView(tools, new LinearLayout.LayoutParams(dp(48), dp(48)));
        KeyButton more = new KeyButton("Keyboard options", Icon.MORE, MUTED, SURFACE);
        tools.addView(more, new FrameLayout.LayoutParams(-1, -1));
        menu = more;
        more.setOnClickListener(view -> showKeyboardMenu(view));
        KeyButton close = new KeyButton("Cancel voice attempt", Icon.CLOSE, MUTED, SURFACE);
        tools.addView(close, new FrameLayout.LayoutParams(-1, -1));
        cancel = close;
        close.setOnClickListener(view -> cancelAttempt());
        LinearLayout title = column();
        title.setPadding(dp(6), 0, dp(6), 0);
        toolbar.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
        brand = new TextView(this);
        brand.setText(R.string.app_name);
        brand.setTextColor(INK);
        brand.setTextSize(16);
        brand.setSingleLine(true);
        brand.setEllipsize(android.text.TextUtils.TruncateAt.END);
        brand.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        title.addView(brand);
        subtitle = new TextView(this);
        subtitle.setTextSize(10);
        subtitle.setTextColor(MUTED);
        subtitle.setSingleLine(true);
        subtitle.setEllipsize(android.text.TextUtils.TruncateAt.END);
        title.addView(subtitle);
        mic = new MicButton();
        toolbar.addView(mic, new LinearLayout.LayoutParams(dp(52), dp(48)));
        status = new TextView(this);
        status.setTextSize(12);
        status.setTextColor(MUTED);
        status.setMaxLines(3);
        status.setEllipsize(android.text.TextUtils.TruncateAt.END);
        status.setPadding(dp(12), dp(4), dp(12), dp(6));
        status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        root.addView(status);
        voicePanel = column();
        voicePanel.setPadding(dp(10), dp(8), dp(10), dp(8));
        root.addView(voicePanel, new LinearLayout.LayoutParams(-1, keyRowHeight() * 4));
        voiceFeedback = new VoiceFeedbackView(this, () -> recorder == null ? 0 : recorder.level());
        voicePanel.addView(voiceFeedback, new LinearLayout.LayoutParams(-1, 0, 1));
        LinearLayout voiceActions = row();
        voicePanel.addView(voiceActions);
        stop = button(voiceActions, "Stop recording", this::finishRecording);
        style(stop, ACCENT, KEY);
        reviewPanel = column();
        root.addView(reviewPanel);
        recovery = row();
        root.addView(recovery);
        copy = button(recovery, "Copy & close", this::copyResult);
        retry =
                button(
                        recovery,
                        "Retry",
                        () -> {
                            if (phase == Phase.ERROR
                                    && retryAudio != null
                                    && target != null
                                    && target.current(this, session, selectionStart, selectionEnd))
                                beginRequest();
                            else show("Original selection changed. Start a new recording instead.");
                        });
        keyboard = column();
        root.addView(keyboard);
        buildKeys();
        if (phase == Phase.REVIEW) renderReview();
        refresh();
        return root;
    }

    @Override
    public void onStartInput(EditorInfo info, boolean restarting) {
        super.onStartInput(info, restarting);
        invalidateEditor();
        selectionStart = info.initialSelStart;
        selectionEnd = info.initialSelEnd;
        layout.reset(
                (info.inputType & android.text.InputType.TYPE_MASK_CLASS)
                                == android.text.InputType.TYPE_CLASS_NUMBER
                        || (info.inputType & android.text.InputType.TYPE_MASK_CLASS)
                                == android.text.InputType.TYPE_CLASS_PHONE);
    }

    @Override
    public void onStartInputView(EditorInfo info, boolean restarting) {
        super.onStartInputView(info, restarting);
        buildKeys();
        refresh();
    }

    @Override
    public void onFinishInputView(boolean finishingInput) {
        invalidateEditor();
        super.onFinishInputView(finishingInput);
    }

    @Override
    public void onWindowHidden() {
        invalidateEditor();
        super.onWindowHidden();
    }

    @Override
    public void onFinishInput() {
        invalidateEditor();
        super.onFinishInput();
    }

    @Override
    public boolean onEvaluateFullscreenMode() {
        return false;
    }

    @Override
    public void onUpdateSelection(
            int oldStart,
            int oldEnd,
            int newStart,
            int newEnd,
            int candidatesStart,
            int candidatesEnd) {
        super.onUpdateSelection(oldStart, oldEnd, newStart, newEnd, candidatesStart, candidatesEnd);
        selectionStart = newStart;
        selectionEnd = newEnd;
        if (phase == Phase.REVIEW) refresh();
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_ESCAPE && phase != Phase.IDLE) {
            cancelAttempt();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    public void onDestroy() {
        cancelAttempt();
        captureWorker.shutdown();
        networkWorker.shutdownNow();
        super.onDestroy();
    }

    private final class MicButton extends KeyButton {
        private boolean physicalClick;

        MicButton() {
            super("Hold to talk; double-tap for hands-free", Icon.MIC, KEY, ACCENT);
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
            if (!isEnabled()) return false;
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    setPressed(true);
                    main.removeCallbacks(pendingTap);
                    handle(gesture.down(event.getEventTime()));
                    return true;
                case MotionEvent.ACTION_UP:
                    setPressed(false);
                    physicalClick = true;
                    performClick();
                    physicalClick = false;
                    handle(gesture.up(event.getEventTime()));
                    return true;
                case MotionEvent.ACTION_CANCEL:
                    setPressed(false);
                    if (phase == Phase.RECORDING) cancelAttempt();
                    return true;
                default:
                    return true;
            }
        }

        @Override
        public boolean performClick() {
            super.performClick();
            if (!physicalClick) {
                if (phase == Phase.RECORDING) finishRecording();
                else if (phase == Phase.IDLE) {
                    gesture.startLocked();
                    startRecording();
                }
            }
            return true;
        }
    }

    private void invalidateEditor() {
        typedWords.reset();
        stopDeleteRepeat();
        session++;
        if (phase == Phase.RECORDING || phase == Phase.PROCESSING || phase == Phase.ERROR)
            cancelAttempt();
        // A completed proposal can still be copied, but never applied into a new editor session.
        if (phase == Phase.REVIEW) refresh();
    }

    private void handle(MicGesture.Action action) {
        switch (action) {
            case START:
                startRecording();
                break;
            case WAIT:
                main.postDelayed(pendingTap, MicGesture.DOUBLE_TAP_MS);
                break;
            case LOCK:
                refresh();
                break;
            case STOP:
                finishRecording();
                break;
            case NONE:
                break;
        }
    }

    private void startRecording() {
        if (phase != Phase.IDLE) {
            gesture.reset();
            return;
        }
        try {
            if (checkSelfPermission(Manifest.permission.RECORD_AUDIO)
                    != PackageManager.PERMISSION_GRANTED)
                throw new IllegalStateException("Open Settings and allow microphone access first.");
            SettingsStore store = new SettingsStore(this);
            settings = store.settings(store.provider());
            if (store.credential(settings.getString("provider")).isEmpty())
                throw new IllegalStateException("Add this provider's API key in Settings first.");
            target = InputTarget.capture(this, session, selectionStart, selectionEnd);
            typedWords.reset();
            usageAllowed = UsageStore.allowed(getCurrentInputEditorInfo()) && usage().enabled();
            usageRevision = usage().revision();
            retryAudio = null;
            proposed = null;
            preview = null;
            attempt++;
            VoiceRecorder started = new VoiceRecorder();
            long token = attempt;
            started.start(
                    this,
                    captureWorker,
                    () ->
                            main.post(
                                    () -> {
                                        if (attempt == token && phase == Phase.RECORDING)
                                            finishRecording();
                                    }));
            recorder = started;
            recordingStartedAt = SystemClock.elapsedRealtime();
            phase = Phase.RECORDING;
            main.postDelayed(recordingLimit, VoiceRecorder.MAX_SECONDS * 1000L);
            refresh();
        } catch (Exception | LinkageError error) {
            cancelAttempt();
            show(message(error));
        }
    }

    private void clearGesture() {
        gesture.reset();
        main.removeCallbacks(pendingTap);
        main.removeCallbacks(recordingLimit);
    }

    private void finishRecording() {
        if (phase != Phase.RECORDING || recorder == null) return;
        clearGesture();
        VoiceRecorder stopped = recorder;
        recorder = null;
        Future<byte[]> capture = stopped.stop();
        captureWorker.submit(stopped::release);
        long token = attempt;
        phase = Phase.PROCESSING;
        refresh();
        show("Preparing audio…");
        status.setVisibility(View.GONE);
        main.removeCallbacks(deadline);
        main.postDelayed(deadline, 40_000);
        networkTask =
                networkWorker.submit(
                        () -> {
                            try {
                                byte[] audio = capture.get();
                                if (audio.length < 44 + 1600)
                                    throw new IllegalStateException(
                                            "Recording was too short. Try again.");
                                main.post(
                                        () -> {
                                            if (attempt == token && phase == Phase.PROCESSING) {
                                                retryAudio = audio;
                                                beginRequest();
                                            }
                                        });
                            } catch (Exception error) {
                                main.post(
                                        () -> {
                                            if (attempt == token)
                                                failCurrent(
                                                        "Recording failed. Start a new attempt.");
                                        });
                            }
                        });
    }

    private void beginRequest() {
        if (retryAudio == null || target == null) return;
        long token = ++attempt;
        phase = Phase.PROCESSING;
        refresh();
        show("Processing · one model request…");
        status.setVisibility(View.GONE);
        byte[] audio = retryAudio;
        JSONObject config = settings;
        String selected = target.selected;
        ProviderTransport request = new ProviderTransport();
        transport = request;
        main.removeCallbacks(deadline);
        main.postDelayed(deadline, 40_000);
        networkTask =
                networkWorker.submit(
                        () -> {
                            try {
                                String credential =
                                        new SettingsStore(this)
                                                .credential(config.getString("provider"));
                                JSONObject result =
                                        request.process(
                                                config,
                                                credential,
                                                audio,
                                                selected,
                                                (audio.length - 44) / 32000.0);
                                String text = result.getString("text");
                                long wordCount = result.getLong("wordCount");
                                JSONObject comparison =
                                        selected == null
                                                ? null
                                                : CoreBridge.execute(
                                                        new JSONObject()
                                                                .put("operation", "preview")
                                                                .put("settings", config)
                                                                .put("selectedText", selected)
                                                                .put("proposed", text),
                                                        null);
                                main.post(
                                        () -> {
                                            if (token != attempt || phase != Phase.PROCESSING)
                                                return;
                                            main.removeCallbacks(deadline);
                                            transport = null;
                                            networkTask = null;
                                            retryAudio = null;
                                            proposed = text;
                                            preview = comparison;
                                            if (usageAllowed
                                                    && UsageStore.allowed(
                                                            getCurrentInputEditorInfo()))
                                                usage().voice(
                                                                wordCount,
                                                                Math.round(
                                                                        (audio.length - 44) / 32.0),
                                                                selected != null,
                                                                usageRevision);
                                            if (selected == null
                                                    && target.current(
                                                            this,
                                                            session,
                                                            selectionStart,
                                                            selectionEnd)
                                                    && target.connection.commitText(text, 1)) {
                                                proposed = null;
                                                target = null;
                                                phase = Phase.IDLE;
                                                refresh();
                                                show("Text sent to the editor. Check the result.");
                                            } else {
                                                phase = Phase.REVIEW;
                                                renderReview();
                                                refresh();
                                            }
                                        });
                            } catch (Exception | LinkageError error) {
                                main.post(
                                        () -> {
                                            if (token == attempt)
                                                failCurrent(
                                                        "Processing failed: "
                                                                + message(error)
                                                                + " · Retry is explicit.");
                                        });
                            }
                        });
    }

    private void failCurrent(String message) {
        attempt++;
        main.removeCallbacks(deadline);
        clearGesture();
        if (transport != null) {
            transport.cancel();
            transport = null;
        }
        if (networkTask != null) {
            networkTask.cancel(true);
            networkTask = null;
        }
        phase = Phase.ERROR;
        refresh();
        show(message);
    }

    private void cancelAttempt() {
        attempt++;
        clearGesture();
        main.removeCallbacks(deadline);
        if (transport != null) {
            transport.cancel();
            transport = null;
        }
        if (networkTask != null) {
            networkTask.cancel(true);
            networkTask = null;
        }
        if (recorder != null) {
            VoiceRecorder stopped = recorder;
            recorder = null;
            stopped.stop();
            captureWorker.submit(stopped::release);
        }
        retryAudio = null;
        proposed = null;
        preview = null;
        target = null;
        phase = Phase.IDLE;
        if (reviewPanel != null) reviewPanel.removeAllViews();
        acknowledgement = null;
        apply = null;
        refresh();
    }

    private void renderReview() {
        if (reviewPanel == null) return;
        reviewPanel.removeAllViews();
        acknowledgement = null;
        apply = null;
        try {
            ScrollView scroll = new ScrollView(this);
            LinearLayout contents = column();
            scroll.addView(contents);
            reviewPanel.addView(scroll, new LinearLayout.LayoutParams(-1, dp(210)));
            if (preview != null) {
                reviewText(contents, "Original", preview.getJSONArray("before"), false);
                reviewText(contents, "Proposed", preview.getJSONArray("after"), true);
            } else {
                TextView value = new TextView(this);
                value.setText(proposed);
                value.setTextIsSelectable(true);
                contents.addView(value);
            }
            if (preview != null && preview.getJSONArray("warnings").length() > 0) {
                TextView warning = new TextView(this);
                warning.setText(R.string.protected_warning);
                contents.addView(warning);
                JSONArray values = preview.getJSONArray("warnings");
                for (int i = 0; i < values.length(); i++) {
                    JSONObject value = values.getJSONObject(i);
                    TextView item = new TextView(this);
                    item.setText(
                            getString(
                                    R.string.value_change,
                                    value.getString("kind"),
                                    value.getString("value"),
                                    value.getInt("beforeCount"),
                                    value.getInt("afterCount")));
                    contents.addView(item);
                }
                acknowledgement = new CheckBox(this);
                acknowledgement.setText(R.string.protected_ack);
                reviewPanel.addView(acknowledgement);
                acknowledgement.setOnCheckedChangeListener((view, checked) -> refresh());
            }
            LinearLayout actions = row();
            reviewPanel.addView(actions);
            apply = button(actions, "Apply to original", this::applyResult);
            button(actions, "Discard", this::cancelAttempt);
        } catch (Exception error) {
            show("Review unavailable. Copy the result manually.");
        }
    }

    private void reviewText(
            LinearLayout parent, String heading, JSONArray segments, boolean additions)
            throws Exception {
        TextView title = new TextView(this);
        title.setText(heading);
        parent.addView(title);
        SpannableStringBuilder text = new SpannableStringBuilder();
        for (int i = 0; i < segments.length(); i++) {
            JSONObject segment = segments.getJSONObject(i);
            int start = text.length();
            text.append(segment.getString("text"));
            if (segment.getBoolean("changed")) {
                text.setSpan(
                        additions ? new UnderlineSpan() : new StrikethroughSpan(),
                        start,
                        text.length(),
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                text.setSpan(
                        new BackgroundColorSpan(additions ? 0xffd7f1df : 0xffffdddd),
                        start,
                        text.length(),
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            }
        }
        TextView value = new TextView(this);
        value.setText(text);
        value.setTextSize(14);
        value.setTextIsSelectable(true);
        parent.addView(value);
    }

    private void applyResult() {
        if (phase != Phase.REVIEW || proposed == null || target == null) return;
        if (acknowledgement != null && !acknowledgement.isChecked()) return;
        if (!target.current(this, session, selectionStart, selectionEnd)) {
            refresh();
            show("Original editor or selection changed. Use Copy & close.");
            return;
        }
        if (target.connection.commitText(proposed, 1)) {
            cancelAttempt();
            show("Replacement sent. Check the editor; nothing was submitted.");
        } else show("Editor rejected replacement. Your result is still available to copy.");
    }

    private void copyResult() {
        if (proposed == null) return;
        ClipData clip = ClipData.newPlainText("ChatterKey result", proposed);
        PersistableBundle extras = new PersistableBundle();
        extras.putBoolean("android.content.extra.IS_SENSITIVE", true);
        clip.getDescription().setExtras(extras);
        try {
            ((ClipboardManager) getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(clip);
            cancelAttempt();
            show("Copied. Paste manually into the intended selection.");
        } catch (RuntimeException error) {
            show("Could not copy. Result retained.");
        }
    }

    private void refresh() {
        if (root == null) return;
        mic.setEnabled(
                (phase == Phase.IDLE && !InputTarget.secure(getCurrentInputEditorInfo()))
                        || phase == Phase.RECORDING);
        boolean voiceActive = phase == Phase.RECORDING || phase == Phase.PROCESSING;
        if (phase != Phase.IDLE) stopDeleteRepeat();
        cancel.setVisibility(phase == Phase.IDLE ? View.GONE : View.VISIBLE);
        menu.setVisibility(phase == Phase.IDLE ? View.VISIBLE : View.GONE);
        brand.setText(
                phase == Phase.RECORDING
                        ? "Voice recording"
                        : phase == Phase.PROCESSING
                                ? "Working on your words"
                                : phase == Phase.REVIEW ? "Review voice edit" : "ChatterKey");
        subtitle.setText(
                phase == Phase.IDLE
                        ? "Hold or double-tap mic"
                        : phase == Phase.RECORDING
                                ? "2-minute recording limit"
                                : phase == Phase.PROCESSING
                                        ? "You can cancel at any time"
                                        : "Your words, your final say");
        ((KeyButton) mic).icon = phase == Phase.RECORDING ? Icon.STOP : Icon.MIC;
        mic.setContentDescription(
                phase == Phase.RECORDING
                        ? "Stop recording"
                        : "Hold to talk; double-tap for hands-free");
        mic.setAlpha(mic.isEnabled() ? 1 : .45f);
        mic.invalidate();
        voicePanel.setVisibility(voiceActive ? View.VISIBLE : View.GONE);
        voiceFeedback.state(
                phase == Phase.RECORDING,
                phase == Phase.PROCESSING,
                gesture.locked(),
                recordingStartedAt);
        stop.setVisibility(phase == Phase.RECORDING ? View.VISIBLE : View.INVISIBLE);
        stop.setEnabled(phase == Phase.RECORDING);
        keyboard.setVisibility(voiceActive || phase == Phase.REVIEW ? View.GONE : View.VISIBLE);
        for (Button key : typingButtons) {
            key.setEnabled(phase == Phase.IDLE);
            key.setAlpha(phase == Phase.IDLE ? 1 : .45f);
        }
        status.setVisibility(
                phase == Phase.REVIEW || phase == Phase.ERROR ? View.VISIBLE : View.GONE);
        reviewPanel.setVisibility(phase == Phase.REVIEW ? View.VISIBLE : View.GONE);
        recovery.setVisibility(
                phase == Phase.REVIEW || phase == Phase.ERROR ? View.VISIBLE : View.GONE);
        copy.setVisibility(proposed != null ? View.VISIBLE : View.GONE);
        retry.setVisibility(phase == Phase.ERROR && retryAudio != null ? View.VISIBLE : View.GONE);
        if (apply != null)
            apply.setEnabled(
                    phase == Phase.REVIEW
                            && target != null
                            && target.current(this, session, selectionStart, selectionEnd)
                            && (preview == null || preview.optBoolean("hasChanges"))
                            && (acknowledgement == null || acknowledgement.isChecked()));
        if (phase == Phase.IDLE)
            show(
                    InputTarget.secure(getCurrentInputEditorInfo())
                            ? "Voice disabled in this field · normal typing available"
                            : "ChatterKey · type normally, or hold/double-tap the mic");
        if (phase == Phase.IDLE && !InputTarget.secure(getCurrentInputEditorInfo()))
            status.setVisibility(View.GONE);
        if (phase == Phase.RECORDING)
            show("Microphone active · Stop or Cancel · maximum 2 minutes");
        if (voiceActive) status.setVisibility(View.GONE);
        if (phase == Phase.REVIEW)
            show(
                    target != null && target.current(this, session, selectionStart, selectionEnd)
                            ? "Review before applying. No extra model request."
                            : "Original selection is unverifiable or changed. Copy manually.");
    }

    private void showKeyboardMenu(View anchor) {
        PopupMenu popup = new PopupMenu(this, anchor);
        popup.getMenu().add(0, 1, 0, "Keyboard settings");
        popup.getMenu().add(0, 2, 1, "Switch keyboard");
        popup.setOnMenuItemClickListener(
                item -> {
                    if (phase != Phase.IDLE) return false;
                    if (item.getItemId() == 1)
                        startActivity(
                                new Intent(this, SettingsActivity.class)
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
                    else switchKeyboard();
                    return true;
                });
        popup.show();
    }

    private void switchKeyboard() {
        if (phase != Phase.IDLE) return;
        stopDeleteRepeat();
        ((InputMethodManager) getSystemService(INPUT_METHOD_SERVICE)).showInputMethodPicker();
    }

    private int keyRowHeight() {
        return dp(
                getResources().getConfiguration().orientation
                                == android.content.res.Configuration.ORIENTATION_LANDSCAPE
                        ? 42
                        : 54);
    }

    private void buildKeys() {
        if (keyboard == null) return;
        stopDeleteRepeat();
        keyboard.removeAllViews();
        typingButtons.clear();
        String[] rows = layout.rows();
        for (int r = 0; r < rows.length; r++) {
            LinearLayout line = row();
            keyboard.addView(line);
            if (r == 1 && !layout.symbols()) spacer(line, .5f);
            if (r == 2) {
                KeyButton shift =
                        key(
                                line,
                                layout.symbols() ? layout.shiftLabel() : "Shift",
                                layout.symbols() ? null : Icon.SHIFT,
                                1.5f,
                                () -> {
                                    layout.shift(SystemClock.uptimeMillis());
                                    buildKeys();
                                    refresh();
                                });
                if (!layout.symbols()) {
                    shift.setContentDescription(
                            layout.capsLocked()
                                    ? "Caps lock on"
                                    : layout.shifted()
                                            ? "Shift on"
                                            : "Shift; double-tap for caps lock");
                    if (layout.shifted()) style(shift, ACCENT, KEY);
                    shift.setOnLongClickListener(
                            view -> {
                                if (phase != Phase.IDLE) return false;
                                layout.lockCaps();
                                buildKeys();
                                refresh();
                                return true;
                            });
                }
            }
            for (int i = 0; i < rows[r].length(); i++) {
                String text = rows[r].substring(i, i + 1);
                KeyButton letter = key(line, text, null, 1, () -> type(text));
                if (r == 0 && !layout.symbols()) {
                    String digit = "1234567890".substring(i, i + 1);
                    letter.hint = digit;
                    letter.setContentDescription(text + "; hold for " + digit);
                    letter.setOnLongClickListener(
                            view -> {
                                type(digit);
                                return true;
                            });
                }
            }
            if (r == 1 && !layout.symbols()) spacer(line, .5f);
            if (r == 2) {
                KeyButton backspace = key(line, "Backspace", Icon.DELETE, 1.5f, this::delete);
                backspace.setOnLongClickListener(
                        view -> {
                            if (phase != Phase.IDLE) return false;
                            stopDeleteRepeat();
                            repeatingDelete = backspace;
                            deleteRepeat.run();
                            return true;
                        });
            }
        }
        LinearLayout bottom = row();
        keyboard.addView(bottom);
        KeyButton page =
                key(
                        bottom,
                        layout.symbols() ? "ABC" : "?123",
                        null,
                        1.5f,
                        () -> {
                            layout.toggleSymbols();
                            buildKeys();
                            refresh();
                        });
        style(page, UTILITY, INK);
        key(bottom, ",", null, 1, () -> type(","));
        KeyButton space = key(bottom, "English (India)", null, 4.5f, () -> type(" "));
        space.setTextSize(13);
        space.setContentDescription("Space; hold to switch keyboard. English India.");
        space.setOnLongClickListener(
                view -> {
                    switchKeyboard();
                    return true;
                });
        key(bottom, ".", null, 1, () -> type("."));
        EditorInfo info = getCurrentInputEditorInfo();
        int action =
                info == null || (info.imeOptions & EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0
                        ? EditorInfo.IME_ACTION_NONE
                        : info.imeOptions & EditorInfo.IME_MASK_ACTION;
        CharSequence label = getTextForImeAction(action);
        boolean newline =
                action == EditorInfo.IME_ACTION_NONE || action == EditorInfo.IME_ACTION_UNSPECIFIED;
        KeyButton enter =
                key(
                        bottom,
                        newline || label == null ? "Enter" : label.toString(),
                        newline ? Icon.ENTER : null,
                        2,
                        this::enter);
        enter.setTextSize(13);
        style(enter, ACCENT, KEY);
    }

    private KeyButton key(
            LinearLayout parent, String text, Icon icon, float weight, Runnable action) {
        KeyButton key = new KeyButton(text, icon, INK, icon == null ? KEY : UTILITY);
        if (icon == null && text.length() > 1) {
            key.setTextSize(14);
            key.setAutoSizeTextTypeUniformWithConfiguration(
                    10, 14, 1, android.util.TypedValue.COMPLEX_UNIT_SP);
        }
        if (icon == null && text.length() == 1)
            key.setAutoSizeTextTypeUniformWithConfiguration(
                    14, 22, 1, android.util.TypedValue.COMPLEX_UNIT_SP);
        key.setOnClickListener(
                view -> {
                    if (phase == Phase.IDLE) action.run();
                });
        LinearLayout.LayoutParams params =
                new LinearLayout.LayoutParams(0, keyRowHeight() - 2 * dp(3), weight);
        params.setMargins(dp(2), dp(3), dp(2), dp(3));
        parent.addView(key, params);
        typingButtons.add(key);
        return key;
    }

    private void spacer(LinearLayout parent, float weight) {
        parent.addView(new View(this), new LinearLayout.LayoutParams(0, 1, weight));
    }

    private void stopDeleteRepeat() {
        main.removeCallbacks(deleteRepeat);
        repeatingDelete = null;
    }

    private UsageStore usage() {
        if (usage == null) usage = new UsageStore(this);
        return usage;
    }

    private void type(String text) {
        if (phase != Phase.IDLE
                || getCurrentInputConnection() == null
                || !getCurrentInputConnection().commitText(text, 1)) return;
        if (UsageStore.allowed(getCurrentInputEditorInfo()) && usage().enabled())
            usage().typed(typedWords.accept(text));
        else typedWords.reset();
        if (layout.inserted(text)) {
            buildKeys();
            refresh();
        }
    }

    private void delete() {
        if (phase != Phase.IDLE) return;
        typedWords.reset();
        InputConnection c = getCurrentInputConnection();
        if (c == null) return;
        CharSequence selected = c.getSelectedText(0);
        if (selected != null && selected.length() > 0) c.commitText("", 1);
        else c.deleteSurroundingTextInCodePoints(1, 0);
    }

    private void enter() {
        if (phase != Phase.IDLE) return;
        typedWords.reset();
        InputConnection c = getCurrentInputConnection();
        EditorInfo info = getCurrentInputEditorInfo();
        if (c == null || info == null) return;
        int action = info.imeOptions & EditorInfo.IME_MASK_ACTION;
        if ((info.imeOptions & EditorInfo.IME_FLAG_NO_ENTER_ACTION) == 0
                && action != EditorInfo.IME_ACTION_NONE
                && action != EditorInfo.IME_ACTION_UNSPECIFIED) c.performEditorAction(action);
        else c.commitText("\n", 1);
    }

    private LinearLayout row() {
        LinearLayout view = new LinearLayout(this);
        view.setOrientation(LinearLayout.HORIZONTAL);
        return view;
    }

    private LinearLayout column() {
        LinearLayout view = new LinearLayout(this);
        view.setOrientation(LinearLayout.VERTICAL);
        return view;
    }

    private GradientDrawable rounded(int color, float radius) {
        GradientDrawable background = new GradientDrawable();
        background.setColor(color);
        background.setCornerRadius(dp(Math.round(radius)));
        return background;
    }

    private void style(Button view, int background, int foreground) {
        view.setBackgroundTintList(null);
        view.setBackground(
                new RippleDrawable(
                        ColorStateList.valueOf(0x246256d9), rounded(background, 12), null));
        view.setTextColor(foreground);
        if (view instanceof KeyButton) ((KeyButton) view).foreground = foreground;
    }

    private class KeyButton extends Button {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Path path = new Path();
        private Icon icon;
        private int foreground;
        private String hint;

        KeyButton(String label, Icon icon, int foreground, int background) {
            super(ChatterKeyService.this);
            this.icon = icon;
            setText(icon == null ? label : "");
            setContentDescription(label);
            setTextSize(22);
            setAllCaps(false);
            setMinWidth(0);
            setMinimumWidth(0);
            setMinHeight(0);
            setMinimumHeight(0);
            setPadding(0, 0, 0, 0);
            setGravity(Gravity.CENTER);
            setSingleLine(true);
            setHorizontallyScrolling(false);
            setEllipsize(android.text.TextUtils.TruncateAt.END);
            setStateListAnimator(null);
            style(this, background, foreground);
        }

        @Override
        public boolean dispatchTouchEvent(MotionEvent event) {
            if (event.getActionMasked() == MotionEvent.ACTION_DOWN && isEnabled())
                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP);
            if ((event.getActionMasked() == MotionEvent.ACTION_UP
                            || event.getActionMasked() == MotionEvent.ACTION_CANCEL)
                    && repeatingDelete == this) stopDeleteRepeat();
            return super.dispatchTouchEvent(event);
        }

        @Override
        public boolean performClick() {
            stopDeleteRepeat();
            return super.performClick();
        }

        @Override
        protected void onDetachedFromWindow() {
            if (repeatingDelete == this) stopDeleteRepeat();
            super.onDetachedFromWindow();
        }

        private void line(Canvas canvas, float... coordinates) {
            path.reset();
            path.moveTo(coordinates[0], coordinates[1]);
            for (int i = 2; i < coordinates.length; i += 2)
                path.lineTo(coordinates[i], coordinates[i + 1]);
            canvas.drawPath(path, paint);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            paint.setColor(foreground);
            if (hint != null) {
                paint.setStyle(Paint.Style.FILL);
                paint.setTextSize(dp(9));
                paint.setTextAlign(Paint.Align.RIGHT);
                paint.setColor(MUTED);
                canvas.drawText(hint, getWidth() - dp(5), dp(11), paint);
            }
            if (icon == null) return;
            canvas.save();
            canvas.translate(getWidth() / 2f - dp(12), getHeight() / 2f - dp(12));
            float scale = getResources().getDisplayMetrics().density;
            canvas.scale(scale, scale);
            paint.setColor(foreground);
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(1.8f);
            paint.setStrokeCap(Paint.Cap.ROUND);
            paint.setStrokeJoin(Paint.Join.ROUND);
            switch (icon) {
                case MIC:
                    canvas.drawRoundRect(9, 3, 15, 14, 3, 3, paint);
                    canvas.drawArc(6, 6, 18, 18, 0, 180, false, paint);
                    line(canvas, 12, 18, 12, 21);
                    line(canvas, 9, 21, 15, 21);
                    break;
                case STOP:
                    paint.setStyle(Paint.Style.FILL);
                    canvas.drawRoundRect(5, 5, 19, 19, 4, 4, paint);
                    break;
                case SHIFT:
                    line(canvas, 4, 11, 12, 3, 20, 11, 16, 11, 16, 20, 8, 20, 8, 11, 4, 11);
                    if (layout.capsLocked()) line(canvas, 8, 23, 16, 23);
                    break;
                case DELETE:
                    line(canvas, 9, 5, 21, 5, 21, 19, 9, 19, 2, 12, 9, 5);
                    line(canvas, 12, 9, 17, 15);
                    line(canvas, 17, 9, 12, 15);
                    break;
                case ENTER:
                    line(canvas, 20, 5, 20, 14, 4, 14);
                    line(canvas, 9, 9, 4, 14, 9, 19);
                    break;
                case CLOSE:
                    line(canvas, 6, 6, 18, 18);
                    line(canvas, 18, 6, 6, 18);
                    break;
                case MORE:
                    paint.setStyle(Paint.Style.FILL);
                    for (int x = 6; x <= 18; x += 6) canvas.drawCircle(x, 12, 1.7f, paint);
                    break;
            }
            canvas.restore();
        }
    }

    private Button button(LinearLayout parent, String text, Runnable action) {
        Button view = new KeyButton(text, null, INK, KEY);
        view.setTextSize(14);
        view.setOnClickListener(v -> action.run());
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, dp(46), 1);
        params.setMargins(dp(3), dp(3), dp(3), dp(3));
        parent.addView(view, params);
        return view;
    }

    private void show(String message) {
        if (status != null) {
            status.setVisibility(View.VISIBLE);
            status.setText(
                    message == null ? "Something went wrong. Cancel and try again." : message);
        }
    }

    private static String message(Throwable error) {
        return error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage();
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
