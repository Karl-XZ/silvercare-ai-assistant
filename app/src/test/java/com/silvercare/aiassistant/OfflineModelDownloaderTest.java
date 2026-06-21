package com.silvercare.aiassistant;

import org.junit.Test;

import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.endsWith;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.greaterThan;

public class OfflineModelDownloaderTest {
    @Test
    public void qwen4BManifestContainsRequiredMnnFilesOnly() {
        List<String> paths = Arrays.stream(OfflineModelDownloader.QWEN4B_FILES)
            .map(item -> item.relativePath)
            .collect(Collectors.toList());

        assertThat(paths, containsInAnyOrder(
            "Qwen3-4B-Instruct-2507-MNN/config.json",
            "Qwen3-4B-Instruct-2507-MNN/llm.mnn",
            "Qwen3-4B-Instruct-2507-MNN/llm.mnn.json",
            "Qwen3-4B-Instruct-2507-MNN/llm.mnn.weight",
            "Qwen3-4B-Instruct-2507-MNN/llm_config.json",
            "Qwen3-4B-Instruct-2507-MNN/tokenizer.txt"
        ));
    }

    @Test
    public void qwen4BManifestUsesDirectHuggingFaceResolveUrls() {
        for (OfflineModelDownloader.DownloadFile item : OfflineModelDownloader.QWEN4B_FILES) {
            assertThat(item.urls.length, equalTo(1));
            assertThat(item.urls[0], endsWith(item.relativePath.substring(OfflineModelDownloader.QWEN4B_DIR.length() + 1)));
            assertThat(item.expectedBytes, greaterThan(0L));
        }
    }

    @Test
    public void expectedTotalIncludesBundledDetectorAndQwenFiles() {
        long expected = OfflineModelDownloader.BUNDLED_DETECTOR_BYTES;
        for (OfflineModelDownloader.DownloadFile item : OfflineModelDownloader.QWEN4B_FILES) {
            expected += item.expectedBytes;
        }

        assertThat(OfflineModelDownloader.expectedTotalBytes(), equalTo(expected));
        assertThat(OfflineModelDownloader.BUNDLED_DETECTOR_FILE, equalTo("damo-yolo.mnn"));
    }
}
