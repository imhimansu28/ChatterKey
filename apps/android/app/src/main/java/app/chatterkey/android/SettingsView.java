package app.chatterkey.android;

import android.Manifest;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.provider.Settings;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.*;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.text.NumberFormat;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;
import java.util.Scanner;

final class SettingsView extends LinearLayout {
    private static final int INK = 0xff252738, MUTED = 0xff73778b, ACCENT = 0xff6256d9;
    private static final int BG = 0xfff4f5fa, CARD = 0xffffffff, TINT = 0xffeeebff;
    private static final Locale EN_IN = Locale.forLanguageTag("en-IN");
    private SettingsStore store;
    private UsageStore usage;
    private JSONObject catalog, current;
    private Spinner providers, modes;
    private EditText model, credential, prompt, dictionary, snippets;
    private CompoundButton polish, commands;
    private TextView status;
    private String shownProvider;
    private LinearLayout dashboard;
    private final ScrollView[] pages = new ScrollView[3];
    private final Button[] tabs = new Button[3];
    int selectedTab, period;
    private Runnable requestMicrophone;

    public SettingsView(Context context) {
        super(context);
        setOrientation(LinearLayout.VERTICAL);
    }

    void refreshUsage() {
        if (dashboard != null) renderDashboard();
    }

    // Explicit stores let device fixtures render the real screens without opening user credentials.
    View createContent(SettingsStore store, UsageStore usage, Runnable requestMicrophone) {
        this.store = store;
        this.usage = usage;
        this.requestMicrophone = requestMicrophone;
        LinearLayout root = this;
        root.setBackgroundColor(BG);
        LinearLayout header = row();
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(20), dp(16), dp(20), dp(12));
        TextView mark = new TextView(getContext());
        mark.setText(R.string.monogram);
        mark.setTextColor(ACCENT);
        mark.setTextSize(17);
        mark.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        mark.setGravity(Gravity.CENTER);
        mark.setBackground(rounded(TINT, 14));
        header.addView(mark, new LinearLayout.LayoutParams(dp(44), dp(44)));
        LinearLayout title = column();
        title.setPadding(dp(12), 0, 0, 0);
        header.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
        label(title, "ChatterKey", 20, INK, true);
        label(title, "Your voice. Your space.", 12, MUTED, false);
        root.addView(header);
        FrameLayout content = new FrameLayout(getContext());
        root.addView(content, new LinearLayout.LayoutParams(-1, 0, 1));
        for (int i = 0; i < pages.length; i++) {
            pages[i] = new ScrollView(getContext());
            pages[i].setFillViewport(true);
            pages[i].setClipToPadding(false);
            content.addView(pages[i], new FrameLayout.LayoutParams(-1, -1));
        }
        dashboard = page();
        pages[0].addView(dashboard);
        pages[1].addView(settingsPage());
        pages[2].addView(practicePage());
        LinearLayout navigation = row();
        navigation.setPadding(dp(12), dp(8), dp(12), dp(8));
        navigation.setBackgroundColor(CARD);
        root.addView(navigation);
        String[] names = {"Dashboard", "Settings", "Practice"};
        for (int i = 0; i < names.length; i++) {
            final int tab = i;
            tabs[i] = button(navigation, names[i], () -> selectTab(tab), false);
            tabs[i].setMaxLines(1);
            tabs[i].setHorizontallyScrolling(false);
            tabs[i].setAutoSizeTextTypeUniformWithConfiguration(
                    10, 13, 1, android.util.TypedValue.COMPLEX_UNIT_SP);
        }
        selectTab(0);
        return root;
    }

    void selectTab(int tab) {
        if (tab != selectedTab) {
            View focused = pages[selectedTab].findFocus();
            if (focused != null) {
                if (focused.getWindowToken() != null)
                    ((InputMethodManager)
                                    getContext().getSystemService(Context.INPUT_METHOD_SERVICE))
                            .hideSoftInputFromWindow(focused.getWindowToken(), 0);
                focused.clearFocus();
            }
        }
        selectedTab = tab;
        for (int i = 0; i < pages.length; i++) {
            pages[i].setVisibility(i == tab ? View.VISIBLE : View.GONE);
            if (tabs[i] != null) {
                style(tabs[i], i == tab ? TINT : CARD, i == tab ? ACCENT : MUTED);
                tabs[i].setSelected(i == tab);
            }
        }
        if (tab == 0) renderDashboard();
    }

    private void renderDashboard() {
        dashboard.removeAllViews();
        label(dashboard, "Dashboard", 27, INK, true);
        label(dashboard, "A little progress, every day.", 14, MUTED, false);
        Switch tracking =
                toggle(
                        dashboard,
                        "Local usage counters",
                        usage.enabled()
                                ? "On · totals only, stored on this phone."
                                : "Off · enable to count future activity locally.");
        tracking.setChecked(usage.enabled());
        tracking.setOnCheckedChangeListener(
                (view, enabled) -> {
                    usage.setEnabled(enabled);
                    renderDashboard();
                });
        LinearLayout range = row();
        range.setPadding(0, dp(14), 0, dp(8));
        dashboard.addView(range);
        String[] names = {"Today", "7 days", "All time"};
        for (int i = 0; i < names.length; i++) {
            final int value = i;
            Button option =
                    button(
                            range,
                            names[i],
                            () -> {
                                period = value;
                                renderDashboard();
                            },
                            false);
            style(option, period == i ? ACCENT : CARD, period == i ? CARD : MUTED);
            option.setSelected(period == i);
        }
        UsageStore.Totals totals =
                period == 0 ? usage.today() : period == 1 ? usage.week() : usage.total();
        LinearLayout first = row();
        dashboard.addView(first);
        metric(first, "Typed words", number(totals.typed()), "Estimate · ChatterKey taps", INK);
        metric(
                first,
                "Voice output",
                number(totals.voice()),
                "Words · final dictation text",
                ACCENT);
        LinearLayout second = row();
        dashboard.addView(second);
        metric(second, "Voice time", duration(totals.millis()), "Successful requests", INK);
        metric(second, "Dictations", number(totals.dictations()), "Completed successfully", INK);
        LinearLayout chartCard = card(dashboard);
        label(chartCard, "Last 7 days", 17, INK, true);
        label(chartCard, "Typed estimate + voice output", 12, MUTED, false);
        UsageChart chart = new UsageChart(getContext());
        chart.setDays(usage.days());
        chartCard.addView(chart, new LinearLayout.LayoutParams(-1, dp(170)));
        label(chartCard, "Light purple: typed   ·   Purple: voice", 11, MUTED, false);
        label(
                chartCard,
                "Voice edits: "
                        + number(totals.edits())
                        + " in this period. Edited text is not added to voice-word totals.",
                12,
                MUTED,
                false);
        LinearLayout privacy = card(dashboard);
        label(
                privacy,
                usage.enabled()
                        ? "Counting from now on. No typed text, audio, app names or keystroke logs"
                                + " are stored."
                        : "Paused. Enable to start counting future activity. Earlier typing and"
                                + " recordings cannot be recovered.",
                13,
                MUTED,
                false);
        label(
                privacy,
                "Password fields, editors requesting private mode and the practice area are"
                        + " excluded. Other keyboards and pasted text are not monitored.",
                12,
                MUTED,
                false);
        button(
                privacy,
                "Clear local usage",
                () ->
                        new AlertDialog.Builder(getContext())
                                .setTitle("Clear local usage?")
                                .setMessage(
                                        "This removes word counts, voice time and daily totals."
                                            + " Your API keys and settings will stay unchanged.")
                                .setNegativeButton("Keep", null)
                                .setPositiveButton(
                                        "Clear usage",
                                        (dialog, which) -> {
                                            usage.clear();
                                            renderDashboard();
                                        })
                                .show(),
                false);
        LinearLayout details = card(dashboard);
        label(details, "What do these numbers mean?", 16, INK, true);
        label(
                details,
                "Typed words estimate new word runs from accepted ChatterKey key taps, not the"
                    + " current document's word count. Deleting, moving the cursor or retyping can"
                    + " change the estimate.",
                12,
                MUTED,
                false);
        label(
                details,
                "Voice words count the final output of successful dictations, not exact spoken"
                    + " words. Translation and polishing can change the count. Successful previews"
                    + " count even if you later copy or discard them; retries, failures and"
                    + " cancellation are not a billing ledger.",
                12,
                MUTED,
                false);
        label(
                details,
                "All-time totals stay local. Daily buckets are pruned to 30 days when new activity"
                        + " is counted. No Mac history is imported.",
                12,
                MUTED,
                false);
    }

    private LinearLayout settingsPage() {
        LinearLayout form = page();
        label(form, "Settings", 27, INK, true);
        label(form, "One model. A voice that feels like you.", 14, MUTED, false);
        status =
                label(
                        form,
                        "Changes are saved only when you choose Save settings.",
                        12,
                        MUTED,
                        false);
        status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        try {
            catalog = CoreBridge.catalog();
            LinearLayout connection = card(form);
            label(connection, "AI connection", 18, INK, true);
            label(
                    connection,
                    "Each connection keeps its own key and preferences. Switching discards unsaved"
                            + " form changes.",
                    12,
                    MUTED,
                    false);
            label(connection, "Connection", 12, MUTED, true);
            providers = spinner(connection, catalog.getJSONArray("providers"));
            model = field(connection, "Audio model", "Audio-capable model ID", false);
            credential = field(connection, "API key", "Paste your provider key", false);
            credential.setInputType(
                    InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
            credential.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO);
            credential.setSaveEnabled(false);
            label(
                    connection,
                    "Blank removes the saved key. Stored encrypted; never copied between"
                            + " providers.",
                    11,
                    MUTED,
                    false);
            LinearLayout writing = card(form);
            label(writing, "Your writing style", 18, INK, true);
            label(writing, "Clean Same Language preserves Hindi/Hinglish.", 12, MUTED, false);
            modes = spinner(writing, catalog.getJSONArray("modes"));
            polish =
                    toggle(
                            writing,
                            "Clean filler words",
                            "Keep the meaning; make the wording cleaner.");
            commands =
                    toggle(
                            writing,
                            "Spoken formatting",
                            "Use spoken commands for paragraphs and punctuation.");
            LinearLayout advanced = card(form);
            LinearLayout advancedFields = column();
            Button expand =
                    button(
                            advanced,
                            "Instructions & vocabulary",
                            () -> {
                                boolean show = advancedFields.getVisibility() != View.VISIBLE;
                                advancedFields.setVisibility(show ? View.VISIBLE : View.GONE);
                            },
                            false);
            expand.setContentDescription(
                    "Show or hide custom instructions, vocabulary and snippets");
            advanced.addView(advancedFields);
            prompt = field(advancedFields, "Writing instructions", "Custom system prompt", true);
            dictionary =
                    field(
                            advancedFields,
                            "Personal vocabulary",
                            "spoken phrase => exact spelling",
                            true);
            snippets =
                    field(
                            advancedFields,
                            "Voice snippets",
                            "cue => replacement (use \\n for newlines)",
                            true);
            label(
                    advancedFields,
                    "One vocabulary/snippet entry per line. These are explicit preferences, not"
                            + " automatic learning.",
                    12,
                    MUTED,
                    false);
            advancedFields.setVisibility(View.GONE);
            button(form, "Save settings", this::save, true);
            label(
                    form,
                    "Saving does not send an API request. One selected audio model handles each"
                            + " voice attempt; Retry stays explicit.",
                    12,
                    MUTED,
                    false);
            JSONArray choices = catalog.getJSONArray("providers");
            for (int i = 0; i < choices.length(); i++)
                if (choices.getJSONObject(i).getString("id").equals(store.provider()))
                    providers.setSelection(i);
            providers.setOnItemSelectedListener(
                    new AdapterView.OnItemSelectedListener() {
                        public void onNothingSelected(AdapterView<?> parent) {}

                        public void onItemSelected(
                                AdapterView<?> parent, View view, int position, long id) {
                            load(position);
                        }
                    });
            load(providers.getSelectedItemPosition());
        } catch (Exception | LinkageError error) {
            status.setText(getContext().getString(R.string.core_unavailable, error.getMessage()));
        }
        LinearLayout about = card(form);
        label(about, "ChatterKey " + BuildConfig.VERSION_NAME, 17, INK, true);
        label(about, "Android 9+ · ARM64 · one audio model per attempt", 12, MUTED, false);
        button(about, "Privacy & data", () -> showDocument("Privacy & data", "privacy.txt"), false);
        button(
                about,
                "Open-source licenses",
                () -> showDocument("Open-source licenses", "licenses.txt"),
                false);
        return form;
    }

    private void showDocument(String title, String asset) {
        try (InputStream input = getContext().getAssets().open(asset);
                Scanner reader = new Scanner(input, StandardCharsets.UTF_8.name())) {
            String text = reader.useDelimiter("\\A").hasNext() ? reader.next() : "";
            ScrollView scroll = new ScrollView(getContext());
            TextView contents = new TextView(getContext());
            contents.setText(text);
            contents.setTextColor(INK);
            contents.setTextSize(14);
            contents.setPadding(dp(20), dp(12), dp(20), dp(12));
            contents.setTextIsSelectable(true);
            scroll.addView(contents);
            new AlertDialog.Builder(getContext())
                    .setTitle(title)
                    .setView(scroll)
                    .setPositiveButton("Close", null)
                    .show();
        } catch (java.io.IOException error) {
            new AlertDialog.Builder(getContext())
                    .setTitle(title)
                    .setMessage(
                            "This document could not be opened. Please reinstall the complete APK.")
                    .setPositiveButton("Close", null)
                    .show();
        }
    }

    private LinearLayout practicePage() {
        LinearLayout form = page();
        label(form, "Make yourself at home", 25, INK, true);
        label(form, "A private space to try your keyboard.", 14, MUTED, false);
        LinearLayout setup = card(form);
        label(setup, "Keyboard setup", 18, INK, true);
        label(
                setup,
                "First enable and choose ChatterKey, then allow microphone access. In Settings,"
                    + " enter your selected provider's API key and tap Save. Normal typing does not"
                    + " need a key or internet connection.",
                12,
                MUTED,
                false);
        button(
                setup,
                "Enable ChatterKey",
                () -> getContext().startActivity(new Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)),
                false);
        button(
                setup,
                "Choose keyboard",
                () ->
                        ((InputMethodManager)
                                        getContext().getSystemService(Context.INPUT_METHOD_SERVICE))
                                .showInputMethodPicker(),
                false);
        button(
                setup,
                "Allow microphone",
                () -> {
                    if (getContext().checkSelfPermission(Manifest.permission.RECORD_AUDIO)
                            != PackageManager.PERMISSION_GRANTED) requestMicrophone.run();
                    else
                        new AlertDialog.Builder(getContext())
                                .setMessage(R.string.mic_granted)
                                .setPositiveButton("OK", null)
                                .show();
                },
                false);
        LinearLayout test = card(form);
        label(test, "Try a few words", 18, INK, true);
        label(
                test,
                "Nothing is submitted. Practice is excluded from usage counters.",
                12,
                MUTED,
                false);
        EditText editor =
                field(
                        test,
                        "Private test editor",
                        "Type here, or select text and speak an edit.",
                        true);
        editor.setMinLines(5);
        editor.setText(R.string.test_draft);
        LinearLayout tips = card(form);
        label(tips, "A few little shortcuts", 17, INK, true);
        label(
                tips,
                "Hold the mic to speak; release to finish. Double-tap for hands-free, then tap"
                        + " Stop. A recording can last up to two minutes.",
                13,
                MUTED,
                false);
        label(
                tips,
                "Double-tap Shift for caps lock. Hold top-row letters for digits, Backspace to keep"
                        + " deleting, or Space to switch keyboards.",
                13,
                MUTED,
                false);
        label(
                tips,
                "Voice edits pause for review. If the original selection cannot be verified, use"
                        + " Copy instead. Voice never presses Send.",
                13,
                MUTED,
                false);
        return form;
    }

    private void load(int position) {
        try {
            String provider =
                    catalog.getJSONArray("providers").getJSONObject(position).getString("id");
            if (provider.equals(shownProvider)) return;
            shownProvider = provider;
            current = null;
            credential.setText("");
            current = store.settings(provider);
            model.setText(current.getString("model"));
            prompt.setText(current.getString("systemPrompt"));
            polish.setChecked(current.getBoolean("smartPolish"));
            commands.setChecked(current.getBoolean("spokenCommandsEnabled"));
            dictionary.setText(
                    SettingsStore.displayEntries(
                            current.getJSONArray("personalDictionary"), false));
            snippets.setText(
                    SettingsStore.displayEntries(current.getJSONArray("voiceSnippets"), true));
            JSONArray options = catalog.getJSONArray("modes");
            for (int i = 0; i < options.length(); i++)
                if (options.getJSONObject(i)
                        .getString("id")
                        .equals(current.getString("outputMode"))) modes.setSelection(i);
            credential.setText(store.credential(provider));
        } catch (Exception error) {
            status.setText(
                    getContext().getString(R.string.connection_unavailable, error.getMessage()));
        }
    }

    private void save() {
        try {
            JSONObject value = new JSONObject(current.toString());
            value.put("provider", shownProvider)
                    .put("model", model.getText().toString().trim())
                    .put("systemPrompt", prompt.getText().toString())
                    .put(
                            "outputMode",
                            catalog.getJSONArray("modes")
                                    .getJSONObject(modes.getSelectedItemPosition())
                                    .getString("id"))
                    .put("smartPolish", polish.isChecked())
                    .put("spokenCommandsEnabled", commands.isChecked())
                    .put(
                            "personalDictionary",
                            SettingsStore.entries(dictionary.getText().toString(), false))
                    .put(
                            "voiceSnippets",
                            SettingsStore.entries(snippets.getText().toString(), true));
            store.save(value, credential.getText().toString());
            current = value;
            status.setText(R.string.saved);
            if (getWindowToken() != null)
                Toast.makeText(getContext(), R.string.settings_saved_short, Toast.LENGTH_SHORT)
                        .show();
        } catch (Exception error) {
            status.setText(getContext().getString(R.string.not_saved, error.getMessage()));
            pages[1].smoothScrollTo(0, 0);
        }
    }

    private LinearLayout column() {
        LinearLayout view = new LinearLayout(getContext());
        view.setOrientation(LinearLayout.VERTICAL);
        return view;
    }

    private LinearLayout row() {
        LinearLayout view = new LinearLayout(getContext());
        view.setOrientation(LinearLayout.HORIZONTAL);
        return view;
    }

    private LinearLayout page() {
        LinearLayout view = column();
        view.setPadding(dp(16), dp(6), dp(16), dp(24));
        return view;
    }

    private LinearLayout card(LinearLayout parent) {
        LinearLayout view = column();
        view.setPadding(dp(16), dp(14), dp(16), dp(14));
        view.setBackground(rounded(CARD, 18));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.setMargins(0, dp(12), 0, 0);
        parent.addView(view, params);
        return view;
    }

    private TextView label(LinearLayout parent, String text, int size, int color, boolean medium) {
        TextView view = new TextView(getContext());
        view.setText(text);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setTypeface(
                Typeface.create(medium ? "sans-serif-medium" : "sans-serif", Typeface.NORMAL));
        view.setPadding(0, dp(3), 0, dp(4));
        parent.addView(view);
        return view;
    }

    private void metric(
            LinearLayout parent, String title, String number, String detail, int color) {
        LinearLayout view = column();
        view.setPadding(dp(14), dp(12), dp(14), dp(12));
        view.setBackground(rounded(CARD, 18));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, -1, 1);
        params.setMargins(dp(3), dp(5), dp(3), dp(5));
        parent.addView(view, params);
        label(view, title, 12, MUTED, true);
        TextView value = label(view, number, 32, color, true);
        value.setMaxLines(1);
        value.setAutoSizeTextTypeUniformWithConfiguration(
                16, 32, 1, android.util.TypedValue.COMPLEX_UNIT_SP);
        label(view, detail, 10, MUTED, false);
    }

    private EditText field(LinearLayout parent, String title, String hint, boolean multiline) {
        label(parent, title, 12, MUTED, true);
        EditText view = new EditText(getContext());
        view.setHint(hint);
        view.setTextColor(INK);
        view.setHintTextColor(MUTED);
        view.setTextSize(15);
        view.setPadding(dp(12), dp(12), dp(12), dp(12));
        view.setBackground(rounded(BG, 10));
        view.setInputType(
                InputType.TYPE_CLASS_TEXT | (multiline ? InputType.TYPE_TEXT_FLAG_MULTI_LINE : 0));
        view.setSingleLine(!multiline);
        view.setImeOptions(view.getImeOptions() | EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING);
        view.setSaveEnabled(false);
        if (multiline) {
            view.setMinLines(3);
            view.setMaxLines(6);
            view.setGravity(Gravity.TOP | Gravity.START);
        }
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.setMargins(0, dp(4), 0, dp(10));
        parent.addView(view, params);
        return view;
    }

    private Switch toggle(LinearLayout parent, String title, String subtitle) {
        Switch view = new Switch(getContext());
        view.setText(title);
        view.setTextColor(INK);
        view.setTextSize(14);
        view.setSwitchPadding(dp(12));
        view.setPadding(0, dp(8), 0, dp(8));
        view.setMinHeight(dp(48));
        view.setTrackTintList(
                new ColorStateList(
                        new int[][] {new int[] {android.R.attr.state_checked}, new int[0]},
                        new int[] {ACCENT, 0xffc9ccda}));
        view.setThumbTintList(ColorStateList.valueOf(CARD));
        parent.addView(view, new LinearLayout.LayoutParams(-1, -2));
        label(parent, subtitle, 12, MUTED, false);
        return view;
    }

    private Spinner spinner(LinearLayout parent, JSONArray options) throws Exception {
        String[] titles = new String[options.length()];
        for (int i = 0; i < titles.length; i++)
            titles[i] = options.getJSONObject(i).getString("title");
        Spinner view = new Spinner(getContext());
        ArrayAdapter<String> adapter =
                new ArrayAdapter<>(getContext(), android.R.layout.simple_spinner_item, titles);
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        view.setAdapter(adapter);
        view.setBackgroundTintList(ColorStateList.valueOf(ACCENT));
        parent.addView(view, new LinearLayout.LayoutParams(-1, dp(52)));
        return view;
    }

    private Button button(LinearLayout parent, String text, Runnable action, boolean primary) {
        Button view = new Button(getContext());
        view.setText(text);
        view.setAllCaps(false);
        view.setTextSize(13);
        view.setMinWidth(0);
        view.setMinimumWidth(0);
        view.setPadding(dp(8), dp(8), dp(8), dp(8));
        view.setMinHeight(dp(48));
        view.setStateListAnimator(null);
        view.setOnClickListener(v -> action.run());
        style(view, primary ? ACCENT : TINT, primary ? CARD : ACCENT);
        LinearLayout.LayoutParams params =
                parent.getOrientation() == LinearLayout.HORIZONTAL
                        ? new LinearLayout.LayoutParams(0, -2, 1)
                        : new LinearLayout.LayoutParams(-1, -2);
        params.setMargins(dp(3), dp(5), dp(3), dp(5));
        parent.addView(view, params);
        return view;
    }

    private void style(Button view, int background, int color) {
        view.setBackgroundTintList(null);
        view.setBackground(
                new RippleDrawable(
                        ColorStateList.valueOf(0x246256d9), rounded(background, 12), null));
        view.setTextColor(color);
    }

    private GradientDrawable rounded(int color, int radius) {
        GradientDrawable view = new GradientDrawable();
        view.setColor(color);
        view.setCornerRadius(dp(radius));
        return view;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private String number(long value) {
        return NumberFormat.getIntegerInstance(EN_IN).format(value);
    }

    private String duration(long millis) {
        long seconds = millis / 1000;
        return seconds >= 3600
                ? String.format(EN_IN, "%dh %dm", seconds / 3600, seconds % 3600 / 60)
                : String.format(EN_IN, "%dm %ds", seconds / 60, seconds % 60);
    }

    private static final class UsageChart extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private List<UsageStore.Day> days;

        UsageChart(android.content.Context context) {
            super(context);
        }

        void setDays(List<UsageStore.Day> days) {
            this.days = days;
            StringBuilder description = new StringBuilder("Last seven days. ");
            for (UsageStore.Day day : days)
                description
                        .append(day.date)
                        .append(": typed estimate ")
                        .append(day.totals.typed())
                        .append(", voice output ")
                        .append(day.totals.voice())
                        .append(". ");
            setContentDescription(description.toString());
            setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_YES);
            invalidate();
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            if (days == null || days.isEmpty()) return;
            float density = getResources().getDisplayMetrics().density;
            float bottom = getHeight() - 28 * density, top = 24 * density;
            double maximum = 0;
            for (UsageStore.Day day : days)
                maximum = Math.max(maximum, (double) day.totals.typed() + day.totals.voice());
            paint.setStrokeWidth(density);
            paint.setColor(0xffe8eaf2);
            canvas.drawLine(0, bottom, getWidth(), bottom, paint);
            float step = getWidth() / 7f;
            paint.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
            paint.setTextAlign(Paint.Align.CENTER);
            paint.setTextSize(
                    android.util.TypedValue.applyDimension(
                            android.util.TypedValue.COMPLEX_UNIT_SP,
                            10,
                            getResources().getDisplayMetrics()));
            for (int i = 0; i < days.size(); i++) {
                UsageStore.Day day = days.get(i);
                float cx = step * (i + .5f), width = Math.min(24 * density, step * .55f);
                float typed =
                        maximum == 0 ? 0 : (float) (day.totals.typed() / maximum * (bottom - top));
                float voice =
                        maximum == 0 ? 0 : (float) (day.totals.voice() / maximum * (bottom - top));
                paint.setColor(0xffc6bef9);
                canvas.drawRoundRect(
                        cx - width / 2,
                        bottom - typed - voice,
                        cx + width / 2,
                        bottom - voice,
                        3 * density,
                        3 * density,
                        paint);
                paint.setColor(ACCENT);
                canvas.drawRoundRect(
                        cx - width / 2,
                        bottom - voice,
                        cx + width / 2,
                        bottom,
                        3 * density,
                        3 * density,
                        paint);
                paint.setColor(MUTED);
                canvas.drawText(
                        day.date.format(DateTimeFormatter.ofPattern("EEE", EN_IN)),
                        cx,
                        getHeight() - 8 * density,
                        paint);
            }
            if (maximum == 0) {
                paint.setTextSize(
                        android.util.TypedValue.applyDimension(
                                android.util.TypedValue.COMPLEX_UNIT_SP,
                                12,
                                getResources().getDisplayMetrics()));
                canvas.drawText(
                        "Your activity will appear here", getWidth() / 2f, getHeight() / 2f, paint);
            }
        }
    }
}
