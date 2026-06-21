package com.silvercare.aiassistant;

import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

final class MemoryStore {
    private static final String KEY_LOCATIONS = "locations_json";
    private static final String KEY_HISTORY = "history_json";
    private static final int MAX_HISTORY = 100;

    private final SharedPreferences preferences;

    MemoryStore(SharedPreferences preferences) {
        this.preferences = preferences;
    }

    synchronized void addLocation(String name, String description) {
        try {
            JSONObject locations = locations();
            locations.put(name, new JSONObject()
                .put("description", description == null ? "" : description)
                .put("timestamp", System.currentTimeMillis()));
            preferences.edit().putString(KEY_LOCATIONS, locations.toString()).apply();
        } catch (Exception ignored) {
        }
    }

    synchronized void logObject(String objectName, String locationTag, String scene) {
        if (objectName == null || objectName.trim().isEmpty()) return;
        try {
            JSONArray history = history();
            if (history.length() > 0) {
                JSONObject last = history.getJSONObject(history.length() - 1);
                long lastTime = last.optLong("timestamp", 0L);
                String lastName = last.optString("name", last.optString("object", ""));
                if (objectName.equals(lastName) && System.currentTimeMillis() - lastTime < 10000) {
                    return;
                }
            }

            history.put(new JSONObject()
                .put("name", objectName)
                .put("location", locationTag == null ? "" : locationTag)
                .put("scene", scene == null ? "" : scene)
                .put("timestamp", System.currentTimeMillis()));

            while (history.length() > MAX_HISTORY) {
                history.remove(0);
            }

            preferences.edit().putString(KEY_HISTORY, history.toString()).apply();
        } catch (Exception ignored) {
        }
    }

    synchronized String locationSummary() {
        try {
            JSONObject locations = locations();
            if (locations.length() == 0) return "还没有标记过的地点。";

            StringBuilder builder = new StringBuilder();
            JSONArray names = locations.names();
            if (names == null) return "还没有标记过的地点。";
            for (int i = 0; i < names.length(); i++) {
                String name = names.getString(i);
                JSONObject entry = locations.getJSONObject(name);
                if (builder.length() > 0) builder.append("，");
                builder.append("“").append(name).append("”：")
                    .append(entry.optString("description", ""));
            }
            return builder.toString();
        } catch (Exception e) {
            return "还没有标记过的地点。";
        }
    }

    synchronized String historyContext() {
        try {
            JSONArray history = history();
            if (history.length() == 0) return "还没有记录过物体历史。";

            int start = Math.max(0, history.length() - 30);
            StringBuilder builder = new StringBuilder();
            SimpleDateFormat format = new SimpleDateFormat("HH:mm", Locale.CHINA);
            for (int i = start; i < history.length(); i++) {
                JSONObject entry = history.getJSONObject(i);
                if (builder.length() > 0) builder.append("\n");
                String time = format.format(new Date(entry.optLong("timestamp", System.currentTimeMillis())));
                builder.append("[").append(time).append("] 看到 ")
                    .append(entry.optString("name", entry.optString("object", "")));
                String location = entry.optString("location", "");
                if (!location.isEmpty()) {
                    builder.append(" 在“").append(location).append("”");
                }
                String scene = entry.optString("scene", "");
                if (!scene.isEmpty()) {
                    builder.append("（").append(scene).append("）");
                }
            }
            return builder.toString();
        } catch (Exception e) {
            return "还没有记录过物体历史。";
        }
    }

    synchronized String findObjectLocation(String query) {
        String cleanQuery = query == null ? "" : query.trim();
        if (cleanQuery.isEmpty()) return "";
        try {
            JSONArray history = history();
            for (int i = history.length() - 1; i >= 0; i--) {
                JSONObject entry = history.getJSONObject(i);
                String name = entry.optString("name", entry.optString("object", ""));
                if (name.isEmpty()) continue;
                if (!cleanQuery.contains(name) && !name.contains(cleanQuery)) continue;

                String location = entry.optString("location", "");
                String scene = entry.optString("scene", "");
                if (!location.isEmpty() && !scene.isEmpty()) return name + "在" + location + "，" + scene;
                if (!location.isEmpty()) return name + "在" + location;
                if (!scene.isEmpty()) return name + "最近出现在：" + scene;
                return name + "最近被看见过，但没有明确位置。";
            }
        } catch (Exception ignored) {
        }
        return "";
    }

    private JSONObject locations() {
        try {
            return new JSONObject(preferences.getString(KEY_LOCATIONS, "{}"));
        } catch (Exception e) {
            return new JSONObject();
        }
    }

    private JSONArray history() {
        try {
            return new JSONArray(preferences.getString(KEY_HISTORY, "[]"));
        } catch (Exception e) {
            return new JSONArray();
        }
    }
}
