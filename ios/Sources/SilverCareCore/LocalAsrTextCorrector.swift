import Foundation

public enum LocalAsrTextCorrector {
    private static let maxCorrectedCharacters = 80

    public static func prompt(rawTranscript: String) -> String {
        """
        你是银龄智护的本地语音识别校对器。
        下面的文本来自手机端本地 ASR，可能有错字、同音字、漏字、误断句或多余空格。

        校对目标：
        - 还原用户真正想说的短句。
        - 优先保留原意，不要扩写，不要替用户新增没有说过的需求。
        - 如果用户像是在找东西、问路、开启引导、关闭引导、停止任务、询问设置，请把命令校正成自然中文。
        - 如果不确定，只做最小修改。
        - 输出文本要能直接作为用户字幕和后续 AI 输入。

        常见纠错示例：
        - “帮我找到我的晚” -> “帮我找到我的碗”
        - “关闭影导” -> “关闭引导”
        - “找一下手几” -> “找一下手机”
        - “亭子”在导航语境中可能是“停止”

        原始 ASR 文本：“\(rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines))”

        只输出一个 JSON 对象，不要 Markdown：
        {"corrected_text":"校对后的用户原话","changed":true,"reason":"中文简短原因"}
        /no_think
        """
    }

    public static func correctedText(rawModelResponse: String, fallbackTranscript: String) -> String {
        let fallback = sanitize(fallbackTranscript)
        do {
            let json = try JSONSupport.object(from: rawModelResponse)
            var corrected = sanitize(json.string("corrected_text"))
            if corrected.isEmpty {
                corrected = sanitize(json.string("text"))
            }
            if corrected.isEmpty || corrected.count > maxCorrectedCharacters {
                return fallback
            }
            return corrected
        } catch {
            return fallback
        }
    }

    public static func fastCorrect(_ value: String) -> String {
        let text = sanitize(value)
        guard !text.isEmpty else { return "" }
        return text
            .replacingOccurrences(of: "我的晚", with: "我的碗")
            .replacingOccurrences(of: "到我的晚", with: "到我的碗")
            .replacingOccurrences(of: "找晚", with: "找碗")
            .replacingOccurrences(of: "找一下手几", with: "找一下手机")
            .replacingOccurrences(of: "手几", with: "手机")
            .replacingOccurrences(of: "关闭影导", with: "关闭引导")
            .replacingOccurrences(of: "影导", with: "引导")
    }

    public static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum LocalVoskTranscriptParser {
    public static func parseTranscript(_ resultJSON: String) -> String {
        guard
            let data = resultJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let raw = object["text"] as? String
        else { return "" }
        return normalizeChineseTranscript(raw)
    }

    public static func normalizeChineseTranscript(_ raw: String) -> String {
        let text = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !text.isEmpty else { return "" }

        var output = ""
        let characters = Array(text)
        for index in characters.indices {
            let current = characters[index]
            if current.isWhitespace {
                let previous = previousNonSpace(in: characters, before: index)
                let next = nextNonSpace(in: characters, after: index)
                if let previous, let next, previous.isCJK, next.isCJK {
                    continue
                }
                output.append(" ")
                continue
            }
            output.append(current)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func previousNonSpace(in characters: [Character], before index: Int) -> Character? {
        guard index > characters.startIndex else { return nil }
        var cursor = characters.index(before: index)
        while true {
            let value = characters[cursor]
            if !value.isWhitespace { return value }
            if cursor == characters.startIndex { return nil }
            cursor = characters.index(before: cursor)
        }
    }

    private static func nextNonSpace(in characters: [Character], after index: Int) -> Character? {
        var cursor = characters.index(after: index)
        while cursor < characters.endIndex {
            let value = characters[cursor]
            if !value.isWhitespace { return value }
            cursor = characters.index(after: cursor)
        }
        return nil
    }
}

private extension Character {
    var isCJK: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0x20000...0x2A6DF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
    }
}
