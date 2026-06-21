package com.silvercare.aiassistant;

interface SilverCareArtificialIntelligenceClient {
    SettingsProvider settings();

    String visionJson(String prompt, String imageDataUrl, String model) throws Exception;

    String textJson(String prompt, String model) throws Exception;

    default String textJson(String prompt, String model, int maxNewTokens) throws Exception {
        return textJson(prompt, model);
    }

    default String textJson(String prompt, String model, int maxNewTokens, String endWith) throws Exception {
        return textJson(prompt, model, maxNewTokens);
    }

    String transcribe(String audioDataUrl) throws Exception;

    interface SettingsProvider {
        String aiRuntimeMode();
        String offlineModelDir();
        String apiKey();
        String compatibleBaseUrl();
        String apiBaseUrl();
        String visionModel();
        String microModel();
        String textModel();
        String asrModel();
        String mnnLlmTuningMode();
        boolean voiceFirstEnabled();

        default boolean smartNavigationRefreshEnabled() {
            return false;
        }
    }
}
