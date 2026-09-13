package app.chatterkey.android;

import android.content.Context;
import android.content.SharedPreferences;
import android.view.inputmethod.EditorInfo;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * Opt-in aggregate counters only: no text, audio, key sequences, app IDs or per-attempt history.
 */
final class UsageStore {
    private final SharedPreferences preferences;
    private static final String[] METRICS = {"typed", "voice", "millis", "dictations", "edits"};

    UsageStore(Context context) {
        this(context.getSharedPreferences("chatterkey.usage.v1", Context.MODE_PRIVATE));
    }

    UsageStore(SharedPreferences preferences) {
        this.preferences = preferences;
    }

    boolean enabled() {
        return preferences.getBoolean("enabled", false);
    }

    long revision() {
        return preferences.getLong("revision", 0);
    }

    void setEnabled(boolean enabled) {
        synchronized (preferences) {
            if (enabled == enabled()) return;
            preferences
                    .edit()
                    .putBoolean("enabled", enabled)
                    .putLong("revision", revision() + 1)
                    .apply();
        }
    }

    void clear() {
        synchronized (preferences) {
            preferences
                    .edit()
                    .clear()
                    .putBoolean("enabled", enabled())
                    .putLong("revision", revision() + 1)
                    .apply();
        }
    }

    static boolean allowed(EditorInfo info) {
        return !InputTarget.secure(info)
                && (info.imeOptions & EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING) == 0;
    }

    void typed(long words) {
        if (words > 0) record(new long[] {words, 0, 0, 0, 0}, revision());
    }

    void voice(long words, long millis, boolean editing, long revision) {
        record(
                new long[] {
                    0,
                    editing ? 0 : Math.max(0, words),
                    Math.max(0, millis),
                    editing ? 0 : 1,
                    editing ? 1 : 0
                },
                revision);
    }

    private void record(long[] delta, long expectedRevision) {
        synchronized (preferences) {
            if (!enabled() || revision() != expectedRevision) return;
            String day = LocalDate.now().toString();
            SharedPreferences.Editor update = preferences.edit();
            for (int i = 0; i < METRICS.length; i++) {
                if (delta[i] == 0) continue;
                for (String prefix : new String[] {"all.", "day." + day + "."}) {
                    String key = prefix + METRICS[i];
                    update.putLong(key, preferences.getLong(key, 0) + delta[i]);
                }
            }
            String oldest = LocalDate.now().minusDays(29).toString();
            for (String key : preferences.getAll().keySet()) {
                if (key.startsWith("day.")
                        && key.length() > 14
                        && key.substring(4, 14).compareTo(oldest) < 0) update.remove(key);
            }
            update.apply();
        }
    }

    Totals total() {
        return totals("all.");
    }

    Totals today() {
        return totals("day." + LocalDate.now() + ".");
    }

    Totals week() {
        long[] sum = new long[METRICS.length];
        for (Day day : days()) {
            long[] values = day.totals.values;
            for (int i = 0; i < values.length; i++) sum[i] += values[i];
        }
        return new Totals(sum);
    }

    List<Day> days() {
        List<Day> result = new ArrayList<>();
        LocalDate today = LocalDate.now();
        for (int i = 6; i >= 0; i--) {
            LocalDate date = today.minusDays(i);
            result.add(new Day(date, totals("day." + date + ".")));
        }
        return result;
    }

    private Totals totals(String prefix) {
        long[] values = new long[METRICS.length];
        for (int i = 0; i < values.length; i++)
            values[i] = preferences.getLong(prefix + METRICS[i], 0);
        return new Totals(values);
    }

    static final class Totals {
        private final long[] values;

        Totals(long[] values) {
            this.values = values;
        }

        long typed() {
            return values[0];
        }

        long voice() {
            return values[1];
        }

        long millis() {
            return values[2];
        }

        long dictations() {
            return values[3];
        }

        long edits() {
            return values[4];
        }
    }

    static final class Day {
        final LocalDate date;
        final Totals totals;

        Day(LocalDate date, Totals totals) {
            this.date = date;
            this.totals = totals;
        }
    }

    /**
     * Counts new letter/number runs from accepted ChatterKey taps, without retaining characters.
     */
    static final class TypedWords {
        private boolean inWord;

        void reset() {
            inWord = false;
        }

        int accept(String text) {
            int count = 0;
            for (int i = 0; i < text.length(); ) {
                int c = text.codePointAt(i);
                i += Character.charCount(c);
                if (Character.isLetterOrDigit(c)) {
                    if (!inWord) count++;
                    inWord = true;
                } else if (c != '\''
                        && c != '’'
                        && Character.getType(c) != Character.NON_SPACING_MARK
                        && Character.getType(c) != Character.COMBINING_SPACING_MARK
                        && c != 0x200d
                        && c != 0x200c) {
                    inWord = false;
                }
            }
            return count;
        }
    }
}
