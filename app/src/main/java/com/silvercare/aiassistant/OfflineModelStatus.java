package com.silvercare.aiassistant;

import java.io.File;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

final class OfflineModelStatus {
    final String modelDir;
    final String textModel;
    final File textConfig;
    final File yoloModel;
    final boolean nativeRuntimeAvailable;
    final boolean directoryReadable;
    final boolean textReady;
    final boolean yoloReady;
    final List<String> missing;

    OfflineModelStatus(
        String modelDir,
        File textConfig,
        File yoloModel,
        boolean nativeRuntimeAvailable,
        boolean directoryReadable,
        boolean textReady,
        boolean yoloReady,
        List<String> missing
    ) {
        this(
            modelDir,
            OfflineAiClient.TEXT_MODEL,
            textConfig,
            yoloModel,
            nativeRuntimeAvailable,
            directoryReadable,
            textReady,
            yoloReady,
            missing
        );
    }

    OfflineModelStatus(
        String modelDir,
        String textModel,
        File textConfig,
        File yoloModel,
        boolean nativeRuntimeAvailable,
        boolean directoryReadable,
        boolean textReady,
        boolean yoloReady,
        List<String> missing
    ) {
        this.modelDir = modelDir;
        this.textModel = OfflineAiClient.isOfflineTextModel(textModel) ? textModel : OfflineAiClient.TEXT_MODEL;
        this.textConfig = textConfig;
        this.yoloModel = yoloModel;
        this.nativeRuntimeAvailable = nativeRuntimeAvailable;
        this.directoryReadable = directoryReadable;
        this.textReady = textReady;
        this.yoloReady = yoloReady;
        this.missing = Collections.unmodifiableList(new ArrayList<>(missing));
    }

    boolean ready() {
        return nativeRuntimeAvailable && directoryReadable && textReady && yoloReady;
    }

    String shortText() {
        if (ready()) return "端侧离线模型已就绪";
        if (missing.isEmpty()) return "端侧离线模型未就绪";
        return "端侧离线模型未就绪：" + String.join("、", missing);
    }

    String detailText() {
        StringBuilder builder = new StringBuilder();
        builder.append(shortText())
            .append("\n\n模型目录：").append(modelDir == null || modelDir.isEmpty() ? "未设置" : modelDir)
            .append("\n离线文本模型：").append(OfflineAiClient.textModelLabel(textModel))
            .append("\n文本模型文件：").append(textReady ? pathOf(textConfig) : "未找到 config.json")
            .append("\nDAMO-YOLO：").append(yoloReady ? pathOf(yoloModel) : "未找到 .mnn 模型")
            .append("\nMNN Native Runtime：").append(nativeRuntimeAvailable ? "已加载" : "未加载 silvercare_mnn_runtime");
        return builder.toString();
    }

    private static String pathOf(File file) {
        return file == null ? "未找到" : file.getAbsolutePath();
    }
}
