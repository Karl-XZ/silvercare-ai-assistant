package com.silvercare.aiassistant;

import org.json.JSONObject;
import org.junit.Assume;
import org.junit.Test;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Base64;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.startsWith;

public class DashScopeLiveIntegrationTest {
    @Test
    public void qwenVisionCanReadUserPowerStripFixture() throws Exception {
        Assume.assumeTrue(
            "Live DashScope tests are opt-in. Run with -Dsilvercare.liveDashScope=true.",
            Boolean.getBoolean("silvercare.liveDashScope")
        );

        String key = System.getProperty("DASHSCOPE_API_KEY", System.getenv("DASHSCOPE_API_KEY"));
        Assume.assumeTrue("DASHSCOPE_API_KEY is required for live tests.", key != null && !key.trim().isEmpty());

        TestFakes.Settings settings = new TestFakes.Settings();
        settings.apiKey = key;
        settings.compatibleBaseUrl = "https://dashscope.aliyuncs.com/compatible-mode/v1";
        settings.apiBaseUrl = "https://dashscope.aliyuncs.com/api/v1";
        DashScopeClient client = new DashScopeClient(settings);

        String result = client.visionJson(
            """
            这是一张用户自摄真实照片。请判断画面中是否有插排、电源线或插座。只返回 JSON：
            {"contains_power_strip":true,"main_object":"插排或电源线"}
            如果你没有看到插排、电源线或插座，就把 contains_power_strip 设为 false。
            """,
            realWorldFixtureDataUrl("user_table_power_plug.jpg"),
            settings.visionModel()
        );

        JSONObject json = new JSONObject(result);
        assertThat(json.getBoolean("contains_power_strip"), equalTo(true));
    }

    @Test
    public void qwenTtsCanSynthesizeChineseSafetyPrompt() throws Exception {
        Assume.assumeTrue(
            "Live DashScope tests are opt-in. Run with -Dsilvercare.liveDashScope=true.",
            Boolean.getBoolean("silvercare.liveDashScope")
        );

        String key = System.getProperty("DASHSCOPE_API_KEY", System.getenv("DASHSCOPE_API_KEY"));
        Assume.assumeTrue("DASHSCOPE_API_KEY is required for live tests.", key != null && !key.trim().isEmpty());

        TestFakes.Settings settings = new TestFakes.Settings();
        settings.apiKey = key;
        settings.apiBaseUrl = "https://dashscope.aliyuncs.com/api/v1";
        DashScopeClient client = new DashScopeClient(settings);

        String audioUrl = client.synthesizeSpeechUrl("前方安全，请保持慢速直行。");

        assertThat(audioUrl, startsWith("http"));
    }

    private static String realWorldFixtureDataUrl(String fileName) throws Exception {
        Path cwd = Paths.get(System.getProperty("user.dir"));
        Path[] candidates = new Path[] {
            cwd.resolve("test_runs").resolve("fixtures").resolve("real_world_images").resolve(fileName),
            cwd.resolve("..").resolve("test_runs").resolve("fixtures").resolve("real_world_images").resolve(fileName),
            cwd.resolve("..").resolve("..").resolve("test_runs").resolve("fixtures").resolve("real_world_images").resolve(fileName)
        };
        for (Path candidate : candidates) {
            Path normalized = candidate.normalize();
            if (Files.exists(normalized)) {
                return "data:image/jpeg;base64," + Base64.getEncoder().encodeToString(Files.readAllBytes(normalized));
            }
        }
        throw new IllegalStateException("Missing real-world image fixture: " + fileName);
    }
}
