import Foundation
import zlib

public struct OfflineModelDownloadFile: Equatable {
    public let relativePath: String
    public let expectedBytes: Int64
    public let urls: [URL]

    public init(relativePath: String, expectedBytes: Int64, urls: [URL]) {
        self.relativePath = relativePath
        self.expectedBytes = expectedBytes
        self.urls = urls
    }
}

public enum OfflineModelManifest {
    public static let automaticModelDirectoryName = "multimodal_care_models"
    public static let qwen4BDirectory = "Qwen3-4B-Instruct-2507-MNN"
    public static let bundledDetectorResource = "offline/damo-yolo.mnn"
    public static let bundledDetectorFile = "damo-yolo.mnn"
    public static let bundledDetectorBytes: Int64 = 34_058_720
    public static let qwen4BHFBase = "https://huggingface.co/taobao-mnn/Qwen3-4B-Instruct-2507-MNN/resolve/main/"
    public static let textModel4B = "qwen3-4b-instruct-2507-mnn"
    public static let textModel15B = "qwen2.5-1.5b-instruct-mnn"

    public static let qwen4BFiles: [OfflineModelDownloadFile] = [
        qwen4BFile("config.json", expectedBytes: 403),
        qwen4BFile("llm.mnn", expectedBytes: 592_336),
        qwen4BFile("llm.mnn.json", expectedBytes: 1_243_600),
        qwen4BFile("llm.mnn.weight", expectedBytes: 2_709_972_658),
        qwen4BFile("llm_config.json", expectedBytes: 4_803),
        qwen4BFile("tokenizer.txt", expectedBytes: 3_193_555)
    ]

    public static var expectedTotalBytes: Int64 {
        qwen4BFiles.reduce(bundledDetectorBytes) { $0 + $1.expectedBytes }
    }

    public static func cleanTextModel(_ textModel: String) -> String {
        let lower = textModel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower == textModel15B || lower.contains("1.5b") || lower.contains("1_5b") {
            return textModel15B
        }
        return textModel4B
    }

    public static func textModelLabel(_ textModel: String) -> String {
        cleanTextModel(textModel) == textModel15B
            ? "Qwen2.5-1.5B-Instruct-MNN"
            : "Qwen3-4B-Instruct-2507-MNN"
    }

    public static func humanBytes(_ bytes: Int64) -> String {
        var value = Double(max(0, bytes))
        let units = ["B", "KB", "MB", "GB"]
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return String(format: "%.1f%@", value, units[index])
    }

    private static func qwen4BFile(_ name: String, expectedBytes: Int64) -> OfflineModelDownloadFile {
        let relativePath = "\(qwen4BDirectory)/\(name)"
        return OfflineModelDownloadFile(
            relativePath: relativePath,
            expectedBytes: expectedBytes,
            urls: [URL(string: qwen4BHFBase + name)!]
        )
    }
}

public enum SilverCareModelPathResolver {
    public static let modelRootOverrideEnvironmentKey = "SILVERCARE_IOS_MODEL_ROOT"

    public static func automaticModelDirectory(fileManager: FileManager = .default) -> URL {
        if let override = ProcessInfo.processInfo.environment[modelRootOverrideEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return resolveOverride(override, fileManager: fileManager)
        }

        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("SilverCare", isDirectory: true)
            .appendingPathComponent(OfflineModelManifest.automaticModelDirectoryName, isDirectory: true)
    }

    private static func resolveOverride(_ value: String, fileManager: FileManager) -> URL {
        let expanded = (value as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }

        var relative = expanded
        if relative == "Documents" {
            relative = ""
        } else if relative.hasPrefix("Documents/") {
            relative.removeFirst("Documents/".count)
        }

        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return relative.isEmpty
            ? documents
            : documents.appendingPathComponent(relative, isDirectory: true)
    }
}

public struct OfflineModelStatus {
    public let modelDirectory: URL
    public let textModel: String
    public let textConfigURL: URL?
    public let yoloModelURL: URL?
    public let nativeRuntimeAvailable: Bool
    public let directoryReadable: Bool
    public let textReady: Bool
    public let yoloReady: Bool
    public let missing: [String]

    public var ready: Bool {
        nativeRuntimeAvailable && directoryReadable && textReady && yoloReady
    }

    public var visionReady: Bool {
        nativeRuntimeAvailable && directoryReadable && yoloReady
    }

    public var textInferenceReady: Bool {
        nativeRuntimeAvailable && directoryReadable && textReady
    }

    public var visionMissing: [String] {
        var items: [String] = []
        if !nativeRuntimeAvailable { items.append("MNN Native Runtime") }
        if !directoryReadable { items.append("模型目录不可读") }
        if !yoloReady { items.append("DAMO-YOLO .mnn") }
        return items
    }

    public var textInferenceMissing: [String] {
        var items: [String] = []
        if !nativeRuntimeAvailable { items.append("MNN Native Runtime") }
        if !directoryReadable { items.append("模型目录不可读") }
        if !textReady { items.append("\(OfflineModelManifest.textModelLabel(textModel))/config.json") }
        return items
    }

    public var shortText: String {
        if ready { return "端侧离线模型已就绪" }
        if missing.isEmpty { return "端侧离线模型未就绪" }
        return "端侧离线模型未就绪：" + missing.joined(separator: "、")
    }

    public var visionShortText: String {
        if visionReady { return "端侧视觉模型已就绪" }
        if visionMissing.isEmpty { return "端侧视觉模型未就绪" }
        return "端侧视觉模型未就绪：" + visionMissing.joined(separator: "、")
    }

    public var textInferenceShortText: String {
        if textInferenceReady { return "端侧文本模型已就绪" }
        if textInferenceMissing.isEmpty { return "端侧文本模型未就绪" }
        return "端侧文本模型未就绪：" + textInferenceMissing.joined(separator: "、")
    }

    public var detailText: String {
        [
            shortText,
            "",
            "模型目录：\(modelDirectory.path)",
            "离线文本模型：\(OfflineModelManifest.textModelLabel(textModel))",
            "文本模型文件：\(textReady ? textConfigURL?.path ?? "未找到 config.json" : "未找到 config.json")",
            "DAMO-YOLO：\(yoloReady ? yoloModelURL?.path ?? "未找到 .mnn 模型" : "未找到 .mnn 模型")",
            "MNN Native Runtime：\(nativeRuntimeAvailable ? "已加载" : "未加载 iOS MNN runtime")"
        ].joined(separator: "\n")
    }

    public var payload: [String: Any] {
        [
            "model_directory": modelDirectory.path,
            "text_model": textModel,
            "text_ready": textReady,
            "yolo_ready": yoloReady,
            "vision_ready": visionReady,
            "vision_missing": visionMissing,
            "vision_status_text": visionShortText,
            "text_inference_ready": textInferenceReady,
            "text_inference_missing": textInferenceMissing,
            "text_inference_status_text": textInferenceShortText,
            "native_runtime_available": nativeRuntimeAvailable,
            "directory_readable": directoryReadable,
            "ready": ready,
            "missing": missing,
            "short_text": shortText,
            "detail_text": detailText
        ]
    }
}

public struct OfflineModelDownloadProgress {
    public let message: String
    public let downloadedBytes: Int64
    public let totalBytes: Int64
    public let complete: Bool
    public let failed: Bool

    public init(
        message: String,
        downloadedBytes: Int64,
        totalBytes: Int64,
        complete: Bool,
        failed: Bool
    ) {
        self.message = message
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.complete = complete
        self.failed = failed
    }

    public var percent: Int {
        guard totalBytes > 0 else { return 0 }
        return Int(min(100, max(0, (downloadedBytes * 100) / totalBytes)))
    }

    public var payload: [String: Any] {
        [
            "text": message,
            "downloaded_bytes": downloadedBytes,
            "total_bytes": totalBytes,
            "percent": percent,
            "complete": complete,
            "failed": failed
        ]
    }
}

public struct OfflineModelDownloadResult {
    public let modelDirectory: URL
    public let totalBytes: Int64
}

public struct LocalASRModelDownloadResult {
    public let modelRoot: URL
    public let modelDirectory: URL
    public let totalBytes: Int64
}

public enum LocalASRModelManifest {
    public static let asrDirectory = "asr"
    public static let voskChineseDirectory = "vosk-model-small-cn-0.22"
    public static let expectedZipBytes: Int64 = 43_898_754
    public static let sourceURL = URL(string: "https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip")!
    public static let requiredFiles = [
        "am/final.mdl",
        "conf/model.conf",
        "graph/HCLr.fst",
        "graph/Gr.fst",
        "ivector/final.ie"
    ]
}

public struct LocalASRModelStatus: Equatable {
    public let modelRoot: URL
    public let modelDirectory: URL
    public let directoryReadable: Bool
    public let modelReady: Bool
    public let runtimeAvailable: Bool
    public let missing: [String]

    public var ready: Bool {
        modelReady && runtimeAvailable
    }

    public var shortText: String {
        if ready { return "本地语音识别模型已就绪" }
        if missing.isEmpty { return "本地语音识别模型未就绪" }
        return "本地语音识别模型未就绪：" + missing.joined(separator: "、")
    }

    public var detailText: String {
        [
            shortText,
            "",
            "模型目录：\(modelDirectory.path)",
            "模型来源：Vosk 中文小模型 \(LocalASRModelManifest.voskChineseDirectory)",
            "下载大小：约 \(OfflineModelManifest.humanBytes(LocalASRModelManifest.expectedZipBytes))",
            "用途：端侧离线语音转文字，录音不会上传。",
            "iOS Vosk Runtime：\(runtimeAvailable ? "已绑定" : "尚未绑定")"
        ].joined(separator: "\n")
    }

    public var payload: [String: Any] {
        [
            "model_root": modelRoot.path,
            "model_directory": modelDirectory.path,
            "directory_readable": directoryReadable,
            "model_ready": modelReady,
            "runtime_available": runtimeAvailable,
            "ready": ready,
            "missing": missing,
            "short_text": shortText,
            "detail_text": detailText
        ]
    }
}

public final class LocalASRModelManager {
    public typealias ProgressHandler = (OfflineModelDownloadProgress) -> Void

    private let fileManager: FileManager
    private let session: URLSession

    private static let minFreeSpaceBuffer: Int64 = 256 * 1024 * 1024
    private static let bufferSize = 256 * 1024
    private static let progressStepBytes: Int64 = 2 * 1024 * 1024

    public init(fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
    }

    public func automaticModelRoot() -> URL {
        SilverCareModelPathResolver
            .automaticModelDirectory(fileManager: fileManager)
            .appendingPathComponent(LocalASRModelManifest.asrDirectory, isDirectory: true)
    }

    public func inspect(
        modelRoot: URL? = nil,
        runtimeAvailable: Bool = false
    ) -> LocalASRModelStatus {
        let root = modelRoot ?? automaticModelRoot()
        let modelDirectory = root.appendingPathComponent(LocalASRModelManifest.voskChineseDirectory, isDirectory: true)
        let directoryReadable = isReadableDirectory(root)

        var missing: [String] = []
        if !directoryReadable { missing.append("ASR 模型目录不可读") }
        if !isReadableDirectory(modelDirectory) {
            missing.append(LocalASRModelManifest.voskChineseDirectory)
        } else {
            for required in LocalASRModelManifest.requiredFiles {
                let file = modelDirectory.appendingPathComponent(required)
                if !fileManager.isReadableFile(atPath: file.path) {
                    missing.append(required)
                }
            }
        }
        if !runtimeAvailable { missing.append("iOS Vosk Runtime") }

        let modelMissing = missing.filter { $0 != "iOS Vosk Runtime" }
        return LocalASRModelStatus(
            modelRoot: root,
            modelDirectory: modelDirectory,
            directoryReadable: directoryReadable,
            modelReady: modelMissing.isEmpty && directoryReadable,
            runtimeAvailable: runtimeAvailable,
            missing: missing
        )
    }

    public func ensureChineseModel(progress: ProgressHandler? = nil) async throws -> LocalASRModelDownloadResult {
        let root = automaticModelRoot()
        try ensureDirectory(root)

        var status = inspect(modelRoot: root, runtimeAvailable: false)
        if status.modelReady {
            progress?(OfflineModelDownloadProgress(
                message: "本地 ASR 模型已存在",
                downloadedBytes: LocalASRModelManifest.expectedZipBytes,
                totalBytes: LocalASRModelManifest.expectedZipBytes,
                complete: true,
                failed: false
            ))
            return LocalASRModelDownloadResult(
                modelRoot: root,
                modelDirectory: status.modelDirectory,
                totalBytes: LocalASRModelManifest.expectedZipBytes
            )
        }

        try ensureFreeSpace(root: root, missingBytes: LocalASRModelManifest.expectedZipBytes)
        let zip = root.appendingPathComponent("\(LocalASRModelManifest.voskChineseDirectory).zip")
        if !isComplete(zip, expectedBytes: LocalASRModelManifest.expectedZipBytes) {
            try await downloadZip(to: zip, progress: progress)
        } else {
            progress?(OfflineModelDownloadProgress(
                message: "本地 ASR 压缩包已存在",
                downloadedBytes: LocalASRModelManifest.expectedZipBytes,
                totalBytes: LocalASRModelManifest.expectedZipBytes,
                complete: false,
                failed: false
            ))
        }

        progress?(OfflineModelDownloadProgress(
            message: "正在解压本地 ASR 模型",
            downloadedBytes: LocalASRModelManifest.expectedZipBytes,
            totalBytes: LocalASRModelManifest.expectedZipBytes,
            complete: false,
            failed: false
        ))
        try extractChineseModelZip(zip: zip, modelRoot: root)

        status = inspect(modelRoot: root, runtimeAvailable: false)
        guard status.modelReady else {
            throw SilverCareCoreError.modelNotReady(status.shortText)
        }
        progress?(OfflineModelDownloadProgress(
            message: "本地 ASR 模型下载完成",
            downloadedBytes: LocalASRModelManifest.expectedZipBytes,
            totalBytes: LocalASRModelManifest.expectedZipBytes,
            complete: true,
            failed: false
        ))
        return LocalASRModelDownloadResult(
            modelRoot: root,
            modelDirectory: status.modelDirectory,
            totalBytes: LocalASRModelManifest.expectedZipBytes
        )
    }

    public func extractChineseModelZip(zip: URL, modelRoot root: URL) throws {
        let modelDirectory = root.appendingPathComponent(LocalASRModelManifest.voskChineseDirectory, isDirectory: true)
        let tempDirectory = root.appendingPathComponent("\(LocalASRModelManifest.voskChineseDirectory).tmp", isDirectory: true)
        try safeDeleteRecursively(tempDirectory, allowedRoot: root)
        try ensureDirectory(tempDirectory)

        let prefix = "\(LocalASRModelManifest.voskChineseDirectory)/"
        let entries = try zipEntries(zip)
        for entry in entries {
            let name = entry.name.replacingOccurrences(of: "\\", with: "/")
            guard name.hasPrefix(prefix) else { continue }
            let relative = String(name.dropFirst(prefix.count))
            guard !relative.isEmpty else { continue }
            let target = try safeChild(root: tempDirectory, relativePath: relative)
            if entry.isDirectory {
                try ensureDirectory(target)
                continue
            }

            try ensureDirectory(target.deletingLastPathComponent())
            let data: Data
            switch entry.compressionMethod {
            case 0:
                data = entry.compressedData
            case 8:
                data = try inflateRaw(entry.compressedData, expectedSize: entry.uncompressedSize)
            default:
                throw SilverCareCoreError.modelNotReady("ASR 模型压缩包使用了不支持的压缩方式：\(entry.compressionMethod)")
            }
            try data.write(to: target, options: .atomic)
        }

        try safeDeleteRecursively(modelDirectory, allowedRoot: root)
        try fileManager.moveItem(at: tempDirectory, to: modelDirectory)
    }

    private func isReadableDirectory(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && fileManager.isReadableFile(atPath: url.path)
    }

    private func downloadZip(to target: URL, progress: ProgressHandler?) async throws {
        let part = URL(fileURLWithPath: target.path + ".part")
        if fileSize(part) > LocalASRModelManifest.expectedZipBytes {
            try? fileManager.removeItem(at: part)
        }
        if fileManager.fileExists(atPath: target.path) {
            try? fileManager.removeItem(at: target)
        }

        var existing = min(fileSize(part), LocalASRModelManifest.expectedZipBytes)
        progress?(OfflineModelDownloadProgress(
            message: "正在下载本地 ASR 模型",
            downloadedBytes: existing,
            totalBytes: LocalASRModelManifest.expectedZipBytes,
            complete: false,
            failed: false
        ))

        var request = URLRequest(url: LocalASRModelManifest.sourceURL)
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
            existing = 0
            append = false
        }
        if statusCode == 416 && isComplete(part, expectedBytes: LocalASRModelManifest.expectedZipBytes) {
            try replaceFile(part, target: target)
            return
        }
        guard statusCode >= 200, statusCode < 300 else {
            throw SilverCareCoreError.transport("本地 ASR 模型下载失败：HTTP \(statusCode)")
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

        var downloaded = existing
        var sinceProgress: Int64 = 0
        var buffer = Data(capacity: Self.bufferSize)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= Self.bufferSize {
                output.write(buffer)
                let count = Int64(buffer.count)
                downloaded = min(LocalASRModelManifest.expectedZipBytes, downloaded + count)
                sinceProgress += count
                buffer.removeAll(keepingCapacity: true)
                if sinceProgress >= Self.progressStepBytes {
                    sinceProgress = 0
                    progress?(OfflineModelDownloadProgress(
                        message: "正在下载本地 ASR 模型",
                        downloadedBytes: downloaded,
                        totalBytes: LocalASRModelManifest.expectedZipBytes,
                        complete: false,
                        failed: false
                    ))
                }
            }
        }
        if !buffer.isEmpty {
            output.write(buffer)
            downloaded = min(LocalASRModelManifest.expectedZipBytes, downloaded + Int64(buffer.count))
        }

        guard isComplete(part, expectedBytes: LocalASRModelManifest.expectedZipBytes) else {
            throw SilverCareCoreError.transport(
                "本地 ASR 模型下载不完整，已下载 \(OfflineModelManifest.humanBytes(fileSize(part))) / \(OfflineModelManifest.humanBytes(LocalASRModelManifest.expectedZipBytes))"
            )
        }
        try replaceFile(part, target: target)
        progress?(OfflineModelDownloadProgress(
            message: "本地 ASR 模型下载完成",
            downloadedBytes: LocalASRModelManifest.expectedZipBytes,
            totalBytes: LocalASRModelManifest.expectedZipBytes,
            complete: false,
            failed: false
        ))
    }

    private struct ZipEntryInfo {
        let name: String
        let compressionMethod: UInt16
        let compressedData: Data
        let uncompressedSize: Int

        var isDirectory: Bool {
            name.hasSuffix("/")
        }
    }

    private func zipEntries(_ zip: URL) throws -> [ZipEntryInfo] {
        let data = try Data(contentsOf: zip)
        let eocd = try findEndOfCentralDirectory(in: data)
        let totalEntries = Int(try uint16(data, eocd + 10))
        let centralSize = Int(try uint32(data, eocd + 12))
        var offset = Int(try uint32(data, eocd + 16))
        let centralEnd = offset + centralSize
        guard offset >= 0, centralEnd <= data.count else {
            throw SilverCareCoreError.invalidJSON("ASR 模型压缩包中央目录越界。")
        }

        var entries: [ZipEntryInfo] = []
        for _ in 0..<totalEntries {
            guard offset + 46 <= centralEnd, try uint32(data, offset) == 0x02014b50 else {
                throw SilverCareCoreError.invalidJSON("ASR 模型压缩包中央目录损坏。")
            }
            let flags = try uint16(data, offset + 8)
            let method = try uint16(data, offset + 10)
            let compressedSize = Int(try uint32(data, offset + 20))
            let uncompressedSize = Int(try uint32(data, offset + 24))
            let fileNameLength = Int(try uint16(data, offset + 28))
            let extraLength = Int(try uint16(data, offset + 30))
            let commentLength = Int(try uint16(data, offset + 32))
            let localHeaderOffset = Int(try uint32(data, offset + 42))
            let nameStart = offset + 46
            let nameEnd = nameStart + fileNameLength
            guard nameEnd <= centralEnd else {
                throw SilverCareCoreError.invalidJSON("ASR 模型压缩包文件名越界。")
            }
            let nameData = data[nameStart..<nameEnd]
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? ""
            if flags & 0x0001 != 0 {
                throw SilverCareCoreError.modelNotReady("ASR 模型压缩包不应加密。")
            }
            guard localHeaderOffset + 30 <= data.count, try uint32(data, localHeaderOffset) == 0x04034b50 else {
                throw SilverCareCoreError.invalidJSON("ASR 模型压缩包本地文件头损坏。")
            }
            let localNameLength = Int(try uint16(data, localHeaderOffset + 26))
            let localExtraLength = Int(try uint16(data, localHeaderOffset + 28))
            let dataStart = localHeaderOffset + 30 + localNameLength + localExtraLength
            let dataEnd = dataStart + compressedSize
            guard compressedSize >= 0, uncompressedSize >= 0, dataStart >= 0, dataEnd <= data.count else {
                throw SilverCareCoreError.invalidJSON("ASR 模型压缩包数据越界。")
            }
            entries.append(ZipEntryInfo(
                name: name,
                compressionMethod: method,
                compressedData: Data(data[dataStart..<dataEnd]),
                uncompressedSize: uncompressedSize
            ))
            offset = nameEnd + extraLength + commentLength
        }
        return entries
    }

    private func findEndOfCentralDirectory(in data: Data) throws -> Int {
        guard data.count >= 22 else {
            throw SilverCareCoreError.invalidJSON("ASR 模型压缩包过小。")
        }
        let lowerBound = max(0, data.count - 65_557)
        var offset = data.count - 22
        while offset >= lowerBound {
            if try uint32(data, offset) == 0x06054b50 {
                return offset
            }
            offset -= 1
        }
        throw SilverCareCoreError.invalidJSON("ASR 模型压缩包缺少中央目录。")
    }

    private func inflateRaw(_ compressed: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0 else {
            throw SilverCareCoreError.invalidJSON("ASR 模型压缩包解压大小无效。")
        }
        if expectedSize == 0 { return Data() }
        var output = Data(count: expectedSize)
        let outputCount = output.count
        let result: (Int32, UInt) = compressed.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                var stream = z_stream()
                stream.next_in = UnsafeMutablePointer<Bytef>(
                    mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress
                )
                stream.avail_in = uInt(compressed.count)
                stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outputCount)
                let initStatus = inflateInit2_(
                    &stream,
                    -MAX_WBITS,
                    ZLIB_VERSION,
                    Int32(MemoryLayout<z_stream>.size)
                )
                guard initStatus == Z_OK else {
                    return (initStatus, 0)
                }
                defer { inflateEnd(&stream) }
                let status = inflate(&stream, Z_FINISH)
                return (status, UInt(stream.total_out))
            }
        }
        guard result.0 == Z_STREAM_END, result.1 == UInt(expectedSize) else {
            throw SilverCareCoreError.invalidJSON("ASR 模型压缩包解压失败：zlib \(result.0)")
        }
        return output
    }

    private func uint16(_ data: Data, _ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else {
            throw SilverCareCoreError.invalidJSON("ASR 模型压缩包读取越界。")
        }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func uint32(_ data: Data, _ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else {
            throw SilverCareCoreError.invalidJSON("ASR 模型压缩包读取越界。")
        }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func safeChild(root: URL, relativePath: String) throws -> URL {
        let target = root.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        let targetPath = target.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
            throw SilverCareCoreError.modelNotReady("ASR 模型压缩包路径不安全：\(relativePath)")
        }
        return target
    }

    private func safeDeleteRecursively(_ target: URL, allowedRoot: URL) throws {
        guard fileManager.fileExists(atPath: target.path) else { return }
        let allowedPath = allowedRoot.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        guard targetPath.hasPrefix(allowedPath + "/") else {
            throw SilverCareCoreError.modelNotReady("拒绝删除模型目录外文件：\(targetPath)")
        }
        try deleteRecursively(target)
    }

    private func deleteRecursively(_ url: URL) throws {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            let children = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for child in children {
                try deleteRecursively(child)
            }
        }
        try fileManager.removeItem(at: url)
    }

    private func ensureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func ensureFreeSpace(root: URL, missingBytes: Int64) throws {
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? values.volumeAvailableCapacity.map(Int64.init)
            ?? 0
        let required = missingBytes + Self.minFreeSpaceBuffer
        guard available >= required else {
            throw SilverCareCoreError.modelNotReady(
                "存储空间不足。本地 ASR 模型下载约 \(OfflineModelManifest.humanBytes(missingBytes))，请至少保留 \(OfflineModelManifest.humanBytes(required)) 可用空间。"
            )
        }
    }

    private func isComplete(_ url: URL, expectedBytes: Int64) -> Bool {
        fileSize(url) == expectedBytes
    }

    private func fileSize(_ url: URL) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else { return 0 }
        return size.int64Value
    }

    private func replaceFile(_ source: URL, target: URL) throws {
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        try fileManager.moveItem(at: source, to: target)
    }
}

public final class OfflineModelManager {
    public typealias ProgressHandler = (OfflineModelDownloadProgress) -> Void

    private let fileManager: FileManager
    private let bundle: Bundle
    private let session: URLSession

    private static let minFreeSpaceBuffer: Int64 = 512 * 1024 * 1024
    private static let bufferSize = 256 * 1024
    private static let progressStepBytes: Int64 = 8 * 1024 * 1024

    private static let textConfigCandidates4B = [
        "Qwen3-4B-Instruct-2507-MNN/config.json",
        "qwen3-4b-instruct-2507-mnn/config.json",
        "qwen-text-4b/config.json",
        "text-4b/config.json"
    ]

    private static let textConfigCandidates15B = [
        "Qwen2.5-1.5B-Instruct-MNN/config.json",
        "qwen2.5-1.5b-instruct-mnn/config.json",
        "qwen2_5-1_5b-instruct-mnn/config.json",
        "qwen-text-1.5b/config.json",
        "text-1.5b/config.json"
    ]

    private static let yoloModelCandidates = [
        "damo-yolo.mnn",
        "damo_yolo.mnn",
        "DAMO-YOLO.mnn",
        "yolo.mnn",
        "detector/damo-yolo.mnn",
        "detector/damo_yolo.mnn"
    ]

    public init(
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        session: URLSession = .shared
    ) {
        self.fileManager = fileManager
        self.bundle = bundle
        self.session = session
    }

    public func automaticModelDirectory() -> URL {
        SilverCareModelPathResolver.automaticModelDirectory(fileManager: fileManager)
    }

    public func inspect(
        modelDirectory: URL? = nil,
        textModel: String = OfflineModelManifest.textModel4B,
        nativeRuntimeAvailable: Bool
    ) -> OfflineModelStatus {
        let root = modelDirectory ?? automaticModelDirectory()
        let cleanTextModel = OfflineModelManifest.cleanTextModel(textModel)
        let directoryReadable = isReadableDirectory(root)
        let textConfig = directoryReadable ? findExisting(root: root, candidates: textConfigCandidates(cleanTextModel)) : nil
        let yoloModel = directoryReadable ? findExisting(root: root, candidates: Self.yoloModelCandidates) : nil

        var missing: [String] = []
        if !nativeRuntimeAvailable { missing.append("MNN Native Runtime") }
        if !directoryReadable { missing.append("模型目录不可读") }
        if textConfig == nil { missing.append("\(OfflineModelManifest.textModelLabel(cleanTextModel))/config.json") }
        if yoloModel == nil { missing.append("DAMO-YOLO .mnn") }

        return OfflineModelStatus(
            modelDirectory: root,
            textModel: cleanTextModel,
            textConfigURL: textConfig,
            yoloModelURL: yoloModel,
            nativeRuntimeAvailable: nativeRuntimeAvailable,
            directoryReadable: directoryReadable,
            textReady: textConfig != nil,
            yoloReady: yoloModel != nil,
            missing: missing
        )
    }

    public func prepareQwen4BBundle(progress: ProgressHandler? = nil) async throws -> OfflineModelDownloadResult {
        let root = automaticModelDirectory()
        try ensureDirectory(root)
        try ensureFreeSpace(root: root, missingBytes: missingBytes(root), totalBytes: OfflineModelManifest.expectedTotalBytes)

        let tracker = Progress(totalBytes: OfflineModelManifest.expectedTotalBytes)
        try copyBundledDetector(to: root, tracker: tracker, progress: progress)
        for item in OfflineModelManifest.qwen4BFiles {
            try await downloadFile(root: root, item: item, tracker: tracker, progress: progress)
        }

        progress?(tracker.snapshot(message: "离线模型下载完成", complete: true))
        return OfflineModelDownloadResult(modelDirectory: root, totalBytes: tracker.totalBytes)
    }

    private func textConfigCandidates(_ textModel: String) -> [String] {
        OfflineModelManifest.cleanTextModel(textModel) == OfflineModelManifest.textModel15B
            ? Self.textConfigCandidates15B
            : Self.textConfigCandidates4B
    }

    private func isReadableDirectory(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && fileManager.isReadableFile(atPath: url.path)
    }

    private func findExisting(root: URL, candidates: [String]) -> URL? {
        candidates
            .map { root.appendingPathComponent($0) }
            .first { fileManager.isReadableFile(atPath: $0.path) }
    }

    private func ensureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func missingBytes(_ root: URL) -> Int64 {
        var missing: Int64 = isComplete(
            root.appendingPathComponent(OfflineModelManifest.bundledDetectorFile),
            expectedBytes: OfflineModelManifest.bundledDetectorBytes
        ) ? 0 : OfflineModelManifest.bundledDetectorBytes
        for item in OfflineModelManifest.qwen4BFiles {
            if !isComplete(root.appendingPathComponent(item.relativePath), expectedBytes: item.expectedBytes) {
                missing += item.expectedBytes
            }
        }
        return missing
    }

    private func ensureFreeSpace(root: URL, missingBytes: Int64, totalBytes: Int64) throws {
        guard missingBytes > 0 else { return }
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? values.volumeAvailableCapacity.map(Int64.init)
            ?? 0
        let required = missingBytes + Self.minFreeSpaceBuffer
        guard available >= required else {
            throw SilverCareCoreError.modelNotReady(
                "存储空间不足。离线模型总大小约 \(OfflineModelManifest.humanBytes(totalBytes))，当前还需要 \(OfflineModelManifest.humanBytes(missingBytes))，请至少保留 \(OfflineModelManifest.humanBytes(required)) 可用空间。"
            )
        }
    }

    private func copyBundledDetector(
        to root: URL,
        tracker: Progress,
        progress: ProgressHandler?
    ) throws {
        let target = root.appendingPathComponent(OfflineModelManifest.bundledDetectorFile)
        if isComplete(target, expectedBytes: OfflineModelManifest.bundledDetectorBytes) {
            tracker.add(OfflineModelManifest.bundledDetectorBytes)
            progress?(tracker.snapshot(message: "DAMO-YOLO 检测模型已就绪"))
            return
        }

        guard let source = bundledDetectorURL() else {
            throw SilverCareCoreError.modelNotReady("未找到内置 DAMO-YOLO 检测模型资源：\(OfflineModelManifest.bundledDetectorResource)")
        }

        let part = target.appendingPathExtension("part")
        try? fileManager.removeItem(at: part)
        progress?(tracker.snapshot(message: "正在准备 DAMO-YOLO 检测模型"))

        let input = try FileHandle(forReadingFrom: source)
        fileManager.createFile(atPath: part.path, contents: nil)
        let output = try FileHandle(forWritingTo: part)
        defer {
            try? input.close()
            try? output.close()
        }

        var copied: Int64 = 0
        var lastProgress: Int64 = 0
        while true {
            let data = input.readData(ofLength: Self.bufferSize)
            if data.isEmpty { break }
            output.write(data)
            let count = Int64(data.count)
            copied += count
            tracker.add(count)
            if copied - lastProgress >= Self.progressStepBytes {
                lastProgress = copied
                progress?(tracker.snapshot(message: "正在复制 DAMO-YOLO 检测模型"))
            }
        }

        try replaceFile(part, target: target)
        guard isComplete(target, expectedBytes: OfflineModelManifest.bundledDetectorBytes) else {
            throw SilverCareCoreError.modelNotReady("DAMO-YOLO 检测模型复制不完整。")
        }
        progress?(tracker.snapshot(message: "DAMO-YOLO 检测模型已就绪"))
    }

    private func bundledDetectorURL() -> URL? {
        let candidates = [
            bundle.url(forResource: "damo-yolo", withExtension: "mnn", subdirectory: "offline"),
            bundle.url(forResource: "damo-yolo", withExtension: "mnn", subdirectory: "WebAssets/offline"),
            bundle.resourceURL?.appendingPathComponent("offline/damo-yolo.mnn"),
            bundle.resourceURL?.appendingPathComponent("WebAssets/offline/damo-yolo.mnn")
        ]
        return candidates.compactMap { $0 }.first { fileManager.isReadableFile(atPath: $0.path) }
    }

    private func downloadFile(
        root: URL,
        item: OfflineModelDownloadFile,
        tracker: Progress,
        progress: ProgressHandler?
    ) async throws {
        let target = root.appendingPathComponent(item.relativePath)
        if isComplete(target, expectedBytes: item.expectedBytes) {
            tracker.add(item.expectedBytes)
            progress?(tracker.snapshot(message: "已存在：\(item.relativePath)"))
            return
        }

        try ensureDirectory(target.deletingLastPathComponent())
        var lastError: Error?
        for url in item.urls {
            do {
                try await streamURL(url, target: target, item: item, tracker: tracker, progress: progress)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? SilverCareCoreError.transport("下载失败：\(item.relativePath)")
    }

    private func streamURL(
        _ url: URL,
        target: URL,
        item: OfflineModelDownloadFile,
        tracker: Progress,
        progress: ProgressHandler?
    ) async throws {
        let part = URL(fileURLWithPath: target.path + ".part")
        if isComplete(part, expectedBytes: item.expectedBytes) {
            try replaceFile(part, target: target)
            progress?(tracker.snapshot(message: "下载完成：\(item.relativePath)"))
            return
        }
        if fileManager.fileExists(atPath: target.path) {
            try? fileManager.removeItem(at: target)
        }
        if fileSize(part) > item.expectedBytes {
            try? fileManager.removeItem(at: part)
        }

        var existing = min(fileSize(part), item.expectedBytes)
        if existing > 0 { tracker.add(existing) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("SilverCareiOS/1.0", forHTTPHeaderField: "User-Agent")
        if existing > 0 {
            request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
        }

        progress?(tracker.snapshot(message: "正在下载：\(item.relativePath)"))
        let (bytes, response) = try await session.bytes(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
        var append = existing > 0 && statusCode == 206
        if existing > 0 && statusCode == 200 {
            tracker.subtract(existing)
            existing = 0
            append = false
        }
        if statusCode == 416 && isComplete(part, expectedBytes: item.expectedBytes) {
            try replaceFile(part, target: target)
            progress?(tracker.snapshot(message: "下载完成：\(item.relativePath)"))
            return
        }
        guard statusCode >= 200, statusCode < 300 else {
            throw SilverCareCoreError.transport("HTTP \(statusCode)：\(item.relativePath)")
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

        var buffer = Data(capacity: Self.bufferSize)
        var sinceProgress: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= Self.bufferSize {
                output.write(buffer)
                let count = Int64(buffer.count)
                tracker.add(count)
                sinceProgress += count
                buffer.removeAll(keepingCapacity: true)
                if sinceProgress >= Self.progressStepBytes {
                    sinceProgress = 0
                    progress?(tracker.snapshot(message: "正在下载：\(item.relativePath)"))
                }
            }
        }
        if !buffer.isEmpty {
            output.write(buffer)
            let count = Int64(buffer.count)
            tracker.add(count)
        }

        guard isComplete(part, expectedBytes: item.expectedBytes) else {
            throw SilverCareCoreError.transport(
                "下载不完整：\(item.relativePath)，已下载 \(OfflineModelManifest.humanBytes(fileSize(part))) / \(OfflineModelManifest.humanBytes(item.expectedBytes))"
            )
        }
        try replaceFile(part, target: target)
        progress?(tracker.snapshot(message: "下载完成：\(item.relativePath)"))
    }

    private func isComplete(_ url: URL, expectedBytes: Int64) -> Bool {
        fileSize(url) == expectedBytes
    }

    private func fileSize(_ url: URL) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else { return 0 }
        return size.int64Value
    }

    private func replaceFile(_ source: URL, target: URL) throws {
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        try fileManager.moveItem(at: source, to: target)
    }

    private final class Progress {
        let totalBytes: Int64
        private(set) var downloadedBytes: Int64 = 0

        init(totalBytes: Int64) {
            self.totalBytes = totalBytes
        }

        func add(_ bytes: Int64) {
            downloadedBytes = min(totalBytes, downloadedBytes + max(0, bytes))
        }

        func subtract(_ bytes: Int64) {
            downloadedBytes = max(0, downloadedBytes - max(0, bytes))
        }

        func snapshot(message: String, complete: Bool = false, failed: Bool = false) -> OfflineModelDownloadProgress {
            OfflineModelDownloadProgress(
                message: message,
                downloadedBytes: downloadedBytes,
                totalBytes: totalBytes,
                complete: complete,
                failed: failed
            )
        }
    }
}
