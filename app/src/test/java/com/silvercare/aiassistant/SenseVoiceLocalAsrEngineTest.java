package com.silvercare.aiassistant;

import org.junit.Test;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.closeTo;
import static org.hamcrest.Matchers.equalTo;

public class SenseVoiceLocalAsrEngineTest {
    @Test public void normalizesModelOutput() {
        assertThat(SenseVoiceLocalAsrEngine.normalizeTranscript("  帮我  找  碗  "), equalTo("帮我 找 碗"));
    }

    @Test public void convertsPcm16LittleEndianToFloat() {
        float[] samples = SenseVoiceLocalAsrEngine.pcm16ToFloat(new byte[] {0, 0, (byte) 0xff, 0x7f});
        assertThat(samples.length, equalTo(2));
        assertThat((double) samples[0], closeTo(0.0, 0.00001));
        assertThat((double) samples[1], closeTo(0.99997, 0.0001));
    }
}
