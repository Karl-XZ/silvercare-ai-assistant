package com.silvercare.aiassistant;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.File;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;

public class LocalAsrModelManagerTest {
    @Rule
    public TemporaryFolder folder = new TemporaryFolder();

    @Test
    public void inspectReportsMissingModelFiles() throws Exception {
        File root = folder.newFolder("asr");

        LocalAsrModelStatus status = new LocalAsrModelManager().inspect(root);

        assertThat(status.ready, equalTo(false));
        assertThat(status.shortText(), containsString("本地语音识别模型未就绪"));
        assertThat(status.shortText(), containsString(LocalAsrModelManager.VOSK_CN_MODEL_DIR));
    }

    @Test
    public void inspectAcceptsVoskChineseModelLayout() throws Exception {
        File root = folder.newFolder("asr");
        File model = new File(root, LocalAsrModelManager.VOSK_CN_MODEL_DIR);
        assertThat(new File(model, "am").mkdirs(), equalTo(true));
        assertThat(new File(model, "conf").mkdirs(), equalTo(true));
        assertThat(new File(model, "graph").mkdirs(), equalTo(true));
        assertThat(new File(model, "ivector").mkdirs(), equalTo(true));
        assertThat(new File(model, "am/final.mdl").createNewFile(), equalTo(true));
        assertThat(new File(model, "conf/model.conf").createNewFile(), equalTo(true));
        assertThat(new File(model, "graph/HCLr.fst").createNewFile(), equalTo(true));
        assertThat(new File(model, "graph/Gr.fst").createNewFile(), equalTo(true));
        assertThat(new File(model, "ivector/final.ie").createNewFile(), equalTo(true));

        LocalAsrModelStatus status = new LocalAsrModelManager().inspect(root);

        assertThat(status.ready, equalTo(true));
        assertThat(status.modelDir.getName(), equalTo(LocalAsrModelManager.VOSK_CN_MODEL_DIR));
        assertThat(status.shortText(), equalTo("本地语音识别模型已就绪"));
    }
}
