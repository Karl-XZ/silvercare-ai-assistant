package com.silvercare.aiassistant;

import com.k2fsa.sherpa.onnx.OfflineModelConfig;
import com.k2fsa.sherpa.onnx.OfflineRecognizer;
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig;
import com.k2fsa.sherpa.onnx.OfflineSenseVoiceModelConfig;
import com.k2fsa.sherpa.onnx.OfflineStream;

import java.io.File;

/** Runs Alibaba SenseVoiceSmall INT8 fully on-device through sherpa-onnx. */
final class SenseVoiceLocalAsrEngine implements AutoCloseable {
    static final int SAMPLE_RATE = 16000;
    private final Object lock = new Object();
    private OfflineRecognizer recognizer;
    private String modelPath;

    String transcribePcm(File modelDir, byte[] pcm) {
        if (modelDir == null || !modelDir.isDirectory()) {
            throw new IllegalStateException("本地 SenseVoice 模型目录不存在。");
        }
        if (pcm == null || pcm.length < SAMPLE_RATE / 5) {
            throw new IllegalStateException("录音太短，请按住说完整问题。");
        }
        synchronized (lock) {
            OfflineStream stream = null;
            try {
                stream = recognizerFor(modelDir).createStream();
                stream.acceptWaveform(pcm16ToFloat(pcm), SAMPLE_RATE);
                recognizer.decode(stream);
                String transcript = normalizeTranscript(recognizer.getResult(stream).getText());
                if (transcript.isEmpty()) {
                    throw new IllegalStateException("本地 ASR 没有识别到清晰语音。");
                }
                return transcript;
            } finally {
                if (stream != null) stream.release();
            }
        }
    }

    private OfflineRecognizer recognizerFor(File modelDir) {
        String path = modelDir.getAbsolutePath();
        if (recognizer != null && path.equals(modelPath)) return recognizer;
        closeRecognizer();
        OfflineSenseVoiceModelConfig senseVoice = new OfflineSenseVoiceModelConfig();
        senseVoice.setModel(new File(modelDir, "model.int8.onnx").getAbsolutePath());
        senseVoice.setLanguage("zh");
        senseVoice.setUseInverseTextNormalization(true);
        OfflineModelConfig model = new OfflineModelConfig();
        model.setSenseVoice(senseVoice);
        model.setTokens(new File(modelDir, "tokens.txt").getAbsolutePath());
        model.setNumThreads(Math.max(1, Math.min(4, Runtime.getRuntime().availableProcessors() - 1)));
        model.setDebug(false);
        OfflineRecognizerConfig config = new OfflineRecognizerConfig();
        config.setModelConfig(model);
        // Passing null selects sherpa-onnx's newFromFile path, so the downloaded
        // model stays in app storage rather than being bundled into the APK assets.
        recognizer = new OfflineRecognizer(null, config);
        modelPath = path;
        return recognizer;
    }

    static String normalizeTranscript(String raw) {
        if (raw == null) return "";
        return raw.replaceAll("\\s+", " ").trim();
    }

    static float[] pcm16ToFloat(byte[] pcm) {
        int sampleCount = pcm == null ? 0 : pcm.length / 2;
        float[] samples = new float[sampleCount];
        for (int i = 0; i < sampleCount; i++) {
            int low = pcm[i * 2] & 0xff;
            int high = pcm[i * 2 + 1];
            samples[i] = (short) ((high << 8) | low) / 32768.0f;
        }
        return samples;
    }

    @Override public void close() { synchronized (lock) { closeRecognizer(); } }

    private void closeRecognizer() {
        if (recognizer != null) recognizer.release();
        recognizer = null;
        modelPath = null;
    }
}
