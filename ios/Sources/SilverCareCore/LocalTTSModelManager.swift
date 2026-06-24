import Foundation

public struct LocalTTSModelDownloadResult {
    public let modelRoot: URL
    public let modelDirectory: URL
    public let totalBytes: Int64
}

public enum LocalTTSModelManifest {
    public static let ttsDirectory = "tts"
    public static let mnnTTSDirectory = "bert-vits2-mnn"
    public static let modelName = "bert-vits2-MNN"
    public static let hfBase = "https://huggingface.co/taobao-mnn/bert-vits2-MNN/resolve/main/"

    public static let requiredFiles: [OfflineModelDownloadFile] = [
        file("config.json", expectedBytes: 172),
        file("tokenizer.txt", expectedBytes: 156_256),
        file("tts_generator_w_bert_chenxi_0310_int8.mnn", expectedBytes: 50_457_744),
        file("common/mnn_models/chinese_bert.mnn", expectedBytes: 595_296),
        file("common/mnn_models/chinese_bert.mnn.weight", expectedBytes: 367_494_936),
        file("common/mnn_models/english_bert.mnn", expectedBytes: 416_016),
        file("common/mnn_models/english_bert.mnn.weight", expectedBytes: 929_559_392),
        file("common/text_processing_jsons/char_state.bin", expectedBytes: 949_364),
        file("common/text_processing_jsons/cn_bert_token.bin", expectedBytes: 341_956),
        file("common/text_processing_jsons/default_tone_words.json", expectedBytes: 6_249),
        file("common/text_processing_jsons/en_bert_token.json", expectedBytes: 3_011_214),
        file("common/text_processing_jsons/eng_dict.bin", expectedBytes: 13_716_655),
        file("common/text_processing_jsons/hotwords_cn.bin", expectedBytes: 5_081),
        file("common/text_processing_jsons/hotwords_cn.json", expectedBytes: 14_232),
        file("common/text_processing_jsons/phrases_dict.bin", expectedBytes: 2_834_832),
        file("common/text_processing_jsons/pinyin_dict.bin", expectedBytes: 1_117_037),
        file("common/text_processing_jsons/pinyin_to_symbol_map.bin", expectedBytes: 5_809),
        file("common/text_processing_jsons/prob_emit.bin", expectedBytes: 1_701_802),
        file("common/text_processing_jsons/prob_start.bin", expectedBytes: 5_292),
        file("common/text_processing_jsons/prob_trans.bin", expectedBytes: 112_039),
        file("common/text_processing_jsons/tokenizer.txt", expectedBytes: 156_256),
        file("common/text_processing_jsons/word_freq.bin", expectedBytes: 10_251_325),
        file("common/text_processing_jsons/word_tag.bin", expectedBytes: 9_111_009)
    ]

    public static var expectedTotalBytes: Int64 {
        requiredFiles.reduce(0) { $0 + $1.expectedBytes }
    }

    private static func file(_ name: String, expectedBytes: Int64) -> OfflineModelDownloadFile {
        OfflineModelDownloadFile(
            relativePath: name,
            expectedBytes: expectedBytes,
            urls: [URL(string: hfBase + name)!]
        )
    }
}

public struct LocalTTSModelStatus: Equatable {
    public let modelRoot: URL
    public let modelDirectory: URL
    public let runtimeAvailable: Bool
    public let runtimeSummary: String
    public let directoryReadable: Bool
    public let modelReady: Bool
    public let voiceQualityPassed: Bool
    public let missing: [String]

    public var ready: Bool {
        modelReady && runtimeAvailable && voiceQualityPassed
    }

    public var shortText: String {
        if ready { return "本地 MNN TTS 已就绪" }
        if modelReady && runtimeAvailable && !voiceQualityPassed { return "本地 MNN TTS Runtime 已绑定，但音质验收未通过" }
        if modelReady && !runtimeAvailable { return "本地 MNN TTS 模型已下载，Native Runtime 不可用" }
        if missing.isEmpty { return "本地 MNN TTS 未就绪" }
        return "本地 MNN TTS 未就绪：" + missing.joined(separator: "、")
    }

    public var detailText: String {
        [
            shortText,
            "",
            "模型目录：\(modelDirectory.path)",
            "模型来源：\(LocalTTSModelManifest.modelName)",
            "下载大小：约 \(OfflineModelManifest.humanBytes(LocalTTSModelManifest.expectedTotalBytes))",
            "Native Runtime：\(runtimeAvailable ? "已就绪，" : "不可用，")\(runtimeSummary.isEmpty ? "无运行时信息" : runtimeSummary)",
            "音质验收：\(voiceQualityPassed ? "已通过" : "未通过")",
            "用途：端侧离线文字转语音，朗读内容不上云。",
            "注意：本地 MNN TTS 仍为实验项，未通过真实可懂度验收前不会作为主朗读方案。"
        ].joined(separator: "\n")
    }

    public var payload: [String: Any] {
        [
            "model_root": modelRoot.path,
            "model_directory": modelDirectory.path,
            "runtime_available": runtimeAvailable,
            "runtime_summary": runtimeSummary,
            "directory_readable": directoryReadable,
            "model_ready": modelReady,
            "voice_quality_passed": voiceQualityPassed,
            "ready": ready,
            "missing": missing,
            "short_text": shortText,
            "detail_text": detailText
        ]
    }
}

public final class LocalTTSModelManager {
    public typealias ProgressHandler = (OfflineModelDownloadProgress) -> Void

    private let fileManager: FileManager
    private let session: URLSession

    private static let minFreeSpaceBuffer: Int64 = 512 * 1024 * 1024
    private static let bufferSize = 256 * 1024
    private static let progressStepBytes: Int64 = 8 * 1024 * 1024

    public init(fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
    }

    public func automaticModelRoot() -> URL {
        SilverCareModelPathResolver
            .automaticModelDirectory(fileManager: fileManager)
            .appendingPathComponent(LocalTTSModelManifest.ttsDirectory, isDirectory: true)
    }

    public func inspect(
        modelRoot: URL? = nil,
        runtimeAvailable: Bool = false,
        runtimeSummary: String = "iOS MNN TTS Runtime 尚未绑定",
        voiceQualityPassed: Bool = false,
        requiredFiles: [OfflineModelDownloadFile] = LocalTTSModelManifest.requiredFiles
    ) -> LocalTTSModelStatus {
        let root = modelRoot ?? automaticModelRoot()
        let modelDirectory = root.appendingPathComponent(LocalTTSModelManifest.mnnTTSDirectory, isDirectory: true)
        let directoryReadable = isReadableDirectory(root)

        var missing: [String] = []
        if !directoryReadable {
            missing.append("TTS 模型目录不可读")
        }
        if !isReadableDirectory(modelDirectory) {
            missing.append(LocalTTSModelManifest.mnnTTSDirectory)
        } else {
            for item in requiredFiles {
                let file = modelDirectory.appendingPathComponent(item.relativePath)
                if !isComplete(file, expectedBytes: item.expectedBytes) {
                    missing.append(item.relativePath)
                }
            }
        }

        return LocalTTSModelStatus(
            modelRoot: root,
            modelDirectory: modelDirectory,
            runtimeAvailable: runtimeAvailable,
            runtimeSummary: runtimeSummary,
            directoryReadable: directoryReadable,
            modelReady: missing.isEmpty && directoryReadable,
            voiceQualityPassed: voiceQualityPassed,
            missing: missing
        )
    }

    public func ensureMNNBundle(progress: ProgressHandler? = nil) async throws -> LocalTTSModelDownloadResult {
        let root = automaticModelRoot()
        try ensureDirectory(root)
        let modelDirectory = root.appendingPathComponent(LocalTTSModelManifest.mnnTTSDirectory, isDirectory: true)
        try ensureDirectory(modelDirectory)

        var status = inspect(modelRoot: root, runtimeAvailable: false)
        if status.modelReady {
            progress?(OfflineModelDownloadProgress(
                message: "本地 MNN TTS 模型已存在",
                downloadedBytes: LocalTTSModelManifest.expectedTotalBytes,
                totalBytes: LocalTTSModelManifest.expectedTotalBytes,
                complete: true,
                failed: false
            ))
            return LocalTTSModelDownloadResult(
                modelRoot: root,
                modelDirectory: status.modelDirectory,
                totalBytes: LocalTTSModelManifest.expectedTotalBytes
            )
        }

        let missing = missingBytes(modelDirectory: modelDirectory)
        try ensureFreeSpace(root: root, missingBytes: missing)
        let state = DownloadProgressState(total: LocalTTSModelManifest.expectedTotalBytes)
        for item in LocalTTSModelManifest.requiredFiles {
            try await downloadFile(item, modelDirectory: modelDirectory, state: state, progress: progress)
        }

        status = inspect(modelRoot: root, runtimeAvailable: false)
        guard status.modelReady else {
            throw SilverCareCoreError.modelNotReady(status.shortText)
        }
        progress?(OfflineModelDownloadProgress(
            message: "本地 MNN TTS 模型下载完成",
            downloadedBytes: LocalTTSModelManifest.expectedTotalBytes,
            totalBytes: LocalTTSModelManifest.expectedTotalBytes,
            complete: true,
            failed: false
        ))
        return LocalTTSModelDownloadResult(
            modelRoot: root,
            modelDirectory: status.modelDirectory,
            totalBytes: LocalTTSModelManifest.expectedTotalBytes
        )
    }

    private func downloadFile(
        _ item: OfflineModelDownloadFile,
        modelDirectory: URL,
        state: DownloadProgressState,
        progress: ProgressHandler?
    ) async throws {
        let target = modelDirectory.appendingPathComponent(item.relativePath)
        try ensureDirectory(target.deletingLastPathComponent())
        if isComplete(target, expectedBytes: item.expectedBytes) {
            state.add(item.expectedBytes)
            progress?(OfflineModelDownloadProgress(
                message: "已存在：\(item.relativePath)",
                downloadedBytes: state.done,
                totalBytes: state.total,
                complete: false,
                failed: false
            ))
            return
        }

        if fileManager.fileExists(atPath: target.path) {
            try? fileManager.removeItem(at: target)
        }
        let part = URL(fileURLWithPath: target.path + ".part")
        if fileSize(part) > item.expectedBytes {
            try? fileManager.removeItem(at: part)
        }

        var existing = min(fileSize(part), item.expectedBytes)
        if existing > 0 {
            state.add(existing)
        }
        progress?(OfflineModelDownloadProgress(
            message: "正在下载：\(item.relativePath)",
            downloadedBytes: state.done,
            totalBytes: state.total,
            complete: false,
            failed: false
        ))

        var lastError: Error?
        for url in item.urls {
            do {
                try await downloadFileURL(url, item: item, target: target, part: part, existing: existing, state: state, progress: progress)
                return
            } catch {
                lastError = error
                if existing > 0 {
                    state.subtract(existing)
                    existing = 0
                }
            }
        }
        throw lastError ?? SilverCareCoreError.transport("本地 MNN TTS 下载失败：\(item.relativePath)")
    }

    private func downloadFileURL(
        _ url: URL,
        item: OfflineModelDownloadFile,
        target: URL,
        part: URL,
        existing: Int64,
        state: DownloadProgressState,
        progress: ProgressHandler?
    ) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("SilverCareiOS/1.0", forHTTPHeaderField: "User-Agent")
        if existing > 0 {
            request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
        }

        let (bytes, response) = try await session.bytes(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
        var append = existing > 0 && statusCode == 206
        if existing > 0 && statusCode == 200 {
            state.subtract(existing)
            append = false
        }
        if statusCode == 416 && isComplete(part, expectedBytes: item.expectedBytes) {
            try replaceFile(part, target: target)
            return
        }
        guard statusCode >= 200, statusCode < 300 else {
            throw SilverCareCoreError.transport("本地 MNN TTS 下载失败：HTTP \(statusCode)：\(item.relativePath)")
        }

        if !append {
            try? fileManager.removeItem(at: part)
            fileManager.createFile(atPath: part.path, contents: nil)
        } else if !fileManager.fileExists(atPath: part.path) {
            fileManager.createFile(atPath: part.path, contents: nil)
        }

        let output = try FileHandle(forWritingTo: part)
        defer { try? output.close() }
        if append {
            try output.seekToEnd()
        }

        var sinceProgress: Int64 = 0
        var buffer = Data(capacity: Self.bufferSize)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= Self.bufferSize {
                output.write(buffer)
                let count = Int64(buffer.count)
                state.add(count)
                sinceProgress += count
                buffer.removeAll(keepingCapacity: true)
                if sinceProgress >= Self.progressStepBytes {
                    sinceProgress = 0
                    progress?(OfflineModelDownloadProgress(
                        message: "正在下载：\(item.relativePath)",
                        downloadedBytes: state.done,
                        totalBytes: state.total,
                        complete: false,
                        failed: false
                    ))
                }
            }
        }
        if !buffer.isEmpty {
            output.write(buffer)
            state.add(Int64(buffer.count))
        }

        guard isComplete(part, expectedBytes: item.expectedBytes) else {
            throw SilverCareCoreError.transport(
                "本地 MNN TTS 下载不完整：\(item.relativePath)，已下载 \(OfflineModelManifest.humanBytes(fileSize(part))) / \(OfflineModelManifest.humanBytes(item.expectedBytes))"
            )
        }
        try replaceFile(part, target: target)
        progress?(OfflineModelDownloadProgress(
            message: "下载完成：\(item.relativePath)",
            downloadedBytes: state.done,
            totalBytes: state.total,
            complete: false,
            failed: false
        ))
    }

    private func missingBytes(modelDirectory: URL) -> Int64 {
        LocalTTSModelManifest.requiredFiles.reduce(0) { total, item in
            let file = modelDirectory.appendingPathComponent(item.relativePath)
            return isComplete(file, expectedBytes: item.expectedBytes) ? total : total + item.expectedBytes
        }
    }

    private func isReadableDirectory(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && fileManager.isReadableFile(atPath: url.path)
    }

    private func ensureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func fileSize(_ url: URL) -> Int64 {
        let value = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        return value ?? 0
    }

    private func isComplete(_ url: URL, expectedBytes: Int64) -> Bool {
        fileManager.isReadableFile(atPath: url.path) && fileSize(url) == expectedBytes
    }

    private func replaceFile(_ source: URL, target: URL) throws {
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        try fileManager.moveItem(at: source, to: target)
    }

    private func ensureFreeSpace(root: URL, missingBytes: Int64) throws {
        guard missingBytes > 0 else { return }
        let values = try root.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        let available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
        let required = missingBytes + Self.minFreeSpaceBuffer
        if available > 0 && available < required {
            throw SilverCareCoreError.modelNotReady(
                "存储空间不足。本地 TTS 模型总大小约 \(OfflineModelManifest.humanBytes(LocalTTSModelManifest.expectedTotalBytes))，当前还需要 \(OfflineModelManifest.humanBytes(missingBytes))，请至少保留 \(OfflineModelManifest.humanBytes(required)) 可用空间。"
            )
        }
    }
}

private final class DownloadProgressState {
    let total: Int64
    private(set) var done: Int64 = 0

    init(total: Int64) {
        self.total = total
    }

    func add(_ bytes: Int64) {
        done = min(total, done + max(0, bytes))
    }

    func subtract(_ bytes: Int64) {
        done = max(0, done - max(0, bytes))
    }
}
