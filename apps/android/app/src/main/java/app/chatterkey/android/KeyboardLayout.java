package app.chatterkey.android;

import java.util.Locale;

/** English (India) key pages and shift state, independent of Android views. */
final class KeyboardLayout {
    private int page;
    private int caps; // 0: lowercase, 1: next letter, 2: caps lock.
    private long lastShift = -1;

    void reset(boolean numeric) {
        page = numeric ? 1 : 0;
        caps = 0;
        lastShift = -1;
    }

    boolean symbols() {
        return page != 0;
    }

    boolean shifted() {
        return caps != 0;
    }

    boolean capsLocked() {
        return caps == 2;
    }

    void toggleSymbols() {
        page = page == 0 ? 1 : 0;
        lastShift = -1;
    }

    void shift(long time) {
        if (symbols()) {
            page = page == 1 ? 2 : 1;
            return;
        }
        if (caps == 0) caps = 1;
        else if (caps == 1 && lastShift >= 0 && time >= lastShift && time - lastShift <= 350)
            caps = 2;
        else caps = 0;
        lastShift = time;
    }

    void lockCaps() {
        if (!symbols()) {
            caps = 2;
            lastShift = -1;
        }
    }

    boolean inserted(String text) {
        lastShift = -1;
        if (page == 0 && caps == 1 && !text.isEmpty() && Character.isLetter(text.codePointAt(0))) {
            caps = 0;
            return true;
        }
        return false;
    }

    String shiftLabel() {
        return page == 1 ? "=\\<" : "?123";
    }

    String[] rows() {
        if (page == 1) return new String[] {"1234567890", "@#₹_&-+()/", "*\"':;!?"};
        if (page == 2) return new String[] {"~`|•√π÷×§∆", "£€$¢^°={}\\", "%©®™✓[]"};
        String[] rows = {"qwertyuiop", "asdfghjkl", "zxcvbnm"};
        if (shifted())
            for (int i = 0; i < rows.length; i++) rows[i] = rows[i].toUpperCase(Locale.ROOT);
        return rows;
    }
}
