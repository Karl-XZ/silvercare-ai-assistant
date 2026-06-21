#include <jni.h>

namespace {

void throwIllegalState(JNIEnv* env) {
    jclass cls = env->FindClass("java/lang/IllegalStateException");
    if (cls != nullptr) {
        env->ThrowNew(
            cls,
            "x86_64 emulator build only supports UI, sensors, and DashScope testing. "
            "Use an arm64-v8a phone for local MNN inference."
        );
    }
}

} // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_silvercare_aiassistant_MnnNativeBridge_nativeRuntimeKind(
    JNIEnv* env,
    jobject
) {
    return env->NewStringUTF("unsupported-x86_64-emulator");
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_silvercare_aiassistant_MnnNativeBridge_nativeSupportsSme2(
    JNIEnv*,
    jobject
) {
    return JNI_FALSE;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_silvercare_aiassistant_MnnNativeBridge_nativeVisionJson(
    JNIEnv* env,
    jobject,
    jstring,
    jstring,
    jfloatArray,
    jint,
    jint,
    jstring
) {
    throwIllegalState(env);
    return nullptr;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_silvercare_aiassistant_MnnNativeBridge_nativeTextJson(
    JNIEnv* env,
    jobject,
    jstring,
    jstring,
    jstring,
    jstring,
    jint,
    jstring
) {
    throwIllegalState(env);
    return nullptr;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_silvercare_aiassistant_MnnNativeBridge_nativeTranscribe(
    JNIEnv* env,
    jobject,
    jstring,
    jstring
) {
    throwIllegalState(env);
    return nullptr;
}
