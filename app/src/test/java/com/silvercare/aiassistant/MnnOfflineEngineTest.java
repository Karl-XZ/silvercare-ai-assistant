package com.silvercare.aiassistant;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.File;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;
import static org.junit.Assert.fail;

public class MnnOfflineEngineTest {
    @Rule
    public TemporaryFolder folder = new TemporaryFolder();

    @Test
    public void refusesInferenceWhenNativeRuntimeOrModelsAreMissing() throws Exception {
        TestFakes.Settings settings = new TestFakes.Settings();
        settings.offlineModelDir = folder.newFolder("empty_models").getAbsolutePath();
        MnnOfflineEngine engine = new MnnOfflineEngine(
            settings,
            new OfflineModelManager(),
            new FakeBridge(false)
        );

        try {
            engine.textJson("hello", "reasoning");
            fail("Expected missing offline runtime to throw");
        } catch (IllegalStateException expected) {
            assertThat(expected.getMessage(), containsString("端侧离线模型未就绪"));
        }
    }

    @Test
    public void forwardsRequestsToNativeBridgeWhenReady() throws Exception {
        File root = folder.newFolder("multimodal_care_models");
        File text = new File(root, "Qwen3-4B-Instruct-2507-MNN");
        assertThat(text.mkdirs(), equalTo(true));
        assertThat(new File(text, "config.json").createNewFile(), equalTo(true));
        assertThat(new File(root, "damo_yolo.mnn").createNewFile(), equalTo(true));

        TestFakes.Settings settings = new TestFakes.Settings();
        settings.offlineModelDir = root.getAbsolutePath();
        FakeBridge bridge = new FakeBridge(true);
        MnnOfflineEngine engine = new MnnOfflineEngine(settings, new OfflineModelManager(), bridge);

        String vision = engine.visionJson("Current task: 正在寻找：狗\n", "image", "vision");
        assertThat(vision, containsString("\"target_detected\":true"));
        assertThat(vision, containsString("\"subject\":\"狗\""));
        assertThat(engine.textJson("prompt", "reasoning"), equalTo("{\"native\":\"text\"}"));
        assertThat(engine.textJson("prompt", "reasoning", 96), equalTo("{\"native\":\"text\"}"));
        assertThat(engine.transcribe("audio"), equalTo("离线语音"));
        assertThat(bridge.modelDir, equalTo(root.getAbsolutePath()));
        assertThat(bridge.visionRole, equalTo("vision"));
        assertThat(bridge.textRole, equalTo("reasoning"));
        assertThat(bridge.maxNewTokens, equalTo(96));
        assertThat(bridge.endWith, equalTo(""));
        assertThat(
            bridge.tuningConfigJson,
            equalTo("{\"jinja\":{\"context\":{\"enable_thinking\":false}},\"cpu_sme2_neon_division_ratio\":41,\"cpu_sme_core_num\":2}")
        );
    }

    @Test
    public void usesSelectedBackupTextModelForReadinessAndBridgeRole() throws Exception {
        File root = folder.newFolder("multimodal_care_models_15b");
        File text = new File(root, "Qwen2.5-1.5B-Instruct-MNN");
        assertThat(text.mkdirs(), equalTo(true));
        assertThat(new File(text, "config.json").createNewFile(), equalTo(true));
        assertThat(new File(root, "damo-yolo.mnn").createNewFile(), equalTo(true));

        TestFakes.Settings settings = new TestFakes.Settings();
        settings.offlineModelDir = root.getAbsolutePath();
        settings.textModel = OfflineAiClient.TEXT_MODEL_1_5B;
        FakeBridge bridge = new FakeBridge(true);
        MnnOfflineEngine engine = new MnnOfflineEngine(settings, new OfflineModelManager(), bridge);

        assertThat(engine.status().ready(), equalTo(true));
        assertThat(engine.status().textModel, equalTo(OfflineAiClient.TEXT_MODEL_1_5B));
        assertThat(
            engine.textJson("prompt", OfflineAiClient.TEXT_MODEL_1_5B),
            equalTo("{\"native\":\"text\"}")
        );
        assertThat(bridge.textRole, equalTo(OfflineAiClient.TEXT_MODEL_1_5B));
    }

    @Test
    public void fallsBackToMnnDefaultWhenAutoTuningRunsWithoutSme2() throws Exception {
        File root = folder.newFolder("multimodal_care_models_no_sme2");
        File text = new File(root, "Qwen3-4B-Instruct-2507-MNN");
        assertThat(text.mkdirs(), equalTo(true));
        assertThat(new File(text, "config.json").createNewFile(), equalTo(true));
        assertThat(new File(root, "damo-yolo.mnn").createNewFile(), equalTo(true));

        TestFakes.Settings settings = new TestFakes.Settings();
        settings.offlineModelDir = root.getAbsolutePath();
        FakeBridge bridge = new FakeBridge(true);
        bridge.supportsSme2 = false;
        MnnOfflineEngine engine = new MnnOfflineEngine(settings, new OfflineModelManager(), bridge);

        assertThat(engine.textJson("prompt", "reasoning"), equalTo("{\"native\":\"text\"}"));
        assertThat(bridge.tuningConfigJson, equalTo("{\"jinja\":{\"context\":{\"enable_thinking\":false}}}"));
    }

    @Test
    public void appliesSelectedPerformanceTuningProfile() throws Exception {
        File root = folder.newFolder("multimodal_care_models_perf");
        File text = new File(root, "Qwen3-4B-Instruct-2507-MNN");
        assertThat(text.mkdirs(), equalTo(true));
        assertThat(new File(text, "config.json").createNewFile(), equalTo(true));
        assertThat(new File(root, "damo-yolo.mnn").createNewFile(), equalTo(true));

        TestFakes.Settings settings = new TestFakes.Settings();
        settings.offlineModelDir = root.getAbsolutePath();
        settings.mnnLlmTuningMode = MnnLlmTuningProfile.PERFORMANCE.value;
        FakeBridge bridge = new FakeBridge(true);
        MnnOfflineEngine engine = new MnnOfflineEngine(settings, new OfflineModelManager(), bridge);

        assertThat(engine.textJson("prompt", "reasoning"), equalTo("{\"native\":\"text\"}"));
        assertThat(
            bridge.tuningConfigJson,
            equalTo("{\"jinja\":{\"context\":{\"enable_thinking\":false}},\"cpu_sme2_neon_division_ratio\":49,\"cpu_sme_core_num\":2}")
        );
    }

    private static final class FakeBridge implements MnnRuntimeBridge {
        private final boolean available;
        String modelDir;
        String visionRole;
        String textRole;
        String tuningConfigJson;
        int maxNewTokens;
        String endWith = "";
        boolean supportsSme2 = true;

        FakeBridge(boolean available) {
            this.available = available;
        }

        @Override
        public boolean isAvailable() {
            return available;
        }

        @Override
        public boolean supportsSme2() {
            return supportsSme2;
        }

        @Override
        public String runtimeSummary() {
            return supportsSme2 ? "fake-mnn · SME2 可用" : "fake-mnn · 未检测到 SME2";
        }

        @Override
        public String visionJson(String modelDir, String prompt, String imageDataUrl, String role) {
            this.modelDir = modelDir;
            this.visionRole = role;
            return """
                {
                  "image_width": 640,
                  "image_height": 480,
                  "detections": [
                    {"class":"dog","score":0.86,"box":[120,180,320,470]}
                  ]
                }
                """;
        }

        @Override
        public String textJson(String modelDir, String prompt, String role, String tuningConfigJson) {
            return textJson(modelDir, prompt, role, tuningConfigJson, 0);
        }

        @Override
        public String textJson(
            String modelDir,
            String prompt,
            String role,
            String tuningConfigJson,
            int maxNewTokens
        ) {
            return textJson(modelDir, prompt, role, tuningConfigJson, maxNewTokens, null);
        }

        @Override
        public String textJson(
            String modelDir,
            String prompt,
            String role,
            String tuningConfigJson,
            int maxNewTokens,
            String endWith
        ) {
            this.modelDir = modelDir;
            this.textRole = role;
            this.tuningConfigJson = tuningConfigJson;
            this.maxNewTokens = maxNewTokens;
            this.endWith = endWith == null ? "" : endWith;
            return "{\"native\":\"text\"}";
        }

        @Override
        public String transcribe(String modelDir, String audioDataUrl) {
            this.modelDir = modelDir;
            return "离线语音";
        }
    }
}
