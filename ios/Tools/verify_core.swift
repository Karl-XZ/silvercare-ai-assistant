import Foundation

final class VerificationAIClient: SilverCareAIClient {
    var settings: SilverCareSettings
    var transcript = ""
    var visionResponses: [String] = []
    var textResponses: [String] = []
    private(set) var lastVisionPrompt = ""
    private(set) var lastTextPrompt = ""

    init(settings: SilverCareSettings = SilverCareSettings()) {
        self.settings = settings
    }

    func visionJSON(prompt: String, imageDataURL: String, model: String) throws -> String {
        lastVisionPrompt = prompt
        if visionResponses.isEmpty {
            return #"{"priority":"low","category":"navigation","subject":"通行空间","distance":3.0,"direction":"ahead","speech":"前方未检测到明显障碍。","scene_description":"空旷"}"#
        }
        return visionResponses.removeFirst()
    }

    func textJSON(prompt: String, model: String, maxNewTokens: Int?, endWith: String?) throws -> String {
        lastTextPrompt = prompt
        if textResponses.isEmpty {
            return #"{"intent":"info","speech":"我可以帮你看路、找东西、提醒风险。"}"#
        }
        return textResponses.removeFirst()
    }

    func transcribe(audioDataURL: String) throws -> String {
        transcript
    }
}

final class CapturingDashScopeTransport: DashScopeJSONTransport {
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

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func first(_ messages: [SilverCareMessage], _ type: String) -> SilverCareMessage? {
    messages.first { $0.type == type }
}

@main
enum SilverCareCoreVerifier {
static func main() {
do {
    let vision = try OfflineVisionInterpreter.interpret(
        prompt: "Current task: 正在寻找：晚\n",
        rawJSON: """
        {"image_width":640,"image_height":480,"detections":[{"class":"bowl","score":0.86,"box":[240,210,420,380]}]}
        """,
        role: "detector"
    )
    let visionJSON = try JSONSupport.object(from: vision)
    expect(visionJSON.bool("target_detected") == true, "bowl target should be detected")
    expect(visionJSON.string("subject") == "碗", "phonetic target 晚 should normalize to 碗")

    let fallSensor = FallDetectorCore.motionSample(
        gravity: SIMD3<Double>(0, 0, 25),
        rotation: SIMD3<Double>(120, 180, 0),
        time: 1234
    )
    expect(FallDetectorCore.hasFallImpact(fallSensor), "fall impact should be detected")
    let strongVisual = VisualEvidence(sampleCount: 7, maxDiff: 0.22, spikeCount: 3, brightnessRange: 0.44)
    expect(FallDetectorCore.shouldConfirmFall(
        sensor: (maxAcceleration: 27, maxDeviation: 17, maxRotation: 250),
        visual: strongVisual
    ), "fall confirmation should require strong sensor and visual evidence")

    expect(LocalAsrTextCorrector.fastCorrect("帮我找到我的晚") == "帮我找到我的碗", "fast ASR correction should handle 晚/碗")

    let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("silvercare-core-verify-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }
    let modelManager = OfflineModelManager()
    let missingStatus = modelManager.inspect(
        modelDirectory: tempRoot.appendingPathComponent("missing", isDirectory: true),
        nativeRuntimeAvailable: false
    )
    expect(missingStatus.ready == false, "offline status should be false when runtime and files are missing")
    expect(missingStatus.missing == [
        "MNN Native Runtime",
        "模型目录不可读",
        "Qwen3-4B-Instruct-2507-MNN/config.json",
        "DAMO-YOLO .mnn"
    ], "offline status should report Android-compatible missing items")

    let modelRoot = tempRoot.appendingPathComponent("multimodal_care_models", isDirectory: true)
    let textRoot = modelRoot.appendingPathComponent("Qwen3-4B-Instruct-2507-MNN", isDirectory: true)
    try FileManager.default.createDirectory(at: textRoot, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: textRoot.appendingPathComponent("config.json").path, contents: Data())
    FileManager.default.createFile(atPath: modelRoot.appendingPathComponent("damo-yolo.mnn").path, contents: Data())
    let readyStatus = modelManager.inspect(modelDirectory: modelRoot, nativeRuntimeAvailable: true)
    expect(readyStatus.ready, "offline status should accept expected Qwen4B + DAMO-YOLO layout")
    expect(readyStatus.shortText == "端侧离线模型已就绪", "offline status should expose localized ready text")
    expect(OfflineModelManifest.expectedTotalBytes > 2_700_000_000, "offline manifest should include Qwen4B weights")

    let dashTransport = CapturingDashScopeTransport()
    dashTransport.responses = [
        ["choices": [["message": ["content": #"{"intent":"info","speech":"你好"}"#]]]],
        ["choices": [["message": ["content": #"{"priority":"low","speech":"可以前进"}"#]]]],
        ["output": ["choices": [["message": ["content": [["text": "帮我找杯子"]]]]]]],
        ["output": ["audio": ["url": "https://example.com/tts.wav"]]]
    ]
    let dashSettings = SilverCareSettings(
        aiRuntimeMode: "dashscope",
        apiKey: "test-key",
        compatibleBaseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
        apiBaseURL: "https://dashscope.aliyuncs.com/api/v1",
        visionModel: "qwen3-vl-flash",
        textModel: "qwen-plus",
        asrModel: "qwen3-asr-flash"
    )
    let dashClient = DashScopeAIClient(settings: dashSettings, transport: dashTransport)
    let textOutput = try dashClient.textJSON(prompt: "你好", model: "qwen-plus", maxNewTokens: 24, endWith: "}")
    expect(textOutput.contains("你好"), "DashScope text response should parse chat content")
    _ = try dashClient.visionJSON(prompt: "看路", imageDataURL: "data:image/jpeg;base64,abc", model: "qwen3-vl-flash")
    let asrOutput = try dashClient.transcribe(audioDataURL: "data:audio/wav;base64,abc")
    expect(asrOutput == "帮我找杯子", "DashScope ASR response should parse transcript")
    let ttsURL = try dashClient.synthesizeSpeechURL(text: "请慢走")
    expect(ttsURL == "https://example.com/tts.wav", "DashScope TTS response should parse audio URL")
    expect(dashTransport.apiKeys.allSatisfy { $0 == "test-key" }, "DashScope transport should receive API key")
    expect(dashTransport.endpoints[0].absoluteString.hasSuffix("/compatible-mode/v1/chat/completions"), "DashScope chat endpoint should use compatible path")
    expect(dashTransport.endpoints[2].absoluteString.hasSuffix("/api/v1/services/aigc/multimodal-generation/generation"), "DashScope ASR endpoint should use generation path")
    expect((dashTransport.payloads[1]["response_format"] as? [String: Any])?["type"] as? String == "json_object", "DashScope vision should request JSON mode")

    let ai = VerificationAIClient()
    ai.transcript = "帮我找杯子"
    ai.visionResponses.append("""
    {
      "priority":"high",
      "category":"target",
      "subject":"杯子",
      "distance":1.2,
      "direction":"right",
      "target_detected":true,
      "speech":"杯子在右侧，距离约1.2米。",
      "scene_description":"桌面右侧有杯子"
    }
    """)
    let processor = SilverCareProcessor(client: ai)
    let searchMessages = try processor.processInquiry(
        imageDataURL: "data:image/png;base64,test",
        audioDataURL: "data:audio/wav;base64,test"
    )
    expect(processor.currentGoal == "杯子", "search inquiry should set current goal")
    expect(first(searchMessages, "inquiry_result")?.string("current_goal") == "杯子", "inquiry result should expose current goal")
    expect(first(searchMessages, "result")?.string("current_goal") == "杯子", "search inquiry should immediately run navigation frame")
    expect(ai.lastVisionPrompt.contains("正在寻找：杯子"), "navigation prompt should carry search target")

    var smartSettings = SilverCareSettings()
    smartSettings.smartNavigationRefreshEnabled = true
    let smartAI = VerificationAIClient(settings: smartSettings)
    smartAI.visionResponses.append("""
    {"priority":"medium","category":"navigation","subject":"门","distance":0.75,"direction":"ahead","speech":"前方有门","scene_description":"走廊尽头有门"}
    """)
    smartAI.visionResponses.append("""
    {"priority":"medium","category":"navigation","subject":"门","distance":0.80,"direction":"ahead","speech":"正前方仍然是门","scene_description":"走廊尽头仍然有门"}
    """)
    smartAI.textResponses.append(#"{"consistent":true,"reason":"行动建议未变化"}"#)
    let smartProcessor = SilverCareProcessor(client: smartAI)
    _ = try smartProcessor.processFrame("frame1")
    let smartMessages = try smartProcessor.processFrame("frame2")
    expect(first(smartMessages, "smart_refresh_skipped") != nil, "smart refresh should skip consistent navigation")

    print("SilverCareCore verification passed")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
}
}
