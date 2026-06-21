package com.silvercare.aiassistant;

import org.junit.Test;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.equalTo;

public class TtsRuntimeModeTest {
    @Test
    public void unknownValueFallsBackToAuto() {
        assertThat(TtsRuntimeMode.from("bad"), equalTo(TtsRuntimeMode.AUTO));
    }

    @Test
    public void autoUsesSystemAndDashScopeFallbackOnly() {
        assertThat(TtsRuntimeMode.AUTO.allowsLocal(), equalTo(false));
        assertThat(TtsRuntimeMode.AUTO.allowsSystem(), equalTo(true));
        assertThat(TtsRuntimeMode.AUTO.allowsDashScope(), equalTo(true));
    }

    @Test
    public void explicitLocalMnnDisablesOtherEnginesAsPrimary() {
        assertThat(TtsRuntimeMode.LOCAL_MNN.allowsLocal(), equalTo(true));
        assertThat(TtsRuntimeMode.LOCAL_MNN.allowsSystem(), equalTo(false));
        assertThat(TtsRuntimeMode.LOCAL_MNN.allowsDashScope(), equalTo(false));
    }

    @Test
    public void legacyLocalQwenValueMapsToLocalMnn() {
        assertThat(TtsRuntimeMode.from("local_qwen"), equalTo(TtsRuntimeMode.LOCAL_MNN));
    }

    @Test
    public void explicitSystemDisablesDashScopeFallback() {
        assertThat(TtsRuntimeMode.SYSTEM.allowsLocal(), equalTo(false));
        assertThat(TtsRuntimeMode.SYSTEM.allowsSystem(), equalTo(true));
        assertThat(TtsRuntimeMode.SYSTEM.allowsDashScope(), equalTo(false));
    }

    @Test
    public void explicitDashScopeDoesNotRequireSystemTts() {
        assertThat(TtsRuntimeMode.DASHSCOPE.allowsLocal(), equalTo(false));
        assertThat(TtsRuntimeMode.DASHSCOPE.allowsSystem(), equalTo(false));
        assertThat(TtsRuntimeMode.DASHSCOPE.allowsDashScope(), equalTo(true));
    }
}
