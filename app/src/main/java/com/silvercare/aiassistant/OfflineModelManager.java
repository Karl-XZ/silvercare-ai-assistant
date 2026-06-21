package com.silvercare.aiassistant;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

final class OfflineModelManager {
    static final String DEFAULT_MODEL_DIR = "/sdcard/Download/multimodal_care_models";

    private static final String[] TEXT_CONFIG_CANDIDATES_4B = new String[] {
        "Qwen3-4B-Instruct-2507-MNN/config.json",
        "qwen3-4b-instruct-2507-mnn/config.json",
        "qwen-text-4b/config.json",
        "text-4b/config.json"
    };

    private static final String[] TEXT_CONFIG_CANDIDATES_1_5B = new String[] {
        "Qwen2.5-1.5B-Instruct-MNN/config.json",
        "qwen2.5-1.5b-instruct-mnn/config.json",
        "qwen2_5-1_5b-instruct-mnn/config.json",
        "qwen-text-1.5b/config.json",
        "text-1.5b/config.json"
    };

    private static final String[] YOLO_MODEL_CANDIDATES = new String[] {
        "damo-yolo.mnn",
        "damo_yolo.mnn",
        "DAMO-YOLO.mnn",
        "yolo.mnn",
        "detector/damo-yolo.mnn",
        "detector/damo_yolo.mnn"
    };

    OfflineModelStatus inspect(String modelDir, boolean nativeRuntimeAvailable) {
        return inspect(modelDir, OfflineAiClient.TEXT_MODEL, nativeRuntimeAvailable);
    }

    OfflineModelStatus inspect(String modelDir, String textModel, boolean nativeRuntimeAvailable) {
        String cleanDir = cleanModelDir(modelDir);
        String cleanTextModel = cleanTextModel(textModel);
        File root = new File(cleanDir);
        boolean directoryReadable = root.isDirectory() && root.canRead();

        File textConfig = directoryReadable ? findExisting(root, textConfigCandidates(cleanTextModel)) : null;
        File yoloModel = directoryReadable ? findExisting(root, YOLO_MODEL_CANDIDATES) : null;

        List<String> missing = new ArrayList<>();
        if (!nativeRuntimeAvailable) missing.add("MNN Native Runtime");
        if (!directoryReadable) missing.add("模型目录不可读");
        if (textConfig == null) missing.add(OfflineAiClient.textModelLabel(cleanTextModel) + "/config.json");
        if (yoloModel == null) missing.add("DAMO-YOLO .mnn");

        return new OfflineModelStatus(
            cleanDir,
            cleanTextModel,
            textConfig,
            yoloModel,
            nativeRuntimeAvailable,
            directoryReadable,
            textConfig != null,
            yoloModel != null,
            missing
        );
    }

    private static String cleanModelDir(String modelDir) {
        String value = modelDir == null ? "" : modelDir.trim();
        return value.isEmpty() ? DEFAULT_MODEL_DIR : value;
    }

    private static String cleanTextModel(String textModel) {
        return OfflineAiClient.isOfflineTextModel(textModel) ? textModel : OfflineAiClient.TEXT_MODEL;
    }

    private static String[] textConfigCandidates(String textModel) {
        if (OfflineAiClient.TEXT_MODEL_1_5B.equals(textModel)) {
            return TEXT_CONFIG_CANDIDATES_1_5B;
        }
        return TEXT_CONFIG_CANDIDATES_4B;
    }

    private static File findExisting(File root, String[] candidates) {
        for (String candidate : candidates) {
            File file = new File(root, candidate);
            if (file.isFile() && file.canRead()) {
                return file;
            }
        }
        return null;
    }
}
