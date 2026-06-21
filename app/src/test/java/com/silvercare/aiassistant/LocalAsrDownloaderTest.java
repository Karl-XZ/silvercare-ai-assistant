package com.silvercare.aiassistant;

import org.junit.Test;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.greaterThan;

public class LocalAsrDownloaderTest {
    @Test
    public void chineseAsrManifestUsesDirectVoskModelUrl() {
        assertThat(LocalAsrDownloader.VOSK_CN_ZIP_URL, containsString("alphacephei.com/vosk/models/"));
        assertThat(LocalAsrDownloader.VOSK_CN_ZIP_URL, containsString(LocalAsrModelManager.VOSK_CN_MODEL_DIR));
        assertThat(LocalAsrDownloader.expectedTotalBytes(), equalTo(LocalAsrDownloader.VOSK_CN_ZIP_BYTES));
        assertThat(LocalAsrDownloader.VOSK_CN_ZIP_BYTES, greaterThan(40L * 1024L * 1024L));
    }

    @Test
    public void formatsModelDownloadSizeForSettingsCopy() {
        assertThat(LocalAsrDownloader.humanBytes(LocalAsrDownloader.VOSK_CN_ZIP_BYTES), containsString("MB"));
    }
}
