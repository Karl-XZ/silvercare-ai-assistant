package com.silvercare.aiassistant;

import android.content.Context;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

final class LocalTtsModelManager {
    static final String TTS_DIR = "tts";
    static final String MNN_TTS_DIR = "bert-vits2-mnn";

    LocalTtsModelStatus inspect(Context context, boolean runtimeAvailable, String runtimeSummary) {
        return inspect(ttsRoot(context), runtimeAvailable, runtimeSummary);
    }

    LocalTtsModelStatus inspect(File modelRoot, boolean runtimeAvailable, String runtimeSummary) {
        return inspect(modelRoot, runtimeAvailable, runtimeSummary, LocalTtsDownloader.MNN_TTS_FILES);
    }

    LocalTtsModelStatus inspect(
        File modelRoot,
        boolean runtimeAvailable,
        String runtimeSummary,
        LocalTtsDownloader.DownloadFile[] requiredFiles
    ) {
        File root = modelRoot == null ? null : modelRoot;
        File modelDir = root == null ? null : new File(root, MNN_TTS_DIR);
        boolean directoryReadable = root != null && root.isDirectory() && root.canRead();

        List<String> missing = new ArrayList<>();
        if (!directoryReadable) {
            missing.add("TTS 模型目录不可读");
        }
        if (modelDir == null || !modelDir.isDirectory() || !modelDir.canRead()) {
            missing.add(MNN_TTS_DIR);
        } else {
            for (LocalTtsDownloader.DownloadFile item : requiredFiles) {
                File file = new File(modelDir, item.relativePath);
                if (!file.isFile() || !file.canRead() || file.length() != item.expectedBytes) {
                    missing.add(item.relativePath);
                }
            }
        }
        boolean modelReady = missing.isEmpty();
        return new LocalTtsModelStatus(
            root,
            modelDir,
            runtimeAvailable,
            runtimeSummary,
            directoryReadable,
            modelReady,
            missing
        );
    }

    static File ttsRoot(Context context) {
        return new File(OfflineModelDownloader.automaticModelDir(context), TTS_DIR);
    }
}
