import Darwin
import Foundation
import SilverCareCore

final class DynamicIOSMNNTTSRuntime: @unchecked Sendable {
    enum RuntimeError: Error, LocalizedError {
        case libraryUnavailable
        case synthesisUnavailable
        case invalidOutput

        var errorDescription: String? {
            switch self {
            case .libraryUnavailable:
                return "iOS MNN TTS Runtime 尚未绑定。请打包 SilverCareMNNTTSRuntime.framework 或 libsilvercare_mnn_tts_runtime.dylib。"
            case .synthesisUnavailable:
                return "iOS MNN TTS 未生成有效音频。"
            case .invalidOutput:
                return "iOS MNN TTS 返回了无效 WAV 路径。"
            }
        }
    }

    private typealias RuntimeKindFn = @convention(c) () -> UnsafePointer<CChar>?
    private typealias VoiceQualityPassedFn = @convention(c) () -> Int32
    private typealias SynthesizeWavFn = @convention(c) (
        UnsafePointer<CChar>,
        UnsafePointer<CChar>,
        UnsafePointer<CChar>,
        UnsafePointer<CChar>
    ) -> UnsafeMutablePointer<CChar>?
    private typealias FreeStringFn = @convention(c) (UnsafeMutablePointer<CChar>) -> Void

    private struct Symbols {
        let runtimeKind: RuntimeKindFn
        let voiceQualityPassed: VoiceQualityPassedFn
        let synthesizeWav: SynthesizeWavFn
        let freeString: FreeStringFn?
    }

    private let bundle: Bundle
    private let lock = NSLock()
    private var symbols: Symbols?
    private var loadAttempted = false

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return loadSymbolsLocked() != nil
    }

    var voiceQualityPassed: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let symbols = loadSymbolsLocked() else { return false }
        return symbols.voiceQualityPassed() != 0
    }

    var runtimeSummary: String {
        lock.lock()
        defer { lock.unlock() }
        guard let symbols = loadSymbolsLocked() else { return "iOS MNN TTS Runtime 未加载" }
        let kind = symbols.runtimeKind().map { String(cString: $0) } ?? "mnn-tts-ios"
        let quality = symbols.voiceQualityPassed() != 0 ? "音质验收已通过" : "音质验收未通过"
        return "\(kind) · \(quality)"
    }

    func synthesizeToWav(modelDirectory: URL, cacheDirectory: URL, text: String, language: String) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RuntimeError.synthesisUnavailable }
        lock.lock()
        let loaded = loadSymbolsLocked()
        lock.unlock()
        guard let loaded else { throw RuntimeError.libraryUnavailable }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let outputPath = try modelDirectory.path.withCString { modelPtr in
            try cacheDirectory.path.withCString { cachePtr in
                try trimmed.withCString { textPtr in
                    try language.withCString { languagePtr in
                        guard let output = loaded.synthesizeWav(modelPtr, cachePtr, textPtr, languagePtr) else {
                            throw RuntimeError.synthesisUnavailable
                        }
                        defer { loaded.freeString?(output) }
                        return String(cString: output)
                    }
                }
            }
        }
        guard !outputPath.isEmpty else { throw RuntimeError.invalidOutput }
        let url = URL(fileURLWithPath: outputPath)
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw RuntimeError.invalidOutput
        }
        return url
    }

    private func loadSymbolsLocked() -> Symbols? {
        if let symbols { return symbols }
        if loadAttempted { return nil }
        loadAttempted = true
        for handle in candidateLibraryHandles() {
            guard let runtimeKind: RuntimeKindFn = load("silvercare_mnn_tts_runtime_kind", from: handle),
                  let voiceQualityPassed: VoiceQualityPassedFn = load("silvercare_mnn_tts_voice_quality_passed", from: handle),
                  let synthesizeWav: SynthesizeWavFn = load("silvercare_mnn_tts_synthesize_wav", from: handle)
            else {
                continue
            }
            let freeString: FreeStringFn? = load("silvercare_mnn_tts_free_string", from: handle)
            let loaded = Symbols(
                runtimeKind: runtimeKind,
                voiceQualityPassed: voiceQualityPassed,
                synthesizeWav: synthesizeWav,
                freeString: freeString
            )
            symbols = loaded
            return loaded
        }
        return nil
    }

    private func candidateLibraryHandles() -> [UnsafeMutableRawPointer] {
        var handles: [UnsafeMutableRawPointer] = []
        if let handle = dlopen(nil, RTLD_NOW) {
            handles.append(handle)
        }
        for path in candidateLibraryPaths() {
            if let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) {
                handles.append(handle)
            }
        }
        for name in [
            "libsilvercare_mnn_tts_runtime.dylib",
            "SilverCareMNNTTSRuntime.framework/SilverCareMNNTTSRuntime",
            "libsilvercare_mnn_tts_runtime.framework/libsilvercare_mnn_tts_runtime",
            "libmnn_tts.dylib",
            "libmnn_tts.framework/libmnn_tts"
        ] {
            if let handle = dlopen(name, RTLD_NOW | RTLD_LOCAL) {
                handles.append(handle)
            }
        }
        return handles
    }

    private func candidateLibraryPaths() -> [String] {
        var paths: [String] = []
        let environmentPath = ProcessInfo.processInfo.environment["SILVERCARE_MNN_TTS_LIBRARY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentPath, !environmentPath.isEmpty {
            paths.append(environmentPath)
        }
        let frameworkRoots = [
            bundle.privateFrameworksURL,
            bundle.bundleURL.appendingPathComponent("Frameworks", isDirectory: true)
        ].compactMap { $0 }
        for root in frameworkRoots {
            paths.append(root.appendingPathComponent("SilverCareMNNTTSRuntime.framework/SilverCareMNNTTSRuntime").path)
            paths.append(root.appendingPathComponent("libsilvercare_mnn_tts_runtime.framework/libsilvercare_mnn_tts_runtime").path)
            paths.append(root.appendingPathComponent("libsilvercare_mnn_tts_runtime.dylib").path)
            paths.append(root.appendingPathComponent("libmnn_tts.framework/libmnn_tts").path)
            paths.append(root.appendingPathComponent("libmnn_tts.dylib").path)
        }
        paths.append(bundle.bundleURL.appendingPathComponent("libsilvercare_mnn_tts_runtime.dylib").path)
        paths.append(bundle.bundleURL.appendingPathComponent("libmnn_tts.dylib").path)
        return Array(dictKeysPreservingOrder: paths)
    }

    private func load<T>(_ name: String, from handle: UnsafeMutableRawPointer) -> T? {
        guard let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }
}

private extension Array where Element == String {
    init(dictKeysPreservingOrder values: [String]) {
        var seen: Set<String> = []
        var unique: [String] = []
        for value in values where !value.isEmpty {
            if seen.insert(value).inserted {
                unique.append(value)
            }
        }
        self = unique
    }
}
