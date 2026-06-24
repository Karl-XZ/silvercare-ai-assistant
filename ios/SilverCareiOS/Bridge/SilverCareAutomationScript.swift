import Foundation

enum SilverCareAutomationScript {
    static func make() -> String {
        """
        (() => {
          if (window.__silverCareAutomationInstalled) return;
          window.__silverCareAutomationInstalled = true;

          let lastSignature = '';
          let pending = { value: false };
          const speechHistoryTokens = new Set();
          const speechHistoryTokenNames = new Set([
            'inquiry-needs-navigation',
            'inquiry-recording',
            'speech-listening',
            'speech-submitted',
            'speech-terminal'
          ]);

          const textIncludes = (needle) => {
            const text = document.body?.innerText || '';
            return text.includes(needle);
          };

          const isVisible = (element) => {
            if (!element) return false;
            if (element.getAttribute('aria-hidden') === 'true') return false;
            const style = window.getComputedStyle(element);
            return style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity || '1') > 0;
          };

          const labelFor = (id) => {
            const element = document.getElementById(id);
            return (element?.innerText || element?.textContent || '').trim();
          };

          const commandIds = new Set([
            'toggleCommand',
            'inquiryCommand',
            'detailsCommand',
            'settingsCommand',
            'managementCommand',
            'closeIntelButton'
          ]);

          const closestCommandId = (element) => {
            const command = element?.closest?.('button, [data-action]');
            return commandIds.has(command?.id) ? command.id : '';
          };

          const rectsOverlap = (a, b) => (
            a.left < b.right &&
            a.right > b.left &&
            a.top < b.bottom &&
            a.bottom > b.top
          );

          const centerHitMatches = (id) => {
            const element = document.getElementById(id);
            if (!element || !isVisible(element)) return false;
            const rect = element.getBoundingClientRect();
            if (rect.width < 2 || rect.height < 2) return false;
            const x = Math.min(window.innerWidth - 1, Math.max(1, rect.left + rect.width / 2));
            const y = Math.min(window.innerHeight - 1, Math.max(1, rect.top + rect.height / 2));
            return closestCommandId(document.elementFromPoint(x, y)) === id;
          };

          const captionLayout = () => {
            const panel = document.getElementById('captionPanel');
            const ai = document.getElementById('aiCaption');
            if (!panel || !ai || !isVisible(panel)) return { visible: false };
            const panelRect = panel.getBoundingClientRect();
            const aiRect = ai.getBoundingClientRect();
            const aiStyle = window.getComputedStyle(ai);
            const panelStyle = window.getComputedStyle(panel);
            return {
              visible: true,
              heightOk: panelRect.height >= 104 && panelRect.height <= 150,
              aiInside:
                aiRect.top >= panelRect.top - 1 &&
                aiRect.bottom <= panelRect.bottom + 1 &&
                aiRect.left >= panelRect.left - 1 &&
                aiRect.right <= panelRect.right + 1,
              aiClamped: aiStyle.webkitLineClamp === '2' || aiStyle.getPropertyValue('-webkit-line-clamp') === '2',
              panelNonInteractive: panelStyle.pointerEvents === 'none'
            };
          };

          const mainFeedbackLayout = () => {
            const main = document.getElementById('mainFeedback');
            if (!main) return { present: false, clearOfCommands: true, nonInteractive: true };
            const visible = isVisible(main) && main.classList.contains('visible');
            const mainStyle = window.getComputedStyle(main);
            if (!visible) {
              return {
                present: true,
                visible: false,
                clearOfCommands: true,
                nonInteractive: mainStyle.pointerEvents === 'none'
              };
            }
            const mainRect = main.getBoundingClientRect();
            const clearOfCommands = ['toggleCommand', 'inquiryCommand', 'detailsCommand'].every((id) => {
              const command = document.getElementById(id);
              if (!command || !isVisible(command)) return true;
              return !rectsOverlap(mainRect, command.getBoundingClientRect());
            });
            return {
              present: true,
              visible: true,
              clearOfCommands,
              nonInteractive: mainStyle.pointerEvents === 'none'
            };
          };

          const feedbackState = () => {
            const main = document.getElementById('mainFeedback');
            const user = document.getElementById('userCaption');
            const ai = document.getElementById('aiCaption');
            const mainText = (main?.innerText || main?.textContent || '').trim();
            const userText = (user?.innerText || user?.textContent || '').trim();
            const aiText = (ai?.innerText || ai?.textContent || '').trim();
            const ttsFallback = (text) => /TTS|朗读|语音合成/.test(text || '')
              && /Key|密钥|回退|fallback|无效音频地址/.test(text || '');
            return {
              mainClean: !ttsFallback(mainText),
              userClean: !ttsFallback(userText),
              aiClean: !ttsFallback(aiText),
              mainVisible: isVisible(main),
              mainText,
              userText,
              aiText
            };
          };

          const collect = () => {
            const dashboard = document.getElementById('careDashboard');
            const details = document.getElementById('intelligence-layer');
            const managementVisible = isVisible(dashboard) && dashboard?.classList.contains('visible');
            const detailsVisible = isVisible(details) && details?.classList.contains('visible');
            const statusLabel = labelFor('statusText');
            const toggleLabel = labelFor('toggleCommand');
            const inquiryLabel = labelFor('inquiryCommand');
            const detailsLabel = labelFor('detailsCommand');
            const runtimeSubtitle = labelFor('runtimeSubtitle');
            const native = window.AndroidSilverCare || {};
            const safeNativeString = (name) => {
              try {
                return typeof native[name] === 'function' ? String(native[name]() || '') : '';
              } catch (error) {
                return '';
              }
            };
            const safeNativeBoolean = (name) => {
              try {
                return typeof native[name] === 'function' ? Boolean(native[name]()) : false;
              } catch (error) {
                return false;
              }
            };
            const aiRuntime = safeNativeString('aiRuntimeMode') || (runtimeSubtitle.includes('端侧离线') ? 'offline_mnn' : 'dashscope');
            const asrRuntime = safeNativeString('asrRuntimeMode') || (runtimeSubtitle.includes('本地内置ASR') ? 'local_vosk' : 'dashscope');
            const ttsRuntime = safeNativeString('ttsRuntimeMode') || 'dashscope';
            const cameraStatus = safeNativeString('nativeCameraStatus') || 'idle';
            const cameraAuth = safeNativeString('nativeCameraAuthorizationStatus') || 'unknown';
            const cameraError = safeNativeString('nativeCameraErrorCode') || '';
            const cameraAvailable = safeNativeBoolean('nativeCameraAvailable');
            const cameraHardware = safeNativeBoolean('nativeCameraHardwareAvailable');
            const cameraPreviewVisible = safeNativeBoolean('nativeCameraPreviewVisible');
            const assistantState = window.LONG_TERM_CARE_ASSISTANT?.STATE || {};
            const tokens = [];

            if (textIncludes('银龄智护')) tokens.push('brand');
            if (aiRuntime === 'dashscope') tokens.push('ai-dashscope');
            if (aiRuntime === 'offline_mnn') tokens.push('ai-offline');
            if (asrRuntime === 'dashscope' || runtimeSubtitle.includes('联网ASR')) tokens.push('asr-dashscope');
            if (asrRuntime === 'local_vosk' || runtimeSubtitle.includes('本地内置ASR')) tokens.push('asr-local');
            if (ttsRuntime === 'auto') tokens.push('tts-auto');
            if (ttsRuntime === 'system') tokens.push('tts-system');
            if (ttsRuntime === 'dashscope') tokens.push('tts-dashscope');
            if (ttsRuntime === 'local_mnn') tokens.push('tts-local-mnn');
            if (ttsRuntime || /朗读|TTS/i.test(runtimeSubtitle)) tokens.push('tts-runtime-visible');
            tokens.push(cameraAvailable ? 'camera-bridge-available' : 'camera-bridge-unavailable');
            tokens.push(cameraHardware ? 'camera-hardware-available' : 'camera-hardware-unavailable');
            tokens.push(cameraPreviewVisible ? 'camera-preview-visible' : 'camera-preview-hidden');
            if (cameraStatus === 'running' && cameraPreviewVisible) tokens.push('camera-native-preview-running');
            tokens.push(assistantState.nativeFrameInFlight ? 'native-frame-in-flight' : 'native-frame-idle');
            if (Number(assistantState.nativeLastFrameReturnedAt || 0) > 0 && Date.now() - Number(assistantState.nativeLastFrameReturnedAt || 0) < 5000) {
              tokens.push('native-frame-returned-recent');
            }
            if (Number(assistantState.lastNavigationResultAt || 0) > 0 && Date.now() - Number(assistantState.lastNavigationResultAt || 0) < 15000) {
              tokens.push('navigation-result-recent');
            }
            if (String(assistantState.lastNavigationSpeech || '').trim()) tokens.push('navigation-speech-present');
            if (String(assistantState.lastNavigationSubject || '').trim()) tokens.push('navigation-subject-present');
            tokens.push('camera-native-' + cameraStatus.replace(/[^a-z0-9_-]/gi, '-').toLowerCase());
            tokens.push('camera-auth-' + cameraAuth.replace(/[^a-z0-9_-]/gi, '-').toLowerCase());
            if (cameraError) tokens.push('camera-error-' + cameraError.replace(/[^a-z0-9_-]/gi, '-').toLowerCase());
            if (textIncludes('长按提问')) tokens.push('hold-inquiry');
            if (inquiryLabel.includes('按住提问')) tokens.push('inquiry-ready');
            if (inquiryLabel.includes('松开发送')) tokens.push('inquiry-recording');
            if (statusLabel.includes('启动相机')) tokens.push('status-camera-starting');
            if (statusLabel.includes('摄像头错误')) tokens.push('status-camera-error');
            if (statusLabel.includes('扫描中') || statusLabel.includes('自动刷新') || statusLabel.includes('手动刷新') || statusLabel.includes('本机联网')) tokens.push('status-navigation-active');
            if (toggleLabel.includes('启动导航')) tokens.push('start-nav');
            if (toggleLabel.includes('停止导航')) tokens.push('stop-nav');
            if (detailsLabel.includes('查看详情')) tokens.push('show-details');
            if (detailsLabel.includes('隐藏详情')) tokens.push('hide-details');
            tokens.push(detailsVisible ? 'details-open' : 'details-closed');
            if (detailsVisible && textIncludes('AI 推理')) tokens.push('ai-reasoning');
            if (detailsVisible && textIncludes('识别对象')) tokens.push('ai-objects');
            if (detailsVisible && centerHitMatches('closeIntelButton')) tokens.push('hit-close-details');

            if (!managementVisible && !detailsVisible) {
              if (centerHitMatches('toggleCommand')) tokens.push('hit-toggle');
              if (centerHitMatches('inquiryCommand')) tokens.push('hit-inquiry');
              if (centerHitMatches('detailsCommand')) tokens.push('hit-details');
              if (centerHitMatches('settingsCommand')) tokens.push('hit-settings');
              if (centerHitMatches('managementCommand')) tokens.push('hit-management');
              if (['toggleCommand', 'inquiryCommand', 'detailsCommand', 'settingsCommand', 'managementCommand'].every(centerHitMatches)) {
                tokens.push('home-controls-hittable');
              }
            }

            const caption = captionLayout();
            if (caption.visible) tokens.push('caption-visible');
            if (caption.heightOk) tokens.push('caption-height-ok');
            if (caption.aiInside) tokens.push('ai-caption-inside');
            if (caption.aiClamped) tokens.push('ai-caption-clamped');
            if (caption.panelNonInteractive) tokens.push('caption-nonblocking');
            if (caption.visible && caption.heightOk && caption.aiInside && caption.aiClamped && caption.panelNonInteractive) {
              tokens.push('caption-layout-ok');
            }

            const mainFeedbackLayoutState = mainFeedbackLayout();
            if (mainFeedbackLayoutState.visible) tokens.push('main-feedback-visible');
            if (mainFeedbackLayoutState.clearOfCommands) tokens.push('main-feedback-clear-of-controls');
            if (mainFeedbackLayoutState.nonInteractive) tokens.push('main-feedback-nonblocking');
            if (mainFeedbackLayoutState.clearOfCommands && mainFeedbackLayoutState.nonInteractive) {
              tokens.push('main-feedback-layout-ok');
            }

            const feedback = feedbackState();
            const speechText = [feedback.mainText, feedback.userText, feedback.aiText].join(' ');
            if (/No complete JSON value found|Expected JSON object|DashScope chat response content is empty/.test(speechText)) {
              tokens.push('json-parse-error-visible');
            }
            if (speechText.includes('请先启动导航')) tokens.push('inquiry-needs-navigation');
            if (speechText.includes('正在聆听') || inquiryLabel.includes('松开发送')) tokens.push('speech-listening');
            if (/语音已提交|正在识别|正在思考/.test(speechText)) tokens.push('speech-submitted');
            if (/语音识别超时|麦克风被阻止|没有正在进行|权限|ASR|识别失败|DashScope.*Key|Key|密钥/.test(speechText)) {
              tokens.push('speech-terminal');
            }
            if (feedback.mainClean) tokens.push('main-feedback-tts-clean');
            if (feedback.userClean) tokens.push('user-caption-tts-clean');
            if (feedback.aiClean) tokens.push('ai-caption-tts-clean');
            if (feedback.mainClean && feedback.userClean && feedback.aiClean) tokens.push('feedback-tts-clean');

            tokens.forEach((token) => {
              if (speechHistoryTokenNames.has(token)) speechHistoryTokens.add('seen-' + token);
            });
            speechHistoryTokens.forEach((token) => tokens.push(token));

            if (managementVisible) {
              tokens.push('management-open');
              if (textIncludes('适老化居家长护服务管理端')) tokens.push('management-title');
              if (textIncludes('风险队列')) tokens.push('risk-queue');
              if (textIncludes('长护对象')) tokens.push('residents');
              if (textIncludes('照护数据智能助手')) tokens.push('care-agent');
            } else {
              tokens.push('home-view');
            }

            return {
              view: managementVisible ? 'management' : 'home',
              tokens,
              statusLabel,
              toggleLabel,
              detailsLabel,
              runtimeSubtitle,
              aiRuntime,
              asrRuntime,
              ttsRuntime,
              mainFeedback: feedback.mainText,
              userCaption: feedback.userText,
              aiCaption: feedback.aiText
            };
          };

          const post = () => {
            try {
              const snapshot = collect();
              const signature = JSON.stringify(snapshot);
              if (signature === lastSignature) return;
              lastSignature = signature;
              window.webkit?.messageHandlers?.silverCareAutomation?.postMessage(snapshot);
            } catch (error) {
              console.error('SilverCare automation snapshot failed', error);
            }
          };

          const schedule = () => {
            if (pending.value) return;
            pending.value = true;
            window.requestAnimationFrame(() => {
              pending.value = false;
              post();
            });
          };

          const install = () => {
            const root = document.documentElement || document.body;
            if (root) {
              new MutationObserver(schedule).observe(root, {
                attributes: true,
                childList: true,
                subtree: true,
                characterData: true
              });
            }
            document.addEventListener('click', () => window.setTimeout(post, 80), true);
            window.addEventListener('load', schedule);
            window.setInterval(post, 500);
            schedule();
          };

          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', install, { once: true });
          } else {
            install();
          }
        })();
        """
    }
}
