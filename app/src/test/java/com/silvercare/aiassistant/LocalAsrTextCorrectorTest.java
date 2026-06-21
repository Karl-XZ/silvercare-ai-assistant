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
    public void promptIncludesAsrContextAndRawTranscript() {
        String prompt = LocalAsrTextCorrector.prompt("关闭影导");

        assertThat(prompt, containsString("本地 ASR"));
        assertThat(prompt, containsString("关闭影导"));
        assertThat(prompt, containsString("关闭引导"));
    }
}
