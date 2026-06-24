import XCTest
import SilverCareCore
@testable import SilverCareiOS

final class RuntimeStatusSnapshotStoreTests: XCTestCase {
    private let persistedRuntimeStatusKeys = [
        "ios_ai_runtime_mode",
        "ios_dashscope_api_key",
        "ios_compatible_base_url",
        "ios_api_base_url",
        "ios_vision_model",
        "ios_text_model",
        "ios_offline_text_model",
        "ios_micro_model",
        "ios_asr_runtime_mode",
        "ios_asr_model",
        "ios_tts_runtime_mode",
        "ios_captions_enabled",
        "ios_voice_first_enabled",
        "ios_fall_detection_enabled",
        "ios_navigation_refresh_mode",
        "ios_navigation_refresh_interval_ms",
        "ios_smart_navigation_refresh_enabled",
        "ios_mnn_llm_tuning_mode",
        "ios_cloud_first_runtime_migration_v1"
    ]

    override func setUp() {
        super.setUp()
        clearPersistedRuntimeStatus()
    }

    override func tearDown() {
        clearPersistedRuntimeStatus()
        super.tearDown()
    }

    func testSnapshotStoreReturnsLatestWholeStatusValue() {
        var initial = SilverCareRuntimeStatus()
        initial.runtimeDisplayName = "seed"
        initial.offlineModelDirectory = "seed"
        let store = RuntimeStatusSnapshotStore(status: initial)

        var updated = SilverCareRuntimeStatus()
        updated.aiRuntimeMode = "offline_mnn"
        updated.runtimeDisplayName = "offline-marker"
        updated.offlineModelDirectory = "offline-marker"
        updated.navigationRefreshIntervalMs = 1250
        store.update(updated)

        let snapshot = store.status()
        XCTAssertEqual(snapshot.aiRuntimeMode, "offline_mnn")
        XCTAssertEqual(snapshot.runtimeDisplayName, "offline-marker")
        XCTAssertEqual(snapshot.offlineModelDirectory, "offline-marker")
        XCTAssertEqual(snapshot.navigationRefreshIntervalMs, 1250)
    }

    func testSnapshotStoreKeepsWholeValuesDuringConcurrentReadsAndWrites() {
        var initial = SilverCareRuntimeStatus()
        initial.runtimeDisplayName = "seed"
        initial.offlineModelDirectory = "seed"
        let store = RuntimeStatusSnapshotStore(status: initial)
        let queue = DispatchQueue(label: "silvercare.runtime.snapshot.test", attributes: .concurrent)
        let group = DispatchGroup()
        let failureLock = NSLock()
        var failures: [String] = []

        func recordFailure(_ message: String) {
            failureLock.lock()
            failures.append(message)
            failureLock.unlock()
        }

        for index in 0..<400 {
            group.enter()
            queue.async {
                var status = SilverCareRuntimeStatus()
                let marker = "marker-\(index)"
                status.runtimeDisplayName = marker
                status.offlineModelDirectory = marker
                status.navigationRefreshIntervalMs = 1000 + index
                store.update(status)
                group.leave()
            }

            group.enter()
            queue.async {
                for _ in 0..<8 {
                    let snapshot = store.status()
                    if snapshot.runtimeDisplayName != snapshot.offlineModelDirectory {
                        recordFailure(
                            "saw torn status value: \(snapshot.runtimeDisplayName) / \(snapshot.offlineModelDirectory)"
                        )
                    }
                    if snapshot.navigationRefreshIntervalMs <= 0 {
                        recordFailure("saw invalid refresh interval: \(snapshot.navigationRefreshIntervalMs)")
                    }
                }
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertTrue(failures.isEmpty, failures.first ?? "")
    }

    func testHybridClientReadsSnapshotSettingsOffMainThread() {
        var status = SilverCareRuntimeStatus()
        status.aiRuntimeMode = "offline_mnn"
        status.offlineModelDirectory = "/tmp/silvercare-models"
        status.offlineTextModel = "Qwen2.5-1.5B-Instruct-MNN"
        status.asrRuntimeMode = "local_vosk"
        status.ttsRuntimeMode = "local_mnn"
        status.voiceFirstEnabled = false
        status.smartNavigationRefreshEnabled = true
        let store = RuntimeStatusSnapshotStore(status: status)
        let client = IOSHybridAIClient(
            statusProvider: { store.status() },
            diagnosticLogger: IOSDiagnosticLogger()
        )
        let expectation = expectation(description: "background settings read")
        let resultLock = NSLock()
        var observed: SilverCareSettings?

        DispatchQueue.global(qos: .userInitiated).async {
            let settings = client.settings
            resultLock.lock()
            observed = settings
            resultLock.unlock()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
        resultLock.lock()
        let settings = observed
        resultLock.unlock()
        XCTAssertEqual(settings?.aiRuntimeMode, "offline_mnn")
        XCTAssertEqual(settings?.offlineModelDirectory, "/tmp/silvercare-models")
        XCTAssertEqual(settings?.textModel, "qwen2.5-1.5b-instruct-mnn")
        XCTAssertEqual(settings?.asrRuntimeMode, "local_vosk")
        XCTAssertEqual(settings?.ttsRuntimeMode, "local_mnn")
        XCTAssertEqual(settings?.voiceFirstEnabled, false)
        XCTAssertEqual(settings?.smartNavigationRefreshEnabled, true)
    }

    func testHybridClientDoesNotReturnSyntheticOfflineVisionJSONWhenRuntimeIsMissing() {
        var status = SilverCareRuntimeStatus()
        status.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
        status.offlineModelDirectory = "/tmp/silvercare-models"
        let client = IOSHybridAIClient(
            statusProvider: { status },
            diagnosticLogger: IOSDiagnosticLogger()
        )

        XCTAssertThrowsError(try client.visionJSON(
            prompt: "看前方是否可通行",
            imageDataURL: "data:image/png;base64,",
            model: "damo-yolo-mnn"
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("runtime"))
        }
    }

    func testHybridClientDoesNotReturnSyntheticOfflineTextJSONWhenRuntimeIsMissing() {
        var status = SilverCareRuntimeStatus()
        status.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
        status.offlineModelDirectory = "/tmp/silvercare-models"
        let client = IOSHybridAIClient(
            statusProvider: { status },
            diagnosticLogger: IOSDiagnosticLogger()
        )

        XCTAssertThrowsError(try client.textJSON(
            prompt: "只输出 JSON",
            model: OfflineModelManifest.textModel4B,
            maxNewTokens: 32,
            endWith: "}"
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("runtime"))
        }
    }

    func testDynamicMNNRuntimeDoesNotReportSme2WhenSymbolsAreMissing() {
        let runtime = DynamicIOSMNNLocalModelRuntime(statusProvider: { SilverCareRuntimeStatus() })

        XCTAssertFalse(runtime.isReady)
        XCTAssertFalse(runtime.supportsSme2)
        XCTAssertTrue(runtime.runtimeSummary.contains("未加载"))
    }

    func testRuntimeStatusPersistsCloudSettingsAndDefersLocalRuntimeModesAcrossReloads() {
        markCloudFirstRuntimeMigrationDone()
        var status = SilverCareRuntimeStatus()
        status.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
        status.dashScopeAPIKey = "test-key-that-must-stay-local"
        status.compatibleBaseURL = "https://example.test/compatible"
        status.apiBaseURL = "https://example.test/api"
        status.visionModel = "vision-model"
        status.textModel = "text-model"
        status.offlineTextModel = OfflineModelManifest.textModel15B
        status.microModel = "micro-model"
        status.asrRuntimeMode = SilverCareASRRuntimeMode.localVosk.rawValue
        status.asrModel = "asr-model"
        status.ttsRuntimeMode = SilverCareTTSRuntimeMode.system.rawValue
        status.captionsEnabled = false
        status.voiceFirstEnabled = false
        status.fallDetectionEnabled = false
        status.navigationRefreshMode = "manual"
        status.navigationRefreshIntervalMs = 5000
        status.smartNavigationRefreshEnabled = true
        status.mnnLlmTuningMode = "performance"

        status.save()

        let reloaded = SilverCareRuntimeStatus.load()
        XCTAssertEqual(reloaded.aiRuntimeMode, SilverCareRuntimeMode.dashScope.rawValue)
        XCTAssertEqual(reloaded.runtimeDisplayName, SilverCareRuntimeMode.dashScope.label)
        XCTAssertEqual(reloaded.dashScopeAPIKey, "test-key-that-must-stay-local")
        XCTAssertEqual(reloaded.compatibleBaseURL, "https://example.test/compatible")
        XCTAssertEqual(reloaded.apiBaseURL, "https://example.test/api")
        XCTAssertEqual(reloaded.visionModel, "vision-model")
        XCTAssertEqual(reloaded.textModel, "text-model")
        XCTAssertEqual(reloaded.offlineTextModel, OfflineModelManifest.textModel15B)
        XCTAssertEqual(reloaded.microModel, "micro-model")
        XCTAssertEqual(reloaded.asrRuntimeMode, SilverCareASRRuntimeMode.dashScope.rawValue)
        XCTAssertEqual(reloaded.asrRuntimeDisplayName, SilverCareASRRuntimeMode.dashScope.label)
        XCTAssertEqual(reloaded.asrModel, "asr-model")
        XCTAssertEqual(reloaded.ttsRuntimeMode, SilverCareTTSRuntimeMode.dashScope.rawValue)
        XCTAssertEqual(reloaded.ttsRuntimeDisplayName, SilverCareTTSRuntimeMode.dashScope.label)
        XCTAssertFalse(reloaded.captionsEnabled)
        XCTAssertFalse(reloaded.voiceFirstEnabled)
        XCTAssertFalse(reloaded.fallDetectionEnabled)
        XCTAssertEqual(reloaded.navigationRefreshMode, "manual")
        XCTAssertEqual(reloaded.navigationRefreshIntervalMs, 5000)
        XCTAssertTrue(reloaded.smartNavigationRefreshEnabled)
        XCTAssertEqual(reloaded.mnnLlmTuningMode, "performance")
        XCTAssertEqual(reloaded.mnnLlmTuningDisplayName, "SME2 性能优先")
    }

    func testRuntimeStatusUsesDefaultsWhenBooleanKeysHaveNeverBeenSaved() {
        let status = SilverCareRuntimeStatus.load()

        XCTAssertTrue(status.captionsEnabled)
        XCTAssertTrue(status.voiceFirstEnabled)
        XCTAssertTrue(status.fallDetectionEnabled)
        XCTAssertFalse(status.smartNavigationRefreshEnabled)
        XCTAssertEqual(status.navigationRefreshIntervalMs, 3000)
    }

    func testRuntimeStatusNormalizesLegacyAndInvalidSavedModes() {
        markCloudFirstRuntimeMigrationDone()
        let defaults = UserDefaults.standard
        defaults.set("unexpected-ai-mode", forKey: "ios_ai_runtime_mode")
        defaults.set("unexpected-asr-mode", forKey: "ios_asr_runtime_mode")
        defaults.set("local_qwen", forKey: "ios_tts_runtime_mode")
        defaults.set("unexpected-text-model", forKey: "ios_offline_text_model")

        let status = SilverCareRuntimeStatus.load()

        XCTAssertEqual(status.aiRuntimeMode, SilverCareRuntimeMode.dashScope.rawValue)
        XCTAssertEqual(status.runtimeDisplayName, SilverCareRuntimeMode.dashScope.label)
        XCTAssertEqual(status.asrRuntimeMode, SilverCareASRRuntimeMode.dashScope.rawValue)
        XCTAssertEqual(status.asrRuntimeDisplayName, SilverCareASRRuntimeMode.dashScope.label)
        XCTAssertEqual(status.ttsRuntimeMode, SilverCareTTSRuntimeMode.dashScope.rawValue)
        XCTAssertEqual(status.ttsRuntimeDisplayName, SilverCareTTSRuntimeMode.dashScope.label)
        XCTAssertEqual(status.offlineTextModel, OfflineModelManifest.textModel4B)
    }

    func testRuntimeStatusDefaultsToCloudRuntimeUnlessLocalRuntimeIsExplicitlyAllowed() {
        let defaults = UserDefaults.standard
        defaults.set(SilverCareRuntimeMode.offlineMNN.rawValue, forKey: "ios_ai_runtime_mode")
        defaults.set(SilverCareASRRuntimeMode.localVosk.rawValue, forKey: "ios_asr_runtime_mode")
        defaults.set(SilverCareTTSRuntimeMode.localMNN.rawValue, forKey: "ios_tts_runtime_mode")

        let loaded = SilverCareRuntimeStatus.load()

        XCTAssertEqual(loaded.aiRuntimeMode, SilverCareRuntimeMode.dashScope.rawValue)
        XCTAssertEqual(loaded.runtimeDisplayName, SilverCareRuntimeMode.dashScope.label)
        XCTAssertEqual(loaded.asrRuntimeMode, SilverCareASRRuntimeMode.dashScope.rawValue)
        XCTAssertEqual(loaded.asrRuntimeDisplayName, SilverCareASRRuntimeMode.dashScope.label)
        XCTAssertEqual(loaded.ttsRuntimeMode, SilverCareTTSRuntimeMode.dashScope.rawValue)
        XCTAssertEqual(loaded.ttsRuntimeDisplayName, SilverCareTTSRuntimeMode.dashScope.label)
        XCTAssertTrue(defaults.bool(forKey: "ios_cloud_first_runtime_migration_v1"))

        defaults.set(SilverCareRuntimeMode.offlineMNN.rawValue, forKey: "ios_ai_runtime_mode")
        defaults.set(SilverCareASRRuntimeMode.localVosk.rawValue, forKey: "ios_asr_runtime_mode")
        defaults.set(SilverCareTTSRuntimeMode.localMNN.rawValue, forKey: "ios_tts_runtime_mode")

        let reloadedAfterUserChange = SilverCareRuntimeStatus.load()
        XCTAssertEqual(reloadedAfterUserChange.aiRuntimeMode, SilverCareRuntimeMode.dashScope.rawValue)
        XCTAssertEqual(reloadedAfterUserChange.asrRuntimeMode, SilverCareASRRuntimeMode.dashScope.rawValue)
        XCTAssertEqual(reloadedAfterUserChange.ttsRuntimeMode, SilverCareTTSRuntimeMode.dashScope.rawValue)
    }

    private func markCloudFirstRuntimeMigrationDone() {
        UserDefaults.standard.set(true, forKey: "ios_cloud_first_runtime_migration_v1")
    }

    private func clearPersistedRuntimeStatus() {
        let defaults = UserDefaults.standard
        for key in persistedRuntimeStatusKeys {
            defaults.removeObject(forKey: key)
        }
    }
}
