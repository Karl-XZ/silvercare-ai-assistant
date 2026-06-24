import Foundation
import SilverCareCore

protocol IOSLocalModelRuntime {
    var isReady: Bool { get }
    func visionDetectionsJSON(imageDataURL: String, role: String) throws -> String
    func textJSON(prompt: String, role: String, maxNewTokens: Int?, endWith: String?) throws -> String
}

struct UnavailableIOSLocalModelRuntime: IOSLocalModelRuntime {
    var isReady: Bool { false }

    func visionDetectionsJSON(imageDataURL: String, role: String) throws -> String {
        throw SilverCareCoreError.modelNotReady("iOS MNN 视觉 runtime 尚未绑定。")
    }

    func textJSON(prompt: String, role: String, maxNewTokens: Int?, endWith: String?) throws -> String {
        throw SilverCareCoreError.modelNotReady("iOS MNN 文本 runtime 尚未绑定。")
    }
}

final class IOSHybridAIClient: SilverCareAIClient {
    private let statusProvider: @Sendable () -> SilverCareRuntimeStatus
    private let diagnosticLogger: IOSDiagnosticLogger
    private let localRuntime: IOSLocalModelRuntime

    init(
        statusProvider: @escaping @Sendable () -> SilverCareRuntimeStatus,
        diagnosticLogger: IOSDiagnosticLogger,
        localRuntime: IOSLocalModelRuntime = UnavailableIOSLocalModelRuntime()
    ) {
        self.statusProvider = statusProvider
        self.diagnosticLogger = diagnosticLogger
        self.localRuntime = localRuntime
    }

    var settings: SilverCareSettings {
        let status = statusProvider()
        return SilverCareSettings(
            aiRuntimeMode: status.aiRuntimeMode,
            offlineModelDirectory: status.offlineModelDirectory,
            apiKey: status.dashScopeAPIKey,
            compatibleBaseURL: status.compatibleBaseURL,
            apiBaseURL: status.apiBaseURL,
            visionModel: status.aiRuntimeMode == "dashscope" ? status.visionModel : "damo-yolo-mnn",
            microModel: status.aiRuntimeMode == "dashscope" ? status.microModel : "damo-yolo-mnn",
            textModel: status.aiRuntimeMode == "dashscope"
                ? status.textModel
                : OfflineModelManifest.cleanTextModel(status.offlineTextModel),
            asrRuntimeMode: status.asrRuntimeMode,
            asrModel: SilverCareASRRuntimeMode.from(status.asrRuntimeMode).isLocal ? "device-asr" : status.asrModel,
            ttsRuntimeMode: status.ttsRuntimeMode,
            voiceFirstEnabled: status.voiceFirstEnabled,
            smartNavigationRefreshEnabled: status.smartNavigationRefreshEnabled
        )
    }

    func visionJSON(prompt: String, imageDataURL: String, model: String) throws -> String {
        if settings.aiRuntimeMode == "dashscope" {
            diagnosticLogger.event("ios_dashscope_vision_route", data: ["model": model])
            return try DashScopeAIClient(settings: settings).visionJSON(
                prompt: prompt,
                imageDataURL: imageDataURL,
                model: model
            )
        }
        diagnosticLogger.event("ios_vision_start", data: [
            "model": model,
            "prompt_chars": prompt.count,
            "image_chars": imageDataURL.count
        ])
        do {
            let rawDetections = try localRuntime.visionDetectionsJSON(imageDataURL: imageDataURL, role: model)
            let interpreted = try OfflineVisionInterpreter.interpret(prompt: prompt, rawJSON: rawDetections, role: model)
            diagnosticLogger.event("ios_vision_end", data: ["interpreted_chars": interpreted.count])
            return interpreted
        } catch {
            diagnosticLogger.event("ios_vision_unavailable", data: ["error": error.localizedDescription])
            throw error
        }
    }

    func textJSON(prompt: String, model: String, maxNewTokens: Int?, endWith: String?) throws -> String {
        if settings.aiRuntimeMode == "dashscope" {
            diagnosticLogger.event("ios_dashscope_text_route", data: ["model": model])
            return try DashScopeAIClient(settings: settings).textJSON(
                prompt: prompt,
                model: model,
                maxNewTokens: maxNewTokens,
                endWith: endWith
            )
        }
        diagnosticLogger.event("ios_text_start", data: [
            "model": model,
            "prompt_chars": prompt.count,
            "max_new_tokens": maxNewTokens ?? 0
        ])
        do {
            let output = try localRuntime.textJSON(prompt: prompt, role: model, maxNewTokens: maxNewTokens, endWith: endWith)
            diagnosticLogger.event("ios_text_end", data: ["output_chars": output.count])
            return output
        } catch {
            diagnosticLogger.event("ios_text_unavailable", data: ["error": error.localizedDescription])
            throw error
        }
    }

    func transcribe(audioDataURL: String) throws -> String {
        if settings.asrRuntimeMode == "dashscope" {
            diagnosticLogger.event("ios_dashscope_asr_route", data: ["audio_chars": audioDataURL.count])
            return try DashScopeAIClient(settings: settings).transcribe(audioDataURL: audioDataURL)
        }
        throw SilverCareCoreError.unsupported("iOS 原生录音转写请使用 startSpeechInquiry/stopSpeechInquiry 连续录音路径。")
    }
}
