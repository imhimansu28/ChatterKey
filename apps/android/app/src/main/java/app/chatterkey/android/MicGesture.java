package app.chatterkey.android;

final class MicGesture {
    static final long DOUBLE_TAP_MS = 350;

    enum Action {
        NONE,
        START,
        WAIT,
        LOCK,
        STOP
    }

    private boolean active, locked, pending;
    private long pressedAt, releasedAt;

    Action down(long time) {
        if (locked) {
            reset();
            return Action.STOP;
        }
        if (pending) {
            pending = false;
            long gap = time - releasedAt;
            if (gap >= 0 && gap <= DOUBLE_TAP_MS) {
                locked = true;
                return Action.LOCK;
            }
            reset();
            return Action.STOP;
        }
        if (active) return Action.NONE;
        active = true;
        pressedAt = time;
        return Action.START;
    }

    Action up(long time) {
        if (!active || locked) return Action.NONE;
        if (time - pressedAt >= 0 && time - pressedAt <= 250) {
            pending = true;
            releasedAt = time;
            return Action.WAIT;
        }
        reset();
        return Action.STOP;
    }

    Action expire() {
        if (!pending) return Action.NONE;
        reset();
        return Action.STOP;
    }

    void startLocked() {
        active = true;
        locked = true;
        pending = false;
    }

    void reset() {
        active = false;
        locked = false;
        pending = false;
    }

    boolean locked() {
        return locked;
    }
}
