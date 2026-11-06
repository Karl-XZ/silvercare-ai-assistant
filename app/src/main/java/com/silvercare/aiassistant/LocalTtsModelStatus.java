package com.silvercare.aiassistant;

import java.io.File;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

final class LocalTtsModelStatus {
    final File modelRoot;
    final File modelDir;
    final boolean runtimeAvailable;
    final String runtimeSummary;
    final boolean directoryReadable;
    final boolean modelReady;
    final boolean ready;
    final List<String> missing;

    LocalTtsModelStatus(
        File modelRoot,
        File modelDir,
        boolean runtimeAvailable,
        String runtimeSummary,
        boolean directoryReadable,
        boolean modelReady,
        List<String> missing
    ) {
        this.modelRoot = modelRoot;
        this.modelDir = modelDir;
        this.runtimeAvailable = runtimeAvailable;
        this.runtimeSummary = runtimeSummary == null ? "" : runtimeSummary;
        this.directoryReadable = directoryReadable;
        this.modelReady = modelReady;
        this.ready = modelReady && runtimeAvailable;
        this.missing = Collections.unmodifiableList(new ArrayList<>(missing));
    }

    String shortText() {
        if (ready) return "本地 MNN TTS 已就绪";
        if (modelReady && !runtimeAvailable) return "本地 MNN TTS 模型已下载，Native Runtime 不可用";
        if (missing.isEmpty()) return "本地 MNN TTS 未就绪";
        return "本地 MNN TTS 未就绪：" + String.join("、", missing);
    }

    String detailText() { return detailText("zh"); }

    String detailText(String language) {
        StringBuilder builder = new StringBuilder();
        builder.append(LanguageResources.text(language, shortText()))
            .append(LanguageResources.text(language, "\n\n模型目录：")).append(pathOf(modelDir, language))
            .append(LanguageResources.text(language, "\n模型来源：")).append(LocalTtsDownloader.MODEL_NAME)
            .append(LanguageResources.text(language, "\n下载大小：约 "))
            .append(LocalTtsDownloader.humanBytes(LocalTtsDownloader.expectedTotalBytes()))
            .append("\nNative Runtime：")
            .append(runtimeAvailable ? LanguageResources.text(language, "已就绪，") : LanguageResources.text(language, "不可用，"))
            .append(runtimeSummary == null || runtimeSummary.isEmpty() ? LanguageResources.text(language, "无运行时信息") : LanguageResources.text(language, runtimeSummary))
            .append(LanguageResources.text(language, "\n用途：端侧离线文字转语音，朗读内容不上云。"));
        return builder.toString();
    }

    private static String pathOf(File file, String language) {
        return file == null ? LanguageResources.text(language, "未设置") : file.getAbsolutePath();
    }
}
