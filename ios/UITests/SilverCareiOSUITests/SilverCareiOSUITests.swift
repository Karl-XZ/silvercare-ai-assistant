import XCTest

final class SilverCareiOSUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--silvercare-simulator-automation")
        if let dashScopeKey = ProcessInfo.processInfo.environment["DASHSCOPE_API_KEY"], !dashScopeKey.isEmpty {
            app.launchEnvironment["DASHSCOPE_API_KEY"] = dashScopeKey
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testHomeScreenLoadsFromBundledWebAssets() throws {
        launchApp()

        waitForAutomationTokens([
            "brand",
            "home-view",
            "start-nav",
            "hold-inquiry",
            "show-details",
            "tts-runtime-visible",
            "home-controls-hittable",
            "caption-layout-ok",
            "main-feedback-layout-ok",
            "feedback-tts-clean",
            "main-feedback-tts-clean",
            "user-caption-tts-clean",
            "ai-caption-tts-clean"
        ], timeout: 20)
        XCTAssertTrue(
            waitForAnyAutomationToken(["ai-dashscope", "ai-offline"], timeout: 5),
            "No AI runtime mode surfaced. Current state: \(automationState().label)"
        )
        XCTAssertTrue(
            waitForAnyAutomationToken(["asr-dashscope", "asr-local"], timeout: 5),
            "No ASR runtime mode surfaced. Current state: \(automationState().label)"
        )
        XCTAssertTrue(
            waitForAnyAutomationToken(["tts-auto", "tts-system", "tts-dashscope", "tts-local-mnn"], timeout: 5),
            "No TTS runtime mode surfaced. Current state: \(automationState().label)"
        )
    }

    func testStartNavigationButtonTriggersNativeCameraFlow() throws {
        launchApp()

        waitForAutomationTokens(["home-view", "start-nav", "hit-toggle"], timeout: 20)
        let hadNativeCameraBridge = automationState().label.contains("camera-bridge-available")
        tap("启动或停止导航", fallback: "启动导航")

        let expectedTokens = hadNativeCameraBridge
            ? ["camera-native-running", "camera-native-error", "camera-native-warming", "stop-nav", "status-navigation-active"]
            : ["status-camera-error", "status-camera-starting", "camera-native-stopped"]
        XCTAssertTrue(
            waitForAnyAutomationToken(expectedTokens, timeout: 10),
            "Start navigation did not update expected camera/status state. Expected \(expectedTokens), current state: \(automationState().label)"
        )
        XCTAssertFalse(
            automationState().label.contains("status-camera-error") && automationState().label.contains("启动相机"),
            "Camera flow got stuck between starting and error states. Current state: \(automationState().label)"
        )
        if hadNativeCameraBridge {
            XCTAssertTrue(
                waitForAnyAutomationToken(["native-frame-in-flight", "native-frame-returned-recent", "camera-native-warming", "camera-native-frame_error"], timeout: 10),
                "Native camera flow did not enter a frame-processing lifecycle. Current state: \(automationState().label)"
            )
            if automationState().label.contains("camera-native-running") {
                waitForAutomationTokens(["camera-preview-visible", "camera-native-preview-running"], timeout: 5)
            }
        }

        if automationState().label.contains("stop-nav") {
            tap("启动或停止导航", fallback: "停止导航")
            waitForAutomationTokens(["start-nav"], timeout: 8)
        }
    }

    func testHomeControlsStayTappableAfterFeedbackAndPanelRoundTrip() throws {
        launchApp()

        waitForAutomationTokens([
            "home-view",
            "home-controls-hittable",
            "caption-layout-ok",
            "main-feedback-layout-ok"
        ], timeout: 20)

        press("按住提问", duration: 0.8)
        XCTAssertTrue(
            waitForAnyAutomationToken(["main-feedback-visible", "seen-inquiry-needs-navigation"], timeout: 4),
            "Inquiry feedback did not become visible. Current state: \(automationState().label)"
        )
        waitForAutomationTokens([
            "main-feedback-layout-ok",
            "home-controls-hittable",
            "caption-layout-ok"
        ], timeout: 6)

        tap("显示或隐藏 AI 详情", fallback: "查看详情")
        waitForAutomationTokens(["details-open", "hit-close-details"], timeout: 8)
        tap("关闭 AI 详情")
        waitForAutomationTokens([
            "details-closed",
            "home-controls-hittable",
            "caption-layout-ok",
            "main-feedback-layout-ok"
        ], timeout: 8)

        tap("打开长护管理端")
        waitForAutomationTokens(["management-open", "management-title"], timeout: 12)
        tap("返回老人端")
        waitForAutomationTokens([
            "home-view",
            "home-controls-hittable",
            "caption-layout-ok",
            "main-feedback-layout-ok"
        ], timeout: 12)
    }

    func testHoldInquiryButtonReportsBlockedOrSpeechBridgeStates() throws {
        launchApp()

        waitForAutomationTokens(["home-view", "hit-inquiry", "inquiry-ready"], timeout: 20)
        press("按住提问", duration: 1.0)
        waitForAutomationTokens(["seen-inquiry-needs-navigation", "inquiry-ready", "caption-layout-ok", "feedback-tts-clean"], timeout: 8)

        let hadNativeCameraBridge = automationState().label.contains("camera-bridge-available")
        tap("启动或停止导航", fallback: "启动导航")
        let expectedCameraTokens = hadNativeCameraBridge
            ? ["camera-native-running", "camera-native-error", "camera-native-warming", "stop-nav", "status-navigation-active"]
            : ["status-camera-error", "status-camera-starting", "camera-native-stopped"]
        XCTAssertTrue(
            waitForAnyAutomationToken(expectedCameraTokens, timeout: 10),
            "Start navigation did not update expected camera/status state before inquiry. Current state: \(automationState().label)"
        )

        guard waitForAnyAutomationToken(["stop-nav", "status-navigation-active", "camera-native-running"], timeout: 3) else {
            waitForAutomationTokens(["inquiry-ready", "caption-layout-ok", "feedback-tts-clean"], timeout: 8)
            return
        }

        press("按住提问", duration: 1.2)
        XCTAssertTrue(
            waitForAnyAutomationToken(["seen-inquiry-recording", "seen-speech-listening"], timeout: 10),
            "Long-press inquiry never entered a listening/recording state. Current state: \(automationState().label)"
        )
        XCTAssertTrue(
            waitForAnyAutomationToken(["seen-speech-submitted", "seen-speech-terminal"], timeout: 15),
            "Releasing inquiry did not submit speech or surface a terminal speech state. Current state: \(automationState().label)"
        )
        waitForAutomationTokens(["inquiry-ready", "caption-layout-ok", "feedback-tts-clean"], timeout: 8)

        if automationState().label.contains("stop-nav") {
            tap("启动或停止导航", fallback: "停止导航")
            waitForAutomationTokens(["start-nav"], timeout: 8)
        }
    }

    func testAIDetailsPanelCanOpenAndClose() throws {
        launchApp()

        waitForAutomationTokens(["hit-details"], timeout: 20)
        tap("显示或隐藏 AI 详情", fallback: "查看详情")
        waitForAutomationTokens(["details-open", "ai-reasoning", "ai-objects"], timeout: 8)
        waitForAutomationTokens(["hit-close-details"], timeout: 8)

        tap("关闭 AI 详情")
        waitForAutomationTokens(["details-closed", "show-details", "home-controls-hittable"], timeout: 8)
    }

    func testCareManagementDashboardRoundTrip() throws {
        launchApp()

        waitForAutomationTokens(["hit-management"], timeout: 20)
        tap("打开长护管理端")
        waitForAutomationTokens(["management-open", "management-title", "risk-queue", "residents", "care-agent"], timeout: 12)

        tap("返回老人端")
        waitForAutomationTokens(["home-view", "details-closed", "show-details"], timeout: 12)
    }

    func testNativeSettingsSheetIsReachableFromWebBridge() throws {
        launchApp()

        waitForAutomationTokens(["hit-settings"], timeout: 20)
        openSettingsSheet()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.buttons["切换运行方案"].exists)
        XCTAssertTrue(sheet.buttons["全部切换为本地"].exists)
        XCTAssertTrue(sheet.buttons["全部切换为云端 DashScope"].exists)
        XCTAssertTrue(sheet.buttons["离线文本模型"].exists)
        XCTAssertTrue(sheet.buttons["语音识别方案"].exists)
        XCTAssertTrue(sheet.buttons["朗读方案"].exists)
        XCTAssertTrue(sheet.buttons["检查本地离线模型"].exists)
        XCTAssertTrue(sheet.buttons["本地模型诊断"].exists)
    }

    func testNativeSettingsSubflowsAreActuallyTappable() throws {
        launchApp()

        assertSettingsAction("切换运行方案", opens: "端侧离线 MNN", dismiss: "取消")
        assertSettingsAction("全部切换为本地", opensAny: ["只切换", "切换为本地"], dismiss: "取消")
        assertSettingsAction("DashScope 区域/模型", opens: "保存", dismiss: "取消")
        assertSettingsAction("离线文本模型", opens: "Qwen3-4B-Instruct-2507-MNN", dismiss: "取消")
        assertSettingsAction("语音识别方案", opens: "本地内置 ASR", dismiss: "取消")
        assertSettingsAction("朗读方案", opens: "手机系统 TTS", dismiss: "取消")
        assertSettingsAction("检查本地离线模型", opens: "自动准备模型", dismiss: "关闭")
        assertSettingsAction("语音/字幕/跌倒", opens: "测试朗读", dismiss: "取消")
        assertSettingsAction("导航刷新模式", opens: "手动刷新", dismiss: "取消")
        assertSettingsAction("SME2 性能调优", opens: "SME2 自动调优", dismiss: "取消")
        assertSettingsAction("本地模型诊断", opens: "发送状态到页面", dismiss: "关闭", timeout: 12)
    }

    func testNativeSettingsRuntimeModeChangesPersistAfterRelaunch() throws {
        launchApp()
        waitForAutomationTokens(["hit-settings"], timeout: 20)

        openSettingsSheet()
        tap("全部切换为云端 DashScope")
        waitForAutomationTokens(["ai-dashscope", "asr-dashscope", "tts-dashscope"], timeout: 12)

        relaunchApp()
        waitForAutomationTokens(["ai-dashscope", "asr-dashscope", "tts-dashscope"], timeout: 20)

        openSettingsSheet()
        tap("全部切换为本地")
        tapAny(["只切换", "切换为本地"], timeout: 10)
        waitForAutomationTokens(["ai-offline", "asr-local", "tts-system"], timeout: 12)

        relaunchApp()
        waitForAutomationTokens(["ai-offline", "asr-local", "tts-system"], timeout: 20)
    }

    private func launchApp() {
        app.launch()
        _ = app.webViews.firstMatch.waitForExistence(timeout: 20)
        _ = automationState().waitForExistence(timeout: 10)
    }

    private func find(_ text: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func findTappable(_ text: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let candidates = [
            app.buttons.matching(predicate).firstMatch,
            app.switches.matching(predicate).firstMatch,
            app.cells.matching(predicate).firstMatch,
            app.otherElements.matching(predicate).firstMatch
        ]
        return candidates.first { candidate in
            candidate.waitForExistence(timeout: 1) && candidate.isHittable
        } ?? candidates.first ?? find(text)
    }

    private func tap(_ text: String, fallback: String? = nil) {
        let primary = findTappable(text)
        if primary.waitForExistence(timeout: 8) {
            primary.tap()
            return
        }
        if let fallback {
            let fallbackElement = findTappable(fallback)
            XCTAssertTrue(fallbackElement.waitForExistence(timeout: 8), "Could not find \(text) or \(fallback)")
            fallbackElement.tap()
            return
        }
        XCTFail("Could not find \(text)")
    }

    private func press(_ text: String, duration: TimeInterval) {
        let element = findTappable(text)
        XCTAssertTrue(element.waitForExistence(timeout: 8), "Could not find \(text)")
        element.press(forDuration: duration)
    }

    private func tapAny(_ texts: [String], timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for text in texts {
                let element = findTappable(text)
                if element.exists && element.isHittable {
                    element.tap()
                    return
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("Could not find any of \(texts.joined(separator: ", "))")
    }

    private func openSettingsSheet() {
        tap("打开 AI 运行方案和设置")
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        XCTAssertTrue(sheet.staticTexts["银龄智护 iOS 设置"].exists)
    }

    private func assertSettingsAction(
        _ action: String,
        opens text: String,
        dismiss dismissLabel: String,
        timeout: TimeInterval = 8
    ) {
        assertSettingsAction(action, opensAny: [text], dismiss: dismissLabel, timeout: timeout)
    }

    private func assertSettingsAction(
        _ action: String,
        opensAny texts: [String],
        dismiss _: String,
        timeout: TimeInterval = 8
    ) {
        openSettingsSheet()
        tap(action)
        XCTAssertTrue(
            waitForAnyText(texts, timeout: timeout),
            "Tapping \(action) did not open any of \(texts)."
        )
        relaunchApp()
    }

    private func relaunchApp() {
        app.terminate()
        app.launch()
        _ = app.webViews.firstMatch.waitForExistence(timeout: 20)
        _ = automationState().waitForExistence(timeout: 10)
    }

    private func waitForAnyText(_ texts: [String], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if texts.contains(where: { find($0).exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return texts.contains(where: { find($0).exists })
    }

    private func automationState() -> XCUIElement {
        app.descendants(matching: .any)["SilverCareAutomationState"]
    }

    private func waitForAutomationTokens(
        _ tokens: [String],
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for token in tokens {
            XCTAssertTrue(
                waitForAutomationToken(token, timeout: timeout),
                "Missing automation token \(token). Current state: \(automationState().label)",
                file: file,
                line: line
            )
        }
    }

    private func waitForAutomationToken(_ token: String, timeout: TimeInterval) -> Bool {
        let element = automationState()
        guard element.waitForExistence(timeout: min(3, timeout)) else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.label.contains(token) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return element.label.contains(token)
    }

    private func waitForAnyAutomationToken(_ tokens: [String], timeout: TimeInterval) -> Bool {
        let element = automationState()
        guard element.waitForExistence(timeout: min(3, timeout)) else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let label = element.label
            if tokens.contains(where: { label.contains($0) }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        let label = element.label
        return tokens.contains(where: { label.contains($0) })
    }
}

final class SilverCareiOSDeviceDebugUITests: XCTestCase {
    func testOrdinaryDeviceLaunchScreenshotsAndSettingsTap() throws {
        let app = makeDeviceDebugApp()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        sleep(3)
        attachScreenshot(named: "01-ordinary-launch")

        let settings = find("打开 AI 运行方案和设置", in: app)
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.16)).tap()
        }
        sleep(2)
        attachScreenshot(named: "02-after-settings-tap")

        let sheet = app.sheets.firstMatch
        let title = find("银龄智护 iOS 设置", in: app)
        XCTAssertTrue(sheet.exists || title.exists, "Settings sheet did not appear after tapping the gear button.")
    }

    func testOrdinaryDeviceNativeControlsOpenPanels() throws {
        let app = makeDeviceDebugApp()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        sleep(3)
        attachScreenshot(named: "01-controls-home")

        tap("显示或隐藏 AI 详情", in: app, fallback: "查看详情")
        XCTAssertTrue(find("AI 详情", in: app).waitForExistence(timeout: 8))
        attachScreenshot(named: "02-after-details-tap")

        tap("关闭 AI 详情", in: app, fallback: "查看详情")
        sleep(1)

        tap("打开长护管理端", in: app)
        XCTAssertTrue(find("适老化居家长护服务管理端", in: app).waitForExistence(timeout: 8))
        attachScreenshot(named: "03-after-management-tap")

        tap("返回老人端", in: app)
        XCTAssertTrue(
            waitForAny(["查看详情", "显示或隐藏 AI 详情"], in: app, timeout: 8),
            "Home controls did not reappear after returning from management."
        )
        attachScreenshot(named: "04-after-return-tap")
    }

    func testOrdinaryDeviceStartNavigationEntersNativeCameraFlow() throws {
        let app = makeDeviceDebugApp()
        addPermissionInterruptionMonitor()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(automationState(in: app).waitForExistence(timeout: 20))
        sleep(3)
        attachScreenshot(named: "01-before-start-navigation")

        tap("启动或停止导航", in: app, fallback: "启动导航")
        XCTAssertTrue(
            waitForAnyAutomationToken([
                "camera-native-running",
                "camera-native-warming",
                "camera-native-error",
                "status-navigation-active"
            ], in: app, timeout: 12),
            "Tapping start navigation did not enter the native camera flow. Current state: \(automationState(in: app).label)"
        )
        attachScreenshot(named: "02-after-start-navigation")

        if automationState(in: app).label.contains("camera-native-running") {
            XCTAssertTrue(
                waitForAnyAutomationToken(["camera-preview-visible", "camera-native-preview-running"], in: app, timeout: 5),
                "Native camera reported running but no visible preview token appeared. Current state: \(automationState(in: app).label)"
            )
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.45)).tap()
            attachScreenshot(named: "03-after-manual-refresh-tap")
            XCTAssertTrue(
                waitForAnyAutomationToken(["navigation-result-recent"], in: app, timeout: 45),
                "Native camera ran, but no parsed navigation result reached the UI. Current state: \(automationState(in: app).label)"
            )
            XCTAssertFalse(
                automationState(in: app).label.contains("json-parse-error-visible"),
                "A raw JSON parsing error is visible in the navigation UI. Current state: \(automationState(in: app).label)"
            )
            attachScreenshot(named: "04-after-navigation-result")
        }

        if automationState(in: app).label.contains("stop-nav") {
            tap("启动或停止导航", in: app, fallback: "停止导航")
        }
    }

    private func makeDeviceDebugApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--silvercare-simulator-automation")
        app.launchEnvironment["SILVERCARE_IOS_FORCE_DASHSCOPE_RUNTIME"] = "1"
        return app
    }

    private func find(_ text: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func findTappable(_ text: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let candidates = [
            app.buttons[text],
            app.switches[text],
            app.cells[text],
            app.otherElements[text],
            app.buttons.matching(predicate).firstMatch,
            app.switches.matching(predicate).firstMatch,
            app.cells.matching(predicate).firstMatch,
            app.otherElements.matching(predicate).firstMatch
        ]
        return candidates.first { candidate in
            candidate.waitForExistence(timeout: 1) && candidate.isHittable
        } ?? candidates.first { candidate in
            candidate.exists
        } ?? find(text, in: app)
    }

    private func waitForAny(_ texts: [String], in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if texts.contains(where: { find($0, in: app).exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return texts.contains(where: { find($0, in: app).exists })
    }

    private func automationState(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["SilverCareAutomationState"]
    }

    private func waitForAnyAutomationToken(
        _ tokens: [String],
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let element = automationState(in: app)
        guard element.waitForExistence(timeout: min(3, timeout)) else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let label = element.label
            if tokens.contains(where: { label.contains($0) }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        let label = element.label
        return tokens.contains(where: { label.contains($0) })
    }

    private func tap(_ label: String, in app: XCUIApplication, fallback: String? = nil) {
        let primary = findTappable(label, in: app)
        if primary.waitForExistence(timeout: 8), primary.isHittable {
            primary.tap()
            return
        }
        if let fallback {
            let fallbackElement = findTappable(fallback, in: app)
            XCTAssertTrue(
                fallbackElement.waitForExistence(timeout: 8) && fallbackElement.isHittable,
                "Could not find a hittable control for \(label) or \(fallback)"
            )
            fallbackElement.tap()
            return
        }
        XCTAssertTrue(
            primary.waitForExistence(timeout: 8) && primary.isHittable,
            "Could not find a hittable control for \(label)"
        )
        primary.tap()
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func addPermissionInterruptionMonitor() {
        addUIInterruptionMonitor(withDescription: "Camera or microphone permission") { alert in
            for label in ["允许", "Allow", "好", "OK", "继续"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
    }
}
