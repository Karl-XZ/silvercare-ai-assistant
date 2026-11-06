package com.silvercare.aiassistant;
import org.json.JSONObject;
import org.junit.Test;
import static org.junit.Assert.*;
public class BackendLanguageTest {
 @Test public void offlineSearchAndStopUseSelectedLanguageAndCanonicalTargets() {
  for (String language : new String[]{"en","ja"}) {
   TestFakes.AiClient ai = new TestFakes.AiClient(); ai.settings.appLanguage=language; ai.settings.aiRuntimeMode="offline_mnn";
   TestFakes.Sink sink=new TestFakes.Sink();
   SilverCareProcessor p=new SilverCareProcessor(ai,new MemoryStore(new TestFakes.Preferences()),sink);
   String input=language.equals("en")?"Please find my cup":"私のコップを探して";
   p.processTextInquiry("",input);
   JSONObject r=sink.firstOfType("inquiry_result");
   assertEquals("search",r.optString("intent")); assertEquals(language.equals("en")?"cup":"コップ",r.optString("current_goal"));
   assertEquals(input,r.optString("transcript"));
   assertTrue(r.optString("speech"),r.optString("speech").contains(language.equals("en")?"cup":"コップ"));
   assertFalse(r.optString("speech").contains("寻找"));
   p.processTextInquiry("",language.equals("en")?"stop searching":"検索をやめて");
   assertTrue(ai.textResponses.isEmpty());
  }
 }
 @Test public void selectedLanguagePromptsPreserveUserRequest() {
  for(String language:new String[]{"en","ja"}) {
   TestFakes.AiClient ai=new TestFakes.AiClient(); ai.settings.appLanguage=language;
   ai.visionResponses.add("{\"intent\":\"info\",\"speech\":\"OK\"}");
   SilverCareProcessor p=new SilverCareProcessor(ai,new MemoryStore(new TestFakes.Preferences()),new TestFakes.Sink());
   String input="Remember my name: 王先生";p.processTextInquiry("",input);
   assertTrue(ai.lastVisionPrompt.contains(input));
   assertTrue(ai.lastVisionPrompt.contains(language.equals("en")?"English":"Japanese"));
   assertFalse(ai.lastVisionPrompt.contains("must be Simplified Chinese"));
  }
 }
 @Test public void targetLabelsAreLocalizedWithoutChangingCanonicalClasses() {
  assertEquals("杯子",OfflineVisionInterpreter.canonicalSearchTarget("コップ"));
  assertEquals("cup",OfflineVisionInterpreter.localizeObjectName("杯子","en"));
  assertEquals("椅子",OfflineVisionInterpreter.localizeObjectName("chair","ja"));
 }
 @Test public void capabilityNavigationAndTaskControlsWorkInBothLanguages() {
  for(String lang:new String[]{"en","ja"}) {
   TestFakes.AiClient ai=new TestFakes.AiClient(); ai.settings.appLanguage=lang;ai.settings.aiRuntimeMode="offline_mnn";
   TestFakes.Sink sink=new TestFakes.Sink();SilverCareProcessor p=new SilverCareProcessor(ai,new MemoryStore(new TestFakes.Preferences()),sink);
   p.processTextInquiry("",lang.equals("en")?"What can you do?":"何ができますか");
   assertTrue(sink.firstOfType("inquiry_result").optString("speech").contains(lang.equals("en")?"hazards":"危険"));
   sink.messages.clear();p.processTextInquiry("",lang.equals("en")?"Is it safe to walk ahead?":"前方は安全に歩けますか");
   assertEquals("nav_check",sink.firstOfType("inquiry_result").optString("intent"));
   sink.messages.clear();ai.textResponses.add("{\"intent\":\"task\",\"task_name\":\"My 王先生 task\",\"speech\":\"OK\"}");
   ai.textResponses.add("[{\"step_id\":1,\"instruction\":\"first\",\"completed\":false},{\"step_id\":2,\"instruction\":\"second\",\"completed\":false},{\"step_id\":3,\"instruction\":\"third\",\"completed\":false}]");
   p.processTextInquiry("",lang.equals("en")?"Help me make tea":"お茶を入れる手順を教えて");
   assertTrue(ai.lastTextPrompt.contains(lang.equals("en")?"English":"Japanese"));assertTrue(ai.lastTextPrompt.contains("My 王先生 task"));
   assertTrue(sink.firstOfType("inquiry_result").optString("speech").contains("My 王先生 task"));
   sink.messages.clear();p.processTextInquiry("",lang.equals("en")?"next step":"次の手順");
   assertEquals("task_done",sink.firstOfType("inquiry_result").optString("intent"));
   assertTrue(sink.firstOfType("inquiry_result").optString("speech").contains("second"));
   sink.messages.clear();p.processTextInquiry("",lang.equals("en")?"cancel":"中止");
   assertEquals("stop",sink.firstOfType("inquiry_result").optString("intent"));
   assertEquals("nav",sink.firstOfType("inquiry_result").optString("mode"));
  }
 }
 @Test public void careRecordsPreserveExactUserContent() {
  TestFakes.AiClient ai=new TestFakes.AiClient();ai.settings.appLanguage="en";
  TestFakes.Sink sink=new TestFakes.Sink();SilverCareProcessor p=new SilverCareProcessor(ai,new MemoryStore(new TestFakes.Preferences()),sink);
  p.processTextInquiry("","Record 王先生 medicine, 5 mg.");
  assertEquals("王先生 medicine, 5 mg.",sink.firstOfType("care_record").optString("record_text"));
  assertTrue(sink.firstOfType("care_record").optString("speech").contains("王先生 medicine, 5 mg."));
 }
 @Test public void offlineDetectorSpeechUsesSelectedLanguage() throws Exception {
  for(String lang:new String[]{"English","Japanese"}) {
   JSONObject result=new JSONObject(OfflineVisionInterpreter.interpret("Output language: "+lang+"\nCurrent task: 找物目标：杯子\n","{\"detections\":[{\"label\":\"cup\",\"score\":0.9,\"bbox\":[100,100,200,200]}]}","vision"));
   assertFalse(result.optString("speech").contains("距离"));assertFalse(result.optString("speech").contains("找到"));
  }
 }
 @Test public void variedPoliteSearchPhrasesKeepCanonicalTargets() {
  for(String input:new String[]{"Could you look for the cup please?","Can you find my mug for me?","コップを見つけてください","私のコップはどこですか"}) {
   TestFakes.AiClient ai=new TestFakes.AiClient();ai.settings.aiRuntimeMode="offline_mnn";ai.settings.appLanguage=input.startsWith("C")?"en":"ja";
   TestFakes.Sink sink=new TestFakes.Sink();new SilverCareProcessor(ai,new MemoryStore(new TestFakes.Preferences()),sink).processTextInquiry("",input);
   assertEquals(input,"search",sink.firstOfType("inquiry_result").optString("intent"));
   assertEquals(ai.settings.appLanguage.equals("en")?"cup":"コップ",sink.firstOfType("inquiry_result").optString("current_goal"));
  }
 }
 @Test public void searchFrameDisplaysLocalizedGoalButUsesCanonicalDetectorTarget() {
  for(String lang:new String[]{"en","ja"}) {
   TestFakes.AiClient ai=new TestFakes.AiClient();ai.settings.appLanguage=lang;ai.settings.aiRuntimeMode="offline_mnn";
   ai.visionResponses.add("{\"priority\":\"low\",\"subject\":\"\",\"speech\":\"\",\"objects\":[]}");
   TestFakes.Sink sink=new TestFakes.Sink();new SilverCareProcessor(ai,new MemoryStore(new TestFakes.Preferences()),sink).processTextInquiry("data:image/png;base64,test",lang.equals("en")?"Find my cup":"私のコップを探して");
   assertTrue(ai.lastVisionPrompt.contains("Current task: 找物目标：杯子"));
   assertEquals(lang.equals("en")?"cup":"コップ",sink.firstOfType("result").optString("current_goal"));
   assertFalse(sink.firstOfType("inquiry_result").optString("speech").contains("杯子"));
  }
 }
}
