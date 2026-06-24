import AVFoundation
import Foundation
import SilverCareCore
import SwiftUI
import UIKit
import WebKit

final class RuntimeStatusSnapshotStore: @unchecked Sendable {
    private let lock = NSLock()
    private var value: SilverCareRuntimeStatus

    init(status: SilverCareRuntimeStatus) {
        value = status
    }

    func update(_ status: SilverCareRuntimeStatus) {
        lock.lock()
        value = status
        lock.unlock()
    }

    func status() -> SilverCareRuntimeStatus {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@MainActor
final class SilverCareAppModel: ObservableObject {
    @Published private(set) var runtimeStatus: SilverCareRuntimeStatus {
        didSet {
            runtimeStatusSnapshot.update(runtimeStatus)
        }
    }
    @Published private(set) var automationSnapshot = "SilverCareAutomation: boot"
    @Published private(set) var cameraPreviewVisible = false
    @Published private(set) var latestLocalBenchmarkPath = ""
    @Published private(set) var latestCameraStatus = "idle"
    @Published private(set) var latestCameraStatusText = "摄像头未启动"
    @Published private(set) var latestCameraErrorCode = ""

    weak var webView: WKWebView?

    let cameraService = NativeCameraService()
    private let runtimeStatusSnapshot: RuntimeStatusSnapshotStore
    private let ttsService = SystemSpeechService()
    private let dashScopeAudioRecorder = PCM16AudioRecorderService()
    private let localASRAudioRecorder = PCM16AudioRecorderService()
    private let localVoskRuntime = LocalVoskASRRuntime()
    private let motionFallMonitor = MotionFallMonitorService()
    private let diagnosticLogger = IOSDiagnosticLogger()
    private let offlineModelManager = OfflineModelManager()
    private let localASRModelManager = LocalASRModelManager()
    private let localTTSModelManager = LocalTTSModelManager()
    private let localTTSRuntime = DynamicIOSMNNTTSRuntime()
    private var dashScopeSpeechPlayer: AVPlayer?
    private var dashScopeSpeechObserver: NSObjectProtocol?
    private var dashScopeSpeechFailureObserver: NSObjectProtocol?
    private var dashScopeSpeechStatusObservation: NSKeyValueObservation?
    private lazy var localModelRuntime = DynamicIOSMNNLocalModelRuntime(statusProvider: { [runtimeStatusSnapshot] in
        runtimeStatusSnapshot.status()
    })
    private lazy var aiClient = IOSHybridAIClient(statusProvider: { [runtimeStatusSnapshot] in
        runtimeStatusSnapshot.status()
    }, diagnosticLogger: diagnosticLogger, localRuntime: localModelRuntime)
    private lazy var processorPipeline = SilverCareProcessorPipeline(client: aiClient)
    private var offlineDownloadInFlight = false
    private var nativeFrameProcessing = false
    private var pendingSpeechImageDataURL = ""
    private var nativeFallAlert: UIAlertController?
    private var nativeFallCountdownTimer: Timer?
    private var nativeFallCountdownLeft = 10
    private var nativeFallEvidenceJSON = "{}"
    var automationEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--silvercare-simulator-automation")
    }

    init() {
        let status = SilverCareRuntimeStatus.load()
        runtimeStatus = status
        runtimeStatusSnapshot = RuntimeStatusSnapshotStore(status: status)
    }

    func requestStartupPermissions() async {
        refreshSpeechRuntimeStatus()
        refreshTTSRuntimeStatus()
        refreshOfflineModelStatus()
        publishRuntimeStatus()
        startNativeFallMonitoringIfNeeded()
    }

    func prepareForAutomation() {
        automationSnapshot = "SilverCareAutomation: preparing"
        refreshSpeechRuntimeStatus()
        refreshTTSRuntimeStatus()
        motionFallMonitor.stop()
        refreshOfflineModelStatus()
        publishRuntimeStatus()
    }

    func runAutomationLocalBenchmarksIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--silvercare-run-local-benchmarks") else { return }
        let tests = automationLocalBenchmarkTests(arguments: arguments)
        automationSnapshot = "SilverCareAutomation: local-benchmark-start"
        prepareAutomationLocalBenchmarkSeedIfAvailable()
        for test in tests {
            await runLocalModelBenchmark(test: test, presentReport: false, speakResult: false)
        }
        automationSnapshot = "SilverCareAutomation: local-benchmark-finished"
    }

    func attach(webView: WKWebView) {
        self.webView = webView
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.publishRuntimeStatus()
            if !ProcessInfo.processInfo.arguments.contains("--silvercare-simulator-automation") {
                self.startNativeFallMonitoringIfNeeded()
            }
        }
    }

    func runtimeBootstrapScript() -> String {
        let json = runtimeBridgeJSON()
        return SilverCareBridgeScript.make(runtimeJSON: json)
    }

    private func runtimeBridgeJSON() -> String {
        let payload: [String: Any] = [
            "aiRuntimeMode": runtimeStatus.aiRuntimeMode,
            "runtimeDisplayName": runtimeStatus.runtimeDisplayName,
            "hasDashScopeKey": runtimeStatus.hasDashScopeKey,
            "diagnosticLogPath": diagnosticLogger.latestLogPath,
            "offlineModelReady": runtimeStatus.offlineReady,
            "offlineStatusText": runtimeStatus.offlineStatusText,
            "offlineModelDirectory": runtimeStatus.offlineModelDirectory,
            "offlineMissing": runtimeStatus.offlineMissing,
            "offlineDirectoryReadable": runtimeStatus.offlineDirectoryReadable,
            "offlineTextModelReady": runtimeStatus.offlineTextReady,
            "offlineYoloModelReady": runtimeStatus.offlineYoloReady,
            "offlineNativeRuntimeAvailable": runtimeStatus.offlineNativeRuntimeAvailable,
            "compatibleBaseURL": runtimeStatus.compatibleBaseURL,
            "apiBaseURL": runtimeStatus.apiBaseURL,
            "visionModel": runtimeStatus.visionModel,
            "textModel": runtimeStatus.textModel,
            "offlineTextModel": runtimeStatus.offlineTextModel,
            "offlineTextModelLabel": runtimeStatus.offlineTextModelLabel,
            "microModel": runtimeStatus.microModel,
            "asrRuntimeMode": runtimeStatus.asrRuntimeMode,
            "asrRuntimeDisplayName": runtimeStatus.asrRuntimeDisplayName,
            "asrModel": runtimeStatus.asrModel,
            "localAsrReady": runtimeStatus.localAsrReady,
            "localAsrStatusText": runtimeStatus.localAsrStatusText,
            "localAsrModelDirectory": runtimeStatus.localAsrModelDirectory,
            "localAsrMissing": runtimeStatus.localAsrMissing,
            "localAsrModelReady": runtimeStatus.localAsrModelReady,
            "localAsrRuntimeAvailable": runtimeStatus.localAsrRuntimeAvailable,
            "ttsRuntimeMode": runtimeStatus.ttsRuntimeMode,
            "ttsRuntimeDisplayName": runtimeStatus.ttsRuntimeDisplayName,
            "ttsStatusText": runtimeStatus.ttsStatusText,
            "localTtsReady": runtimeStatus.localTtsReady,
            "localTtsStatusText": runtimeStatus.localTtsStatusText,
            "localTtsModelDirectory": runtimeStatus.localTtsModelDirectory,
            "localTtsMissing": runtimeStatus.localTtsMissing,
            "localTtsModelReady": runtimeStatus.localTtsModelReady,
            "localTtsRuntimeAvailable": runtimeStatus.localTtsRuntimeAvailable,
            "localTtsVoiceQualityPassed": runtimeStatus.localTtsVoiceQualityPassed,
            "captionsEnabled": runtimeStatus.captionsEnabled,
            "voiceFirstEnabled": runtimeStatus.voiceFirstEnabled,
            "fallDetectionEnabled": runtimeStatus.fallDetectionEnabled,
            "navigationRefreshMode": runtimeStatus.navigationRefreshMode,
            "navigationRefreshIntervalMs": runtimeStatus.navigationRefreshIntervalMs,
            "smartNavigationRefreshEnabled": runtimeStatus.smartNavigationRefreshEnabled,
            "mnnLlmTuningMode": runtimeStatus.mnnLlmTuningMode,
            "mnnLlmTuningDisplayName": runtimeStatus.mnnLlmTuningDisplayName,
            "mnnSme2Supported": localModelRuntime.supportsSme2,
            "mnnRuntimeSummary": localModelRuntime.runtimeSummary,
            "localBenchmarkPath": latestLocalBenchmarkPath,
            "nativeCameraAvailable": cameraService.canStartCamera,
            "nativeCameraRunning": cameraService.isRunning,
            "nativeCameraPreviewVisible": cameraPreviewVisible,
            "nativeCameraStatus": latestCameraStatus,
            "nativeCameraStatusText": latestCameraStatusText,
            "nativeCameraErrorCode": latestCameraErrorCode,
            "nativeCameraAuthorizationStatus": cameraService.authorizationStatusLabel,
            "nativeCameraHardwareAvailable": cameraService.hardwareAvailable
        ]
        let jsonData = try? JSONSerialization.data(withJSONObject: payload)
        return jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    func handleBridgeMessage(_ message: [String: Any]) {
        guard let method = message["method"] as? String else { return }
        let args = message["args"] as? [Any] ?? []
        Task { @MainActor in
            do {
                try await route(method: method, args: args)
            } catch {
                sendToWeb(type: "error", payload: ["text": error.localizedDescription])
                if method == "startSpeechInquiry" || method == "stopSpeechInquiry" {
                    finishNativeSpeechUI()
                }
            }
        }
    }

    func handleAutomationSnapshot(_ snapshot: [String: Any]) {
        guard automationEnabled else { return }
        let view = snapshot["view"] as? String ?? "unknown"
        let tokens = (snapshot["tokens"] as? [Any] ?? [])
            .compactMap { $0 as? String }
            .sorted()
            .joined(separator: ",")
        automationSnapshot = "SilverCareAutomation view=\(view) tokens=\(tokens)"
    }

    func presentSettingsFromFallback() {
        presentSettings()
    }

    func closeManagementFromFallback() {
        runWebUIAction("close-management")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.webView?.reload()
        }
    }

    func runWebUIAction(_ action: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: [action]),
              let arrayJSON = String(data: data, encoding: .utf8),
              arrayJSON.count >= 2
        else { return }
        let json = String(arrayJSON.dropFirst().dropLast())
        evaluate("""
        (function(action) {
          function click(id) {
            var element = document.getElementById(id);
            if (!element) return false;
            element.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
            return true;
          }

          if (action === 'details') {
            var layer = document.getElementById('intelligence-layer');
            if (!layer) return;
            var visible = !layer.classList.contains('visible');
            layer.classList.toggle('visible', visible);
            layer.setAttribute('aria-hidden', String(!visible));
            var button = document.getElementById('detailsCommand');
            if (button) {
              button.classList.toggle('is-active', visible);
              button.setAttribute('aria-pressed', String(visible));
              var label = button.querySelector('span');
              if (label) label.textContent = visible ? '隐藏详情' : '查看详情';
            }
            return;
          }

          if (action === 'management') {
            var intel = document.getElementById('intelligence-layer');
            if (intel) {
              intel.classList.remove('visible');
              intel.setAttribute('aria-hidden', 'true');
            }
            var detailsButton = document.getElementById('detailsCommand');
            if (detailsButton) {
              detailsButton.classList.remove('is-active');
              detailsButton.setAttribute('aria-pressed', 'false');
              var detailsLabel = detailsButton.querySelector('span');
              if (detailsLabel) detailsLabel.textContent = '查看详情';
            }
            var dashboard = document.getElementById('careDashboard');
            if (dashboard) {
              dashboard.classList.add('visible');
              dashboard.setAttribute('aria-hidden', 'false');
            }
            if (window.SILVERCARE_MANAGEMENT_DASHBOARD && typeof window.SILVERCARE_MANAGEMENT_DASHBOARD.open === 'function') {
              try {
                window.SILVERCARE_MANAGEMENT_DASHBOARD.open();
                return;
              } catch (error) {
                console.error('Native management fallback open failed:', error);
              }
            }
            if (click('managementCommand')) return;
            if (dashboard) {
              dashboard.classList.add('visible');
              dashboard.setAttribute('aria-hidden', 'false');
            }
            return;
          }

          if (action === 'close-management') {
            if (window.SILVERCARE_MANAGEMENT_DASHBOARD && typeof window.SILVERCARE_MANAGEMENT_DASHBOARD.close === 'function') {
              window.SILVERCARE_MANAGEMENT_DASHBOARD.close();
              return;
            }
            if (click('careCloseButton')) return;
            var dashboard = document.getElementById('careDashboard');
            if (dashboard) {
              dashboard.classList.remove('visible');
              dashboard.setAttribute('aria-hidden', 'true');
            }
            return;
          }

          if (typeof window.SILVERCARE_UI_ACTION === 'function') {
            window.SILVERCARE_UI_ACTION(action);
            return;
          }

          if (action === 'toggle') click('toggleCommand');
          if (action === 'inquiry-start') click('inquiryCommand');
        })(\(json));
        """)
    }

    private func route(method: String, args: [Any]) async throws {
        switch method {
        case "startCamera":
            await startCamera()
        case "stopCamera":
            await stopCamera()
        case "captureFrame":
            captureNativeFrame()
        case "sendFrame":
            let image = args.first as? String ?? ""
            processFrameAsync(image, source: "sendFrame")
        case "sendInquiryData":
            let image = args.first as? String ?? ""
            let audio = args.dropFirst().first as? String ?? ""
            processInquiryAsync(imageDataURL: image, audioDataURL: audio)
        case "processTextInquiry":
            let image = args.first as? String ?? ""
            let transcript = args.dropFirst().first as? String ?? ""
            processTextInquiryAsync(imageDataURL: image, transcript: transcript)
        case "startSpeechInquiry":
            try await startSpeechInquiry(imageDataURL: args.first as? String ?? "")
        case "stopSpeechInquiry":
            stopSpeechInquiry()
        case "speak":
            let text = args.first as? String ?? ""
            speak(text)
        case "triggerFallAlarm":
            triggerFallAlarm(args.first as? String ?? "{}")
        case "diagnosticEvent":
            let event = args.first as? String ?? "js_event"
            let dataText = args.dropFirst().first as? String ?? "{}"
            diagnosticLogger.event("js_\(event)", dataJSON: dataText)
        case "openSettings":
            presentSettings()
        case "openRuntimeSettings":
            presentRuntimeModeSheet()
        case "openAsrSettings":
            presentAsrRuntimeSheet()
        case "openTtsSettings":
            presentTtsRuntimeSheet()
        case "switchAllLocal":
            presentAllLocalConfirmation()
        case "switchAllCloud":
            switchAllCloud()
        case "openKeySettings":
            presentDashScopeKeyPrompt()
        case "openOfflineModelSettings":
            presentOfflineModelStatus()
        case "prepareOfflineModels":
            await prepareOfflineModels()
        case "prepareLocalTtsModels":
            await prepareLocalTTSModels()
        case "runLocalBenchmark":
            await runLocalModelBenchmark(test: args.first as? String ?? "status")
        default:
            break
        }
    }

    private func emit(_ messages: [SilverCareMessage]) {
        for message in messages {
            if message.type == "speak" {
                speak(message.string("text"))
            } else {
                sendToWeb(type: message.type, payload: message.payload)
            }
        }
    }

    private func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isSpeechInquiryRecording else {
            diagnosticLogger.event("ios_tts_suppressed_during_recording", data: ["chars": text.count])
            return
        }
        sendToWeb(type: "speak", payload: ["text": text])
        let mode = SilverCareTTSRuntimeMode.from(runtimeStatus.ttsRuntimeMode)
        if mode == .dashScope {
            speakWithDashScope(text)
            return
        }
        if mode == .localMNN || (mode == .auto && runtimeStatus.localTtsReady) {
            speakWithLocalMNN(text)
            return
        }
        speakWithSystemTTS(text)
    }

    private func speakWithSystemTTS(_ text: String) {
        guard !isSpeechInquiryRecording else {
            diagnosticLogger.event("ios_system_tts_suppressed_during_recording", data: ["chars": text.count])
            return
        }
        ttsService.speak(text) { [weak self] speaking in
            Task { @MainActor in
                self?.evaluate("window.LONG_TERM_CARE_TTS_STATE_CHANGED?.(\(speaking ? "true" : "false"));")
            }
        }
    }

    private func speakWithDashScope(_ text: String) {
        guard runtimeStatus.hasDashScopeKey else {
            sendToWeb(type: "error", payload: ["text": "联网 DashScope TTS 需要先填写 DashScope Key。"])
            speakWithSystemTTS(text)
            return
        }
        let settings = aiClient.settings
        evaluate("window.LONG_TERM_CARE_TTS_STATE_CHANGED?.(true);")
        Task.detached {
            do {
                let urlString = try DashScopeAIClient(settings: settings).synthesizeSpeechURL(text: text)
                await MainActor.run { [weak self] in
                    self?.playDashScopeSpeech(urlString: urlString, fallbackText: text)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.evaluate("window.LONG_TERM_CARE_TTS_STATE_CHANGED?.(false);")
                    self?.sendToWeb(type: "error", payload: ["text": error.localizedDescription])
                    self?.speakWithSystemTTS(text)
                }
            }
        }
    }

    private func speakWithLocalMNN(_ text: String) {
        refreshTTSRuntimeStatus()
        guard runtimeStatus.localTtsReady else {
            sendToWeb(type: "error", payload: [
                "text": "\(runtimeStatus.localTtsStatusText)。已回退到 iOS 系统 TTS。"
            ])
            speakWithSystemTTS(text)
            return
        }
        let modelDirectory = URL(fileURLWithPath: runtimeStatus.localTtsModelDirectory, isDirectory: true)
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SilverCareLocalTTS", isDirectory: true)
        let runtime = localTTSRuntime
        evaluate("window.LONG_TERM_CARE_TTS_STATE_CHANGED?.(true);")
        Task.detached {
            do {
                let wav = try runtime.synthesizeToWav(
                    modelDirectory: modelDirectory,
                    cacheDirectory: cacheDirectory,
                    text: text,
                    language: "zh"
                )
                await MainActor.run { [weak self] in
                    self?.playLocalSpeech(url: wav, fallbackText: text)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.evaluate("window.LONG_TERM_CARE_TTS_STATE_CHANGED?.(false);")
                    self?.sendToWeb(type: "error", payload: ["text": error.localizedDescription])
                    self?.speakWithSystemTTS(text)
                }
            }
        }
    }

    private func playDashScopeSpeech(urlString: String, fallbackText: String) {
        guard !isSpeechInquiryRecording else {
            evaluate("window.LONG_TERM_CARE_TTS_STATE_CHANGED?.(false);")
            diagnosticLogger.event("ios_dashscope_tts_suppressed_during_recording", data: [:])
            return
        }
        guard let url = URL(string: urlString) else {
            evaluate("window.LONG_TERM_CARE_TTS_STATE_CHANGED?.(false);")
            sendToWeb(type: "error", payload: ["text": "DashScope TTS 返回了无效音频地址。"])
            speakWithSystemTTS(fallbackText)
            return
        }
        playSpeechAudio(url: url, source: "dashscope_tts", fallbackText: fallbackText)
    }

    private func playLocalSpeech(url: URL, fallbackText: String) {
        guard !isSpeechInquiryRecording else {
            evaluate("window.LONG_TERM_CARE_TTS_STATE_CHANGED?.(false);")
            diagnosticLogger.event("ios_local_tts_suppressed_during_recording", data: [:])
            return
        }
        playSpeechAudio(url: url, source: "local_mnn_tts", fallbackText: fallbackText)
    }

    private func playSpeechAudio(url: URL, source: String, fallbackText: String) {
        clearSpeechAudioPlayback()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])
        let item = AVPlayerItem(url: url)
        dashScopeSpeechPlayer = AVPlayer(playerItem: item)

        dashScopeSpeechObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.finishSpeechAudioPlayback(source: source)
            }
        }

        dashScopeSpeechFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor in
                self?.failSpeechAudioPlayback(
                    source: source,
                    fallbackText: fallbackText,
                    reason: error?.localizedDescription ?? "音频播放中断。"
                )
            }
        }

        dashScopeSpeechStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let reason = item.error?.localizedDescription ?? "音频加载失败。"
            Task { @MainActor in
                self?.failSpeechAudioPlayback(source: source, fallbackText: fallbackText, reason: reason)
            }
        }

        dashScopeSpeechPlayer?.play()
    }

    private func finishSpeechAudioPlayback(source: String) {
        guard dashScopeSpeechPlayer != nil else { return }
        evaluate("window.LONG_TERM_CARE_TTS_STATE_CHANGED?.(false);")
        diagnosticLogger.event("ios_tts_playback_finished", data: ["source": source])
        clearSpeechAudioPlayback()
        if !isSpeechInquiryRecording {
            deactivateSpeechAudioSession()
        }
    }

    private func failSpeechAudioPlayback(source: String, fallbackText: String, reason: String) {
        guard dashScopeSpeechPlayer != nil else { return }
        evaluate("window.LONG_TERM_CARE_TTS_STATE_CHANGED?.(false);")
        diagnosticLogger.event("ios_tts_playback_failed", data: [
            "source": source,
            "reason": reason
        ])
        if isSpeechInquiryRecording {
            diagnosticLogger.event("ios_tts_playback_failure_suppressed_during_recording", data: ["source": source])
            clearSpeechAudioPlayback()
            return
        }
        sendToWeb(type: "error", payload: [
            "text": "\(source == "dashscope_tts" ? "DashScope TTS" : "本地 MNN TTS") 播放失败，已回退到 iOS 系统 TTS：\(reason)"
        ])
        clearSpeechAudioPlayback()
        deactivateSpeechAudioSession()
        speakWithSystemTTS(fallbackText)
    }

    private func clearSpeechAudioPlayback() {
        if let observer = dashScopeSpeechObserver {
            NotificationCenter.default.removeObserver(observer)
            dashScopeSpeechObserver = nil
        }
        if let observer = dashScopeSpeechFailureObserver {
            NotificationCenter.default.removeObserver(observer)
            dashScopeSpeechFailureObserver = nil
        }
        dashScopeSpeechStatusObservation?.invalidate()
        dashScopeSpeechStatusObservation = nil
        dashScopeSpeechPlayer?.pause()
        dashScopeSpeechPlayer = nil
    }

    private var isSpeechInquiryRecording: Bool {
        dashScopeAudioRecorder.isRecording || localASRAudioRecorder.isRecording
    }

    private func prepareAudioSessionForSpeechRecording() {
        evaluate("window.LONG_TERM_CARE_TTS_STATE_CHANGED?.(false);")
        clearSpeechAudioPlayback()
        ttsService.cancelForRecording()
    }

    private func deactivateSpeechAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func triggerFallAlarm(_ evidenceJSON: String) {
        nativeFallCountdownTimer?.invalidate()
        nativeFallCountdownTimer = nil
        nativeFallAlert?.dismiss(animated: true)
        nativeFallAlert = nil
        diagnosticLogger.event("ios_fall_alarm", dataJSON: evidenceJSON)
        sendToWeb(type: "fall_alarm", payload: [
            "text": "已发送报警",
            "evidence": evidenceJSON
        ])
        speak("已发送报警。请照护者尽快复核。")
    }

    private func startSpeechInquiry(imageDataURL: String) async throws {
        guard !localASRAudioRecorder.isRecording && !dashScopeAudioRecorder.isRecording else {
            sendToWeb(type: "speech_busy", payload: ["text": "上一条语音还在处理，请稍等。"])
            diagnosticLogger.event("ios_speech_busy", data: [:])
            finishNativeSpeechUI()
            return
        }
        if SilverCareASRRuntimeMode.from(runtimeStatus.asrRuntimeMode) == .dashScope {
            try await startDashScopeSpeechInquiry(imageDataURL: imageDataURL)
            return
        }
        refreshSpeechRuntimeStatus()
        guard runtimeStatus.localAsrReady else {
            sendToWeb(type: "error", payload: ["text": runtimeStatus.localAsrStatusText])
            finishNativeSpeechUI()
            return
        }
        guard await ensureMicrophonePermissionOnly() else {
            throw PCM16AudioRecorderService.RecorderError.notAuthorized
        }
        let frame = try imageDataURL.isEmpty ? cameraService.captureFrameDataURL() : imageDataURL
        pendingSpeechImageDataURL = frame
        sendToWeb(type: "speech_status", payload: ["listening": true])
        diagnosticLogger.event("ios_local_asr_speech_start", data: [
            "image_chars": frame.count,
            "model_dir": runtimeStatus.localAsrModelDirectory
        ])
        prepareAudioSessionForSpeechRecording()
        try localASRAudioRecorder.start()
    }

    private func ensureMicrophonePermissionOnly() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    private func startDashScopeSpeechInquiry(imageDataURL: String) async throws {
        guard runtimeStatus.hasDashScopeKey else {
            throw SilverCareCoreError.missingCredential("联网 DashScope ASR 需要先在设置里填写 DashScope Key，或切换到本地内置 ASR。")
        }
        guard await ensureMicrophonePermissionOnly() else {
            throw PCM16AudioRecorderService.RecorderError.notAuthorized
        }
        let frame = try imageDataURL.isEmpty ? cameraService.captureFrameDataURL() : imageDataURL
        pendingSpeechImageDataURL = frame
        sendToWeb(type: "speech_status", payload: ["listening": true])
        diagnosticLogger.event("ios_dashscope_speech_start", data: ["image_chars": frame.count])
        prepareAudioSessionForSpeechRecording()
        try dashScopeAudioRecorder.start()
    }

    private func stopSpeechInquiry() {
        diagnosticLogger.event("ios_speech_stop", data: [:])
        if dashScopeAudioRecorder.isRecording {
            do {
                let audioDataURL = try dashScopeAudioRecorder.stopDataURL()
                finishNativeSpeechUI()
                diagnosticLogger.event("ios_dashscope_speech_audio_ready", data: [
                    "audio_chars": audioDataURL.count
                ])
                let imageDataURL = pendingSpeechImageDataURL
                pendingSpeechImageDataURL = ""
                processDashScopeSpeechInquiryAsync(imageDataURL: imageDataURL, audioDataURL: audioDataURL)
            } catch {
                finishNativeSpeechUI()
                pendingSpeechImageDataURL = ""
                diagnosticLogger.event("ios_dashscope_speech_failed", data: [
                    "error": error.localizedDescription
                ])
                sendToWeb(type: "error", payload: ["text": error.localizedDescription])
            }
            return
        }
        if localASRAudioRecorder.isRecording {
            do {
                let pcm = try localASRAudioRecorder.stopPCM()
                let imageDataURL = pendingSpeechImageDataURL
                let modelDirectory = URL(fileURLWithPath: runtimeStatus.localAsrModelDirectory, isDirectory: true)
                let runtime = localVoskRuntime
                finishNativeSpeechUI()
                pendingSpeechImageDataURL = ""
                diagnosticLogger.event("ios_local_asr_audio_ready", data: [
                    "pcm_bytes": pcm.count,
                    "model_dir": modelDirectory.path
                ])
                let pipeline = processorPipeline
                Task { [weak self, pipeline] in
                    guard let self else { return }
                    do {
                        let rawTranscript = try await Task.detached(priority: .userInitiated) {
                            try runtime.transcribe(modelDirectory: modelDirectory, pcm16: pcm)
                        }.value
                        let transcript = LocalAsrTextCorrector.fastCorrect(rawTranscript)
                        self.sendToWeb(type: "speech_transcript", payload: ["text": transcript])
                        if transcript != rawTranscript {
                            self.sendToWeb(type: "speech_transcript_correction", payload: [
                                "source_text": rawTranscript,
                                "text": transcript
                            ])
                        }
                        let messages = try await pipeline.processTextInquiry(
                            imageDataURL: imageDataURL,
                            transcript: transcript
                        )
                        self.emit(messages)
                    } catch {
                        self.diagnosticLogger.event("ios_local_asr_failed", data: [
                            "error": error.localizedDescription
                        ])
                        self.sendToWeb(type: "error", payload: ["text": error.localizedDescription])
                    }
                }
            } catch {
                finishNativeSpeechUI()
                pendingSpeechImageDataURL = ""
                diagnosticLogger.event("ios_local_asr_failed", data: [
                    "error": error.localizedDescription
                ])
                sendToWeb(type: "error", payload: ["text": error.localizedDescription])
            }
            return
        }
        finishNativeSpeechUI()
        sendToWeb(type: "error", payload: ["text": "没有正在进行的语音识别。"])
    }

    private func finishNativeSpeechUI() {
        if dashScopeAudioRecorder.isRecording {
            dashScopeAudioRecorder.cancel()
        }
        if localASRAudioRecorder.isRecording {
            localASRAudioRecorder.cancel()
        }
        sendToWeb(type: "speech_status", payload: ["listening": false])
        evaluate("window.LONG_TERM_CARE_NATIVE_SPEECH_DONE?.();")
    }

    private func startCamera() async {
        do {
            try await cameraService.start()
            cameraPreviewVisible = true
            latestCameraStatus = "running"
            latestCameraStatusText = "摄像头已打开"
            latestCameraErrorCode = ""
            publishRuntimeStatus()
            sendCameraStatusToWeb(status: latestCameraStatus, text: latestCameraStatusText)
            diagnosticLogger.event("ios_camera_start", data: cameraStatusPayload(status: latestCameraStatus, text: latestCameraStatusText))
        } catch {
            cameraPreviewVisible = false
            latestCameraStatus = "error"
            latestCameraStatusText = error.localizedDescription
            latestCameraErrorCode = cameraErrorCode(error)
            publishRuntimeStatus()
            var payload = cameraStatusPayload(
                status: latestCameraStatus,
                text: latestCameraStatusText,
                errorCode: latestCameraErrorCode
            )
            payload["error"] = error.localizedDescription
            diagnosticLogger.event("ios_camera_start_failed", data: payload)
            sendCameraStatusToWeb(status: latestCameraStatus, text: latestCameraStatusText, errorCode: latestCameraErrorCode)
        }
    }

    private func stopCamera() async {
        await cameraService.stop()
        cameraPreviewVisible = false
        latestCameraStatus = "stopped"
        latestCameraStatusText = "摄像头已关闭"
        latestCameraErrorCode = ""
        publishRuntimeStatus()
        sendCameraStatusToWeb(status: latestCameraStatus, text: latestCameraStatusText)
        diagnosticLogger.event("ios_camera_stop", data: cameraStatusPayload(status: latestCameraStatus, text: latestCameraStatusText))
    }

    private func captureNativeFrame() {
        do {
            let image = try cameraService.captureFrameDataURL()
            if latestCameraStatus != "running" {
                latestCameraStatus = "running"
                latestCameraStatusText = "摄像头已打开"
                latestCameraErrorCode = ""
                publishRuntimeStatus()
            }
            diagnosticLogger.event("ios_camera_frame", data: [
                "image_chars": image.count
            ])
            processFrameAsync(image, source: "captureFrame")
        } catch NativeCameraError.noFrame {
            latestCameraStatus = "warming"
            latestCameraStatusText = NativeCameraError.noFrame.localizedDescription
            latestCameraErrorCode = cameraErrorCode(NativeCameraError.noFrame)
            publishRuntimeStatus()
            diagnosticLogger.event("ios_camera_frame_waiting", data: cameraStatusPayload(
                status: latestCameraStatus,
                text: latestCameraStatusText,
                errorCode: latestCameraErrorCode
            ))
            sendCameraStatusToWeb(status: latestCameraStatus, text: latestCameraStatusText, errorCode: latestCameraErrorCode)
        } catch {
            latestCameraStatus = "frame_error"
            latestCameraStatusText = error.localizedDescription
            latestCameraErrorCode = cameraErrorCode(error)
            publishRuntimeStatus()
            diagnosticLogger.event("ios_camera_frame_failed", data: [
                "error": error.localizedDescription,
                "error_code": latestCameraErrorCode
            ])
            sendCameraStatusToWeb(status: latestCameraStatus, text: latestCameraStatusText, errorCode: latestCameraErrorCode)
        }
    }

    private func processFrameAsync(_ imageDataURL: String, source: String) {
        guard !nativeFrameProcessing else {
            diagnosticLogger.event("ios_camera_frame_busy", data: ["source": source])
            sendToWeb(type: "frame_status", payload: [
                "status": "busy",
                "text": "上一帧仍在分析，已跳过本次刷新。"
            ])
            return
        }

        nativeFrameProcessing = true
        sendToWeb(type: "frame_status", payload: ["status": "processing", "source": source])
        let pipeline = processorPipeline
        Task { [weak self, pipeline] in
            do {
                let messages = try await pipeline.processFrame(imageDataURL)
                await MainActor.run {
                    guard let self else { return }
                    self.nativeFrameProcessing = false
                    self.emit(messages)
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.nativeFrameProcessing = false
                    let message = self.userFacingProcessorError(error)
                    self.diagnosticLogger.event("ios_processor_frame_failed", data: [
                        "source": source,
                        "error": error.localizedDescription,
                        "user_message": message
                    ])
                    self.sendToWeb(type: "frame_status", payload: [
                        "status": "error",
                        "source": source,
                        "text": message
                    ])
                    self.sendToWeb(type: "error", payload: ["text": message])
                }
            }
        }
    }

    private func userFacingProcessorError(_ error: Error) -> String {
        if case SilverCareCoreError.invalidJSON = error {
            return "云端视觉返回格式不完整，已跳过本次刷新，请再点一次刷新。"
        }
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "本次导航刷新失败，请再试一次。" : message
    }

    private func processInquiryAsync(imageDataURL: String, audioDataURL: String) {
        let pipeline = processorPipeline
        Task { [weak self, pipeline] in
            do {
                let messages = try await pipeline.processInquiry(imageDataURL: imageDataURL, audioDataURL: audioDataURL)
                await MainActor.run {
                    guard let self else { return }
                    self.emit(messages)
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    let message = self.userFacingProcessorError(error)
                    self.diagnosticLogger.event("ios_processor_inquiry_failed", data: [
                        "error": error.localizedDescription,
                        "user_message": message
                    ])
                    self.sendToWeb(type: "error", payload: ["text": message])
                }
            }
        }
    }

    private func processDashScopeSpeechInquiryAsync(imageDataURL: String, audioDataURL: String) {
        let client = aiClient
        let pipeline = processorPipeline
        Task { [weak self, client, pipeline] in
            do {
                let rawTranscript = try await Task.detached(priority: .userInitiated) {
                    try client.transcribe(audioDataURL: audioDataURL)
                }.value
                let transcript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    guard let self else { return }
                    self.diagnosticLogger.event("ios_dashscope_asr_transcript", data: [
                        "transcript_chars": transcript.count
                    ])
                    self.sendToWeb(type: "speech_transcript", payload: ["text": transcript])
                }
                guard !transcript.isEmpty else {
                    await MainActor.run {
                        self?.sendToWeb(type: "error", payload: ["text": "没有识别到清晰语音。"])
                    }
                    return
                }
                let messages = try await pipeline.processTextInquiry(imageDataURL: imageDataURL, transcript: transcript)
                await MainActor.run {
                    guard let self else { return }
                    self.emit(messages)
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    let message = self.userFacingProcessorError(error)
                    self.diagnosticLogger.event("ios_dashscope_speech_inquiry_failed", data: [
                        "error": error.localizedDescription,
                        "user_message": message
                    ])
                    self.sendToWeb(type: "error", payload: ["text": message])
                }
            }
        }
    }

    private func processTextInquiryAsync(imageDataURL: String, transcript: String) {
        let pipeline = processorPipeline
        Task { [weak self, pipeline] in
            do {
                let messages = try await pipeline.processTextInquiry(imageDataURL: imageDataURL, transcript: transcript)
                await MainActor.run {
                    guard let self else { return }
                    self.emit(messages)
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    let message = self.userFacingProcessorError(error)
                    self.diagnosticLogger.event("ios_processor_text_inquiry_failed", data: [
                        "error": error.localizedDescription,
                        "user_message": message
                    ])
                    self.sendToWeb(type: "error", payload: ["text": message])
                }
            }
        }
    }

    private func sendCameraStatusToWeb(status: String, text: String, errorCode: String = "") {
        sendToWeb(type: "camera_status", payload: cameraStatusPayload(status: status, text: text, errorCode: errorCode))
    }

    private func cameraStatusPayload(status: String, text: String, errorCode: String = "") -> [String: Any] {
        [
            "status": status,
            "text": text,
            "running": cameraService.isRunning,
            "preview_visible": cameraPreviewVisible,
            "available": cameraService.canStartCamera,
            "hardware_available": cameraService.hardwareAvailable,
            "authorization_status": cameraService.authorizationStatusLabel,
            "error_code": errorCode
        ]
    }

    private func cameraErrorCode(_ error: Error) -> String {
        if let cameraError = error as? NativeCameraError {
            switch cameraError {
            case .permissionDenied:
                return "permission_denied"
            case .cameraUnavailable:
                return "camera_unavailable"
            case .cannotAddInput:
                return "cannot_add_input"
            case .cannotAddOutput:
                return "cannot_add_output"
            case .noFrame:
                return "no_frame"
            case .imageEncodingFailed:
                return "image_encoding_failed"
            }
        }
        return "unknown"
    }

    private func sendToWeb(type: String, payload: [String: Any]) {
        var data = payload
        data["type"] = type
        guard
            JSONSerialization.isValidJSONObject(data),
            let jsonData = try? JSONSerialization.data(withJSONObject: data),
            let json = String(data: jsonData, encoding: .utf8)
        else { return }
        evaluate("window.LONG_TERM_CARE_NATIVE_MESSAGE?.(\(json));")
    }

    private func evaluate(_ script: String) {
        webView?.evaluateJavaScript(script)
    }

    private func presentSettings() {
        guard let presenter = webView?.window?.rootViewController else {
            sendToWeb(type: "runtime_status", payload: runtimeStatus.payload)
            return
        }
        let alert = UIAlertController(
            title: "银龄智护 iOS 设置",
            message: "当前方案：\(runtimeStatus.runtimeDisplayName)",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "切换运行方案", style: .default) { [weak self] _ in
            Task { @MainActor in self?.presentRuntimeModeSheet() }
        })
        alert.addAction(UIAlertAction(title: "全部切换为本地", style: .default) { [weak self] _ in
            Task { @MainActor in self?.presentAllLocalConfirmation() }
        })
        alert.addAction(UIAlertAction(title: "全部切换为云端 DashScope", style: .default) { [weak self] _ in
            Task { @MainActor in self?.switchAllCloud() }
        })
        alert.addAction(UIAlertAction(title: "填写 DashScope Key", style: .default) { [weak self] _ in
            Task { @MainActor in self?.presentDashScopeKeyPrompt() }
        })
        alert.addAction(UIAlertAction(title: "DashScope 区域/模型", style: .default) { [weak self] _ in
            Task { @MainActor in self?.presentAdvancedRuntimePrompt() }
        })
        alert.addAction(UIAlertAction(title: "离线文本模型", style: .default) { [weak self] _ in
            Task { @MainActor in self?.presentOfflineTextModelSheet() }
        })
        alert.addAction(UIAlertAction(title: "语音识别方案", style: .default) { [weak self] _ in
            Task { @MainActor in self?.presentAsrRuntimeSheet() }
        })
        alert.addAction(UIAlertAction(title: "朗读方案", style: .default) { [weak self] _ in
            Task { @MainActor in self?.presentTtsRuntimeSheet() }
        })
        alert.addAction(UIAlertAction(title: "检查本地离线模型", style: .default) { [weak self] _ in
            Task { @MainActor in self?.presentOfflineModelStatus() }
        })
        alert.addAction(UIAlertAction(title: "自动准备本地模型", style: .default) { [weak self] _ in
            Task { @MainActor in await self?.prepareOfflineModels() }
        })
        alert.addAction(UIAlertAction(title: "本地模型诊断", style: .default) { [weak self] _ in
            Task { @MainActor in self?.presentLocalModelDiagnostics() }
        })
        alert.addAction(UIAlertAction(title: "语音/字幕/跌倒", style: .default) { [weak self] _ in
            Task { @MainActor in self?.presentAccessibilitySettings() }
        })
        alert.addAction(UIAlertAction(title: "导航刷新模式", style: .default) { [weak self] _ in
            Task { @MainActor in self?.presentNavigationRefreshSettings() }
        })
        alert.addAction(UIAlertAction(title: "SME2 性能调优", style: .default) { [weak self] _ in
            Task { @MainActor in self?.presentMnnTuningSettings() }
        })
        alert.addAction(UIAlertAction(title: "发送当前状态到页面", style: .default) { [weak self] _ in
            Task { @MainActor in self?.publishRuntimeStatus() }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, from: presenter)
    }

    private func presentAdvancedRuntimePrompt() {
        guard let presenter = webView?.window?.rootViewController else {
            sendToWeb(type: "runtime_status", payload: runtimeStatus.payload)
            return
        }
        let alert = UIAlertController(
            title: "DashScope 区域/模型",
            message: "一般只需要填写 Key；不同地域或模型才需要改这里。",
            preferredStyle: .alert
        )
        alert.addTextField { [runtimeStatus] field in
            field.placeholder = "OpenAI 兼容地址"
            field.text = runtimeStatus.compatibleBaseURL
            field.keyboardType = .URL
        }
        alert.addTextField { [runtimeStatus] field in
            field.placeholder = "DashScope API 地址"
            field.text = runtimeStatus.apiBaseURL
            field.keyboardType = .URL
        }
        alert.addTextField { [runtimeStatus] field in
            field.placeholder = "视觉模型"
            field.text = runtimeStatus.visionModel
        }
        alert.addTextField { [runtimeStatus] field in
            field.placeholder = "文本模型"
            field.text = runtimeStatus.textModel
        }
        alert.addTextField { [runtimeStatus] field in
            field.placeholder = "联网 ASR 模型"
            field.text = runtimeStatus.asrModel
        }
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            Task { @MainActor in
                guard let self, let fields = alert?.textFields, fields.count >= 5 else { return }
                self.runtimeStatus.compatibleBaseURL = self.trimTrailingSlash(fields[0].text ?? self.runtimeStatus.compatibleBaseURL)
                self.runtimeStatus.apiBaseURL = self.trimTrailingSlash(fields[1].text ?? self.runtimeStatus.apiBaseURL)
                self.runtimeStatus.visionModel = fields[2].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? self.runtimeStatus.visionModel
                self.runtimeStatus.microModel = self.runtimeStatus.visionModel
                self.runtimeStatus.textModel = fields[3].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? self.runtimeStatus.textModel
                self.runtimeStatus.asrModel = fields[4].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? self.runtimeStatus.asrModel
                self.runtimeStatus.save()
                self.publishRuntimeStatus()
                self.speak("区域和模型设置已保存。")
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, from: presenter)
    }

    private func presentOfflineModelStatus() {
        refreshOfflineModelStatus()
        publishRuntimeStatus()
        guard let presenter = webView?.window?.rootViewController else {
            sendToWeb(type: "runtime_status", payload: runtimeStatus.payload)
            return
        }
        let alert = UIAlertController(
            title: "本地离线模型",
            message: runtimeStatus.offlineDetailText
                + "\n\n1.5B 选项会保留，但不会自动下载或打包；低内存设备需要用户自行准备对应模型后再切换。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "自动准备模型", style: .default) { [weak self] _ in
            Task { @MainActor in await self?.prepareOfflineModels() }
        })
        alert.addAction(UIAlertAction(title: "发送状态到页面", style: .default) { [weak self] _ in
            Task { @MainActor in self?.publishRuntimeStatus() }
        })
        alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
        present(alert, from: presenter)
    }

    private func presentLocalModelDiagnostics() {
        refreshOfflineModelStatus()
        refreshSpeechRuntimeStatus()
        refreshTTSRuntimeStatus()
        publishRuntimeStatus()
        guard let presenter = webView?.window?.rootViewController else {
            sendToWeb(type: "runtime_status", payload: runtimeStatus.payload)
            return
        }
        let message = """
        MNN：\(localModelRuntime.runtimeSummary)
        离线模型：\(runtimeStatus.offlineStatusText)
        本地 ASR：\(runtimeStatus.localAsrStatusText)
        本地 TTS：\(runtimeStatus.localTtsStatusText)
        """
        let alert = UIAlertController(title: "本地模型诊断", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "运行状态诊断", style: .default) { [weak self] _ in
            Task { @MainActor in await self?.runLocalModelBenchmark(test: "status") }
        })
        alert.addAction(UIAlertAction(title: "发送状态到页面", style: .default) { [weak self] _ in
            Task { @MainActor in self?.publishRuntimeStatus() }
        })
        alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
        present(alert, from: presenter)
    }

    private func presentOfflineTextModelSheet() {
        refreshOfflineModelStatus()
        guard let presenter = webView?.window?.rootViewController else {
            sendToWeb(type: "runtime_status", payload: runtimeStatus.payload)
            return
        }
        let current = OfflineModelManifest.cleanTextModel(runtimeStatus.offlineTextModel)
        let message = """
        只影响端侧离线 MNN 文本模型；联网 DashScope 文本模型仍在“DashScope 区域/模型”里设置。

        自动准备模型只会准备 Qwen3-4B-Instruct-2507-MNN。1.5B 选项会保留，但不会自动下载或打包；低内存设备需要用户自行准备对应模型后再切换。

        当前选择：\(OfflineModelManifest.textModelLabel(current))
        """
        let alert = UIAlertController(title: "离线文本模型", message: message, preferredStyle: .actionSheet)
        let models = [
            (OfflineModelManifest.textModel4B, "Qwen3-4B-Instruct-2507-MNN（默认，质量更高）"),
            (OfflineModelManifest.textModel15B, "Qwen2.5-1.5B-Instruct-MNN（备用，更轻更快）")
        ]
        for (model, label) in models {
            let selected = current == model ? " ✓" : ""
            alert.addAction(UIAlertAction(title: label + selected, style: .default) { [weak self] _ in
                Task { @MainActor in self?.setOfflineTextModel(model) }
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, from: presenter)
    }

    private func presentRuntimeModeSheet() {
        guard let presenter = webView?.window?.rootViewController else {
            sendToWeb(type: "runtime_status", payload: runtimeStatus.payload)
            return
        }
        let alert = UIAlertController(title: "运行方案", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "联网 DashScope", style: .default) { [weak self] _ in
            Task { @MainActor in
                self?.setRuntimeMode("dashscope")
            }
        })
        alert.addAction(UIAlertAction(title: "端侧离线 MNN", style: .default) { [weak self] _ in
            Task { @MainActor in
                self?.setRuntimeMode("offline_mnn")
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, from: presenter)
    }

    private func presentAllLocalConfirmation() {
        refreshOfflineModelStatus()
        refreshSpeechRuntimeStatus()
        refreshTTSRuntimeStatus()
        let plan = localRuntimeBundlePlan()
        guard let presenter = webView?.window?.rootViewController else {
            sendToWeb(type: "runtime_status", payload: runtimeStatus.payload)
            return
        }
        var message = """
        将切换为：
        AI：端侧离线 MNN + Qwen3-4B + DAMO-YOLO
        ASR：本地内置 ASR
        TTS：手机系统 TTS 本机朗读

        还没准备好的内容：
        \(plan.downloadSummaryText)
        """
        let warnings = plan.runtimeWarningText
        if !warnings.isEmpty {
            message += "\n\n运行时提醒：\n\(warnings)"
        }

        let alert = UIAlertController(title: "全部切换为本地", message: message, preferredStyle: .alert)
        if plan.hasDownloads {
            alert.addAction(UIAlertAction(title: "准备模型并切换", style: .default) { [weak self] _ in
                Task { @MainActor in
                    self?.applyAllLocalPreferences()
                    await self?.prepareOfflineModels()
                }
            })
            alert.addAction(UIAlertAction(title: "只切换", style: .default) { [weak self] _ in
                Task { @MainActor in self?.switchAllLocalWithoutDownload() }
            })
        } else {
            alert.addAction(UIAlertAction(title: "切换为本地", style: .default) { [weak self] _ in
                Task { @MainActor in self?.switchAllLocalWithoutDownload() }
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, from: presenter)
    }

    private func switchAllCloud() {
        runtimeStatus.visionModel = SilverCareRuntimeStatus.defaultDashScopeVisionModel
        runtimeStatus.microModel = SilverCareRuntimeStatus.defaultDashScopeVisionModel
        runtimeStatus.textModel = SilverCareRuntimeStatus.defaultDashScopeTextModel
        setRuntimeMode(SilverCareRuntimeMode.dashScope.rawValue, speakResult: false)
        setAsrRuntimeMode(SilverCareASRRuntimeMode.dashScope.rawValue, speakResult: false)
        setTtsRuntimeMode(SilverCareTTSRuntimeMode.dashScope.rawValue, speakResult: false)
        publishRuntimeStatus()
        speak("已全部切换为云端 DashScope。AI、语音识别和朗读都会使用联网方案。")
        if !runtimeStatus.hasDashScopeKey {
            presentDashScopeKeyPrompt()
        }
    }

    private func switchAllLocalWithoutDownload() {
        applyAllLocalPreferences()
        let plan = localRuntimeBundlePlan()
        publishRuntimeStatus()
        speak("已全部切换为本地优先。")
        if plan.hasDownloads {
            sendToWeb(type: "error", payload: ["text": "本地模型还未全部下载：\(plan.downloadSummaryText)"])
        }
        let warnings = plan.runtimeWarningText
        if !warnings.isEmpty {
            sendToWeb(type: "error", payload: ["text": warnings])
        }
    }

    private func applyAllLocalPreferences() {
        runtimeStatus.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
        runtimeStatus.runtimeDisplayName = SilverCareRuntimeMode.offlineMNN.label
        runtimeStatus.offlineTextModel = OfflineModelManifest.textModel4B
        runtimeStatus.visionModel = "damo-yolo-mnn"
        runtimeStatus.microModel = "damo-yolo-mnn"
        runtimeStatus.asrRuntimeMode = SilverCareASRRuntimeMode.localVosk.rawValue
        runtimeStatus.asrRuntimeDisplayName = SilverCareASRRuntimeMode.localVosk.label
        runtimeStatus.ttsRuntimeMode = SilverCareTTSRuntimeMode.system.rawValue
        runtimeStatus.ttsRuntimeDisplayName = SilverCareTTSRuntimeMode.system.label
        runtimeStatus.save()
        refreshSpeechRuntimeStatus()
        refreshTTSRuntimeStatus()
        refreshOfflineModelStatus()
    }

    private func localRuntimeBundlePlan() -> SilverCareLocalRuntimeBundlePlan {
        let offline = offlineModelManager.inspect(
            textModel: OfflineModelManifest.textModel4B,
            nativeRuntimeAvailable: localModelRuntime.isReady
        )
        let localASR = localASRModelManager.inspect(runtimeAvailable: localVoskRuntime.isAvailable)
        return SilverCareLocalRuntimeBundlePlan.from(
            offlineStatus: offline,
            localASRReady: localASR.modelReady,
            localASRRuntimeAvailable: localASR.runtimeAvailable,
            includeExperimentalTTS: false,
            ttsRuntimeAvailable: false
        )
    }

    private func presentAsrRuntimeSheet() {
        refreshSpeechRuntimeStatus()
        guard let presenter = webView?.window?.rootViewController else {
            sendToWeb(type: "runtime_status", payload: runtimeStatus.payload)
            return
        }
        let current = SilverCareASRRuntimeMode.from(runtimeStatus.asrRuntimeMode)
        let message = """
        ASR 可以独立选择本地或联网，不跟随 AI 运行方案。

        本地内置 ASR：\(runtimeStatus.localAsrStatusText)
        联网 DashScope：\(runtimeStatus.hasDashScopeKey ? "已配置 Key" : "需要 DashScope Key")

        当前选择：\(current.label)
        """
        let alert = UIAlertController(title: "语音识别方案", message: message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "本地内置 ASR", style: .default) { [weak self] _ in
            Task { @MainActor in self?.setAsrRuntimeMode(SilverCareASRRuntimeMode.localVosk.rawValue) }
        })
        alert.addAction(UIAlertAction(title: "联网 DashScope", style: .default) { [weak self] _ in
            Task { @MainActor in self?.setAsrRuntimeMode(SilverCareASRRuntimeMode.dashScope.rawValue) }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, from: presenter)
    }

    private func presentTtsRuntimeSheet() {
        refreshTTSRuntimeStatus()
        guard let presenter = webView?.window?.rootViewController else {
            sendToWeb(type: "runtime_status", payload: runtimeStatus.payload)
            return
        }
        let current = SilverCareTTSRuntimeMode.from(runtimeStatus.ttsRuntimeMode)
        let message = """
        朗读方案独立于 ASR 和 AI 运行方案。

        自动兜底会优先用 iOS 系统 TTS；明确选择 DashScope 时，会请求联网语音合成并播放返回音频。
        本地 MNN TTS 当前保留为实验项；可以准备模型和检查状态，但未通过真实可懂度验收前不会作为主朗读方案。

        当前选择：\(current.label)
        当前状态：\(runtimeStatus.ttsStatusText)
        本地模型：\(runtimeStatus.localTtsStatusText)
        """
        let alert = UIAlertController(title: "朗读方案", message: message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "自动兜底：iOS 系统 TTS -> DashScope", style: .default) { [weak self] _ in
            Task { @MainActor in self?.setTtsRuntimeMode(SilverCareTTSRuntimeMode.auto.rawValue) }
        })
        alert.addAction(UIAlertAction(title: "手机系统 TTS（本地）", style: .default) { [weak self] _ in
            Task { @MainActor in self?.setTtsRuntimeMode(SilverCareTTSRuntimeMode.system.rawValue) }
        })
        alert.addAction(UIAlertAction(title: "联网 DashScope", style: .default) { [weak self] _ in
            Task { @MainActor in self?.setTtsRuntimeMode(SilverCareTTSRuntimeMode.dashScope.rawValue) }
        })
        let local = UIAlertAction(title: "本地 MNN TTS（实验）", style: .default) { [weak self] _ in
            Task { @MainActor in self?.setTtsRuntimeMode(SilverCareTTSRuntimeMode.localMNN.rawValue) }
        }
        alert.addAction(local)
        alert.addAction(UIAlertAction(title: "准备本地 MNN TTS 模型（约 1.3GB，实验）", style: .default) { [weak self] _ in
            Task { @MainActor in await self?.prepareLocalTTSModels() }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, from: presenter)
    }

    private func presentAccessibilitySettings() {
        guard let presenter = webView?.window?.rootViewController else {
            sendToWeb(type: "runtime_status", payload: runtimeStatus.payload)
            return
        }
        let alert = UIAlertController(
            title: "语音/字幕/跌倒",
            message: "本页控制低视力使用时最常用的本地辅助能力。",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(
            title: runtimeStatus.captionsEnabled ? "关闭语音字幕" : "开启语音字幕",
            style: .default
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setCaptionsEnabled(!(self?.runtimeStatus.captionsEnabled ?? true))
            }
        })
        alert.addAction(UIAlertAction(
            title: runtimeStatus.voiceFirstEnabled ? "关闭语音优先模式" : "开启语音优先模式",
            style: .default
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setVoiceFirstEnabled(!(self?.runtimeStatus.voiceFirstEnabled ?? true))
            }
        })
        alert.addAction(UIAlertAction(
            title: runtimeStatus.fallDetectionEnabled ? "关闭跌倒检测" : "开启跌倒检测",
            style: .default
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setFallDetectionEnabled(!(self?.runtimeStatus.fallDetectionEnabled ?? true))
            }
        })
        alert.addAction(UIAlertAction(title: "测试朗读", style: .default) { [weak self] _ in
            Task { @MainActor in self?.speak("这是银龄智护的语音测试。如果你听到这句话，说明系统朗读正常。") }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, from: presenter)
    }

    private func presentNavigationRefreshSettings() {
        guard let presenter = webView?.window?.rootViewController else {
            sendToWeb(type: "runtime_status", payload: runtimeStatus.payload)
            return
        }
        let alert = UIAlertController(
            title: "导航刷新模式",
            message: "自动刷新适合持续看路；手动刷新适合省电和低带宽。智能刷新会跳过语义变化很小的画面。",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "自动刷新，每 3 秒", style: .default) { [weak self] _ in
            Task { @MainActor in self?.setNavigationRefresh(mode: "auto", intervalMs: 3000) }
        })
        alert.addAction(UIAlertAction(title: "自动刷新，每 5 秒", style: .default) { [weak self] _ in
            Task { @MainActor in self?.setNavigationRefresh(mode: "auto", intervalMs: 5000) }
        })
        alert.addAction(UIAlertAction(title: "手动刷新", style: .default) { [weak self] _ in
            Task { @MainActor in self?.setNavigationRefresh(mode: "manual", intervalMs: self?.runtimeStatus.navigationRefreshIntervalMs ?? 3000) }
        })
        alert.addAction(UIAlertAction(
            title: runtimeStatus.smartNavigationRefreshEnabled ? "关闭智能刷新" : "开启智能刷新",
            style: .default
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.runtimeStatus.smartNavigationRefreshEnabled.toggle()
                self.runtimeStatus.save()
                self.publishRuntimeStatus()
                self.speak(self.runtimeStatus.smartNavigationRefreshEnabled ? "智能刷新已开启。" : "智能刷新已关闭。")
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, from: presenter)
    }

    private func presentMnnTuningSettings() {
        guard let presenter = webView?.window?.rootViewController else {
            sendToWeb(type: "runtime_status", payload: runtimeStatus.payload)
            return
        }
        let alert = UIAlertController(
            title: "SME2 性能调优",
            message: localModelRuntime.runtimeSummary,
            preferredStyle: .actionSheet
        )
        let options = [
            ("auto", "SME2 自动调优"),
            ("performance", "SME2 性能优先"),
            ("efficiency", "SME2 省电稳定"),
            ("mnn_default", "MNN 默认")
        ]
        for (value, label) in options {
            alert.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                Task { @MainActor in self?.setMnnTuningMode(value, label: label) }
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, from: presenter)
    }

    private func presentDashScopeKeyPrompt() {
        guard let presenter = webView?.window?.rootViewController else {
            sendToWeb(type: "runtime_status", payload: runtimeStatus.payload)
            return
        }
        let alert = UIAlertController(title: "DashScope Key", message: "密钥只保存在本机 UserDefaults。", preferredStyle: .alert)
        alert.addTextField { [runtimeStatus] field in
            field.placeholder = "sk-..."
            field.text = runtimeStatus.dashScopeAPIKey
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "保存并切换联网", style: .default) { [weak self, weak alert] _ in
            Task { @MainActor in
                let key = alert?.textFields?.first?.text ?? ""
                self?.runtimeStatus.dashScopeAPIKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.setRuntimeMode("dashscope")
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, from: presenter)
    }

    private func setRuntimeMode(_ mode: String, speakResult: Bool = true) {
        let runtimeMode = SilverCareRuntimeMode.from(mode)
        runtimeStatus.aiRuntimeMode = runtimeMode.rawValue
        runtimeStatus.runtimeDisplayName = runtimeMode.label
        runtimeStatus.save()
        publishRuntimeStatus()
        if speakResult {
            speak("已切换到\(runtimeMode.label)。")
        }
        if runtimeMode.isOffline && !runtimeStatus.offlineReady {
            presentOfflineModelStatus()
        } else if !runtimeMode.isOffline && !runtimeStatus.hasDashScopeKey {
            presentDashScopeKeyPrompt()
        }
    }

    private func setOfflineTextModel(_ model: String) {
        let clean = OfflineModelManifest.cleanTextModel(model)
        runtimeStatus.offlineTextModel = clean
        runtimeStatus.save()
        refreshOfflineModelStatus()
        publishRuntimeStatus()
        let label = OfflineModelManifest.textModelLabel(clean)
        speak("离线文本模型已切换到\(label)。")
        if !runtimeStatus.offlineTextReady {
            sendToWeb(type: "error", payload: [
                "text": "\(label) 尚未就绪：\(runtimeStatus.offlineStatusText)"
            ])
        }
    }

    private func setAsrRuntimeMode(_ mode: String, speakResult: Bool = true) {
        let asrMode = SilverCareASRRuntimeMode.from(mode)
        runtimeStatus.asrRuntimeMode = asrMode.rawValue
        runtimeStatus.asrRuntimeDisplayName = asrMode.label
        runtimeStatus.save()
        refreshSpeechRuntimeStatus()
        publishRuntimeStatus()
        if speakResult {
            speak("语音识别已切换到\(asrMode.label)。")
        }
        if !asrMode.isLocal && !runtimeStatus.hasDashScopeKey {
            presentDashScopeKeyPrompt()
        }
    }

    private func setTtsRuntimeMode(_ mode: String, speakResult: Bool = true) {
        let ttsMode = SilverCareTTSRuntimeMode.from(mode)
        runtimeStatus.ttsRuntimeMode = ttsMode.rawValue
        runtimeStatus.ttsRuntimeDisplayName = ttsMode.label
        runtimeStatus.save()
        refreshTTSRuntimeStatus()
        publishRuntimeStatus()
        if speakResult {
            speak("朗读方案已切换到\(ttsMode.label)。")
        }
        if ttsMode.allowsDashScope && !runtimeStatus.hasDashScopeKey && ttsMode == .dashScope {
            presentDashScopeKeyPrompt()
        } else if ttsMode == .localMNN && !runtimeStatus.localTtsReady {
            sendToWeb(type: "error", payload: [
                "text": "\(runtimeStatus.localTtsStatusText)。当前朗读会继续安全回退到 iOS 系统 TTS。"
            ])
        }
    }

    private func setCaptionsEnabled(_ enabled: Bool) {
        runtimeStatus.captionsEnabled = enabled
        runtimeStatus.save()
        publishRuntimeStatus()
        speak(enabled ? "语音字幕已开启。" : "语音字幕已关闭。")
    }

    private func setVoiceFirstEnabled(_ enabled: Bool) {
        runtimeStatus.voiceFirstEnabled = enabled
        runtimeStatus.save()
        publishRuntimeStatus()
        speak(enabled ? "语音优先模式已开启。" : "语音优先模式已关闭。")
    }

    private func setFallDetectionEnabled(_ enabled: Bool) {
        runtimeStatus.fallDetectionEnabled = enabled
        runtimeStatus.save()
        publishRuntimeStatus()
        startNativeFallMonitoringIfNeeded()
        speak(enabled ? "跌倒检测已开启。" : "跌倒检测已关闭。")
    }

    private func setNavigationRefresh(mode: String, intervalMs: Int) {
        runtimeStatus.navigationRefreshMode = mode
        runtimeStatus.navigationRefreshIntervalMs = intervalMs
        runtimeStatus.save()
        publishRuntimeStatus()
        if mode == "manual" {
            speak("已切换到手动刷新。启动导航后，单击屏幕刷新一次导航。")
        } else {
            speak("已切换到自动刷新，每 \(max(1, intervalMs / 1000)) 秒刷新一次。")
        }
    }

    private func setMnnTuningMode(_ mode: String, label: String) {
        runtimeStatus.mnnLlmTuningMode = mode
        runtimeStatus.mnnLlmTuningDisplayName = label
        runtimeStatus.save()
        publishRuntimeStatus()
        speak("\(label) 已选择。")
    }

    func publishRuntimeStatus() {
        refreshSpeechRuntimeStatus()
        refreshTTSRuntimeStatus()
        refreshOfflineModelStatus()
        evaluate("window.SILVERCARE_IOS_RUNTIME = \(runtimeBridgeJSON());")
        evaluate("window.SILVERCARE_SYNC_IOS_NATIVE_CAMERA_CLASS?.();")
        sendToWeb(type: "runtime_status", payload: runtimeStatusPayload())
        evaluate("window.LONG_TERM_CARE_REFRESH_SETTINGS_CHANGED?.('\(runtimeStatus.navigationRefreshMode)', \(runtimeStatus.navigationRefreshIntervalMs), \(runtimeStatus.smartNavigationRefreshEnabled ? "true" : "false"));")
    }

    private func runtimeStatusPayload() -> [String: Any] {
        var payload = runtimeStatus.payload
        payload["native_camera_available"] = cameraService.canStartCamera
        payload["native_camera_running"] = cameraService.isRunning
        payload["native_camera_preview_visible"] = cameraPreviewVisible
        payload["native_camera_status"] = latestCameraStatus
        payload["native_camera_status_text"] = latestCameraStatusText
        payload["native_camera_error_code"] = latestCameraErrorCode
        payload["native_camera_authorization_status"] = cameraService.authorizationStatusLabel
        payload["native_camera_hardware_available"] = cameraService.hardwareAvailable
        return payload
    }

    private func refreshOfflineModelStatus() {
        let status = offlineModelManager.inspect(
            textModel: runtimeStatus.offlineTextModel,
            nativeRuntimeAvailable: localModelRuntime.isReady
        )
        runtimeStatus.applyOfflineModelStatus(status)
        runtimeStatus.mnnRuntimeSummary = localModelRuntime.runtimeSummary
    }

    private func refreshSpeechRuntimeStatus() {
        let mode = SilverCareASRRuntimeMode.from(runtimeStatus.asrRuntimeMode)
        runtimeStatus.asrRuntimeMode = mode.rawValue
        runtimeStatus.asrRuntimeDisplayName = mode.label
        if mode.isLocal {
            runtimeStatus.applyLocalASRModelStatus(localASRModelManager.inspect(runtimeAvailable: localVoskRuntime.isAvailable))
        } else {
            runtimeStatus.localAsrReady = false
            runtimeStatus.localAsrStatusText = runtimeStatus.hasDashScopeKey
                ? "联网 ASR 已配置 DashScope Key。"
                : "联网 ASR 需要先填写 DashScope Key。"
        }
    }

    private func refreshTTSRuntimeStatus() {
        let mode = SilverCareTTSRuntimeMode.from(runtimeStatus.ttsRuntimeMode)
        let localTTS = currentLocalTTSModelStatus()
        runtimeStatus.applyLocalTTSModelStatus(localTTS)
        runtimeStatus.ttsRuntimeMode = mode.rawValue
        runtimeStatus.ttsRuntimeDisplayName = mode.label
        switch mode {
        case .auto:
            runtimeStatus.ttsStatusText = runtimeStatus.hasDashScopeKey
                ? "自动兜底：优先 iOS 系统 TTS，必要时可使用 DashScope。"
                : "自动兜底：iOS 系统 TTS 已就绪；DashScope 需要 Key。"
        case .system:
            runtimeStatus.ttsStatusText = "iOS 系统 TTS 已就绪。"
        case .dashScope:
            runtimeStatus.ttsStatusText = runtimeStatus.hasDashScopeKey
                ? "联网 DashScope TTS 已配置 Key。"
                : "联网 DashScope TTS 需要先填写 Key。"
        case .localMNN:
            runtimeStatus.ttsStatusText = localTTS.detailText
        }
    }

    private func currentLocalTTSModelStatus() -> LocalTTSModelStatus {
        localTTSModelManager.inspect(
            runtimeAvailable: localTTSRuntime.isAvailable,
            runtimeSummary: localTTSRuntime.runtimeSummary,
            voiceQualityPassed: localTTSRuntime.voiceQualityPassed
        )
    }

    private func prepareOfflineModels() async {
        let aiBytes = OfflineModelManifest.expectedTotalBytes
        let asrBytes = LocalASRModelManifest.expectedZipBytes
        let totalBytes = aiBytes + asrBytes
        if offlineDownloadInFlight {
            sendModelDownloadProgress(OfflineModelDownloadProgress(
                message: "离线模型准备任务正在进行中",
                downloadedBytes: 0,
                totalBytes: totalBytes,
                complete: false,
                failed: false
            ))
            return
        }

        offlineDownloadInFlight = true
        defer { offlineDownloadInFlight = false }
        sendModelDownloadProgress(OfflineModelDownloadProgress(
            message: "开始准备 iOS 离线模型",
            downloadedBytes: 0,
            totalBytes: totalBytes,
            complete: false,
            failed: false
        ))
        diagnosticLogger.event("ios_offline_model_prepare_start", data: [
            "expected_ai_bytes": aiBytes,
            "expected_asr_bytes": asrBytes,
            "expected_total_bytes": totalBytes
        ])

        do {
            let result = try await offlineModelManager.prepareQwen4BBundle { [weak self] progress in
                Task { @MainActor in
                    self?.sendModelDownloadProgress(OfflineModelDownloadProgress(
                        message: progress.message,
                        downloadedBytes: min(progress.downloadedBytes, aiBytes),
                        totalBytes: totalBytes,
                        complete: false,
                        failed: progress.failed
                    ))
                }
            }
            diagnosticLogger.event("ios_offline_model_prepare_done", data: [
                "model_dir": result.modelDirectory.path,
                "total_bytes": result.totalBytes
            ])
            refreshOfflineModelStatus()
            let asrResult = try await localASRModelManager.ensureChineseModel { [weak self] progress in
                Task { @MainActor in
                    self?.sendModelDownloadProgress(OfflineModelDownloadProgress(
                        message: progress.message,
                        downloadedBytes: min(aiBytes + progress.downloadedBytes, totalBytes),
                        totalBytes: totalBytes,
                        complete: false,
                        failed: progress.failed
                    ))
                }
            }
            diagnosticLogger.event("ios_local_asr_model_prepare_done", data: [
                "model_root": asrResult.modelRoot.path,
                "model_dir": asrResult.modelDirectory.path,
                "total_bytes": asrResult.totalBytes
            ])
            refreshSpeechRuntimeStatus()
            sendModelDownloadProgress(OfflineModelDownloadProgress(
                message: "离线模型和本地 ASR 模型已准备完成，等待 iOS MNN/Vosk runtime 绑定",
                downloadedBytes: totalBytes,
                totalBytes: totalBytes,
                complete: true,
                failed: false
            ))
            publishRuntimeStatus()
        } catch {
            diagnosticLogger.event("ios_offline_model_prepare_failed", data: [
                "error": error.localizedDescription
            ])
            sendModelDownloadProgress(OfflineModelDownloadProgress(
                message: error.localizedDescription,
                downloadedBytes: 0,
                totalBytes: totalBytes,
                complete: false,
                failed: true
            ))
            refreshOfflineModelStatus()
            refreshSpeechRuntimeStatus()
            publishRuntimeStatus()
        }
    }

    private func prepareLocalTTSModels() async {
        let totalBytes = LocalTTSModelManifest.expectedTotalBytes
        if offlineDownloadInFlight {
            sendModelDownloadProgress(OfflineModelDownloadProgress(
                message: "本地模型准备任务正在进行中",
                downloadedBytes: 0,
                totalBytes: totalBytes,
                complete: false,
                failed: false
            ))
            return
        }

        offlineDownloadInFlight = true
        defer { offlineDownloadInFlight = false }
        sendModelDownloadProgress(OfflineModelDownloadProgress(
            message: "开始准备本地 MNN TTS 实验模型",
            downloadedBytes: 0,
            totalBytes: totalBytes,
            complete: false,
            failed: false
        ))
        diagnosticLogger.event("ios_local_tts_model_prepare_start", data: [
            "expected_tts_bytes": totalBytes,
            "model_name": LocalTTSModelManifest.modelName
        ])

        do {
            let result = try await localTTSModelManager.ensureMNNBundle { [weak self] progress in
                Task { @MainActor in
                    self?.sendModelDownloadProgress(progress)
                }
            }
            diagnosticLogger.event("ios_local_tts_model_prepare_done", data: [
                "model_root": result.modelRoot.path,
                "model_dir": result.modelDirectory.path,
                "total_bytes": result.totalBytes
            ])
            refreshTTSRuntimeStatus()
            sendModelDownloadProgress(OfflineModelDownloadProgress(
                message: "本地 MNN TTS 实验模型已准备完成，等待 iOS TTS runtime 和音质验收",
                downloadedBytes: totalBytes,
                totalBytes: totalBytes,
                complete: true,
                failed: false
            ))
            publishRuntimeStatus()
        } catch {
            diagnosticLogger.event("ios_local_tts_model_prepare_failed", data: [
                "error": error.localizedDescription
            ])
            sendModelDownloadProgress(OfflineModelDownloadProgress(
                message: error.localizedDescription,
                downloadedBytes: 0,
                totalBytes: totalBytes,
                complete: false,
                failed: true
            ))
            refreshTTSRuntimeStatus()
            publishRuntimeStatus()
        }
    }

    private func sendModelDownloadProgress(_ progress: OfflineModelDownloadProgress) {
        sendToWeb(type: "model_download_progress", payload: progress.payload)
    }

    private func runLocalModelBenchmark(
        test requestedTest: String = "status",
        presentReport: Bool = true,
        speakResult: Bool = true
    ) async {
        refreshOfflineModelStatus()
        refreshSpeechRuntimeStatus()
        refreshTTSRuntimeStatus()
        let test = cleanLocalBenchmarkTest(requestedTest)
        let report = makeLocalBenchmarkReport(test: test)
        do {
            let output = try writeLocalBenchmarkReport(report)
            latestLocalBenchmarkPath = output.path
            var payload = report
            payload["output_file"] = output.path
            sendToWeb(type: "local_benchmark_result", payload: payload)
            diagnosticLogger.event("ios_local_benchmark_\(test)", data: payload)
            publishRuntimeStatus()
            if presentReport {
                presentLocalBenchmarkReport(payload: payload)
            }
            if speakResult {
                speak("本地模型诊断已完成。")
            }
        } catch {
            let message = "本地模型诊断失败：\(error.localizedDescription)"
            diagnosticLogger.event("ios_local_benchmark_failed", data: ["error": error.localizedDescription])
            sendToWeb(type: "error", payload: ["text": message])
            if speakResult {
                speak(message)
            }
        }
    }

    private func makeLocalBenchmarkReport(test: String) -> [String: Any] {
        switch test {
        case "asr": return makeLocalBenchmarkASRReport()
        case "vision": return makeLocalBenchmarkVisionReport()
        case "text": return makeLocalBenchmarkTextReport()
        case "text_suite": return makeLocalBenchmarkTextSuiteReport()
        case "text_inquiry": return makeLocalBenchmarkTextInquiryReport()
        case "tts": return makeLocalBenchmarkTTSReport()
        case "scenario": return makeLocalBenchmarkScenarioReport()
        default: return makeLocalBenchmarkStatusReport()
        }
    }

    private func makeLocalBenchmarkStatusReport() -> [String: Any] {
        let offlineStatus = offlineModelManager.inspect(
            textModel: runtimeStatus.offlineTextModel,
            nativeRuntimeAvailable: localModelRuntime.isReady
        )
        let localASR = localASRModelManager.inspect(runtimeAvailable: localVoskRuntime.isAvailable)
        let localTTS = currentLocalTTSModelStatus()
        let plan = SilverCareLocalRuntimeBundlePlan.from(
            offlineStatus: offlineStatus,
            localASRReady: localASR.modelReady,
            localASRRuntimeAvailable: localASR.runtimeAvailable,
            localTTSModelReady: localTTS.modelReady,
            includeExperimentalTTS: true,
            ttsRuntimeAvailable: localTTS.runtimeAvailable
        )
        var report = baseLocalBenchmarkReport(test: "status")
        report.merge([
            "model_root": offlineStatus.modelDirectory.path,
            "mnn_available": localModelRuntime.isReady,
            "mnn_summary": localModelRuntime.runtimeSummary,
            "mnn_sme2_supported": localModelRuntime.supportsSme2,
            "offline_ready": offlineStatus.ready,
            "offline_status": offlineStatus.detailText,
            "offline": offlineStatus.payload,
            "local_asr_ready": localASR.ready,
            "local_asr_status": localASR.detailText,
            "local_asr": localASR.payload,
            "local_tts_ready": localTTS.ready,
            "local_tts_model_ready": localTTS.modelReady,
            "local_tts_runtime_available": localTTS.runtimeAvailable,
            "local_tts_voice_quality_passed": localTTS.voiceQualityPassed,
            "local_tts_status": localTTS.detailText,
            "local_tts": localTTS.payload,
            "native_camera": nativeCameraDiagnosticPayload(),
            "runtime_warnings": plan.runtimeWarningText,
            "download_summary": plan.downloadSummaryText
        ]) { _, new in new }
        return report
    }

    private func nativeCameraDiagnosticPayload() -> [String: Any] {
        [
            "status": latestCameraStatus,
            "status_text": latestCameraStatusText,
            "error_code": latestCameraErrorCode,
            "running": cameraService.isRunning,
            "preview_visible": cameraPreviewVisible,
            "available": cameraService.canStartCamera,
            "hardware_available": cameraService.hardwareAvailable,
            "authorization_status": cameraService.authorizationStatusLabel
        ]
    }

    private func nativeSpeechDiagnosticPayload() -> [String: Any] {
        [
            "asr_runtime_mode": runtimeStatus.asrRuntimeMode,
            "asr_runtime_label": runtimeStatus.asrRuntimeDisplayName,
            "asr_model": runtimeStatus.asrModel,
            "microphone_authorization_status": microphoneAuthorizationStatusLabel(),
            "recording": dashScopeAudioRecorder.isRecording || localASRAudioRecorder.isRecording,
            "dashscope_recording": dashScopeAudioRecorder.isRecording,
            "local_asr_recording": localASRAudioRecorder.isRecording,
            "pending_image": !pendingSpeechImageDataURL.isEmpty,
            "local_asr_ready": runtimeStatus.localAsrReady,
            "local_asr_status_text": runtimeStatus.localAsrStatusText,
            "local_asr_model_ready": runtimeStatus.localAsrModelReady,
            "local_asr_runtime_available": runtimeStatus.localAsrRuntimeAvailable,
            "local_asr_model_directory": runtimeStatus.localAsrModelDirectory
        ]
    }

    private func nativeTTSDiagnosticPayload() -> [String: Any] {
        [
            "tts_runtime_mode": runtimeStatus.ttsRuntimeMode,
            "tts_runtime_label": runtimeStatus.ttsRuntimeDisplayName,
            "tts_status_text": runtimeStatus.ttsStatusText,
            "system_speaking": ttsService.isSpeaking,
            "native_audio_playback_active": dashScopeSpeechPlayer != nil,
            "dashscope_available": runtimeStatus.hasDashScopeKey,
            "local_tts_ready": runtimeStatus.localTtsReady,
            "local_tts_status_text": runtimeStatus.localTtsStatusText,
            "local_tts_model_ready": runtimeStatus.localTtsModelReady,
            "local_tts_runtime_available": runtimeStatus.localTtsRuntimeAvailable,
            "local_tts_voice_quality_passed": runtimeStatus.localTtsVoiceQualityPassed,
            "local_tts_model_directory": runtimeStatus.localTtsModelDirectory
        ]
    }

    private func microphoneAuthorizationStatusLabel() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .notDetermined:
            return "not_determined"
        case .restricted:
            return "restricted"
        @unknown default:
            return "unknown"
        }
    }

    private func makeLocalBenchmarkASRReport() -> [String: Any] {
        let status = localASRModelManager.inspect(runtimeAvailable: localVoskRuntime.isAvailable)
        var report = baseLocalBenchmarkReport(test: "asr")
        report.merge([
            "ready": status.ready,
            "status": status.detailText,
            "local_asr": status.payload
        ]) { _, new in new }
        guard status.ready else {
            report["success"] = false
            report["error"] = status.shortText
            return report
        }

        let audioFile = localBenchmarkManualAudioFile()
        let audioDescription = describeLocalBenchmarkFile(audioFile)
        let audioReadable = FileManager.default.isReadableFile(atPath: audioFile.path)
        let pcm: Data
        let input: String
        do {
            if audioReadable {
                pcm = try wavPCM16(audioFile)
                input = "manual_test/real_voice.wav, expected 16kHz mono PCM WAV"
            } else {
                pcm = silencePCM(sampleRate: 16_000, durationMs: 3_000)
                input = "3 seconds 16kHz mono silence PCM; no speech accuracy expected"
            }
        } catch {
            report["success"] = false
            report["audio_file"] = audioDescription
            report["error"] = "无法读取本地 ASR benchmark 音频：\(error.localizedDescription)"
            return report
        }
        var transcripts: [String] = []
        let runs = [
            timedBenchmarkRun(name: audioReadable ? "cold_manual_real_voice_vosk" : "cold_load_plus_3s_silence_asr") {
                let transcript = try localVoskRuntime.transcribe(modelDirectory: status.modelDirectory, pcm16: pcm)
                transcripts.append(transcript)
                return transcript
            },
            timedBenchmarkRun(name: audioReadable ? "warm_manual_real_voice_vosk" : "warm_3s_silence_asr") {
                let transcript = try localVoskRuntime.transcribe(modelDirectory: status.modelDirectory, pcm16: pcm)
                transcripts.append(transcript)
                return transcript
            }
        ]
        report["input"] = input
        report["audio_file"] = audioDescription
        report["transcripts"] = transcripts
        report["runs"] = runs
        report["success"] = runs.allSatisfy { ($0["success"] as? Bool) == true }
        return report
    }

    private func makeLocalBenchmarkVisionReport() -> [String: Any] {
        let status = offlineModelManager.inspect(
            textModel: runtimeStatus.offlineTextModel,
            nativeRuntimeAvailable: localModelRuntime.isReady
        )
        var report = baseLocalBenchmarkReport(test: "vision")
        report.merge([
            "ready": status.visionReady,
            "status": status.visionShortText,
            "offline": status.payload
        ]) { _, new in new }
        guard status.visionReady else {
            report["success"] = false
            report["error"] = status.visionShortText
            return report
        }

        let imageDataURL = syntheticRoomImageDataURL()
        let runs = [
            timedBenchmarkRun(name: "cold_synthetic_image_yolo") {
                try localModelRuntime.visionDetectionsJSON(imageDataURL: imageDataURL, role: "damo-yolo-mnn")
            },
            timedBenchmarkRun(name: "warm_synthetic_image_yolo") {
                try localModelRuntime.visionDetectionsJSON(imageDataURL: imageDataURL, role: "damo-yolo-mnn")
            }
        ]
        report["input"] = "generated 640x640 synthetic room-like bitmap"
        report["runs"] = runs
        report["success"] = runs.allSatisfy { ($0["success"] as? Bool) == true }
        return report
    }

    private func makeLocalBenchmarkTextReport() -> [String: Any] {
        let status = offlineModelManager.inspect(
            textModel: runtimeStatus.offlineTextModel,
            nativeRuntimeAvailable: localModelRuntime.isReady
        )
        var report = baseLocalBenchmarkReport(test: "text")
        report.merge([
            "ready": status.ready,
            "status": status.detailText,
            "offline": status.payload,
            "text_model": OfflineModelManifest.cleanTextModel(runtimeStatus.offlineTextModel),
            "tuning": benchmarkTuningJSON()
        ]) { _, new in new }
        guard status.ready else {
            report["success"] = false
            report["error"] = status.shortText
            return report
        }

        let model = OfflineModelManifest.cleanTextModel(runtimeStatus.offlineTextModel)
        let runs = [
            timedBenchmarkRun(name: "cold_qwen_short_json") {
                try localModelRuntime.textJSON(
                    prompt: #"你是适老化居家辅助系统。只输出 JSON：{"reply":"请停下，前方可能有障碍。"}"#,
                    role: model,
                    maxNewTokens: 64,
                    endWith: "}"
                )
            },
            timedBenchmarkRun(name: "warm_qwen_short_json") {
                try localModelRuntime.textJSON(
                    prompt: #"只输出 JSON：{"same":true,"tip":"向右慢慢绕开。"}"#,
                    role: model,
                    maxNewTokens: 48,
                    endWith: "}"
                )
            }
        ]
        report["runs"] = runs
        report["success"] = runs.allSatisfy { ($0["success"] as? Bool) == true }
        return report
    }

    private func makeLocalBenchmarkTextSuiteReport() -> [String: Any] {
        let status = offlineModelManager.inspect(
            textModel: runtimeStatus.offlineTextModel,
            nativeRuntimeAvailable: localModelRuntime.isReady
        )
        var report = baseLocalBenchmarkReport(test: "text_suite")
        report.merge([
            "ready": status.ready,
            "status": status.detailText,
            "offline": status.payload,
            "text_model": OfflineModelManifest.cleanTextModel(runtimeStatus.offlineTextModel),
            "tuning": benchmarkTuningJSON()
        ]) { _, new in new }
        guard status.ready else {
            report["success"] = false
            report["error"] = status.shortText
            return report
        }

        let model = OfflineModelManifest.cleanTextModel(runtimeStatus.offlineTextModel)
        let suiteStarted = ProcessInfo.processInfo.systemUptime
        let cases: [(String, String)] = [
            ("care_chat_night_toilet", "你是银龄智护的离线文本模型。用户是低视力老人。用户说：晚上起来上厕所前，我该注意什么？只输出 JSON：{\"speech\":\"不超过45字的中文语音回复\",\"intent\":\"info\"}。"),
            ("navigation_obstacle_prompt", "你是盲人居家通行助手。画面检测结果：正前方偏左约1.2米有大型障碍，右侧有可通行空间。给用户一句能直接朗读的中文提醒，不要描述颜色，不要超过35字。只输出 JSON：{\"speech\":\"...\",\"intent\":\"nav_check\"}。"),
            ("find_object_asr_correction", "ASR 识别文本可能错误：帮我找到我的晚。离线视觉模型可识别目标列表：碗、杯子、椅子、门、行李箱、背包、手提包、手机。判断用户最可能要找什么。只输出 JSON：{\"target\":\"...\",\"speech\":\"不超过35字中文\"}。"),
            ("fall_confirmation", "传感器检测到疑似摔倒，画面也出现剧烈变化。请生成给老人的确认语音。要先询问是否摔倒，并说明10秒后将发送报警事件。只输出 JSON：{\"speech\":\"...\",\"intent\":\"fall_confirm\"}。"),
            ("medication_and_care_record", "用户：我是糖尿病患者，今天晚饭后可能忘记吃药了，怎么办？你不能替代医生诊断，要给安全建议并建议记录给家属复核。只输出 JSON：{\"speech\":\"不超过60字中文\",\"intent\":\"care_advice\"}。"),
            ("smart_refresh_semantic_compare", "上一次导航：前方一米有大型障碍，请向右慢慢绕开。新导航：前方约一米仍有大型障碍，右侧可绕行。判断语义是否一致。只输出 JSON：{\"same\":true或false,\"reason\":\"不超过20字中文\"}。")
        ]
        let runs = cases.map { name, prompt -> [String: Any] in
            var run = timedBenchmarkRun(name: name) {
                try localModelRuntime.textJSON(prompt: prompt, role: model, maxNewTokens: 96, endWith: "}")
            }
            run["prompt_chars"] = prompt.count
            run["max_new_tokens"] = 96
            return run
        }
        report["runs"] = runs
        report["total_elapsed_ms"] = elapsedMilliseconds(since: suiteStarted)
        report["success"] = runs.allSatisfy { ($0["success"] as? Bool) == true }
        return report
    }

    private func makeLocalBenchmarkTextInquiryReport() -> [String: Any] {
        let status = offlineModelManager.inspect(
            textModel: runtimeStatus.offlineTextModel,
            nativeRuntimeAvailable: localModelRuntime.isReady
        )
        var report = baseLocalBenchmarkReport(test: "text_inquiry")
        report.merge([
            "ready": status.ready,
            "status": status.detailText,
            "offline": status.payload
        ]) { _, new in new }
        guard status.ready else {
            report["success"] = false
            report["error"] = status.shortText
            return report
        }

        let imageDataURL = syntheticRoomImageDataURL()
        let runs = [
            runProcessorBenchmarkScenario(imageDataURL: imageDataURL, transcript: "你好你可以说什么你提做什么", expectedIntent: "info", expectedSpeechContains: "看路", name: "cold_capability_text_inquiry"),
            runProcessorBenchmarkScenario(imageDataURL: imageDataURL, transcript: "帮我看看前方有没有障碍物", expectedIntent: "nav_check", expectedSpeechContains: "前方", name: "warm_navigation_text_inquiry"),
            runProcessorBenchmarkScenario(imageDataURL: imageDataURL, transcript: "帮我找到我的碗", expectedIntent: "search", expectedSpeechContains: "碗", name: "warm_search_bowl_text_inquiry"),
            runProcessorBenchmarkScenario(imageDataURL: imageDataURL, transcript: "帮我找到血压计", expectedIntent: "info", expectedSpeechContains: "不在当前离线视觉", name: "warm_unsupported_target_text_inquiry")
        ]
        report["runs"] = runs
        report["success"] = runs.allSatisfy {
            ($0["success"] as? Bool) == true && ($0["semantic_ok"] as? Bool) == true
        }
        return report
    }

    private func makeLocalBenchmarkTTSReport() -> [String: Any] {
        let status = currentLocalTTSModelStatus()
        var report = baseLocalBenchmarkReport(test: "tts")
        report.merge([
            "ready": status.ready,
            "model_ready": status.modelReady,
            "runtime_available": status.runtimeAvailable,
            "voice_quality_passed": status.voiceQualityPassed,
            "status": status.detailText,
            "local_tts": status.payload,
            "skipped": !status.ready
        ]) { _, new in new }
        guard status.ready else {
            report["success"] = false
            report["error"] = status.shortText
            report["reason"] = "iOS 已实现本地 MNN TTS 模型检查和下载准备；真实合成仍等待 iOS MNN TTS runtime 与可懂度验收。"
            return report
        }

        let cacheDirectory = localBenchmarkTTSOutputDirectory()
        let modelDirectory = status.modelDirectory
        let runs = [
            timedLocalTTSBenchmarkRun(
                name: "cold_local_mnn_tts_wav",
                modelDirectory: modelDirectory,
                cacheDirectory: cacheDirectory,
                text: "银龄智护本地朗读测试。前方一米有障碍，请慢慢向右绕行。"
            ),
            timedLocalTTSBenchmarkRun(
                name: "warm_local_mnn_tts_wav",
                modelDirectory: modelDirectory,
                cacheDirectory: cacheDirectory,
                text: "如果你听到这句话，说明本地离线文字转语音已经完成合成。"
            )
        ]
        let success = runs.allSatisfy { ($0["success"] as? Bool) == true }
        report["input"] = "two short Chinese safety prompts"
        report["cache_dir"] = cacheDirectory.path
        report["runs"] = runs
        report["success"] = success
        report["skipped"] = false
        report["reason"] = success
            ? "本地 MNN TTS 已完成 WAV 合成；仍需人工试听确认可懂度后才能作为主朗读方案。"
            : "本地 MNN TTS Runtime 已声明 ready，但合成 benchmark 未全部成功。"
        if !success {
            report["error"] = runs
                .compactMap { $0["error"] as? String }
                .joined(separator: "; ")
        }
        return report
    }

    private func makeLocalBenchmarkScenarioReport() -> [String: Any] {
        var report = baseLocalBenchmarkReport(test: "scenario")
        let inputDirectory = localBenchmarkManualTestDirectory()
        let audioFile = localBenchmarkManualAudioFile()
        let imageFile = localBenchmarkManualImageFile()
        report["input_dir"] = inputDirectory.path
        report["audio_file"] = describeLocalBenchmarkFile(audioFile)
        report["image_file"] = describeLocalBenchmarkFile(imageFile)
        guard FileManager.default.isReadableFile(atPath: audioFile.path),
              FileManager.default.isReadableFile(atPath: imageFile.path) else {
            report["success"] = false
            report["error"] = "manual_test/real_voice.wav or manual_test/real_scene.jpg is missing"
            return report
        }

        let offlineStatus = offlineModelManager.inspect(
            textModel: runtimeStatus.offlineTextModel,
            nativeRuntimeAvailable: localModelRuntime.isReady
        )
        let asrStatus = localASRModelManager.inspect(runtimeAvailable: localVoskRuntime.isAvailable)
        report["offline_ready"] = offlineStatus.ready
        report["local_asr_ready"] = asrStatus.ready
        report["offline_status"] = offlineStatus.detailText
        report["local_asr_status"] = asrStatus.detailText
        report["offline"] = offlineStatus.payload
        report["local_asr"] = asrStatus.payload

        var transcript = ""
        var asrSucceeded = false
        if asrStatus.ready {
            let asrRun = timedBenchmarkRun(name: "manual_real_voice_vosk") {
                transcript = try localVoskRuntime.transcribe(modelDirectory: asrStatus.modelDirectory, pcm16: wavPCM16(audioFile))
                return transcript
            }
            asrSucceeded = (asrRun["success"] as? Bool) == true
            report["asr"] = asrRun
            report["transcript"] = transcript
        } else {
            report["asr_skipped"] = asrStatus.shortText
        }

        let imageDataURL: String?
        do {
            imageDataURL = try benchmarkImageDataURL(file: imageFile)
        } catch {
            imageDataURL = nil
            report["image_load_error"] = error.localizedDescription
        }

        var visionSucceeded = false
        if offlineStatus.visionReady, let imageDataURL {
            let visionRun = timedBenchmarkRun(name: "manual_real_scene_yolo") {
                try localModelRuntime.visionDetectionsJSON(imageDataURL: imageDataURL, role: "damo-yolo-mnn")
            }
            visionSucceeded = (visionRun["success"] as? Bool) == true
            report["vision"] = visionRun
        } else if !offlineStatus.visionReady {
            report["vision_skipped"] = offlineStatus.visionShortText
        } else {
            report["vision_skipped"] = "manual_test/real_scene.jpg could not be loaded"
        }

        if offlineStatus.ready,
           visionSucceeded,
           let imageDataURL,
           !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            report["pipeline"] = runProcessorBenchmarkScenario(
                imageDataURL: imageDataURL,
                transcript: transcript,
                expectedIntent: "",
                expectedSpeechContains: "",
                name: "manual_offline_pipeline"
            )
        } else {
            var skipped: [String] = []
            if !offlineStatus.ready { skipped.append("offline model is not ready") }
            if !visionSucceeded { skipped.append("vision did not run successfully") }
            if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { skipped.append("ASR did not produce a transcript") }
            report["pipeline_skipped"] = skipped.isEmpty ? "manual offline pipeline was not run" : skipped.joined(separator: "; ")
        }
        report["success"] = asrSucceeded && visionSucceeded
        if !asrSucceeded || !visionSucceeded {
            report["error"] = [
                asrSucceeded ? nil : "local ASR component did not succeed",
                visionSucceeded ? nil : "offline vision component did not succeed"
            ].compactMap { $0 }.joined(separator: "; ")
        }
        return report
    }

    private func writeLocalBenchmarkReport(_ report: [String: Any]) throws -> URL {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw SilverCareCoreError.transport("无法找到 iOS Documents 目录。")
        }
        let directory = documents.appendingPathComponent("benchmarks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let test = cleanLocalBenchmarkTest(report["test"] as? String ?? "status")
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let output = directory.appendingPathComponent("local-model-benchmark-\(test)-\(timestamp).json")
        let latest = directory.appendingPathComponent("latest-\(test).json")
        var finalReport = report
        finalReport["output_file"] = output.path
        guard JSONSerialization.isValidJSONObject(finalReport) else {
            throw SilverCareCoreError.invalidJSON("本地模型诊断报告不是合法 JSON。")
        }
        let data = try JSONSerialization.data(withJSONObject: finalReport, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output, options: .atomic)
        try data.write(to: latest, options: .atomic)
        if test == "status" {
            try data.write(to: directory.appendingPathComponent("latest-status.json"), options: .atomic)
        }
        return output
    }

    private func baseLocalBenchmarkReport(test: String) -> [String: Any] {
        [
            "test": test,
            "success": true,
            "timestamp_ms": Int(Date().timeIntervalSince1970 * 1000),
            "device": "\(UIDevice.current.model) \(UIDevice.current.name)",
            "system": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "package": Bundle.main.bundleIdentifier ?? "com.silvercare.aiassistant.ios",
            "ai_runtime_mode": runtimeStatus.aiRuntimeMode,
            "runtime_label": runtimeStatus.runtimeDisplayName,
            "vision_model": runtimeStatus.visionModel,
            "text_model": runtimeStatus.textModel,
            "diagnostic_log_path": diagnosticLogger.latestLogPath,
            "native_camera": nativeCameraDiagnosticPayload(),
            "native_speech": nativeSpeechDiagnosticPayload(),
            "native_tts": nativeTTSDiagnosticPayload()
        ]
    }

    private func cleanLocalBenchmarkTest(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "asr", "vision", "text", "text_suite", "text_inquiry", "tts", "scenario":
            return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        default:
            return "status"
        }
    }

    private func automationLocalBenchmarkTests(arguments: [String]) -> [String] {
        let defaultTests = ["status", "asr", "vision", "text", "text_suite", "text_inquiry", "tts", "scenario"]
        let argumentValue = arguments.enumerated().first { index, value in
            value == "--silvercare-local-benchmark-tests" && arguments.indices.contains(index + 1)
        }.map { arguments[$0.offset + 1] }
        let raw = argumentValue
            ?? ProcessInfo.processInfo.environment["SILVERCARE_IOS_LOCAL_BENCHMARK_TESTS"]
            ?? defaultTests.joined(separator: ",")
        let tests = raw.split(separator: ",")
            .map { cleanLocalBenchmarkTest(String($0)) }
            .filter { !$0.isEmpty }
        let unique = tests.reduce(into: [String]()) { result, test in
            if !result.contains(test) { result.append(test) }
        }
        return unique.isEmpty ? defaultTests : unique
    }

    private func prepareAutomationLocalBenchmarkSeedIfAvailable() {
        let environment = ProcessInfo.processInfo.environment
        let seedDirectoryName = environment["SILVERCARE_IOS_MODEL_SEED_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSeedDirectoryName = (seedDirectoryName?.isEmpty == false) ? seedDirectoryName! : "silvercare_seed"
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let seedDirectory = documents.appendingPathComponent(cleanSeedDirectoryName, isDirectory: true)
        let seedDirectories = [
            seedDirectory,
            seedDirectory.appendingPathComponent(cleanSeedDirectoryName, isDirectory: true)
        ].reduce(into: [URL]()) { result, directory in
            if !result.contains(where: { $0.path == directory.path }) {
                result.append(directory)
            }
        }
        let modelRoot = SilverCareModelPathResolver.automaticModelDirectory(fileManager: fileManager)
        var prepared: [String] = []
        var failures: [String] = []

        let detectorSource = seedDirectories
            .flatMap { directory in
                [
                    directory.appendingPathComponent(OfflineModelManifest.bundledDetectorFile),
                    directory
                        .appendingPathComponent("models", isDirectory: true)
                        .appendingPathComponent(OfflineModelManifest.bundledDetectorFile)
                ]
            }
            .first { fileManager.isReadableFile(atPath: $0.path) }
        if let detectorSource {
            do {
                try fileManager.createDirectory(at: modelRoot, withIntermediateDirectories: true)
                let detectorTarget = modelRoot.appendingPathComponent(OfflineModelManifest.bundledDetectorFile)
                if fileManager.fileExists(atPath: detectorTarget.path) {
                    try fileManager.removeItem(at: detectorTarget)
                }
                try fileManager.copyItem(at: detectorSource, to: detectorTarget)
                prepared.append("damo-yolo")
            } catch {
                failures.append("detector: \(error.localizedDescription)")
            }
        }

        let asrZip = seedDirectories
            .flatMap { directory in
                [
                    directory.appendingPathComponent("\(LocalASRModelManifest.voskChineseDirectory).zip"),
                    directory
                        .appendingPathComponent("models", isDirectory: true)
                        .appendingPathComponent(LocalASRModelManifest.asrDirectory, isDirectory: true)
                        .appendingPathComponent("\(LocalASRModelManifest.voskChineseDirectory).zip")
                ]
            }
            .first { fileManager.isReadableFile(atPath: $0.path) }
        let asrDirectorySource = seedDirectories
            .flatMap { directory in
                [
                    directory.appendingPathComponent(LocalASRModelManifest.voskChineseDirectory, isDirectory: true),
                    directory
                        .appendingPathComponent("models", isDirectory: true)
                        .appendingPathComponent(LocalASRModelManifest.asrDirectory, isDirectory: true)
                        .appendingPathComponent(LocalASRModelManifest.voskChineseDirectory, isDirectory: true)
                ]
            }
            .first { directory in
                var isDirectory = ObjCBool(false)
                return fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
        let asrRoot = modelRoot.appendingPathComponent(LocalASRModelManifest.asrDirectory, isDirectory: true)
        let asrStatus = localASRModelManager.inspect(
            modelRoot: asrRoot,
            runtimeAvailable: localVoskRuntime.isAvailable
        )
        if asrStatus.modelReady {
            prepared.append("vosk-existing")
        } else if let asrZip {
            do {
                try localASRModelManager.extractChineseModelZip(zip: asrZip, modelRoot: asrRoot)
                prepared.append("vosk")
            } catch {
                failures.append("vosk: \(error.localizedDescription)")
            }
        } else if let asrDirectorySource {
            do {
                try fileManager.createDirectory(at: asrRoot, withIntermediateDirectories: true)
                let target = asrRoot.appendingPathComponent(LocalASRModelManifest.voskChineseDirectory, isDirectory: true)
                if asrDirectorySource.path != target.path {
                    if fileManager.fileExists(atPath: target.path) {
                        try fileManager.removeItem(at: target)
                    }
                    try fileManager.copyItem(at: asrDirectorySource, to: target)
                }
                prepared.append("vosk-directory")
            } catch {
                failures.append("vosk: \(error.localizedDescription)")
            }
        }

        diagnosticLogger.event("ios_local_benchmark_seed", data: [
            "seed_directory": seedDirectory.path,
            "seed_directories": seedDirectories.map(\.path),
            "seed_directories_existing": seedDirectories.filter { fileManager.fileExists(atPath: $0.path) }.map(\.path),
            "detector_source": detectorSource?.path ?? "",
            "asr_zip": asrZip?.path ?? "",
            "asr_directory_source": asrDirectorySource?.path ?? "",
            "model_root": modelRoot.path,
            "model_root_exists": fileManager.fileExists(atPath: modelRoot.path),
            "prepared": prepared,
            "failures": failures
        ])
        refreshOfflineModelStatus()
        refreshSpeechRuntimeStatus()
    }

    private func timedBenchmarkRun(name: String, block: () throws -> String) -> [String: Any] {
        let started = ProcessInfo.processInfo.systemUptime
        do {
            let output = try block()
            return [
                "name": name,
                "success": true,
                "elapsed_ms": elapsedMilliseconds(since: started),
                "output_excerpt": benchmarkExcerpt(output)
            ]
        } catch {
            return [
                "name": name,
                "success": false,
                "elapsed_ms": elapsedMilliseconds(since: started),
                "error": error.localizedDescription
            ]
        }
    }

    private func timedLocalTTSBenchmarkRun(
        name: String,
        modelDirectory: URL,
        cacheDirectory: URL,
        text: String
    ) -> [String: Any] {
        let started = ProcessInfo.processInfo.systemUptime
        do {
            let wav = try localTTSRuntime.synthesizeToWav(
                modelDirectory: modelDirectory,
                cacheDirectory: cacheDirectory,
                text: text,
                language: "zh"
            )
            let wavFile = describeLocalBenchmarkFile(wav)
            let size = wavFile["size_bytes"] as? Int64 ?? -1
            guard FileManager.default.isReadableFile(atPath: wav.path), size > 44 else {
                throw SilverCareCoreError.transport("本地 MNN TTS 未生成有效 WAV 音频。")
            }
            return [
                "name": name,
                "success": true,
                "elapsed_ms": elapsedMilliseconds(since: started),
                "output_excerpt": wav.path,
                "prompt_chars": text.count,
                "wav_file": wavFile
            ]
        } catch {
            return [
                "name": name,
                "success": false,
                "elapsed_ms": elapsedMilliseconds(since: started),
                "prompt_chars": text.count,
                "error": error.localizedDescription
            ]
        }
    }

    private func runProcessorBenchmarkScenario(
        imageDataURL: String,
        transcript: String,
        expectedIntent: String,
        expectedSpeechContains: String,
        name: String
    ) -> [String: Any] {
        let started = ProcessInfo.processInfo.systemUptime
        do {
            var benchmarkStatusBuilder = runtimeStatus
            let offlineStatus = offlineModelManager.inspect(
                textModel: runtimeStatus.offlineTextModel,
                nativeRuntimeAvailable: localModelRuntime.isReady
            )
            benchmarkStatusBuilder.aiRuntimeMode = SilverCareRuntimeMode.offlineMNN.rawValue
            benchmarkStatusBuilder.runtimeDisplayName = SilverCareRuntimeMode.offlineMNN.label
            benchmarkStatusBuilder.visionModel = "damo-yolo-mnn"
            benchmarkStatusBuilder.microModel = "damo-yolo-mnn"
            benchmarkStatusBuilder.textModel = OfflineModelManifest.cleanTextModel(runtimeStatus.offlineTextModel)
            benchmarkStatusBuilder.applyOfflineModelStatus(offlineStatus)
            let benchmarkStatus = benchmarkStatusBuilder
            let benchmarkClient = IOSHybridAIClient(
                statusProvider: { benchmarkStatus },
                diagnosticLogger: diagnosticLogger,
                localRuntime: localModelRuntime
            )
            let benchmarkProcessor = SilverCareProcessor(client: benchmarkClient)
            let messages = try benchmarkProcessor.processTextInquiry(imageDataURL: imageDataURL, transcript: transcript)
            let inquiry = messages.first { $0.type == "inquiry_result" }
            let speak = messages.first { $0.type == "speak" }
            let actualIntent = inquiry?.string("intent") ?? ""
            let spoken = speak?.string("text") ?? ""
            let intentOK = expectedIntent.isEmpty || actualIntent == expectedIntent
            let speechOK = expectedSpeechContains.isEmpty || spoken.contains(expectedSpeechContains)
            return [
                "name": name,
                "success": true,
                "semantic_ok": intentOK && speechOK,
                "expected_intent": expectedIntent,
                "actual_intent": actualIntent,
                "spoken": spoken,
                "elapsed_ms": elapsedMilliseconds(since: started),
                "input_transcript": transcript,
                "messages": messages.map { ["type": $0.type, "payload": $0.payload] }
            ]
        } catch {
            return [
                "name": name,
                "success": false,
                "semantic_ok": false,
                "elapsed_ms": elapsedMilliseconds(since: started),
                "error": error.localizedDescription
            ]
        }
    }

    private func benchmarkTuningJSON() -> String {
        let noThink = #""jinja":{"context":{"enable_thinking":false}}"#
        switch runtimeStatus.mnnLlmTuningMode {
        case "performance" where localModelRuntime.supportsSme2:
            return "{\(noThink),\"cpu_sme2_neon_division_ratio\":49,\"cpu_sme_core_num\":2}"
        case "efficiency" where localModelRuntime.supportsSme2:
            return "{\(noThink),\"cpu_sme2_neon_division_ratio\":33,\"cpu_sme_core_num\":1}"
        case "mnn_default":
            return "{\(noThink)}"
        default:
            if localModelRuntime.supportsSme2 {
                return "{\(noThink),\"cpu_sme2_neon_division_ratio\":41,\"cpu_sme_core_num\":2}"
            }
            return "{\(noThink)}"
        }
    }

    private func elapsedMilliseconds(since started: TimeInterval) -> Int {
        Int(((ProcessInfo.processInfo.systemUptime - started) * 1000).rounded())
    }

    private func benchmarkExcerpt(_ value: String) -> String {
        let clean = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > 500 else { return clean }
        return String(clean.prefix(500)) + "..."
    }

    private func syntheticRoomImageDataURL() -> String {
        let size = CGSize(width: 640, height: 640)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor(red: 238 / 255, green: 236 / 255, blue: 228 / 255, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 175 / 255, green: 150 / 255, blue: 116 / 255, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 430, width: 640, height: 210))
            UIColor(red: 80 / 255, green: 92 / 255, blue: 70 / 255, alpha: 1).setFill()
            context.fill(CGRect(x: 70, y: 260, width: 160, height: 325))
            UIColor(red: 30 / 255, green: 36 / 255, blue: 45 / 255, alpha: 1).setFill()
            context.fill(CGRect(x: 290, y: 290, width: 140, height: 295))
            UIColor(red: 40 / 255, green: 110 / 255, blue: 210 / 255, alpha: 1).setFill()
            context.fill(CGRect(x: 120, y: 220, width: 380, height: 80))
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 448, y: 58, width: 104, height: 104))
        }
        return "data:image/png;base64,\((image.pngData() ?? Data()).base64EncodedString())"
    }

    private func silencePCM(sampleRate: Int, durationMs: Int) -> Data {
        let samples = max(1, sampleRate * durationMs / 1000)
        return Data(repeating: 0, count: samples * 2)
    }

    private func describeLocalBenchmarkFile(_ file: URL) -> [String: Any] {
        let manager = FileManager.default
        let readable = manager.isReadableFile(atPath: file.path)
        let size = ((try? manager.attributesOfItem(atPath: file.path)[.size]) as? NSNumber)?.int64Value ?? -1
        return [
            "path": file.path,
            "exists": manager.fileExists(atPath: file.path),
            "readable": readable,
            "size_bytes": readable ? size : -1
        ]
    }

    private func localBenchmarkManualTestDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("manual_test", isDirectory: true)
    }

    private func localBenchmarkTTSOutputDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documents
            .appendingPathComponent("benchmarks", isDirectory: true)
            .appendingPathComponent("local_tts_wav", isDirectory: true)
    }

    private func localBenchmarkManualAudioFile() -> URL {
        localBenchmarkManualTestDirectory().appendingPathComponent("real_voice.wav")
    }

    private func localBenchmarkManualImageFile() -> URL {
        localBenchmarkManualTestDirectory().appendingPathComponent("real_scene.jpg")
    }

    private func benchmarkImageDataURL(file: URL) throws -> String {
        let data = try Data(contentsOf: file)
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    private func wavPCM16(_ file: URL) throws -> Data {
        let bytes = try Data(contentsOf: file)
        guard bytes.count >= 20 else {
            throw SilverCareCoreError.invalidJSON("WAV data chunk not found")
        }
        var offset = 12
        while offset + 8 <= bytes.count {
            let chunk = String(data: bytes[offset..<(offset + 4)], encoding: .ascii) ?? ""
            let size = littleEndianInt(bytes, offset + 4)
            let dataOffset = offset + 8
            let next = dataOffset + max(size, 0)
            if chunk == "data", size > 0, dataOffset <= bytes.count {
                return bytes[dataOffset..<min(bytes.count, dataOffset + size)]
            }
            offset = next + (size % 2)
        }
        throw SilverCareCoreError.invalidJSON("WAV data chunk not found")
    }

    private func littleEndianInt(_ data: Data, _ offset: Int) -> Int {
        guard offset + 4 <= data.count else { return 0 }
        return Int(data[offset])
            | (Int(data[offset + 1]) << 8)
            | (Int(data[offset + 2]) << 16)
            | (Int(data[offset + 3]) << 24)
    }

    private func presentLocalBenchmarkReport(payload: [String: Any]) {
        guard let presenter = webView?.window?.rootViewController else { return }
        let output = payload["output_file"] as? String ?? latestLocalBenchmarkPath
        let message = """
        MNN：\(payload["mnn_summary"] as? String ?? localModelRuntime.runtimeSummary)
        离线模型：\(runtimeStatus.offlineStatusText)
        本地 ASR：\(runtimeStatus.localAsrStatusText)
        本地 TTS：实验项，当前不作为主朗读方案

        报告：\(output)
        """
        let alert = UIAlertController(title: "本地模型诊断", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "发送状态到页面", style: .default) { [weak self] _ in
            self?.sendToWeb(type: "local_benchmark_result", payload: payload)
        })
        alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
        present(alert, from: presenter)
    }

    private func startNativeFallMonitoringIfNeeded() {
        guard runtimeStatus.fallDetectionEnabled else {
            motionFallMonitor.stop()
            return
        }
        motionFallMonitor.onConfirmationNeeded = { [weak self] evidence in
            Task { @MainActor in
                self?.presentNativeFallConfirmation(evidence)
            }
        }
        motionFallMonitor.start()
    }

    private func presentNativeFallConfirmation(_ evidence: NativeFallEvidence) {
        guard nativeFallAlert == nil else { return }
        nativeFallEvidenceJSON = jsonString(evidence.payload)
        nativeFallCountdownLeft = 10
        diagnosticLogger.event("ios_native_fall_confirmation", data: evidence.payload)

        let alert = UIAlertController(
            title: "疑似摔倒",
            message: "检测到手机冲击。若你没事，请点击“我没事”。\(nativeFallCountdownLeft) 秒后将模拟报警。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "我没事", style: .cancel) { [weak self] _ in
            Task { @MainActor in
                self?.cancelNativeFallConfirmation()
            }
        })
        alert.addAction(UIAlertAction(title: "立即报警", style: .destructive) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.triggerFallAlarm(self.nativeFallEvidenceJSON)
            }
        })
        nativeFallAlert = alert
        webView?.window?.rootViewController?.present(alert, animated: true)
        speak("检测到疑似摔倒。如果你没有摔倒，请点击我没事。10 秒后将模拟报警。")

        nativeFallCountdownTimer?.invalidate()
        nativeFallCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.nativeFallCountdownLeft -= 1
                self.nativeFallAlert?.message = "检测到手机冲击。若你没事，请点击“我没事”。\(self.nativeFallCountdownLeft) 秒后将模拟报警。"
                if self.nativeFallCountdownLeft <= 0 {
                    timer.invalidate()
                    self.triggerFallAlarm(self.nativeFallEvidenceJSON)
                }
            }
        }
    }

    private func cancelNativeFallConfirmation() {
        nativeFallCountdownTimer?.invalidate()
        nativeFallCountdownTimer = nil
        nativeFallAlert = nil
        speak("已取消报警。")
    }

    private func jsonString(_ payload: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    private func trimTrailingSlash(_ text: String) -> String {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while clean.hasSuffix("/") {
            clean.removeLast()
        }
        return clean
    }

    private func present(_ alert: UIAlertController, from presenter: UIViewController) {
        if let popover = alert.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.maxY - 24,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(alert, animated: true)
    }
}

struct SilverCareRuntimeStatus: Sendable {
    private static let defaults = UserDefaults.standard

    var aiRuntimeMode = SilverCareRuntimeMode.dashScope.rawValue
    var runtimeDisplayName = SilverCareRuntimeMode.dashScope.label
    var offlineReady = false
    var offlineStatusText = "端侧离线模型未就绪：MNN Native Runtime、模型目录不可读、Qwen3-4B-Instruct-2507-MNN/config.json、DAMO-YOLO .mnn"
    var offlineModelDirectory = ""
    var offlineMissing: [String] = []
    var offlineDirectoryReadable = false
    var offlineTextReady = false
    var offlineYoloReady = false
    var offlineNativeRuntimeAvailable = false
    var dashScopeAPIKey = ""
    var compatibleBaseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    var apiBaseURL = "https://dashscope.aliyuncs.com/api/v1"
    static let defaultDashScopeVisionModel = "qwen3-vl-flash"
    static let defaultDashScopeTextModel = "qwen-plus"
    var visionModel = defaultDashScopeVisionModel
    var textModel = defaultDashScopeTextModel
    var offlineTextModel = OfflineModelManifest.textModel4B
    var microModel = defaultDashScopeVisionModel
    var asrRuntimeMode = SilverCareASRRuntimeMode.dashScope.rawValue
    var asrRuntimeDisplayName = SilverCareASRRuntimeMode.dashScope.label
    var asrModel = "qwen3-asr-flash"
    var localAsrReady = false
    var localAsrStatusText = "联网 ASR 需要先填写 DashScope Key。"
    var localAsrModelDirectory = ""
    var localAsrMissing: [String] = []
    var localAsrModelReady = false
    var localAsrRuntimeAvailable = false
    var ttsRuntimeMode = SilverCareTTSRuntimeMode.dashScope.rawValue
    var ttsRuntimeDisplayName = SilverCareTTSRuntimeMode.dashScope.label
    var ttsStatusText = "联网 DashScope TTS 需要先填写 Key。"
    var localTtsReady = false
    var localTtsStatusText = "本地 MNN TTS 未就绪：TTS 模型目录不可读、bert-vits2-mnn"
    var localTtsModelDirectory = ""
    var localTtsMissing: [String] = []
    var localTtsModelReady = false
    var localTtsRuntimeAvailable = false
    var localTtsVoiceQualityPassed = false
    var captionsEnabled = true
    var voiceFirstEnabled = true
    var fallDetectionEnabled = true
    var navigationRefreshMode = "auto"
    var navigationRefreshIntervalMs = 3000
    var smartNavigationRefreshEnabled = false
    var mnnLlmTuningMode = "auto"
    var mnnLlmTuningDisplayName = "自动"
    var mnnRuntimeSummary = "iOS MNN Runtime 未加载"

    static func load() -> SilverCareRuntimeStatus {
        var status = SilverCareRuntimeStatus()
        migrateStaleLocalRuntimeModesToDashScopeIfNeeded()
        let allowLocalRuntime = ProcessInfo.processInfo.environment["SILVERCARE_IOS_ALLOW_LOCAL_RUNTIME"] == "1"
        let forceDashScope = ProcessInfo.processInfo.environment["SILVERCARE_IOS_FORCE_DASHSCOPE_RUNTIME"] == "1"
            || !allowLocalRuntime
        let mode = SilverCareRuntimeMode.from(defaults.string(forKey: "ios_ai_runtime_mode") ?? status.aiRuntimeMode)
        let effectiveMode: SilverCareRuntimeMode = forceDashScope ? .dashScope : mode
        status.aiRuntimeMode = effectiveMode.rawValue
        status.runtimeDisplayName = effectiveMode.label
        let savedKey = defaults.string(forKey: "ios_dashscope_api_key")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let environmentKey = ProcessInfo.processInfo.environment["DASHSCOPE_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bundledKey = bundledDashScopeAPIKey()
        status.dashScopeAPIKey = firstNonEmpty([savedKey, environmentKey, bundledKey])
        status.compatibleBaseURL = defaults.string(forKey: "ios_compatible_base_url") ?? status.compatibleBaseURL
        status.apiBaseURL = defaults.string(forKey: "ios_api_base_url") ?? status.apiBaseURL
        status.visionModel = normalizedDashScopeVisionModel(defaults.string(forKey: "ios_vision_model") ?? status.visionModel)
        status.textModel = defaults.string(forKey: "ios_text_model") ?? status.textModel
        status.offlineTextModel = OfflineModelManifest.cleanTextModel(
            defaults.string(forKey: "ios_offline_text_model") ?? status.offlineTextModel
        )
        status.microModel = normalizedDashScopeVisionModel(defaults.string(forKey: "ios_micro_model") ?? status.microModel)
        if defaults.string(forKey: "ios_vision_model") != status.visionModel {
            defaults.set(status.visionModel, forKey: "ios_vision_model")
        }
        if defaults.string(forKey: "ios_micro_model") != status.microModel {
            defaults.set(status.microModel, forKey: "ios_micro_model")
        }
        let asrMode = SilverCareASRRuntimeMode.from(defaults.string(forKey: "ios_asr_runtime_mode") ?? status.asrRuntimeMode)
        let effectiveASRMode: SilverCareASRRuntimeMode = forceDashScope ? .dashScope : asrMode
        status.asrRuntimeMode = effectiveASRMode.rawValue
        status.asrRuntimeDisplayName = effectiveASRMode.label
        status.asrModel = Self.normalizedDashScopeASRModel(defaults.string(forKey: "ios_asr_model") ?? status.asrModel)
        if defaults.string(forKey: "ios_asr_model") != status.asrModel {
            defaults.set(status.asrModel, forKey: "ios_asr_model")
        }
        let ttsMode = SilverCareTTSRuntimeMode.from(defaults.string(forKey: "ios_tts_runtime_mode") ?? status.ttsRuntimeMode)
        let effectiveTTSMode: SilverCareTTSRuntimeMode = forceDashScope ? .dashScope : ttsMode
        status.ttsRuntimeMode = effectiveTTSMode.rawValue
        status.ttsRuntimeDisplayName = effectiveTTSMode.label
        status.captionsEnabled = defaults.bool(forKey: "ios_captions_enabled", default: status.captionsEnabled)
        status.voiceFirstEnabled = defaults.bool(forKey: "ios_voice_first_enabled", default: status.voiceFirstEnabled)
        status.fallDetectionEnabled = defaults.bool(forKey: "ios_fall_detection_enabled", default: status.fallDetectionEnabled)
        status.navigationRefreshMode = defaults.string(forKey: "ios_navigation_refresh_mode") ?? status.navigationRefreshMode
        let interval = defaults.integer(forKey: "ios_navigation_refresh_interval_ms")
        if interval > 0 { status.navigationRefreshIntervalMs = interval }
        status.smartNavigationRefreshEnabled = defaults.bool(
            forKey: "ios_smart_navigation_refresh_enabled",
            default: status.smartNavigationRefreshEnabled
        )
        status.mnnLlmTuningMode = defaults.string(forKey: "ios_mnn_llm_tuning_mode") ?? status.mnnLlmTuningMode
        status.mnnLlmTuningDisplayName = Self.mnnTuningDisplayName(for: status.mnnLlmTuningMode)
        return status
    }

    private static func migrateStaleLocalRuntimeModesToDashScopeIfNeeded() {
        let migrationKey = "ios_cloud_first_runtime_migration_v1"
        guard !defaults.bool(forKey: migrationKey) else { return }
        guard ProcessInfo.processInfo.environment["SILVERCARE_IOS_SKIP_CLOUD_FIRST_MIGRATION"] != "1" else { return }

        if let savedMode = defaults.string(forKey: "ios_ai_runtime_mode"),
           SilverCareRuntimeMode.from(savedMode) != .dashScope {
            defaults.set(SilverCareRuntimeMode.dashScope.rawValue, forKey: "ios_ai_runtime_mode")
        }
        if let savedASRMode = defaults.string(forKey: "ios_asr_runtime_mode"),
           SilverCareASRRuntimeMode.from(savedASRMode) != .dashScope {
            defaults.set(SilverCareASRRuntimeMode.dashScope.rawValue, forKey: "ios_asr_runtime_mode")
        }
        if let savedTTSMode = defaults.string(forKey: "ios_tts_runtime_mode"),
           SilverCareTTSRuntimeMode.from(savedTTSMode) != .dashScope {
            defaults.set(SilverCareTTSRuntimeMode.dashScope.rawValue, forKey: "ios_tts_runtime_mode")
        }
        defaults.set(true, forKey: migrationKey)
    }

    static func bundledDashScopeAPIKey(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: "SilverCarePrivateConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any],
              let key = dictionary["DASHSCOPE_API_KEY"] as? String
        else {
            return ""
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstNonEmpty(_ values: [String]) -> String {
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private static func normalizedDashScopeASRModel(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "qwen-audio-asr" {
            return "qwen3-asr-flash"
        }
        return trimmed
    }

    private static func normalizedDashScopeVisionModel(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "qwen-vl-plus" {
            return defaultDashScopeVisionModel
        }
        return trimmed
    }

    func save() {
        Self.defaults.set(aiRuntimeMode, forKey: "ios_ai_runtime_mode")
        Self.defaults.set(dashScopeAPIKey, forKey: "ios_dashscope_api_key")
        Self.defaults.set(compatibleBaseURL, forKey: "ios_compatible_base_url")
        Self.defaults.set(apiBaseURL, forKey: "ios_api_base_url")
        Self.defaults.set(visionModel, forKey: "ios_vision_model")
        Self.defaults.set(textModel, forKey: "ios_text_model")
        Self.defaults.set(OfflineModelManifest.cleanTextModel(offlineTextModel), forKey: "ios_offline_text_model")
        Self.defaults.set(microModel, forKey: "ios_micro_model")
        Self.defaults.set(asrRuntimeMode, forKey: "ios_asr_runtime_mode")
        Self.defaults.set(asrModel, forKey: "ios_asr_model")
        Self.defaults.set(ttsRuntimeMode, forKey: "ios_tts_runtime_mode")
        Self.defaults.set(captionsEnabled, forKey: "ios_captions_enabled")
        Self.defaults.set(voiceFirstEnabled, forKey: "ios_voice_first_enabled")
        Self.defaults.set(fallDetectionEnabled, forKey: "ios_fall_detection_enabled")
        Self.defaults.set(navigationRefreshMode, forKey: "ios_navigation_refresh_mode")
        Self.defaults.set(navigationRefreshIntervalMs, forKey: "ios_navigation_refresh_interval_ms")
        Self.defaults.set(smartNavigationRefreshEnabled, forKey: "ios_smart_navigation_refresh_enabled")
        Self.defaults.set(mnnLlmTuningMode, forKey: "ios_mnn_llm_tuning_mode")
    }

    var hasDashScopeKey: Bool {
        !dashScopeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var offlineTextModelLabel: String {
        OfflineModelManifest.textModelLabel(offlineTextModel)
    }

    static func mnnTuningDisplayName(for mode: String) -> String {
        switch mode {
        case "performance": return "SME2 性能优先"
        case "efficiency": return "SME2 省电稳定"
        case "mnn_default": return "MNN 默认"
        default: return "SME2 自动调优"
        }
    }

    mutating func applyOfflineModelStatus(_ status: OfflineModelStatus) {
        offlineReady = status.ready
        offlineStatusText = status.shortText
        offlineModelDirectory = status.modelDirectory.path
        offlineMissing = status.missing
        offlineDirectoryReadable = status.directoryReadable
        offlineTextReady = status.textReady
        offlineYoloReady = status.yoloReady
        offlineNativeRuntimeAvailable = status.nativeRuntimeAvailable
        offlineTextModel = status.textModel
    }

    mutating func applyLocalASRModelStatus(_ status: LocalASRModelStatus) {
        localAsrReady = status.ready
        localAsrStatusText = status.shortText
        localAsrModelDirectory = status.modelDirectory.path
        localAsrMissing = status.missing
        localAsrModelReady = status.modelReady
        localAsrRuntimeAvailable = status.runtimeAvailable
    }

    mutating func applyLocalTTSModelStatus(_ status: LocalTTSModelStatus) {
        localTtsReady = status.ready
        localTtsStatusText = status.shortText
        localTtsModelDirectory = status.modelDirectory.path
        localTtsMissing = status.missing
        localTtsModelReady = status.modelReady
        localTtsRuntimeAvailable = status.runtimeAvailable
        localTtsVoiceQualityPassed = status.voiceQualityPassed
    }

    var payload: [String: Any] {
        [
            "ai_runtime_mode": aiRuntimeMode,
            "runtime_label": runtimeDisplayName,
            "offline_ready": offlineReady,
            "offline_status_text": offlineStatusText,
            "offline_model_directory": offlineModelDirectory,
            "offline_missing": offlineMissing,
            "offline_directory_readable": offlineDirectoryReadable,
            "offline_text_ready": offlineTextReady,
            "offline_yolo_ready": offlineYoloReady,
            "offline_native_runtime_available": offlineNativeRuntimeAvailable,
            "has_dashscope_key": hasDashScopeKey,
            "compatible_base_url": compatibleBaseURL,
            "api_base_url": apiBaseURL,
            "vision_model": visionModel,
            "text_model": textModel,
            "offline_text_model": offlineTextModel,
            "offline_text_model_label": offlineTextModelLabel,
            "micro_model": microModel,
            "asr_runtime_mode": asrRuntimeMode,
            "asr_runtime_label": asrRuntimeDisplayName,
            "asr_model": asrModel,
            "local_asr_ready": localAsrReady,
            "local_asr_status_text": localAsrStatusText,
            "local_asr_model_directory": localAsrModelDirectory,
            "local_asr_missing": localAsrMissing,
            "local_asr_model_ready": localAsrModelReady,
            "local_asr_runtime_available": localAsrRuntimeAvailable,
            "tts_runtime_mode": ttsRuntimeMode,
            "tts_runtime_label": ttsRuntimeDisplayName,
            "tts_status_text": ttsStatusText,
            "local_tts_ready": localTtsReady,
            "local_tts_status_text": localTtsStatusText,
            "local_tts_model_directory": localTtsModelDirectory,
            "local_tts_missing": localTtsMissing,
            "local_tts_model_ready": localTtsModelReady,
            "local_tts_runtime_available": localTtsRuntimeAvailable,
            "local_tts_voice_quality_passed": localTtsVoiceQualityPassed,
            "captions_enabled": captionsEnabled,
            "voice_first_enabled": voiceFirstEnabled,
            "fall_detection_enabled": fallDetectionEnabled,
            "navigation_refresh_mode": navigationRefreshMode,
            "navigation_refresh_interval_ms": navigationRefreshIntervalMs,
            "smart_navigation_refresh_enabled": smartNavigationRefreshEnabled,
            "mnn_llm_tuning_mode": mnnLlmTuningMode,
            "mnn_llm_tuning_label": mnnLlmTuningDisplayName,
            "mnn_runtime_summary": mnnRuntimeSummary
        ]
    }

    var offlineDetailText: String {
        [
            offlineStatusText,
            "",
            "模型目录：\(offlineModelDirectory.isEmpty ? "未设置" : offlineModelDirectory)",
            "离线文本模型：\(offlineTextModelLabel)",
            "文本模型：\(offlineTextReady ? "已找到 config.json" : "未找到 config.json")",
            "DAMO-YOLO：\(offlineYoloReady ? "已找到 .mnn 模型" : "未找到 .mnn 模型")",
            "MNN Native Runtime：\(offlineNativeRuntimeAvailable ? "已加载" : "未加载 iOS MNN runtime")"
        ].joined(separator: "\n")
    }
}

private extension UserDefaults {
    func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        object(forKey: key) == nil ? defaultValue : bool(forKey: key)
    }
}
