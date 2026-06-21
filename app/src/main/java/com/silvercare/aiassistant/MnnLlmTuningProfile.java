package com.silvercare.aiassistant;

enum MnnLlmTuningProfile {
    AUTO(
        "auto",
        "SME2 自动调优",
        "检测到 SME2 时使用 MNN 推荐的 41/2 配置；否则使用 MNN 默认路径。",
        41,
        2,
        true
    ),
    PERFORMANCE(
        "performance",
        "SME2 性能优先",
        "偏向更高吞吐，适合长提示词和需要更快首轮响应的 4B 文本推理。",
        49,
        2,
        true
    ),
    EFFICIENCY(
        "efficiency",
        "SME2 省电稳定",
        "减少 SME 核参与，优先降低发热和长时间使用时的降频风险。",
        33,
        1,
        true
    ),
    MNN_DEFAULT(
        "mnn_default",
        "MNN 默认",
        "不覆盖 MNN-LLM 的运行时配置，用于排查兼容性或对比基准。",
        0,
        0,
        false
    );

    static final MnnLlmTuningProfile DEFAULT = AUTO;
    private static final String QWEN3_NO_THINK_CONFIG = "\"jinja\":{\"context\":{\"enable_thinking\":false}}";

    final String value;
    final String label;
    final String description;
    final int sme2NeonDivisionRatio;
    final int smeCoreCount;
    private final boolean appliesSme2Config;

    MnnLlmTuningProfile(
        String value,
        String label,
        String description,
        int sme2NeonDivisionRatio,
        int smeCoreCount,
        boolean appliesSme2Config
    ) {
        this.value = value;
        this.label = label;
        this.description = description;
        this.sme2NeonDivisionRatio = sme2NeonDivisionRatio;
        this.smeCoreCount = smeCoreCount;
        this.appliesSme2Config = appliesSme2Config;
    }

    static MnnLlmTuningProfile from(String value) {
        if (value != null) {
            for (MnnLlmTuningProfile profile : values()) {
                if (profile.value.equals(value)) return profile;
            }
        }
        return DEFAULT;
    }

    String nativeConfigJson(boolean sme2Supported) {
        if (!appliesSme2Config || !sme2Supported) return "{" + QWEN3_NO_THINK_CONFIG + "}";
        return "{" + QWEN3_NO_THINK_CONFIG
            + ",\"cpu_sme2_neon_division_ratio\":" + sme2NeonDivisionRatio
            + ",\"cpu_sme_core_num\":" + smeCoreCount + "}";
    }

    String menuText(boolean sme2Supported) {
        if (!appliesSme2Config) {
            return label + "：不覆盖 MNN 配置";
        }
        String suffix = sme2Supported
            ? "比例 " + sme2NeonDivisionRatio + "，SME 核 " + smeCoreCount
            : "当前设备未检测到 SME2，会自动回退";
        return label + "：" + suffix;
    }
}
