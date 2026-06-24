import XCTest
@testable import SilverCareCore

final class ModelManifestTests: XCTestCase {
    func testQwen4BManifestContainsRequiredMnnFilesOnly() {
        let paths = OfflineModelManifest.qwen4BFiles.map(\.relativePath)

        XCTAssertEqual(Set(paths), [
            "Qwen3-4B-Instruct-2507-MNN/config.json",
            "Qwen3-4B-Instruct-2507-MNN/llm.mnn",
            "Qwen3-4B-Instruct-2507-MNN/llm.mnn.json",
            "Qwen3-4B-Instruct-2507-MNN/llm.mnn.weight",
            "Qwen3-4B-Instruct-2507-MNN/llm_config.json",
            "Qwen3-4B-Instruct-2507-MNN/tokenizer.txt"
        ])
        XCTAssertEqual(paths.count, 6)
    }

    func testQwen4BManifestUsesDirectHuggingFaceResolveUrls() {
        for item in OfflineModelManifest.qwen4BFiles {
            XCTAssertEqual(item.urls.count, 1)
            XCTAssertTrue(item.urls[0].absoluteString.hasPrefix(OfflineModelManifest.qwen4BHFBase))
            XCTAssertTrue(item.urls[0].absoluteString.hasSuffix(item.relativePath.replacingOccurrences(
                of: "\(OfflineModelManifest.qwen4BDirectory)/",
                with: ""
            )))
            XCTAssertGreaterThan(item.expectedBytes, 0)
        }
    }

    func testOfflineModelExpectedTotalIncludesBundledDetectorAndQwenFiles() {
        let expected = OfflineModelManifest.bundledDetectorBytes
            + OfflineModelManifest.qwen4BFiles.reduce(Int64(0)) { $0 + $1.expectedBytes }

        XCTAssertEqual(OfflineModelManifest.expectedTotalBytes, expected)
        XCTAssertEqual(OfflineModelManifest.bundledDetectorFile, "damo-yolo.mnn")
        XCTAssertGreaterThan(OfflineModelManifest.expectedTotalBytes, 2_000_000_000)
    }

    func testOfflineModelInspectionReportsMissingRuntimeAndModels() {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("silvercare-offline-missing-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let status = OfflineModelManager(fileManager: fileManager).inspect(
            modelDirectory: root,
            nativeRuntimeAvailable: false
        )

        XCTAssertFalse(status.ready)
        XCTAssertFalse(status.visionReady)
        XCTAssertFalse(status.textInferenceReady)
        XCTAssertTrue(status.shortText.contains("未就绪"))
        XCTAssertEqual(status.visionMissing, [
            "MNN Native Runtime",
            "模型目录不可读",
            "DAMO-YOLO .mnn"
        ])
        XCTAssertEqual(status.textInferenceMissing, [
            "MNN Native Runtime",
            "模型目录不可读",
            "Qwen3-4B-Instruct-2507-MNN/config.json"
        ])
        XCTAssertEqual(status.missing, [
            "MNN Native Runtime",
            "模型目录不可读",
            "Qwen3-4B-Instruct-2507-MNN/config.json",
            "DAMO-YOLO .mnn"
        ])
    }

    func testOfflineModelInspectionAcceptsExpectedOfflineModelLayout() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("silvercare-offline-ready-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let textConfig = root
            .appendingPathComponent(OfflineModelManifest.qwen4BDirectory, isDirectory: true)
            .appendingPathComponent("config.json")
        try fileManager.createDirectory(at: textConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileManager.createFile(atPath: textConfig.path, contents: Data("{}".utf8))
        fileManager.createFile(
            atPath: root.appendingPathComponent(OfflineModelManifest.bundledDetectorFile).path,
            contents: Data("mnn".utf8)
        )

        let status = OfflineModelManager(fileManager: fileManager).inspect(
            modelDirectory: root,
            nativeRuntimeAvailable: true
        )

        XCTAssertTrue(status.ready)
        XCTAssertTrue(status.textReady)
        XCTAssertTrue(status.yoloReady)
        XCTAssertTrue(status.visionReady)
        XCTAssertTrue(status.textInferenceReady)
        XCTAssertEqual(status.shortText, "端侧离线模型已就绪")
    }

    func testOfflineModelInspectionSeparatesVisionAndTextReadiness() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("silvercare-offline-vision-only-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        fileManager.createFile(
            atPath: root.appendingPathComponent(OfflineModelManifest.bundledDetectorFile).path,
            contents: Data("mnn".utf8)
        )

        let status = OfflineModelManager(fileManager: fileManager).inspect(
            modelDirectory: root,
            nativeRuntimeAvailable: true
        )

        XCTAssertFalse(status.ready)
        XCTAssertTrue(status.visionReady)
        XCTAssertFalse(status.textInferenceReady)
        XCTAssertEqual(status.visionShortText, "端侧视觉模型已就绪")
        XCTAssertEqual(status.textInferenceMissing, ["Qwen3-4B-Instruct-2507-MNN/config.json"])
        XCTAssertTrue(status.textInferenceShortText.contains("Qwen3-4B-Instruct-2507-MNN/config.json"))
        XCTAssertEqual(status.payload["vision_ready"] as? Bool, true)
        XCTAssertEqual(status.payload["text_inference_ready"] as? Bool, false)
    }

    func testOfflineModelInspectionReportsSelectedBackupModelWhenMissing() {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("silvercare-offline-missing-15b-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let status = OfflineModelManager(fileManager: fileManager).inspect(
            modelDirectory: root,
            textModel: OfflineModelManifest.textModel15B,
            nativeRuntimeAvailable: true
        )

        XCTAssertFalse(status.ready)
        XCTAssertEqual(status.textModel, OfflineModelManifest.textModel15B)
        XCTAssertEqual(status.missing, [
            "模型目录不可读",
            "Qwen2.5-1.5B-Instruct-MNN/config.json",
            "DAMO-YOLO .mnn"
        ])
    }

    func testLocalASRManifestUsesDirectVoskModelUrlAndHumanSize() {
        XCTAssertTrue(LocalASRModelManifest.sourceURL.absoluteString.contains("alphacephei.com/vosk/models/"))
        XCTAssertTrue(LocalASRModelManifest.sourceURL.absoluteString.contains(LocalASRModelManifest.voskChineseDirectory))
        XCTAssertGreaterThan(LocalASRModelManifest.expectedZipBytes, 40 * 1024 * 1024)
        XCTAssertTrue(OfflineModelManifest.humanBytes(LocalASRModelManifest.expectedZipBytes).contains("MB"))
    }

    func testMnnTTSManifestTargetsBertVitsArtifacts() {
        XCTAssertEqual(LocalTTSModelManifest.requiredFiles.count, 23)
        XCTAssertEqual(LocalTTSModelManifest.requiredFiles[0].relativePath, "config.json")
        XCTAssertTrue(LocalTTSModelManifest.requiredFiles[0].urls[0].absoluteString.contains("bert-vits2-MNN"))
        XCTAssertTrue(LocalTTSModelManifest.requiredFiles[0].urls[0].absoluteString.hasSuffix("config.json"))
        XCTAssertEqual(
            LocalTTSModelManifest.requiredFiles[4].relativePath,
            "common/mnn_models/chinese_bert.mnn.weight"
        )
        XCTAssertEqual(
            LocalTTSModelManifest.requiredFiles[6].relativePath,
            "common/mnn_models/english_bert.mnn.weight"
        )
    }

    func testMnnTTSExpectedSizeIncludesBertVitsModelAndTextAssets() {
        let expected = LocalTTSModelManifest.requiredFiles.reduce(Int64(0)) { $0 + $1.expectedBytes }

        XCTAssertEqual(LocalTTSModelManifest.expectedTotalBytes, expected)
        XCTAssertGreaterThan(LocalTTSModelManifest.expectedTotalBytes, 1_300_000_000)
        XCTAssertLessThan(LocalTTSModelManifest.expectedTotalBytes, 1_500_000_000)
        XCTAssertTrue(OfflineModelManifest.humanBytes(LocalTTSModelManifest.expectedTotalBytes).contains("GB"))
    }
}
