import Foundation

public final class SilverCareProcessor {
    private static let offlineInquiryMaxNewTokens = 24
    private static let offlineSmartRefreshMaxNewTokens = 48
    private static let taskPlanMaxNewTokens = 256
    private static let jsonObjectEnd = "}"

    private let client: SilverCareAIClient
    private let memoryStore: SilverCareMemoryStore

    public private(set) var mode: SilverCareMode = .navigation
    public private(set) var currentGoal: String?
    public private(set) var microTarget: String?

    private var taskPlan: [[String: Any]] = []
    private var currentStepIndex = 0
    private var lastSpeechAt: TimeInterval = 0
    private var lastSpeech = ""
    private var lastNavigationSemanticText = ""
    private var lastMicroGuidanceSpeech = ""
    private var socialContext: [String] = []

    public init(client: SilverCareAIClient, memoryStore: SilverCareMemoryStore = SilverCareMemoryStore()) {
        self.client = client
        self.memoryStore = memoryStore
    }

    public func processFrame(_ imageDataURL: String) throws -> [SilverCareMessage] {
        switch mode {
        case .micro:
            return try processMicroFrame(imageDataURL)
        case .task:
            return try processTaskFrame(imageDataURL)
        case .navigation:
            return try processNavigationFrame(imageDataURL, forceRefresh: false)
        }
    }

    public func processInquiry(imageDataURL: String, audioDataURL: String) throws -> [SilverCareMessage] {
        let transcript = try client.transcribe(audioDataURL: audioDataURL)
        return try processTextInquiry(imageDataURL: imageDataURL, transcript: transcript.isEmpty ? "未识别到清晰语音" : transcript)
    }

    public func processTextInquiry(imageDataURL: String, transcript: String) throws -> [SilverCareMessage] {
        let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .micro && containsCloseKeyword(cleanTranscript) {
            mode = .navigation
            microTarget = nil
            lastMicroGuidanceSpeech = ""
            return [
                SilverCareMessage(type: "inquiry_result", payload: [
                    "thinking": "用户说出关闭词，已退出精确引导",
                    "mode": mode.rawValue,
                    "transcript": cleanTranscript
                ]),
                SilverCareMessage(type: "speak", payload: ["text": "已关闭精确引导。"])
            ]
        }
        if mode == .micro && !containsGuidanceKeyword(cleanTranscript) {
            return try processMicroFollowUpInquiry(imageDataURL: imageDataURL, transcript: cleanTranscript)
        }

        let raw = try routeInquiryModel(transcript: cleanTranscript, imageDataURL: imageDataURL)
        var result = try? expandCompactInquiryResult(JSONSupport.object(from: raw))
        result = try applyTranscriptFallback(cleanTranscript, modelResult: result)
        if result == nil {
            result = fallbackIntent(intent: "info", speech: "我暂时没有理解这句话，请再说一遍。")
            result?["thinking"] = "模型未返回可解析 JSON，已使用本地兜底回复"
        }

        var output = result ?? [:]
        var intent = normalizeIntent(output.string("intent", default: "info"))
        output["intent"] = intent
        var speech = output.string("speech", default: "我没有听清。")

        if intent == "micro_nav" && !containsGuidanceKeyword(cleanTranscript) {
            output = fallbackIntent(intent: "info", speech: "如果需要精确引导，请说：引导我靠近目标。当前我不会自动开启精确引导。")
            output["thinking"] = "用户没有说出“引导”，已阻止自动进入精确引导"
            intent = "info"
            speech = output.string("speech")
        }

        if intent == "search" && isOfflineRuntime && Self.isNavigationSafetyQuestion(cleanTranscript) {
            output = fallbackIntent(intent: "nav_check", speech: "正在查看前方是否可以通行。")
            output["thinking"] = "LLM 将通行检查误判为找物，已按安全意图校正为避障导航。"
            intent = "nav_check"
            speech = output.string("speech")
        }

        if intent == "search" && isOfflineRuntime && !isSearchIntentRequest(cleanTranscript) {
            output = fallbackIntent(intent: "info", speech: offlineCapabilitySpeech(transcript: cleanTranscript, modelSpeech: speech))
            output["thinking"] = "本地 LLM 返回找物，但用户原话没有找物意图，已校正为普通问答。"
            intent = "info"
            speech = output.string("speech")
        }

        if intent == "search" && isOfflineRuntime {
            output = normalizeOfflineSearchIntent(transcript: cleanTranscript, result: output)
            intent = normalizeIntent(output.string("intent", default: "info"))
            output["intent"] = intent
            speech = output.string("speech", default: speech)
        }

        if intent == "info" && speech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            speech = offlineCapabilitySpeech(transcript: cleanTranscript, modelSpeech: speech)
            output["speech"] = speech
        } else if intent == "nav_check" && speech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            speech = "正在查看前方是否可以通行。"
            output["speech"] = speech
        }

        if let override = try handleIntent(intent: intent, result: output), !override.isEmpty {
            speech = override
        }

        var messages: [SilverCareMessage] = [
            SilverCareMessage(type: "inquiry_result", payload: [
                "thinking": output.string("thinking"),
                "current_goal": currentGoal ?? "",
                "mode": mode.rawValue,
                "intent": intent,
                "task_active": mode == .task,
                "speech": speech,
                "transcript": cleanTranscript
            ]),
            SilverCareMessage(type: "speak", payload: ["text": speech])
        ]

        if intent == "search", currentGoal != nil, !imageDataURL.isEmpty {
            messages.append(contentsOf: try processNavigationFrame(imageDataURL, forceRefresh: true))
        } else if intent == "nav_check", !imageDataURL.isEmpty {
            currentGoal = nil
            mode = .navigation
            messages.append(contentsOf: try processNavigationFrame(imageDataURL, forceRefresh: false))
        } else if intent == "task" || intent.hasPrefix("task_") {
            messages.append(taskUpdateMessage())
        }
        return messages
    }

    private func routeInquiryModel(transcript: String, imageDataURL: String) throws -> String {
        let prompt = inquiryPrompt(transcript: transcript)
        if isOfflineRuntime {
            return try client.textJSON(
                prompt: prompt,
                model: client.settings.textModel,
                maxNewTokens: Self.offlineInquiryMaxNewTokens,
                endWith: Self.jsonObjectEnd
            )
        }
        return try client.visionJSON(prompt: prompt, imageDataURL: imageDataURL, model: client.settings.visionModel)
    }

    private func processNavigationFrame(_ imageDataURL: String, forceRefresh: Bool) throws -> [SilverCareMessage] {
        let start = Date()
        let raw = try client.visionJSON(prompt: navigationPrompt(), imageDataURL: imageDataURL, model: client.settings.visionModel)
        let result = try JSONSupport.object(from: raw)

        let priority = result.string("priority", default: "low").lowercased()
        let category = result.string("category", default: "navigation")
        let subject = result.string("subject")
        let distance = result.double("distance", default: 2.0)
        let direction = result.string("direction", default: "ahead")
        var speech = result.string("speech")
        let scene = result.string("scene_description")

        if !scene.isEmpty {
            socialContext.append(scene)
            if socialContext.count > 5 {
                socialContext.removeFirst(socialContext.count - 5)
            }
        }
        if !subject.isEmpty {
            memoryStore.logObject(subject, locationTag: result.string("current_location_tag"), scene: scene)
        }
        if !speech.isEmpty, distance > 0, !speech.contains("米"), !speech.contains("厘米") {
            speech = Self.appendDistance(Self.trimTerminalPunctuation(speech), distance: distance)
        }

        let semanticText = navigationSemanticText(speech: speech, scene: scene, subject: subject, direction: direction, distance: distance)
        if !forceRefresh && shouldSkipSmartNavigationRefresh(priority: priority, semanticText: semanticText) {
            return [SilverCareMessage(type: "smart_refresh_skipped", payload: [
                "text": "画面语义与上次导航一致，已跳过刷新",
                "ms": Self.elapsedMilliseconds(since: start)
            ])]
        }
        if !semanticText.isEmpty {
            lastNavigationSemanticText = semanticText
        }

        var messages: [SilverCareMessage] = []
        if !speech.isEmpty, forceRefresh || shouldSpeak(priority: priority, speech: speech) {
            messages.append(SilverCareMessage(type: "speak", payload: ["text": speech]))
        }
        messages.append(SilverCareMessage(type: "result", payload: [
            "priority": priority,
            "category": category,
            "subject": subject,
            "speech": speech,
            "distance": distance,
            "direction": direction,
            "target_detected": result.bool("target_detected"),
            "current_goal": currentGoal ?? "",
            "social_cues": result["social_cues"] as? [String: Any] ?? [:],
            "environment": result["environment"] as? [String: Any] ?? [:],
            "scene": scene,
            "objects": localizedObjects(result["objects"] as? [[String: Any]] ?? []),
            "ms": Self.elapsedMilliseconds(since: start),
            "stats": [:]
        ]))
        return messages
    }

    private func processMicroFrame(_ imageDataURL: String) throws -> [SilverCareMessage] {
        let start = Date()
        guard let microTarget, !microTarget.isEmpty else {
            mode = .navigation
            return []
        }
        let result = try JSONSupport.object(from: client.visionJSON(
            prompt: microPrompt(),
            imageDataURL: imageDataURL,
            model: client.settings.microModel
        ))
        lastMicroGuidanceSpeech = result.string("guidance_speech", default: lastMicroGuidanceSpeech)
        return [SilverCareMessage(type: "micro_result", payload: [
            "x": result.int("x"),
            "y": result.int("y"),
            "action": result.string("action", default: "move"),
            "guidance_speech": result.string("guidance_speech"),
            "ms": Self.elapsedMilliseconds(since: start)
        ])]
    }

    private func processTaskFrame(_ imageDataURL: String) throws -> [SilverCareMessage] {
        let start = Date()
        guard !taskPlan.isEmpty, currentStepIndex < taskPlan.count else {
            mode = .navigation
            taskPlan = []
            currentStepIndex = 0
            return []
        }
        let step = taskPlan[currentStepIndex]
        let result = try JSONSupport.object(from: client.visionJSON(
            prompt: taskGuidancePrompt(instruction: step.string("instruction")),
            imageDataURL: imageDataURL,
            model: client.settings.visionModel
        ))

        var messages: [SilverCareMessage] = []
        if result.bool("step_completed") {
            taskPlan[currentStepIndex]["completed"] = true
            currentStepIndex += 1
            if currentStepIndex >= taskPlan.count {
                mode = .navigation
                messages.append(SilverCareMessage(type: "speak", payload: ["text": "任务完成。"]))
            } else {
                messages.append(SilverCareMessage(type: "speak", payload: [
                    "text": "这一步完成。下一步：\(taskPlan[currentStepIndex].string("instruction"))"
                ]))
            }
        } else {
            let speech = result.string("speech")
            if !speech.isEmpty, shouldSpeak(priority: "medium", speech: speech) {
                messages.append(SilverCareMessage(type: "speak", payload: ["text": speech]))
            }
        }
        messages.append(SilverCareMessage(type: "task_update", payload: [
            "plan": taskPlan,
            "current_step_index": currentStepIndex,
            "visual_feedback": result.string("visual_feedback"),
            "mode": mode.rawValue,
            "ms": Self.elapsedMilliseconds(since: start)
        ]))
        return messages
    }

    private func taskUpdateMessage(visualFeedback: String = "") -> SilverCareMessage {
        SilverCareMessage(type: "task_update", payload: [
            "plan": taskPlan,
            "current_step_index": currentStepIndex,
            "visual_feedback": visualFeedback,
            "mode": mode.rawValue
        ])
    }

    private func processMicroFollowUpInquiry(imageDataURL: String, transcript: String) throws -> [SilverCareMessage] {
        let result: [String: Any]
        do {
            let prompt = microFollowUpPrompt(transcript: transcript)
            let raw = try client.visionJSON(prompt: prompt, imageDataURL: imageDataURL, model: client.settings.visionModel)
            result = try JSONSupport.object(from: raw)
        } catch {
            result = fallbackIntent(intent: "info", speech: "我正在继续引导你靠近\(microTarget ?? "目标")。如果要结束，请说关闭引导。")
        }
        let speech = result.string("speech", default: "我正在继续引导你靠近\(microTarget ?? "目标")。如果要结束，请说关闭引导。")
        return [
            SilverCareMessage(type: "inquiry_result", payload: [
                "thinking": result.string("thinking", default: "精确引导中的追问"),
                "mode": "micro",
                "task_active": false,
                "speech": speech,
                "transcript": transcript
            ]),
            SilverCareMessage(type: "speak", payload: ["text": speech])
        ]
    }

    private func applyTranscriptFallback(_ transcript: String, modelResult: [String: Any]?) throws -> [String: Any]? {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return modelResult }

        if let control = deterministicTaskControl(text) {
            return control
        }

        let remembered = memoryStore.findObjectLocation(extractMemoryObject(text))
        if !remembered.isEmpty && Self.isWhereQuestion(text) {
            var result = fallbackIntent(intent: "info", speech: remembered)
            result["thinking"] = "根据本地记忆回答物体位置"
            return result
        }

        if var modelResult {
            let intent = normalizeIntent(modelResult.string("intent", default: "info"))
            modelResult["intent"] = intent
            if intent == "search" {
                let target = cleanTarget(modelResult.string("search_target"))
                if target.isEmpty || target.lowercased() == "null" {
                    let extracted = extractSearchTarget(text)
                    if !extracted.isEmpty {
                        modelResult["search_target"] = extracted
                        modelResult["thinking"] = appendThinking(
                            modelResult.string("thinking"),
                            extra: "模型已判定找物，本地仅补全缺失目标。"
                        )
                    }
                }
            }
            return modelResult
        }

        if let tag = extractAfter(text, prefixes: ["记住这里是", "把这里标记为", "这里叫"]), !tag.isEmpty {
            var result = fallbackIntent(intent: "tag", speech: "已记住\(tag)。")
            result["tag_name"] = tag
            result["scene_description"] = tag
            result["thinking"] = "确定性识别地点标记指令"
            return result
        }

        let micro = containsGuidanceKeyword(text)
            ? (extractAfter(text, prefixes: ["引导我摸到", "引导我靠近", "引导我按", "引导我找到", "引导"]) ?? "")
            : ""
        if containsGuidanceKeyword(text), !micro.isEmpty || containsAny(text, "按钮", "开关", "把手", "水龙头") {
            let target = micro.isEmpty ? cleanTarget(text) : micro
            var result = fallbackIntent(intent: "micro_nav", speech: "正在引导你靠近\(target)。")
            result["target"] = target
            result["thinking"] = "确定性识别微导航指令"
            return result
        }

        if let task = extractAfter(text, prefixes: ["教我", "帮我完成", "一步步指导我", "我想"]), !task.isEmpty {
            var result = fallbackIntent(intent: "task", speech: "我来指导你\(task)。")
            result["task_name"] = task
            result["thinking"] = "确定性识别任务指导指令"
            return result
        }

        if Self.isCapabilityQuestion(text) {
            var result = fallbackIntent(intent: "info", speech: offlineCapabilitySpeech(transcript: text, modelSpeech: ""))
            result["thinking"] = "确定性识别能力询问"
            return result
        }

        if Self.isNavigationSafetyQuestion(text) {
            var result = fallbackIntent(intent: "nav_check", speech: "正在查看前方是否可以通行。")
            result["thinking"] = "确定性识别通行和避障询问"
            return result
        }

        let search = extractSearchTarget(text)
        if !search.isEmpty {
            var result = fallbackIntent(intent: "search", speech: "好的，正在寻找\(search)。")
            result["search_target"] = search
            result["thinking"] = "确定性补全搜索目标"
            return result
        }

        return modelResult
    }

    private func normalizeOfflineSearchIntent(transcript: String, result: [String: Any]) -> [String: Any] {
        var output = result
        var rawTarget = cleanTarget(output.string("search_target", default: output.string("goal")))
        if rawTarget.isEmpty || rawTarget.lowercased() == "null" {
            rawTarget = extractSearchTarget(transcript)
        }
        let target = exactSupportedSearchTarget(rawTarget)
        guard !target.isEmpty else {
            mode = .navigation
            currentGoal = nil
            var fallback = fallbackIntent(
                intent: "info",
                speech: "我听到你可能想找“\(rawTarget.isEmpty ? "某个东西" : rawTarget)”，但它不在当前离线视觉可稳定识别的目标清单里。你可以改说：找杯子、碗、手机、椅子、桌子、行李箱等，或者直接问我问题。"
            )
            fallback["thinking"] = "离线找物目标未通过可检测目标校验，未进入搜索模式。"
            return fallback
        }
        output["intent"] = "search"
        output["search_target"] = target
        output["speech"] = "好的，正在寻找\(target)。"
        output["thinking"] = appendThinking(
            output.string("thinking"),
            extra: "离线找物目标已校正为可检测类别：“\(target)”。原始目标：“\(rawTarget)”。"
        )
        return output
    }

    private func handleIntent(intent: String, result: [String: Any]) throws -> String? {
        if intent == "micro_nav" {
            let target = result.string("target")
            if !target.isEmpty {
                mode = .micro
                microTarget = target
                lastMicroGuidanceSpeech = ""
                return "正在引导你靠近\(target)。请保持稳定。"
            }
        } else if intent == "search" {
            let goal = result.string("search_target", default: result.string("goal"))
            if !goal.isEmpty {
                mode = .navigation
                currentGoal = goal
                return "好的，正在寻找\(goal)。"
            }
        } else if intent == "stop" {
            mode = .navigation
            currentGoal = nil
            microTarget = nil
            taskPlan = []
            currentStepIndex = 0
            return "已停止所有任务和搜索。"
        } else if intent == "tag" {
            let name = result.string("tag_name")
            if !name.isEmpty {
                memoryStore.addLocation(name, description: result.string("scene_description"))
                return "已将当前位置标记为\(name)。"
            }
        } else if intent == "task" {
            return try generateTaskPlan(taskName: result.string("task_name"))
        } else if intent.hasPrefix("task_") {
            return try handleTaskControl(intent: intent)
        }
        return nil
    }

    private func generateTaskPlan(taskName: String) throws -> String {
        let clean = taskName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "我没有听清任务名称。" }
        let raw = try client.textJSON(
            prompt: taskPlannerPrompt(taskName: clean),
            model: client.settings.textModel,
            maxNewTokens: Self.taskPlanMaxNewTokens,
            endWith: nil
        )
        taskPlan = try JSONSupport.array(from: raw)
        currentStepIndex = 0
        mode = .task
        return "已为\(clean)生成计划。第一步：\(taskPlan.first?.string("instruction") ?? "")"
    }

    private func handleTaskControl(intent: String) throws -> String {
        guard mode == .task, !taskPlan.isEmpty else {
            return "当前没有可控制的任务。"
        }
        if intent == "task_skip" || intent == "task_done" {
            taskPlan[currentStepIndex]["completed"] = true
            currentStepIndex += 1
            if currentStepIndex >= taskPlan.count {
                mode = .navigation
                return "任务完成。"
            }
            return "已完成。下一步：\(taskPlan[currentStepIndex].string("instruction"))"
        }
        if intent == "task_previous" {
            if currentStepIndex > 0 {
                currentStepIndex -= 1
                taskPlan[currentStepIndex]["completed"] = false
                return "返回上一步：\(taskPlan[currentStepIndex].string("instruction"))"
            }
            return "已经在第一步。"
        }
        if intent == "task_repeat" {
            return "当前步骤：\(taskPlan[currentStepIndex].string("instruction"))"
        }
        if intent == "task_status" {
            return "当前是第 \(currentStepIndex + 1) 步，共 \(taskPlan.count) 步。"
        }
        return "未知的任务指令。"
    }

    private func shouldSkipSmartNavigationRefresh(priority: String, semanticText: String) -> Bool {
        guard client.settings.smartNavigationRefreshEnabled else { return false }
        guard priority != "critical", !semanticText.isEmpty, !lastNavigationSemanticText.isEmpty else { return false }
        do {
            let raw = try client.textJSON(
                prompt: smartNavigationConsistencyPrompt(previous: lastNavigationSemanticText, current: semanticText),
                model: client.settings.textModel,
                maxNewTokens: Self.offlineSmartRefreshMaxNewTokens,
                endWith: Self.jsonObjectEnd
            )
            return try JSONSupport.object(from: raw).bool("consistent")
        } catch {
            return false
        }
    }

    private func shouldSpeak(priority: String, speech: String) -> Bool {
        let now = Date().timeIntervalSince1970
        if priority == "critical" {
            lastSpeechAt = now
            lastSpeech = speech
            return true
        }
        let duplicateWindow: TimeInterval = client.settings.voiceFirstEnabled ? 4.2 : 8.0
        let cooldown: TimeInterval = client.settings.voiceFirstEnabled ? 1.3 : 3.0
        if speech == lastSpeech && now - lastSpeechAt < duplicateWindow {
            return false
        }
        if now - lastSpeechAt < cooldown {
            return false
        }
        lastSpeechAt = now
        lastSpeech = speech
        return true
    }

    private var isOfflineRuntime: Bool {
        SilverCareRuntimeMode(rawValue: client.settings.aiRuntimeMode)?.isOffline ?? true
    }

    private func localizedObjects(_ source: [[String: Any]]) -> [[String: Any]] {
        source.map { item in
            var copy = item
            if let name = copy["name"] as? String {
                copy["name"] = OfflineVisionInterpreter.localizeObjectName(name)
            }
            if let category = copy["category"] as? String {
                copy["category"] = OfflineVisionInterpreter.localizeObjectName(category)
            }
            return copy
        }
    }
}

private extension SilverCareProcessor {
    func navigationPrompt() -> String {
        let context = socialContext.isEmpty ? "无" : socialContext.joined(separator: " | ")
        let task = currentGoal == nil ? "通用导航" : "正在寻找：\(currentGoal!)"
        return """
        You are 银龄智护, a socially aware visual navigation assistant for blind users.
        Keep JSON keys and enum values in English. All natural-language values must be Simplified Chinese.
        Current task: \(task)
        Temporal context: \(context)
        Memory: \(memoryStore.historyContext())
        Known locations: \(memoryStore.locationSummary())

        Analyze hazards, navigable space, people, social intent, object states, text, and affordances.
        If immediate danger is within 0.5m, start speech with "停下".
        Target search rule:
        - If Current task starts with "正在寻找：" and the requested target is not clearly visible in the current image, do NOT infer or guess its location, direction, or distance.
        - In that case return target_detected:false, priority:"low", category:"target", subject as the requested target, distance:0, direction:"unknown", confidence_score:0.
        - The speech must say the target is not in the frame yet and ask the user to slowly turn the phone left or right, then refresh. Example: "画面里还没有找到杯子。请左右缓慢转动手机，然后点击刷新。"
        - Only set target_detected:true and give a direction/distance when the target is clearly visible with high confidence.
        The user is blind or has low vision, often an older adult. Speech must be actionable without seeing the screen:
        - Use body-relative directions: 正前方、左前方、右手边、脚边、腰部高度.
        - Avoid color-only or vague references like "绿色行李箱旁边" or "排插附近".
        - If a visual object is useful as an anchor, turn it into touchable steps: first reach it, then describe where to move hand/phone next.
        - Prefer short sequential guidance such as "向前一步，右手摸到行李箱后，沿底部向下摸".
        - Tell the user when to point the phone at a tactile anchor and ask for the next step.

        Output JSON:
        {
          "thinking": "中文简短推理",
          "target_detected": false,
          "priority": "critical|high|medium|low",
          "category": "social|navigation|hazard|text|target|furniture",
          "subject": "主要对象",
          "current_location_tag": null,
          "distance": 2.0,
          "direction": "ahead|left|right|behind|11 o'clock",
          "confidence_score": 90,
          "speech": "中文简短可执行提示",
          "scene_description": "中文场景摘要",
          "social_cues": {"intent":"passive|interaction_seeking|hazard|none","details":"中文细节","crowd_flow":"static|moving_fast|dispersing|none"},
          "environment": {"occupancy":"free|occupied|unknown","markers":["中文标记"],"affordances":"中文可操作方式"},
          "objects": [{"name":"对象名","category":"类别","distance":2.0,"direction":"ahead","confidence_score":90,"risk_level":"low|med|high"}]
        }
        """
    }

    func microPrompt() -> String {
        """
        You are 多模态长护精确引导模式, a high-speed precision guidance system.
        Target: \(microTarget ?? "")
        Keep JSON keys and action enum values in English. guidance_speech must be Simplified Chinese.
        Locate the target and return relative vector from image center.
        X: -100 left to 100 right. Y: -100 down to 100 up.
        action: move, push, or stop.
        The user may be blind or low-vision. Use direct tactile and body-relative words in guidance_speech.
        Do not rely on color-only clues. Prefer "手机稍微向左", "向前半步", "右手沿桌边向下摸", "现在按下".
        Output JSON:
        {"x":0,"y":0,"action":"move|push|stop","guidance_speech":"向左|向右|向上|向下|慢慢向前|现在按下|null"}
        """
    }

    func microFollowUpPrompt(transcript: String) -> String {
        """
        You are 银龄智护 during an active precision guidance session for a blind or low-vision user.
        Current precision target: "\(microTarget ?? "")"
        Last short guidance: "\(lastMicroGuidanceSpeech)"
        User follow-up question: "\(transcript)"
        Memory: \(memoryStore.historyContext())

        Important control rule:
        - The user has NOT said the exact keyword "引导" in this follow-up, so do not start a new precision target.
        - The user has NOT said "关闭", so keep the current precision guidance active.
        - Answer the question in the context of the current target and the current image.

        Speaking style:
        - Do not say vague visual-only phrases such as "绿色行李箱旁边" as the whole answer.
        - Convert visual anchors into tactile steps and body-relative directions.
        - Good style: "你前面有个行李箱。向前一步摸到行李箱后，沿它的底部往下摸，排插在更靠近地面的方向。把手机对准排插再问我下一步。"
        - Mention color only as secondary information, never as the only way to find something.

        Return exactly one JSON object. No Markdown.
        Output JSON:
        {"thinking":"中文简短推理","speech":"面向盲人或低视力老年人的中文回答"}
        """
    }

    func inquiryPrompt(transcript: String) -> String {
        """
        You are 银龄智护, the brain of a smart navigation assistant for blind users.
        Understand Mandarin Chinese and English. Keep JSON keys and intent enum values in English.
        Write all natural-language values in Simplified Chinese.
        User command transcript: "\(transcript)"
        History: \(memoryStore.historyContext())
        Task state: \(taskStateText())

        Intents:
        micro_nav: press/find/manipulate a small target. Set target.
        search: find or locate an object. Set search_target.
        tag: remember current place. Set tag_name and scene_description.
        task: complex physical process. Set task_name.
        task_skip, task_previous, task_repeat, task_done, task_status: control active task.
        stop: cancel current search/task.
        info: answer question or describe scene/text.

        Rules:
        Return exactly one JSON object.
        Do not output Markdown, explanations, examples, or multiple JSON blocks.
        intent must be one of the listed enum values; never invent another intent value.
        intent must be one concrete string such as "search"; do not copy the whole enum list into intent.
        intent must be written in English exactly as listed, never in Chinese.
        Use null for fields that do not apply.
        For a find/search command, always set search_target to the object named by the user, even if the object is not visible yet.
        History is authoritative for "where is my object" questions.
        If the user asks where a remembered object is, use intent "info" and answer from History.
        Task control overrides micro navigation. If Task state says a task is active and the user says this step is done/completed, use intent "task_done".
        Use intent "micro_nav" ONLY when the user explicitly says the keyword "引导".
        If the user asks to press, touch, align with, or manipulate a small object but does not say "引导", use intent "info" and explain that precision guidance starts only after saying "引导我靠近...".
        If the user says "关闭" during precision guidance, close precision guidance.
        The user is blind or low-vision. All speech must use body-relative, tactile, step-by-step language. Do not rely on color-only or vague visual references.

        Output fields:
        thinking, intent, search_target, target, tag_name, task_name, scene_description, speech.

        Reference examples:
        {"thinking":"用户要找门","intent":"search","search_target":"门","target":null,"tag_name":null,"task_name":null,"scene_description":null,"speech":"正在寻找门。"}
        {"thinking":"用户问杯子位置，本地记忆可回答","intent":"info","search_target":null,"target":null,"tag_name":null,"task_name":null,"scene_description":null,"speech":"你的杯子上次在餐桌右前角。"}
        {"thinking":"用户要精确按按钮且说了引导","intent":"micro_nav","search_target":null,"target":"电梯上行按钮","tag_name":null,"task_name":null,"scene_description":null,"speech":"正在引导你靠近电梯上行按钮。"}
        """
    }

    func smartNavigationConsistencyPrompt(previous: String, current: String) -> String {
        """
        你是 银龄智护 的导航刷新判定器。
        判断两段面向盲人用户的导航提示是否语义一致。

        一致的定义：
        - 主要障碍、方向、目标或通行建议没有实质变化；
        - 距离只有小幅变化，且不改变行动建议；
        - 描述文字不同但用户听到后的行动不变。

        不一致的定义：
        - 出现新的危险、目标、可通行方向或阻挡；
        - 方向明显变化；
        - 距离变化足以改变行动建议；
        - 当前提示优先级更高或需要用户立即改变动作。

        只输出 JSON，不要 Markdown，不要解释。
        JSON 格式：
        {"consistent":true,"reason":"中文短原因"}

        上一次：
        \(previous)

        当前：
        \(current)
        """
    }

    func taskPlannerPrompt(taskName: String) -> String {
        """
        You are 银龄智护's task planner.
        User request: "\(taskName)"
        Memory: \(memoryStore.historyContext())
        Break the user's physical task into granular, observable, sequential steps.
        Return exactly one JSON array. Output at least 3 steps.
        """
    }

    func taskGuidancePrompt(instruction: String) -> String {
        """
        You are 银龄智护, guiding a user through a physical task.
        Current step: "\(instruction)"
        Return exactly one JSON object:
        {"step_completed":false,"speech":"中文引导","visual_feedback":"中文短状态"}
        """
    }

    func taskStateText() -> String {
        guard mode == .task, !taskPlan.isEmpty, currentStepIndex < taskPlan.count else {
            return "当前没有进行中的任务"
        }
        return "当前任务：第 \(currentStepIndex + 1)/\(taskPlan.count) 步 - “\(taskPlan[currentStepIndex].string("instruction"))”"
    }

    func navigationSemanticText(speech: String, scene: String, subject: String, direction: String, distance: Double) -> String {
        var parts: [String] = []
        if !speech.isEmpty { parts.append("speech: \(speech)") }
        if !scene.isEmpty { parts.append("scene: \(scene)") }
        if !subject.isEmpty { parts.append("subject: \(subject)") }
        if !direction.isEmpty { parts.append("direction: \(direction)") }
        if distance > 0 { parts.append("distance: \(Self.formatDistance(distance))") }
        return parts.joined(separator: "\n")
    }
}

private extension SilverCareProcessor {
    func deterministicTaskControl(_ text: String) -> [String: Any]? {
        guard mode == .task, !taskPlan.isEmpty else { return nil }
        if containsAny(text, "完成", "好了", "做完", "下一步") {
            var result = fallbackIntent(intent: "task_done", speech: "好的，这一步已完成。")
            result["thinking"] = "确定性识别任务步骤完成"
            return result
        }
        if containsAny(text, "跳过") {
            return fallbackIntent(intent: "task_skip", speech: "已跳过这一步。")
        }
        if containsAny(text, "上一步", "上一部", "前一步") {
            return fallbackIntent(intent: "task_previous", speech: "返回上一步。")
        }
        if containsAny(text, "重复", "再说一遍") {
            return fallbackIntent(intent: "task_repeat", speech: "我再重复当前步骤。")
        }
        if containsAny(text, "第几步", "进度", "状态") {
            return fallbackIntent(intent: "task_status", speech: "正在查看当前步骤。")
        }
        return nil
    }

    func fallbackIntent(intent: String, speech: String) -> [String: Any] {
        [
            "thinking": "",
            "intent": intent,
            "search_target": NSNull(),
            "target": NSNull(),
            "tag_name": NSNull(),
            "task_name": NSNull(),
            "scene_description": NSNull(),
            "speech": speech
        ]
    }

    func expandCompactInquiryResult(_ result: [String: Any]) -> [String: Any] {
        var expanded = result
        if expanded["intent"] == nil, let code = expanded["i"] as? String {
            expanded["intent"] = expandIntentCode(code)
        }
        if expanded["speech"] == nil, let speech = expanded["s"] as? String {
            expanded["speech"] = speech
        }
        if expanded["thinking"] == nil, let thinking = expanded["r"] as? String {
            expanded["thinking"] = thinking
        }
        if expanded["search_target"] == nil, let query = expanded["q"] as? String {
            expanded["search_target"] = query
        }
        if expanded["target"] == nil, let target = expanded["t"] as? String {
            expanded["target"] = target
        }
        if expanded["tag_name"] == nil, let tag = expanded["tag"] as? String {
            expanded["tag_name"] = tag
        }
        if expanded["task_name"] == nil, let task = expanded["task"] as? String {
            expanded["task_name"] = task
        }
        if expanded["scene_description"] == nil, let scene = expanded["scene"] as? String {
            expanded["scene_description"] = scene
        }
        expanded["thinking"] = expanded.string("thinking")
        expanded["intent"] = expanded.string("intent", default: "info")
        expanded["speech"] = expanded.string("speech")
        return expanded
    }

    func normalizeIntent(_ value: String) -> String {
        expandIntentCode(value)
    }

    func expandIntentCode(_ value: String) -> String {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = code.lowercased()
        let allowed = [
            "search", "nav_check", "micro_nav", "tag", "task",
            "task_done", "task_skip", "task_previous", "task_repeat",
            "task_status", "stop", "info"
        ]
        if allowed.contains(lower) { return lower }
        let first = code.first.map { String($0).uppercased() } ?? ""
        switch first {
        case "S": return "search"
        case "N": return "nav_check"
        case "M": return "micro_nav"
        case "L": return "tag"
        case "P": return "task"
        case "D": return "task_done"
        case "K": return "task_skip"
        case "B": return "task_previous"
        case "R": return "task_repeat"
        case "U": return "task_status"
        case "X": return "stop"
        default: return "info"
        }
    }

    func offlineCapabilitySpeech(transcript: String, modelSpeech: String) -> String {
        let speech = modelSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
        if !speech.isEmpty, speech != "找物", speech != "正在找物", speech.count >= 6, !speech.contains("某个东西") {
            return speech
        }
        if Self.isCapabilityQuestion(transcript) {
            return "我可以看路、找东西、提醒风险。"
        }
        return "我可以继续回答，也可以帮你看路、找东西。"
    }

    func exactSupportedSearchTarget(_ value: String) -> String {
        let clean = normalizeText(value)
        guard !clean.isEmpty, clean != "none", clean != "null" else { return "" }
        return OfflineVisionInterpreter.canonicalSearchTarget(clean)
    }
}

private extension SilverCareProcessor {
    static func isWhereQuestion(_ text: String) -> Bool {
        containsAny(text, "在哪里", "在哪", "放哪", "哪里", "哪儿")
    }

    static func isCapabilityQuestion(_ text: String) -> Bool {
        containsAny(text, "可以做什么", "可以说什么", "能做什么", "有什么功能", "你会什么", "你能干什么", "能帮我什么")
    }

    static func isNavigationSafetyQuestion(_ text: String) -> Bool {
        if containsAny(text, "障碍", "避障", "路况", "通行", "可不可以走", "能不能走", "能不能过", "能走吗") {
            return true
        }
        let asksFront = containsAny(text, "看看前面", "看下前面", "看一下前面", "看看前方", "看下前方", "前面", "前方")
        let asksSafety = containsAny(text, "能不能", "有没有", "能否", "危险", "安全", "走", "着", "过", "路")
        return asksFront && asksSafety && !containsAny(text, "找我的", "找到我的", "帮我找", "寻找", "找一下")
    }

    func isSearchIntentRequest(_ text: String) -> Bool {
        guard !Self.isNavigationSafetyQuestion(text) else { return false }
        return containsAny(text, "帮我找", "帮我找到", "找一下", "寻找", "找找", "找到我的", "找我的", "我的", "在哪里", "在哪", "哪儿", "哪里", "定位")
            && !Self.isCapabilityQuestion(text)
    }

    func extractMemoryObject(_ text: String) -> String {
        cleanTarget(text)
            .replacingOccurrences(of: "我的", with: "")
            .replacingOccurrences(of: "我记的", with: "")
            .replacingOccurrences(of: "在哪里", with: "")
            .replacingOccurrences(of: "在哪", with: "")
            .replacingOccurrences(of: "放哪了", with: "")
            .replacingOccurrences(of: "放哪", with: "")
            .replacingOccurrences(of: "哪里", with: "")
            .replacingOccurrences(of: "哪儿", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func extractSearchTarget(_ text: String) -> String {
        if let value = extractAfter(text, prefixes: ["帮我找到", "帮我找", "找我的", "找到我的", "找一下", "带我去找", "我要找", "寻找"]), !value.isEmpty {
            return value
        }
        if Self.isWhereQuestion(text), !text.hasPrefix("我的") {
            return extractMemoryObject(text)
        }
        return ""
    }

    func extractAfter(_ text: String, prefixes: [String]) -> String? {
        for prefix in prefixes {
            guard let range = text.range(of: prefix) else { continue }
            return cleanTarget(String(text[range.upperBound...]))
        }
        return nil
    }

    func cleanTarget(_ value: String) -> String {
        var clean = value
        ["请", "帮我", "我的", "这个", "那个", "一个", "一只", "一把", "一张", "一台", "一部", "一下", "。", "？", "?", "！", "，", ","]
            .forEach { clean = clean.replacingOccurrences(of: $0, with: "") }
        while clean.hasPrefix("到") {
            clean.removeFirst()
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func appendThinking(_ existing: String, extra: String) -> String {
        let clean = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? extra : "\(clean)\n\(extra)"
    }

    func normalizeText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
    }

    static func formatDistance(_ meters: Double) -> String {
        if meters < 1.0 {
            return "\(Int((meters * 100).rounded()))厘米"
        }
        if meters < 10.0 {
            return String(format: "%.1f米", meters)
        }
        return "\(Int(meters.rounded()))米"
    }

    static func trimTerminalPunctuation(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t。！？!?，,；;：:"))
    }

    static func appendDistance(_ text: String, distance: Double) -> String {
        "\(text)，距离\(formatDistance(distance))。"
    }

    static func elapsedMilliseconds(since start: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(start) * 1000))
    }
}

private func containsGuidanceKeyword(_ text: String) -> Bool {
    text.contains("引导")
}

private func containsCloseKeyword(_ text: String) -> Bool {
    containsAny(text, "关闭", "停止", "退出", "结束", "取消")
}

private func containsAny(_ text: String, _ needles: String...) -> Bool {
    needles.contains { text.contains($0) }
}
