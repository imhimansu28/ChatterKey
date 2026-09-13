# The C entry point resolves this exact class/method name through JNI.
-keep class app.chatterkey.android.CoreBridge {
    private static native byte[] call(byte[], byte[]);
}
