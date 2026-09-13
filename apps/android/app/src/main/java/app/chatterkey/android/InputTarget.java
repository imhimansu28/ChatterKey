package app.chatterkey.android;

import android.inputmethodservice.InputMethodService;
import android.text.InputType;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;

import java.util.Objects;

final class InputTarget {
    final InputConnection connection;
    final long session;
    final int start, end;
    final String selected, before, after;
    private final boolean verifiable;

    private InputTarget(
            InputConnection connection,
            long session,
            int start,
            int end,
            String selected,
            String before,
            String after,
            boolean verifiable) {
        this.connection = connection;
        this.session = session;
        this.start = start;
        this.end = end;
        this.selected = selected;
        this.before = before;
        this.after = after;
        this.verifiable = verifiable;
    }

    static boolean secure(EditorInfo info) {
        if (info == null) return true;
        int type = info.inputType & InputType.TYPE_MASK_CLASS;
        int variation = info.inputType & InputType.TYPE_MASK_VARIATION;
        return info.inputType == InputType.TYPE_NULL
                || (type == InputType.TYPE_CLASS_NUMBER
                        && variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD)
                || (type == InputType.TYPE_CLASS_TEXT
                        && (variation == InputType.TYPE_TEXT_VARIATION_PASSWORD
                                || variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD
                                || variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD));
    }

    static InputTarget capture(InputMethodService service, long session, int start, int end) {
        InputConnection connection = service.getCurrentInputConnection();
        if (connection == null || secure(service.getCurrentInputEditorInfo()))
            throw new IllegalStateException("Voice input is unavailable in this field.");
        String selected = string(connection.getSelectedText(0));
        if (selected != null && selected.length() > 50_000)
            throw new IllegalStateException("Select fewer than 50,000 characters.");
        if (selected != null && selected.isEmpty()) selected = null;
        if (start >= 0 && end >= 0 && start != end && selected == null)
            throw new IllegalStateException(
                    "Selected text is unavailable. Clear the selection or use a supported editor.");
        String before = string(connection.getTextBeforeCursor(64, 0));
        String after = string(connection.getTextAfterCursor(64, 0));
        boolean valid =
                start >= 0
                        && end >= 0
                        && (selected == null
                                ? start == end
                                : selected.length() == Math.abs(end - start));
        return new InputTarget(
                connection,
                session,
                start,
                end,
                selected,
                before,
                after,
                valid && before != null && after != null);
    }

    boolean current(InputMethodService service, long session, int start, int end) {
        if (!verifiable
                || this.session != session
                || this.start != start
                || this.end != end
                || secure(service.getCurrentInputEditorInfo())
                || service.getCurrentInputConnection() != connection) return false;
        String actual = string(connection.getSelectedText(0));
        if (actual != null && actual.isEmpty()) actual = null;
        return Objects.equals(selected, actual)
                && Objects.equals(before, string(connection.getTextBeforeCursor(64, 0)))
                && Objects.equals(after, string(connection.getTextAfterCursor(64, 0)));
    }

    private static String string(CharSequence value) {
        return value == null ? null : value.toString();
    }
}
