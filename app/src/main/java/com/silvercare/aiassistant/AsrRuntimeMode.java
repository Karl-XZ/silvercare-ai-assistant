package com.silvercare.aiassistant;

enum AsrRuntimeMode {
    LOCAL_SENSEVOICE("local_sensevoice", "本地 SenseVoice"),
    DASHSCOPE("dashscope", "联网 DashScope");

    static final AsrRuntimeMode DEFAULT = DASHSCOPE;

    final String value;
    final String label;

    AsrRuntimeMode(String value, String label) {
        this.value = value;
        this.label = label;
    }

    boolean isLocal() {
        return this == LOCAL_SENSEVOICE;
    }

    static AsrRuntimeMode from(String value) {
        if (DASHSCOPE.value.equals(value)) return DASHSCOPE;
        if (LOCAL_SENSEVOICE.value.equals(value) || "local_vosk".equals(value)) return LOCAL_SENSEVOICE;
        return DEFAULT;
    }
}
