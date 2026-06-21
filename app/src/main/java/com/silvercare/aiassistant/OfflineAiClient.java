package com.silvercare.aiassistant;

final class OfflineAiClient implements SilverCareArtificialIntelligenceClient {
    static final String TEXT_MODEL_4B = "qwen3-4b-instruct-2507-mnn";
    static final String TEXT_MODEL_1_5B = "qwen2.5-1.5b-instruct-mnn";
    static final String TEXT_MODEL = TEXT_MODEL_4B;
    static final String DETECTOR_MODEL = "damo-yolo-mnn";
    static final String DEVICE_ASR_MODEL = "device-asr";

    private final SettingsProvider settings;
    private final OfflineInferenceEngine engine;

    OfflineAiClient(SettingsProvider settings) {
        this(settings, new MnnOfflineEngine(settings));
    }

    OfflineAiClient(SettingsProvider settings, OfflineInferenceEngine engine) {
        this.settings = settings;
        this.engine = engine;
    }

    @Override
    public SettingsProvider settings() {
        return settings;
    }

    @Override
    public String visionJson(String prompt, String imageDataUrl, String model) throws Exception {
        String role = DETECTOR_MODEL.equals(model) ? DETECTOR_MODEL : "detector";
        return engine.visionJson(prompt, imageDataUrl, role);
    }

    @Override
    public String textJson(String prompt, String model) throws Exception {
        String role = isOfflineTextModel(model) ? model : TEXT_MODEL;
        return engine.textJson(prompt, role);
    }

    @Override
    public String textJson(String prompt, String model, int maxNewTokens) throws Exception {
        String role = isOfflineTextModel(model) ? model : TEXT_MODEL;
        return engine.textJson(prompt, role, maxNewTokens);
    }

    @Override
    public String textJson(String prompt, String model, int maxNewTokens, String endWith) throws Exception {
        String role = isOfflineTextModel(model) ? model : TEXT_MODEL;
        return engine.textJson(prompt, role, maxNewTokens, endWith);
    }

    @Override
    public String transcribe(String audioDataUrl) throws Exception {
        return engine.transcribe(audioDataUrl);
    }

    OfflineModelStatus status() {
        return engine.status();
    }

    static boolean isOfflineTextModel(String model) {
        return TEXT_MODEL_4B.equals(model) || TEXT_MODEL_1_5B.equals(model);
    }

    static String textModelLabel(String model) {
        if (TEXT_MODEL_1_5B.equals(model)) return "Qwen2.5-1.5B-Instruct-MNN";
        return "Qwen3-4B-Instruct-2507-MNN";
    }
}
