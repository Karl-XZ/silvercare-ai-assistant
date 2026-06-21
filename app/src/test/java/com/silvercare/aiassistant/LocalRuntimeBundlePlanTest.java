package com.silvercare.aiassistant;

import org.junit.Test;

import java.io.File;
import java.util.Collections;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;

public class LocalRuntimeBundlePlanTest {
    @Test
    public void readyModelsDoNotRequireDownloads() {
        LocalRuntimeBundlePlan plan = LocalRuntimeBundlePlan.from(
            offlineStatus(true, true, true),
            asrStatus(true),
            ttsStatus(true, true)
        );

        assertThat(plan.hasDownloads(), equalTo(false));
        assertThat(plan.downloadBytes, equalTo(0L));
        assertThat(plan.downloadSummaryText(), containsString("未发现需要下载"));
    }

    @Test
    public void missingModelsAreSummedAcrossAiAsrAndTts() {
        LocalRuntimeBundlePlan plan = LocalRuntimeBundlePlan.from(
            offlineStatus(true, false, false),
            asrStatus(false),
            ttsStatus(false, false)
        );

        long expected = OfflineModelDownloader.expectedTotalBytes()
            + LocalAsrDownloader.expectedTotalBytes();
        assertThat(plan.hasDownloads(), equalTo(true));
        assertThat(plan.downloadBytes, equalTo(expected));
        assertThat(plan.downloadSummaryText(), containsString("Qwen3-4B"));
        assertThat(plan.downloadSummaryText(), containsString("本地 ASR"));
    }

    @Test
    public void nativeRuntimeIssuesAreWarningsNotDownloads() {
        LocalRuntimeBundlePlan plan = LocalRuntimeBundlePlan.from(
            offlineStatus(false, true, true),
            asrStatus(true),
            ttsStatus(true, false)
        );

        assertThat(plan.hasDownloads(), equalTo(false));
        assertThat(plan.runtimeWarningText(), containsString("MNN Native Runtime"));
    }

    private static OfflineModelStatus offlineStatus(
        boolean nativeRuntimeAvailable,
        boolean textReady,
        boolean yoloReady
    ) {
        return new OfflineModelStatus(
            "/tmp/multimodal_care_models",
            OfflineAiClient.TEXT_MODEL_4B,
            textReady ? new File("/tmp/config.json") : null,
            yoloReady ? new File("/tmp/damo-yolo.mnn") : null,
            nativeRuntimeAvailable,
            true,
            textReady,
            yoloReady,
            Collections.emptyList()
        );
    }

    private static LocalAsrModelStatus asrStatus(boolean ready) {
        return new LocalAsrModelStatus(
            new File("/tmp/asr"),
            new File("/tmp/asr/vosk"),
            true,
            ready,
            ready ? Collections.emptyList() : Collections.singletonList("vosk")
        );
    }

    private static LocalTtsModelStatus ttsStatus(boolean modelReady, boolean runtimeAvailable) {
        return new LocalTtsModelStatus(
            new File("/tmp/tts"),
            new File("/tmp/tts/bert-vits2-mnn"),
            runtimeAvailable,
            runtimeAvailable ? "mnn-tts-test" : "runtime missing",
            true,
            modelReady,
            modelReady ? Collections.emptyList() : Collections.singletonList("bert-vits2-mnn")
        );
    }
}
