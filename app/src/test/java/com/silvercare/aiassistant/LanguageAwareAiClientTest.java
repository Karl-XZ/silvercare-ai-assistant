package com.silvercare.aiassistant;

import java.util.ArrayDeque;
import java.util.Queue;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import static org.junit.Assert.*;

public class LanguageAwareAiClientTest {
    @Test public void repairsRealJapaneseUiQuotationWithoutChangingProtocolOrUserData() throws Exception {
        RawClient raw = new RawClient("ja");
        String source = "画面上部に「联网 DashScope」、下部に「长按提问」と表示されています。";
        raw.vision = new JSONObject().put("speech",source).put("search_target","杯子").put("record_text","王先生：请记录原文").put("transcript","长按という名前").put("name","联网").put("current_goal","杯子").put("target_detected",false).put("distance",0.75).toString();
        raw.text.add("{\"t0\":\"画面上部に「オンライン接続」、下部に「長押しで質問」と表示されています。\"}");
        JSONObject result = new JSONObject(new LanguageAwareAiClient(raw).visionJson("prompt","image","vision"));
        assertEquals("杯子",result.getString("search_target")); assertEquals("杯子",result.getString("current_goal"));
        assertEquals("王先生：请记录原文",result.getString("record_text")); assertEquals("长按という名前",result.getString("transcript"));assertEquals("联网",result.getString("name"));
        assertFalse(result.getBoolean("target_detected"));assertEquals(0.75,result.getDouble("distance"),0);
        assertTrue(result.getString("speech").contains("オンライン接続"));assertFalse(result.getString("speech").contains("联网"));
        assertEquals(1,raw.textCalls);assertEquals(raw.settings.textModel(),raw.lastModel);
        assertTrue(raw.lastPrompt.contains("untrusted data"));assertTrue(raw.lastPrompt.contains("quoted user names"));assertTrue(raw.lastPrompt.contains(source));
    }
    @Test public void englishRepairPreservesChinesePersonalNamesAsInstructed() throws Exception {
        RawClient raw = new RawClient("en");raw.vision="{\"speech\":\"王先生，前方请沿墙走。\",\"record_text\":\"王先生，前方请沿墙走。\"}";
        raw.text.add("```json\n{\"t0\":\"Mr 王先生, walk along the wall ahead.\"}\n```");
        JSONObject result=new JSONObject(new LanguageAwareAiClient(raw).visionJson("p","i","v"));
        assertEquals("Mr 王先生, walk along the wall ahead.",result.getString("speech"));assertEquals("王先生，前方请沿墙走。",result.getString("record_text"));
        assertTrue(raw.lastPrompt.contains("Preserve person names"));
    }
    @Test public void plansRepairOnlyGeneratedFieldsAndPreserveTypes() throws Exception {
        RawClient raw=new RawClient("en");raw.text.add("```json\n[{\"step_id\":1,\"instruction\":\"找到杯子\",\"items\":[\"杯子\"],\"completed\":false}]\n```");raw.text.add("{\"t0\":\"Find the cup\"}");
        JSONArray plan=new JSONArray(new LanguageAwareAiClient(raw).textJson("p","requested-model",256,"end"));
        assertEquals("Find the cup",plan.getJSONObject(0).getString("instruction"));assertEquals("杯子",plan.getJSONObject(0).getJSONArray("items").getString(0));assertFalse(plan.getJSONObject(0).getBoolean("completed"));
        assertEquals(2,raw.textCalls);assertEquals(256,raw.lastBudget);assertEquals("end",raw.lastEnd);
    }
    @Test public void compliantRepliesZhAndAsrDoNotRequestRepair() throws Exception {
        for(String language:new String[]{"ja","en","zh"}) {
            RawClient raw=new RawClient(language);raw.vision=language.equals("ja")?"{\"speech\":\"長押しで質問してください。周囲の状況を確認します。\"}":language.equals("en")?"{\"speech\":\"Hold to ask a question.\"}":"{\"speech\":\"请长按提问。\"}";
            LanguageAwareAiClient client=new LanguageAwareAiClient(raw);assertSame(raw.settings,client.settings());assertEquals(raw.vision,client.visionJson("p","i","v"));assertEquals("请保留识别原文",client.transcribe("audio"));assertEquals(0,raw.textCalls);
        }
    }
    @Test public void invalidJsonRemainsForExistingProcessorFallbackAndLanguageIsCaptured() throws Exception {
        RawClient raw=new RawClient("ja-JP");LanguageAwareAiClient client=new LanguageAwareAiClient(raw);raw.settings.appLanguage="zh";
        raw.vision="not JSON 请长按";assertEquals(raw.vision,client.visionJson("p","i","v"));assertEquals(0,raw.textCalls);
        raw.vision="{\"speech\":\"请长按提问\"}";raw.text.add("{\"t0\":\"長押しで質問してください\"}");
        assertTrue(client.visionJson("p","i","v").contains("長押し"));assertEquals(1,raw.textCalls);
    }
    @Test public void invalidRepairMapsFailClearlyAndNeverRetry() throws Exception {
        for(String invalid:new String[]{"not JSON","{}","{\"t0\":1}","{\"t0\":null}","{\"t0\":\"\"}"}) {
            RawClient raw=new RawClient("ja");raw.vision="{\"speech\":\"请长按提问\"}";raw.text.add(invalid);
            try {new LanguageAwareAiClient(raw).visionJson("p","i","v");fail("Expected repair failure");}catch(IllegalStateException expected){assertTrue(expected.getMessage().contains("回答の言語を修正できませんでした"));}
            assertEquals(1,raw.textCalls);
        }
    }
    @Test public void everyTextOverloadForwardsArgumentsWithoutExtraWorkForEnglish() throws Exception {
        RawClient raw=new RawClient("en");LanguageAwareAiClient client=new LanguageAwareAiClient(raw);
        for(int i=0;i<3;i++)raw.text.add("{\"speech\":\"Ready\"}");
        client.textJson("first","model1");assertEquals("model1",raw.lastModel);
        client.textJson("second","model2",99);assertEquals(99,raw.lastBudget);
        client.textJson("third","model3",77,"stop");assertEquals(77,raw.lastBudget);assertEquals("stop",raw.lastEnd);assertEquals(3,raw.textCalls);
    }
    @Test public void chineseUserAndProtocolFieldsAloneNeverTriggerTranslation() throws Exception {
        RawClient raw=new RawClient("ja");raw.vision="{\"speech\":null,\"s\":7,\"transcript\":\"请长按提问\",\"record_text\":\"王先生\",\"current_goal\":\"杯子\",\"category\":\"hazard\",\"path\":\"/用户/请勿翻译\"}";
        assertEquals(raw.vision,new LanguageAwareAiClient(raw).visionJson("p","i","v"));assertEquals(0,raw.textCalls);
    }
    @Test public void requestFailureHasLocalizedAuthoredMessage() throws Exception {
        RawClient raw=new RawClient("ja");raw.vision="{\"speech\":\"请长按\"}";
        try {new LanguageAwareAiClient(raw).visionJson("p","i","v");fail("Expected request failure");}
        catch(IllegalStateException expected){assertTrue(expected.getMessage().contains("翻訳のリクエストに失敗しました"));}
        assertEquals(1,raw.textCalls);
    }
    private static final class RawClient implements SilverCareArtificialIntelligenceClient {
        final TestFakes.Settings settings=new TestFakes.Settings();final Queue<String> text=new ArrayDeque<>();String vision,lastPrompt,lastModel,lastEnd;int textCalls,lastBudget;
        RawClient(String language){settings.appLanguage=language;}
        public SettingsProvider settings(){return settings;}
        public String visionJson(String prompt,String image,String model){return vision;}
        public String textJson(String prompt,String model){textCalls++;lastPrompt=prompt;lastModel=model;return text.remove();}
        public String textJson(String prompt,String model,int budget){lastBudget=budget;return textJson(prompt,model);}
        public String textJson(String prompt,String model,int budget,String end){lastEnd=end;return textJson(prompt,model,budget);}
        public String transcribe(String audio){return "请保留识别原文";}
    }
}
