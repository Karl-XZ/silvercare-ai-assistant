package com.silvercare.aiassistant;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Assume;
import org.junit.Test;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;
import static org.junit.Assert.*;

/** Opt-in live round trips. Credentials are test-only and never placed in BuildConfig. */
public class ThreeLanguageCloudLiveTest {
    @Test public void actualProcessorAndVisionRepliesFollowLanguage() throws Exception {
        String key=System.getenv("SILVERCARE_I18N_TEST_KEY");
        Assume.assumeTrue(key!=null&&!key.isBlank());
        Path out=Path.of(System.getenv().getOrDefault("SILVERCARE_I18N_TEST_OUT","build/i18n-live"));
        Files.createDirectories(out);
        Path root=Path.of(System.getProperty("user.dir"));
        if(!Files.exists(root.resolve("docs/images/screen_corridor_walk.jpeg"))) root=root.getParent();
        byte[] image=Files.readAllBytes(root.resolve("docs/images/screen_corridor_walk.jpeg"));
        String imageUrl="data:image/jpeg;base64,"+Base64.getEncoder().encodeToString(image);
        JSONArray evidence=new JSONArray();
        String[] languages={"zh","en","ja"};
        String[] questions={"这张图片中有什么？","Describe what is visible in this image.","この画像に写っているものを説明してください。"};
        for(int i=0;i<languages.length;i++) {
            TestFakes.Settings settings=new TestFakes.Settings(); settings.apiKey=key;settings.appLanguage=languages[i];
            settings.compatibleBaseUrl="https://dashscope.aliyuncs.com/compatible-mode/v1";
            settings.apiBaseUrl="https://dashscope.aliyuncs.com/api/v1";
            TestFakes.Sink sink=new TestFakes.Sink();
            SilverCareProcessor processor=new SilverCareProcessor(new LanguageAwareAiClient(new DashScopeClient(settings)),new MemoryStore(new TestFakes.Preferences()),sink);
            processor.processTextInquiry(imageUrl,questions[i]);
            JSONObject reply=sink.firstOfType("inquiry_result");
            JSONObject row=new JSONObject().put("language",languages[i]).put("request",questions[i]).put("messages",new JSONArray(sink.messages));
            evidence.put(row);
            Files.write(out.resolve("real-processor-vision.json"),evidence.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));
            assertNotNull("Expected a real model reply: "+sink.messages,reply);
            String speech=reply.optString("speech"); assertFalse("Reply should contain speech",speech.isBlank());
            if(languages[i].equals("en")) assertFalse(speech,speech.matches("(?s).*[\\p{IsHan}\\p{InHiragana}\\p{InKatakana}].*"));
            if(languages[i].equals("ja")) {
                assertTrue(speech,speech.matches("(?s).*[\\p{InHiragana}\\p{InKatakana}].*"));
                for(String copiedChinese:new String[]{"联网","长按","请沿","识别","银龄"}) assertFalse("Chinese image label copied into Japanese narration: "+speech,speech.contains(copiedChinese));
            }
            row.put("passed",true);
            Files.write(out.resolve("real-processor-vision.json"),evidence.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));
        }
    }
    @Test public void realProvidersHonorAllThreeLanguages() throws Exception {
        String key = System.getenv("SILVERCARE_I18N_TEST_KEY");
        Assume.assumeTrue("Explicit live test credential required", key != null && !key.isBlank());
        JSONArray evidence = new JSONArray();
        Path out = Path.of(System.getenv().getOrDefault("SILVERCARE_I18N_TEST_OUT", "build/i18n-live"));
        Files.createDirectories(out);
        String[] languages = {"zh", "en", "ja"};
        String[] samples = {"语音导航已准备好。请帮我找一下杯子。", "Voice guidance is ready. Please help me find the cup.", "音声案内の準備ができました。コップを探してください。"};
        for (int i=0;i<languages.length;i++) {
            String language = languages[i];
            TestFakes.Settings settings = new TestFakes.Settings();
            settings.apiKey=key; settings.appLanguage=language;
            settings.compatibleBaseUrl="https://dashscope.aliyuncs.com/compatible-mode/v1";
            settings.apiBaseUrl="https://dashscope.aliyuncs.com/api/v1";
            DashScopeClient client=new DashScopeClient(settings);
            JSONObject row=new JSONObject().put("language",language);
            evidence.put(row);
            try {
                String prompt = "Return only JSON with a speech field: a brief helpful answer about keeping a regular sleep schedule. Write speech entirely in " + AppLanguage.cloudLanguage(language) + ".";
                String raw = client.textJson(prompt,"qwen-plus");
                int start=raw.indexOf('{'),end=raw.lastIndexOf('}');
                String speech=new JSONObject(raw.substring(start,end+1)).getString("speech");
                row.put("model_speech",speech);
                assertFalse(speech.isBlank());
                if(language.equals("en")) assertFalse(speech.matches("(?s).*[\\p{IsHan}\\p{InHiragana}\\p{InKatakana}].*"));
                if(language.equals("ja")) assertTrue(speech.matches("(?s).*[\\p{InHiragana}\\p{InKatakana}].*"));
                String url=client.synthesizeSpeechUrl(samples[i]);
                byte[] audio;
                try(var stream=URI.create(url).toURL().openStream()){ audio=stream.readAllBytes(); }
                assertTrue("Real synthesis must contain audio",audio.length>2000);
                Files.write(out.resolve("tts-"+language+".wav"),audio);
                row.put("tts_audio_bytes",audio.length);
                String transcript=client.transcribe("data:audio/wav;base64,"+Base64.getEncoder().encodeToString(audio));
                row.put("tts_asr_roundtrip",transcript);
                assertFalse(transcript.isBlank());
                if(language.equals("en")) assertTrue(transcript.toLowerCase().contains("cup"));
                if(language.equals("ja")) assertTrue(transcript.contains("コップ"));
                if(language.equals("zh")) assertTrue(transcript.contains("杯"));
                row.put("passed",true);
            } catch(Exception | AssertionError error) {
                row.put("passed",false).put("error",error.toString());
                throw error;
            } finally { Files.write(out.resolve("cloud-language-results.json"),evidence.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8)); }
        }
    }
}
