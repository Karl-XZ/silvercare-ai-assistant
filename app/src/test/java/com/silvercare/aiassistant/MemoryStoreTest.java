package com.silvercare.aiassistant;

import org.junit.Test;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.containsString;

public class MemoryStoreTest {
    @Test
    public void addLocationIncludesLocationInSummary() {
        MemoryStore store = new MemoryStore(new TestFakes.Preferences());

        store.addLocation("家门口", "白色门，旁边有鞋柜");

        assertThat(store.locationSummary(), containsString("家门口"));
        assertThat(store.locationSummary(), containsString("鞋柜"));
    }

    @Test
    public void logObjectDeduplicatesImmediateRepeatedObject() {
        MemoryStore store = new MemoryStore(new TestFakes.Preferences());

        store.logObject("杯子", "桌面", "木桌上有杯子");
        store.logObject("杯子", "桌面", "木桌上有杯子");

        String history = store.historyContext();
        assertThat(history, containsString("杯子"));
        assertThat(history.split("\\R").length, equalTo(1));
    }
}
