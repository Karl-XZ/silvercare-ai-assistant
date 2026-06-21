package com.silvercare.aiassistant;

final class LocalRuntimeBundlePlan {
    final boolean offlineModelsRequired;
    final boolean asrModelRequired;
    final boolean ttsModelRequired;
    final boolean mnnRuntimeMissing;
    final boolean ttsRuntimeMissing;
    final long downloadBytes;

    private LocalRuntimeBundlePlan(
        boolean offlineModelsRequired,
        boolean asrModelRequired,
        boolean ttsModelRequired,
        boolean mnnRuntimeMissing,
        boolean ttsRuntimeMissing,
        long downloadBytes
    ) {
        this.offlineModelsRequired = offlineModelsRequired;
        this.asrModelRequired = asrModelRequired;
        this.ttsModelRequired = ttsModelRequired;
        this.mnnRuntimeMissing = mnnRuntimeMissing;
        this.ttsRuntimeMissing = ttsRuntimeMissing;
        this.downloadBytes = downloadBytes;
    }

    static LocalRuntimeBundlePlan from(
        OfflineModelStatus offlineStatus,
        LocalAsrModelStatus asrStatus,
        LocalTtsModelStatus ttsStatus
    ) {
        boolean offlineRequired = offlineStatus == null
            || !offlineStatus.directoryReadable
            || !offlineStatus.textReady
            || !offlineStatus.yoloReady;
        boolean asrRequired = asrStatus == null || !asrStatus.ready;
        boolean ttsRequired = false;
        boolean mnnMissing = offlineStatus != null && !offlineStatus.nativeRuntimeAvailable;
        boolean ttsRuntimeMissing = false;

        long total = 0L;
        if (offlineRequired) total += OfflineModelDownloader.expectedTotalBytes();
        if (asrRequired) total += LocalAsrDownloader.expectedTotalBytes();
        return new LocalRuntimeBundlePlan(
            offlineRequired,
            asrRequired,
            ttsRequired,
            mnnMissing,
            ttsRuntimeMissing,
            total
        );
    }

    boolean hasDownloads() {
        return downloadBytes > 0L;
    }

    String downloadSummaryText() {
        if (!hasDownloads()) {
            return "未发现需要下载的本地模型文件。";
        }
        StringBuilder builder = new StringBuilder();
        if (offlineModelsRequired) {
            appendLine(builder, "AI 离线模型：Qwen3-4B-Instruct-2507-MNN + DAMO-YOLO，约 "
                + LocalTtsDownloader.humanBytes(OfflineModelDownloader.expectedTotalBytes()));
        }
        if (asrModelRequired) {
            appendLine(builder, "本地 ASR：应用内置中文语音识别模型，约 "
                + LocalTtsDownloader.humanBytes(LocalAsrDownloader.expectedTotalBytes()));
        }
        appendLine(builder, "合计需要准备：约 " + LocalTtsDownloader.humanBytes(downloadBytes));
        return builder.toString();
    }

    String runtimeWarningText() {
        StringBuilder builder = new StringBuilder();
        if (mnnRuntimeMissing) {
            appendLine(builder, "MNN Native Runtime 当前未加载；下载模型不能单独修复 native runtime 问题。");
        }
        if (ttsRuntimeMissing) {
            appendLine(builder, "本地 MNN TTS 当前为实验项；即使模型已下载，也不会作为主朗读方案。");
        }
        if (builder.length() == 0) return "";
        return builder.toString();
    }

    private static void appendLine(StringBuilder builder, String line) {
        if (builder.length() > 0) builder.append('\n');
        builder.append(line);
    }
}
