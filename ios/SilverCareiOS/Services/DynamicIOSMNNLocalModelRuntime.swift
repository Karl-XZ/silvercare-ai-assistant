import Darwin
import Foundation
import SilverCareCore
import UIKit

final class DynamicIOSMNNLocalModelRuntime: IOSLocalModelRuntime {
    private typealias RuntimeKindFn = @convention(c) () -> UnsafePointer<CChar>?
    private typealias SupportsSme2Fn = @convention(c) () -> Int32
    private typealias VisionDataURLJSONFn = @convention(c) (
        UnsafePointer<CChar>,
        UnsafePointer<CChar>,
        UnsafePointer<CChar>,
        UnsafePointer<CChar>
    ) -> UnsafeMutablePointer<CChar>?
    private typealias VisionCHWJSONFn = @convention(c) (
        UnsafePointer<CChar>,
        UnsafePointer<CChar>,
        UnsafePointer<Float>,
        Int32,
        Int32,
        UnsafePointer<CChar>
    ) -> UnsafeMutablePointer<CChar>?
    private typealias TextJSONFn = @convention(c) (
        UnsafePointer<CChar>,
        UnsafePointer<CChar>,
        UnsafePointer<CChar>,
        UnsafePointer<CChar>,
        Int32,
        UnsafePointer<CChar>
    ) -> UnsafeMutablePointer<CChar>?
    private typealias FreeStringFn = @convention(c) (UnsafeMutablePointer<CChar>) -> Void

    private struct Symbols {
        let runtimeKind: RuntimeKindFn
        let supportsSme2: SupportsSme2Fn?
        let visionDataURLJSON: VisionDataURLJSONFn?
        let visionCHWJSON: VisionCHWJSONFn?
        let textJSON: TextJSONFn
        let freeString: FreeStringFn?
    }

    private struct VisionTensor {
        let values: [Float]
        let originalWidth: Int32
        let originalHeight: Int32
    }

    private let statusProvider: @Sendable () -> SilverCareRuntimeStatus
    private let bundle: Bundle
    private let symbols: Symbols?
    private static let visionInputSize = 640

    init(statusProvider: @escaping @Sendable () -> SilverCareRuntimeStatus, bundle: Bundle = .main) {
        self.statusProvider = statusProvider
        self.bundle = bundle
        self.symbols = Self.loadSymbols(bundle: bundle)
    }

    var isReady: Bool {
        symbols != nil
    }

    var supportsSme2: Bool {
        (symbols?.supportsSme2?() ?? 0) != 0
    }

    var runtimeSummary: String {
        guard let symbols else { return "iOS MNN Runtime 未加载" }
        let kind = symbols.runtimeKind().map { String(cString: $0) } ?? "mnn-ios"
        return kind + (supportsSme2 ? " · SME2 可用" : " · 未检测到 SME2")
    }

    func visionDetectionsJSON(imageDataURL: String, role: String) throws -> String {
        guard let symbols else {
            throw SilverCareCoreError.modelNotReady("iOS MNN 视觉 runtime 尚未绑定。")
        }
        let status = statusProvider()
        guard !status.offlineModelDirectory.isEmpty else {
            throw SilverCareCoreError.modelNotReady("iOS 离线模型目录尚未就绪。")
        }
        if let visionCHWJSON = symbols.visionCHWJSON {
            return try callVisionCHW(
                visionCHWJSON,
                modelDirectory: status.offlineModelDirectory,
                prompt: "",
                imageDataURL: imageDataURL,
                role: role,
                freeString: symbols.freeString
            )
        }
        if let visionDataURLJSON = symbols.visionDataURLJSON {
            return try callVisionDataURL(
                visionDataURLJSON,
                modelDirectory: status.offlineModelDirectory,
                prompt: "",
                imageDataURL: imageDataURL,
                role: role,
                freeString: symbols.freeString
            )
        }
        throw SilverCareCoreError.modelNotReady("iOS MNN 视觉 ABI 尚未绑定。")
    }

    func textJSON(prompt: String, role: String, maxNewTokens: Int?, endWith: String?) throws -> String {
        guard let symbols else {
            throw SilverCareCoreError.modelNotReady("iOS MNN 文本 runtime 尚未绑定。")
        }
        let status = statusProvider()
        guard !status.offlineModelDirectory.isEmpty else {
            throw SilverCareCoreError.modelNotReady("iOS 离线模型目录尚未就绪。")
        }
        let tuning = SilverCareMnnLlmTuningProfile.nativeConfigJSON(
            mode: status.mnnLlmTuningMode,
            supportsSme2: supportsSme2
        )
        return try callText(
            symbols.textJSON,
            modelDirectory: status.offlineModelDirectory,
            prompt: prompt,
            role: role,
            tuningConfigJSON: tuning,
            maxNewTokens: Int32(maxNewTokens ?? 0),
            endWith: endWith ?? "",
            freeString: symbols.freeString
        )
    }

    private static func loadSymbols(bundle: Bundle) -> Symbols? {
        for handle in candidateLibraryHandles(bundle: bundle) {
            if let symbols = loadSymbols(from: handle) {
                return symbols
            }
        }
        return nil
    }

    private static func candidateLibraryHandles(bundle: Bundle) -> [UnsafeMutableRawPointer] {
        var handles: [UnsafeMutableRawPointer] = []
        if let handle = dlopen(nil, RTLD_NOW) {
            handles.append(handle)
        }
        for path in candidateLibraryPaths(bundle: bundle) {
            if let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) {
                handles.append(handle)
            }
        }
        if let handle = dlopen("libsilvercare_mnn_runtime.dylib", RTLD_NOW | RTLD_LOCAL) {
            handles.append(handle)
        }
        if let handle = dlopen("SilverCareMNNRuntime.framework/SilverCareMNNRuntime", RTLD_NOW | RTLD_LOCAL) {
            handles.append(handle)
        }
        return handles
    }

    private static func candidateLibraryPaths(bundle: Bundle) -> [String] {
        var paths: [String] = []
        let environmentPath = ProcessInfo.processInfo.environment["SILVERCARE_MNN_LIBRARY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentPath, !environmentPath.isEmpty {
            paths.append(environmentPath)
        }
        let frameworkRoots = [
            bundle.privateFrameworksURL,
            bundle.bundleURL.appendingPathComponent("Frameworks", isDirectory: true)
        ].compactMap { $0 }
        for root in frameworkRoots {
            paths.append(root.appendingPathComponent("SilverCareMNNRuntime.framework/SilverCareMNNRuntime").path)
            paths.append(root.appendingPathComponent("libsilvercare_mnn_runtime.framework/libsilvercare_mnn_runtime").path)
            paths.append(root.appendingPathComponent("libsilvercare_mnn_runtime.dylib").path)
        }
        paths.append(bundle.bundleURL.appendingPathComponent("libsilvercare_mnn_runtime.dylib").path)
        return Array(dictKeysPreservingOrder: paths)
    }

    private static func loadSymbols(from handle: UnsafeMutableRawPointer) -> Symbols? {
        guard let runtimeKind: RuntimeKindFn = load("silvercare_mnn_runtime_kind", from: handle),
              let textJSON: TextJSONFn = load("silvercare_mnn_text_json", from: handle)
        else {
            return nil
        }
        let visionCHWJSON: VisionCHWJSONFn? = load("silvercare_mnn_vision_json_from_chw", from: handle)
        let visionDataURLJSON: VisionDataURLJSONFn? = load("silvercare_mnn_vision_json", from: handle)
        guard visionCHWJSON != nil || visionDataURLJSON != nil else { return nil }
        let supportsSme2: SupportsSme2Fn? = load("silvercare_mnn_supports_sme2", from: handle)
        let freeString: FreeStringFn? = load("silvercare_mnn_free_string", from: handle)
        return Symbols(
            runtimeKind: runtimeKind,
            supportsSme2: supportsSme2,
            visionDataURLJSON: visionDataURLJSON,
            visionCHWJSON: visionCHWJSON,
            textJSON: textJSON,
            freeString: freeString
        )
    }

    private static func load<T>(_ name: String, from handle: UnsafeMutableRawPointer) -> T? {
        guard let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }

    private func callVisionDataURL(
        _ function: VisionDataURLJSONFn,
        modelDirectory: String,
        prompt: String,
        imageDataURL: String,
        role: String,
        freeString: FreeStringFn?
    ) throws -> String {
        try modelDirectory.withCString { modelDirPtr in
            try prompt.withCString { promptPtr in
                try imageDataURL.withCString { imagePtr in
                    try role.withCString { rolePtr in
                        guard let output = function(modelDirPtr, promptPtr, imagePtr, rolePtr) else {
                            throw SilverCareCoreError.modelNotReady("iOS MNN 视觉推理未返回结果。")
                        }
                        defer { freeString?(output) }
                        return String(cString: output)
                    }
                }
            }
        }
    }

    private func callVisionCHW(
        _ function: VisionCHWJSONFn,
        modelDirectory: String,
        prompt: String,
        imageDataURL: String,
        role: String,
        freeString: FreeStringFn?
    ) throws -> String {
        let tensor = try makeVisionTensor(from: imageDataURL)
        return try tensor.values.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw SilverCareCoreError.modelNotReady("iOS MNN 视觉张量为空。")
            }
            return try modelDirectory.withCString { modelDirPtr in
                try prompt.withCString { promptPtr in
                    try role.withCString { rolePtr in
                        guard let output = function(
                            modelDirPtr,
                            promptPtr,
                            baseAddress,
                            tensor.originalWidth,
                            tensor.originalHeight,
                            rolePtr
                        ) else {
                            throw SilverCareCoreError.modelNotReady("iOS MNN 视觉推理未返回结果。")
                        }
                        defer { freeString?(output) }
                        return String(cString: output)
                    }
                }
            }
        }
    }

    private func makeVisionTensor(from imageDataURL: String) throws -> VisionTensor {
        let data = try decodeImageDataURL(imageDataURL)
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw SilverCareCoreError.invalidJSON("无法解码摄像头图像。")
        }
        let originalWidth = Int32(max(1, Int((image.size.width * image.scale).rounded())))
        let originalHeight = Int32(max(1, Int((image.size.height * image.scale).rounded())))
        let inputSize = Self.visionInputSize
        let inputLength = CGFloat(inputSize)
        let inputRect = CGRect(x: 0, y: 0, width: inputLength, height: inputLength)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: inputLength, height: inputLength))
        let scaled = renderer.image { _ in
            image.draw(in: inputRect)
        }
        guard let cgImage = scaled.cgImage else {
            throw SilverCareCoreError.invalidJSON("无法生成摄像头图像张量。")
        }

        var rgba = [UInt8](repeating: 0, count: inputSize * inputSize * 4)
        guard let context = CGContext(
            data: &rgba,
            width: inputSize,
            height: inputSize,
            bitsPerComponent: 8,
            bytesPerRow: inputSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw SilverCareCoreError.invalidJSON("无法创建摄像头图像张量上下文。")
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: inputRect)

        let plane = inputSize * inputSize
        var values = [Float](repeating: 0, count: 3 * plane)
        for index in 0..<plane {
            let pixel = index * 4
            values[index] = Float(rgba[pixel])
            values[plane + index] = Float(rgba[pixel + 1])
            values[(2 * plane) + index] = Float(rgba[pixel + 2])
        }
        return VisionTensor(values: values, originalWidth: originalWidth, originalHeight: originalHeight)
    }

    private func decodeImageDataURL(_ imageDataURL: String) throws -> Data {
        var value = imageDataURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comma = value.firstIndex(of: ",") {
            value = String(value[value.index(after: comma)...])
        }
        guard !value.isEmpty, let data = Data(base64Encoded: value, options: [.ignoreUnknownCharacters]) else {
            throw SilverCareCoreError.invalidJSON("摄像头图像为空。")
        }
        return data
    }

    private func callText(
        _ function: TextJSONFn,
        modelDirectory: String,
        prompt: String,
        role: String,
        tuningConfigJSON: String,
        maxNewTokens: Int32,
        endWith: String,
        freeString: FreeStringFn?
    ) throws -> String {
        try modelDirectory.withCString { modelDirPtr in
            try prompt.withCString { promptPtr in
                try role.withCString { rolePtr in
                    try tuningConfigJSON.withCString { tuningPtr in
                        try endWith.withCString { endPtr in
                            guard let output = function(
                                modelDirPtr,
                                promptPtr,
                                rolePtr,
                                tuningPtr,
                                maxNewTokens,
                                endPtr
                            ) else {
                                throw SilverCareCoreError.modelNotReady("iOS MNN 文本推理未返回结果。")
                            }
                            defer { freeString?(output) }
                            return String(cString: output)
                        }
                    }
                }
            }
        }
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
