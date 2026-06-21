package com.silvercare.aiassistant;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.File;
import java.io.FileOutputStream;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;

public class LocalTtsModelManagerTest {
    @Rule
    public TemporaryFolder folder = new TemporaryFolder();

    private static final LocalTtsDownloader.DownloadFile[] SMALL_REQUIRED_FILES =
        new LocalTtsDownloader.DownloadFile[] {
            new LocalTtsDownloader.DownloadFile("config.json", 3L, "https://example.test/config.json"),
            new LocalTtsDownloader.DownloadFile("common/mnn_models/chinese_bert.mnn", 5L, "https://example.test/chinese_bert.mnn")
        };

    @Test
    public void inspectReportsMissingModelFiles() throws Exception {
        File root = folder.newFolder("tts");

        LocalTtsModelStatus status = new LocalTtsModelManager()
            .inspect(root, false, "runtime missing", SMALL_REQUIRED_FILES);

        assertThat(status.ready, equalTo(false));
        assertThat(status.modelReady, equalTo(false));
        assertThat(status.runtimeAvailable, equalTo(false));
        assertThat(status.shortText(), containsString("本地 MNN TTS 未就绪"));
        assertThat(status.shortText(), containsString(LocalTtsModelManager.MNN_TTS_DIR));
    }

    @Test
    public void modelCanBeReadyWhileRuntimeIsMissing() throws Exception {
        File root = createSmallReadyModel();

        LocalTtsModelStatus status = new LocalTtsModelManager()
            .inspect(root, false, "未加载 mnn_tts", SMALL_REQUIRED_FILES);

        assertThat(status.modelReady, equalTo(true));
        assertThat(status.runtimeAvailable, equalTo(false));
        assertThat(status.ready, equalTo(false));
        assertThat(status.shortText(), containsString("Native Runtime 不可用"));
    }

    @Test
    public void inspectAcceptsCompleteModelAndRuntime() throws Exception {
        File root = createSmallReadyModel();

        LocalTtsModelStatus status = new LocalTtsModelManager()
            .inspect(root, true, "mnn-tts-test", SMALL_REQUIRED_FILES);

        assertThat(status.modelReady, equalTo(true));
        assertThat(status.runtimeAvailable, equalTo(true));
        assertThat(status.ready, equalTo(true));
        assertThat(status.shortText(), equalTo("本地 MNN TTS 已就绪"));
    }

    private File createSmallReadyModel() throws Exception {
        File root = folder.newFolder("tts");
        File model = new File(root, LocalTtsModelManager.MNN_TTS_DIR);
        assertThat(model.mkdirs(), equalTo(true));
        for (LocalTtsDownloader.DownloadFile item : SMALL_REQUIRED_FILES) {
            File target = new File(model, item.relativePath);
            File parent = target.getParentFile();
            if (parent != null && !parent.isDirectory()) {
                assertThat(parent.mkdirs(), equalTo(true));
            }
            try (FileOutputStream output = new FileOutputStream(target)) {
                for (int i = 0; i < item.expectedBytes; i += 1) {
                    output.write('x');
                }
            }
        }
        return root;
    }
}
