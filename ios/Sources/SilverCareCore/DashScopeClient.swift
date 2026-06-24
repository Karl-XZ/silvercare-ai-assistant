import Foundation

public protocol DashScopeJSONTransport {
    func postJSON(endpoint: URL, payload: [String: Any], apiKey: String) throws -> [String: Any]
}

public final class URLSessionDashScopeTransport: DashScopeJSONTransport {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 60) {
        self.session = session
        self.timeout = timeout
    }

    public func postJSON(endpoint: URL, payload: [String: Any], apiKey: String) throws -> [String: Any] {
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let semaphore = DispatchSemaphore(value: 0)
        final class Box {
            var result: Result<[String: Any], Error>?
        }
        let box = Box()
        session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                box.result = .failure(error)
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = data ?? Data()
            if status < 200 || status >= 300 {
                let text = String(data: body, encoding: .utf8) ?? ""
                box.result = .failure(SilverCareCoreError.transport("DashScope 请求失败：\(status) \(text)"))
                return
            }
            do {
                guard let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                    throw SilverCareCoreError.invalidJSON("DashScope response is not a JSON object")
                }
                box.result = .success(object)
            } catch {
                box.result = .failure(error)
            }
        }.resume()
        semaphore.wait()
        return try box.result?.get() ?? { throw SilverCareCoreError.transport("DashScope 请求没有返回结果。") }()
    }
}

public final class DashScopeAIClient: SilverCareAIClient {
    public let settings: SilverCareSettings
    private let transport: DashScopeJSONTransport

    public init(settings: SilverCareSettings, transport: DashScopeJSONTransport = URLSessionDashScopeTransport()) {
        self.settings = settings
        self.transport = transport
    }

    public func visionJSON(prompt: String, imageDataURL: String, model: String) throws -> String {
        let content: [[String: Any]] = [
            ["type": "text", "text": prompt],
            ["type": "image_url", "image_url": ["url": imageDataURL]]
        ]
        return try chat(content: content, model: model, jsonMode: true, temperature: 0.1)
    }

    public func textJSON(prompt: String, model: String, maxNewTokens: Int?, endWith: String?) throws -> String {
        var payloadText = prompt
        if let endWith, !endWith.isEmpty {
            payloadText += "\nReturn a JSON value ending with \(endWith)."
        }
        let content: [[String: Any]] = [
            ["type": "text", "text": payloadText]
        ]
        return try chat(content: content, model: model, jsonMode: false, temperature: 0.2, maxNewTokens: maxNewTokens)
    }

    public func transcribe(audioDataURL: String) throws -> String {
        let messages: [[String: Any]] = [
            [
                "role": "system",
                "content": [
                    [
                        "text": "银龄智护 盲人导航助手。常见词：找门、找水杯、按电梯上行按钮、巡路、障碍物、跌倒、厨房、办公室。"
                    ] as [String: Any]
                ] as [[String: Any]]
            ],
            [
                "role": "user",
                "content": [
                    ["audio": audioDataURL] as [String: Any]
                ] as [[String: Any]]
            ]
        ]
        let payload: [String: Any] = [
            "model": settings.asrModel,
            "input": [
                "messages": messages
            ] as [String: Any],
            "parameters": [
                "asr_options": [
                    "language": "zh",
                    "enable_itn": false
                ] as [String: Any]
            ] as [String: Any]
        ]
        let response = try transport.postJSON(
            endpoint: endpoint(settings.apiBaseURL, path: "/services/aigc/multimodal-generation/generation"),
            payload: payload,
            apiKey: requireAPIKey()
        )
        let content = (((response["output"] as? [String: Any])?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? [[String: Any]]
        return content?.first?.string("text") ?? ""
    }

    public func synthesizeSpeechURL(text: String) throws -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }
        let payload: [String: Any] = [
            "model": "qwen3-tts-flash",
            "input": [
                "text": clean,
                "voice": "Cherry",
                "language_type": "Chinese"
            ]
        ]
        let response = try transport.postJSON(
            endpoint: endpoint(settings.apiBaseURL, path: "/services/aigc/multimodal-generation/generation"),
            payload: payload,
            apiKey: requireAPIKey()
        )
        guard
            let output = response["output"] as? [String: Any],
            let audio = output["audio"] as? [String: Any],
            let url = audio["url"] as? String,
            !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw SilverCareCoreError.invalidJSON("DashScope TTS 返回缺少音频 URL。")
        }
        return url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func chat(
        content: [[String: Any]],
        model: String,
        jsonMode: Bool,
        temperature: Double,
        maxNewTokens: Int? = nil
    ) throws -> String {
        var payload: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": content
                ] as [String: Any]
            ] as [[String: Any]],
            "stream": false,
            "temperature": temperature
        ]
        if jsonMode {
            payload["response_format"] = ["type": "json_object"]
        }
        if let maxNewTokens, maxNewTokens > 0 {
            payload["max_tokens"] = maxNewTokens
        }

        let response = try transport.postJSON(
            endpoint: endpoint(settings.compatibleBaseURL, path: "/chat/completions"),
            payload: payload,
            apiKey: requireAPIKey()
        )
        guard
            let choices = response["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any]
        else {
            throw SilverCareCoreError.invalidJSON("DashScope chat response missing choices[0].message.content")
        }
        let output = Self.normalizedMessageContent(message["content"])
        guard !output.isEmpty else {
            throw SilverCareCoreError.invalidJSON("DashScope chat response content is empty")
        }
        return output
    }

    static func normalizedMessageContent(_ content: Any?) -> String {
        if let text = content as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let items = content as? [[String: Any]] {
            return items
                .compactMap { item in
                    if let text = item["text"] as? String { return text }
                    if let text = item["content"] as? String { return text }
                    return nil
                }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let items = content as? [Any] {
            return items
                .compactMap { item in
                    if let text = item as? String { return text }
                    if let object = item as? [String: Any] {
                        if let text = object["text"] as? String { return text }
                        if let text = object["content"] as? String { return text }
                    }
                    return nil
                }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private func requireAPIKey() throws -> String {
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            throw SilverCareCoreError.missingCredential("请先配置 DashScope Key。")
        }
        return key
    }

    private func endpoint(_ baseURL: String, path: String) throws -> URL {
        let cleanBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: cleanBase) else {
            throw SilverCareCoreError.transport("DashScope base URL 无效：\(baseURL)")
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, suffix].filter { !$0.isEmpty }.joined(separator: "/")
        guard let url = components.url else {
            throw SilverCareCoreError.transport("DashScope endpoint URL 无效：\(baseURL)\(path)")
        }
        return url
    }
}
