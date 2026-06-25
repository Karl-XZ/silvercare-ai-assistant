package com.silvercare.aiassistant;

import org.junit.Test;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;

public class LocalAsrTextCorrectorTest {
    @Test
    public void parsesCorrectedTextFromLooseJsonResponse() {
        String response = """
            ```json
            {"corrected_text":"帮我找到我的碗","changed":true,"reason":"同音字校正"}
            ```
            """;

        String corrected = LocalAsrTextCorrector.correctedText(response, "帮我找到我的晚");

        assertThat(corrected, equalTo("帮我找到我的碗"));
    }

    @Test
    public void fallsBackWhenModelReturnsOverlongText() {
        String response = "{\"corrected_text\":\"" + "请".repeat(90) + "\"}";

        String corrected = LocalAsrTextCorrector.correctedText(response, "停止");

        assertThat(corrected, equalTo("停止"));
    }

    @Test
    public void fastCorrectHandlesCommonLocalAsrHomophonesWithoutModelCall() {
        assertThat(LocalAsrTextCorrector.fastCorrect("帮我找到我的晚"), equalTo("帮我找到我的碗"));
        assertThat(LocalAsrTextCorrector.fastCorrect("找一下手几"), equalTo("找一下手机"));
        assertThat(LocalAsrTextCorrector.fastCorrect("关闭影导"), equalTo("关闭引导"));
    }

    @Test
    public void fastCorrectDropsAsrContextPromptLeak() {
        assertThat(
            LocalAsrTextCorrector.fastCorrect("银龄智护 盲人导航助手。常见词：找门、找水杯、按电梯上行按钮、巡路、障碍物、跌倒、厨房、办公室。"),
            equalTo("")
        );
    }

    @Test
    public void fastCorrectKeepsTranscriptWhenPromptLeakIsMixedIntoSameText() {
        assertThat(
            LocalAsrTextCorrector.fastCorrect("银龄智护 盲人导航助手。常见词：找门、找水杯、按电梯上行按钮、巡路、障碍物、跌倒、厨房、办公室。你好"),
            equalTo("你好")
        );
    }

    @Test
    public void promptIncludesAsrContextAndRawTranscript() {
        String prompt = LocalAsrTextCorrector.prompt("关闭影导");

        assertThat(prompt, containsString("本地 ASR"));
        assertThat(prompt, containsString("关闭影导"));
        assertThat(prompt, containsString("关闭引导"));
    }
}
