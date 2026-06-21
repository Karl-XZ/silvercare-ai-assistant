package com.silvercare.aiassistant;

import org.junit.Test;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.equalTo;

public class VoskLocalAsrEngineTest {
    @Test
    public void parseTranscriptReadsVoskFinalJson() throws Exception {
        String transcript = VoskLocalAsrEngine.parseTranscript("{\"text\":\"帮 我 找 门\"}");

        assertThat(transcript, equalTo("帮我找门"));
    }

    @Test
    public void normalizeKeepsSpacesForLatinWordsButRemovesChineseCharacterSpacing() {
        String transcript = VoskLocalAsrEngine.normalizeChineseTranscript("银龄智护 帮 我 找 door");

        assertThat(transcript, equalTo("银龄智护帮我找 door"));
    }
}
