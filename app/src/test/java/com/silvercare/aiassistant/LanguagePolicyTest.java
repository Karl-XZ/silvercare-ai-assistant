package com.silvercare.aiassistant;
import org.junit.Test;
import static org.junit.Assert.*;
public class LanguagePolicyTest {
 @Test public void normalizesLocalesAndRejectsUnknownLanguages() {
  assertEquals("en", AppLanguage.normalize("en-US"));
  assertEquals("ja", AppLanguage.normalize("JA_jp"));
  assertEquals("zh", AppLanguage.normalize(null));
  assertEquals("zh", AppLanguage.normalize("invalid"));
  assertEquals("ja-JP", AppLanguage.bcp47("ja"));
  assertEquals("en", AppLanguage.locale("en").getLanguage());
 }
 @Test public void cloudLanguageMatchesTheSelection() {
  assertEquals("Japanese", AppLanguage.cloudLanguage("ja"));
  assertEquals("English", AppLanguage.cloudLanguage("en"));
  assertEquals("Chinese", AppLanguage.cloudLanguage("zh"));
  assertEquals("ja", AppLanguage.asrCode("ja"));
 }
 @Test public void catalogsTranslateAuthoredTextAndPreserveUnmatchedData() {
  assertEquals("Settings", LanguageResources.text("en", "设置"));
  assertEquals("設定", LanguageResources.text("ja", "设置"));
  assertEquals("recording-123.wav", LanguageResources.text("ja", "recording-123.wav"));
  assertEquals("设置", LanguageResources.text("zh", "设置"));
 }
 @Test public void localizedModelDetailsPreserveUserSuppliedPaths() {
  String path = "/custom/设置/有米/模型";
  java.io.File modelDir = new java.io.File(path);
  String absolutePath = modelDir.getAbsolutePath();
  LocalAsrModelStatus asr = new LocalAsrModelStatus(modelDir, modelDir, true, true, java.util.List.of());
  LocalTtsModelStatus tts = new LocalTtsModelStatus(modelDir, modelDir, true, "runtime", true, true, java.util.List.of());
  OfflineModelStatus ai = new OfflineModelStatus(path, modelDir, modelDir, true, true, true, true, java.util.List.of());
  for (String language : new String[]{"en", "ja"}) {
   assertTrue(asr.detailText(language), asr.detailText(language).contains(absolutePath));
   assertTrue(tts.detailText(language), tts.detailText(language).contains(absolutePath));
   assertTrue(ai.detailText(language), ai.detailText(language).contains(path));
   assertTrue(ai.detailText(language), ai.detailText(language).contains(absolutePath));
  }
 }
 @Test public void englishAndJapaneseNativeCatalogsHaveIdenticalCompleteKeys() throws Exception {
  org.json.JSONObject en = readCatalog("en");
  org.json.JSONObject ja = readCatalog("ja");
  assertEquals(catalogKeys(en), catalogKeys(ja));
  assertTrue(en.length() > 350);
  for (String key : catalogKeys(en)) {
   assertFalse("Empty English translation: " + key, en.getString(key).isEmpty());
   assertFalse("Empty Japanese translation: " + key, ja.getString(key).isEmpty());
  }
 }
 @Test public void dynamicAuthoredSegmentsTranslateWithoutRepeatedJapaneseReplacement() {
  assertEquals("Offline model download failed: file123", LanguageResources.text("en", "离线模型下载失败：file123"));
  assertEquals("設定", LanguageResources.text("ja", "设置"));
 }
 private static java.util.Set<String> catalogKeys(org.json.JSONObject catalog) {
  java.util.Set<String> result = new java.util.HashSet<>();
  java.util.Iterator<String> keys = catalog.keys();
  while (keys.hasNext()) result.add(keys.next());
  return result;
 }
 private static org.json.JSONObject readCatalog(String language) throws Exception {
  try (java.io.InputStream input = LanguagePolicyTest.class.getResourceAsStream("/i18n/native-" + language + ".json")) {
   assertNotNull(input);
   return new org.json.JSONObject(new String(input.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8));
  }
 }
}
