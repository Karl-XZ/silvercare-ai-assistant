package com.silvercare.aiassistant;

import org.junit.Test;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.greaterThan;

public class LocalAsrDownloaderTest {
    @Test
    public void senseVoiceManifestUsesOfficialReleaseUrl() {
        assertThat(LocalAsrDownloader.SENSEVOICE_ARCHIVE_URL, containsString("github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/"));
        assertThat(LocalAsrDownloader.SENSEVOICE_ARCHIVE_URL, containsString("sense-voice"));
        assertThat(LocalAsrDownloader.expectedTotalBytes(), equalTo(LocalAsrDownloader.SENSEVOICE_ARCHIVE_BYTES));
        assertThat(LocalAsrDownloader.SENSEVOICE_ARCHIVE_BYTES, greaterThan(150L * 1024L * 1024L));
    }

    @Test
    public void formatsModelDownloadSizeForSettingsCopy() {
        assertThat(LocalAsrDownloader.humanBytes(LocalAsrDownloader.SENSEVOICE_ARCHIVE_BYTES), containsString("MB"));
    }
}
