package com.silvercare.aiassistant;

import java.io.File;
import java.io.IOException;
import org.json.JSONObject;
import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;
import static org.junit.Assert.*;

public class BackendLanguageRegressionTest {
    @Rule public TemporaryFolder folder = new TemporaryFolder();

    @Test public void microFollowUpRequestFailuresSpeakSelectedLanguageForBothRoutes() {
        for (String language : new String[]{"en", "ja"}) {
            for (String image : new String[]{"", "data:image/png;base64,test"}) {
                RecordingClient ai = new RecordingClient(language);
                TestFakes.Sink sink = new TestFakes.Sink();
                SilverCareProcessor processor = new SilverCareProcessor(ai, new MemoryStore(new TestFakes.Preferences()), sink);
                processor.processTextInquiry("", language.equals("en") ? "Guide me to the cup" : "コップに誘導して");
                sink.messages.clear(); ai.fail = true; ai.visionCalls = 0; ai.textCalls = 0;
                processor.processTextInquiry(image, language.equals("en") ? "How much farther?" : "あとどのくらいですか");
                assertEquals(image.isEmpty() ? 0 : 1, ai.visionCalls);
                assertEquals(image.isEmpty() ? 1 : 0, ai.textCalls);
                String speech = sink.firstOfType("speak").optString("text");
                assertEquals(language.equals("en") ? "Continuing guidance toward cup. Say “close guidance” to finish." : "引き続き誘導します：コップ。終了するには「誘導を終了」と言ってください。", speech);
                assertFalse(speech.contains("杯子")); assertFalse(speech.contains("我正在"));
                assertEquals("micro", sink.firstOfType("inquiry_result").optString("mode"));
            }
        }
    }

    @Test public void sceneQuestionsCallVisionAndNeverTextInOfflineMode() {
        String[][] phrases = {{"What is on the table?", "Describe what is in front of me", "What do you see around me?"}, {"テーブルの上に何がありますか", "目の前に何が見えますか", "周囲の様子を説明して"}};
        for (int index = 0; index < phrases.length; index++) {
            String language = index == 0 ? "en" : "ja";
            for (String phrase : phrases[index]) {
                RecordingClient ai = new RecordingClient(language); ai.scene = true;
                TestFakes.Sink sink = new TestFakes.Sink();
                new SilverCareProcessor(ai, new MemoryStore(new TestFakes.Preferences()), sink).processTextInquiry("image", phrase);
                assertEquals(phrase, 1, ai.visionCalls); assertEquals(phrase, 0, ai.textCalls);
                assertTrue(sink.firstOfType("speak").optString("text").contains(language.equals("en") ? "cup" : "コップ"));
                ai = new RecordingClient(language); sink = new TestFakes.Sink();
                new SilverCareProcessor(ai, new MemoryStore(new TestFakes.Preferences()), sink).processTextInquiry("", phrase);
                assertEquals(0, ai.visionCalls); assertEquals(0, ai.textCalls);
                assertTrue(sink.firstOfType("speak").optString("text").contains(language.equals("en") ? "camera" : "カメラ"));
            }
        }
    }

    @Test public void identityAndProjectQuestionsRemainTextQuestions() {
        for (String phrase : new String[]{"What is this project?", "Describe this model", "このプロジェクトは何ですか", "あなたは何者ですか"}) {
            RecordingClient ai = new RecordingClient("en"); ai.scene = true;
            new SilverCareProcessor(ai, new MemoryStore(new TestFakes.Preferences()), new TestFakes.Sink()).processTextInquiry("image", phrase);
            assertEquals(phrase, 0, ai.visionCalls); assertEquals(phrase, 1, ai.textCalls);
        }
    }

    @Test public void realOfflineClientAndEngineProduceLocalizedMicroGuidance() throws Exception {
        for (String language : new String[]{"en", "ja"}) {
            File root = folder.newFolder(language);
            File text = new File(root, "Qwen3-4B-Instruct-2507-MNN"); assertTrue(text.mkdirs());
            assertTrue(new File(text, "config.json").createNewFile()); assertTrue(new File(root, "damo_yolo.mnn").createNewFile());
            TestFakes.Settings settings = new TestFakes.Settings(); settings.appLanguage = language;
            settings.aiRuntimeMode = "offline_mnn"; settings.offlineModelDir = root.getAbsolutePath();
            DetectorBridge bridge = new DetectorBridge(language);
            OfflineAiClient client = new OfflineAiClient(settings, new MnnOfflineEngine(settings, new OfflineModelManager(), bridge));
            TestFakes.Sink sink = new TestFakes.Sink();
            SilverCareProcessor processor = new SilverCareProcessor(client, new MemoryStore(new TestFakes.Preferences()), sink);
            processor.processTextInquiry("", language.equals("en") ? "Guide me to the cup" : "コップに誘導して");
            processor.processFrame("image");
            assertEquals("detector", bridge.lastRole);
            JSONObject result = sink.firstOfType("micro_result"); assertNotNull(result);
            assertTrue(result.optInt("x") < -12); assertEquals("move", result.optString("action"));
            assertEquals(language.equals("en") ? "A little to the left." : "少し左へ。", result.optString("guidance_speech"));
        }
    }

    @Test public void recalledObjectsMatchAcrossLanguagesWithoutRewritingSavedText() {
        for (String storedName : new String[]{"cup", "コップ", "杯子"}) {
            TestFakes.Preferences preferences = new TestFakes.Preferences();
            MemoryStore memory = new MemoryStore(preferences);
            memory.logObject(storedName, "王先生 shelf", "Original scene: 紅茶の隣，青い箱。");
            String before = preferences.getString("history_json", "");
            for (String language : new String[]{"en", "ja"}) {
                RecordingClient ai = new RecordingClient(language);
                TestFakes.Sink sink = new TestFakes.Sink();
                new SilverCareProcessor(ai, memory, sink).processTextInquiry("", language.equals("en") ? "Where is my cup?" : "私のコップはどこですか");
                JSONObject result = sink.firstOfType("inquiry_result");
                assertEquals("info", result.optString("intent"));
                assertTrue(result.optString("speech").contains(storedName));
                assertTrue(result.optString("speech").contains("王先生 shelf"));
                assertTrue(result.optString("speech").contains("Original scene: 紅茶の隣，青い箱。"));
                assertEquals(before, preferences.getString("history_json", ""));
            }
        }
    }

    private static final class RecordingClient implements SilverCareArtificialIntelligenceClient {
        final TestFakes.Settings settings = new TestFakes.Settings();
        int visionCalls, textCalls; boolean fail, scene;
        RecordingClient(String language) { settings.appLanguage = language; settings.aiRuntimeMode = "offline_mnn"; }
        public SettingsProvider settings() { return settings; }
        public String visionJson(String prompt, String image, String model) throws Exception {
            visionCalls++; if (fail) throw new IOException("network unavailable");
            return "{\"objects\":[{\"name\":\"杯子\",\"confidence_score\":90}]}";
        }
        public String textJson(String prompt, String model) throws Exception {
            textCalls++; if (fail) throw new IOException("network unavailable");
            return scene ? "{\"intent\":\"info\",\"speech\":\"OK\"}" : "{\"intent\":\"micro_nav\",\"target\":\"杯子\",\"speech\":\"OK\"}";
        }
        public String transcribe(String audio) { return ""; }
    }
    private static final class DetectorBridge implements MnnRuntimeBridge {
        final String language; String lastRole;
        DetectorBridge(String language) { this.language = language; }
        public boolean isAvailable() { return true; }
        public boolean supportsSme2() { return false; }
        public String runtimeSummary() { return "fake detector"; }
        public String visionJson(String dir, String prompt, String image, String role) {
            lastRole = role; return "{\"detections\":[{\"class\":\"cup\",\"score\":0.9,\"box\":[0,180,100,280]}]}";
        }
        public String textJson(String dir, String prompt, String role, String tuning) {
            return "{\"intent\":\"micro_nav\",\"target\":\"" + (language.equals("en") ? "cup" : "コップ") + "\",\"speech\":\"OK\"}";
        }
        public String transcribe(String dir, String audio) { return ""; }
    }
}
