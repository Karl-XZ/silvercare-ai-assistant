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
    @Test
    public void recallLabelsHistoricalEvidenceAndDoesNotClaimCurrentLocation() {
        for (String language : new String[]{"zh", "en", "ja"}) {
            TestFakes.Preferences preferences = new TestFakes.Preferences();
            MemoryStore store = new MemoryStore(preferences);
            store.logObject("cup", "Kitchen shelf", "Original scene 原文。");
            String original = preferences.getString("history_json", "");
            String expected = "zh".equals(language)
                ? "cup上次看到的位置是：Kitchen shelf，Original scene 原文。（这是历史记录，当前位置尚未确认。）"
                : "en".equals(language)
                    ? "cup was last seen at: Kitchen shelf, Original scene 原文。 (This is a historical record; the current location has not been confirmed.)"
                    : "cupが最後に見つかった場所：Kitchen shelf、Original scene 原文。（これは過去の記録で、現在の場所は確認できていません。）";
            assertThat(store.findObjectLocation("杯子", language), equalTo(expected));
            assertThat(preferences.getString("history_json", ""), equalTo(original));
        }
    }
}
