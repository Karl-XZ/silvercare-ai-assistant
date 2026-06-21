package com.silvercare.aiassistant;

import org.junit.Test;

import java.io.File;
import java.util.Collections;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.equalTo;

public class OfflineAiClientTest {
    @Test
    public void routesVisionToDetectorAndTextToSelectedQwenModel() throws Exception {
        TestFakes.Settings settings = new TestFakes.Settings();
        settings.aiRuntimeMode = AiRuntimeMode.OFFLINE_MNN.value;
        settings.textModel = OfflineAiClient.TEXT_MODEL_4B;
        RecordingOfflineEngine engine = new RecordingOfflineEngine();
        OfflineAiClient client = new OfflineAiClient(settings, engine);

        assertThat(client.visionJson("看前方", "data:image/png;base64,abc", settings.visionModel()), equalTo("{\"ok\":true}"));
        assertThat(client.textJson("规划倒水", settings.textModel()), equalTo("[{\"instruction\":\"找到杯子\"}]"));
        assertThat(client.transcribe("data:audio/webm;base64,abc"), equalTo("帮我找门"));

        assertThat(engine.lastVisionRole, equalTo("detector"));
        assertThat(engine.lastTextRole, equalTo(OfflineAiClient.TEXT_MODEL_4B));
        assertThat(engine.lastImageDataUrl, equalTo("data:image/png;base64,abc"));
        assertThat(engine.lastAudioDataUrl, equalTo("data:audio/webm;base64,abc"));
    }

    @Test
    public void routesTextToBackupOnePointFiveBModel() throws Exception {
        TestFakes.Settings settings = new TestFakes.Settings();
        settings.aiRuntimeMode = AiRuntimeMode.OFFLINE_MNN.value;
        settings.textModel = OfflineAiClient.TEXT_MODEL_1_5B;
        RecordingOfflineEngine engine = new RecordingOfflineEngine();
        OfflineAiClient client = new OfflineAiClient(settings, engine);

        assertThat(client.textJson("规划倒水", settings.textModel()), equalTo("[{\"instruction\":\"找到杯子\"}]"));

        assertThat(engine.lastTextRole, equalTo(OfflineAiClient.TEXT_MODEL_1_5B));
    }

    @Test
    public void fallsBackToFourBWhenTextModelIsNotAnOfflineModel() throws Exception {
        TestFakes.Settings settings = new TestFakes.Settings();
        settings.aiRuntimeMode = AiRuntimeMode.OFFLINE_MNN.value;
        RecordingOfflineEngine engine = new RecordingOfflineEngine();
        OfflineAiClient client = new OfflineAiClient(settings, engine);

        client.textJson("规划倒水", settings.textModel());

        assertThat(engine.lastTextRole, equalTo(OfflineAiClient.TEXT_MODEL_4B));
    }

    @Test
    public void preservesDetectorRoleForMicroNavigation() throws Exception {
        TestFakes.Settings settings = new TestFakes.Settings();
        RecordingOfflineEngine engine = new RecordingOfflineEngine();
        OfflineAiClient client = new OfflineAiClient(settings, engine);

        client.visionJson("微导航", "data:image/png;base64,abc", OfflineAiClient.DETECTOR_MODEL);

        assertThat(engine.lastVisionRole, equalTo(OfflineAiClient.DETECTOR_MODEL));
    }

    private static final class RecordingOfflineEngine implements OfflineInferenceEngine {
        String lastVisionRole;
        String lastTextRole;
        String lastImageDataUrl;
        String lastAudioDataUrl;

        @Override
        public String visionJson(String prompt, String imageDataUrl, String role) {
            lastVisionRole = role;
            lastImageDataUrl = imageDataUrl;
            return "{\"ok\":true}";
        }

        @Override
        public String textJson(String prompt, String role) {
            lastTextRole = role;
            return "[{\"instruction\":\"找到杯子\"}]";
        }

        @Override
        public String transcribe(String audioDataUrl) {
            lastAudioDataUrl = audioDataUrl;
            return "帮我找门";
        }

        @Override
        public OfflineModelStatus status() {
            return new OfflineModelStatus(
                "test",
                new File("config.json"),
                new File("damo-yolo.mnn"),
                true,
                true,
                true,
                true,
                Collections.emptyList()
            );
        }
    }
}
