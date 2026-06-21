package com.silvercare.aiassistant;

import org.json.JSONObject;

final class MnnOfflineEngine implements OfflineInferenceEngine {
    private final SilverCareArtificialIntelligenceClient.SettingsProvider settings;
    private final OfflineModelManager modelManager;
    private final MnnRuntimeBridge bridge;

    MnnOfflineEngine(SilverCareArtificialIntelligenceClient.SettingsProvider settings) {
        this(settings, new OfflineModelManager(), new MnnNativeBridge());
    }

    MnnOfflineEngine(
        SilverCareArtificialIntelligenceClient.SettingsProvider settings,
        OfflineModelManager modelManager,
        MnnRuntimeBridge bridge
    ) {
        this.settings = settings;
        this.modelManager = modelManager;
        this.bridge = bridge;
    }

    @Override
    public String visionJson(String prompt, String imageDataUrl, String role) throws Exception {
        long started = DiagnosticLogger.start();
        DiagnosticLogger.event("mnn_vision_start", new JSONObject()
            .put("role", role)
            .put("prompt_chars", prompt == null ? 0 : prompt.length())
            .put("prompt", DiagnosticLogger.excerpt(prompt))
            .put("image_chars", imageDataUrl == null ? 0 : imageDataUrl.length()));
        OfflineModelStatus status = requireReady();
        try {
            String rawDetections = bridge.visionJson(status.modelDir, prompt, imageDataUrl, role);
            String interpreted = OfflineVisionInterpreter.interpret(prompt, rawDetections, role);
            DiagnosticLogger.event("mnn_vision_end", new JSONObject()
                .put("role", role)
                .put("elapsed_ms", DiagnosticLogger.elapsed(started))
                .put("raw_output_chars", rawDetections == null ? 0 : rawDetections.length())
                .put("raw_output", DiagnosticLogger.excerpt(rawDetections))
                .put("interpreted_chars", interpreted == null ? 0 : interpreted.length())
                .put("interpreted", DiagnosticLogger.excerpt(interpreted)));
            return interpreted;
        } catch (Exception error) {
            DiagnosticLogger.event("mnn_vision_error", new JSONObject()
                .put("role", role)
                .put("elapsed_ms", DiagnosticLogger.elapsed(started))
                .put("error", error.getClass().getSimpleName() + ": " + error.getMessage()));
            throw error;
        }
    }

    @Override
    public String textJson(String prompt, String role) throws Exception {
        return textJson(prompt, role, 0);
    }

    @Override
    public String textJson(String prompt, String role, int maxNewTokens) throws Exception {
        return textJson(prompt, role, maxNewTokens, null);
    }

    @Override
    public String textJson(String prompt, String role, int maxNewTokens, String endWith) throws Exception {
        long started = DiagnosticLogger.start();
        DiagnosticLogger.event("mnn_text_start", new JSONObject()
            .put("role", role)
            .put("max_new_tokens", maxNewTokens)
            .put("end_with", endWith == null ? "" : endWith)
            .put("prompt_chars", prompt == null ? 0 : prompt.length())
            .put("prompt", DiagnosticLogger.excerpt(prompt)));
        OfflineModelStatus status = requireReady();
        MnnLlmTuningProfile profile = MnnLlmTuningProfile.from(settings.mnnLlmTuningMode());
        String tuning = profile.nativeConfigJson(bridge.supportsSme2());
        try {
            String output = bridge.textJson(status.modelDir, prompt, role, tuning, maxNewTokens, endWith);
            DiagnosticLogger.event("mnn_text_end", new JSONObject()
                .put("role", role)
                .put("elapsed_ms", DiagnosticLogger.elapsed(started))
                .put("tuning", tuning)
                .put("max_new_tokens", maxNewTokens)
                .put("end_with", endWith == null ? "" : endWith)
                .put("output_chars", output == null ? 0 : output.length())
                .put("output", DiagnosticLogger.excerpt(output)));
            return output;
        } catch (Exception error) {
            DiagnosticLogger.event("mnn_text_error", new JSONObject()
                .put("role", role)
                .put("elapsed_ms", DiagnosticLogger.elapsed(started))
                .put("tuning", tuning)
                .put("max_new_tokens", maxNewTokens)
                .put("end_with", endWith == null ? "" : endWith)
                .put("error", error.getClass().getSimpleName() + ": " + error.getMessage()));
            throw error;
        }
    }

    @Override
    public String transcribe(String audioDataUrl) throws Exception {
        OfflineModelStatus status = requireReady();
        return bridge.transcribe(status.modelDir, audioDataUrl);
    }

    @Override
    public OfflineModelStatus status() {
        return modelManager.inspect(settings.offlineModelDir(), settings.textModel(), bridge.isAvailable());
    }

    private OfflineModelStatus requireReady() {
        OfflineModelStatus status = status();
        if (!status.ready()) {
            throw new IllegalStateException(status.shortText());
        }
        return status;
    }
}
