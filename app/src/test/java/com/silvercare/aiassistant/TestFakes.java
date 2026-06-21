package com.silvercare.aiassistant;

import android.content.SharedPreferences;

import org.json.JSONObject;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Queue;
import java.util.Set;

final class TestFakes {
    private TestFakes() {
    }

    static final class Settings implements SilverCareArtificialIntelligenceClient.SettingsProvider {
        String apiKey = "test-key";
        String compatibleBaseUrl = "http://127.0.0.1";
        String apiBaseUrl = "http://127.0.0.1";
        String visionModel = "qwen3-vl-flash";
        String microModel = "qwen3-vl-flash";
        String textModel = "qwen-plus";
        String asrModel = "qwen3-asr-flash";
        String aiRuntimeMode = AiRuntimeMode.DASHSCOPE.value;
        String offlineModelDir = OfflineModelManager.DEFAULT_MODEL_DIR;
        String mnnLlmTuningMode = MnnLlmTuningProfile.DEFAULT.value;
        boolean voiceFirstEnabled = true;
        boolean smartNavigationRefreshEnabled = false;

        @Override
        public String aiRuntimeMode() {
            return aiRuntimeMode;
        }

        @Override
        public String offlineModelDir() {
            return offlineModelDir;
        }

        @Override
        public String apiKey() {
            return apiKey;
        }

        @Override
        public String compatibleBaseUrl() {
            return compatibleBaseUrl;
        }

        @Override
        public String apiBaseUrl() {
            return apiBaseUrl;
        }

        @Override
        public String visionModel() {
            return visionModel;
        }

        @Override
        public String microModel() {
            return microModel;
        }

        @Override
        public String textModel() {
            return textModel;
        }

        @Override
        public String asrModel() {
            return asrModel;
        }

        @Override
        public String mnnLlmTuningMode() {
            return mnnLlmTuningMode;
        }

        @Override
        public boolean voiceFirstEnabled() {
            return voiceFirstEnabled;
        }

        @Override
        public boolean smartNavigationRefreshEnabled() {
            return smartNavigationRefreshEnabled;
        }
    }

    static final class AiClient implements SilverCareArtificialIntelligenceClient {
        final Settings settings = new Settings();
        final Queue<String> visionResponses = new ArrayDeque<>();
        final Queue<String> textResponses = new ArrayDeque<>();
        String transcript = "";
        String lastVisionPrompt = "";
        String lastTextPrompt = "";
        String lastTextModel = "";
        int lastTextMaxNewTokens = 0;
        String lastTextEndWith = "";
        String lastImageDataUrl = "";
        String lastAudioDataUrl = "";

        @Override
        public SettingsProvider settings() {
            return settings;
        }

        @Override
        public String visionJson(String prompt, String imageDataUrl, String model) {
            lastVisionPrompt = prompt;
            lastImageDataUrl = imageDataUrl;
            return visionResponses.remove();
        }

        @Override
        public String textJson(String prompt, String model) {
            lastTextPrompt = prompt;
            lastTextModel = model;
            lastTextMaxNewTokens = 0;
            lastTextEndWith = "";
            return textResponses.remove();
        }

        @Override
        public String textJson(String prompt, String model, int maxNewTokens) {
            lastTextPrompt = prompt;
            lastTextModel = model;
            lastTextMaxNewTokens = maxNewTokens;
            lastTextEndWith = "";
            return textResponses.remove();
        }

        @Override
        public String textJson(String prompt, String model, int maxNewTokens, String endWith) {
            lastTextPrompt = prompt;
            lastTextModel = model;
            lastTextMaxNewTokens = maxNewTokens;
            lastTextEndWith = endWith == null ? "" : endWith;
            return textResponses.remove();
        }

        @Override
        public String transcribe(String audioDataUrl) {
            lastAudioDataUrl = audioDataUrl;
            return transcript;
        }
    }

    static final class Sink implements SilverCareProcessor.MessageSink {
        final List<JSONObject> messages = new ArrayList<>();

        @Override
        public void send(JSONObject data) {
            messages.add(data);
        }

        JSONObject firstOfType(String type) {
            for (JSONObject message : messages) {
                if (type.equals(message.optString("type"))) return message;
            }
            return null;
        }
    }

    static final class Preferences implements SharedPreferences {
        private final Map<String, Object> values = new HashMap<>();

        @Override
        public Map<String, ?> getAll() {
            return new HashMap<>(values);
        }

        @Override
        public String getString(String key, String defValue) {
            Object value = values.get(key);
            return value instanceof String ? (String) value : defValue;
        }

        @SuppressWarnings("unchecked")
        @Override
        public Set<String> getStringSet(String key, Set<String> defValues) {
            Object value = values.get(key);
            return value instanceof Set ? new HashSet<>((Set<String>) value) : defValues;
        }

        @Override
        public int getInt(String key, int defValue) {
            Object value = values.get(key);
            return value instanceof Integer ? (Integer) value : defValue;
        }

        @Override
        public long getLong(String key, long defValue) {
            Object value = values.get(key);
            return value instanceof Long ? (Long) value : defValue;
        }

        @Override
        public float getFloat(String key, float defValue) {
            Object value = values.get(key);
            return value instanceof Float ? (Float) value : defValue;
        }

        @Override
        public boolean getBoolean(String key, boolean defValue) {
            Object value = values.get(key);
            return value instanceof Boolean ? (Boolean) value : defValue;
        }

        @Override
        public boolean contains(String key) {
            return values.containsKey(key);
        }

        @Override
        public Editor edit() {
            return new Editor() {
                private final Map<String, Object> updates = new HashMap<>();
                private final Set<String> removals = new HashSet<>();
                private boolean clear = false;

                @Override
                public Editor putString(String key, String value) {
                    updates.put(key, value);
                    return this;
                }

                @Override
                public Editor putStringSet(String key, Set<String> value) {
                    updates.put(key, value == null ? null : new HashSet<>(value));
                    return this;
                }

                @Override
                public Editor putInt(String key, int value) {
                    updates.put(key, value);
                    return this;
                }

                @Override
                public Editor putLong(String key, long value) {
                    updates.put(key, value);
                    return this;
                }

                @Override
                public Editor putFloat(String key, float value) {
                    updates.put(key, value);
                    return this;
                }

                @Override
                public Editor putBoolean(String key, boolean value) {
                    updates.put(key, value);
                    return this;
                }

                @Override
                public Editor remove(String key) {
                    removals.add(key);
                    return this;
                }

                @Override
                public Editor clear() {
                    clear = true;
                    return this;
                }

                @Override
                public boolean commit() {
                    apply();
                    return true;
                }

                @Override
                public void apply() {
                    if (clear) values.clear();
                    for (String key : removals) values.remove(key);
                    values.putAll(updates);
                }
            };
        }

        @Override
        public void registerOnSharedPreferenceChangeListener(OnSharedPreferenceChangeListener listener) {
        }

        @Override
        public void unregisterOnSharedPreferenceChangeListener(OnSharedPreferenceChangeListener listener) {
        }
    }
}
