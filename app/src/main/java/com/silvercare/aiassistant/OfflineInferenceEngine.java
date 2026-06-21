package com.silvercare.aiassistant;

interface OfflineInferenceEngine {
    String visionJson(String prompt, String imageDataUrl, String role) throws Exception;
    String textJson(String prompt, String role) throws Exception;
    default String textJson(String prompt, String role, int maxNewTokens) throws Exception {
        return textJson(prompt, role);
    }
    default String textJson(String prompt, String role, int maxNewTokens, String endWith) throws Exception {
        return textJson(prompt, role, maxNewTokens);
    }
    String transcribe(String audioDataUrl) throws Exception;
    OfflineModelStatus status();
}
