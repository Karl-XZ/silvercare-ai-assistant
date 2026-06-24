import fs from 'node:fs';
import path from 'node:path';

const androidSourceDir = 'app/src/main/java/com/silvercare/aiassistant';
const androidTestDir = 'app/src/test/java/com/silvercare/aiassistant';
const parityChecklist = 'docs/ios-android-parity-checklist.md';

function readText(file) {
  return fs.readFileSync(file, 'utf8');
}

function collectClasses(dir) {
  return fs.readdirSync(dir)
    .filter((entry) => /\.(java|kt)$/.test(entry))
    .map((entry) => path.basename(entry).replace(/\.(java|kt)$/, ''))
    .sort();
}

function assertEvidence(label, evidence, failures) {
  for (const item of evidence) {
    if (!fs.existsSync(item.file)) {
      failures.push(`${label}: missing evidence file ${item.file}`);
      continue;
    }
    const text = readText(item.file);
    for (const marker of item.markers ?? []) {
      if (!text.includes(marker)) {
        failures.push(`${label}: ${item.file} missing marker ${JSON.stringify(marker)}`);
      }
    }
  }
}

const sourceParity = {
  AiRuntimeMode: [{ file: 'ios/Sources/SilverCareCore/SilverCareTypes.swift', markers: ['public enum SilverCareRuntimeMode'] }],
  AsrRuntimeMode: [{ file: 'ios/Sources/SilverCareCore/SilverCareTypes.swift', markers: ['public enum SilverCareASRRuntimeMode'] }],
  DashScopeClient: [{ file: 'ios/Sources/SilverCareCore/DashScopeClient.swift', markers: ['public final class DashScopeAIClient', 'synthesizeSpeechURL'] }],
  DiagnosticLogger: [{ file: 'ios/SilverCareiOS/Services/IOSDiagnosticLogger.swift', markers: ['final class IOSDiagnosticLogger', 'latestLogPath'] }],
  LocalAsrDownloader: [{ file: 'ios/Sources/SilverCareCore/OfflineModelManager.swift', markers: ['public final class LocalASRModelManager', 'ensureChineseModel'] }],
  LocalAsrModelManager: [{ file: 'ios/Sources/SilverCareCore/OfflineModelManager.swift', markers: ['public final class LocalASRModelManager', 'LocalASRModelManifest.requiredFiles'] }],
  LocalAsrModelStatus: [{ file: 'ios/Sources/SilverCareCore/OfflineModelManager.swift', markers: ['public struct LocalASRModelStatus'] }],
  LocalAsrTextCorrector: [{ file: 'ios/Sources/SilverCareCore/LocalAsrTextCorrector.swift', markers: ['public enum LocalAsrTextCorrector', 'public enum LocalVoskTranscriptParser'] }],
  LocalModelBenchmarkActivity: [
    { file: 'ios/SilverCareiOS/App/SilverCareAppModel.swift', markers: ['runLocalModelBenchmark', 'makeLocalBenchmarkStatusReport', 'makeLocalBenchmarkScenarioReport'] },
    { file: 'tools/check-ios-benchmark-reports.mjs', markers: ['assertStatus', 'assertNativeCamera', 'assertScenario'] }
  ],
  LocalRuntimeBundlePlan: [{ file: 'ios/Sources/SilverCareCore/SilverCareTypes.swift', markers: ['public struct SilverCareLocalRuntimeBundlePlan'] }],
  LocalTtsDownloader: [{ file: 'ios/Sources/SilverCareCore/LocalTTSModelManager.swift', markers: ['public final class LocalTTSModelManager', 'ensureMNNBundle'] }],
  LocalTtsModelManager: [{ file: 'ios/Sources/SilverCareCore/LocalTTSModelManager.swift', markers: ['public final class LocalTTSModelManager', 'LocalTTSModelManifest.requiredFiles'] }],
  LocalTtsModelStatus: [{ file: 'ios/Sources/SilverCareCore/LocalTTSModelManager.swift', markers: ['public struct LocalTTSModelStatus'] }],
  LocalTtsRuntimeBridge: [
    { file: 'ios/SilverCareiOS/Services/DynamicIOSMNNTTSRuntime.swift', markers: ['final class DynamicIOSMNNTTSRuntime', 'silvercare_mnn_tts_synthesize_wav'] },
    { file: 'ios/Native/SilverCareMNNTTSRuntimeABI.h', markers: ['silvercare_mnn_tts_voice_quality_passed'] }
  ],
  MainActivity: [
    { file: 'ios/SilverCareiOS/App/SilverCareAppModel.swift', markers: ['final class SilverCareAppModel', 'handleBridgeMessage', 'presentSettings'] },
    { file: 'ios/SilverCareiOS/Bridge/SilverCareBridgeScript.swift', markers: ['AndroidSilverCare', 'runLocalBenchmark'] },
    { file: 'ios/SilverCareiOS/Bridge/SilverCareWebView.swift', markers: ['WKWebView', 'SilverCareWebView'] }
  ],
  MemoryStore: [{ file: 'ios/Sources/SilverCareCore/MemoryStore.swift', markers: ['public final class SilverCareMemoryStore', 'dedupeWindowSeconds'] }],
  MnnLlmTuningProfile: [
    { file: 'ios/Sources/SilverCareCore/SilverCareTypes.swift', markers: ['public enum SilverCareMnnLlmTuningProfile', 'nativeConfigJSON'] },
    { file: 'ios/SilverCareiOS/Services/DynamicIOSMNNLocalModelRuntime.swift', markers: ['SilverCareMnnLlmTuningProfile.nativeConfigJSON'] },
    { file: 'ios/SilverCareiOS/App/SilverCareAppModel.swift', markers: ['presentMnnTuningSettings'] }
  ],
  MnnNativeBridge: [
    { file: 'ios/SilverCareiOS/Services/DynamicIOSMNNLocalModelRuntime.swift', markers: ['silvercare_mnn_text_json', 'silvercare_mnn_vision_json_from_chw'] },
    { file: 'ios/Native/SilverCareMNNRuntimeABI.h', markers: ['silvercare_mnn_text_json', 'silvercare_mnn_vision_json_from_chw'] }
  ],
  MnnOfflineEngine: [
    { file: 'ios/SilverCareiOS/Services/IOSHybridAIClient.swift', markers: ['final class IOSHybridAIClient', 'visionDetectionsJSON'] },
    { file: 'ios/Native/SilverCareMNNRuntime/SilverCareMNNRuntime.mm', markers: ['silvercare_mnn_text_json', 'silvercare_mnn_vision_json_from_chw'] }
  ],
  MnnRuntimeBridge: [{ file: 'ios/SilverCareiOS/Services/DynamicIOSMNNLocalModelRuntime.swift', markers: ['final class DynamicIOSMNNLocalModelRuntime', 'runtimeSummary'] }],
  MnnTtsRuntimeBridge: [
    { file: 'ios/SilverCareiOS/Services/DynamicIOSMNNTTSRuntime.swift', markers: ['final class DynamicIOSMNNTTSRuntime', 'synthesizeToWav'] },
    { file: 'ios/Native/SilverCareMNNTTSRuntime/SilverCareMNNTTSRuntime.mm', markers: ['silvercare_mnn_tts_synthesize_wav'] }
  ],
  NavigationRefreshMode: [
    { file: 'ios/SilverCareiOS/App/SilverCareAppModel.swift', markers: ['presentNavigationRefreshSettings', 'setNavigationRefresh'] },
    { file: 'ios/Sources/SilverCareCore/SilverCareProcessor.swift', markers: ['shouldSkipSmartNavigationRefresh'] }
  ],
  OfflineAiClient: [{ file: 'ios/SilverCareiOS/Services/IOSHybridAIClient.swift', markers: ['final class IOSHybridAIClient', 'settings.aiRuntimeMode == "dashscope"'] }],
  OfflineInferenceEngine: [{ file: 'ios/SilverCareiOS/Services/IOSHybridAIClient.swift', markers: ['protocol IOSLocalModelRuntime', 'UnavailableIOSLocalModelRuntime'] }],
  OfflineModelDownloader: [{ file: 'ios/Sources/SilverCareCore/OfflineModelManager.swift', markers: ['prepareQwen4BBundle', 'OfflineModelManifest.qwen4BFiles'] }],
  OfflineModelManager: [{ file: 'ios/Sources/SilverCareCore/OfflineModelManager.swift', markers: ['public final class OfflineModelManager', 'public func inspect'] }],
  OfflineModelStatus: [{ file: 'ios/Sources/SilverCareCore/OfflineModelManager.swift', markers: ['public struct OfflineModelStatus'] }],
  OfflineVisionInterpreter: [{ file: 'ios/Sources/SilverCareCore/OfflineVisionInterpreter.swift', markers: ['public enum OfflineVisionInterpreter', 'navigationOrSearchResult', 'canonicalSearchTargetOrder'] }],
  SilverCareArtificialIntelligenceClient: [{ file: 'ios/Sources/SilverCareCore/SilverCareTypes.swift', markers: ['public protocol SilverCareAIClient'] }],
  SilverCareProcessor: [{ file: 'ios/Sources/SilverCareCore/SilverCareProcessor.swift', markers: ['public final class SilverCareProcessor', 'processTextInquiry', 'taskUpdateMessage'] }],
  TtsRuntimeMode: [{ file: 'ios/Sources/SilverCareCore/SilverCareTypes.swift', markers: ['public enum SilverCareTTSRuntimeMode'] }],
  VoskLocalAsrEngine: [{ file: 'ios/SilverCareiOS/Services/LocalVoskASRRuntime.swift', markers: ['final class LocalVoskASRRuntime', 'vosk_recognizer_accept_waveform'] }]
};

const testParity = {
  AsrRuntimeModeTest: [{ file: 'ios/Tests/SilverCareCoreTests/DashScopeClientTests.swift', markers: ['testRuntimeModeValuesMatchAndroidCompatibilityContract', 'SilverCareASRRuntimeMode'] }],
  DashScopeClientTest: [{ file: 'ios/Tests/SilverCareCoreTests/DashScopeClientTests.swift', markers: ['testDashScopeBuildsAndParsesTextVisionAsrAndTtsRequests'] }],
  DashScopeLiveIntegrationTest: [
    { file: 'tools/run-live-dashscope-scenarios.mjs', markers: ['downloadScenarioImage', 'runVisionScenario'] },
    { file: 'tools/check-live-dashscope-scenarios.mjs', markers: ['REDACTED_DASHSCOPE_API_KEY', 'scenario'] }
  ],
  LocalAsrDownloaderTest: [{ file: 'ios/Tests/SilverCareCoreTests/DashScopeClientTests.swift', markers: ['testLocalASRZipExtractionAcceptsAndroidVoskArchiveLayout', 'testLocalASRZipExtractionRejectsUnsafePaths'] }],
  LocalAsrModelManagerTest: [{ file: 'ios/Tests/SilverCareCoreTests/DashScopeClientTests.swift', markers: ['testLocalASRModelInspectionMatchesAndroidVoskLayout'] }],
  LocalAsrTextCorrectorTest: [{ file: 'ios/Tests/SilverCareCoreTests/LocalAsrTextCorrectorTests.swift', markers: ['testFastCorrectHandlesCommonSilverCarePhrases'] }],
  LocalRuntimeBundlePlanTest: [{ file: 'ios/Tests/SilverCareCoreTests/DashScopeClientTests.swift', markers: ['testLocalRuntimeBundlePlanMatchesAndroidDownloadAccounting'] }],
  LocalTtsDownloaderTest: [{ file: 'ios/Tests/SilverCareCoreTests/DashScopeClientTests.swift', markers: ['LocalTTSModelManifest.expectedTotalBytes', 'bert-vits2-MNN'] }],
  LocalTtsModelManagerTest: [{ file: 'ios/Tests/SilverCareCoreTests/DashScopeClientTests.swift', markers: ['testLocalTTSModelInspectionMatchesAndroidBertVitsLayout'] }],
  MemoryStoreTest: [{ file: 'ios/Tests/SilverCareCoreTests/MemoryStoreTests.swift', markers: ['testLogObjectDeduplicatesImmediateRepeatedObject'] }],
  MnnLlmTuningProfileTest: [{ file: 'ios/Tests/SilverCareCoreTests/MnnLlmTuningProfileTests.swift', markers: ['testEmitsNativeConfigOnlyWhenSme2IsSupported', 'testMenuTextExplainsAutomaticFallback'] }],
  MnnOfflineEngineTest: [
    { file: 'ios/Tests/SilverCareCoreTests/OfflineVisionInterpreterTests.swift', markers: ['testFindsRequestedObjectDirectionFromDetectorBoxes'] },
    { file: 'tools/check-ios-native-runtime.mjs', markers: ['silvercare_mnn_text_json', 'silvercare_mnn_vision_json_from_chw'] }
  ],
  NavigationRefreshModeTest: [{ file: 'ios/Tests/SilverCareCoreTests/SilverCareProcessorTests.swift', markers: ['testSmartRefreshSkipsSemanticallyConsistentNavigationText'] }],
  OfflineAiClientTest: [{ file: 'ios/Tests/SilverCareCoreTests/SilverCareProcessorTests.swift', markers: ['testOfflineNavigationQuestionDoesNotBecomeSearchTarget'] }],
  OfflineModelDownloaderTest: [{ file: 'ios/Tests/SilverCareCoreTests/DashScopeClientTests.swift', markers: ['testOfflineModelInspectionSupportsAndroidBackupTextModel'] }],
  OfflineModelManagerTest: [{ file: 'ios/Tests/SilverCareCoreTests/DashScopeClientTests.swift', markers: ['testOfflineModelInspectionSupportsAndroidBackupTextModel'] }],
  OfflineVisionInterpreterTest: [{ file: 'ios/Tests/SilverCareCoreTests/OfflineVisionInterpreterTests.swift', markers: ['testProducesObstacleNavigationFromLargestAheadObject'] }],
  SilverCareProcessorTest: [{
    file: 'ios/Tests/SilverCareCoreTests/SilverCareProcessorTests.swift',
    markers: [
      'testNavigationFrameEmitsResultAndSpeechWithDistance',
      'testSmartRefreshSkipsSemanticallyConsistentNavigationText',
      'testSearchInquiryUpdatesGoalAndRunsNavigationOnSameFrame',
      'testOfflineInquiryUsesTextModelForIntent',
      'testOfflineCompactIntentNormalizesNoisyRouterCode',
      'testOfflineCompactIntentFallsBackToInfoWhenRouterReturnsInvalidCode',
      'testOfflineInfoInquiryUsesShortFourBPromptAndTokenBudget',
      'testOfflineSearchCorrectsAsrTargetBeforeStartingSearch',
      'testOfflineNavigationQuestionDoesNotBecomeSearchTarget',
      'testOfflineNavigationQuestionOverridesModelSearchMisroute',
      'testOfflineSearchRejectsUnsupportedTargetAndStaysInConversation',
      'testOfflineInquiryAcceptsFirstJsonWhenBackupModelAddsExtraText',
      'testOfflineInquiryFallsBackWhenBackupModelReturnsNoJson',
      'testMicroNavigationRequiresGuidanceKeyword',
      'testMicroFollowUpKeepsCurrentGuidanceMode',
      'testExplicitGuidanceStartsMicroModeAndCloseKeywordStopsIt',
      'testTranscriptFallbackRestoresSearchTargetWhenSmallModelLeavesItNull',
      'testTranscriptFallbackAnswersRememberedObjectLocation',
      'testTranscriptFallbackTaskDoneOverridesSmallModelMicroNavMistake',
      'testTaskInquiryCreatesTaskPlanAndAnnouncesFirstStep'
    ]
  }],
  TestFakes: [{ file: 'ios/Tests/SilverCareCoreTests/TestDoubles.swift', markers: ['final class FakeAIClient'] }],
  TtsRuntimeModeTest: [{ file: 'ios/Tests/SilverCareCoreTests/DashScopeClientTests.swift', markers: ['SilverCareTTSRuntimeMode'] }],
  VoskLocalAsrEngineTest: [{ file: 'ios/Tests/SilverCareCoreTests/LocalAsrTextCorrectorTests.swift', markers: ['testVoskTranscriptParserMatchesAndroidChineseSpacingRules'] }]
};

const failures = [];

const androidClasses = collectClasses(androidSourceDir);
for (const className of androidClasses) {
  if (!sourceParity[className]) {
    failures.push(`Android source ${className} has no iOS parity mapping`);
    continue;
  }
  assertEvidence(`Android source ${className}`, sourceParity[className], failures);
}
for (const className of Object.keys(sourceParity)) {
  if (!androidClasses.includes(className)) {
    failures.push(`iOS parity mapping references missing Android source ${className}`);
  }
}

const androidTests = collectClasses(androidTestDir);
for (const className of androidTests) {
  if (!testParity[className]) {
    failures.push(`Android test ${className} has no iOS/test parity mapping`);
    continue;
  }
  assertEvidence(`Android test ${className}`, testParity[className], failures);
}
for (const className of Object.keys(testParity)) {
  if (!androidTests.includes(className)) {
    failures.push(`iOS test parity mapping references missing Android test ${className}`);
  }
}

if (fs.existsSync(parityChecklist)) {
  const checklist = readText(parityChecklist);
  const missingRows = checklist
    .split(/\r?\n/)
    .filter((line) => /^\|/.test(line) && /\|\s*missing\s*\|/.test(line));
  if (missingRows.length > 0) {
    failures.push(`Parity checklist still contains missing rows:\n${missingRows.join('\n')}`);
  }
} else {
  failures.push(`Missing parity checklist ${parityChecklist}`);
}

if (failures.length > 0) {
  console.error('iOS parity surface check failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log(`Checked iOS parity mappings for ${androidClasses.length} Android source class(es) and ${androidTests.length} Android test class(es).`);
