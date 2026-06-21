package com.silvercare.aiassistant;

import android.content.Context;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

final class LocalAsrModelManager {
    static final String ASR_DIR = "asr";
    static final String VOSK_CN_MODEL_DIR = "vosk-model-small-cn-0.22";

    private static final String[] REQUIRED_FILES = new String[] {
        "am/final.mdl",
        "conf/model.conf",
        "graph/HCLr.fst",
        "graph/Gr.fst",
        "ivector/final.ie"
    };

    LocalAsrModelStatus inspect(Context context) {
        return inspect(asrRoot(context));
    }

    LocalAsrModelStatus inspect(File modelRoot) {
        File root = modelRoot == null ? null : modelRoot;
        File modelDir = root == null ? null : new File(root, VOSK_CN_MODEL_DIR);
        boolean directoryReadable = root != null && root.isDirectory() && root.canRead();

        List<String> missing = new ArrayList<>();
        if (!directoryReadable) {
            missing.add("ASR 模型目录不可读");
        }
        if (modelDir == null || !modelDir.isDirectory() || !modelDir.canRead()) {
            missing.add(VOSK_CN_MODEL_DIR);
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
