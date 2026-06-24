import Foundation
@testable import SilverCareCore

final class FakeAIClient: SilverCareAIClient {
    var settings: SilverCareSettings
    var transcript = ""
    var visionResponses: [String] = []
    var textResponses: [String] = []

    private(set) var lastVisionPrompt = ""
    private(set) var lastVisionModel = ""
    private(set) var lastTextPrompt = ""
    private(set) var lastTextModel = ""
    private(set) var lastTextMaxNewTokens: Int?
    private(set) var lastTextEndWith: String?

    init(settings: SilverCareSettings = SilverCareSettings()) {
        self.settings = settings
    }

    func visionJSON(prompt: String, imageDataURL: String, model: String) throws -> String {
        lastVisionPrompt = prompt
        lastVisionModel = model
        guard !visionResponses.isEmpty else {
            return #"{"priority":"low","category":"navigation","subject":"通行空间","distance":3.0,"direction":"ahead","speech":"前方未检测到明显障碍。","scene_description":"空旷"}"#
        }
        return visionResponses.removeFirst()
    }

    func textJSON(prompt: String, model: String, maxNewTokens: Int?, endWith: String?) throws -> String {
        lastTextPrompt = prompt
        lastTextModel = model
        lastTextMaxNewTokens = maxNewTokens
        lastTextEndWith = endWith
        guard !textResponses.isEmpty else {
            return #"{"intent":"info","speech":"我可以帮你看路、找东西、提醒风险。"}"#
        }
        return textResponses.removeFirst()
    }

    func transcribe(audioDataURL: String) throws -> String {
        transcript
    }
}

extension Array where Element == SilverCareMessage {
    func first(type: String) -> SilverCareMessage? {
        first { $0.type == type }
    }

    func all(type: String) -> [SilverCareMessage] {
        filter { $0.type == type }
    }

    func last(type: String) -> SilverCareMessage? {
        last { $0.type == type }
    }
}
