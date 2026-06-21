package com.silvercare.aiassistant;

import org.json.JSONObject;
import org.junit.Test;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;
import static org.junit.Assert.fail;

public class DashScopeClientTest {
    @Test
    public void visionJsonBuildsOpenAiCompatiblePayloadAndParsesContent() throws Exception {
        TestFakes.Settings settings = new TestFakes.Settings();
        settings.apiKey = "unit-test-key";
        settings.compatibleBaseUrl = "https://example.test/compatible";
        RecordingTransport transport = new RecordingTransport(chatResponse("{\"ok\":true,\"source\":\"unit\"}"));
        DashScopeClient client = new DashScopeClient(settings, transport);

        String content = client.visionJson(
            "识别红色方块，返回 JSON",
            "data:image/png;base64,abc",
            "qwen3-vl-flash"
        );

        JSONObject parsed = new JSONObject(content);
        assertThat(transport.endpoint, equalTo("https://example.test/compatible/chat/completions"));
        assertThat(transport.apiKey, equalTo("unit-test-key"));
        assertThat(transport.payload.getString("model"), equalTo("qwen3-vl-flash"));
        assertThat(transport.payload.getJSONObject("response_format").getString("type"), equalTo("json_object"));
        assertThat(transport.payload.toString(), containsString("data:image/png;base64,abc"));
        assertThat(parsed.getBoolean("ok"), equalTo(true));
    }

    @Test
    public void textJsonBuildsTextPayloadWithoutJsonResponseFormat() throws Exception {
        TestFakes.Settings settings = new TestFakes.Settings();
        settings.compatibleBaseUrl = "https://example.test/compatible";
        RecordingTransport transport = new RecordingTransport(chatResponse("任务计划"));
        DashScopeClient client = new DashScopeClient(settings, transport);

        client.textJson("生成任务计划", "qwen-plus");

        assertThat(transport.endpoint, equalTo("https://example.test/compatible/chat/completions"));
        assertThat(transport.payload.getString("model"), equalTo("qwen-plus"));
        assertThat(transport.payload.has("response_format"), equalTo(false));
        assertThat(transport.payload.toString(), containsString("生成任务计划"));
    }

    @Test
    public void transcribeBuildsNativeMultimodalPayloadAndParsesText() throws Exception {
        TestFakes.Settings settings = new TestFakes.Settings();
        settings.apiBaseUrl = "https://example.test/api";
        RecordingTransport transport = new RecordingTransport(new JSONObject("""
            {"output":{"choices":[{"message":{"content":[{"text":"请帮我找门"}]}}]}}
            """));
        DashScopeClient client = new DashScopeClient(settings, transport);

        String transcript = client.transcribe("data:audio/webm;base64,abc");

        assertThat(transport.endpoint, equalTo("https://example.test/api/services/aigc/multimodal-generation/generation"));
        assertThat(transport.payload.getString("model"), equalTo("qwen3-asr-flash"));
        assertThat(transport.payload.toString(), containsString("data:audio/webm;base64,abc"));
        assertThat(transport.payload.toString(), containsString("\"language\":\"zh\""));
        assertThat(transport.payload.toString(), containsString("银龄智护"));
        assertThat(transcript, equalTo("请帮我找门"));
    }

    @Test
    public void synthesizeSpeechBuildsQwenTtsPayloadAndParsesAudioUrl() throws Exception {
        TestFakes.Settings settings = new TestFakes.Settings();
        settings.apiBaseUrl = "https://example.test/api";
        RecordingTransport transport = new RecordingTransport(new JSONObject("""
            {"output":{"audio":{"url":"https://example.test/audio.wav"}}}
            """));
        DashScopeClient client = new DashScopeClient(settings, transport);

        String audioUrl = client.synthesizeSpeechUrl("前方有障碍物，请向左绕行。");

        assertThat(transport.endpoint, equalTo("https://example.test/api/services/aigc/multimodal-generation/generation"));
        assertThat(transport.payload.getString("model"), equalTo("qwen3-tts-flash"));
        assertThat(transport.payload.toString(), containsString("前方有障碍物"));
        assertThat(transport.payload.toString(), containsString("\"voice\":\"Cherry\""));
        assertThat(transport.payload.toString(), containsString("\"language_type\":\"Chinese\""));
        assertThat(audioUrl, equalTo("https://example.test/audio.wav"));
    }

    @Test
    public void missingApiKeyThrowsBeforeTransportCall() throws Exception {
        TestFakes.Settings settings = new TestFakes.Settings();
        settings.apiKey = "";
        RecordingTransport transport = new RecordingTransport(chatResponse("unused"));
        DashScopeClient client = new DashScopeClient(settings, transport);

        try {
            client.textJson("hello", "qwen-plus");
            fail("Expected missing key to throw");
        } catch (IllegalStateException expected) {
            assertThat(expected.getMessage(), containsString("DashScope Key"));
            assertThat(transport.called, equalTo(false));
        }
    }

    private static JSONObject chatResponse(String content) throws Exception {
        return new JSONObject()
            .put("choices", new org.json.JSONArray()
                .put(new JSONObject()
                    .put("message", new JSONObject()
                        .put("content", content))));
    }

    private static final class RecordingTransport implements DashScopeClient.JsonTransport {
        private final JSONObject response;
        String endpoint;
        JSONObject payload;
        String apiKey;
        boolean called;

        RecordingTransport(JSONObject response) {
            this.response = response;
        }

        @Override
        public JSONObject postJson(String endpoint, JSONObject payload, String apiKey) {
            this.called = true;
            this.endpoint = endpoint;
            this.payload = payload;
            this.apiKey = apiKey;
            return response;
        }
    }
}
