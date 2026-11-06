package com.silvercare.aiassistant;

import android.app.Activity;
import android.os.Bundle;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.widget.TextView;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.Locale;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/** Debug-only real audio/locale probe; never included in release builds. */
public final class LanguageValidationActivity extends Activity {
    private final JSONArray results = new JSONArray();
    private TextToSpeech engine;
    private TextView status;
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        status = new TextView(this); status.setText("Running local language validation"); setContentView(status);
        Executors.newSingleThreadExecutor().execute(this::runChecks);
    }
    private void runChecks() {
        try {
            File root = new File(getFilesDir(), "language-validation");
            File model = new File(root, LocalAsrModelManager.SENSEVOICE_MODEL_DIR);
            // Reuse one engine across switches: exercises recognizer language cache invalidation.
            try (SenseVoiceLocalAsrEngine asr = new SenseVoiceLocalAsrEngine()) {
                for (String language : new String[]{"zh", "en", "ja", "en"}) {
                    JSONObject check = new JSONObject().put("kind", "real_local_asr").put("language", language);
                    long start = System.currentTimeMillis();
                    try {
                        byte[] wave = Files.readAllBytes(new File(root, language + ".wav").toPath());
                        byte[] pcm = pcm(wave);
                        String text = asr.transcribePcm(model, pcm, language);
                        check.put("text", text).put("nonempty", !text.isBlank());
                    } catch (Exception error) { check.put("error", error.toString()); }
                    check.put("elapsed_ms", System.currentTimeMillis()-start); results.put(check); save();
                }
            }
            CountDownLatch initialized = new CountDownLatch(1);
            engine = new TextToSpeech(this, code -> initialized.countDown());
            boolean init = initialized.await(30, TimeUnit.SECONDS);
            for (String language : new String[]{"zh", "en", "ja"}) {
                JSONObject check = new JSONObject().put("kind", "real_system_tts").put("language", language);
                Locale locale = AppLanguage.locale(language);
                int availability = init ? engine.isLanguageAvailable(locale) : TextToSpeech.LANG_NOT_SUPPORTED;
                check.put("availability", availability).put("requested_locale", locale.toLanguageTag());
                if (availability >= 0) {
                    int selected = engine.setLanguage(locale);
                    check.put("set_result", selected).put("selected_locale", engine.getVoice() == null ? "" : engine.getVoice().getLocale().toLanguageTag());
                    File audio = new File(root, "tts-"+language+".wav");
                    CountDownLatch spoken = new CountDownLatch(1);
                    engine.setOnUtteranceProgressListener(new UtteranceProgressListener() {
                        @Override public void onStart(String id) { }
                        @Override public void onDone(String id) { spoken.countDown(); }
                        @Override public void onError(String id) { spoken.countDown(); }
                    });
                    String text = language.equals("ja") ? "音声案内の準備ができました。前方を確認します。" : language.equals("en") ? "Voice guidance is ready. I will check the area ahead." : "语音导航已准备好，正在查看前方。";
                    check.put("submitted", engine.synthesizeToFile(text, new Bundle(), audio, "validation-"+language));
                    check.put("completed", spoken.await(35, TimeUnit.SECONDS)).put("audio_bytes", audio.length());
                }
                results.put(check); save();
            }
        } catch (Exception error) {
            try { results.put(new JSONObject().put("fatal", error.toString())); } catch (Exception ignored) { }
        } finally {
            if (engine != null) engine.shutdown(); save();
            runOnUiThread(() -> status.setText(results.toString()));
        }
    }
    private static byte[] pcm(byte[] wave) {
        if(wave.length < 44 || !new String(wave,0,4,StandardCharsets.US_ASCII).equals("RIFF")) throw new IllegalArgumentException("Not a RIFF WAV");
        for(int offset=12;offset+8<=wave.length;) {
            int size=(wave[offset+4]&255)|((wave[offset+5]&255)<<8)|((wave[offset+6]&255)<<16)|((wave[offset+7]&255)<<24);
            if(size < 0 || offset+8L+size > wave.length) throw new IllegalArgumentException("Invalid WAV chunk");
            if(new String(wave,offset,4,StandardCharsets.US_ASCII).equals("data")) return Arrays.copyOfRange(wave,offset+8,offset+8+size);
            offset+=8+size+(size&1);
        }
        throw new IllegalArgumentException("WAV data missing");
    }
    private void save() {
        try { Files.write(new File(getFilesDir(), "language-validation.json").toPath(), results.toString(2).getBytes(StandardCharsets.UTF_8)); }
        catch (Exception ignored) { }
    }
}
