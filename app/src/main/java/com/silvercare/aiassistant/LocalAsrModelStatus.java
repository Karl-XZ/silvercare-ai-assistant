package com.silvercare.aiassistant;

import java.io.File;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

final class LocalAsrModelStatus {
    final File modelRoot;
    final File modelDir;
    final boolean directoryReadable;
    final boolean ready;
    final List<String> missing;

    LocalAsrModelStatus(
        File modelRoot,
        File modelDir,
        boolean directoryReadable,
        boolean ready,
        List<String> missing
    ) {
        this.modelRoot = modelRoot;
        this.modelDir = modelDir;
        this.directoryReadable = directoryReadable;
        this.ready = ready;
        this.missing = Collections.unmodifiableList(new ArrayList<>(missing));
    }

    String shortText() {
        if (ready) return "本地语音识别模型已就绪";
        if (missing.isEmpty()) return "本地语音识别模型未就绪";
        return "本地语音识别模型未就绪：" + String.join("、", missing);
    }

    String detailText() {
        StringBuilder builder = new StringBuilder();
        builder.append(shortText())
            .append("\n\n模型目录：").append(pathOf(modelDir))
            .append("\n模型来源：Vosk 中文小模型 ")
            .append(LocalAsrModelManager.VOSK_CN_MODEL_DIR)
            .append("\n下载大小：约 ")
            .append(LocalAsrDownloader.humanBytes(LocalAsrDownloader.VOSK_CN_ZIP_BYTES))
            .append("\n用途：端侧离线语音转文字，录音不会上传。");
        return builder.toString();
    }

    private static String pathOf(File file) {
        return file == null ? "未设置" : file.getAbsolutePath();
    }
}
