package com.silvercare.aiassistant;

import org.json.JSONObject;

final class LocalAsrTextCorrector {
    private static final int MAX_CORRECTED_CHARS = 80;

    private LocalAsrTextCorrector() {
    }

    static String prompt(String rawTranscript) {
        return """
            你是银龄智护的本地语音识别校对器。
            下面的文本来自手机端本地 ASR，可能有错字、同音字、漏字、误断句或多余空格。

            校对目标：
            - 还原用户真正想说的短句。
            - 优先保留原意，不要扩写，不要替用户新增没有说过的需求。
            - 如果用户像是在找东西、问路、开启引导、关闭引导、停止任务、询问设置，请把命令校正成自然中文。
            - 如果不确定，只做最小修改。
            - 输出文本要能直接作为用户字幕和后续 AI 输入。

            常见纠错示例：
            - “帮我找到我的晚” -> “帮我找到我的碗”
            - “关闭影导” -> “关闭引导”
            - “找一下手几” -> “找一下手机”
            - “亭子”在导航语境中可能是“停止”

            原始 ASR 文本：“%s”

            只输出一个 JSON 对象，不要 Markdown：
            {"corrected_text":"校对后的用户原话","changed":true,"reason":"中文简短原因"}
            /no_think
            """.formatted(rawTranscript == null ? "" : rawTranscript.trim());
    }

    static String correctedText(String rawModelResponse, String fallbackTranscript) {
        String fallback = sanitize(fallbackTranscript);
        try {
            JSONObject json = parseJsonObject(rawModelResponse);
            String corrected = sanitize(json.optString("corrected_text", ""));
            if (corrected.isEmpty()) corrected = sanitize(json.optString("text", ""));
            if (corrected.isEmpty()) return fallback;
            if (corrected.length() > MAX_CORRECTED_CHARS) return fallback;
            return corrected;
        } catch (Exception ignored) {
            return fallback;
        }
    }

    static String fastCorrect(String value) {
        String text = sanitize(value);
        if (text.isEmpty()) return "";
        return text
            .replace("我的晚", "我的碗")
            .replace("到我的晚", "到我的碗")
            .replace("找晚", "找碗")
            .replace("找一下手几", "找一下手机")
            .replace("手几", "手机")
            .replace("关闭影导", "关闭引导")
            .replace("影导", "引导");
    }

    static String sanitize(String value) {
        if (value == null) return "";
        return value
            .replace("```json", "")
            .replace("```", "")
            .replace("\n", " ")
            .replace("\r", " ")
            .replaceAll("\\s+", " ")
            .trim();
    }

    private static JSONObject parseJsonObject(String text) throws Exception {
        String clean = sanitize(text);
        if (clean.startsWith("{")) return new JSONObject(clean);

        int start = clean.indexOf('{');
        if (start < 0) throw new IllegalArgumentException("未找到 JSON 对象");
        String json = firstCompleteJson(clean, start);
        if (json == null) throw new IllegalArgumentException("JSON 对象不完整");
        return new JSONObject(json);
    }

    private static String firstCompleteJson(String text, int start) {
        int depth = 0;
        boolean inString = false;
        boolean escaped = false;
        for (int index = start; index < text.length(); index += 1) {
            char ch = text.charAt(index);
            if (inString) {
                if (escaped) {
                    escaped = false;
                } else if (ch == '\\') {
                    escaped = true;
                } else if (ch == '"') {
                    inString = false;
                }
                continue;
            }
            if (ch == '"') {
                inString = true;
            } else if (ch == '{') {
                depth += 1;
            } else if (ch == '}') {
                depth -= 1;
                if (depth == 0) return text.substring(start, index + 1);
                if (depth < 0) return null;
            }
        }
        return null;
    }
}
