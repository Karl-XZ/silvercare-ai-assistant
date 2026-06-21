package com.silvercare.aiassistant;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.File;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.contains;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;

public class OfflineModelManagerTest {
    @Rule
    public TemporaryFolder folder = new TemporaryFolder();

    @Test
    public void inspectReportsMissingRuntimeAndModels() {
        OfflineModelStatus status = new OfflineModelManager().inspect(
            new File(folder.getRoot(), "missing").getAbsolutePath(),
            false
        );

        assertThat(status.ready(), equalTo(false));
        assertThat(status.shortText(), containsString("未就绪"));
        assertThat(status.missing, contains(
            "MNN Native Runtime",
            "模型目录不可读",
            "Qwen3-4B-Instruct-2507-MNN/config.json",
            "DAMO-YOLO .mnn"
        ));
    }

    @Test
    public void inspectAcceptsExpectedOfflineModelLayout() throws Exception {
        File root = folder.newFolder("multimodal_care_models");
        File text = new File(root, "Qwen3-4B-Instruct-2507-MNN");
        assertThat(text.mkdirs(), equalTo(true));
        assertThat(new File(text, "config.json").createNewFile(), equalTo(true));
        assertThat(new File(root, "damo-yolo.mnn").createNewFile(), equalTo(true));

        OfflineModelStatus status = new OfflineModelManager().inspect(root.getAbsolutePath(), true);

        assertThat(status.ready(), equalTo(true));
        assertThat(status.textReady, equalTo(true));
        assertThat(status.yoloReady, equalTo(true));
        assertThat(status.shortText(), equalTo("端侧离线模型已就绪"));
    }

    @Test
    public void inspectAcceptsBackupOnePointFiveBLayout() throws Exception {
        File root = folder.newFolder("multimodal_care_models_15b");
        File text = new File(root, "Qwen2.5-1.5B-Instruct-MNN");
        assertThat(text.mkdirs(), equalTo(true));
        assertThat(new File(text, "config.json").createNewFile(), equalTo(true));
        assertThat(new File(root, "damo-yolo.mnn").createNewFile(), equalTo(true));

        OfflineModelStatus status = new OfflineModelManager().inspect(
            root.getAbsolutePath(),
            OfflineAiClient.TEXT_MODEL_1_5B,
            true
        );

        assertThat(status.ready(), equalTo(true));
        assertThat(status.textModel, equalTo(OfflineAiClient.TEXT_MODEL_1_5B));
        assertThat(status.textReady, equalTo(true));
        assertThat(status.yoloReady, equalTo(true));
        assertThat(status.detailText(), containsString("Qwen2.5-1.5B-Instruct-MNN"));
    }

    @Test
    public void inspectReportsSelectedBackupModelWhenMissing() {
        OfflineModelStatus status = new OfflineModelManager().inspect(
            new File(folder.getRoot(), "missing").getAbsolutePath(),
            OfflineAiClient.TEXT_MODEL_1_5B,
            true
        );

        assertThat(status.ready(), equalTo(false));
        assertThat(status.missing, contains(
            "模型目录不可读",
            "Qwen2.5-1.5B-Instruct-MNN/config.json",
            "DAMO-YOLO .mnn"
        ));
    }
}
