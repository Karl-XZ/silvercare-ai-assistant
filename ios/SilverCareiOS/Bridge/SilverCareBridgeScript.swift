import Foundation

enum SilverCareBridgeScript {
    static func make(runtimeJSON: String) -> String {
        """
          (() => {
            window.SILVERCARE_IOS_RUNTIME = \(runtimeJSON);
            const getRuntime = () => window.SILVERCARE_IOS_RUNTIME || {};
            const syncNativeCameraClass = () => {
              const runtime = getRuntime();
              const nativeCameraMode = runtime.nativeCameraAvailable === true
                || runtime.nativeCameraRunning === true
                || runtime.nativeCameraPreviewVisible === true;
              document.documentElement.classList.toggle('silvercare-ios-native-camera', nativeCameraMode);
            };
            window.SILVERCARE_SYNC_IOS_NATIVE_CAMERA_CLASS = syncNativeCameraClass;
            syncNativeCameraClass();
          const post = (method, args = []) => {
            try {
              window.webkit?.messageHandlers?.silverCare?.postMessage({ method, args });
            } catch (error) {
              console.error('SilverCare iOS bridge error', error);
            }
          };
          window.AndroidSilverCare = {
            isStandalone: () => true,
            hasDashScopeKey: () => Boolean(getRuntime().hasDashScopeKey),
            diagnosticLogPath: () => getRuntime().diagnosticLogPath || '',
            diagnosticEvent: (event, dataJson) => post('diagnosticEvent', [event, dataJson]),
            aiRuntimeMode: () => getRuntime().aiRuntimeMode || 'dashscope',
            runtimeDisplayName: () => getRuntime().runtimeDisplayName || '联网 DashScope',
            isOfflineRuntime: () => (getRuntime().aiRuntimeMode || 'dashscope') === 'offline_mnn',
            offlineModelReady: () => Boolean(getRuntime().offlineModelReady),
            offlineStatusText: () => getRuntime().offlineStatusText || 'iOS 端侧模型尚未完成绑定',
            offlineModelDirectory: () => getRuntime().offlineModelDirectory || '',
            offlineMissing: () => Array.isArray(getRuntime().offlineMissing) ? getRuntime().offlineMissing : [],
            offlineDirectoryReadable: () => Boolean(getRuntime().offlineDirectoryReadable),
            offlineTextModelReady: () => Boolean(getRuntime().offlineTextModelReady),
            offlineYoloModelReady: () => Boolean(getRuntime().offlineYoloModelReady),
            offlineNativeRuntimeAvailable: () => Boolean(getRuntime().offlineNativeRuntimeAvailable),
            localAsrReady: () => Boolean(getRuntime().localAsrReady),
            localAsrEnabled: () => (getRuntime().asrRuntimeMode || 'dashscope') === 'local_vosk',
            localAsrStatusText: () => getRuntime().localAsrStatusText || '联网 ASR 需要 DashScope Key',
            localAsrModelDirectory: () => getRuntime().localAsrModelDirectory || '',
            localAsrMissing: () => Array.isArray(getRuntime().localAsrMissing) ? getRuntime().localAsrMissing : [],
            localAsrModelReady: () => Boolean(getRuntime().localAsrModelReady),
            localAsrRuntimeAvailable: () => Boolean(getRuntime().localAsrRuntimeAvailable),
            asrRuntimeMode: () => getRuntime().asrRuntimeMode || 'dashscope',
            asrRuntimeDisplayName: () => getRuntime().asrRuntimeDisplayName || '联网 DashScope',
            ttsRuntimeMode: () => getRuntime().ttsRuntimeMode || 'dashscope',
            ttsRuntimeDisplayName: () => getRuntime().ttsRuntimeDisplayName || '联网 DashScope',
            ttsStatusText: () => getRuntime().ttsStatusText || '自动兜底：iOS 系统 TTS 已就绪',
            localTtsReady: () => Boolean(getRuntime().localTtsReady),
            localTtsStatusText: () => getRuntime().localTtsStatusText || '本地 MNN TTS 未就绪',
            localTtsModelDirectory: () => getRuntime().localTtsModelDirectory || '',
            localTtsMissing: () => Array.isArray(getRuntime().localTtsMissing) ? getRuntime().localTtsMissing : [],
            localTtsModelReady: () => Boolean(getRuntime().localTtsModelReady),
            localTtsRuntimeAvailable: () => Boolean(getRuntime().localTtsRuntimeAvailable),
            localTtsVoiceQualityPassed: () => Boolean(getRuntime().localTtsVoiceQualityPassed),
            captionsEnabled: () => getRuntime().captionsEnabled !== false,
            navigationRefreshMode: () => getRuntime().navigationRefreshMode || 'auto',
            navigationRefreshDisplayName: () => (getRuntime().navigationRefreshMode === 'manual' ? '手动刷新' : '自动刷新'),
            navigationRefreshIntervalMs: () => Number(getRuntime().navigationRefreshIntervalMs || 3000),
            smartNavigationRefreshEnabled: () => Boolean(getRuntime().smartNavigationRefreshEnabled),
            mnnLlmTuningMode: () => getRuntime().mnnLlmTuningMode || 'auto',
            mnnLlmTuningDisplayName: () => getRuntime().mnnLlmTuningDisplayName || '自动',
            mnnSme2Supported: () => Boolean(getRuntime().mnnSme2Supported),
            mnnRuntimeSummary: () => getRuntime().mnnRuntimeSummary || 'iOS MNN Runtime 未加载',
            localBenchmarkPath: () => getRuntime().localBenchmarkPath || '',
            isFallDetectionEnabled: () => getRuntime().fallDetectionEnabled !== false,
            isVoiceFirstEnabled: () => getRuntime().voiceFirstEnabled !== false,
            nativeCameraAvailable: () => Boolean(getRuntime().nativeCameraAvailable),
            nativeCameraRunning: () => Boolean(getRuntime().nativeCameraRunning),
            nativeCameraPreviewVisible: () => Boolean(getRuntime().nativeCameraPreviewVisible),
            nativeCameraStatus: () => getRuntime().nativeCameraStatus || 'idle',
            nativeCameraStatusText: () => getRuntime().nativeCameraStatusText || '',
            nativeCameraErrorCode: () => getRuntime().nativeCameraErrorCode || '',
            nativeCameraAuthorizationStatus: () => getRuntime().nativeCameraAuthorizationStatus || 'unknown',
            nativeCameraHardwareAvailable: () => getRuntime().nativeCameraHardwareAvailable !== false,
            startCamera: () => post('startCamera'),
            stopCamera: () => post('stopCamera'),
            captureFrame: () => post('captureFrame'),
            sendFrame: (imageDataUrl) => post('sendFrame', [imageDataUrl]),
            sendInquiryData: (imageDataUrl, audioDataUrl) => post('sendInquiryData', [imageDataUrl, audioDataUrl]),
            processTextInquiry: (imageDataUrl, transcript) => post('processTextInquiry', [imageDataUrl, transcript]),
            startSpeechInquiry: (imageDataUrl) => post('startSpeechInquiry', [imageDataUrl]),
            stopSpeechInquiry: () => post('stopSpeechInquiry'),
            speak: (text) => post('speak', [text]),
            triggerFallAlarm: (evidenceJson) => post('triggerFallAlarm', [evidenceJson]),
            openSettings: () => post('openSettings'),
            openRuntimeSettings: () => post('openRuntimeSettings'),
            openAsrSettings: () => post('openAsrSettings'),
            openTtsSettings: () => post('openTtsSettings'),
            switchAllLocal: () => post('switchAllLocal'),
            switchAllCloud: () => post('switchAllCloud'),
            openKeySettings: () => post('openKeySettings'),
            openOfflineModelSettings: () => post('openOfflineModelSettings'),
            prepareOfflineModels: () => post('prepareOfflineModels'),
            prepareLocalTtsModels: () => post('prepareLocalTtsModels'),
            runLocalBenchmark: (test = 'status') => post('runLocalBenchmark', [test])
          };
        })();
        """
    }
}
