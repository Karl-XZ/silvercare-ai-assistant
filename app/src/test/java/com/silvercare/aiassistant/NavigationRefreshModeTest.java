package com.silvercare.aiassistant;

import org.junit.Test;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.equalTo;

public class NavigationRefreshModeTest {
    @Test
    public void unknownValueFallsBackToManual() {
        assertThat(NavigationRefreshMode.from("bad"), equalTo(NavigationRefreshMode.MANUAL));
    }

    @Test
    public void manualModeIsExplicit() {
        assertThat(NavigationRefreshMode.MANUAL.isManual(), equalTo(true));
        assertThat(NavigationRefreshMode.AUTO.isManual(), equalTo(false));
    }
}
