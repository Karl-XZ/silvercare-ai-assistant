import XCTest
@testable import SilverCareCore

final class DashScopeClientTests: XCTestCase {
    func testDashScopeBuildsAndParsesTextVisionAsrAndTtsRequests() throws {
        let transport = CapturingTransport()
        transport.responses = [
            ["choices": [["message": ["content": #"{"intent":"info","speech":"你好"}"#]]]],
            ["choices": [["message": ["content": #"{"priority":"low","speech":"可以前进"}"#]]]],
            ["output": ["choices": [["message": ["content": [["text": "帮我找杯子"]]]]]]],
            ["output": ["audio": ["url": "https://example.com/tts.wav"]]]
        ]
        let settings = SilverCareSettings(
            aiRuntimeMode: "dashscope",
            apiKey: "test-key",
            compatibleBaseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            apiBaseURL: "https://dashscope.aliyuncs.com/api/v1",
            visionModel: "qwen3-vl-flash",
            textModel: "qwen-plus",
            asrModel: "qwen3-asr-flash"
        )
        let client = DashScopeAIClient(settings: settings, transport: transport)

        XCTAssertTrue(try client.textJSON(prompt: "你好", model: "qwen-plus", maxNewTokens: 24, endWith: "}").contains("你好"))
        XCTAssertTrue(try client.visionJSON(prompt: "看路", imageDataURL: "data:image/jpeg;base64,abc", model: "qwen3-vl-flash").contains("可以前进"))
        XCTAssertEqual(try client.transcribe(audioDataURL: "data:audio/wav;base64,abc"), "帮我找杯子")
        XCTAssertEqual(try client.synthesizeSpeechURL(text: "请慢走"), "https://example.com/tts.wav")

        XCTAssertTrue(transport.apiKeys.allSatisfy { $0 == "test-key" })
        XCTAssertTrue(transport.endpoints[0].absoluteString.hasSuffix("/compatible-mode/v1/chat/completions"))
        XCTAssertTrue(transport.endpoints[2].absoluteString.hasSuffix("/api/v1/services/aigc/multimodal-generation/generation"))
        XCTAssertEqual((transport.payloads[1]["response_format"] as? [String: Any])?["type"] as? String, "json_object")
    }

    func testDashScopeNormalizesArrayMessageContent() throws {
        let transport = CapturingTransport()
        transport.responses = [
            ["choices": [["message": ["content": [
                ["text": "```json\n"],
                ["text": #"{"ok":true,"speech":"数组内容通过"}"#],
                ["text": "\n```"]
            ]]]]]
        ]
        let client = DashScopeAIClient(
            settings: SilverCareSettings(aiRuntimeMode: "dashscope", apiKey: "test-key"),
            transport: transport
        )

        let raw = try client.textJSON(prompt: "测试", model: "qwen-plus", maxNewTokens: nil, endWith: nil)
        let parsed = try JSONSupport.object(from: raw)

        XCTAssertEqual(parsed.string("speech"), "数组内容通过")
    }

    func testJSONSupportSkipsMalformedPrefixBeforeCompleteObject() throws {
        let raw = """
        导航字段如下：[priority, speech
        ```json
        {"priority":"low","category":"navigation","speech":"前方可以通行","objects":[]}
        ```
        """

        let parsed = try JSONSupport.object(from: raw)

        XCTAssertEqual(parsed.string("category"), "navigation")
        XCTAssertEqual(parsed.string("speech"), "前方可以通行")
    }

    func testDashScopeRequiresApiKey() {
        let client = DashScopeAIClient(settings: SilverCareSettings(aiRuntimeMode: "dashscope", apiKey: ""))

        XCTAssertThrowsError(try client.textJSON(prompt: "你好", model: "qwen-plus", maxNewTokens: nil, endWith: nil)) { error in
            XCTAssertTrue(error.localizedDescription.contains("DashScope Key"))
        }
    }

    func testRuntimeModeValuesMatchAndroidCompatibilityContract() {
        XCTAssertEqual(SilverCareRuntimeMode.from("offline_mnn").label, "端侧离线 MNN")
        XCTAssertEqual(SilverCareRuntimeMode.from("dashscope").label, "联网 DashScope")
        XCTAssertEqual(SilverCareASRRuntimeMode.from("local_vosk").label, "本地内置 ASR")
        XCTAssertEqual(SilverCareASRRuntimeMode.from("local_ios_speech"), .localVosk)
        XCTAssertEqual(SilverCareASRRuntimeMode.from("dashscope"), .dashScope)
        XCTAssertEqual(SilverCareTTSRuntimeMode.from("auto").label, "自动兜底")
        XCTAssertEqual(SilverCareTTSRuntimeMode.from("local_qwen"), .localMNN)

        let settings = SilverCareSettings(
            asrRuntimeMode: "dashscope",
            ttsRuntimeMode: "local_qwen"
        )
        XCTAssertEqual(settings.asrRuntimeMode, "dashscope")
        XCTAssertEqual(settings.ttsRuntimeMode, "local_mnn")
    }

    func testLocalRuntimeBundlePlanMatchesAndroidDownloadAccounting() {
        let status = OfflineModelStatus(
            modelDirectory: URL(fileURLWithPath: "/tmp/silvercare-models"),
            textModel: OfflineModelManifest.textModel4B,
            textConfigURL: nil,
            yoloModelURL: nil,
            nativeRuntimeAvailable: false,
            directoryReadable: false,
            textReady: false,
            yoloReady: false,
            missing: ["MNN Native Runtime", "模型目录不可读"]
        )

        let plan = SilverCareLocalRuntimeBundlePlan.from(
            offlineStatus: status,
            localASRReady: false,
            includeExperimentalTTS: false,
            ttsRuntimeAvailable: false
        )

        XCTAssertTrue(plan.offlineModelsRequired)
        XCTAssertTrue(plan.asrModelRequired)
        XCTAssertFalse(plan.ttsModelRequired)
        XCTAssertTrue(plan.mnnRuntimeMissing)
        XCTAssertEqual(
            plan.downloadBytes,
            OfflineModelManifest.expectedTotalBytes + SilverCareLocalRuntimeBundlePlan.localASRExpectedBytes
        )
        XCTAssertTrue(plan.downloadSummaryText.contains("AI 离线模型"))
        XCTAssertTrue(plan.downloadSummaryText.contains("本地 ASR"))
        XCTAssertTrue(plan.runtimeWarningText.contains("MNN Native Runtime"))

        let runtimeGapPlan = SilverCareLocalRuntimeBundlePlan.from(
            offlineStatus: status,
            localASRReady: true,
            localASRRuntimeAvailable: false,
            includeExperimentalTTS: false,
            ttsRuntimeAvailable: false
        )
        XCTAssertFalse(runtimeGapPlan.asrModelRequired)
        XCTAssertTrue(runtimeGapPlan.asrRuntimeMissing)
        XCTAssertTrue(runtimeGapPlan.runtimeWarningText.contains("iOS Vosk ASR Runtime"))

        XCTAssertEqual(
            LocalTTSModelManifest.expectedTotalBytes,
            SilverCareLocalRuntimeBundlePlan.localTTSExpectedBytes
        )
        let experimentalTTSPlan = SilverCareLocalRuntimeBundlePlan.from(
            offlineStatus: status,
            localASRReady: true,
            localASRRuntimeAvailable: true,
            localTTSModelReady: false,
            includeExperimentalTTS: true,
            ttsRuntimeAvailable: false
        )
        XCTAssertTrue(experimentalTTSPlan.ttsModelRequired)
        XCTAssertTrue(experimentalTTSPlan.ttsRuntimeMissing)
        XCTAssertEqual(
            experimentalTTSPlan.downloadBytes,
            OfflineModelManifest.expectedTotalBytes + SilverCareLocalRuntimeBundlePlan.localTTSExpectedBytes
        )
        XCTAssertTrue(experimentalTTSPlan.downloadSummaryText.contains("bert-vits2-MNN"))
        XCTAssertTrue(experimentalTTSPlan.runtimeWarningText.contains("本地 MNN TTS"))
    }

    func testOfflineModelInspectionSupportsAndroidBackupTextModel() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("silvercare-offline-15b-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let textConfig = root
            .appendingPathComponent("Qwen2.5-1.5B-Instruct-MNN", isDirectory: true)
            .appendingPathComponent("config.json")
        try fileManager.createDirectory(at: textConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileManager.createFile(atPath: textConfig.path, contents: Data("{}".utf8))
        fileManager.createFile(
            atPath: root.appendingPathComponent("damo-yolo.mnn").path,
            contents: Data("mnn".utf8)
        )

        let manager = OfflineModelManager(fileManager: fileManager)
        let status = manager.inspect(
            modelDirectory: root,
            textModel: "Qwen2.5-1.5B-Instruct-MNN",
            nativeRuntimeAvailable: true
        )

        XCTAssertEqual(status.textModel, OfflineModelManifest.textModel15B)
        XCTAssertTrue(status.textReady)
        XCTAssertTrue(status.yoloReady)
        XCTAssertTrue(status.ready)
        XCTAssertTrue(status.missing.isEmpty)
        XCTAssertTrue(status.detailText.contains("Qwen2.5-1.5B-Instruct-MNN"))
    }

    func testLocalASRModelInspectionMatchesAndroidVoskLayout() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("silvercare-asr-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let manager = LocalASRModelManager(fileManager: fileManager)
        let missing = manager.inspect(modelRoot: root, runtimeAvailable: false)
        XCTAssertFalse(missing.modelReady)
        XCTAssertFalse(missing.ready)
        XCTAssertTrue(missing.missing.contains("ASR 模型目录不可读"))
        XCTAssertTrue(missing.missing.contains(LocalASRModelManifest.voskChineseDirectory))

        let modelDir = root.appendingPathComponent(LocalASRModelManifest.voskChineseDirectory, isDirectory: true)
        for required in LocalASRModelManifest.requiredFiles {
            let file = modelDir.appendingPathComponent(required)
            try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            fileManager.createFile(atPath: file.path, contents: Data("ok".utf8))
        }

        let modelOnly = manager.inspect(modelRoot: root, runtimeAvailable: false)
        XCTAssertTrue(modelOnly.modelReady)
        XCTAssertFalse(modelOnly.ready)
        XCTAssertEqual(modelOnly.missing, ["iOS Vosk Runtime"])
        XCTAssertTrue(modelOnly.shortText.contains("iOS Vosk Runtime"))

        let ready = manager.inspect(modelRoot: root, runtimeAvailable: true)
        XCTAssertTrue(ready.modelReady)
        XCTAssertTrue(ready.ready)
        XCTAssertTrue(ready.missing.isEmpty)
    }

    func testLocalTTSModelInspectionMatchesAndroidBertVitsLayout() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("silvercare-tts-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let manager = LocalTTSModelManager(fileManager: fileManager)
        let requiredFiles = [
            OfflineModelDownloadFile(
                relativePath: "config.json",
                expectedBytes: 2,
                urls: [URL(string: "https://example.com/config.json")!]
            ),
            OfflineModelDownloadFile(
                relativePath: "common/mnn_models/chinese_bert.mnn",
                expectedBytes: 3,
                urls: [URL(string: "https://example.com/chinese_bert.mnn")!]
            )
        ]

        let missing = manager.inspect(
            modelRoot: root,
            runtimeAvailable: false,
            requiredFiles: requiredFiles
        )
        XCTAssertFalse(missing.modelReady)
        XCTAssertFalse(missing.ready)
        XCTAssertTrue(missing.missing.contains("TTS 模型目录不可读"))
        XCTAssertTrue(missing.missing.contains(LocalTTSModelManifest.mnnTTSDirectory))

        let modelDir = root.appendingPathComponent(LocalTTSModelManifest.mnnTTSDirectory, isDirectory: true)
        for item in requiredFiles {
            let file = modelDir.appendingPathComponent(item.relativePath)
            try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            fileManager.createFile(
                atPath: file.path,
                contents: Data(repeating: 1, count: Int(item.expectedBytes))
            )
        }

        let modelOnly = manager.inspect(
            modelRoot: root,
            runtimeAvailable: false,
            runtimeSummary: "test runtime unavailable",
            requiredFiles: requiredFiles
        )
        XCTAssertTrue(modelOnly.modelReady)
        XCTAssertFalse(modelOnly.ready)
        XCTAssertTrue(modelOnly.shortText.contains("Native Runtime 不可用"))
        XCTAssertTrue(modelOnly.detailText.contains("bert-vits2-MNN"))

        let runtimeOnly = manager.inspect(
            modelRoot: root,
            runtimeAvailable: true,
            runtimeSummary: "test runtime ready",
            requiredFiles: requiredFiles
        )
        XCTAssertTrue(runtimeOnly.modelReady)
        XCTAssertFalse(runtimeOnly.ready)
        XCTAssertTrue(runtimeOnly.shortText.contains("音质验收未通过"))

        let ready = manager.inspect(
            modelRoot: root,
            runtimeAvailable: true,
            runtimeSummary: "test runtime ready",
            voiceQualityPassed: true,
            requiredFiles: requiredFiles
        )
        XCTAssertTrue(ready.modelReady)
        XCTAssertTrue(ready.ready)
        XCTAssertTrue(ready.missing.isEmpty)
    }

    func testLocalASRZipExtractionAcceptsAndroidVoskArchiveLayout() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("silvercare-asr-zip-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let prefix = "\(LocalASRModelManifest.voskChineseDirectory)/"
        let deflatedOK = Data([203, 207, 6, 0])
        var entries = [
            ZipFixtureEntry(name: prefix, method: 0, compressedData: Data(), uncompressedData: Data())
        ]
        for required in LocalASRModelManifest.requiredFiles {
            entries.append(ZipFixtureEntry(
                name: prefix + required,
                method: 8,
                compressedData: deflatedOK,
                uncompressedData: Data("ok".utf8)
            ))
        }

        let zip = root.appendingPathComponent("vosk-model.zip")
        try makeZip(entries: entries).write(to: zip)

        let manager = LocalASRModelManager(fileManager: fileManager)
        try manager.extractChineseModelZip(zip: zip, modelRoot: root)

        let status = manager.inspect(modelRoot: root, runtimeAvailable: false)
        XCTAssertTrue(status.modelReady)
        XCTAssertEqual(status.missing, ["iOS Vosk Runtime"])
        for required in LocalASRModelManifest.requiredFiles {
            let file = status.modelDirectory.appendingPathComponent(required)
            XCTAssertEqual(try Data(contentsOf: file), Data("ok".utf8))
        }
    }

    func testLocalASRZipExtractionRejectsUnsafePaths() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("silvercare-asr-zip-slip-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let zip = root.appendingPathComponent("evil.zip")
        try makeZip(entries: [
            ZipFixtureEntry(
                name: "\(LocalASRModelManifest.voskChineseDirectory)/../evil.txt",
                method: 0,
                compressedData: Data("bad".utf8),
                uncompressedData: Data("bad".utf8)
            )
        ]).write(to: zip)

        let manager = LocalASRModelManager(fileManager: fileManager)
        XCTAssertThrowsError(try manager.extractChineseModelZip(zip: zip, modelRoot: root)) { error in
            XCTAssertTrue(error.localizedDescription.contains("路径不安全"))
        }
        XCTAssertFalse(fileManager.fileExists(atPath: root.appendingPathComponent("evil.txt").path))
    }
}

private struct ZipFixtureEntry {
    let name: String
    let method: UInt16
    let compressedData: Data
    let uncompressedData: Data
}

private func makeZip(entries: [ZipFixtureEntry]) -> Data {
    var output = Data()
    var centralDirectory = Data()

    for entry in entries {
        let nameData = Data(entry.name.utf8)
        let localOffset = UInt32(output.count)
        appendUInt32(0x04034b50, to: &output)
        appendUInt16(20, to: &output)
        appendUInt16(0, to: &output)
        appendUInt16(entry.method, to: &output)
        appendUInt16(0, to: &output)
        appendUInt16(0, to: &output)
        appendUInt32(0, to: &output)
        appendUInt32(UInt32(entry.compressedData.count), to: &output)
        appendUInt32(UInt32(entry.uncompressedData.count), to: &output)
        appendUInt16(UInt16(nameData.count), to: &output)
        appendUInt16(0, to: &output)
        output.append(nameData)
        output.append(entry.compressedData)

        appendUInt32(0x02014b50, to: &centralDirectory)
        appendUInt16(20, to: &centralDirectory)
        appendUInt16(20, to: &centralDirectory)
        appendUInt16(0, to: &centralDirectory)
        appendUInt16(entry.method, to: &centralDirectory)
        appendUInt16(0, to: &centralDirectory)
        appendUInt16(0, to: &centralDirectory)
        appendUInt32(0, to: &centralDirectory)
        appendUInt32(UInt32(entry.compressedData.count), to: &centralDirectory)
        appendUInt32(UInt32(entry.uncompressedData.count), to: &centralDirectory)
        appendUInt16(UInt16(nameData.count), to: &centralDirectory)
        appendUInt16(0, to: &centralDirectory)
        appendUInt16(0, to: &centralDirectory)
        appendUInt16(0, to: &centralDirectory)
        appendUInt16(0, to: &centralDirectory)
        appendUInt32(0, to: &centralDirectory)
        appendUInt32(localOffset, to: &centralDirectory)
        centralDirectory.append(nameData)
    }

    let centralOffset = UInt32(output.count)
    output.append(centralDirectory)
    appendUInt32(0x06054b50, to: &output)
    appendUInt16(0, to: &output)
    appendUInt16(0, to: &output)
    appendUInt16(UInt16(entries.count), to: &output)
    appendUInt16(UInt16(entries.count), to: &output)
    appendUInt32(UInt32(centralDirectory.count), to: &output)
    appendUInt32(centralOffset, to: &output)
    appendUInt16(0, to: &output)
    return output
}

private func appendUInt16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
}

private func appendUInt32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 24) & 0xff))
}

private final class CapturingTransport: DashScopeJSONTransport {
    var endpoints: [URL] = []
    var payloads: [[String: Any]] = []
    var apiKeys: [String] = []
    var responses: [[String: Any]] = []

    func postJSON(endpoint: URL, payload: [String: Any], apiKey: String) throws -> [String: Any] {
        endpoints.append(endpoint)
        payloads.append(payload)
        apiKeys.append(apiKey)
        return responses.isEmpty ? [:] : responses.removeFirst()
    }
}
