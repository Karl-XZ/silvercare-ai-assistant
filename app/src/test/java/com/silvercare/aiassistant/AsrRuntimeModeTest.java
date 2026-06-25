package com.silvercare.aiassistant;

import org.junit.Test;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.equalTo;

public class AsrRuntimeModeTest {
    @Test
    public void parsesExplicitDashScopeMode() {
        AsrRuntimeMode mode = AsrRuntimeMode.from("dashscope");

        assertThat(mode, equalTo(AsrRuntimeMode.DASHSCOPE));
        assertThat(mode.isLocal(), equalTo(false));
        assertThat(mode.label, equalTo("联网 DashScope"));
    }

    @Test
    public void defaultsUnknownValuesToDashScope() {
        AsrRuntimeMode mode = AsrRuntimeMode.from("unknown");

        assertThat(mode, equalTo(AsrRuntimeMode.DASHSCOPE));
        assertThat(mode.isLocal(), equalTo(false));
        assertThat(mode.value, equalTo("dashscope"));
        assertThat(mode.label, equalTo("联网 DashScope"));
    }
}
