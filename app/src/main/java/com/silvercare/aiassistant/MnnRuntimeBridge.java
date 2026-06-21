package com.silvercare.aiassistant;

interface MnnRuntimeBridge {
    boolean isAvailable();
    boolean supportsSme2();
    String runtimeSummary();
    String visionJson(String modelDir, String prompt, String imageDataUrl, String role) throws Exception;
    String textJson(String modelDir, String prompt, String role, String tuningConfigJson) throws Exception;
    default String textJson(
        String modelDir,
        String prompt,
        String role,
        String tuningConfigJson,
        int maxNewTokens
    ) throws Exception {
        return textJson(modelDir, prompt, role, tuningConfigJson);
    }
    default String textJson(
        String modelDir,
        String prompt,
        String role,
        String tuningConfigJson,
        int maxNewTokens,
        String endWith
    ) throws Exception {
        return textJson(modelDir, prompt, role, tuningConfigJson, maxNewTokens);
    }
    String transcribe(String modelDir, String audioDataUrl) throws Exception;
}
