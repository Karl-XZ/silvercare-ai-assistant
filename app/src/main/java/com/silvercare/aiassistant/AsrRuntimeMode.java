package com.silvercare.aiassistant;

enum AsrRuntimeMode {
    LOCAL_VOSK("local_vosk", "本地内置 ASR"),
    DASHSCOPE("dashscope", "联网 DashScope");

    final String value;
    final String label;

    AsrRuntimeMode(String value, String label) {
        this.value = value;
        this.label = label;
    }

    boolean isLocal() {
        return this == LOCAL_VOSK;
    }

    static AsrRuntimeMode from(String value) {
        if (DASHSCOPE.value.equals(value)) return DASHSCOPE;
        return LOCAL_VOSK;
    }
}
