package com.silvercare.aiassistant;

import android.Manifest;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;

import java.io.ByteArrayOutputStream;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** A manual, visible test surface for the same local SenseVoice recognizer used by the main app. */
public final class LocalAsrTestActivity extends android.app.Activity {
    private static final int REQUEST_RECORD_AUDIO = 7101;
    private static final int SAMPLE_RATE = SenseVoiceLocalAsrEngine.SAMPLE_RATE;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private volatile boolean recording;
    private AudioRecord recorder;
    private Button recordButton;
    private TextView status;
    private TextView transcript;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        setTitle("本地语音转文字测试");
        setContentView(buildContent());
        refreshStatus();
    }

    private View buildContent() {
        int padding = dp(22);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setPadding(padding, padding, padding, padding);
        root.setBackgroundColor(Color.rgb(15, 22, 28));

        TextView title = text("本地语音转文字测试", 25, Color.WHITE);
        root.addView(title, fullWidth());
        TextView description = text("使用手机端 SenseVoice 模型。按住下方按钮说话，松开后自动转成文字；录音不会上传。", 16, Color.rgb(194, 211, 218));
        description.setPadding(0, dp(10), 0, dp(22));
        root.addView(description, fullWidth());

        status = text("正在检查模型…", 16, Color.rgb(44, 214, 168));
        root.addView(status, fullWidth());
        transcript = text("识别结果会显示在这里。", 20, Color.WHITE);
        transcript.setGravity(Gravity.CENTER_VERTICAL);
        transcript.setPadding(dp(16), dp(16), dp(16), dp(16));
        transcript.setBackgroundColor(Color.rgb(28, 39, 47));
        LinearLayout.LayoutParams transcriptParams = fullWidth();
        transcriptParams.topMargin = dp(18);
        transcriptParams.height = dp(180);
        root.addView(transcript, transcriptParams);

        recordButton = new Button(this);
        recordButton.setText("按住说话");
        recordButton.setTextSize(20);
        recordButton.setTextColor(Color.rgb(5, 30, 27));
        recordButton.setBackgroundColor(Color.rgb(28, 216, 166));
        recordButton.setOnTouchListener(this::onRecordTouch);
        LinearLayout.LayoutParams buttonParams = fullWidth();
        buttonParams.topMargin = dp(24);
        buttonParams.height = dp(68);
        root.addView(recordButton, buttonParams);
        return root;
    }

    private boolean onRecordTouch(View view, MotionEvent event) {
        if (event.getAction() == MotionEvent.ACTION_DOWN) {
            startRecording();
            return true;
        }
        if (event.getAction() == MotionEvent.ACTION_UP || event.getAction() == MotionEvent.ACTION_CANCEL) {
            stopRecordingAndRecognize();
            return true;
        }
        return true;
    }

    private void refreshStatus() {
        LocalAsrModelStatus model = new LocalAsrModelManager().inspect(this);
        if (model.ready) {
            status.setText("SenseVoice 已就绪，模型运行在本机。\n" + model.modelDir.getAbsolutePath());
            recordButton.setEnabled(true);
        } else {
            status.setText("SenseVoice 模型未下载。请返回设置，选择“语音识别方案”，下载本地模型后再测试。");
            recordButton.setEnabled(false);
        }
    }

    private void startRecording() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[] {Manifest.permission.RECORD_AUDIO}, REQUEST_RECORD_AUDIO);
            return;
        }
        if (recording) return;
        int minBuffer = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
        int buffer = Math.max(minBuffer, SAMPLE_RATE / 2) * 2;
        recorder = new AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, buffer);
        if (recorder.getState() != AudioRecord.STATE_INITIALIZED) {
            status.setText("麦克风初始化失败，请检查麦克风权限。");
            recorder.release();
            recorder = null;
            return;
        }
        recording = true;
        recordButton.setText("正在录音，松开结束");
        transcript.setText("正在听您说话…");
        executor.execute(() -> captureLoop(buffer));
    }

    private void captureLoop(int bufferSize) {
        AudioRecord active = recorder;
        if (active == null) return;
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[bufferSize];
        try {
            active.startRecording();
            while (recording) {
                int read = active.read(buffer, 0, buffer.length);
                if (read > 0) output.write(buffer, 0, read);
            }
        } catch (Exception error) {
            runOnUiThread(() -> status.setText("录音失败：" + error.getMessage()));
        } finally {
            try { active.stop(); } catch (Exception ignored) { }
            active.release();
            if (recorder == active) recorder = null;
            byte[] pcm = output.toByteArray();
            if (pcm.length > 0) recognize(pcm);
        }
    }

    private void stopRecordingAndRecognize() {
        if (!recording) return;
        recording = false;
        runOnUiThread(() -> {
            recordButton.setEnabled(false);
            recordButton.setText("正在识别…");
            status.setText("SenseVoice 正在本地识别…");
        });
    }

    private void recognize(byte[] pcm) {
        long startedAt = SystemClock.elapsedRealtime();
        try (SenseVoiceLocalAsrEngine engine = new SenseVoiceLocalAsrEngine()) {
            LocalAsrModelStatus model = new LocalAsrModelManager().inspect(this);
            String result = engine.transcribePcm(model.modelDir, pcm);
            long elapsed = SystemClock.elapsedRealtime() - startedAt;
            runOnUiThread(() -> {
                transcript.setText(result);
                status.setText("本地识别完成，用时 " + String.format(java.util.Locale.CHINA, "%.2f", elapsed / 1000.0) + " 秒。");
                resetRecordButton();
            });
        } catch (Exception error) {
            runOnUiThread(() -> {
                transcript.setText("未得到有效文字。");
                status.setText("本地识别失败：" + error.getMessage());
                resetRecordButton();
            });
        }
    }

    private void resetRecordButton() { recordButton.setEnabled(true); recordButton.setText("按住说话"); }
    private TextView text(String value, int size, int color) { TextView view = new TextView(this); view.setText(value); view.setTextSize(size); view.setTextColor(color); return view; }
    private LinearLayout.LayoutParams fullWidth() { return new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT); }
    private int dp(int value) { return (int) (value * getResources().getDisplayMetrics().density + 0.5f); }
    @Override public void onRequestPermissionsResult(int request, @NonNull String[] permissions, @NonNull int[] results) { super.onRequestPermissionsResult(request, permissions, results); if (request == REQUEST_RECORD_AUDIO && results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) startRecording(); }
    @Override protected void onDestroy() { recording = false; if (recorder != null) recorder.release(); executor.shutdownNow(); super.onDestroy(); }
}
