package app.chatterkey.android;

import static org.junit.Assert.*;

import org.junit.Test;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;

public class KeyboardUnitTest {
    @Test
    public void typedWordsKeepOnlyRunStateAndHandleHindiAndCorrections() {
        UsageStore.TypedWords words = new UsageStore.TypedWords();
        assertEquals(1, words.accept("h"));
        assertEquals(0, words.accept("ello"));
        assertEquals(0, words.accept(" "));
        assertEquals(3, words.accept("नमस्ते दुनिया 42"));
        assertEquals(0, words.accept("?! 👋"));
        assertEquals(1, words.accept("don't"));
        words.reset();
        assertEquals(1, words.accept("retyped"));
        assertEquals(1, words.accept("\nnext"));
    }

    @Test
    public void englishIndiaPagesHaveFullAlphabetNumbersAndRupee() {
        KeyboardLayout layout = new KeyboardLayout();
        assertArrayEquals(new String[] {"qwertyuiop", "asdfghjkl", "zxcvbnm"}, layout.rows());
        layout.toggleSymbols();
        assertEquals("1234567890", layout.rows()[0]);
        assertTrue(layout.rows()[1].contains("₹"));
        assertEquals(10, layout.rows()[1].length());
        layout.shift(100);
        assertEquals(10, layout.rows()[0].length());
        assertEquals(10, layout.rows()[1].length());
        assertTrue(layout.rows()[1].contains("\\"));
        assertEquals(7, layout.rows()[2].length());
        layout.shift(200);
        assertEquals("1234567890", layout.rows()[0]);
        layout.toggleSymbols();
        assertEquals("qwertyuiop", layout.rows()[0]);
        layout.reset(true);
        assertTrue(layout.symbols());
    }

    @Test
    public void oneShotShiftCapsLockAndSessionReset() {
        KeyboardLayout layout = new KeyboardLayout();
        layout.shift(100);
        assertEquals("QWERTYUIOP", layout.rows()[0]);
        assertTrue(layout.inserted("Q"));
        assertFalse(layout.shifted());
        layout.shift(200);
        layout.shift(300);
        assertTrue(layout.capsLocked());
        assertFalse(layout.inserted("A"));
        assertTrue(layout.shifted());
        layout.shift(400);
        assertFalse(layout.shifted());
        layout.shift(500);
        layout.shift(1000);
        assertFalse(layout.shifted());
        layout.lockCaps();
        layout.reset(false);
        assertFalse(layout.shifted());
        layout.shift(2000);
        layout.shift(1900);
        assertFalse(layout.capsLocked());
    }

    @Test
    public void audioLevelIsBoundedAndMeasuresOnlyCapturedPcm() {
        assertEquals(0f, VoiceRecorder.audioLevel(new byte[8], 8), 0f);
        assertEquals(0f, VoiceRecorder.audioLevel(new byte[0], 0), 0f);
        assertEquals(1f, VoiceRecorder.audioLevel(new byte[] {0, -128, -1, 127}, 4), 0f);
        assertEquals(.5f, VoiceRecorder.audioLevel(new byte[] {0, 16, 0, -128}, 2), .001f);
        assertEquals(.5f, VoiceRecorder.audioLevel(new byte[] {0, -16}, 2), .001f);
    }

    @Test
    public void holdAndDoubleTapFinishOnlyOnce() {
        MicGesture gesture = new MicGesture();
        assertEquals(MicGesture.Action.START, gesture.down(100));
        assertEquals(MicGesture.Action.STOP, gesture.up(500));
        assertEquals(MicGesture.Action.NONE, gesture.expire());
        assertEquals(MicGesture.Action.START, gesture.down(1000));
        assertEquals(MicGesture.Action.WAIT, gesture.up(1100));
        assertEquals(MicGesture.Action.LOCK, gesture.down(1200));
        assertTrue(gesture.locked());
        assertEquals(MicGesture.Action.NONE, gesture.up(1300));
        assertEquals(MicGesture.Action.NONE, gesture.expire());
        assertEquals(MicGesture.Action.STOP, gesture.down(2000));
        assertEquals(MicGesture.Action.NONE, gesture.up(2100));
        assertFalse(gesture.locked());
    }

    @Test
    public void delayedTimerDoesNotLockDistantTaps() {
        MicGesture gesture = new MicGesture();
        gesture.down(100);
        gesture.up(200);
        assertEquals(MicGesture.Action.STOP, gesture.down(600));
        assertEquals(MicGesture.Action.NONE, gesture.expire());
        assertEquals(MicGesture.Action.NONE, gesture.up(650));
    }

    @Test
    public void cancelManualStopAndFailedStartClearPendingGestures() {
        MicGesture gesture = new MicGesture();
        gesture.down(100);
        gesture.up(200);
        gesture.reset();
        assertEquals(MicGesture.Action.NONE, gesture.expire());
        assertEquals(MicGesture.Action.START, gesture.down(250));
        gesture.reset();
        assertEquals(MicGesture.Action.NONE, gesture.up(260));
        gesture.startLocked();
        assertTrue(gesture.locked());
        assertEquals(MicGesture.Action.STOP, gesture.down(300));
    }

    @Test
    public void singleTapFinishesAfterGraceAndClockReversalDoesNotLock() {
        MicGesture gesture = new MicGesture();
        gesture.down(100);
        gesture.up(200);
        assertEquals(MicGesture.Action.STOP, gesture.expire());
        assertEquals(MicGesture.Action.NONE, gesture.expire());
        gesture.down(300);
        gesture.up(400);
        assertEquals(MicGesture.Action.STOP, gesture.down(350));
    }

    @Test
    public void wavContainsExactMonoPcmAndLength() {
        byte[] pcm = {1, 2, 3, 4};
        byte[] wav = VoiceRecorder.wav(pcm);
        ByteBuffer buffer = ByteBuffer.wrap(wav).order(ByteOrder.LITTLE_ENDIAN);
        assertEquals("RIFF", new String(wav, 0, 4, StandardCharsets.US_ASCII));
        assertEquals(40, buffer.getInt(4));
        assertEquals(1, buffer.getShort(22));
        assertEquals(16000, buffer.getInt(24));
        assertEquals(32000, buffer.getInt(28));
        assertEquals(16, buffer.getShort(34));
        assertEquals(4, buffer.getInt(40));
        assertArrayEquals(pcm, java.util.Arrays.copyOfRange(wav, 44, wav.length));
    }

    @Test(expected = IllegalArgumentException.class)
    public void partialPcmSampleRejected() {
        VoiceRecorder.wav(new byte[] {1});
    }
}
