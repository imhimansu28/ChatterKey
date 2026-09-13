package app.chatterkey.android;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.os.SystemClock;
import android.view.View;

import java.util.Locale;
import java.util.function.DoubleSupplier;

/** A local audio-level display. No audio samples, network calls or files are retained here. */
final class VoiceFeedbackView extends View {
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final DoubleSupplier audioLevel;
    private boolean recording, processing, locked;
    private long startedAt;
    private float level;
    private final Runnable frame =
            new Runnable() {
                @Override
                public void run() {
                    if (!isShown()
                            || getWindowVisibility() != VISIBLE
                            || !isAttachedToWindow()
                            || (!recording && !processing)) return;
                    invalidate();
                    postDelayed(this, ValueAnimator.areAnimatorsEnabled() ? 50 : 1000);
                }
            };

    public VoiceFeedbackView(Context context) {
        this(context, () -> 0);
    }

    VoiceFeedbackView(Context context, DoubleSupplier audioLevel) {
        super(context);
        this.audioLevel = audioLevel;
        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_YES);
    }

    void state(boolean recording, boolean processing, boolean locked, long startedAt) {
        boolean changed =
                this.recording != recording
                        || this.processing != processing
                        || this.locked != locked;
        this.recording = recording;
        this.processing = processing;
        this.locked = locked;
        this.startedAt = startedAt;
        if (!recording) level = 0;
        if (changed)
            setContentDescription(
                    processing
                            ? "Processing audio. One model request."
                            : locked
                                    ? "Hands-free recording. Tap Stop when finished."
                                    : "Recording. Release the microphone when finished.");
        schedule();
    }

    private void schedule() {
        removeCallbacks(frame);
        if (isShown()
                && getWindowVisibility() == VISIBLE
                && isAttachedToWindow()
                && (recording || processing)) post(frame);
        invalidate();
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        schedule();
    }

    @Override
    protected void onDetachedFromWindow() {
        removeCallbacks(frame);
        super.onDetachedFromWindow();
    }

    @Override
    protected void onVisibilityChanged(View view, int visibility) {
        super.onVisibilityChanged(view, visibility);
        if (frame != null) schedule();
    }

    @Override
    protected void onWindowVisibilityChanged(int visibility) {
        super.onWindowVisibilityChanged(visibility);
        if (frame != null) schedule();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        float density = getResources().getDisplayMetrics().density;
        float cx = getWidth() / 2f, cy = getHeight() * .56f;
        boolean animate = ValueAnimator.areAnimatorsEnabled();
        float time = animate ? (SystemClock.uptimeMillis() % 12000) / 1000f : 0;
        float observed = recording ? (float) audioLevel.getAsDouble() : 0;
        level = animate ? level * .65f + observed * .35f : observed;
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(0xffebe8ff);
        canvas.drawCircle(cx, cy, 43 * density, paint);
        int bars = 23;
        float step = Math.min(11 * density, getWidth() / 30f);
        for (int i = 0; i < bars; i++) {
            float distance = Math.abs(i - (bars - 1) / 2f) / (bars / 2f);
            float envelope = (float) Math.sqrt(Math.max(0, 1 - distance));
            float wave =
                    processing
                            ? .2f + .65f * (float) Math.pow(Math.sin(time * 3 - i * .25f), 2)
                            : level
                                    * (.6f
                                            + .4f
                                                    * (float)
                                                            Math.pow(
                                                                    Math.sin(time * 4 + i * .75f),
                                                                    2));
            float available =
                    Math.max(12 * density, Math.min(56 * density, getHeight() - 80 * density));
            float height = 5 * density + available * envelope * wave;
            float x = cx + (i - (bars - 1) / 2f) * step;
            paint.setColor(i % 3 == 0 ? 0xff8980ec : 0xff6256d9);
            canvas.drawRoundRect(
                    x - 2 * density,
                    cy - height / 2,
                    x + 2 * density,
                    cy + height / 2,
                    3 * density,
                    3 * density,
                    paint);
        }
        paint.setTextAlign(Paint.Align.CENTER);
        paint.setColor(0xff252738);
        paint.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        paint.setTextSize(
                android.util.TypedValue.applyDimension(
                        android.util.TypedValue.COMPLEX_UNIT_SP,
                        20,
                        getResources().getDisplayMetrics()));
        canvas.drawText(
                processing
                        ? "Making words happen"
                        : locked ? "You're hands-free" : "Listening to you",
                cx,
                28 * density,
                paint);
        paint.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
        paint.setTextSize(
                android.util.TypedValue.applyDimension(
                        android.util.TypedValue.COMPLEX_UNIT_SP,
                        12,
                        getResources().getDisplayMetrics()));
        paint.setColor(0xff676b80);
        long seconds =
                recording ? Math.max(0, (SystemClock.elapsedRealtime() - startedAt) / 1000) : 0;
        String caption =
                processing
                        ? "One request · no automatic retries"
                        : String.format(
                                Locale.ROOT,
                                "%d:%02d / 2:00  ·  %s",
                                seconds / 60,
                                seconds % 60,
                                locked ? "Tap Stop to finish" : "Release mic to finish");
        canvas.drawText(caption, cx, getHeight() - 14 * density, paint);
    }
}
