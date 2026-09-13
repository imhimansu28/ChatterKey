#include <jni.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

extern char *chatterkey_call(const char *, const uint8_t *, int32_t);
extern void chatterkey_free(char *);

// Byte arrays avoid JNI modified-UTF-8 corruption of emoji, Hindi and embedded NULs.
JNIEXPORT jbyteArray JNICALL
Java_app_chatterkey_android_CoreBridge_call(JNIEnv *env, jclass type, jbyteArray input, jbyteArray audio) {
    (void)type;
    if (!input) return NULL;
    jsize length = (*env)->GetArrayLength(env, input);
    if (length < 1 || length > 1000000) return NULL;
    char *text = malloc((size_t)length + 1);
    if (!text) return NULL;
    (*env)->GetByteArrayRegion(env, input, 0, length, (jbyte *)text);
    if ((*env)->ExceptionCheck(env)) { free(text); return NULL; }
    text[length] = 0;
    jsize count = audio ? (*env)->GetArrayLength(env, audio) : 0;
    if (count > 8000000) { free(text); return NULL; }
    jbyte *bytes = audio ? (*env)->GetByteArrayElements(env, audio, NULL) : NULL;
    if (audio && !bytes) { free(text); return NULL; }
    char *result = chatterkey_call(text, (uint8_t *)bytes, count);
    free(text);
    if (bytes) (*env)->ReleaseByteArrayElements(env, audio, bytes, JNI_ABORT);
    if (!result) return NULL;
    size_t resultLength = strlen(result);
    jbyteArray output = (*env)->NewByteArray(env, (jsize)resultLength);
    if (output) (*env)->SetByteArrayRegion(env, output, 0, (jsize)resultLength, (jbyte *)result);
    chatterkey_free(result);
    return output;
}
