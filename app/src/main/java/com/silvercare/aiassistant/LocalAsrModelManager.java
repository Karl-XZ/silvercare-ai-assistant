package com.silvercare.aiassistant;

import android.content.Context;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

final class LocalAsrModelManager {
    static final String ASR_DIR = "asr";
    static final String SENSEVOICE_MODEL_DIR = "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17";

    private static final String[] REQUIRED_FILES = new String[] {
        "model.int8.onnx",
        "tokens.txt"
    };

    LocalAsrModelStatus inspect(Context context) {
        return inspect(asrRoot(context));
    }

    LocalAsrModelStatus inspect(File modelRoot) {
        File root = modelRoot == null ? null : modelRoot;
        File modelDir = root == null ? null : new File(root, SENSEVOICE_MODEL_DIR);
        boolean directoryReadable = root != null && root.isDirectory() && root.canRead();

        List<String> missing = new ArrayList<>();
        if (!directoryReadable) {
            missing.add("ASR 模型目录不可读");
        }
        if (modelDir == null || !modelDir.isDirectory() || !modelDir.canRead()) {
            missing.add(SENSEVOICE_MODEL_DIR);
        } else {
            for (String required : REQUIRED_FILES) {
                File file = new File(modelDir, required);
                if (!file.isFile() || !file.canRead()) {
                    missing.add(required);
                }
            }
        }

        return new LocalAsrModelStatus(root, modelDir, directoryReadable, missing.isEmpty(), missing);
    }

    static File asrRoot(Context context) {
        return new File(OfflineModelDownloader.automaticModelDir(context), ASR_DIR);
    }
}
