package com.silvercare.aiassistant;

import org.junit.Test;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;

public class MnnLlmTuningProfileTest {
    @Test
    public void defaultsToAutoForUnknownValue() {
        assertThat(MnnLlmTuningProfile.from("missing"), equalTo(MnnLlmTuningProfile.AUTO));
        assertThat(MnnLlmTuningProfile.from(null), equalTo(MnnLlmTuningProfile.AUTO));
    }

    @Test
    public void emitsNativeConfigOnlyWhenSme2IsSupported() {
        assertThat(
            MnnLlmTuningProfile.AUTO.nativeConfigJson(true),
            equalTo("{\"jinja\":{\"context\":{\"enable_thinking\":false}},\"cpu_sme2_neon_division_ratio\":41,\"cpu_sme_core_num\":2}")
        );
        assertThat(
            MnnLlmTuningProfile.AUTO.nativeConfigJson(false),
            equalTo("{\"jinja\":{\"context\":{\"enable_thinking\":false}}}")
        );
        assertThat(
            MnnLlmTuningProfile.MNN_DEFAULT.nativeConfigJson(true),
            equalTo("{\"jinja\":{\"context\":{\"enable_thinking\":false}}}")
        );
    }

    @Test
    public void menuTextExplainsAutomaticFallback() {
        assertThat(MnnLlmTuningProfile.PERFORMANCE.menuText(false), containsString("自动回退"));
        assertThat(MnnLlmTuningProfile.PERFORMANCE.menuText(true), containsString("49"));
    }
}
