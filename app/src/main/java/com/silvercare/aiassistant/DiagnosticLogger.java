package com.silvercare.aiassistant;

import android.content.Context;
import android.os.Build;
import android.os.SystemClock;
import android.util.Log;

import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

final class DiagnosticLogger {
    private static final String TAG = "SilverCareDiag";
    private static final int EXCERPT_LIMIT = 240;

    private static File latestFile;
    private static File sessionFile;
    private static String sessionId = "";

    private DiagnosticLogger() {
    }

    static synchronized void init(Context context) {
        try {
            File dir = new File(context.getExternalFilesDir(null), "diagnostics");
            if (!dir.exists() && !dir.mkdirs()) {
                Log.w(TAG, "Cannot create diagnostics directory: " + dir.getAbsolutePath());
                return;
            }
            sessionId = new SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(new Date());
            latestFile = new File(dir, "latest.jsonl");
            sessionFile = new File(dir, "session-" + sessionId + ".jsonl");
            writeRaw(latestFile, "", false);
            event("diagnostics_init", new JSONObject()
                .put("latest_path", latestFile.getAbsolutePath())
                .put("session_path", sessionFile.getAbsolutePath())
                .put("device", Build.MANUFACTURER + " " + Build.MODEL)
                .put("sdk", Build.VERSION.SDK_INT));
        } catch (Exception error) {
            Log.w(TAG, "Diagnostics init failed", error);
        }
    }

    static void event(String event) {
        event(event, null);
    }

    static void eventPairs(String event, Object... keyValues) {
        try {
            JSONObject data = new JSONObject();
            if (keyValues != null) {
                for (int index = 0; index + 1 < keyValues.length; index += 2) {
                    data.put(String.valueOf(keyValues[index]), keyValues[index + 1]);
                }
            }
            event(event, data);
        } catch (Exception error) {
            Log.w(TAG, "Diagnostics pair write failed", error);
        }
    }

    static synchronized void event(String event, JSONObject data) {
        if (latestFile == null || sessionFile == null) return;
        try {
            JSONObject row = new JSONObject()
                .put("ts", System.currentTimeMillis())
                .put("elapsed_realtime_ms", monotonicNow())
                .put("session", sessionId)
                .put("thread", Thread.currentThread().getName())
                .put("event", event == null ? "" : event);
            if (data != null) row.put("data", data);
            String line = row + "\n";
            writeRaw(latestFile, line, true);
            writeRaw(sessionFile, line, true);
            Log.i(TAG, line.trim());
        } catch (Exception error) {
            Log.w(TAG, "Diagnostics write failed", error);
        }
    }

    static long start() {
        return monotonicNow();
    }

    static long elapsed(long startMs) {
        return Math.max(0L, monotonicNow() - startMs);
    }

    static String latestPath() {
        return latestFile == null ? "" : latestFile.getAbsolutePath();
    }

    static String excerpt(String value) {
        if (value == null) return "";
        String clean = value
            .replace("\r", " ")
            .replace("\n", " ")
            .replaceAll("\\s+", " ")
            .trim();
        if (clean.length() <= EXCERPT_LIMIT) return clean;
        return clean.substring(0, EXCERPT_LIMIT) + "...";
    }

    private static void writeRaw(File file, String text, boolean append) throws Exception {
        try (FileOutputStream output = new FileOutputStream(file, append)) {
            output.write(text.getBytes(StandardCharsets.UTF_8));
        }
    }

    private static long monotonicNow() {
        try {
            return SystemClock.elapsedRealtime();
        } catch (RuntimeException | LinkageError error) {
            return System.currentTimeMillis();
        }
    }
}
