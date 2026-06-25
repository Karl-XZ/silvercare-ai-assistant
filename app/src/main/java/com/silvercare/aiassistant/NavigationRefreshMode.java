package com.silvercare.aiassistant;

enum NavigationRefreshMode {
    AUTO("auto", "自动刷新"),
    MANUAL("manual", "手动刷新");

    static final NavigationRefreshMode DEFAULT = MANUAL;

    final String value;
    final String label;

    NavigationRefreshMode(String value, String label) {
        this.value = value;
        this.label = label;
    }

    static NavigationRefreshMode from(String value) {
        for (NavigationRefreshMode mode : values()) {
            if (mode.value.equals(value)) return mode;
        }
        return DEFAULT;
    }

    boolean isManual() {
        return this == MANUAL;
    }
}
