package com.silvercare.aiassistant;

import org.json.JSONObject;
import org.vosk.LibVosk;
import org.vosk.LogLevel;
import org.vosk.Model;
import org.vosk.Recognizer;

import java.io.File;

final class VoskLocalAsrEngine implements AutoCloseable {
    private static final float SAMPLE_RATE = 16000.0f;
    private static final int CHUNK_BYTES = 4096;

    private final Object lock = new Object();
    private Model model;
    private String modelPath;

    VoskLocalAsrEngine() {
        LibVosk.setLogLevel(LogLevel.WARNINGS);
    }

    String transcribePcm(File modelDir, byte[] pcm) throws Exception {
        if (modelDir == null || !modelDir.isDirectory()) {
            throw new IllegalStateException("本地 ASR 模型目录不存在。");
        }
        if (pcm == null || pcm.length < 1600) {
            throw new IllegalStateException("录音太短，请按住说完整问题。");
        }

        synchronized (lock) {
            Model activeModel = modelFor(modelDir);
            try (Recognizer recognizer = new Recognizer(activeModel, SAMPLE_RATE)) {
                recognizer.setWords(false);
                int offset = 0;
                while (offset < pcm.length) {
                    int length = Math.min(CHUNK_BYTES, pcm.length - offset);
                    byte[] chunk = new byte[length];
                    System.arraycopy(pcm, offset, chunk, 0, length);
                    recognizer.acceptWaveForm(chunk, length);
                    offset += length;
                }
                String transcript = parseTranscript(recognizer.getFinalResult());
                if (transcript.isEmpty()) {
                    throw new IllegalStateException("本地 ASR 没有识别到清晰语音。");
                }
                return transcript;
            }
        }
    }

    private Model modelFor(File modelDir) throws Exception {
        String path = modelDir.getAbsolutePath();
        if (model != null && path.equals(modelPath)) return model;

        closeModel();
        model = new Model(path);
        modelPath = path;
        return model;
    }

    static String parseTranscript(String resultJson) throws Exception {
        if (resultJson == null || resultJson.trim().isEmpty()) return "";
        String text = new JSONObject(resultJson).optString("text", "");
        return normalizeChineseTranscript(text);
    }

    static String normalizeChineseTranscript(String raw) {
        String text = raw == null ? "" : raw.trim().replaceAll("\\s+", " ");
        if (text.isEmpty()) return "";

        StringBuilder builder = new StringBuilder(text.length());
        for (int i = 0; i < text.length(); i += 1) {
            char current = text.charAt(i);
            if (Character.isWhitespace(current)) {
                char previous = previousNonSpace(text, i - 1);
                char next = nextNonSpace(text, i + 1);
                if (isCjk(previous) && isCjk(next)) continue;
                builder.append(' ');
                continue;
            }
            builder.append(current);
        }
        return builder.toString().trim();
    }

    private static char previousNonSpace(String text, int index) {
        for (int i = index; i >= 0; i -= 1) {
            char value = text.charAt(i);
            if (!Character.isWhitespace(value)) return value;
        }
        return 0;
    }

    private static char nextNonSpace(String text, int index) {
        for (int i = index; i < text.length(); i += 1) {
            char value = text.charAt(i);
            if (!Character.isWhitespace(value)) return value;
        }
        return 0;
    }

    private static boolean isCjk(char value) {
        Character.UnicodeBlock block = Character.UnicodeBlock.of(value);
        return block == Character.UnicodeBlock.CJK_UNIFIED_IDEOGRAPHS
            || block == Character.UnicodeBlock.CJK_UNIFIED_IDEOGRAPHS_EXTENSION_A
            || block == Character.UnicodeBlock.CJK_UNIFIED_IDEOGRAPHS_EXTENSION_B
            || block == Character.UnicodeBlock.CJK_COMPATIBILITY_IDEOGRAPHS;
    }

    @Override
    public void close() {
        synchronized (lock) {
            closeModel();
        }
    }

    private void closeModel() {
        if (model != null) {
            model.close();
            model = null;
            modelPath = null;
        }
    }
}
