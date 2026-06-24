import XCTest
@testable import SilverCareCore

final class SilverCareProcessorTests: XCTestCase {
    func testNavigationFrameEmitsResultAndSpeechWithDistance() throws {
        let ai = FakeAIClient()
        ai.visionResponses.append("""
        {
          "thinking":"前方有门",
          "priority":"high",
          "category":"navigation",
          "subject":"门",
          "distance":0.75,
          "direction":"ahead",
          "speech":"前方有门",
          "scene_description":"走廊尽头有门",
          "objects":[{"name":"door","distance":0.75,"direction":"ahead"}]
        }
        """)
        let processor = SilverCareProcessor(client: ai)

        let messages = try processor.processFrame("data:image/png;base64,test")

        XCTAssertEqual(messages.first(type: "speak")?.string("text"), "前方有门，距离75厘米。")
        XCTAssertEqual(messages.first(type: "result")?.string("direction"), "ahead")
        let objects = messages.first(type: "result")?.payload["objects"] as? [[String: Any]]
        XCTAssertEqual(objects?.first?["name"] as? String, "门")
    }

    func testNavigationFrameParsesNoisyCloudJSONEnvelope() throws {
        let ai = FakeAIClient(settings: dashScopeSettings())
        ai.visionResponses.append("""
        下面是导航字段：[priority, speech
        ```json
        {
          "thinking":"前方可通行",
          "priority":"low",
          "category":"navigation",
          "subject":"通行空间",
          "distance":2.0,
          "direction":"ahead",
          "speech":"前方通道可以通行。",
          "scene_description":"室内通道较空旷",
          "objects":[]
        }
        ```
        """)
        let processor = SilverCareProcessor(client: ai)

        let messages = try processor.processFrame("data:image/png;base64,test")

        XCTAssertEqual(messages.first(type: "result")?.string("speech"), "前方通道可以通行，距离2.0米。")
        XCTAssertEqual(messages.first(type: "result")?.string("direction"), "ahead")
    }

    func testCloudNavigationPromptMatchesAndroidActionableGuidanceContract() throws {
        let ai = FakeAIClient(settings: dashScopeSettings())
        ai.visionResponses.append(navigationResponse(subject: "排插", speech: "向前一步，右手摸到行李箱后，沿底部向下摸。"))
        let processor = SilverCareProcessor(client: ai)

        let messages = try processor.processFrame("data:image/png;base64,test")

        XCTAssertEqual(ai.lastVisionModel, "qwen3-vl-flash")
        XCTAssertTrue(ai.lastVisionPrompt.contains("Speech must be actionable without seeing the screen"))
        XCTAssertTrue(ai.lastVisionPrompt.contains("Use body-relative directions"))
        XCTAssertTrue(ai.lastVisionPrompt.contains("Avoid color-only"))
        XCTAssertTrue(ai.lastVisionPrompt.contains("touchable steps"))
        XCTAssertTrue(ai.lastVisionPrompt.contains("do NOT infer or guess its location"))
        XCTAssertTrue(ai.lastVisionPrompt.contains("请左右缓慢转动手机，然后点击刷新"))
        XCTAssertTrue(ai.lastVisionPrompt.contains(#""current_location_tag": null"#))
        XCTAssertTrue(ai.lastVisionPrompt.contains(#""environment": {"occupancy""#))
        XCTAssertEqual(messages.first(type: "result")?.string("category"), "target")
        XCTAssertNotNil(messages.first(type: "result")?.payload["environment"])
        XCTAssertNotNil(messages.first(type: "result")?.payload["social_cues"])
        XCTAssertNotNil(messages.first(type: "result")?.payload["ms"])
    }

    func testSearchInquiryUpdatesGoalAndRunsNavigationOnSameFrame() throws {
        let ai = FakeAIClient(settings: dashScopeSettings())
        ai.transcript = "帮我找杯子"
        ai.visionResponses.append(inquiryIntent(intent: "search", searchTarget: "杯子", speech: "开始找杯子"))
        ai.visionResponses.append(navigationResponse(subject: "杯子", speech: "杯子在右侧，距离约1.2米。"))
        let processor = SilverCareProcessor(client: ai)

        let messages = try processor.processInquiry(
            imageDataURL: "data:image/png;base64,test",
            audioDataURL: "data:audio/wav;base64,test"
        )

        XCTAssertEqual(processor.currentGoal, "杯子")
        XCTAssertEqual(messages.first(type: "inquiry_result")?.string("current_goal"), "杯子")
        XCTAssertEqual(messages.first(type: "speak")?.string("text"), "好的，正在寻找杯子。")
        XCTAssertEqual(messages.first(type: "result")?.string("current_goal"), "杯子")
        XCTAssertTrue(ai.lastVisionPrompt.contains("正在寻找：杯子"))
        XCTAssertTrue(ai.lastVisionPrompt.contains("do NOT infer or guess its location"))
        XCTAssertTrue(ai.lastVisionPrompt.contains("target_detected:false"))
    }

    func testOfflineNavigationQuestionDoesNotBecomeSearchTarget() throws {
        var settings = SilverCareSettings()
        settings.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
        let ai = FakeAIClient(settings: settings)
        ai.textResponses.append(#"{"i":"N","s":"正在查看前方通行。"}"#)
        ai.visionResponses.append("""
        {
          "priority":"high",
          "category":"hazard",
          "subject":"大型障碍",
          "distance":1.0,
          "direction":"ahead",
          "speech":"前方有大型障碍，请向右侧绕开。",
          "scene_description":"前方通道有障碍"
        }
        """)
        let processor = SilverCareProcessor(client: ai)

        let messages = try processor.processTextInquiry(
            imageDataURL: "data:image/png;base64,test",
            transcript: "帮我看看前面能不能着前方有没有障碍物"
        )

        XCTAssertNil(processor.currentGoal)
        XCTAssertEqual(messages.first(type: "inquiry_result")?.string("intent"), "nav_check")
        XCTAssertTrue(ai.lastVisionPrompt.contains("通用导航"))
        XCTAssertEqual(messages.first(type: "result")?.string("current_goal"), "")
    }

    func testOfflineInquiryUsesTextModelForIntent() throws {
        var settings = SilverCareSettings()
        settings.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
        settings.textModel = "qwen3-4b-instruct-2507-mnn"
        let ai = FakeAIClient(settings: settings)
        ai.transcript = "帮我找杯子"
        ai.textResponses.append(inquiryIntent(intent: "search", searchTarget: "杯子", speech: "开始找杯子"))
        ai.visionResponses.append(navigationResponse(subject: "杯子", speech: "杯子在右侧桌面，向右转。"))
        let processor = SilverCareProcessor(client: ai)

        let messages = try processor.processInquiry(
            imageDataURL: "data:image/png;base64,test",
            audioDataURL: "data:audio/wav;base64,test"
        )

        XCTAssertEqual(messages.first(type: "inquiry_result")?.string("current_goal"), "杯子")
        XCTAssertTrue(ai.lastTextPrompt.contains("帮我找杯子"))
        XCTAssertEqual(ai.lastTextModel, "qwen3-4b-instruct-2507-mnn")
        XCTAssertEqual(ai.lastTextMaxNewTokens, 24)
        XCTAssertEqual(ai.lastTextEndWith, "}")
        XCTAssertTrue(ai.lastVisionPrompt.contains("正在寻找：杯子"))
    }

    func testOfflineCompactIntentNormalizesNoisyRouterCode() throws {
        var settings = SilverCareSettings()
        settings.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
        let ai = FakeAIClient(settings: settings)
        ai.transcript = "帮我找杯子"
        ai.textResponses.append(#"{"i":"S找物","q":"杯子","s":"开始找杯子"}"#)
        ai.visionResponses.append(navigationResponse(subject: "杯子", speech: "杯子在右侧桌面，向右转。"))
        let processor = SilverCareProcessor(client: ai)

        let messages = try processor.processInquiry(
            imageDataURL: "data:image/png;base64,test",
            audioDataURL: "data:audio/wav;base64,test"
        )

        XCTAssertEqual(messages.first(type: "inquiry_result")?.string("intent"), "search")
        XCTAssertEqual(messages.first(type: "inquiry_result")?.string("current_goal"), "杯子")
        XCTAssertEqual(messages.first(type: "result")?.string("current_goal"), "杯子")
    }

    func testOfflineCompactIntentFallsBackToInfoWhenRouterReturnsInvalidCode() throws {
        var settings = SilverCareSettings()
        settings.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
        let ai = FakeAIClient(settings: settings)
        ai.transcript = "你好，你可以做什么"
        ai.textResponses.append(#"{"i":"你好","s":"我可以帮你看路、找东西、提醒风险。"}"#)
        let processor = SilverCareProcessor(client: ai)

        let messages = try processor.processInquiry(
            imageDataURL: "data:image/png;base64,test",
            audioDataURL: "data:audio/wav;base64,test"
        )

        XCTAssertNil(processor.currentGoal)
        XCTAssertEqual(messages.first(type: "inquiry_result")?.string("intent"), "info")
        XCTAssertTrue(messages.first(type: "speak")?.string("text").contains("看路") ?? false)
        XCTAssertTrue(messages.all(type: "result").isEmpty)
    }

    func testOfflineInfoInquiryUsesShortFourBPromptAndTokenBudget() throws {
        var settings = SilverCareSettings()
        settings.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
        settings.textModel = "qwen3-4b-instruct-2507-mnn"
        let ai = FakeAIClient(settings: settings)
        ai.transcript = "我现在有点不知道该怎么办"
        ai.textResponses.append(inquiryIntent(intent: "info", speech: "我可以帮你看路、找东西、提醒风险。"))
        let processor = SilverCareProcessor(client: ai)

        let messages = try processor.processInquiry(
            imageDataURL: "data:image/png;base64,test",
            audioDataURL: "data:audio/wav;base64,test"
        )

        XCTAssertEqual(messages.first(type: "inquiry_result")?.string("intent"), "info")
        XCTAssertTrue(messages.first(type: "speak")?.string("text").contains("看路") ?? false)
        XCTAssertTrue(ai.lastTextPrompt.contains("我现在有点不知道该怎么办"))
        XCTAssertEqual(ai.lastTextModel, "qwen3-4b-instruct-2507-mnn")
        XCTAssertEqual(ai.lastTextMaxNewTokens, 24)
        XCTAssertEqual(ai.lastTextEndWith, "}")
    }

    func testOfflineSearchCorrectsAsrTargetBeforeStartingSearch() throws {
        var settings = SilverCareSettings()
        settings.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
        let ai = FakeAIClient(settings: settings)
        ai.transcript = "帮我找到我的晚"
        ai.textResponses.append(inquiryIntent(intent: "search", searchTarget: "到我的晚", speech: "开始找晚"))
        ai.visionResponses.append(navigationResponse(subject: "碗", speech: "碗在左侧，距离约1.2米。"))
        let processor = SilverCareProcessor(client: ai)

        let messages = try processor.processInquiry(
            imageDataURL: "data:image/png;base64,test",
            audioDataURL: "data:audio/wav;base64,test"
        )

        XCTAssertEqual(processor.currentGoal, "碗")
        XCTAssertEqual(messages.first(type: "speak")?.string("text"), "好的，正在寻找碗。")
        XCTAssertEqual(messages.first(type: "result")?.string("current_goal"), "碗")
    }

    func testOfflineNavigationQuestionOverridesModelSearchMisroute() throws {
        var settings = SilverCareSettings()
        settings.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
        let ai = FakeAIClient(settings: settings)
        ai.transcript = "帮我看看前面能不能着前方有没有障碍物"
        ai.textResponses.append(inquiryIntent(intent: "search", searchTarget: "前方障碍物", speech: "正在寻找障碍物"))
        ai.visionResponses.append(navigationResponse(subject: "小型障碍", speech: "左侧约3.5米有小型障碍，请注意避让。"))
        let processor = SilverCareProcessor(client: ai)

        let messages = try processor.processInquiry(
            imageDataURL: "data:image/png;base64,test",
            audioDataURL: "data:audio/wav;base64,test"
        )

        XCTAssertNil(processor.currentGoal)
        XCTAssertEqual(messages.first(type: "inquiry_result")?.string("intent"), "nav_check")
        XCTAssertEqual(messages.first(type: "inquiry_result")?.string("current_goal"), "")
        XCTAssertEqual(messages.first(type: "result")?.string("current_goal"), "")
        XCTAssertEqual(messages.first(type: "speak")?.string("text"), "正在查看前方是否可以通行。")
        XCTAssertTrue(ai.lastVisionPrompt.contains("通用导航"))
    }

    func testOfflineSearchRejectsUnsupportedTargetAndStaysInConversation() throws {
        var settings = SilverCareSettings()
        settings.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
        let ai = FakeAIClient(settings: settings)
        ai.transcript = "帮我找药盒"
        ai.textResponses.append(inquiryIntent(intent: "search", searchTarget: "药盒", speech: "开始找药盒"))
        let processor = SilverCareProcessor(client: ai)

        let messages = try processor.processInquiry(
            imageDataURL: "data:image/png;base64,test",
            audioDataURL: "data:audio/wav;base64,test"
        )

        XCTAssertNil(processor.currentGoal)
        XCTAssertEqual(processor.mode, .navigation)
        XCTAssertEqual(messages.first(type: "inquiry_result")?.string("current_goal"), "")
        XCTAssertTrue(messages.first(type: "speak")?.string("text").contains("不在当前离线视觉可稳定识别的目标清单里") ?? false)
        XCTAssertTrue(messages.all(type: "result").isEmpty)
    }

    func testOfflineInquiryAcceptsFirstJsonWhenBackupModelAddsExtraText() throws {
        var settings = SilverCareSettings()
        settings.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
        let ai = FakeAIClient(settings: settings)
        ai.transcript = "请问你可以做什么"
        ai.textResponses.append("""
        我会先给出结果：
        {"thinking":"能力说明","intent":"info","search_target":null,"speech":"我可以帮你看路、找东西、提醒风险。"}
        后续误输出：
        {"intent":"search","search_target":"杯子","speech":"忽略这一段"}
        """)
        let processor = SilverCareProcessor(client: ai)

        let messages = try processor.processInquiry(
            imageDataURL: "data:image/png;base64,test",
            audioDataURL: "data:audio/wav;base64,test"
        )

        XCTAssertNil(processor.currentGoal)
        XCTAssertEqual(messages.first(type: "inquiry_result")?.string("intent"), "info")
        XCTAssertTrue(messages.first(type: "speak")?.string("text").contains("看路") ?? false)
    }

    func testTranscriptFallbackRestoresSearchTargetWhenSmallModelLeavesItNull() throws {
        var settings = SilverCareSettings()
        settings.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
        let ai = FakeAIClient(settings: settings)
        ai.transcript = "帮我找杯子"
        ai.textResponses.append(#"{"thinking":"缺少信息","intent":"search","search_target":null,"speech":"请提供更多信息"}"#)
        ai.visionResponses.append(navigationResponse(subject: "杯子", speech: "杯子在正前方。"))
        let processor = SilverCareProcessor(client: ai)

        let messages = try processor.processInquiry(
            imageDataURL: "data:image/png;base64,test",
            audioDataURL: "data:audio/wav;base64,test"
        )

        XCTAssertEqual(processor.currentGoal, "杯子")
        XCTAssertEqual(messages.first(type: "inquiry_result")?.string("current_goal"), "杯子")
        XCTAssertEqual(messages.first(type: "result")?.string("current_goal"), "杯子")
    }

    func testTranscriptFallbackAnswersRememberedObjectLocation() throws {
        var settings = SilverCareSettings()
        settings.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
        let ai = FakeAIClient(settings: settings)
        ai.transcript = "我的水杯在哪里"
        let memory = SilverCareMemoryStore()
        memory.logObject("水杯", locationTag: "厨房水槽左侧", scene: "")
        let processor = SilverCareProcessor(client: ai, memoryStore: memory)

        let messages = try processor.processInquiry(
            imageDataURL: "data:image/png;base64,test",
            audioDataURL: "data:audio/wav;base64,test"
        )

        XCTAssertNil(processor.currentGoal)
        XCTAssertEqual(messages.first(type: "inquiry_result")?.string("intent"), "info")
        XCTAssertTrue(messages.first(type: "speak")?.string("text").contains("厨房水槽左侧") ?? false)
        XCTAssertTrue(messages.all(type: "result").isEmpty)
    }

    func testMicroNavigationRequiresGuidanceKeyword() throws {
        let ai = FakeAIClient(settings: dashScopeSettings())
        ai.visionResponses.append("""
        {
          "thinking":"模型误判为精确引导",
          "intent":"micro_nav",
          "target":"电梯上行按钮",
          "speech":"正在引导你靠近上行按钮。"
        }
        """)
        let processor = SilverCareProcessor(client: ai)

        let messages = try processor.processTextInquiry(
            imageDataURL: "data:image/png;base64,test",
            transcript: "帮我按电梯上行按钮"
        )

        XCTAssertEqual(processor.mode, .navigation)
        XCTAssertTrue(messages.first(type: "speak")?.string("text").contains("请说：引导我靠近目标") ?? false)
    }

    func testOfflineInquiryFallsBackWhenBackupModelReturnsNoJson() throws {
        var settings = SilverCareSettings()
        settings.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
        let ai = FakeAIClient(settings: settings)
        ai.transcript = "引导我按电梯的上行按钮"
        ai.textResponses.append("上行按钮通常在电梯门旁边，请慢慢靠近。")
        let processor = SilverCareProcessor(client: ai)

        let messages = try processor.processInquiry(
            imageDataURL: "data:image/png;base64,test",
            audioDataURL: "data:audio/wav;base64,test"
        )

        XCTAssertEqual(processor.mode, .micro)
        XCTAssertEqual(messages.first(type: "inquiry_result")?.string("mode"), "micro")
        XCTAssertTrue(messages.first(type: "speak")?.string("text").contains("正在引导你靠近电梯的上行按钮") ?? false)
    }

    func testMicroFollowUpKeepsCurrentGuidanceMode() throws {
        let ai = FakeAIClient(settings: dashScopeSettings())
        ai.visionResponses.append(inquiryIntent(intent: "micro_nav", target: "电梯上行按钮", speech: "正在引导你靠近上行按钮。"))
        ai.visionResponses.append("""
        {
          "thinking":"用户在精确引导中追问当前位置关系",
          "speech":"不要只依赖颜色。你前面有个行李箱，向前一步摸到行李箱后，沿它底部向下摸。"
        }
        """)
        let processor = SilverCareProcessor(client: ai)

        _ = try processor.processTextInquiry(
            imageDataURL: "data:image/png;base64:test",
            transcript: "引导我按电梯上行按钮"
        )
        let followUp = try processor.processTextInquiry(
            imageDataURL: "data:image/png;base64:test2",
            transcript: "它是在绿色行李箱旁边吗"
        )

        XCTAssertEqual(processor.mode, .micro)
        XCTAssertEqual(followUp.first(type: "inquiry_result")?.string("mode"), "micro")
        XCTAssertTrue(ai.lastVisionPrompt.contains("Current precision target"))
        XCTAssertTrue(ai.lastVisionPrompt.contains("Important control rule"))
        XCTAssertTrue(ai.lastVisionPrompt.contains("Do not say vague visual-only phrases"))
        XCTAssertTrue(ai.lastVisionPrompt.contains("Convert visual anchors into tactile steps"))
        XCTAssertTrue(followUp.first(type: "speak")?.string("text").contains("向前一步摸到行李箱") ?? false)
    }

    func testExplicitGuidanceStartsMicroModeAndCloseKeywordStopsIt() throws {
        let ai = FakeAIClient(settings: dashScopeSettings())
        ai.visionResponses.append(inquiryIntent(intent: "micro_nav", target: "电梯上行按钮", speech: "正在引导你靠近上行按钮。"))
        let processor = SilverCareProcessor(client: ai)

        let start = try processor.processTextInquiry(
            imageDataURL: "data:image/png;base64,test",
            transcript: "引导我按电梯上行按钮"
        )
        XCTAssertEqual(processor.mode, .micro)
        XCTAssertEqual(processor.microTarget, "电梯上行按钮")
        XCTAssertTrue(start.first(type: "speak")?.string("text").contains("正在引导你靠近电梯上行按钮") ?? false)

        let close = try processor.processTextInquiry(
            imageDataURL: "data:image/png;base64,test",
            transcript: "关闭引导"
        )
        XCTAssertEqual(processor.mode, .navigation)
        XCTAssertNil(processor.microTarget)
        XCTAssertEqual(close.first(type: "speak")?.string("text"), "已关闭精确引导。")
    }

    func testTaskInquiryCreatesTaskPlanAndAnnouncesFirstStep() throws {
        let ai = FakeAIClient(settings: dashScopeSettings())
        ai.visionResponses.append(inquiryIntent(intent: "task", taskName: "倒一杯水", speech: "我来指导你倒一杯水。"))
        ai.textResponses.append("""
        [
          {"step_id":1,"instruction":"找到杯子","items":["杯子"],"completed":false},
          {"step_id":2,"instruction":"把杯子放稳","items":["杯子"],"completed":false},
          {"step_id":3,"instruction":"倒入适量的水","items":["杯子","水"],"completed":false}
        ]
        """)
        let processor = SilverCareProcessor(client: ai)

        let messages = try processor.processTextInquiry(
            imageDataURL: "data:image/png;base64,test",
            transcript: "教我倒一杯水"
        )

        XCTAssertEqual(processor.mode, .task)
        XCTAssertTrue(messages.first(type: "speak")?.string("text").contains("第一步：找到杯子") ?? false)
        XCTAssertEqual(messages.first(type: "task_update")?.string("mode"), "task")
        XCTAssertEqual(messages.first(type: "task_update")?.int("current_step_index"), 0)
    }

    func testTranscriptFallbackTaskDoneOverridesSmallModelMicroNavMistake() throws {
        var settings = SilverCareSettings()
        settings.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
        let ai = FakeAIClient(settings: settings)
        ai.textResponses.append(inquiryIntent(intent: "task", taskName: "倒一杯水", speech: "我来指导你倒一杯水。"))
        ai.textResponses.append("""
        [
          {"step_id":1,"instruction":"找到杯子","items":["杯子"],"completed":false},
          {"step_id":2,"instruction":"把杯口对准出水口","items":["杯子"],"completed":false}
        ]
        """)
        let processor = SilverCareProcessor(client: ai)

        _ = try processor.processTextInquiry(
            imageDataURL: "data:image/png;base64:test",
            transcript: "教我倒一杯水"
        )
        let done = try processor.processTextInquiry(
            imageDataURL: "data:image/png;base64:test",
            transcript: "这一步完成了"
        )

        XCTAssertEqual(processor.mode, .task)
        XCTAssertEqual(done.last(type: "task_update")?.int("current_step_index"), 1)
        XCTAssertTrue(done.first(type: "speak")?.string("text").contains("下一步：把杯口对准出水口") ?? false)
    }

    func testSmartRefreshSkipsSemanticallyConsistentNavigationText() throws {
        var settings = SilverCareSettings()
        settings.smartNavigationRefreshEnabled = true
        let ai = FakeAIClient(settings: settings)
        ai.visionResponses.append("""
        {
          "priority":"medium",
          "category":"navigation",
          "subject":"门",
          "distance":0.75,
          "direction":"ahead",
          "speech":"前方有门",
          "scene_description":"走廊尽头有门"
        }
        """)
        ai.visionResponses.append("""
        {
          "priority":"medium",
          "category":"navigation",
          "subject":"门",
          "distance":0.80,
          "direction":"ahead",
          "speech":"正前方仍然是门",
          "scene_description":"走廊尽头仍然有门"
        }
        """)
        ai.textResponses.append(#"{"consistent":true,"reason":"行动建议未变化"}"#)
        let processor = SilverCareProcessor(client: ai)

        let first = try processor.processFrame("frame1")
        let second = try processor.processFrame("frame2")

        XCTAssertNotNil(first.first(type: "result"))
        XCTAssertNotNil(second.first(type: "smart_refresh_skipped"))
        XCTAssertTrue(ai.lastTextPrompt.contains("导航刷新判定器"))
        XCTAssertTrue(ai.lastTextPrompt.contains("一致的定义"))
        XCTAssertTrue(ai.lastTextPrompt.contains("不一致的定义"))
        XCTAssertTrue(ai.lastTextPrompt.contains("只输出 JSON，不要 Markdown，不要解释"))
    }
}

private func dashScopeSettings() -> SilverCareSettings {
    SilverCareSettings(
        aiRuntimeMode: SilverCareRuntimeMode.dashScope.rawValue,
        visionModel: "qwen3-vl-flash",
        microModel: "qwen3-vl-flash",
        textModel: "qwen-plus"
    )
}

private func inquiryIntent(
    intent: String,
    searchTarget: String? = nil,
    target: String? = nil,
    taskName: String? = nil,
    speech: String
) -> String {
    let object: [String: Any] = [
        "thinking": "测试路由",
        "intent": intent,
        "search_target": searchTarget ?? NSNull(),
        "target": target ?? NSNull(),
        "task_name": taskName ?? NSNull(),
        "speech": speech
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
}

private func navigationResponse(subject: String, speech: String) -> String {
    """
    {
      "thinking":"根据当前画面继续寻找目标",
      "priority":"high",
      "category":"target",
      "subject":"\(subject)",
      "distance":1.2,
      "direction":"left",
      "target_detected":true,
      "speech":"\(speech)",
      "scene_description":"目标已经出现在画面中",
      "objects":[{"name":"\(subject)","distance":1.2,"direction":"left"}]
    }
    """
}
