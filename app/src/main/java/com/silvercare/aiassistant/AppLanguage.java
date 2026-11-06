package com.silvercare.aiassistant;

import java.util.Locale;

/** Single language policy shared by UI, speech recognition and synthesis. */
final class AppLanguage {
    private AppLanguage() {}
    static String normalize(String value) {
        String code = value == null ? "" : value.trim().toLowerCase(Locale.ROOT).replace('_', '-');
        if (code.equals("en") || code.startsWith("en-")) return "en";
        if (code.equals("ja") || code.startsWith("ja-")) return "ja";
        return "zh";
    }
    static String asrCode(String value) { return normalize(value); }
    static String bcp47(String value) {
        return switch (normalize(value)) { case "en" -> "en-US"; case "ja" -> "ja-JP"; default -> "zh-CN"; };
    }
    static Locale locale(String value) { return Locale.forLanguageTag(bcp47(value)); }
    static String cloudLanguage(String value) {
        return switch (normalize(value)) { case "en" -> "English"; case "ja" -> "Japanese"; default -> "Chinese"; };
    }
    // Cherry supports all three languages in qwen3-tts-flash; language_type controls pronunciation.
    static String cloudVoice(String value) { return "Cherry"; }
}
