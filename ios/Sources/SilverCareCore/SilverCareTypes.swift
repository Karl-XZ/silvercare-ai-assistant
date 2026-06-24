import Foundation

public enum SilverCareRuntimeMode: String {
    case offlineMNN = "offline_mnn"
    case dashScope = "dashscope"

    public static func from(_ value: String) -> SilverCareRuntimeMode {
        SilverCareRuntimeMode(rawValue: value) ?? .dashScope
    }

    public var isOffline: Bool {
        self == .offlineMNN
    }

    public var label: String {
        switch self {
        case .offlineMNN: return "端侧离线 MNN"
        case .dashScope: return "联网 DashScope"
        }
    }
}

public enum SilverCareASRRuntimeMode: String {
    case localVosk = "local_vosk"
    case dashScope = "dashscope"

    public static func from(_ value: String) -> SilverCareASRRuntimeMode {
        if value == dashScope.rawValue { return .dashScope }
        return .localVosk
    }

    public var isLocal: Bool {
        self == .localVosk
    }

    public var label: String {
        switch self {
        case .localVosk: return "本地内置 ASR"
        case .dashScope: return "联网 DashScope"
        }
    }
}

public enum SilverCareTTSRuntimeMode: String {
    case auto = "auto"
    case localMNN = "local_mnn"
    case system = "system"
    case dashScope = "dashscope"

    public static func from(_ value: String) -> SilverCareTTSRuntimeMode {
        if value == "local_qwen" { return .localMNN }
        return SilverCareTTSRuntimeMode(rawValue: value) ?? .auto
    }

    public var allowsLocal: Bool {
        self == .localMNN
    }

    public var allowsSystem: Bool {
        self == .auto || self == .system
    }

    public var allowsDashScope: Bool {
        self == .auto || self == .dashScope
    }

    public var label: String {
        switch self {
        case .auto: return "自动兜底"
        case .localMNN: return "本地 MNN TTS（实验）"
        case .system: return "手机系统 TTS（本地）"
        case .dashScope: return "联网 DashScope"
        }
    }
}

public struct SilverCareLocalRuntimeBundlePlan: Equatable {
    public static let localASRExpectedBytes: Int64 = 43_898_754
    public static let localTTSExpectedBytes: Int64 = 1_392_019_964

    public let offlineModelsRequired: Bool
    public let asrModelRequired: Bool
    public let ttsModelRequired: Bool
    public let mnnRuntimeMissing: Bool
    public let asrRuntimeMissing: Bool
    public let ttsRuntimeMissing: Bool
    public let downloadBytes: Int64

    public static func from(
        offlineStatus: OfflineModelStatus?,
        localASRReady: Bool,
        localASRRuntimeAvailable: Bool = true,
        localTTSModelReady: Bool = false,
        includeExperimentalTTS: Bool = false,
        ttsRuntimeAvailable: Bool = false
    ) -> SilverCareLocalRuntimeBundlePlan {
        let offlineRequired = offlineStatus == nil
            || offlineStatus?.directoryReadable == false
            || offlineStatus?.textReady == false
            || offlineStatus?.yoloReady == false
        let asrRequired = !localASRReady
        let ttsRequired = includeExperimentalTTS && !localTTSModelReady
        let mnnMissing = offlineStatus.map { !$0.nativeRuntimeAvailable } ?? false
        let asrRuntimeMissing = !localASRRuntimeAvailable
        let ttsMissing = includeExperimentalTTS && !ttsRuntimeAvailable

        var total: Int64 = 0
        if offlineRequired { total += OfflineModelManifest.expectedTotalBytes }
        if asrRequired { total += localASRExpectedBytes }
        if ttsRequired { total += localTTSExpectedBytes }

        return SilverCareLocalRuntimeBundlePlan(
            offlineModelsRequired: offlineRequired,
            asrModelRequired: asrRequired,
            ttsModelRequired: ttsRequired,
            mnnRuntimeMissing: mnnMissing,
            asrRuntimeMissing: asrRuntimeMissing,
            ttsRuntimeMissing: ttsMissing,
            downloadBytes: total
        )
    }

    public var hasDownloads: Bool {
        downloadBytes > 0
    }

    public var downloadSummaryText: String {
        guard hasDownloads else {
            return "未发现需要下载的本地模型文件。"
        }
        var lines: [String] = []
        if offlineModelsRequired {
            lines.append("AI 离线模型：Qwen3-4B-Instruct-2507-MNN + DAMO-YOLO，约 \(OfflineModelManifest.humanBytes(OfflineModelManifest.expectedTotalBytes))")
        }
        if asrModelRequired {
            lines.append("本地 ASR：应用内置中文语音识别模型，约 \(OfflineModelManifest.humanBytes(Self.localASRExpectedBytes))")
        }
        if ttsModelRequired {
            lines.append("本地 TTS：bert-vits2-MNN 实验模型，约 \(OfflineModelManifest.humanBytes(Self.localTTSExpectedBytes))")
        }
        lines.append("合计需要准备：约 \(OfflineModelManifest.humanBytes(downloadBytes))")
        return lines.joined(separator: "\n")
    }

    public var runtimeWarningText: String {
        var lines: [String] = []
        if mnnRuntimeMissing {
            lines.append("MNN Native Runtime 当前未加载；下载模型不能单独修复 native runtime 问题。")
        }
        if asrRuntimeMissing {
            lines.append("iOS Vosk ASR Runtime 当前未绑定；即使模型文件存在，也不能作为 Android 等价本地 ASR 使用。")
        }
        if ttsRuntimeMissing {
            lines.append("本地 MNN TTS 当前为实验项；即使模型已下载，也不会作为主朗读方案。")
        }
        return lines.joined(separator: "\n")
    }
}

public enum SilverCareMnnLlmTuningProfile: String {
    case auto = "auto"
    case performance = "performance"
    case efficiency = "efficiency"
    case mnnDefault = "mnn_default"

    public static func from(_ value: String?) -> SilverCareMnnLlmTuningProfile {
        guard let value else { return .auto }
        return SilverCareMnnLlmTuningProfile(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .auto
    }

    public static func nativeConfigJSON(mode: String, supportsSme2: Bool) -> String {
        from(mode).nativeConfigJSON(supportsSme2: supportsSme2)
    }

    public func nativeConfigJSON(supportsSme2: Bool) -> String {
        let noThink = #""jinja":{"context":{"enable_thinking":false}}"#
        switch self {
        case .performance where supportsSme2:
            return "{\(noThink),\"cpu_sme2_neon_division_ratio\":49,\"cpu_sme_core_num\":2}"
        case .efficiency where supportsSme2:
            return "{\(noThink),\"cpu_sme2_neon_division_ratio\":33,\"cpu_sme_core_num\":1}"
        case .mnnDefault:
            return "{\(noThink)}"
        default:
            if supportsSme2 {
                return "{\(noThink),\"cpu_sme2_neon_division_ratio\":41,\"cpu_sme_core_num\":2}"
            }
            return "{\(noThink)}"
        }
    }

    public func menuText(supportsSme2: Bool) -> String {
        switch self {
        case .auto:
            return supportsSme2
                ? "SME2 自动调优：41/2"
                : "SME2 自动调优：当前设备不支持，自动回退到 MNN 默认"
        case .performance:
            return supportsSme2
                ? "性能优先：49/2"
                : "性能优先：当前设备不支持，自动回退到 MNN 默认"
        case .efficiency:
            return supportsSme2
                ? "省电稳定：33/1"
                : "省电稳定：当前设备不支持，自动回退到 MNN 默认"
        case .mnnDefault:
            return "MNN 默认：不覆盖 MNN 配置"
        }
    }
}

public enum SilverCareMode: String {
    case navigation = "nav"
    case micro = "micro"
    case task = "task"
}

public struct SilverCareSettings: Equatable {
    public var aiRuntimeMode: String
    public var offlineModelDirectory: String
    public var apiKey: String
    public var compatibleBaseURL: String
    public var apiBaseURL: String
    public var visionModel: String
    public var microModel: String
    public var textModel: String
    public var asrRuntimeMode: String
    public var asrModel: String
    public var ttsRuntimeMode: String
    public var mnnTuningMode: String
    public var voiceFirstEnabled: Bool
    public var smartNavigationRefreshEnabled: Bool

    public init(
        aiRuntimeMode: String = SilverCareRuntimeMode.offlineMNN.rawValue,
        offlineModelDirectory: String = "",
        apiKey: String = "",
        compatibleBaseURL: String = "https://dashscope.aliyuncs.com/compatible-mode/v1",
        apiBaseURL: String = "https://dashscope.aliyuncs.com/api/v1",
        visionModel: String = "damo-yolo-mnn",
        microModel: String = "damo-yolo-mnn",
        textModel: String = "qwen3-4b-instruct-2507-mnn",
        asrRuntimeMode: String = SilverCareASRRuntimeMode.localVosk.rawValue,
        asrModel: String = "qwen3-asr-flash",
        ttsRuntimeMode: String = SilverCareTTSRuntimeMode.auto.rawValue,
        mnnTuningMode: String = "auto",
        voiceFirstEnabled: Bool = true,
        smartNavigationRefreshEnabled: Bool = false
    ) {
        self.aiRuntimeMode = aiRuntimeMode
        self.offlineModelDirectory = offlineModelDirectory
        self.apiKey = apiKey
        self.compatibleBaseURL = compatibleBaseURL
        self.apiBaseURL = apiBaseURL
        self.visionModel = visionModel
        self.microModel = microModel
        self.textModel = textModel
        self.asrRuntimeMode = SilverCareASRRuntimeMode.from(asrRuntimeMode).rawValue
        self.asrModel = asrModel
        self.ttsRuntimeMode = SilverCareTTSRuntimeMode.from(ttsRuntimeMode).rawValue
        self.mnnTuningMode = mnnTuningMode
        self.voiceFirstEnabled = voiceFirstEnabled
        self.smartNavigationRefreshEnabled = smartNavigationRefreshEnabled
    }
}

public protocol SilverCareAIClient {
    var settings: SilverCareSettings { get }

    func visionJSON(prompt: String, imageDataURL: String, model: String) throws -> String
    func textJSON(prompt: String, model: String, maxNewTokens: Int?, endWith: String?) throws -> String
    func transcribe(audioDataURL: String) throws -> String
}

public extension SilverCareAIClient {
    func textJSON(prompt: String, model: String) throws -> String {
        try textJSON(prompt: prompt, model: model, maxNewTokens: nil, endWith: nil)
    }
}

public struct SilverCareMessage {
    public var type: String
    public var payload: [String: Any]

    public init(type: String, payload: [String: Any] = [:]) {
        self.type = type
        self.payload = payload
    }

    public func string(_ key: String) -> String {
        if let value = payload[key] as? String { return value }
        if let value = payload[key] { return String(describing: value) }
        return ""
    }

    public func bool(_ key: String) -> Bool {
        payload[key] as? Bool ?? false
    }

    public func double(_ key: String) -> Double {
        if let value = payload[key] as? Double { return value }
        if let value = payload[key] as? Int { return Double(value) }
        if let value = payload[key] as? NSNumber { return value.doubleValue }
        return 0
    }

    public func int(_ key: String) -> Int {
        if let value = payload[key] as? Int { return value }
        if let value = payload[key] as? NSNumber { return value.intValue }
        return 0
    }
}
