package com.silvercare.aiassistant;

import org.json.JSONObject;
import java.io.InputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/** Translates authored messages only. Never apply to saved user text or arbitrary model output. */
final class LanguageResources {
    private static final Map<String, Map<String, String>> CATALOGS = new HashMap<>();
    private static final Map<String, List<String>> KEYS = new HashMap<>();
    private LanguageResources() {}
    private static synchronized Map<String, String> catalog(String language) {
        if (CATALOGS.containsKey(language)) return CATALOGS.get(language);
        Map<String, String> entries = new HashMap<>();
        for (String domain : new String[]{"native", "backend"}) {
            String name = "/i18n/" + domain + "-" + language + ".json";
            try (InputStream stream = LanguageResources.class.getResourceAsStream(name)) {
                if (stream == null) continue;
                ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                byte[] buffer = new byte[4096];
                int count;
                while ((count = stream.read(buffer)) != -1) bytes.write(buffer, 0, count);
                JSONObject json = new JSONObject(new String(bytes.toByteArray(), StandardCharsets.UTF_8));
                Iterator<String> keys = json.keys();
                while (keys.hasNext()) { String key = keys.next(); entries.put(key, json.getString(key)); }
            } catch (Exception error) { throw new IllegalStateException("Invalid language catalog: " + name, error); }
        }
        List<String> keys = new ArrayList<>(entries.keySet());
        keys.remove("");
        keys.sort((a, b) -> Integer.compare(b.length(), a.length()));
        CATALOGS.put(language, Collections.unmodifiableMap(entries));
        KEYS.put(language, keys);
        return CATALOGS.get(language);
    }
    static String text(String language, String source) {
        if (source == null || "zh".equals(AppLanguage.normalize(language))) return source;
        String code = AppLanguage.normalize(language);
        Map<String, String> entries = catalog(code);
        String exact = entries.get(source);
        if (exact != null) return exact;
        // One pass over original text prevents translated Japanese from being translated again.
        StringBuilder result = new StringBuilder();
        for (int at = 0; at < source.length();) {
            String match = null;
            for (String key : KEYS.get(code)) {
                if (source.startsWith(key, at)) { match = key; break; }
            }
            if (match == null) result.append(source.charAt(at++));
            else { result.append(entries.get(match)); at += match.length(); }
        }
        return result.toString();
    }
}
