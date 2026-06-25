package com.silvercare.aiassistant;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.OutputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

final class DashScopeClient implements SilverCareArtificialIntelligenceClient {
    private static final String ASR_CONTEXT_PROMPT =
        "银龄智护 盲人导航助手。常见词：找门、找水杯、按电梯上行按钮、巡路、障碍物、跌倒、厨房、办公室。";

    private final SilverCareArtificialIntelligenceClient.SettingsProvider settings;
    private final JsonTransport transport;

    DashScopeClient(SilverCareArtificialIntelligenceClient.SettingsProvider settings) {
        this(settings, new HttpJsonTransport());
    }

    DashScopeClient(SilverCareArtificialIntelligenceClient.SettingsProvider settings, JsonTransport transport) {
        this.settings = settings;
        this.transport = transport;
    }

    @Override
    public SilverCareArtificialIntelligenceClient.SettingsProvider settings() {
        return settings;
    }

    @Override
    public String visionJson(String prompt, String imageDataUrl, String model) throws Exception {
        long diagnosticStarted = DiagnosticLogger.start();
        DiagnosticLogger.event("dashscope_vision_start", new JSONObject()
            .put("model", model)
            .put("prompt_chars", prompt == null ? 0 : prompt.length())
            .put("prompt", DiagnosticLogger.excerpt(prompt))
            .put("image_chars", imageDataUrl == null ? 0 : imageDataUrl.length()));
        JSONArray content = new JSONArray()
            .put(new JSONObject().put("type", "text").put("text", prompt))
            .put(new JSONObject()
                .put("type", "image_url")
                .put("image_url", new JSONObject().put("url", imageDataUrl)));
        try {
            String output = chat(content, model, true, 0.1);
            DiagnosticLogger.event("dashscope_vision_end", new JSONObject()
                .put("elapsed_ms", DiagnosticLogger.elapsed(diagnosticStarted))
                .put("output_chars", output == null ? 0 : output.length())
                .put("output", DiagnosticLogger.excerpt(output)));
            return output;
        } catch (Exception error) {
            DiagnosticLogger.event("dashscope_vision_error", new JSONObject()
                .put("elapsed_ms", DiagnosticLogger.elapsed(diagnosticStarted))
                .put("error", error.getClass().getSimpleName())
                .put("message", DiagnosticLogger.excerpt(error.getMessage())));
            throw error;
        }
    }

    @Override
    public String textJson(String prompt, String model) throws Exception {
        long diagnosticStarted = DiagnosticLogger.start();
        DiagnosticLogger.event("dashscope_text_start", new JSONObject()
            .put("model", model)
            .put("prompt_chars", prompt == null ? 0 : prompt.length())
            .put("prompt", DiagnosticLogger.excerpt(prompt)));
        JSONArray content = new JSONArray()
            .put(new JSONObject().put("type", "text").put("text", prompt));
        try {
            String output = chat(content, model, false, 0.2);
            DiagnosticLogger.event("dashscope_text_end", new JSONObject()
                .put("elapsed_ms", DiagnosticLogger.elapsed(diagnosticStarted))
                .put("output_chars", output == null ? 0 : output.length())
                .put("output", DiagnosticLogger.excerpt(output)));
            return output;
        } catch (Exception error) {
            DiagnosticLogger.event("dashscope_text_error", new JSONObject()
                .put("elapsed_ms", DiagnosticLogger.elapsed(diagnosticStarted))
                .put("error", error.getClass().getSimpleName())
                .put("message", DiagnosticLogger.excerpt(error.getMessage())));
            throw error;
        }
    }

    @Override
    public String transcribe(String audioDataUrl) throws Exception {
        long diagnosticStarted = DiagnosticLogger.start();
        DiagnosticLogger.event("dashscope_transcribe_start", new JSONObject()
            .put("model", settings.asrModel())
            .put("audio_chars", audioDataUrl == null ? 0 : audioDataUrl.length()));
        JSONObject payload = new JSONObject()
            .put("model", settings.asrModel())
            .put("input", new JSONObject()
                .put("messages", new JSONArray()
                    .put(new JSONObject()
                    .put("role", "system")
                    .put("content", new JSONArray()
                            .put(new JSONObject().put("text", ASR_CONTEXT_PROMPT))))
                    .put(new JSONObject()
                        .put("role", "user")
                        .put("content", new JSONArray()
                            .put(new JSONObject().put("audio", audioDataUrl))))))
            .put("parameters", new JSONObject()
                .put("asr_options", new JSONObject()
                    .put("language", "zh")
                    .put("enable_itn", false)));

        JSONObject response = postJson(settings.apiBaseUrl() + "/services/aigc/multimodal-generation/generation", payload);
        JSONArray content = response.getJSONObject("output")
            .getJSONArray("choices")
            .getJSONObject(0)
            .getJSONObject("message")
            .getJSONArray("content");
        String output = transcriptFromContent(content);
        DiagnosticLogger.event("dashscope_transcribe_end", new JSONObject()
            .put("elapsed_ms", DiagnosticLogger.elapsed(diagnosticStarted))
            .put("text", DiagnosticLogger.excerpt(output)));
        return output;
    }

    private static String transcriptFromContent(JSONArray content) {
        if (content == null || content.length() == 0) return "";
        for (int index = 0; index < content.length(); index += 1) {
            JSONObject item = content.optJSONObject(index);
            if (item == null) continue;
            String text = item.optString("text", "").trim();
            if (text.isEmpty()) text = item.optString("transcript", "").trim();
            if (text.isEmpty()) text = item.optString("sentence", "").trim();
            text = stripAsrContextPromptLeak(text);
            if (text.isEmpty()) continue;
            return text;
        }
        return "";
    }

    private static String stripAsrContextPromptLeak(String text) {
        String clean = text == null ? "" : text.trim();
        if (clean.isEmpty()) return "";
        clean = clean.replace(ASR_CONTEXT_PROMPT, " ");

        int start = clean.indexOf("银龄智护");
        int common = clean.indexOf("常见词");
        if (start < 0 && common >= 0) start = common;
        if (start >= 0 && common >= start && clean.indexOf("找水杯", common) >= 0) {
            int end = contextPromptEnd(clean, common);
            if (end >= 0) {
                clean = (clean.substring(0, start) + " " + clean.substring(end)).trim();
            }
        }

        String normalized = clean.replace(" ", "");
        if (normalized.contains("银龄智护盲人导航助手")
            || normalized.contains("常见词：找门")
            || normalized.contains("找水杯、按电梯上行按钮、巡路")) {
            return "";
        }
        return clean.replaceAll("\\s+", " ").trim();
    }

    private static int contextPromptEnd(String text, int from) {
        String[] endings = {"办公室。", "办公室.", "办公室"};
        for (String ending : endings) {
            int index = text.indexOf(ending, from);
            if (index >= 0) return index + ending.length();
        }
        return -1;
    }

    public String synthesizeSpeechUrl(String text) throws Exception {
        String clean = text == null ? "" : text.trim();
        if (clean.isEmpty()) return "";
        long diagnosticStarted = DiagnosticLogger.start();
        DiagnosticLogger.event("dashscope_tts_start", new JSONObject()
            .put("chars", clean.length())
            .put("text", DiagnosticLogger.excerpt(clean)));

        JSONObject payload = new JSONObject()
            .put("model", "qwen3-tts-flash")
            .put("input", new JSONObject()
                .put("text", clean)
                .put("voice", "Cherry")
                .put("language_type", "Chinese"));

        JSONObject response = postJson(settings.apiBaseUrl() + "/services/aigc/multimodal-generation/generation", payload);
        JSONObject output = response.optJSONObject("output");
        if (output == null) {
            throw new IllegalStateException("DashScope TTS 返回缺少 output。");
        }
        JSONObject audio = output.optJSONObject("audio");
        String url = audio == null ? "" : audio.optString("url", "");
        if (url == null || url.trim().isEmpty()) {
            throw new IllegalStateException("DashScope TTS 返回缺少音频 URL。");
        }
        DiagnosticLogger.event("dashscope_tts_end", new JSONObject()
            .put("elapsed_ms", DiagnosticLogger.elapsed(diagnosticStarted))
            .put("has_url", true));
        return url.trim();
    }

    private String chat(JSONArray content, String model, boolean jsonMode, double temperature) throws Exception {
        JSONObject payload = new JSONObject()
            .put("model", model)
            .put("messages", new JSONArray().put(new JSONObject()
                .put("role", "user")
                .put("content", content)))
            .put("stream", false)
            .put("temperature", temperature);

        if (jsonMode) {
            payload.put("response_format", new JSONObject().put("type", "json_object"));
        }

        JSONObject response = postJson(settings.compatibleBaseUrl() + "/chat/completions", payload);
        return response.getJSONArray("choices")
            .getJSONObject(0)
            .getJSONObject("message")
            .optString("content", "");
    }

    private JSONObject postJson(String endpoint, JSONObject payload) throws Exception {
        String key = settings.apiKey();
        if (key == null || key.trim().isEmpty()) {
            throw new IllegalStateException("请先在设置里填写 DashScope Key。");
        }

        long diagnosticStarted = DiagnosticLogger.start();
        DiagnosticLogger.event("dashscope_http_start", new JSONObject()
            .put("endpoint", DiagnosticLogger.excerpt(endpoint))
            .put("payload_keys", payload == null ? 0 : payload.length()));
        try {
            JSONObject response = transport.postJson(endpoint, payload, key.trim());
            DiagnosticLogger.event("dashscope_http_end", new JSONObject()
                .put("elapsed_ms", DiagnosticLogger.elapsed(diagnosticStarted))
                .put("response_keys", response == null ? 0 : response.length()));
            return response;
        } catch (Exception error) {
            DiagnosticLogger.event("dashscope_http_error", new JSONObject()
                .put("elapsed_ms", DiagnosticLogger.elapsed(diagnosticStarted))
                .put("error", error.getClass().getSimpleName())
                .put("message", DiagnosticLogger.excerpt(error.getMessage())));
            throw error;
        }
    }

    interface JsonTransport {
        JSONObject postJson(String endpoint, JSONObject payload, String apiKey) throws Exception;
    }

    private static final class HttpJsonTransport implements JsonTransport {
        @Override
        public JSONObject postJson(String endpoint, JSONObject payload, String apiKey) throws Exception {
            HttpURLConnection connection = (HttpURLConnection) new URL(endpoint).openConnection();
            connection.setRequestMethod("POST");
            connection.setConnectTimeout(20000);
            connection.setReadTimeout(60000);
            connection.setDoOutput(true);
            connection.setRequestProperty("Authorization", "Bearer " + apiKey);
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8");

            byte[] body = payload.toString().getBytes(StandardCharsets.UTF_8);
            try (OutputStream output = connection.getOutputStream()) {
                output.write(body);
            }

            int code = connection.getResponseCode();
            BufferedReader reader = new BufferedReader(new InputStreamReader(
                code >= 200 && code < 300 ? connection.getInputStream() : connection.getErrorStream(),
                StandardCharsets.UTF_8
            ));

            StringBuilder response = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                response.append(line);
            }

            if (code < 200 || code >= 300) {
                throw new IllegalStateException("DashScope 请求失败：" + code + " " + response);
            }

            return new JSONObject(response.toString());
        }
    }
}
