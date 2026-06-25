package com.silvercare.aiassistant;

enum AiRuntimeMode {
    DASHSCOPE("dashscope", "联网 DashScope"),
    OFFLINE_MNN("offline_mnn", "端侧离线 MNN");

    static final AiRuntimeMode DEFAULT = DASHSCOPE;

    final String value;
    final String label;

    AiRuntimeMode(String value, String label) {
        this.value = value;
        this.label = label;
    }

    static AiRuntimeMode from(String value) {
        for (AiRuntimeMode mode : values()) {
            if (mode.value.equals(value)) return mode;
        }
        return DEFAULT;
    }

    boolean isOffline() {
        return this == OFFLINE_MNN;
    }
}
