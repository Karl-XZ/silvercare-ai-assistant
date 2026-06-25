package com.silvercare.aiassistant;

enum TtsRuntimeMode {
    AUTO("auto", "自动兜底"),
    LOCAL_MNN("local_mnn", "本地 MNN TTS（实验）"),
    SYSTEM("system", "手机系统 TTS（本地）"),
    DASHSCOPE("dashscope", "联网 DashScope");

    static final TtsRuntimeMode DEFAULT = DASHSCOPE;

    final String value;
    final String label;

    TtsRuntimeMode(String value, String label) {
        this.value = value;
        this.label = label;
    }

    boolean allowsLocal() {
        return this == LOCAL_MNN;
    }

    boolean allowsSystem() {
        return this == AUTO || this == SYSTEM;
    }

    boolean allowsDashScope() {
        return this == AUTO || this == DASHSCOPE;
    }

    static TtsRuntimeMode from(String value) {
        if ("local_qwen".equals(value)) return LOCAL_MNN;
        for (TtsRuntimeMode mode : values()) {
            if (mode.value.equals(value)) return mode;
        }
        return DEFAULT;
    }
}
