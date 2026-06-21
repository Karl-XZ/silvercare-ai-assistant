package com.silvercare.aiassistant;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.Process;
import android.os.SystemClock;
import android.util.Base64;
import android.util.Log;

import androidx.annotation.Nullable;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileWriter;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;

public class LocalModelBenchmarkActivity extends Activity {
    private static final String TAG = "LocalModelBenchmark";
    private static final String EXTRA_TEST = "benchmark_test";
    private static final String EXTRA_TIMEOUT_MS = "timeout_ms";
    private static final long DEFAULT_TIMEOUT_MS = 120_000L;
    private static final boolean LOCAL_MNN_TTS_VOICE_QUALITY_ENABLED = false;

    private final AtomicBoolean finished = new AtomicBoolean(false);

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        DiagnosticLogger.init(this);
        Intent intent = getIntent();
        String test = clean(intent.getStringExtra(EXTRA_TEST));
        if (test.isEmpty()) test = "status";
        long timeoutMs = intent.getLongExtra(EXTRA_TIMEOUT_MS, defaultTimeoutFor(test));
        String finalTest = test;

        Handler handler = new Handler(Looper.getMainLooper());
        handler.postDelayed(() -> {
            if (!finished.compareAndSet(false, true)) return;
            JSONObject timeout = baseReport(finalTest);
            putQuietly(timeout, "success", false);
            putQuietly(timeout, "timeout", true);
            putQuietly(timeout, "error", "benchmark timeout after " + timeoutMs + " ms");
            writeAndExit(timeout);
        }, timeoutMs);

        Thread worker = new Thread(() -> {
            JSONObject report;
            try {
                report = runBenchmark(finalTest);
            } catch (Throwable throwable) {
                report = baseReport(finalTest);
                putQuietly(report, "success", false);
                putQuietly(report, "error", readableThrowable(throwable));
            }
            if (finished.compareAndSet(false, true)) {
                writeAndExit(report);
            }
        }, "local-model-benchmark");
        worker.start();
    }

    private JSONObject runBenchmark(String test) throws Exception {
        return switch (test) {
            case "asr" -> benchmarkAsr();
            case "vision" -> benchmarkVision();
            case "text" -> benchmarkText();
            case "text_suite" -> benchmarkTextSuite();
            case "text_inquiry" -> benchmarkTextInquiry();
            case "tts" -> benchmarkTts();
            case "scenario" -> benchmarkManualScenario();
            default -> benchmarkStatus();
        };
    }

    private JSONObject benchmarkStatus() throws Exception {
        JSONObject report = baseReport("status");
        MnnNativeBridge mnn = new MnnNativeBridge();
        OfflineModelStatus offlineStatus = new OfflineModelManager().inspect(
            modelRoot().getAbsolutePath(),
            OfflineAiClient.TEXT_MODEL_4B,
            mnn.isAvailable()
        );
        LocalAsrModelStatus asrStatus = new LocalAsrModelManager().inspect(this);
        LocalTtsModelStatus ttsStatus = new LocalTtsModelManager().inspect(
            this,
            false,
            "本地 MNN TTS 可生成音频，但真实试听不可懂，已停用主朗读。"
        );

        putQuietly(report, "success", true);
        putQuietly(report, "model_root", modelRoot().getAbsolutePath());
        putQuietly(report, "mnn_available", mnn.isAvailable());
        putQuietly(report, "mnn_summary", mnn.runtimeSummary());
        putQuietly(report, "mnn_sme2_supported", mnn.supportsSme2());
        putQuietly(report, "offline_ready", offlineStatus.ready());
        putQuietly(report, "offline_status", offlineStatus.detailText());
        putQuietly(report, "local_asr_ready", asrStatus.ready);
        putQuietly(report, "local_asr_status", asrStatus.detailText());
        putQuietly(report, "local_tts_ready", LOCAL_MNN_TTS_VOICE_QUALITY_ENABLED && ttsStatus.ready);
        putQuietly(report, "local_tts_model_ready", ttsStatus.modelReady);
        putQuietly(report, "local_tts_runtime_available", ttsStatus.runtimeAvailable);
        putQuietly(report, "local_tts_voice_quality_passed", LOCAL_MNN_TTS_VOICE_QUALITY_ENABLED);
        putQuietly(report, "local_tts_status", LOCAL_MNN_TTS_VOICE_QUALITY_ENABLED
            ? ttsStatus.detailText()
            : "本地 MNN TTS 可生成音频，但真实试听不可懂，已停用主朗读。");
        return report;
    }

    private JSONObject benchmarkAsr() throws Exception {
        JSONObject report = baseReport("asr");
        LocalAsrModelStatus status = new LocalAsrModelManager().inspect(this);
        putQuietly(report, "ready", status.ready);
        putQuietly(report, "status", status.detailText());
        if (!status.ready) {
            putQuietly(report, "success", false);
            putQuietly(report, "error", status.shortText());
            return report;
        }

        VoskLocalAsrEngine engine = new VoskLocalAsrEngine();
        JSONArray runs = new JSONArray();
        byte[] pcm = silencePcm(16_000, 3_000);
        runs.put(timed("cold_load_plus_3s_silence_asr", () -> engine.transcribePcm(status.modelDir, pcm)));
        runs.put(timed("warm_3s_silence_asr", () -> engine.transcribePcm(status.modelDir, pcm)));
        engine.close();
        putQuietly(report, "success", true);
        putQuietly(report, "input", "3 seconds 16kHz mono silence PCM; no speech accuracy expected");
        putQuietly(report, "runs", runs);
        return report;
    }

    private JSONObject benchmarkVision() throws Exception {
        JSONObject report = baseReport("vision");
        MnnNativeBridge bridge = new MnnNativeBridge();
        OfflineModelStatus status = new OfflineModelManager().inspect(
            modelRoot().getAbsolutePath(),
            OfflineAiClient.TEXT_MODEL_4B,
            bridge.isAvailable()
        );
        putQuietly(report, "ready", bridge.isAvailable() && status.yoloReady);
        putQuietly(report, "status", status.detailText());
        if (!bridge.isAvailable() || !status.yoloReady) {
            putQuietly(report, "success", false);
            putQuietly(report, "error", status.shortText());
            return report;
        }
        String imageDataUrl = syntheticRoomImageDataUrl();
        JSONArray runs = new JSONArray();
        runs.put(timed("cold_synthetic_image_yolo", () -> bridge.visionJson(
            status.modelDir,
            "检测画面中的障碍物并输出 JSON。",
            imageDataUrl,
            OfflineAiClient.DETECTOR_MODEL
        )));
        runs.put(timed("warm_synthetic_image_yolo", () -> bridge.visionJson(
            status.modelDir,
            "检测画面中的障碍物并输出 JSON。",
            imageDataUrl,
            OfflineAiClient.DETECTOR_MODEL
        )));
        putQuietly(report, "success", true);
        putQuietly(report, "input", "generated 640x640 synthetic room-like bitmap");
        putQuietly(report, "runs", runs);
        return report;
    }

    private JSONObject benchmarkText() throws Exception {
        JSONObject report = baseReport("text");
        MnnNativeBridge bridge = new MnnNativeBridge();
        OfflineModelStatus status = new OfflineModelManager().inspect(
            modelRoot().getAbsolutePath(),
            OfflineAiClient.TEXT_MODEL_4B,
            bridge.isAvailable()
        );
        putQuietly(report, "ready", status.ready());
        putQuietly(report, "status", status.detailText());
        if (!status.ready()) {
            putQuietly(report, "success", false);
            putQuietly(report, "error", status.shortText());
            return report;
        }
        String tuning = MnnLlmTuningProfile.DEFAULT.nativeConfigJson(bridge.supportsSme2());
        JSONArray runs = new JSONArray();
        runs.put(timed("cold_qwen4b_short_json", () -> bridge.textJson(
            status.modelDir,
            "你是适老化居家辅助系统。只输出 JSON：{\"reply\":\"请停下，前方可能有障碍。\"}",
            OfflineAiClient.TEXT_MODEL_4B,
            tuning,
            64,
            "}"
        )));
        runs.put(timed("warm_qwen4b_short_json", () -> bridge.textJson(
            status.modelDir,
            "只输出 JSON：{\"same\":true,\"tip\":\"向右慢慢绕开。\"}",
            OfflineAiClient.TEXT_MODEL_4B,
            tuning,
            48,
            "}"
        )));
        putQuietly(report, "success", true);
        putQuietly(report, "tuning", tuning);
        putQuietly(report, "runs", runs);
        return report;
    }

    private JSONObject benchmarkTextSuite() throws Exception {
        JSONObject report = baseReport("text_suite");
        MnnNativeBridge bridge = new MnnNativeBridge();
        OfflineModelStatus status = new OfflineModelManager().inspect(
            modelRoot().getAbsolutePath(),
            OfflineAiClient.TEXT_MODEL_4B,
            bridge.isAvailable()
        );
        putQuietly(report, "ready", status.ready());
        putQuietly(report, "status", status.detailText());
        if (!status.ready()) {
            putQuietly(report, "success", false);
            putQuietly(report, "error", status.shortText());
            return report;
        }

        String tuning = MnnLlmTuningProfile.DEFAULT.nativeConfigJson(bridge.supportsSme2());
        JSONArray runs = new JSONArray();
        String[][] cases = new String[][]{
            {
                "care_chat_night_toilet",
                """
                你是银龄智护的离线文本模型。用户是低视力老人。
                用户说：晚上起来上厕所前，我该注意什么？
                只输出 JSON：{"speech":"不超过45字的中文语音回复","intent":"info"}。
                """
            },
            {
                "navigation_obstacle_prompt",
                """
                你是盲人居家通行助手。画面检测结果：正前方偏左约1.2米有大型障碍，右侧有可通行空间。
                给用户一句能直接朗读的中文提醒，不要描述颜色，不要超过35字。
                只输出 JSON：{"speech":"...","intent":"nav_check"}。
                """
            },
            {
                "find_object_asr_correction",
                """
                ASR 识别文本可能错误：帮我找到我的晚。
                离线视觉模型可识别目标列表：碗、杯子、椅子、门、行李箱、背包、手提包、手机。
                判断用户最可能要找什么。只输出 JSON：{"target":"...","speech":"不超过35字中文"}。
                """
            },
            {
                "fall_confirmation",
                """
                传感器检测到疑似摔倒，画面也出现剧烈变化。请生成给老人的确认语音。
                要先询问是否摔倒，并说明10秒后将发送报警事件。只输出 JSON：{"speech":"...","intent":"fall_confirm"}。
                """
            },
            {
                "medication_and_care_record",
                """
                用户：我是糖尿病患者，今天晚饭后可能忘记吃药了，怎么办？
                你不能替代医生诊断，要给安全建议并建议记录给家属复核。
                只输出 JSON：{"speech":"不超过60字中文","intent":"care_advice"}。
                """
            },
            {
                "smart_refresh_semantic_compare",
                """
                上一次导航：前方一米有大型障碍，请向右慢慢绕开。
                新导航：前方约一米仍有大型障碍，右侧可绕行。
                判断语义是否一致。只输出 JSON：{"same":true或false,"reason":"不超过20字中文"}。
                """
            }
        };

        long suiteStarted = SystemClock.elapsedRealtimeNanos();
        boolean allSucceeded = true;
        for (String[] item : cases) {
            String name = item[0];
            String prompt = item[1];
            JSONObject run = timedWithTimeout(
                name,
                300_000L,
                () -> bridge.textJson(status.modelDir, prompt, OfflineAiClient.TEXT_MODEL_4B, tuning, 96, "}")
            );
            putQuietly(run, "prompt_chars", prompt.length());
            putQuietly(run, "max_new_tokens", 96);
            runs.put(run);
            if (!run.optBoolean("success")) {
                allSucceeded = false;
            }
        }
        putQuietly(report, "success", allSucceeded);
        putQuietly(report, "tuning", tuning);
        putQuietly(report, "total_elapsed_ms", elapsedMs(suiteStarted));
        putQuietly(report, "runs", runs);
        return report;
    }

    private JSONObject benchmarkTextInquiry() throws Exception {
        JSONObject report = baseReport("text_inquiry");
        MnnNativeBridge bridge = new MnnNativeBridge();
        OfflineModelStatus status = new OfflineModelManager().inspect(
            modelRoot().getAbsolutePath(),
            OfflineAiClient.TEXT_MODEL_4B,
            bridge.isAvailable()
        );
        putQuietly(report, "ready", status.ready());
        putQuietly(report, "status", status.detailText());
        if (!status.ready()) {
            putQuietly(report, "success", false);
            putQuietly(report, "error", status.shortText());
            return report;
        }
        String imageDataUrl = syntheticRoomImageDataUrl();
        JSONArray runs = new JSONArray();
        runs.put(runProcessorScenario(
            imageDataUrl,
            "你好你可以说什么你提做什么",
            bridge,
            "info",
            "看路",
            "cold_capability_text_inquiry"
        ));
        runs.put(runProcessorScenario(
            imageDataUrl,
            "帮我看看前方有没有障碍物",
            bridge,
            "nav_check",
            "前方",
            "warm_navigation_text_inquiry"
        ));
        runs.put(runProcessorScenario(
            imageDataUrl,
            "帮我找到我的碗",
            bridge,
            "search",
            "碗",
            "warm_search_bowl_text_inquiry"
        ));
        runs.put(runProcessorScenario(
            imageDataUrl,
            "帮我找到血压计",
            bridge,
            "info",
            "不在当前离线视觉",
            "warm_unsupported_target_text_inquiry"
        ));
        boolean allSucceeded = true;
        for (int index = 0; index < runs.length(); index += 1) {
            JSONObject run = runs.optJSONObject(index);
            if (run == null || !run.optBoolean("success") || !run.optBoolean("semantic_ok")) {
                allSucceeded = false;
            }
        }
        putQuietly(report, "success", allSucceeded);
        putQuietly(report, "runs", runs);
        return report;
    }

    private JSONObject benchmarkTts() throws Exception {
        JSONObject report = baseReport("tts");
        putQuietly(report, "success", true);
        putQuietly(report, "ready", false);
        putQuietly(report, "skipped", true);
        putQuietly(report, "voice_quality_passed", false);
        putQuietly(report, "reason", "本地 MNN TTS 真实试听不可懂，当前跳过合成测试，避免播放乱码音频。");
        return report;
    }

    private JSONObject benchmarkDisabledMnnTtsForDevelopmentOnly() throws Exception {
        JSONObject report = baseReport("tts_disabled_development_only");
        MnnTtsRuntimeBridge bridge = new MnnTtsRuntimeBridge();
        LocalTtsModelStatus status = new LocalTtsModelManager().inspect(
            this,
            bridge.isAvailable(),
            bridge.runtimeSummary()
        );
        putQuietly(report, "ready", status.ready);
        putQuietly(report, "status", status.detailText());
        if (!status.ready) {
            putQuietly(report, "success", false);
            putQuietly(report, "error", status.shortText());
            return report;
        }
        JSONArray runs = new JSONArray();
        JSONObject cold = timedWithTimeout(
            "cold_mnn_tts_short_sentence",
            30_000L,
            () -> synthesizeAndDescribe(bridge, status, "请停下，前方有障碍。")
        );
        runs.put(cold);
        if (cold.optBoolean("success")) {
            JSONObject warm = timedWithTimeout(
                "warm_mnn_tts_short_sentence",
                30_000L,
                () -> synthesizeAndDescribe(bridge, status, "向右一点，扶住墙再走。")
            );
            runs.put(warm);
            putQuietly(report, "success", warm.optBoolean("success"));
        } else {
            putQuietly(report, "success", false);
            putQuietly(report, "error", cold.optString("error", "cold TTS synthesis failed"));
        }
        putQuietly(report, "runs", runs);
        return report;
    }

    private JSONObject benchmarkManualScenario() throws Exception {
        JSONObject report = baseReport("scenario");
        File inputDir = new File(getExternalFilesDir(null), "manual_test");
        File audioFile = new File(inputDir, "real_voice.wav");
        File imageFile = new File(inputDir, "real_scene.jpg");
        putQuietly(report, "input_dir", inputDir.getAbsolutePath());
        putQuietly(report, "audio_file", describeFile(audioFile));
        putQuietly(report, "image_file", describeFile(imageFile));
        if (!audioFile.isFile() || !imageFile.isFile()) {
            putQuietly(report, "success", false);
            putQuietly(report, "error", "manual_test/real_voice.wav or manual_test/real_scene.jpg is missing");
            return report;
        }

        MnnNativeBridge bridge = new MnnNativeBridge();
        OfflineModelStatus offlineStatus = new OfflineModelManager().inspect(
            modelRoot().getAbsolutePath(),
            OfflineAiClient.TEXT_MODEL_4B,
            bridge.isAvailable()
        );
        LocalAsrModelStatus asrStatus = new LocalAsrModelManager().inspect(this);
        putQuietly(report, "offline_ready", offlineStatus.ready());
        putQuietly(report, "local_asr_ready", asrStatus.ready);
        if (!offlineStatus.ready() || !asrStatus.ready) {
            putQuietly(report, "success", false);
            putQuietly(report, "error", "offline model or local ASR is not ready");
            return report;
        }

        String transcript = "";
        JSONObject asrRun = new JSONObject();
        long asrStarted = SystemClock.elapsedRealtimeNanos();
        VoskLocalAsrEngine asrEngine = new VoskLocalAsrEngine();
        try {
            transcript = asrEngine.transcribePcm(asrStatus.modelDir, wavPcm16(audioFile));
            putQuietly(asrRun, "success", true);
            putQuietly(asrRun, "transcript", transcript);
        } catch (Throwable throwable) {
            putQuietly(asrRun, "success", false);
            putQuietly(asrRun, "error", readableThrowable(throwable));
        } finally {
            asrEngine.close();
            putQuietly(asrRun, "elapsed_ms", elapsedMs(asrStarted));
        }
        putQuietly(report, "asr", asrRun);

        String imageDataUrl = imageDataUrl(imageFile);
        JSONObject visionRun = new JSONObject();
        long visionStarted = SystemClock.elapsedRealtimeNanos();
        try {
            String output = bridge.visionJson(
                offlineStatus.modelDir,
                "检测画面中的通行障碍和可寻找物体，只输出 JSON。",
                imageDataUrl,
                OfflineAiClient.DETECTOR_MODEL
            );
            putQuietly(visionRun, "success", true);
            putQuietly(visionRun, "elapsed_ms", elapsedMs(visionStarted));
            putQuietly(visionRun, "output", output);
        } catch (Throwable throwable) {
            putQuietly(visionRun, "success", false);
            putQuietly(visionRun, "elapsed_ms", elapsedMs(visionStarted));
            putQuietly(visionRun, "error", readableThrowable(throwable));
        }
        putQuietly(report, "vision", visionRun);

        if (!transcript.trim().isEmpty()) {
            JSONObject pipelineRun = runProcessorScenario(imageDataUrl, transcript, bridge);
            putQuietly(report, "pipeline", pipelineRun);
        } else {
            putQuietly(report, "pipeline_skipped", "ASR did not produce a transcript");
        }
        putQuietly(report, "success", asrRun.optBoolean("success") && visionRun.optBoolean("success"));
        return report;
    }

    private JSONObject runProcessorScenario(String imageDataUrl, String transcript, MnnNativeBridge bridge) {
        return runProcessorScenario(imageDataUrl, transcript, bridge, "", "", "");
    }

    private JSONObject runProcessorScenario(
        String imageDataUrl,
        String transcript,
        MnnNativeBridge bridge,
        String expectedIntent,
        String expectedSpeechContains,
        String name
    ) {
        JSONObject run = new JSONObject();
        long started = SystemClock.elapsedRealtimeNanos();
        try {
            SilverCareArtificialIntelligenceClient.SettingsProvider settings = scenarioSettingsProvider();
            List<JSONObject> messages = new ArrayList<>();
            SilverCareProcessor processor = new SilverCareProcessor(
                new OfflineAiClient(settings, new MnnOfflineEngine(settings, new OfflineModelManager(), bridge)),
                new MemoryStore(getSharedPreferences("benchmark_scenario", MODE_PRIVATE)),
                messages::add
            );
            processor.processTextInquiry(imageDataUrl, transcript);
            JSONArray messageArray = new JSONArray(messages);
            JSONObject inquiry = firstMessageOfType(messages, "inquiry_result");
            JSONObject speak = firstMessageOfType(messages, "speak");
            String actualIntent = inquiry == null ? "" : inquiry.optString("intent", "");
            String spoken = speak == null ? "" : speak.optString("text", "");
            boolean intentOk = expectedIntent == null || expectedIntent.isEmpty() || expectedIntent.equals(actualIntent);
            boolean speechOk = expectedSpeechContains == null || expectedSpeechContains.isEmpty() || spoken.contains(expectedSpeechContains);
            putQuietly(run, "success", true);
            putQuietly(run, "semantic_ok", intentOk && speechOk);
            putQuietly(run, "expected_intent", expectedIntent);
            putQuietly(run, "actual_intent", actualIntent);
            putQuietly(run, "spoken", spoken);
            putQuietly(run, "elapsed_ms", elapsedMs(started));
            putQuietly(run, "input_transcript", transcript);
            if (name != null && !name.isEmpty()) putQuietly(run, "name", name);
            putQuietly(run, "messages", messageArray);
        } catch (Throwable throwable) {
            putQuietly(run, "success", false);
            putQuietly(run, "semantic_ok", false);
            putQuietly(run, "elapsed_ms", elapsedMs(started));
            if (name != null && !name.isEmpty()) putQuietly(run, "name", name);
            putQuietly(run, "error", readableThrowable(throwable));
        }
        return run;
    }

    private static JSONObject firstMessageOfType(List<JSONObject> messages, String type) {
        if (messages == null) return null;
        for (JSONObject message : messages) {
            if (message != null && type.equals(message.optString("type"))) {
                return message;
            }
        }
        return null;
    }

    private SilverCareArtificialIntelligenceClient.SettingsProvider scenarioSettingsProvider() {
        return new SilverCareArtificialIntelligenceClient.SettingsProvider() {
            @Override
            public String aiRuntimeMode() {
                return AiRuntimeMode.OFFLINE_MNN.value;
            }

            @Override
            public String offlineModelDir() {
                return modelRoot().getAbsolutePath();
            }

            @Override
            public String apiKey() {
                return "";
            }

            @Override
            public String compatibleBaseUrl() {
                return "";
            }

            @Override
            public String apiBaseUrl() {
                return "";
            }

            @Override
            public String visionModel() {
                return OfflineAiClient.DETECTOR_MODEL;
            }

            @Override
            public String microModel() {
                return OfflineAiClient.DETECTOR_MODEL;
            }

            @Override
            public String textModel() {
                return OfflineAiClient.TEXT_MODEL_4B;
            }

            @Override
            public String asrModel() {
                return OfflineAiClient.DEVICE_ASR_MODEL;
            }

            @Override
            public String mnnLlmTuningMode() {
                return MnnLlmTuningProfile.DEFAULT.value;
            }

            @Override
            public boolean voiceFirstEnabled() {
                return true;
            }

            @Override
            public boolean smartNavigationRefreshEnabled() {
                return false;
            }
        };
    }

    private JSONObject timed(String name, Callable<String> callable) {
        JSONObject item = new JSONObject();
        putQuietly(item, "name", name);
        long started = SystemClock.elapsedRealtimeNanos();
        try {
            String output = callable.call();
            putQuietly(item, "success", true);
            putQuietly(item, "elapsed_ms", elapsedMs(started));
            putQuietly(item, "output_excerpt", excerpt(output));
        } catch (Throwable throwable) {
            putQuietly(item, "success", false);
            putQuietly(item, "elapsed_ms", elapsedMs(started));
            putQuietly(item, "error", readableThrowable(throwable));
        }
        return item;
    }

    private JSONObject timedRouterJson(String name, String expectedIntent, Callable<String> callable) {
        JSONObject item = timed(name, callable);
        String output = item.optString("output_excerpt", "");
        try {
            JSONObject parsed = parseFirstJsonObject(output);
            String compactIntent = parsed.optString("i", parsed.optString("intent", ""));
            String normalizedIntent = normalizeCompactIntent(compactIntent);
            boolean semanticOk = expectedIntent == null || expectedIntent.equals(normalizedIntent);
            putQuietly(item, "json_valid", true);
            putQuietly(item, "parsed_intent", normalizedIntent);
            putQuietly(item, "semantic_ok", semanticOk);
            putQuietly(item, "parsed_json", parsed);
            if (!semanticOk) {
                putQuietly(item, "success", false);
                putQuietly(item, "error", "intent " + normalizedIntent + " != expected " + expectedIntent);
            }
        } catch (Throwable throwable) {
            putQuietly(item, "json_valid", false);
            putQuietly(item, "semantic_ok", false);
            putQuietly(item, "success", false);
            putQuietly(item, "error", readableThrowable(throwable));
        }
        return item;
    }

    private JSONObject timedWithTimeout(String name, long timeoutMs, Callable<String> callable) {
        JSONObject item = new JSONObject();
        putQuietly(item, "name", name);
        long started = SystemClock.elapsedRealtimeNanos();
        ExecutorService single = Executors.newSingleThreadExecutor();
        Future<String> future = single.submit(callable);
        try {
            String output = future.get(timeoutMs, TimeUnit.MILLISECONDS);
            putQuietly(item, "success", true);
            putQuietly(item, "output_excerpt", excerpt(output));
        } catch (TimeoutException timeout) {
            future.cancel(true);
            putQuietly(item, "success", false);
            putQuietly(item, "timeout", true);
            putQuietly(item, "error", "timeout after " + timeoutMs + " ms");
        } catch (Throwable throwable) {
            putQuietly(item, "success", false);
            putQuietly(item, "error", readableThrowable(throwable));
        } finally {
            putQuietly(item, "elapsed_ms", elapsedMs(started));
            single.shutdownNow();
        }
        return item;
    }

    private String synthesizeAndDescribe(LocalTtsRuntimeBridge bridge, LocalTtsModelStatus status, String text) throws Exception {
        File wav = bridge.synthesizeToWav(status.modelDir, getCacheDir(), text, "zh-CN");
        long size = wav.length();
        boolean deleted = wav.delete();
        return "wav_bytes=" + size + ",deleted=" + deleted;
    }

    private String describeFile(File file) {
        if (file == null) return "";
        return file.getAbsolutePath() + " bytes=" + (file.isFile() ? file.length() : -1);
    }

    private byte[] wavPcm16(File wavFile) throws Exception {
        byte[] bytes = readAllBytes(wavFile);
        int dataOffset = -1;
        int dataSize = -1;
        for (int i = 12; i + 8 <= bytes.length; ) {
            String chunk = new String(bytes, i, 4, java.nio.charset.StandardCharsets.US_ASCII);
            int size = littleInt(bytes, i + 4);
            int next = i + 8 + Math.max(size, 0);
            if ("data".equals(chunk)) {
                dataOffset = i + 8;
                dataSize = Math.min(size, bytes.length - dataOffset);
                break;
            }
            i = next + (size % 2);
        }
        if (dataOffset < 0 || dataSize <= 0) {
            throw new IllegalArgumentException("WAV data chunk not found");
        }
        byte[] pcm = new byte[dataSize];
        System.arraycopy(bytes, dataOffset, pcm, 0, dataSize);
        return pcm;
    }

    private String imageDataUrl(File imageFile) throws Exception {
        byte[] bytes = readAllBytes(imageFile);
        return "data:image/jpeg;base64," + Base64.encodeToString(bytes, Base64.NO_WRAP);
    }

    private byte[] readAllBytes(File file) throws Exception {
        try (FileInputStream input = new FileInputStream(file);
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[16 * 1024];
            int read;
            while ((read = input.read(buffer)) >= 0) {
                output.write(buffer, 0, read);
            }
            return output.toByteArray();
        }
    }

    private int littleInt(byte[] bytes, int offset) {
        return (bytes[offset] & 0xff)
            | ((bytes[offset + 1] & 0xff) << 8)
            | ((bytes[offset + 2] & 0xff) << 16)
            | ((bytes[offset + 3] & 0xff) << 24);
    }

    private String syntheticRoomImageDataUrl() throws Exception {
        Bitmap bitmap = Bitmap.createBitmap(640, 640, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        canvas.drawColor(Color.rgb(238, 236, 228));
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        paint.setColor(Color.rgb(175, 150, 116));
        canvas.drawRect(0, 430, 640, 640, paint);
        paint.setColor(Color.rgb(80, 92, 70));
        canvas.drawRect(70, 260, 230, 585, paint);
        paint.setColor(Color.rgb(30, 36, 45));
        canvas.drawRect(290, 290, 430, 585, paint);
        paint.setColor(Color.rgb(40, 110, 210));
        canvas.drawRect(120, 220, 500, 300, paint);
        paint.setColor(Color.rgb(250, 250, 250));
        canvas.drawCircle(500, 110, 52, paint);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out);
        bitmap.recycle();
        return "data:image/png;base64," + Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP);
    }

    private byte[] silencePcm(int sampleRate, int durationMs) {
        int samples = Math.max(1, sampleRate * durationMs / 1000);
        return new byte[samples * 2];
    }

    private File modelRoot() {
        return OfflineModelDownloader.automaticModelDir(this);
    }

    private JSONObject baseReport(String test) {
        JSONObject report = new JSONObject();
        putQuietly(report, "test", test);
        putQuietly(report, "timestamp_ms", System.currentTimeMillis());
        putQuietly(report, "device", android.os.Build.MANUFACTURER + " " + android.os.Build.MODEL);
        putQuietly(report, "sdk", android.os.Build.VERSION.SDK_INT);
        putQuietly(report, "package", getPackageName());
        return report;
    }

    private long elapsedMs(long startedNanos) {
        return Math.round((SystemClock.elapsedRealtimeNanos() - startedNanos) / 1_000_000.0d);
    }

    private void writeAndExit(JSONObject report) {
        try {
            File dir = new File(getExternalFilesDir(null), "benchmarks");
            if (!dir.isDirectory() && !dir.mkdirs()) {
                throw new IllegalStateException("无法创建 benchmark 目录：" + dir.getAbsolutePath());
            }
            String test = report.optString("test", "unknown");
            File output = new File(dir, "local-model-benchmark-" + test + "-" + System.currentTimeMillis() + ".json");
            File latest = new File(dir, "latest-" + test + ".json");
            writeJson(output, report);
            writeJson(latest, report);
            putQuietly(report, "output_file", output.getAbsolutePath());
            Log.i(TAG, "BENCHMARK_RESULT " + report);
        } catch (Throwable throwable) {
            Log.e(TAG, "BENCHMARK_WRITE_FAILED " + readableThrowable(throwable) + " report=" + report);
        }
        runOnUiThread(() -> {
            finish();
            new Handler(Looper.getMainLooper()).postDelayed(() -> {
                Process.killProcess(Process.myPid());
                System.exit(0);
            }, 300L);
        });
    }

    private void writeJson(File file, JSONObject json) throws Exception {
        try (FileWriter writer = new FileWriter(file, false)) {
            writer.write(json.toString(2));
            writer.write('\n');
        }
    }

    private long defaultTimeoutFor(String test) {
        return switch (test) {
            case "text" -> 240_000L;
            case "text_suite" -> 360_000L;
            case "text_inquiry" -> 180_000L;
            case "asr" -> 120_000L;
            case "tts" -> 180_000L;
            case "vision" -> 120_000L;
            default -> DEFAULT_TIMEOUT_MS;
        };
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim().toLowerCase(Locale.US);
    }

    private static String excerpt(String value) {
        if (value == null) return "";
        String clean = value.replace('\n', ' ').replace('\r', ' ').trim();
        return clean.length() <= 500 ? clean : clean.substring(0, 500) + "...";
    }

    private static JSONObject parseFirstJsonObject(String text) throws Exception {
        String clean = text == null ? "" : text.trim();
        int start = clean.indexOf('{');
        if (start < 0) throw new IllegalArgumentException("JSON object not found");
        String json = firstCompleteJson(clean, start);
        if (json == null) throw new IllegalArgumentException("JSON object incomplete");
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

    private static String normalizeCompactIntent(String value) {
        String code = value == null ? "" : value.trim();
        String lower = code.toLowerCase(Locale.US);
        switch (lower) {
            case "search":
            case "nav_check":
            case "micro_nav":
            case "tag":
            case "task":
            case "task_done":
            case "task_skip":
            case "task_previous":
            case "task_repeat":
            case "task_status":
            case "stop":
            case "info":
                return lower;
            default:
                break;
        }
        if (code.length() > 1) code = code.substring(0, 1);
        return switch (code.toUpperCase(Locale.US)) {
            case "S" -> "search";
            case "N" -> "nav_check";
            case "M" -> "micro_nav";
            case "L" -> "tag";
            case "P" -> "task";
            case "D" -> "task_done";
            case "K" -> "task_skip";
            case "B" -> "task_previous";
            case "R" -> "task_repeat";
            case "U" -> "task_status";
            case "X" -> "stop";
            default -> "info";
        };
    }

    private static String readableThrowable(Throwable throwable) {
        if (throwable == null) return "";
        String message = throwable.getMessage();
        return message == null || message.trim().isEmpty()
            ? String.valueOf(throwable)
            : message;
    }

    private static void putQuietly(JSONObject object, String key, Object value) {
        try {
            object.put(key, value);
        } catch (Exception ignored) {
        }
    }
}
