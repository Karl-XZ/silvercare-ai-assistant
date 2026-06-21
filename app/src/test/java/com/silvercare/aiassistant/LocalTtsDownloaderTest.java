package com.silvercare.aiassistant;

import org.junit.Test;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.endsWith;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.greaterThan;
import static org.hamcrest.Matchers.lessThan;

public class LocalTtsDownloaderTest {
    @Test
    public void mnnTtsManifestTargetsBertVitsArtifacts() {
        assertThat(LocalTtsDownloader.MNN_TTS_FILES.length, equalTo(23));
        assertThat(LocalTtsDownloader.MNN_TTS_FILES[0].relativePath, equalTo("config.json"));
        assertThat(LocalTtsDownloader.MNN_TTS_FILES[0].url, containsString("bert-vits2-MNN"));
        assertThat(LocalTtsDownloader.MNN_TTS_FILES[0].url, endsWith("config.json"));
        assertThat(
            LocalTtsDownloader.MNN_TTS_FILES[4].relativePath,
            equalTo("common/mnn_models/chinese_bert.mnn.weight")
        );
        assertThat(
            LocalTtsDownloader.MNN_TTS_FILES[6].relativePath,
            equalTo("common/mnn_models/english_bert.mnn.weight")
        );
    }

    @Test
    public void expectedSizeIncludesBertVitsModelAndTextAssets() {
        long expected = 0L;
        for (LocalTtsDownloader.DownloadFile item : LocalTtsDownloader.MNN_TTS_FILES) {
            expected += item.expectedBytes;
        }

        assertThat(LocalTtsDownloader.expectedTotalBytes(), equalTo(expected));
        assertThat(LocalTtsDownloader.expectedTotalBytes(), greaterThan(1_300_000_000L));
        assertThat(LocalTtsDownloader.expectedTotalBytes(), lessThan(1_500_000_000L));
        assertThat(LocalTtsDownloader.humanBytes(LocalTtsDownloader.expectedTotalBytes()), containsString("GB"));
    }
}
