import Darwin
import Foundation
import SilverCareCore

final class LocalVoskASRRuntime: @unchecked Sendable {
    enum RuntimeError: Error, LocalizedError {
        case libraryUnavailable
        case missingSymbol(String)
        case modelUnavailable(String)
        case recognizerUnavailable
        case audioTooShort
        case noTranscript

        var errorDescription: String? {
            switch self {
            case .libraryUnavailable:
                return "iOS Vosk ASR Runtime 尚未绑定。请打包 libvosk.framework/libvosk.dylib，或将 libvosk.a 链入 App 后再使用本地 ASR。"
            case .missingSymbol(let symbol):
                return "iOS Vosk ASR Runtime 缺少符号：\(symbol)。"
            case .modelUnavailable(let path):
                return "无法加载本地 ASR 模型：\(path)。"
            case .recognizerUnavailable:
                return "无法创建本地 ASR 识别器。"
            case .audioTooShort:
                return "录音太短，请按住说完整问题。"
            case .noTranscript:
                return "本地 ASR 没有识别到清晰语音。"
            }
        }
    }

    private typealias ModelNew = @convention(c) (UnsafePointer<CChar>) -> OpaquePointer?
    private typealias ModelFree = @convention(c) (OpaquePointer?) -> Void
    private typealias RecognizerNew = @convention(c) (OpaquePointer?, Float) -> OpaquePointer?
    private typealias RecognizerFree = @convention(c) (OpaquePointer?) -> Void
    private typealias RecognizerSetWords = @convention(c) (OpaquePointer?, Int32) -> Void
    private typealias RecognizerAcceptWaveform = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int32) -> Int32
    private typealias RecognizerFinalResult = @convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?
    private typealias SetLogLevel = @convention(c) (Int32) -> Void

    private struct Symbols {
        let modelNew: ModelNew
        let modelFree: ModelFree
        let recognizerNew: RecognizerNew
        let recognizerFree: RecognizerFree
        let recognizerSetWords: RecognizerSetWords
        let recognizerAcceptWaveform: RecognizerAcceptWaveform
        let recognizerFinalResult: RecognizerFinalResult
        let setLogLevel: SetLogLevel?
    }

    private struct LibraryCandidate {
        let handle: UnsafeMutableRawPointer
        let shouldClose: Bool
    }

    private static let sampleRate: Float = 16_000
    private static let chunkBytes = 4096
    private static let minimumPCMBytes = 1600

    private let bundle: Bundle
    private let lock = NSLock()
    private var libraryHandle: UnsafeMutableRawPointer?
    private var shouldCloseLibraryHandle = false
    private var symbols: Symbols?
    private var model: OpaquePointer?
    private var modelPath: String?
    private var loadFailure: Error?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return (try? loadSymbolsLocked()) != nil
    }

    func transcribe(modelDirectory: URL, pcm16: Data) throws -> String {
        guard pcm16.count >= Self.minimumPCMBytes else { throw RuntimeError.audioTooShort }
        lock.lock()
        defer { lock.unlock() }

        let symbols = try loadSymbolsLocked()
        symbols.setLogLevel?(2)
        let activeModel = try modelForLocked(modelDirectory: modelDirectory, symbols: symbols)
        guard let recognizer = symbols.recognizerNew(activeModel, Self.sampleRate) else {
            throw RuntimeError.recognizerUnavailable
        }
        defer { symbols.recognizerFree(recognizer) }
        symbols.recognizerSetWords(recognizer, 0)

        try pcm16.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: CChar.self).baseAddress else {
                throw RuntimeError.audioTooShort
            }
            var offset = 0
            while offset < pcm16.count {
                let length = min(Self.chunkBytes, pcm16.count - offset)
                _ = symbols.recognizerAcceptWaveform(recognizer, base.advanced(by: offset), Int32(length))
                offset += length
            }
        }

        guard let resultPointer = symbols.recognizerFinalResult(recognizer) else {
            throw RuntimeError.noTranscript
        }
        let transcript = LocalVoskTranscriptParser.parseTranscript(String(cString: resultPointer))
        guard !transcript.isEmpty else { throw RuntimeError.noTranscript }
        return transcript
    }

    private func modelForLocked(modelDirectory: URL, symbols: Symbols) throws -> OpaquePointer {
        let path = modelDirectory.path
        if let model, modelPath == path { return model }
        if let model {
            symbols.modelFree(model)
            self.model = nil
            self.modelPath = nil
        }
        guard let loaded = path.withCString({ symbols.modelNew($0) }) else {
            throw RuntimeError.modelUnavailable(path)
        }
        model = loaded
        modelPath = path
        return loaded
    }

    private func loadSymbolsLocked() throws -> Symbols {
        if let symbols { return symbols }
        if let loadFailure { throw loadFailure }

        var lastError: Error = RuntimeError.libraryUnavailable
        for candidate in libraryCandidates() {
            do {
                let loaded = Symbols(
                    modelNew: try load("vosk_model_new", from: candidate.handle, as: ModelNew.self),
                    modelFree: try load("vosk_model_free", from: candidate.handle, as: ModelFree.self),
                    recognizerNew: try load("vosk_recognizer_new", from: candidate.handle, as: RecognizerNew.self),
                    recognizerFree: try load("vosk_recognizer_free", from: candidate.handle, as: RecognizerFree.self),
                    recognizerSetWords: try load("vosk_recognizer_set_words", from: candidate.handle, as: RecognizerSetWords.self),
                    recognizerAcceptWaveform: try load("vosk_recognizer_accept_waveform", from: candidate.handle, as: RecognizerAcceptWaveform.self),
                    recognizerFinalResult: try load("vosk_recognizer_final_result", from: candidate.handle, as: RecognizerFinalResult.self),
                    setLogLevel: try? load("vosk_set_log_level", from: candidate.handle, as: SetLogLevel.self)
                )
                libraryHandle = candidate.handle
                shouldCloseLibraryHandle = candidate.shouldClose
                symbols = loaded
                return loaded
            } catch {
                lastError = error
                if candidate.shouldClose {
                    dlclose(candidate.handle)
                }
            }
        }

        loadFailure = lastError
        throw lastError
    }

    private func libraryCandidates() -> [LibraryCandidate] {
        var candidates: [LibraryCandidate] = []
        if let handle = dlopen(nil, RTLD_NOW) {
            candidates.append(LibraryCandidate(handle: handle, shouldClose: false))
        }
        for path in candidateLibraryPaths() {
            if let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) {
                candidates.append(LibraryCandidate(handle: handle, shouldClose: true))
            }
        }
        if let handle = dlopen("libvosk.dylib", RTLD_NOW | RTLD_LOCAL) {
            candidates.append(LibraryCandidate(handle: handle, shouldClose: true))
        }
        if let handle = dlopen("vosk.framework/vosk", RTLD_NOW | RTLD_LOCAL) {
            candidates.append(LibraryCandidate(handle: handle, shouldClose: true))
        }
        return candidates
    }

    private func candidateLibraryPaths() -> [String] {
        var paths: [String] = []
        let environmentPath = ProcessInfo.processInfo.environment["SILVERCARE_VOSK_LIBRARY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentPath, !environmentPath.isEmpty {
            paths.append(environmentPath)
        }
        let frameworkRoots = [
            bundle.privateFrameworksURL,
            bundle.bundleURL.appendingPathComponent("Frameworks", isDirectory: true)
        ].compactMap { $0 }
        for root in frameworkRoots {
            paths.append(root.appendingPathComponent("vosk.framework/vosk").path)
            paths.append(root.appendingPathComponent("libvosk.framework/libvosk").path)
            paths.append(root.appendingPathComponent("libvosk.dylib").path)
        }
        paths.append(bundle.bundleURL.appendingPathComponent("libvosk.dylib").path)
        return Array(dictKeysPreservingOrder: paths)
    }

    private func load<T>(_ symbol: String, from handle: UnsafeMutableRawPointer, as type: T.Type) throws -> T {
        guard let pointer = dlsym(handle, symbol) else {
            throw RuntimeError.missingSymbol(symbol)
        }
        return unsafeBitCast(pointer, to: type)
    }

    deinit {
        lock.lock()
        if let model, let symbols {
            symbols.modelFree(model)
        }
        model = nil
        modelPath = nil
        if let libraryHandle, shouldCloseLibraryHandle {
            dlclose(libraryHandle)
        }
        libraryHandle = nil
        shouldCloseLibraryHandle = false
        lock.unlock()
    }
}

private extension Array where Element == String {
    init(dictKeysPreservingOrder values: [String]) {
        var seen = Set<String>()
        self = values.filter { value in
            guard !seen.contains(value) else { return false }
            seen.insert(value)
            return true
        }
    }
}
