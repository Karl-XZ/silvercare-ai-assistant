package com.silvercare.aiassistant;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioRecord;
import android.media.MediaPlayer;
import android.media.MediaRecorder;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.text.InputType;
import android.util.Base64;
import android.util.Log;
import android.view.Menu;
import android.view.MenuItem;
import android.view.ViewGroup;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.webkit.WebViewAssetLoader;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

public class MainActivity extends Activity
    implements SilverCareArtificialIntelligenceClient.SettingsProvider, SilverCareProcessor.MessageSink {

    private static final int REQUEST_MEDIA_PERMISSIONS = 1001;
    private static final int MENU_RUNTIME = 1;
    private static final int MENU_API_KEY = 2;
    private static final int MENU_REGION = 3;
    private static final int MENU_OFFLINE_MODELS = 4;
    private static final int MENU_ASR = 5;
    private static final int MENU_TTS = 6;
    private static final int MENU_CAPTIONS = 7;
    private static final int MENU_VOICE_FIRST = 8;
    private static final int MENU_FALL = 9;
    private static final int MENU_MNN_TUNING = 10;
    private static final int MENU_NAV_REFRESH = 11;
    private static final long LOCAL_TTS_TIMEOUT_MS = 20_000L;
    private static final long TTS_INIT_TIMEOUT_MS = 12_000L;
    private static final boolean LOCAL_MNN_TTS_VOICE_QUALITY_ENABLED = false;
    private static final int MENU_RELOAD = 12;
    private static final String ASSET_URL = "https://appassets.androidplatform.net/assets/index.html";
    private static final String TAG = "SilverCareMain";

    private static final String KEY_AI_RUNTIME_MODE = "ai_runtime_mode";
    private static final String KEY_API_KEY = "dashscope_api_key";
    private static final String KEY_COMPATIBLE_BASE_URL = "compatible_base_url";
    private static final String KEY_API_BASE_URL = "api_base_url";
    private static final String KEY_VISION_MODEL = "vision_model";
    private static final String KEY_MICRO_MODEL = "micro_model";
    private static final String KEY_TEXT_MODEL = "text_model";
    private static final String KEY_ASR_MODEL = "asr_model";
    private static final String KEY_ASR_RUNTIME_MODE = "asr_runtime_mode";
    private static final String KEY_TTS_RUNTIME_MODE = "tts_runtime_mode";
    private static final String KEY_OFFLINE_MODEL_DIR = "offline_model_dir";
    private static final String KEY_OFFLINE_TEXT_MODEL = "offline_text_model";
    private static final String KEY_LEGACY_LOCAL_ASR_ENABLED = "local_asr_enabled";
    private static final String KEY_CAPTIONS_ENABLED = "captions_enabled";
    private static final String KEY_VOICE_FIRST_ENABLED = "voice_first_enabled";
    private static final String KEY_FALL_DETECTION_ENABLED = "fall_detection_enabled";
    private static final String KEY_MNN_LLM_TUNING_MODE = "mnn_llm_tuning_mode";
    private static final String KEY_NAVIGATION_REFRESH_MODE = "navigation_refresh_mode";
    private static final String KEY_NAVIGATION_REFRESH_INTERVAL_SECONDS = "navigation_refresh_interval_seconds";
    private static final String KEY_SMART_NAVIGATION_REFRESH_ENABLED = "smart_navigation_refresh_enabled";
    private static final long SPEECH_RECORDING_MAX_MS = 15_000L;
    private static final long LOCAL_ASR_TRANSCRIBE_TIMEOUT_MS = 20_000L;
    private static final long LOCAL_ASR_CORRECTION_TIMEOUT_MS = 2_000L;

    private WebView webView;
    private WebViewAssetLoader assetLoader;
    private SharedPreferences preferences;
    private PermissionRequest pendingPermissionRequest;
    private TextToSpeech tts;
    private MediaPlayer dashScopeTtsPlayer;
    private AudioManager audioManager;
    private ExecutorService executor;
    private ExecutorService asrExecutor;
    private ExecutorService asrCorrectionExecutor;
    private AtomicBoolean frameInFlight;
    private SilverCareProcessor processor;
    private MemoryStore memoryStore;
    private OfflineModelManager offlineModelManager;
    private LocalAsrModelManager localAsrModelManager;
    private LocalTtsModelManager localTtsModelManager;
    private VoskLocalAsrEngine localAsrEngine;
    private MnnRuntimeBridge mnnRuntimeBridge;
    private LocalTtsRuntimeBridge localTtsRuntimeBridge;
    private AudioRecord audioRecord;
    private String pendingSpeechImageDataUrl;
    private AtomicBoolean modelDownloadInFlight;
    private AtomicBoolean asrDownloadInFlight;
    private AtomicBoolean ttsDownloadInFlight;
    private AtomicBoolean localBundleDownloadInFlight;
    private AtomicBoolean localPrewarmInFlight;
    private AtomicBoolean localPrewarmCompleted;
    private AtomicBoolean wavRecording;
    private AtomicBoolean speechRequestInFlight;
    private AtomicBoolean localTtsInFlight;
    private AtomicInteger dashScopeTtsSerial;
    private AtomicInteger ttsInitSerial;
    private int lastModelDownloadPercent = -1;
    private int lastAsrDownloadPercent = -1;
    private int lastTtsDownloadPercent = -1;
    private int lastLocalBundleDownloadPercent = -1;
    private boolean ttsReady = false;
    private String ttsEnginePackage = "";
    private long lastLocalTtsFallbackLogAt = 0L;
    private long lastTtsFailureLogAt = 0L;
    private final List<String> pendingTts = new ArrayList<>();

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        preferences = getSharedPreferences("silvercare", MODE_PRIVATE);
        DiagnosticLogger.init(this);
        DiagnosticLogger.eventPairs(
            "app_on_create",
            "ai_runtime", currentRuntimeMode().value,
            "asr_runtime", currentAsrRuntimeMode().value,
            "tts_runtime", currentTtsRuntimeMode().value,
            "offline_model", offlineTextModel()
        );
        migrateDisabledLocalMnnTtsPreference();
        executor = Executors.newFixedThreadPool(4);
        asrExecutor = Executors.newSingleThreadExecutor();
        asrCorrectionExecutor = Executors.newSingleThreadExecutor();
        frameInFlight = new AtomicBoolean(false);
        modelDownloadInFlight = new AtomicBoolean(false);
        asrDownloadInFlight = new AtomicBoolean(false);
        ttsDownloadInFlight = new AtomicBoolean(false);
        localBundleDownloadInFlight = new AtomicBoolean(false);
        localPrewarmInFlight = new AtomicBoolean(false);
        localPrewarmCompleted = new AtomicBoolean(false);
        wavRecording = new AtomicBoolean(false);
        speechRequestInFlight = new AtomicBoolean(false);
        localTtsInFlight = new AtomicBoolean(false);
        dashScopeTtsSerial = new AtomicInteger(0);
        ttsInitSerial = new AtomicInteger(0);
        offlineModelManager = new OfflineModelManager();
        localAsrModelManager = new LocalAsrModelManager();
        localTtsModelManager = new LocalTtsModelManager();
        localAsrEngine = new VoskLocalAsrEngine();
        mnnRuntimeBridge = new MnnNativeBridge();
        localTtsRuntimeBridge = LOCAL_MNN_TTS_VOICE_QUALITY_ENABLED ? new MnnTtsRuntimeBridge() : null;
        audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        memoryStore = new MemoryStore(preferences);
        rebuildProcessor();

        initializeTts();
        maybePrewarmLocalModels("startup");

        assetLoader = new WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(this))
            .build();

        webView = new WebView(this);
        setContentView(webView, new FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        ));

        configureWebView();
        requestMediaPermissionsIfNeeded();
        webView.loadUrl(ASSET_URL);

        webView.postDelayed(this::showInitialRuntimePromptIfNeeded, 600);
    }

    @SuppressLint({"SetJavaScriptEnabled", "AddJavascriptInterface"})
    private void configureWebView() {
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);

        webView.addJavascriptInterface(new SilverCareBridge(this), "AndroidSilverCare");
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(
                WebView view,
                WebResourceRequest request
            ) {
                return assetLoader.shouldInterceptRequest(request.getUrl());
            }

            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, String url) {
                return assetLoader.shouldInterceptRequest(Uri.parse(url));
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                sendRuntimeStatus();
                maybePrewarmLocalModels("page-finished");
                webView.postDelayed(MainActivity.this::sendRuntimeStatus, 300);
                webView.postDelayed(MainActivity.this::sendRuntimeStatus, 1200);
            }
        });

        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onPermissionRequest(PermissionRequest request) {
                runOnUiThread(() -> handleWebPermissionRequest(request));
            }
        });
    }

    private synchronized void rebuildProcessor() {
        processor = new SilverCareProcessor(createAiClient(), memoryStore, this);
        sendRuntimeStatus();
        maybePrewarmLocalModels("runtime-rebuild");
    }

    private SilverCareArtificialIntelligenceClient createAiClient() {
        if (currentRuntimeMode().isOffline()) {
            return new OfflineAiClient(
                this,
                new MnnOfflineEngine(this, offlineModelManager, mnnRuntimeBridge)
            );
        }
        return new DashScopeClient(this);
    }

    private SilverCareArtificialIntelligenceClient.SettingsProvider offlineCorrectionSettings() {
        return new SilverCareArtificialIntelligenceClient.SettingsProvider() {
            @Override
            public String aiRuntimeMode() {
                return AiRuntimeMode.OFFLINE_MNN.value;
            }

            @Override
            public String offlineModelDir() {
                return MainActivity.this.offlineModelDir();
            }

            @Override
            public String apiKey() {
                return MainActivity.this.apiKey();
            }

            @Override
            public String compatibleBaseUrl() {
                return MainActivity.this.compatibleBaseUrl();
            }

            @Override
            public String apiBaseUrl() {
                return MainActivity.this.apiBaseUrl();
            }

            @Override
            public String visionModel() {
                return OfflineAiClient.DETECTOR_MODEL;
            }

            @Override
            public String microModel() {
                return OfflineAiClient.DETECTOR_MODEL;
            }

            @Override
            public String textModel() {
                return offlineTextModel();
            }

            @Override
            public String asrModel() {
                return OfflineAiClient.DEVICE_ASR_MODEL;
            }

            @Override
            public String mnnLlmTuningMode() {
                return MainActivity.this.mnnLlmTuningMode();
            }

            @Override
            public boolean voiceFirstEnabled() {
                return MainActivity.this.voiceFirstEnabled();
            }

            @Override
            public boolean smartNavigationRefreshEnabled() {
                return MainActivity.this.smartNavigationRefreshEnabled();
            }
        };
    }

    private AiRuntimeMode currentRuntimeMode() {
        return AiRuntimeMode.from(preferences.getString(KEY_AI_RUNTIME_MODE, AiRuntimeMode.DEFAULT.value));
    }

    private void showInitialRuntimePromptIfNeeded() {
        if (currentRuntimeMode().isOffline()) {
            OfflineModelStatus status = offlineStatus();
            if (!status.ready()) {
                showOfflineModelsDialog();
            }
            return;
        }
        if (!hasDashScopeKeyInternal()) {
            showApiKeyDialog();
        }
    }

    private void handleWebPermissionRequest(PermissionRequest request) {
        if (hasMediaPermissions()) {
            request.grant(request.getResources());
        } else {
            pendingPermissionRequest = request;
            requestMediaPermissionsIfNeeded();
        }
    }

    private boolean hasMediaPermissions() {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED
            && ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            == PackageManager.PERMISSION_GRANTED;
    }

    private void requestMediaPermissionsIfNeeded() {
        if (!hasMediaPermissions()) {
            ActivityCompat.requestPermissions(
                this,
                new String[] { Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO },
                REQUEST_MEDIA_PERMISSIONS
            );
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_MEDIA_PERMISSIONS && pendingPermissionRequest != null) {
            if (hasMediaPermissions()) {
                pendingPermissionRequest.grant(pendingPermissionRequest.getResources());
            } else {
                pendingPermissionRequest.deny();
            }
            pendingPermissionRequest = null;
        }
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        menu.add(0, MENU_RUNTIME, 0, "AI 运行方案");
        menu.add(0, MENU_API_KEY, 1, "DashScope Key");
        menu.add(0, MENU_REGION, 2, "DashScope 区域/模型");
        menu.add(0, MENU_OFFLINE_MODELS, 3, "离线模型目录");
        menu.add(0, MENU_ASR, 4, "语音识别方案");
        menu.add(0, MENU_TTS, 5, "朗读方案");
        menu.add(0, MENU_CAPTIONS, 6, "语音字幕");
        menu.add(0, MENU_VOICE_FIRST, 7, "语音优先模式");
        menu.add(0, MENU_FALL, 8, "跌倒检测");
        menu.add(0, MENU_MNN_TUNING, 9, "SME2 性能调优");
        menu.add(0, MENU_NAV_REFRESH, 10, "导航刷新模式");
        menu.add(0, MENU_RELOAD, 11, "刷新");
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        if (item.getItemId() == MENU_RUNTIME) {
            showRuntimeDialog();
            return true;
        }
        if (item.getItemId() == MENU_API_KEY) {
            showApiKeyDialog();
            return true;
        }
        if (item.getItemId() == MENU_REGION) {
            showAdvancedDialog();
            return true;
        }
        if (item.getItemId() == MENU_OFFLINE_MODELS) {
            showOfflineModelsDialog();
            return true;
        }
        if (item.getItemId() == MENU_ASR) {
            showAsrRuntimeDialog();
            return true;
        }
        if (item.getItemId() == MENU_TTS) {
            showTtsRuntimeDialog();
            return true;
        }
        if (item.getItemId() == MENU_CAPTIONS) {
            showCaptionsDialog();
            return true;
        }
        if (item.getItemId() == MENU_VOICE_FIRST) {
            showVoiceFirstDialog();
            return true;
        }
        if (item.getItemId() == MENU_FALL) {
            showFallDetectionDialog();
            return true;
        }
        if (item.getItemId() == MENU_MNN_TUNING) {
            showMnnTuningDialog();
            return true;
        }
        if (item.getItemId() == MENU_NAV_REFRESH) {
            showNavigationRefreshModeDialog();
            return true;
        }
        if (item.getItemId() == MENU_RELOAD) {
            webView.reload();
            return true;
        }
        return super.onOptionsItemSelected(item);
    }

    private void showSettingsDialog() {
        AiRuntimeMode runtimeMode = currentRuntimeMode();
        OfflineModelStatus offlineStatus = offlineStatus();
        LocalAsrModelStatus asrStatus = localAsrStatus();
        String runtimeText = "AI 运行方案：" + runtimeMode.label;
        String offlineModelText = "离线文本模型：" + OfflineAiClient.textModelLabel(offlineTextModel());
        String tuningText = mnnTuningSettingsText();
        String offlineText = offlineStatus.ready() ? "离线模型目录：已就绪" : "离线模型目录：未就绪";
        String asrText = localAsrSettingsText(asrStatus);
        String ttsText = ttsSettingsText();
        String captionsText = isCaptionsEnabledInternal() ? "语音字幕：已开启" : "语音字幕：已关闭";
        String voiceText = isVoiceFirstEnabledInternal() ? "语音优先模式：已开启" : "语音优先模式：已关闭";
        String fallText = isFallDetectionEnabledInternal() ? "跌倒检测：已开启" : "跌倒检测：已关闭";
        String refreshText = navigationRefreshSettingsText();
        String presetText = "一键切换全部：本地或云端";
        String[] items = new String[] {
            presetText,
            runtimeText,
            "DashScope Key",
            "DashScope 区域/模型",
            offlineModelText,
            tuningText,
            offlineText,
            asrText,
            ttsText,
            captionsText,
            voiceText,
            fallText,
            refreshText,
            "刷新界面"
        };

        speakIfVoiceFirst("设置已打开。可一键切换全部为本地或云端。当前" + runtimeText + "。" + tuningText + "。" + asrText + "。" + ttsText + "。" + captionsText + "。" + voiceText + "，" + fallText + "。" + refreshText + "。");

        new AlertDialog.Builder(this)
            .setTitle("设置")
            .setItems(items, (dialog, which) -> {
                if (which == 0) {
                    showRuntimePresetDialog();
                } else if (which == 1) {
                    showRuntimeDialog();
                } else if (which == 2) {
                    showApiKeyDialog();
                } else if (which == 3) {
                    showAdvancedDialog();
                } else if (which == 4) {
                    showOfflineTextModelDialog();
                } else if (which == 5) {
                    showMnnTuningDialog();
                } else if (which == 6) {
                    showOfflineModelsDialog();
                } else if (which == 7) {
                    showAsrRuntimeDialog();
                } else if (which == 8) {
                    showTtsRuntimeDialog();
                } else if (which == 9) {
                    showCaptionsDialog();
                } else if (which == 10) {
                    showVoiceFirstDialog();
                } else if (which == 11) {
                    showFallDetectionDialog();
                } else if (which == 12) {
                    showNavigationRefreshModeDialog();
                } else if (which == 13) {
                    webView.reload();
                }
            })
            .show();
    }

    private void showRuntimePresetDialog() {
        String[] items = new String[] {
            "全部切换为本地：AI、ASR、TTS 都优先使用端侧模型",
            "全部切换为云端：AI、ASR、TTS 都使用 DashScope"
        };
        speakIfVoiceFirst("一键切换设置已打开。可以把 AI、语音识别和朗读全部切换为本地或云端。");

        new AlertDialog.Builder(this)
            .setTitle("一键切换全部")
            .setItems(items, (dialog, which) -> {
                if (which == 0) {
                    showSwitchAllLocalConfirmation();
                } else {
                    switchAllCloud();
                }
            })
            .setNegativeButton("取消", null)
            .show();
    }

    private void showSwitchAllLocalConfirmation() {
        LocalRuntimeBundlePlan plan = localRuntimeBundlePlan();
        StringBuilder message = new StringBuilder();
        message.append("将切换为：\n")
            .append("AI：端侧离线 MNN + Qwen3-4B + DAMO-YOLO\n")
            .append("ASR：应用内置中文 ASR 模型，本地离线识别，不依赖 Google 或系统语音服务\n")
            .append("TTS：手机系统 TTS 本机朗读；本地 MNN TTS 音质测试未通过，暂不作为主朗读\n\n")
            .append("还没准备好的内容：\n")
            .append(plan.downloadSummaryText());
        String warnings = plan.runtimeWarningText();
        if (!warnings.isEmpty()) {
            message.append("\n\n运行时提醒：\n").append(warnings);
        }

        speakIfVoiceFirst("准备切换全部为本地。"
            + (plan.hasDownloads()
                ? "需要下载本地模型，约" + LocalTtsDownloader.humanBytes(plan.downloadBytes) + "。"
                : "本地模型文件已经准备好。"));

        AlertDialog.Builder builder = new AlertDialog.Builder(this)
            .setTitle("全部切换为本地")
            .setMessage(message.toString())
            .setNegativeButton("取消", null);
        if (plan.hasDownloads()) {
            builder
                .setPositiveButton("一键下载并切换", (dialog, which) -> startAllLocalBundleDownload(plan))
                .setNeutralButton("只切换", (dialog, which) -> switchAllLocalWithoutDownload());
        } else {
            builder.setPositiveButton("切换为本地", (dialog, which) -> switchAllLocalWithoutDownload());
        }
        builder.show();
    }

    private LocalRuntimeBundlePlan localRuntimeBundlePlan() {
        return LocalRuntimeBundlePlan.from(offlineStatus(), localAsrStatus(), localTtsStatus());
    }

    private void switchAllCloud() {
        preferences.edit()
            .putString(KEY_AI_RUNTIME_MODE, AiRuntimeMode.DASHSCOPE.value)
            .putString(KEY_ASR_RUNTIME_MODE, AsrRuntimeMode.DASHSCOPE.value)
            .putString(KEY_TTS_RUNTIME_MODE, TtsRuntimeMode.DASHSCOPE.value)
            .apply();
        rebuildProcessor();
        sendRuntimeStatus();
        speakNative("已全部切换为云端 DashScope。AI、语音识别和朗读都会使用联网方案。");
        if (!hasDashScopeKeyInternal()) {
            showApiKeyDialog();
        }
    }

    private void switchAllLocalWithoutDownload() {
        applyAllLocalPreferences();
        LocalRuntimeBundlePlan plan = localRuntimeBundlePlan();
        sendRuntimeStatus();
        speakNative("已全部切换为本地优先。");
        if (plan.hasDownloads()) {
            sendError("本地模型还未全部下载：" + plan.downloadSummaryText());
        }
        String warnings = plan.runtimeWarningText();
        if (!warnings.isEmpty()) {
            sendError(warnings);
        }
    }

    private void applyAllLocalPreferences() {
        File targetDir = OfflineModelDownloader.automaticModelDir(this);
        preferences.edit()
            .putString(KEY_AI_RUNTIME_MODE, AiRuntimeMode.OFFLINE_MNN.value)
            .putString(KEY_OFFLINE_MODEL_DIR, targetDir.getAbsolutePath())
            .putString(KEY_OFFLINE_TEXT_MODEL, OfflineAiClient.TEXT_MODEL_4B)
            .putString(KEY_ASR_RUNTIME_MODE, AsrRuntimeMode.LOCAL_VOSK.value)
            .putString(KEY_TTS_RUNTIME_MODE, TtsRuntimeMode.SYSTEM.value)
            .apply();
        rebuildProcessor();
    }

    private void showRuntimeDialog() {
        AiRuntimeMode current = currentRuntimeMode();
        String[] items = new String[] {
            AiRuntimeMode.DASHSCOPE.label + "：使用 DashScope API，效果更强，需要联网和 Key",
            AiRuntimeMode.OFFLINE_MNN.label + "：使用本机 MNN + DAMO-YOLO + 可切换 Qwen 文本模型，不需要联网"
        };
        int checked = current.isOffline() ? 1 : 0;

        speakIfVoiceFirst("AI 运行方案设置已打开。当前是" + current.label + "。");

        new AlertDialog.Builder(this)
            .setTitle("AI 运行方案")
            .setSingleChoiceItems(items, checked, (dialog, which) -> {
                AiRuntimeMode next = which == 1 ? AiRuntimeMode.OFFLINE_MNN : AiRuntimeMode.DASHSCOPE;
                preferences.edit().putString(KEY_AI_RUNTIME_MODE, next.value).apply();
                rebuildProcessor();
                dialog.dismiss();
                speakNative("已切换到" + next.label + "。");
                if (next.isOffline() && !offlineStatus().ready()) {
                    showOfflineModelsDialog();
                } else if (!next.isOffline() && !hasDashScopeKeyInternal()) {
                    showApiKeyDialog();
                }
            })
            .setNegativeButton("取消", null)
            .show();
    }

    private void showOfflineTextModelDialog() {
        String current = offlineTextModel();
        RadioGroup group = new RadioGroup(this);
        group.setOrientation(RadioGroup.VERTICAL);
        int padding = (int) (16 * getResources().getDisplayMetrics().density);
        group.setPadding(padding, 0, padding, 0);

        RadioButton model4b = offlineModelRadio(
            1001,
            OfflineAiClient.TEXT_MODEL_4B,
            "Qwen3-4B-Instruct-2507-MNN（默认，质量更高）"
        );
        RadioButton model15b = offlineModelRadio(
            1002,
            OfflineAiClient.TEXT_MODEL_1_5B,
            "Qwen2.5-1.5B-Instruct-MNN（备用，更轻更快）"
        );
        group.addView(model4b);
        group.addView(model15b);
        group.check(OfflineAiClient.TEXT_MODEL_1_5B.equals(current) ? 1002 : 1001);

        speakIfVoiceFirst("离线文本模型设置已打开。当前是" + OfflineAiClient.textModelLabel(current) + "。");

        new AlertDialog.Builder(this)
            .setTitle("离线文本模型")
            .setMessage("只替换本地文本模型；视觉检测仍使用 DAMO-YOLO，联网 DashScope 设置不受影响。")
            .setView(group)
            .setPositiveButton("保存", (dialog, which) -> {
                RadioButton checked = group.findViewById(group.getCheckedRadioButtonId());
                String selected = checked == null ? OfflineAiClient.TEXT_MODEL : String.valueOf(checked.getTag());
                preferences.edit().putString(KEY_OFFLINE_TEXT_MODEL, selected).apply();
                rebuildProcessor();
                OfflineModelStatus nextStatus = offlineStatus();
                speakNative("已切换到" + OfflineAiClient.textModelLabel(selected) + "。" + nextStatus.shortText());
                if (!nextStatus.ready()) {
                    sendError(nextStatus.shortText());
                }
            })
            .setNegativeButton("取消", null)
            .show();
    }

    private RadioButton offlineModelRadio(int id, String model, String text) {
        RadioButton button = new RadioButton(this);
        button.setId(id);
        button.setTag(model);
        button.setText(text);
        return button;
    }

    private void showMnnTuningDialog() {
        MnnLlmTuningProfile current = currentMnnLlmTuningProfile();
        MnnLlmTuningProfile[] profiles = MnnLlmTuningProfile.values();
        boolean sme2Supported = mnnRuntimeBridge != null && mnnRuntimeBridge.supportsSme2();
        String deviceText = mnnRuntimeBridge == null
            ? "MNN Native Runtime 未加载"
            : mnnRuntimeBridge.runtimeSummary();
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        int padding = (int) (16 * getResources().getDisplayMetrics().density);
        layout.setPadding(padding, 0, padding, 0);

        TextView message = new TextView(this);
        message.setText("仅影响端侧离线 Qwen 文本模型。SME2 可用时会在加载 MNN-LLM 前写入运行时配置；未检测到 SME2 的设备会自动回退，不影响联网 DashScope。\n\n当前设备：" + deviceText);
        message.setTextSize(14);
        layout.addView(message);

        RadioGroup group = new RadioGroup(this);
        group.setOrientation(RadioGroup.VERTICAL);
        for (int index = 0; index < profiles.length; index += 1) {
            RadioButton button = new RadioButton(this);
            button.setId(2000 + index);
            button.setTag(profiles[index]);
            button.setText(profiles[index].menuText(sme2Supported));
            group.addView(button);
            if (profiles[index] == current) group.check(button.getId());
        }
        layout.addView(group);
        speakIfVoiceFirst("SME2 性能调优已打开。当前是" + current.label + "。" + deviceText + "。");

        new AlertDialog.Builder(this)
            .setTitle("SME2 性能调优")
            .setView(layout)
            .setPositiveButton("保存", (dialog, which) -> {
                RadioButton checked = group.findViewById(group.getCheckedRadioButtonId());
                MnnLlmTuningProfile selected = checked == null
                    ? MnnLlmTuningProfile.DEFAULT
                    : (MnnLlmTuningProfile) checked.getTag();
                preferences.edit().putString(KEY_MNN_LLM_TUNING_MODE, selected.value).apply();
                rebuildProcessor();
                sendRuntimeStatus();
                String result = selected.nativeConfigJson(sme2Supported);
                String suffix = "{}".equals(result)
                    ? "当前会使用 MNN 默认配置。"
                    : "下一次端侧回答会按 " + result + " 重新加载模型。";
                speakNative("已切换到" + selected.label + "。" + suffix);
            })
            .setNegativeButton("取消", null)
            .show();
    }

    private void showNavigationRefreshModeDialog() {
        NavigationRefreshMode current = currentNavigationRefreshMode();
        int currentInterval = currentNavigationRefreshIntervalSeconds();
        boolean smartRefresh = isSmartNavigationRefreshEnabledInternal();

        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        int padding = (int) (16 * getResources().getDisplayMetrics().density);
        layout.setPadding(padding, 0, padding, 0);

        TextView message = new TextView(this);
        message.setText("自动刷新会按设定秒数抓取一帧；手动刷新则启动导航后单击屏幕刷新一次。\n\n智能刷新开启后，每次 AI 生成导航文本后，会再用文本模型判断新旧导航语义是否一致；一致则不更新导航 UI，也不朗读。");
        message.setTextSize(14);
        layout.addView(message);

        RadioGroup group = new RadioGroup(this);
        group.setOrientation(RadioGroup.VERTICAL);
        RadioButton auto = navigationRefreshModeRadio(5001, NavigationRefreshMode.AUTO, "自动刷新");
        RadioButton manual = navigationRefreshModeRadio(5002, NavigationRefreshMode.MANUAL, "手动刷新");
        group.addView(auto);
        group.addView(manual);
        group.check(current.isManual() ? manual.getId() : auto.getId());
        layout.addView(group);

        TextView intervalLabel = new TextView(this);
        intervalLabel.setText("自动刷新间隔（1-10 秒）");
        layout.addView(intervalLabel);

        EditText intervalInput = new EditText(this);
        intervalInput.setSingleLine(true);
        intervalInput.setInputType(InputType.TYPE_CLASS_NUMBER);
        intervalInput.setText(String.valueOf(currentInterval));
        layout.addView(intervalInput);

        CheckBox smart = new CheckBox(this);
        smart.setText("智能刷新：语义一致时不刷新");
        smart.setChecked(smartRefresh);
        layout.addView(smart);

        speakIfVoiceFirst("导航刷新模式设置已打开。当前是" + current.label + "，自动间隔"
            + currentInterval + "秒，智能刷新" + (smartRefresh ? "已开启。" : "已关闭。"));

        new AlertDialog.Builder(this)
            .setTitle("导航刷新模式")
            .setView(layout)
            .setPositiveButton("保存", (dialog, which) -> {
                RadioButton checked = group.findViewById(group.getCheckedRadioButtonId());
                NavigationRefreshMode selected = checked == null
                    ? NavigationRefreshMode.DEFAULT
                    : (NavigationRefreshMode) checked.getTag();
                int intervalSeconds = clampNavigationRefreshSeconds(intervalInput.getText().toString());
                preferences.edit()
                    .putString(KEY_NAVIGATION_REFRESH_MODE, selected.value)
                    .putInt(KEY_NAVIGATION_REFRESH_INTERVAL_SECONDS, intervalSeconds)
                    .putBoolean(KEY_SMART_NAVIGATION_REFRESH_ENABLED, smart.isChecked())
                    .apply();
                sendRuntimeStatus();
                notifyWebNavigationRefreshSettingsChanged();
                speakNative(selected.isManual()
                    ? "已切换到手动刷新。启动导航后，单击屏幕刷新一次导航。"
                    : "已切换到自动刷新，每" + intervalSeconds + "秒刷新一次。"
                        + (smart.isChecked() ? "智能刷新已开启。" : "智能刷新已关闭。"));
            })
            .setNegativeButton("取消", null)
            .show();
    }

    private RadioButton navigationRefreshModeRadio(int id, NavigationRefreshMode mode, String text) {
        RadioButton button = new RadioButton(this);
        button.setId(id);
        button.setTag(mode);
        button.setText(text);
        return button;
    }

    private void notifyWebNavigationRefreshSettingsChanged() {
        if (webView == null) return;
        NavigationRefreshMode mode = currentNavigationRefreshMode();
        int intervalMs = currentNavigationRefreshIntervalSeconds() * 1000;
        boolean smart = isSmartNavigationRefreshEnabledInternal();
        webView.post(() -> webView.evaluateJavascript(
            "window.LONG_TERM_CARE_REFRESH_SETTINGS_CHANGED && window.LONG_TERM_CARE_REFRESH_SETTINGS_CHANGED("
                + JSONObject.quote(mode.value) + "," + intervalMs + "," + smart + ");",
            null
        ));
    }

    private void showOfflineModelsDialog() {
        OfflineModelStatus status = offlineStatus();
        File autoDir = OfflineModelDownloader.automaticModelDir(this);
        speakIfVoiceFirst("离线模型设置已打开。" + status.shortText());

        new AlertDialog.Builder(this)
            .setTitle("离线模型")
            .setMessage(status.detailText()
                + "\n\n点击“自动下载离线模型”后，App 会自动下载 Qwen3-4B 文本模型和 DAMO-YOLO 到：\n"
                + autoDir.getAbsolutePath()
                + "\n\nDAMO-YOLO 检测模型已随 APK 内置，会自动复制到同一目录。"
                + "\n\n1.5B 选项会保留，但不会自动下载或打包；低内存设备需要用户自行准备对应模型后再切换。")
            .setPositiveButton("自动下载离线模型", (dialog, which) -> startOfflineModelDownload())
            .setNeutralButton("刷新状态", (dialog, which) -> {
                rebuildProcessor();
                OfflineModelStatus nextStatus = offlineStatus();
                speakNative(nextStatus.shortText());
            })
            .setNegativeButton("关闭", null)
            .show();
    }

    private boolean hasAnyModelDownloadInFlight() {
        return modelDownloadInFlight.get()
            || asrDownloadInFlight.get()
            || ttsDownloadInFlight.get()
            || localBundleDownloadInFlight.get();
    }

    private void notifyModelDownloadAlreadyRunning(String message, long totalBytes) {
        speakNative("模型正在下载中，请等待完成。");
        sendModelDownloadProgress(message, 0L, Math.max(1L, totalBytes), false, false);
    }

    private void startOfflineModelDownload() {
        if (hasAnyModelDownloadInFlight()) {
            notifyModelDownloadAlreadyRunning("已有模型下载正在进行中", OfflineModelDownloader.expectedTotalBytes());
            return;
        }
        if (!modelDownloadInFlight.compareAndSet(false, true)) {
            notifyModelDownloadAlreadyRunning("离线模型正在下载中", OfflineModelDownloader.expectedTotalBytes());
            return;
        }

        File targetDir = OfflineModelDownloader.automaticModelDir(this);
        preferences.edit()
            .putString(KEY_OFFLINE_MODEL_DIR, targetDir.getAbsolutePath())
            .putString(KEY_OFFLINE_TEXT_MODEL, OfflineAiClient.TEXT_MODEL_4B)
            .apply();
        rebuildProcessor();

        long total = OfflineModelDownloader.expectedTotalBytes();
        lastModelDownloadPercent = -1;
        speakNative("开始下载AI离线模型。文件较大，请保持网络连接和足够电量。");
        sendModelDownloadProgress("准备下载AI离线模型", 0L, total, false, false);

        executor.execute(() -> {
            try {
                OfflineModelDownloader.DownloadResult result = new OfflineModelDownloader()
                    .ensureQwen4BBundle(this, this::sendThrottledModelDownloadProgress);
                runOnUiThread(() -> {
                    modelDownloadInFlight.set(false);
                    rebuildProcessor();
                    sendModelDownloadProgress("离线模型已下载完成", result.totalBytes, result.totalBytes, true, false);
                    speakNative("离线模型已下载完成，可以使用端侧离线模式。");
                    Toast.makeText(this, "离线模型已就绪", Toast.LENGTH_LONG).show();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    modelDownloadInFlight.set(false);
                    String message = "离线模型下载失败：" + readableError(error);
                    sendModelDownloadProgress(message, 0L, total, false, true);
                    sendError(message);
                    speakNative(message);
                });
            }
        });
    }

    private void showAsrRuntimeDialog() {
        LocalAsrModelStatus status = localAsrStatus();
        AsrRuntimeMode current = currentAsrRuntimeMode();
        String localText = "本地内置 ASR：" + (status.ready ? "已就绪" : "未下载，需要下载中文 ASR 模型");
        String dashScopeText = hasDashScopeKeyInternal()
            ? "联网 DashScope：已配置 Key"
            : "联网 DashScope：需要 DashScope Key";
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        int padding = (int) (16 * getResources().getDisplayMetrics().density);
        layout.setPadding(padding, 0, padding, 0);

        TextView message = new TextView(this);
        message.setText("ASR 可以独立选择本地或联网，不跟随 AI 运行方案。\n\n"
            + localAsrDetailText(status)
            + "\n\n本地内置 ASR 使用应用下载的中文模型在手机端离线转文字，不依赖 Google、GMS 或 Android 系统语音服务；识别结果会再由本地 Qwen 文本模型校对一次。"
            + "\n联网 DashScope 会上传录音到 DashScope ASR。"
            + "\n\n当前选择：" + current.label);
        message.setTextSize(14);
        layout.addView(message);

        RadioGroup group = new RadioGroup(this);
        group.setOrientation(RadioGroup.VERTICAL);
        RadioButton local = asrModeRadio(3001, AsrRuntimeMode.LOCAL_VOSK, localText);
        RadioButton dashScope = asrModeRadio(3002, AsrRuntimeMode.DASHSCOPE, dashScopeText);
        group.addView(local);
        group.addView(dashScope);
        group.check(current.isLocal() ? local.getId() : dashScope.getId());
        layout.addView(group);

        speakIfVoiceFirst("语音识别方案设置已打开。当前是" + current.label + "。" + status.shortText());

        new AlertDialog.Builder(this)
            .setTitle("语音识别方案")
            .setView(layout)
            .setPositiveButton("保存", (dialog, which) -> {
                RadioButton checked = group.findViewById(group.getCheckedRadioButtonId());
                AsrRuntimeMode selected = checked == null
                    ? AsrRuntimeMode.DEFAULT
                    : (AsrRuntimeMode) checked.getTag();
                preferences.edit().putString(KEY_ASR_RUNTIME_MODE, selected.value).apply();
                sendRuntimeStatus();
                speakNative("语音识别已切换到" + selected.label + "。");
                if (selected.isLocal() && !localAsrReady(localAsrStatus())) {
                    showAsrRuntimeDialog();
                } else if (!selected.isLocal() && !hasDashScopeKeyInternal()) {
                    showApiKeyDialog();
                }
            })
            .setNeutralButton("下载本地 ASR 模型", (dialog, which) -> startLocalAsrDownload())
            .setNegativeButton("关闭", null)
            .show();
    }

    private RadioButton asrModeRadio(int id, AsrRuntimeMode mode, String text) {
        RadioButton button = new RadioButton(this);
        button.setId(id);
        button.setTag(mode);
        button.setText(text);
        return button;
    }

    private void showTtsRuntimeDialog() {
        TtsRuntimeMode current = currentTtsRuntimeMode();
        LocalTtsModelStatus localStatus = localTtsStatus();
        String localText = "本地 MNN TTS（实验，不推荐）：" + localStatus.shortText();
        String systemText = ttsReady
            ? "手机系统 TTS（本地）：已就绪，" + systemTtsEngineText()
            : "手机系统 TTS（本地）：未就绪，手机未启用可用中文朗读引擎";
        String dashScopeText = hasDashScopeKeyInternal()
            ? "联网 DashScope：已配置 Key"
            : "联网 DashScope：需要 DashScope Key";

        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        int padding = (int) (16 * getResources().getDisplayMetrics().density);
        layout.setPadding(padding, 0, padding, 0);

        TextView message = new TextView(this);
        message.setText("朗读方案独立于 ASR 和 AI 运行方案。\n\n"
            + "自动兜底会优先用手机系统 TTS；系统 TTS 不可用时，只要已填写 DashScope Key，就自动改用联网语音合成。"
            + "本地 MNN TTS 当前生成声音不可懂，保留为实验项，不再自动用于盲人/低视力用户朗读。\n\n"
            + localStatus.detailText()
            + "\n\n"
            + "当前状态：" + ttsStatusText());
        message.setTextSize(14);
        layout.addView(message);

        RadioGroup group = new RadioGroup(this);
        group.setOrientation(RadioGroup.VERTICAL);
        RadioButton auto = ttsModeRadio(4001, TtsRuntimeMode.AUTO, "自动兜底：手机系统 TTS -> DashScope");
        RadioButton local = ttsModeRadio(4002, TtsRuntimeMode.LOCAL_MNN, localText);
        if (!LOCAL_MNN_TTS_VOICE_QUALITY_ENABLED) {
            local.setEnabled(false);
            local.setText(localText + "（音质未通过，已停用）");
        }
        RadioButton system = ttsModeRadio(4003, TtsRuntimeMode.SYSTEM, systemText);
        RadioButton dashScope = ttsModeRadio(4004, TtsRuntimeMode.DASHSCOPE, dashScopeText);
        group.addView(auto);
        group.addView(local);
        group.addView(system);
        group.addView(dashScope);
        if (current == TtsRuntimeMode.LOCAL_MNN) {
            group.check(local.getId());
        } else if (current == TtsRuntimeMode.SYSTEM) {
            group.check(system.getId());
        } else if (current == TtsRuntimeMode.DASHSCOPE) {
            group.check(dashScope.getId());
        } else {
            group.check(auto.getId());
        }
        layout.addView(group);

        speakIfVoiceFirst("朗读方案设置已打开。当前是" + current.label + "。" + ttsStatusText());

        new AlertDialog.Builder(this)
            .setTitle("朗读方案")
            .setView(layout)
            .setPositiveButton("保存", (dialog, which) -> {
                RadioButton checked = group.findViewById(group.getCheckedRadioButtonId());
                TtsRuntimeMode selected = checked == null
                    ? TtsRuntimeMode.DEFAULT
                    : (TtsRuntimeMode) checked.getTag();
                if (selected == TtsRuntimeMode.LOCAL_MNN && !LOCAL_MNN_TTS_VOICE_QUALITY_ENABLED) {
                    selected = TtsRuntimeMode.SYSTEM;
                    sendError("本地 MNN TTS 音质测试未通过，已改用手机系统 TTS。");
                }
                preferences.edit().putString(KEY_TTS_RUNTIME_MODE, selected.value).apply();
                sendRuntimeStatus();
                speakNative("朗读方案已切换到" + selected.label + "。");
                if (selected == TtsRuntimeMode.LOCAL_MNN && !localTtsStatus().modelReady) {
                    startLocalTtsDownload();
                } else if (selected == TtsRuntimeMode.LOCAL_MNN) {
                    sendError("本地 MNN TTS 音质测试未通过，当前会自动回退手机系统 TTS 或 DashScope。");
                } else if (selected.allowsDashScope() && !hasDashScopeKeyInternal() && !ttsReady) {
                    showApiKeyDialog();
                }
            })
            .setNeutralButton("下载本地TTS", (dialog, which) -> startLocalTtsDownload())
            .setNegativeButton("关闭", null)
            .show();
    }

    private RadioButton ttsModeRadio(int id, TtsRuntimeMode mode, String text) {
        RadioButton button = new RadioButton(this);
        button.setId(id);
        button.setTag(mode);
        button.setText(text);
        return button;
    }

    private void startLocalAsrDownload() {
        if (hasAnyModelDownloadInFlight()) {
            notifyModelDownloadAlreadyRunning("已有模型下载正在进行中", LocalAsrDownloader.expectedTotalBytes());
            return;
        }
        if (!asrDownloadInFlight.compareAndSet(false, true)) {
            notifyModelDownloadAlreadyRunning("本地 ASR 模型正在下载中", LocalAsrDownloader.expectedTotalBytes());
            return;
        }

        long total = LocalAsrDownloader.expectedTotalBytes();
        lastAsrDownloadPercent = -1;
        speakNative("开始下载本地语音识别模型。文件约四十二MB，请保持网络连接。");
        sendModelDownloadProgress("准备下载本地 ASR 模型", 0L, total, false, false);

        executor.execute(() -> {
            try {
                LocalAsrDownloader.DownloadResult result = new LocalAsrDownloader()
                    .ensureChineseModel(this, this::sendThrottledAsrDownloadProgress);
                runOnUiThread(() -> {
                    asrDownloadInFlight.set(false);
                    preferences.edit().putString(KEY_ASR_RUNTIME_MODE, AsrRuntimeMode.LOCAL_VOSK.value).apply();
                    sendModelDownloadProgress("本地 ASR 模型已下载完成", result.totalBytes, result.totalBytes, true, false);
                    sendRuntimeStatus();
                    speakNative("本地语音识别模型已下载完成。ASR 已切换到本地内置识别。");
                    Toast.makeText(this, "本地 ASR 模型已就绪", Toast.LENGTH_LONG).show();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    asrDownloadInFlight.set(false);
                    String message = "本地 ASR 模型下载失败：" + readableError(error);
                    sendModelDownloadProgress(message, 0L, total, false, true);
                    sendError(message);
                    speakNative(message);
                });
            }
        });
    }

    private void startLocalTtsDownload() {
        if (hasAnyModelDownloadInFlight()) {
            notifyModelDownloadAlreadyRunning("已有模型下载正在进行中", LocalTtsDownloader.expectedTotalBytes());
            return;
        }
        if (!ttsDownloadInFlight.compareAndSet(false, true)) {
            notifyModelDownloadAlreadyRunning("本地 MNN TTS 模型正在下载中", LocalTtsDownloader.expectedTotalBytes());
            return;
        }

        long total = LocalTtsDownloader.expectedTotalBytes();
        lastTtsDownloadPercent = -1;
        speakNative("开始下载本地朗读模型。文件约一点三GB，请保持网络连接、电量和足够存储空间。");
        sendModelDownloadProgress("准备下载本地 MNN TTS 模型", 0L, total, false, false);

        executor.execute(() -> {
            try {
                LocalTtsDownloader.DownloadResult result = new LocalTtsDownloader()
                    .ensureMnnTtsBundle(this, this::sendThrottledTtsDownloadProgress);
                runOnUiThread(() -> {
                    ttsDownloadInFlight.set(false);
                    sendModelDownloadProgress("本地 MNN TTS 模型已下载完成", result.totalBytes, result.totalBytes, true, false);
                    sendRuntimeStatus();
                    LocalTtsModelStatus status = localTtsStatus();
                    speakNative("本地 MNN TTS 模型已下载完成，但当前音质测试未通过，不会自动设为主朗读。");
                    if (!status.runtimeAvailable) {
                        sendError("模型已下载，但本地 MNN TTS Native Runtime 不可用，当前仍会回退系统 TTS 或 DashScope。");
                    } else {
                        sendError("本地 MNN TTS 当前生成声音不可懂，已保留为实验项；主朗读请使用手机系统 TTS 或 DashScope。");
                    }
                    Toast.makeText(this, "本地 MNN TTS 模型已下载完成", Toast.LENGTH_LONG).show();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    ttsDownloadInFlight.set(false);
                    String message = "本地 MNN TTS 模型下载失败：" + readableError(error);
                    sendModelDownloadProgress(message, 0L, total, false, true);
                    sendError(message);
                    speakNative(message);
                });
            }
        });
    }

    private void startAllLocalBundleDownload(LocalRuntimeBundlePlan plan) {
        if (hasAnyModelDownloadInFlight()) {
            notifyModelDownloadAlreadyRunning("一键本地模型下载正在进行中", Math.max(1L, plan.downloadBytes));
            return;
        }
        if (!localBundleDownloadInFlight.compareAndSet(false, true)) {
            notifyModelDownloadAlreadyRunning("一键本地模型下载正在进行中", Math.max(1L, plan.downloadBytes));
            return;
        }

        applyAllLocalPreferences();
        long total = Math.max(1L, plan.downloadBytes);
        lastLocalBundleDownloadPercent = -1;
        speakNative("开始一键下载本地模型。预计需要准备约"
            + LocalTtsDownloader.humanBytes(plan.downloadBytes)
            + "。请保持网络连接、电量和足够存储空间。");
        sendModelDownloadProgress("准备一键下载本地模型", 0L, total, false, false);

        executor.execute(() -> {
            long[] completed = new long[] { 0L };
            try {
                if (plan.offlineModelsRequired) {
                    long stageTotal = OfflineModelDownloader.expectedTotalBytes();
                    new OfflineModelDownloader().ensureQwen4BBundle(
                        this,
                        (message, done, stage) -> sendThrottledLocalBundleDownloadProgress(
                            "AI 离线模型：" + message,
                            completed[0] + Math.min(done, stageTotal),
                            total
                        )
                    );
                    completed[0] += stageTotal;
                    sendThrottledLocalBundleDownloadProgress("AI 离线模型已准备完成", completed[0], total);
                }
                if (plan.asrModelRequired) {
                    long stageTotal = LocalAsrDownloader.expectedTotalBytes();
                    new LocalAsrDownloader().ensureChineseModel(
                        this,
                        (message, done, stage) -> sendThrottledLocalBundleDownloadProgress(
                            "本地 ASR：" + message,
                            completed[0] + Math.min(done, stageTotal),
                            total
                        )
                    );
                    completed[0] += stageTotal;
                    sendThrottledLocalBundleDownloadProgress("本地 ASR 已准备完成", completed[0], total);
                }
                if (plan.ttsModelRequired) {
                    long stageTotal = LocalTtsDownloader.expectedTotalBytes();
                    new LocalTtsDownloader().ensureMnnTtsBundle(
                        this,
                        (message, done, stage) -> sendThrottledLocalBundleDownloadProgress(
                            "本地 TTS：" + message,
                            completed[0] + Math.min(done, stageTotal),
                            total
                        )
                    );
                    completed[0] += stageTotal;
                    sendThrottledLocalBundleDownloadProgress("本地 TTS 已准备完成", completed[0], total);
                }

                runOnUiThread(() -> {
                    localBundleDownloadInFlight.set(false);
                    rebuildProcessor();
                    sendModelDownloadProgress("一键本地模型已准备完成", total, total, true, false);
                    LocalRuntimeBundlePlan currentPlan = localRuntimeBundlePlan();
                    sendRuntimeStatus();
                    speakNative("一键本地模型已准备完成，已切换为本地优先。");
                    String warnings = currentPlan.runtimeWarningText();
                    if (!warnings.isEmpty()) {
                        sendError(warnings);
                    }
                    Toast.makeText(this, "已切换为本地优先", Toast.LENGTH_LONG).show();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    localBundleDownloadInFlight.set(false);
                    String message = "一键本地模型下载失败：" + readableError(error);
                    sendModelDownloadProgress(message, Math.min(completed[0], total), total, false, true);
                    sendError(message);
                    speakNative(message);
                });
            }
        });
    }

    private void sendThrottledModelDownloadProgress(String message, long done, long total) {
        int percent = total <= 0L ? 0 : (int) Math.min(100L, (done * 100L) / total);
        if (percent == lastModelDownloadPercent && done < total) {
            return;
        }
        if (percent < 100 && lastModelDownloadPercent >= 0 && percent - lastModelDownloadPercent < 2) {
            return;
        }
        lastModelDownloadPercent = percent;
        sendModelDownloadProgress(message, done, total, done >= total, false);
    }

    private void sendThrottledAsrDownloadProgress(String message, long done, long total) {
        int percent = total <= 0L ? 0 : (int) Math.min(100L, (done * 100L) / total);
        if (percent == lastAsrDownloadPercent && done < total) {
            return;
        }
        if (percent < 100 && lastAsrDownloadPercent >= 0 && percent - lastAsrDownloadPercent < 5) {
            return;
        }
        lastAsrDownloadPercent = percent;
        sendModelDownloadProgress(message, done, total, done >= total, false);
    }

    private void sendThrottledTtsDownloadProgress(String message, long done, long total) {
        int percent = total <= 0L ? 0 : (int) Math.min(100L, (done * 100L) / total);
        if (percent == lastTtsDownloadPercent && done < total) {
            return;
        }
        if (percent < 100 && lastTtsDownloadPercent >= 0 && percent - lastTtsDownloadPercent < 2) {
            return;
        }
        lastTtsDownloadPercent = percent;
        sendModelDownloadProgress(message, done, total, done >= total, false);
    }

    private void sendThrottledLocalBundleDownloadProgress(String message, long done, long total) {
        int percent = total <= 0L ? 0 : (int) Math.min(100L, (done * 100L) / total);
        if (percent == lastLocalBundleDownloadPercent && done < total) {
            return;
        }
        if (percent < 100 && lastLocalBundleDownloadPercent >= 0 && percent - lastLocalBundleDownloadPercent < 1) {
            return;
        }
        lastLocalBundleDownloadPercent = percent;
        sendModelDownloadProgress(message, done, total, done >= total, false);
    }

    private void sendModelDownloadProgress(String message, long done, long total, boolean complete, boolean failed) {
        try {
            int percent = total <= 0L ? 0 : (int) Math.min(100L, Math.max(0L, (done * 100L) / total));
            send(new JSONObject()
                .put("type", "model_download_progress")
                .put("text", message)
                .put("downloaded_bytes", done)
                .put("total_bytes", total)
                .put("percent", percent)
                .put("complete", complete)
                .put("failed", failed));
        } catch (Exception ignored) {
        }
    }

    private void showApiKeyDialog() {
        speakIfVoiceFirst("DashScope Key 设置已打开。联网模式需要填写 DashScope API Key，然后点击保存。");
        EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        input.setText(apiKey());
        input.setSelectAllOnFocus(true);
        input.setHint("sk-...");

        new AlertDialog.Builder(this)
            .setTitle("DashScope API Key")
            .setMessage("优先使用本机保存的 Key；未填写时使用当前安装包默认配置。")
            .setView(input)
            .setPositiveButton("保存", (dialog, which) -> {
                preferences.edit().putString(KEY_API_KEY, input.getText().toString().trim()).apply();
                sendRuntimeStatus();
                flushPendingSpeech();
                speakNative("DashScope Key 已保存。");
            })
            .setNegativeButton("取消", null)
            .show();
    }

    private void showAdvancedDialog() {
        speakIfVoiceFirst("区域和模型设置已打开。一般情况下只需要保持默认。");
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        int padding = (int) (16 * getResources().getDisplayMetrics().density);
        layout.setPadding(padding, 0, padding, 0);

        EditText compatibleUrl = field(compatibleBaseUrl(), "OpenAI 兼容地址");
        EditText apiUrl = field(apiBaseUrl(), "DashScope API 地址");
        EditText vision = field(visionModel(), "视觉模型");
        EditText asr = field(preferences.getString(KEY_ASR_MODEL, "qwen3-asr-flash"), "联网 ASR 模型");

        layout.addView(compatibleUrl);
        layout.addView(apiUrl);
        layout.addView(vision);
        layout.addView(asr);

        new AlertDialog.Builder(this)
            .setTitle("区域/模型")
            .setMessage("默认北京地域。一般只需要填写 Key；不同地域 Key 才需要改这里。")
            .setView(layout)
            .setPositiveButton("保存", (dialog, which) -> preferences.edit()
                .putString(KEY_COMPATIBLE_BASE_URL, trimTrailingSlash(compatibleUrl.getText().toString()))
                .putString(KEY_API_BASE_URL, trimTrailingSlash(apiUrl.getText().toString()))
                .putString(KEY_VISION_MODEL, vision.getText().toString().trim())
                .putString(KEY_MICRO_MODEL, vision.getText().toString().trim())
                .putString(KEY_ASR_MODEL, asr.getText().toString().trim())
                .apply())
            .setNegativeButton("取消", null)
            .show();
    }

    private void showVoiceFirstDialog() {
        boolean enabled = isVoiceFirstEnabledInternal();
        String action = enabled ? "关闭" : "开启";

        if (enabled) {
            speakNative("语音优先模式已开启。关闭后，应用只朗读核心 AI 回答和安全报警，普通状态提示会减少。");
        }

        new AlertDialog.Builder(this)
            .setTitle("语音优先模式")
            .setMessage("默认开启。开启后，应用会主动朗读启动提示、状态变化、按钮反馈、设置状态、跌倒检测倒计时和报警流程，帮助盲人用户不看屏幕也能使用。\n\n" + ttsStatusText())
            .setPositiveButton(action, (dialog, which) -> {
                boolean next = !enabled;
                preferences.edit().putBoolean(KEY_VOICE_FIRST_ENABLED, next).apply();
                speakNative(next ? "语音优先模式已开启。" : "语音优先模式已关闭。");
            })
            .setNeutralButton("测试朗读", (dialog, which) -> speakNative("这是 银龄智护 的语音测试。如果你听到这句话，说明系统朗读正常。"))
            .setNegativeButton("取消", null)
            .show();
    }

    private void showCaptionsDialog() {
        boolean enabled = isCaptionsEnabledInternal();
        speakIfVoiceFirst(enabled ? "语音字幕已开启。" : "语音字幕已关闭。");

        new AlertDialog.Builder(this)
            .setTitle("语音字幕")
            .setMessage("开启后，主屏会显示两行字幕：我说的识别文字，以及 银龄智护 的 AI 回复。关闭后只隐藏字幕面板，不影响语音识别、AI 回复和朗读。")
            .setPositiveButton(enabled ? "关闭字幕" : "开启字幕", (dialog, which) -> {
                boolean next = !enabled;
                preferences.edit().putBoolean(KEY_CAPTIONS_ENABLED, next).apply();
                sendRuntimeStatus();
                speakNative(next ? "语音字幕已开启。" : "语音字幕已关闭。");
            })
            .setNegativeButton("取消", null)
            .show();
    }

    private void showFallDetectionDialog() {
        boolean enabled = isFallDetectionEnabledInternal();
        String action = enabled ? "关闭" : "开启";

        speakIfVoiceFirst(enabled
            ? "跌倒检测当前已开启。你可以选择关闭。"
            : "跌倒检测当前已关闭。你可以选择开启。");

        new AlertDialog.Builder(this)
            .setTitle("跌倒检测")
            .setMessage("使用本机加速度/陀螺仪和最近几秒摄像头画面变化进行判断，不把单帧画面发给 AI 做确认。检测到疑似摔倒后会先询问，10 秒内未取消才发送报警事件。")
            .setPositiveButton(action, (dialog, which) -> {
                boolean next = !enabled;
                preferences.edit().putBoolean(KEY_FALL_DETECTION_ENABLED, next).apply();
                speakNative(next ? "跌倒检测已开启。" : "跌倒检测已关闭。");
            })
            .setNegativeButton("取消", null)
            .show();
    }

    private EditText field(String value, String hint) {
        EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setText(value);
        input.setHint(hint);
        return input;
    }

    @Override
    public void send(JSONObject data) {
        if (webView == null) return;
        logNativeMessage(data);
        String script = "window.LONG_TERM_CARE_NATIVE_MESSAGE && window.LONG_TERM_CARE_NATIVE_MESSAGE(" + data + ");";
        webView.post(() -> webView.evaluateJavascript(script, null));
    }

    private void logNativeMessage(JSONObject data) {
        try {
            JSONObject summary = new JSONObject()
                .put("type", data == null ? "" : data.optString("type", ""))
                .put("ms", data == null ? JSONObject.NULL : data.opt("ms"));
            if (data != null) {
                for (String key : new String[]{"text", "speech", "transcript", "thinking", "mode", "priority", "subject"}) {
                    if (data.has(key)) {
                        Object value = data.opt(key);
                        summary.put(key, value instanceof String ? DiagnosticLogger.excerpt((String) value) : value);
                    }
                }
            }
            DiagnosticLogger.event("webview_message_send", summary);
        } catch (Exception ignored) {
        }
    }

    private void notifyWebTtsState(boolean speaking) {
        if (webView == null) return;
        webView.post(() -> webView.evaluateJavascript(
            "window.LONG_TERM_CARE_TTS_STATE_CHANGED && window.LONG_TERM_CARE_TTS_STATE_CHANGED(" + speaking + ");",
            null
        ));
    }

    private void submitFrame(String imageDataUrl) {
        if (!ensureAiRuntimeReady()) {
            return;
        }
        if (!frameInFlight.compareAndSet(false, true)) {
            return;
        }
        executor.execute(() -> {
            try {
                processor.processFrame(imageDataUrl);
            } finally {
                frameInFlight.set(false);
            }
        });
    }

    private void submitInquiry(String imageDataUrl, String audioDataUrl) {
        if (!ensureAiRuntimeReady()) {
            return;
        }
        executor.execute(() -> processor.processInquiry(imageDataUrl, audioDataUrl));
    }

    private void submitTextInquiry(String imageDataUrl, String transcript) {
        if (!ensureAiRuntimeReady()) {
            return;
        }
        executor.execute(() -> processor.processTextInquiry(imageDataUrl, transcript));
    }

    private void submitRecognizedSpeech(String imageDataUrl, String rawTranscript, boolean correctWithLocalAi) {
        executor.execute(() -> processRecognizedSpeech(imageDataUrl, rawTranscript, correctWithLocalAi));
    }

    private void processRecognizedSpeech(String imageDataUrl, String rawTranscript, boolean correctWithLocalAi) {
        long started = DiagnosticLogger.start();
        String transcript = "";
        try {
            DiagnosticLogger.eventPairs(
                "speech_process_recognized_start",
                "raw_transcript", DiagnosticLogger.excerpt(rawTranscript),
                "raw_chars", rawTranscript == null ? 0 : rawTranscript.length(),
                "correct_with_local_ai", correctWithLocalAi
            );
            transcript = LocalAsrTextCorrector.fastCorrect(rawTranscript);
            DiagnosticLogger.eventPairs(
                "speech_fast_correction_done",
                "elapsed_ms", DiagnosticLogger.elapsed(started),
                "transcript", DiagnosticLogger.excerpt(transcript),
                "changed", rawTranscript != null && !rawTranscript.trim().equals(transcript)
            );
            if (transcript.isEmpty()) {
                sendSpeechTranscript("");
                sendError("没有识别到清晰语音。");
                return;
            }
            sendSpeechTranscript(transcript);
            processor.processTextInquiry(imageDataUrl, transcript);
        } finally {
            DiagnosticLogger.eventPairs(
                "speech_process_recognized_end",
                "elapsed_ms", DiagnosticLogger.elapsed(started),
                "final_transcript", DiagnosticLogger.excerpt(transcript)
            );
            finishSpeechRequest();
            finishNativeSpeechUi();
        }
    }

    private void submitAsrCorrection(String rawTranscript) {
        executor.execute(() -> {
            String fallback = LocalAsrTextCorrector.sanitize(rawTranscript);
            String corrected = correctLocalAsrTranscript(fallback);
            if (!corrected.isEmpty() && !corrected.equals(fallback)) {
                sendSpeechTranscriptCorrection(fallback, corrected);
            }
        });
    }

    private String correctLocalAsrTranscript(String rawTranscript) {
        String fallback = LocalAsrTextCorrector.sanitize(rawTranscript);
        if (fallback.isEmpty()) return "";
        if (!offlineStatus().ready()) return fallback;

        Future<String> task = null;
        try {
            SilverCareArtificialIntelligenceClient.SettingsProvider settings = offlineCorrectionSettings();
            OfflineAiClient client = new OfflineAiClient(
                settings,
                new MnnOfflineEngine(settings, offlineModelManager, mnnRuntimeBridge)
            );
            task = asrCorrectionExecutor.submit(() -> client.textJson(
                LocalAsrTextCorrector.prompt(fallback),
                settings.textModel(),
                64,
                "}"
            ));
            String rawResponse = task.get(LOCAL_ASR_CORRECTION_TIMEOUT_MS, TimeUnit.MILLISECONDS);
            return LocalAsrTextCorrector.correctedText(rawResponse, fallback);
        } catch (TimeoutException timeout) {
            if (task != null) task.cancel(true);
            return fallback;
        } catch (Exception error) {
            Log.w(TAG, "Local ASR correction skipped: " + readableError(error));
            return fallback;
        }
    }

    private void sendError(String text) {
        try {
            send(new JSONObject().put("type", "error").put("text", text));
        } catch (Exception ignored) {
        }
    }

    private boolean hasDashScopeKeyInternal() {
        return apiKey() != null && !apiKey().trim().isEmpty();
    }

    private OfflineModelStatus offlineStatus() {
        OfflineModelManager manager = offlineModelManager == null ? new OfflineModelManager() : offlineModelManager;
        MnnRuntimeBridge bridge = mnnRuntimeBridge == null ? new MnnNativeBridge() : mnnRuntimeBridge;
        return manager.inspect(offlineModelDir(), offlineTextModel(), bridge.isAvailable());
    }

    private LocalAsrModelStatus localAsrStatus() {
        LocalAsrModelManager manager = localAsrModelManager == null ? new LocalAsrModelManager() : localAsrModelManager;
        return manager.inspect(this);
    }

    private LocalTtsModelStatus localTtsStatus() {
        LocalTtsModelManager manager = localTtsModelManager == null ? new LocalTtsModelManager() : localTtsModelManager;
        if (!LOCAL_MNN_TTS_VOICE_QUALITY_ENABLED) {
            return manager.inspect(this, false, "本地 MNN TTS 音质测试未通过，已停用。");
        }
        LocalTtsRuntimeBridge bridge = localTtsRuntimeBridge == null ? new MnnTtsRuntimeBridge() : localTtsRuntimeBridge;
        return manager.inspect(this, bridge.isAvailable(), bridge.runtimeSummary());
    }

    private void maybePrewarmLocalModels(String reason) {
        if (executor == null || localPrewarmInFlight == null || localPrewarmCompleted == null) return;
        if (!currentRuntimeMode().isOffline()) {
            localPrewarmCompleted.set(false);
            Log.i(TAG, "Local model prewarm skipped: runtime is not offline, reason=" + reason);
            return;
        }
        if (localPrewarmCompleted.get()) {
            Log.i(TAG, "Local model prewarm skipped: already completed, reason=" + reason);
            return;
        }

        OfflineModelStatus offlineStatus = offlineStatus();
        if (!offlineStatus.ready()) {
            Log.i(TAG, "Local model prewarm skipped: offline models are not ready, reason=" + reason);
            return;
        }
        if (!localPrewarmInFlight.compareAndSet(false, true)) {
            Log.i(TAG, "Local model prewarm skipped: already running, reason=" + reason);
            return;
        }

        Log.i(TAG, "Local model prewarm scheduled: reason=" + reason);
        executor.execute(() -> {
            long startedAt = System.currentTimeMillis();
            JSONObject report = new JSONObject();
            try {
                putPrewarm(report, "reason", reason);
                prewarmLocalAsr(report);
                prewarmLocalVision(offlineStatus, report);
                prewarmLocalText(offlineStatus, report);
                prewarmLocalTts(report);
                localPrewarmCompleted.set(true);
                putPrewarm(report, "ok", true);
            } catch (Exception error) {
                putPrewarm(report, "ok", false);
                putPrewarm(report, "error", readableError(error));
                Log.w(TAG, "Local model prewarm failed: " + readableError(error));
            } finally {
                putPrewarm(report, "total_ms", System.currentTimeMillis() - startedAt);
                Log.i(TAG, "Local model prewarm: " + report);
                localPrewarmInFlight.set(false);
            }
        });
    }

    private void prewarmLocalAsr(JSONObject report) {
        LocalAsrModelStatus status = localAsrStatus();
        if (!status.ready) {
            putPrewarm(report, "asr", "skipped");
            return;
        }
        long startedAt = System.currentTimeMillis();
        try {
            localAsrEngine.transcribePcm(status.modelDir, silencePcm16k(600));
            putPrewarm(report, "asr", System.currentTimeMillis() - startedAt);
        } catch (Exception error) {
            String message = readableError(error);
            if (message.contains("没有识别到")) {
                putPrewarm(report, "asr", System.currentTimeMillis() - startedAt);
            } else {
                putPrewarm(report, "asr_error", message);
            }
        }
    }

    private void prewarmLocalVision(OfflineModelStatus status, JSONObject report) {
        if (mnnRuntimeBridge == null || !mnnRuntimeBridge.isAvailable()) {
            putPrewarm(report, "vision", "skipped");
            return;
        }
        long startedAt = System.currentTimeMillis();
        try {
            mnnRuntimeBridge.visionJson(
                status.modelDir,
                "warmup",
                prewarmImageDataUrl(),
                OfflineAiClient.DETECTOR_MODEL
            );
            putPrewarm(report, "vision", System.currentTimeMillis() - startedAt);
        } catch (Exception error) {
            putPrewarm(report, "vision_error", readableError(error));
        }
    }

    private void prewarmLocalText(OfflineModelStatus status, JSONObject report) {
        if (mnnRuntimeBridge == null || !mnnRuntimeBridge.isAvailable()) {
            putPrewarm(report, "text", "skipped");
            return;
        }
        long startedAt = System.currentTimeMillis();
        try {
            boolean sme2Supported = mnnRuntimeBridge.supportsSme2();
            String tuning = MnnLlmTuningProfile.from(mnnLlmTuningMode()).nativeConfigJson(sme2Supported);
            mnnRuntimeBridge.textJson(
                status.modelDir,
                "Return one JSON object only: {\"warmup\":true}",
                status.textModel,
                tuning,
                32,
                "}"
            );
            putPrewarm(report, "text", System.currentTimeMillis() - startedAt);
        } catch (Exception error) {
            putPrewarm(report, "text_error", readableError(error));
        }
    }

    private void prewarmLocalTts(JSONObject report) {
        if (!LOCAL_MNN_TTS_VOICE_QUALITY_ENABLED) {
            putPrewarm(report, "tts", "skipped_voice_quality_failed");
            return;
        }
        LocalTtsModelStatus status = localTtsStatus();
        if (!status.ready || localTtsRuntimeBridge == null) {
            putPrewarm(report, "tts", "skipped");
            return;
        }
        long startedAt = System.currentTimeMillis();
        try {
            File output = localTtsRuntimeBridge.synthesizeToWav(
                status.modelDir,
                new File(getCacheDir(), "local-tts-prewarm"),
                "预热完成",
                "zh-CN"
            );
            if (output != null && output.isFile()) output.delete();
            putPrewarm(report, "tts", System.currentTimeMillis() - startedAt);
        } catch (Exception error) {
            putPrewarm(report, "tts_error", readableError(error));
        }
    }

    private static byte[] silencePcm16k(int durationMs) {
        int byteCount = Math.max(1600, 16_000 * 2 * durationMs / 1000);
        return new byte[byteCount];
    }

    private static String prewarmImageDataUrl() {
        android.graphics.Bitmap bitmap = android.graphics.Bitmap.createBitmap(
            64,
            64,
            android.graphics.Bitmap.Config.ARGB_8888
        );
        bitmap.eraseColor(android.graphics.Color.rgb(32, 36, 40));
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, output);
        bitmap.recycle();
        return "data:image/jpeg;base64," + Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP);
    }

    private static void putPrewarm(JSONObject report, String key, Object value) {
        try {
            report.put(key, value);
        } catch (Exception ignored) {
        }
    }

    private AsrRuntimeMode currentAsrRuntimeMode() {
        String saved = preferences.getString(KEY_ASR_RUNTIME_MODE, "");
        if (saved != null && !saved.trim().isEmpty()) {
            return AsrRuntimeMode.from(saved);
        }
        return AsrRuntimeMode.DEFAULT;
    }

    private TtsRuntimeMode currentTtsRuntimeMode() {
        return TtsRuntimeMode.from(preferences.getString(
            KEY_TTS_RUNTIME_MODE,
            TtsRuntimeMode.DEFAULT.value
        ));
    }

    private void migrateDisabledLocalMnnTtsPreference() {
        if (LOCAL_MNN_TTS_VOICE_QUALITY_ENABLED) return;
        String stored = preferences.getString(KEY_TTS_RUNTIME_MODE, TtsRuntimeMode.DEFAULT.value);
        if (TtsRuntimeMode.LOCAL_MNN.value.equals(stored) || "local_qwen".equals(stored)) {
            preferences.edit().putString(KEY_TTS_RUNTIME_MODE, TtsRuntimeMode.DEFAULT.value).apply();
        }
    }

    private NavigationRefreshMode currentNavigationRefreshMode() {
        return NavigationRefreshMode.from(preferences.getString(
            KEY_NAVIGATION_REFRESH_MODE,
            NavigationRefreshMode.DEFAULT.value
        ));
    }

    private int currentNavigationRefreshIntervalSeconds() {
        return clampNavigationRefreshSeconds(preferences.getInt(
            KEY_NAVIGATION_REFRESH_INTERVAL_SECONDS,
            3
        ));
    }

    private static int clampNavigationRefreshSeconds(String value) {
        try {
            return clampNavigationRefreshSeconds(Integer.parseInt(value == null ? "" : value.trim()));
        } catch (Exception ignored) {
            return 1;
        }
    }

    private static int clampNavigationRefreshSeconds(int seconds) {
        return Math.max(1, Math.min(10, seconds));
    }

    private boolean isSmartNavigationRefreshEnabledInternal() {
        return preferences.getBoolean(KEY_SMART_NAVIGATION_REFRESH_ENABLED, false);
    }

    private MnnLlmTuningProfile currentMnnLlmTuningProfile() {
        return MnnLlmTuningProfile.from(preferences.getString(
            KEY_MNN_LLM_TUNING_MODE,
            MnnLlmTuningProfile.DEFAULT.value
        ));
    }

    private void sendRuntimeStatus() {
        if (webView == null) return;
        try {
            OfflineModelStatus status = offlineStatus();
            LocalAsrModelStatus asrStatus = localAsrStatus();
            LocalTtsModelStatus ttsLocalStatus = localTtsStatus();
            AsrRuntimeMode asrMode = currentAsrRuntimeMode();
            TtsRuntimeMode ttsMode = currentTtsRuntimeMode();
            NavigationRefreshMode refreshMode = currentNavigationRefreshMode();
            int refreshIntervalMs = currentNavigationRefreshIntervalSeconds() * 1000;
            MnnLlmTuningProfile tuning = currentMnnLlmTuningProfile();
            boolean sme2Supported = mnnRuntimeBridge != null && mnnRuntimeBridge.supportsSme2();
            send(new JSONObject()
                .put("type", "runtime_status")
                .put("ai_runtime_mode", currentRuntimeMode().value)
                .put("runtime_label", currentRuntimeMode().label)
                .put("offline_ready", status.ready())
                .put("offline_text_model", status.textModel)
                .put("offline_text_model_label", OfflineAiClient.textModelLabel(status.textModel))
                .put("offline_status", status.shortText())
                .put("asr_runtime_mode", asrMode.value)
                .put("asr_runtime_label", asrMode.label)
                .put("local_asr_enabled", asrMode.isLocal())
                .put("local_asr_ready", localAsrReady(asrStatus))
                .put("local_asr_status", asrStatus.shortText())
                .put("tts_runtime_mode", ttsMode.value)
                .put("tts_runtime_label", ttsMode.label)
                .put("tts_status", ttsStatusText())
                .put("local_tts_ready", ttsLocalStatus.ready)
                .put("local_tts_model_ready", ttsLocalStatus.modelReady)
                .put("local_tts_runtime_available", ttsLocalStatus.runtimeAvailable)
                .put("local_tts_status", ttsLocalStatus.shortText())
                .put("mnn_llm_tuning_mode", tuning.value)
                .put("mnn_llm_tuning_label", tuning.label)
                .put("mnn_sme2_supported", sme2Supported)
                .put("navigation_refresh_mode", refreshMode.value)
                .put("navigation_refresh_label", refreshMode.label)
                .put("navigation_refresh_interval_ms", refreshIntervalMs)
                .put("smart_navigation_refresh_enabled", isSmartNavigationRefreshEnabledInternal())
                .put("captions_enabled", isCaptionsEnabledInternal()));
        } catch (Exception ignored) {
        }
    }

    private boolean ensureAiRuntimeReady() {
        if (currentRuntimeMode().isOffline()) {
            OfflineModelStatus status = offlineStatus();
            if (!status.ready()) {
                sendError(status.shortText());
                speakIfVoiceFirst(status.shortText());
                return false;
            }
            return true;
        }

        if (!hasDashScopeKeyInternal()) {
            sendError("请先在右上角菜单填写 DashScope Key，或在设置里切换到端侧离线模式。");
            return false;
        }
        return true;
    }

    private boolean isFallDetectionEnabledInternal() {
        return preferences.getBoolean(KEY_FALL_DETECTION_ENABLED, true);
    }

    private boolean isCaptionsEnabledInternal() {
        return preferences.getBoolean(KEY_CAPTIONS_ENABLED, true);
    }

    private String localAsrSettingsText(LocalAsrModelStatus status) {
        AsrRuntimeMode mode = currentAsrRuntimeMode();
        if (!mode.isLocal()) return "ASR 方案：联网 DashScope";
        return status.ready ? "ASR 方案：本地内置识别" : "ASR 方案：本地内置识别未就绪";
    }

    private String localAsrDetailText(LocalAsrModelStatus status) {
        StringBuilder builder = new StringBuilder();
        builder.append("本地 ASR 模型：")
            .append(status.ready ? "已就绪" : "未下载")
            .append("\n本地 AI 校对：")
            .append(offlineStatus().ready() ? "可用" : "离线文本模型未就绪时会跳过")
            .append("\n依赖方式：应用内置模型本地推理，不调用 Google、GMS 或 Android 系统语音服务")
            .append("\n\n本地 ASR 详情：\n")
            .append(status.detailText());
        return builder.toString();
    }

    private boolean localAsrReady(LocalAsrModelStatus status) {
        return status != null && status.ready;
    }

    private String ttsSettingsText() {
        TtsRuntimeMode mode = currentTtsRuntimeMode();
        LocalTtsModelStatus localStatus = localTtsStatus();
        if (mode == TtsRuntimeMode.AUTO) return "TTS 方案：自动兜底";
        if (mode == TtsRuntimeMode.LOCAL_MNN) {
            return "TTS 方案：本地 MNN TTS 实验项，当前会回退";
        }
        if (mode == TtsRuntimeMode.DASHSCOPE) return "TTS 方案：联网 DashScope";
        return ttsReady ? "TTS 方案：手机系统 TTS（本地）" : "TTS 方案：手机系统 TTS 未就绪";
    }

    private String mnnTuningSettingsText() {
        MnnLlmTuningProfile profile = currentMnnLlmTuningProfile();
        boolean sme2Supported = mnnRuntimeBridge != null && mnnRuntimeBridge.supportsSme2();
        String suffix = sme2Supported ? "" : "（回退）";
        return "离线推理调优：" + profile.label + suffix;
    }

    private String navigationRefreshSettingsText() {
        NavigationRefreshMode mode = currentNavigationRefreshMode();
        String smart = isSmartNavigationRefreshEnabledInternal() ? "，智能刷新开" : "";
        return mode.isManual()
            ? "导航刷新：手动单击刷新" + smart
            : "导航刷新：自动每" + currentNavigationRefreshIntervalSeconds() + "秒刷新" + smart;
    }

    private boolean isVoiceFirstEnabledInternal() {
        return preferences.getBoolean(KEY_VOICE_FIRST_ENABLED, true);
    }

    private void triggerFallAlarm(String evidenceJson) {
        try {
            send(new JSONObject()
                .put("type", "fall_alarm")
                .put("text", "已发送报警"));
        } catch (Exception ignored) {
        }
    }

    private void speakNative(String text) {
        if (text == null || text.trim().isEmpty()) return;
        DiagnosticLogger.eventPairs(
            "tts_request",
            "tts_runtime", currentTtsRuntimeMode().value,
            "chars", text.length(),
            "text", DiagnosticLogger.excerpt(text)
        );
        runOnUiThread(() -> {
            TtsRuntimeMode mode = currentTtsRuntimeMode();
            LocalTtsModelStatus localStatus = localTtsStatus();
            if (mode.allowsSystem() && tts != null && ttsReady) {
                speakSystemTts(text);
                return;
            }
            if (mode.allowsDashScope() && hasDashScopeKeyInternal()) {
                speakDashScopeTts(text);
                return;
            }
            if (mode == TtsRuntimeMode.LOCAL_MNN || (mode == TtsRuntimeMode.AUTO && canUseLocalMnnTts(localStatus))) {
                if (canUseLocalMnnTts(localStatus)) {
                    speakLocalMnnTts(text, localStatus);
                    return;
                }
                logLocalTtsFallback("本地 MNN TTS 音质测试未通过，已禁用主朗读");
                speakWithNonLocalFallback(text);
                return;
            }
            if (mode == TtsRuntimeMode.SYSTEM || !hasDashScopeKeyInternal()) {
                queuePendingSpeech(text);
            }
            notifyWebTtsState(false);
            logTtsFailure(ttsStatusText() + "，暂时无法朗读。");
        });
    }

    private void speakSystemTts(String text) {
        long started = DiagnosticLogger.start();
        try {
            ensureSpeechAudible();
            Bundle params = new Bundle();
            params.putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f);
            notifyWebTtsState(true);
            int result = tts.speak(text, TextToSpeech.QUEUE_FLUSH, params, "silvercare-" + System.nanoTime());
            DiagnosticLogger.eventPairs(
                "tts_system_submit",
                "elapsed_ms", DiagnosticLogger.elapsed(started),
                "engine", ttsEnginePackage,
                "result", result,
                "chars", text == null ? 0 : text.length()
            );
            if (result == TextToSpeech.ERROR) {
                notifyWebTtsState(false);
                logTtsFailure("系统 TTS 播放失败。请检查手机的文字转语音引擎和媒体音量。");
            }
        } catch (Exception error) {
            notifyWebTtsState(false);
            logTtsFailure("系统 TTS 播放失败：" + readableError(error));
        }
    }

    private void speakLocalMnnTts(String text, LocalTtsModelStatus status) {
        if (localTtsInFlight != null && !localTtsInFlight.compareAndSet(false, true)) {
            logLocalTtsFallback("本地 MNN TTS 上一次合成仍未结束");
            speakWithNonLocalFallback(text);
            return;
        }
        int serial = dashScopeTtsSerial.incrementAndGet();
        AtomicBoolean completed = new AtomicBoolean(false);
        notifyWebTtsState(true);
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            if (completed.get()) return;
            if (serial != dashScopeTtsSerial.get()) return;
            dashScopeTtsSerial.incrementAndGet();
            notifyWebTtsState(false);
            logLocalTtsFallback("本地 MNN TTS 超过 " + (LOCAL_TTS_TIMEOUT_MS / 1000) + " 秒未返回");
            speakWithNonLocalFallback(text);
        }, LOCAL_TTS_TIMEOUT_MS);
        executor.execute(() -> {
            try {
                File cacheDir = new File(getCacheDir(), "tts");
                File wav = localTtsRuntimeBridge.synthesizeToWav(status.modelDir, cacheDir, text, "zh-CN");
                completed.set(true);
                if (localTtsInFlight != null) localTtsInFlight.set(false);
                runOnUiThread(() -> {
                    if (serial != dashScopeTtsSerial.get()) {
                        deleteQuietly(wav);
                        return;
                    }
                    playTtsAudioSource(wav.getAbsolutePath(), "本地 TTS", wav);
                });
            } catch (Exception error) {
                completed.set(true);
                if (localTtsInFlight != null) localTtsInFlight.set(false);
                runOnUiThread(() -> {
                    if (serial == dashScopeTtsSerial.get()) {
                        logLocalTtsFallback("本地 TTS 失败：" + readableError(error));
                        speakWithNonLocalFallback(text);
                    }
                });
            }
        });
    }

    private void logLocalTtsFallback(String reason) {
        long now = System.currentTimeMillis();
        if (now - lastLocalTtsFallbackLogAt < 60_000L) return;
        lastLocalTtsFallbackLogAt = now;
        Log.w(TAG, reason + "，使用非本地朗读兜底。");
    }

    private void logTtsFailure(String reason) {
        long now = System.currentTimeMillis();
        if (now - lastTtsFailureLogAt < 60_000L) return;
        lastTtsFailureLogAt = now;
        Log.w(TAG, reason);
    }

    private void speakWithNonLocalFallback(String text) {
        if (tts != null && ttsReady) {
            speakSystemTts(text);
            return;
        }
        if (hasDashScopeKeyInternal()) {
            speakDashScopeTts(text);
            return;
        }
        queuePendingSpeech(text);
        logTtsFailure("系统 TTS 和联网 DashScope TTS 都不可用，暂时无法朗读。");
    }

    private void speakDashScopeTts(String text) {
        int serial = dashScopeTtsSerial.incrementAndGet();
        notifyWebTtsState(true);
        executor.execute(() -> {
            try {
                String audioUrl = new DashScopeClient(this).synthesizeSpeechUrl(text);
                runOnUiThread(() -> {
                    if (serial != dashScopeTtsSerial.get()) return;
                    playTtsAudioSource(audioUrl, "联网 TTS", null);
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (serial == dashScopeTtsSerial.get()) {
                        notifyWebTtsState(false);
                        logTtsFailure("联网 TTS 失败：" + readableError(error));
                    }
                });
            }
        });
    }

    private void playTtsAudioSource(String audioSource, String label, @Nullable File cleanupFile) {
        if (audioSource == null || audioSource.trim().isEmpty()) {
            notifyWebTtsState(false);
            logTtsFailure(label + " 返回了空音频地址。");
            return;
        }
        ensureSpeechAudible();
        notifyWebTtsState(true);
        releaseDashScopeTtsPlayer();
        MediaPlayer player = new MediaPlayer();
        dashScopeTtsPlayer = player;
        player.setAudioAttributes(new AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build());
        player.setOnPreparedListener(MediaPlayer::start);
        player.setOnCompletionListener(done -> {
            if (dashScopeTtsPlayer == done) releaseDashScopeTtsPlayer();
            deleteQuietly(cleanupFile);
            notifyWebTtsState(false);
        });
        player.setOnErrorListener((failed, what, extra) -> {
            if (dashScopeTtsPlayer == failed) releaseDashScopeTtsPlayer();
            deleteQuietly(cleanupFile);
            notifyWebTtsState(false);
            logTtsFailure(label + " 播放失败。");
            return true;
        });
        try {
            player.setDataSource(audioSource);
            player.prepareAsync();
        } catch (Exception error) {
            releaseDashScopeTtsPlayer();
            deleteQuietly(cleanupFile);
            notifyWebTtsState(false);
            logTtsFailure(label + " 播放失败：" + readableError(error));
        }
    }

    private void releaseDashScopeTtsPlayer() {
        MediaPlayer player = dashScopeTtsPlayer;
        dashScopeTtsPlayer = null;
        if (player != null) {
            try {
                player.release();
            } catch (Exception ignored) {
            }
        }
    }

    private void stopCurrentTtsPlayback() {
        dashScopeTtsSerial.incrementAndGet();
        releaseDashScopeTtsPlayer();
        if (tts != null) {
            try {
                tts.stop();
            } catch (Exception ignored) {
            }
        }
        notifyWebTtsState(false);
    }

    private static void deleteQuietly(@Nullable File file) {
        if (file == null) return;
        try {
            if (file.exists()) file.delete();
        } catch (Exception ignored) {
        }
    }

    private void initializeTts() {
        List<String> candidates = ttsEngineCandidates();
        initializeTtsCandidate(candidates, 0);
    }

    private List<String> ttsEngineCandidates() {
        List<String> candidates = new ArrayList<>();
        String defaultEngine = "";
        try {
            defaultEngine = Settings.Secure.getString(getContentResolver(), "tts_default_synth");
        } catch (Exception ignored) {
        }
        if (defaultEngine != null && !defaultEngine.trim().isEmpty()) {
            if (isPackageInstalled(defaultEngine.trim())) {
                addTtsCandidate(candidates, defaultEngine.trim());
            } else {
                Log.w(TAG, "System default TTS package is not installed: " + defaultEngine);
            }
        }

        try {
            Intent intent = new Intent("android.intent.action.TTS_SERVICE");
            List<ResolveInfo> services = getPackageManager().queryIntentServices(intent, 0);
            for (ResolveInfo info : services) {
                if (info == null || info.serviceInfo == null) continue;
                addTtsCandidate(candidates, info.serviceInfo.packageName);
            }
        } catch (Exception error) {
            Log.w(TAG, "Unable to query TTS engines: " + readableError(error));
        }
        addTtsCandidate(candidates, null);
        return candidates;
    }

    private static void addTtsCandidate(List<String> candidates, @Nullable String enginePackage) {
        String normalized = enginePackage == null ? null : enginePackage.trim();
        for (String existing : candidates) {
            if (existing == null && normalized == null) return;
            if (existing != null && existing.equals(normalized)) return;
        }
        candidates.add(normalized == null || normalized.isEmpty() ? null : normalized);
    }

    private void initializeTtsCandidate(List<String> candidates, int index) {
        if (index >= candidates.size()) {
            ttsReady = false;
            ttsEnginePackage = "unavailable";
            logTtsFailure("系统文字转语音初始化失败。请在手机系统里安装或启用中文 TTS 引擎。");
            return;
        }
        String enginePackage = candidates.get(index);
        ttsEnginePackage = enginePackage == null ? "system-default" : enginePackage;
        int serial = ttsInitSerial.incrementAndGet();
        Log.i(TAG, "Initializing TTS engine=" + ttsEnginePackage);
        tts = new TextToSpeech(this, status -> {
            if (serial != ttsInitSerial.get()) return;
            Log.i(TAG, "TTS init callback engine=" + ttsEnginePackage + " status=" + status);
            if (status == TextToSpeech.SUCCESS) {
                configureTtsEngine();
                if (!ttsReady) {
                    retryNextTtsEngine(candidates, index, serial, "TTS engine does not support Chinese speech");
                    return;
                }
                flushPendingSpeech();
            } else {
                ttsReady = false;
                retryNextTtsEngine(candidates, index, serial, "TTS engine init failed");
            }
        }, enginePackage);
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            if (serial != ttsInitSerial.get()) return;
            if (ttsReady) return;
            retryNextTtsEngine(candidates, index, serial, "TTS engine init timed out");
        }, TTS_INIT_TIMEOUT_MS);
    }

    private void retryNextTtsEngine(List<String> candidates, int index, int serial, String reason) {
        if (serial != ttsInitSerial.get()) return;
        Log.w(TAG, reason + ": " + ttsEnginePackage);
        TextToSpeech failed = tts;
        tts = null;
        ttsReady = false;
        if (failed != null) {
            try {
                failed.shutdown();
            } catch (Exception ignored) {
            }
        }
        initializeTtsCandidate(candidates, index + 1);
    }

    private boolean isPackageInstalled(String packageName) {
        try {
            getPackageManager().getPackageInfo(packageName, 0);
            return true;
        } catch (PackageManager.NameNotFoundException ignored) {
            return false;
        }
    }

    private void configureTtsEngine() {
        if (tts == null) {
            ttsReady = false;
            return;
        }
        tts.setAudioAttributes(new AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build());
        int language = tts.setLanguage(Locale.CHINA);
        if (language == TextToSpeech.LANG_MISSING_DATA || language == TextToSpeech.LANG_NOT_SUPPORTED) {
            language = tts.setLanguage(Locale.getDefault());
        }
        ttsReady = language != TextToSpeech.LANG_MISSING_DATA
            && language != TextToSpeech.LANG_NOT_SUPPORTED;
        tts.setSpeechRate(1.0f);
        tts.setPitch(1.0f);
        tts.setOnUtteranceProgressListener(new UtteranceProgressListener() {
            @Override
            public void onStart(String utteranceId) {
                notifyWebTtsState(true);
            }

            @Override
            public void onDone(String utteranceId) {
                notifyWebTtsState(false);
            }

            @Override
            public void onError(String utteranceId) {
                notifyWebTtsState(false);
            }

            @Override
            public void onStop(String utteranceId, boolean interrupted) {
                notifyWebTtsState(false);
            }
        });
        Log.i(TAG, "TTS configured engine=" + ttsEnginePackage + " languageResult=" + language + " ready=" + ttsReady);
        if (!ttsReady) {
            logTtsFailure("系统 TTS 不支持当前语言。请在手机系统里安装或启用中文文字转语音引擎。");
        }
    }

    private void ensureSpeechAudible() {
        if (audioManager == null) return;
        int max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
        int current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC);
        if (max <= 0 || current > 0) return;
        int target = Math.max(1, max / 3);
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0);
        Toast.makeText(this, "已临时调高媒体音量用于朗读", Toast.LENGTH_SHORT).show();
    }

    private String ttsStatusText() {
        TtsRuntimeMode mode = currentTtsRuntimeMode();
        LocalTtsModelStatus localStatus = localTtsStatus();
        String systemStatus;
        if (tts == null) {
            systemStatus = "系统 TTS 尚未初始化";
        } else if (!ttsReady) {
            systemStatus = "系统 TTS 未就绪";
        } else {
            systemStatus = "系统 TTS 已就绪，" + systemTtsEngineText();
        }

        if (mode == TtsRuntimeMode.LOCAL_MNN) {
            return "本地 MNN TTS 音质测试未通过，当前会回退手机系统 TTS 或 DashScope";
        }
        if (mode == TtsRuntimeMode.DASHSCOPE) {
            return hasDashScopeKeyInternal()
                ? "联网 DashScope TTS 已就绪"
                : "联网 DashScope TTS 需要 DashScope Key";
        }
        if (mode == TtsRuntimeMode.SYSTEM) {
            return systemStatus;
        }
        if (ttsReady) {
            return "自动兜底：" + systemStatus;
        }
        return hasDashScopeKeyInternal()
            ? "自动兜底：系统 TTS 未就绪，将使用联网 DashScope TTS"
            : "自动兜底：系统 TTS 未就绪，联网 TTS 需要 DashScope Key";
    }

    private String systemTtsEngineText() {
        if (audioManager == null) return "引擎 " + ttsEnginePackage;
        int current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC);
        int max = Math.max(1, audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC));
        return "引擎 " + ttsEnginePackage + "，媒体音量 " + current + "/" + max;
    }

    private void queuePendingSpeech(String text) {
        pendingTts.add(text);
        while (pendingTts.size() > 3) {
            pendingTts.remove(0);
        }
    }

    private void flushPendingSpeech() {
        if (pendingTts.isEmpty()) return;
        TtsRuntimeMode mode = currentTtsRuntimeMode();
        LocalTtsModelStatus localStatus = localTtsStatus();
        boolean localReady = mode.allowsLocal() && canUseLocalMnnTts(localStatus);
        boolean systemReady = mode.allowsSystem() && ttsReady && tts != null;
        boolean dashScopeReady = mode.allowsDashScope() && hasDashScopeKeyInternal();
        boolean explicitLocalFallbackReady = mode == TtsRuntimeMode.LOCAL_MNN
            && ((ttsReady && tts != null) || hasDashScopeKeyInternal());
        if (!(localReady || systemReady || dashScopeReady || explicitLocalFallbackReady)) {
            return;
        }
        List<String> copy = new ArrayList<>(pendingTts);
        pendingTts.clear();
        if (localReady || !systemReady) {
            speakNative(copy.get(copy.size() - 1));
            return;
        }
        for (int i = 0; i < copy.size(); i += 1) {
            int queueMode = i == 0 ? TextToSpeech.QUEUE_FLUSH : TextToSpeech.QUEUE_ADD;
            ensureSpeechAudible();
            Bundle params = new Bundle();
            params.putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f);
            tts.speak(copy.get(i), queueMode, params, "silvercare-pending-" + i);
        }
    }

    private boolean canUseLocalMnnTts(LocalTtsModelStatus status) {
        return LOCAL_MNN_TTS_VOICE_QUALITY_ENABLED && status != null && status.ready;
    }

    private void startSpeechInquiry(String imageDataUrl) {
        DiagnosticLogger.eventPairs(
            "speech_request_start",
            "ai_runtime", currentRuntimeMode().value,
            "asr_runtime", currentAsrRuntimeMode().value,
            "tts_runtime", currentTtsRuntimeMode().value,
            "image_chars", imageDataUrl == null ? 0 : imageDataUrl.length()
        );
        if (!beginSpeechRequest()) return;
        stopCurrentTtsPlayback();
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            sendError("请先允许麦克风权限。");
            finishSpeechRequest();
            finishNativeSpeechUi();
            return;
        }
        if (!ensureAiRuntimeReady()) {
            finishSpeechRequest();
            finishNativeSpeechUi();
            return;
        }

        AsrRuntimeMode asrMode = currentAsrRuntimeMode();
        if (asrMode.isLocal()) {
            startBundledLocalAsrSpeechInquiry(imageDataUrl);
            return;
        }

        if (!hasDashScopeKeyInternal()) {
            sendError("联网 DashScope ASR 需要先在设置里填写 DashScope Key，或切换到本地内置 ASR。");
            finishSpeechRequest();
            finishNativeSpeechUi();
            return;
        }
        startDashScopeWavSpeechInquiry(imageDataUrl);
    }

    private boolean beginSpeechRequest() {
        if (speechRequestInFlight == null) {
            speechRequestInFlight = new AtomicBoolean(false);
        }
        if (speechRequestInFlight.compareAndSet(false, true)) {
            DiagnosticLogger.event("speech_request_lock_acquired");
            return true;
        }
        String message = "上一条语音还在处理，请稍等。";
        DiagnosticLogger.event("speech_request_busy");
        sendSpeechBusy(message);
        speakIfVoiceFirst(message);
        finishNativeSpeechUi();
        return false;
    }

    private void finishSpeechRequest() {
        if (speechRequestInFlight != null) {
            speechRequestInFlight.set(false);
        }
        DiagnosticLogger.event("speech_request_lock_released");
    }

    private void startBundledLocalAsrSpeechInquiry(String imageDataUrl) {
        startVoskLocalAsrSpeechInquiry(imageDataUrl);
    }

    private void startVoskLocalAsrSpeechInquiry(String imageDataUrl) {
        stopDashScopeWavRecordingOnly();
        pendingSpeechImageDataUrl = imageDataUrl;
        DiagnosticLogger.eventPairs(
            "local_asr_request_start",
            "image_chars", imageDataUrl == null ? 0 : imageDataUrl.length()
        );

        LocalAsrModelStatus asrStatus = localAsrStatus();
        if (!asrStatus.ready) {
            String message = "本地内置 ASR 模型未就绪。请在设置里下载本地 ASR 模型，或切换到联网 DashScope ASR。";
            sendError(message);
            speakIfVoiceFirst(message);
            finishSpeechRequest();
            finishNativeSpeechUi();
            return;
        }

        if (!wavRecording.compareAndSet(false, true)) {
            sendError("语音识别正在进行中。");
            finishSpeechRequest();
            finishNativeSpeechUi();
            return;
        }

        sendSpeechStatus(true);
        executor.execute(() -> {
            long requestStarted = DiagnosticLogger.start();
            byte[] pcm = new byte[0];
            Exception recordError = null;
            try {
                pcm = recordPcmUntilStopped();
            } catch (Exception error) {
                recordError = error;
                sendError("录音失败：" + readableError(error));
            } finally {
                stopAudioRecordInstance();
                wavRecording.set(false);
                sendSpeechStatus(false);
            }

            if (recordError != null) {
                finishSpeechRequest();
                finishNativeSpeechUi();
                return;
            }
            try {
                DiagnosticLogger.event("local_asr_transcribe_pipeline_start", new JSONObject()
                    .put("recorded_pcm_bytes", pcm.length)
                    .put("elapsed_since_request_ms", DiagnosticLogger.elapsed(requestStarted)));
                String rawTranscript = transcribeLocalAsrWithTimeout(asrStatus.modelDir, pcm);
                processRecognizedSpeech(pendingSpeechImageDataUrl, rawTranscript, true);
            } catch (Exception error) {
                sendSpeechTranscript("");
                sendError("本地语音识别失败：" + readableError(error));
                finishSpeechRequest();
                finishNativeSpeechUi();
            }
        });
    }

    private String transcribeLocalAsrWithTimeout(File modelDir, byte[] pcm) throws Exception {
        long started = DiagnosticLogger.start();
        DiagnosticLogger.event("local_asr_transcribe_start", new JSONObject()
            .put("pcm_bytes", pcm == null ? 0 : pcm.length)
            .put("model_dir", modelDir == null ? "" : modelDir.getAbsolutePath())
            .put("timeout_ms", LOCAL_ASR_TRANSCRIBE_TIMEOUT_MS));
        Future<String> task = asrExecutor.submit(() -> localAsrEngine.transcribePcm(modelDir, pcm));
        try {
            String transcript = task.get(LOCAL_ASR_TRANSCRIBE_TIMEOUT_MS, TimeUnit.MILLISECONDS);
            DiagnosticLogger.event("local_asr_transcribe_end", new JSONObject()
                .put("elapsed_ms", DiagnosticLogger.elapsed(started))
                .put("transcript_chars", transcript == null ? 0 : transcript.length())
                .put("transcript", DiagnosticLogger.excerpt(transcript)));
            return transcript;
        } catch (TimeoutException timeout) {
            task.cancel(true);
            resetLocalAsrAfterTimeout();
            DiagnosticLogger.event("local_asr_transcribe_timeout", new JSONObject()
                .put("elapsed_ms", DiagnosticLogger.elapsed(started))
                .put("pcm_bytes", pcm == null ? 0 : pcm.length));
            throw new IllegalStateException("本地 ASR 识别超时，请再试一次，或在设置里切换到联网 ASR。");
        } catch (Exception error) {
            DiagnosticLogger.event("local_asr_transcribe_error", new JSONObject()
                .put("elapsed_ms", DiagnosticLogger.elapsed(started))
                .put("error", error.getClass().getSimpleName() + ": " + error.getMessage()));
            throw error;
        }
    }

    private void resetLocalAsrAfterTimeout() {
        try {
            localAsrEngine.close();
        } catch (Exception ignored) {
        }
        localAsrEngine = new VoskLocalAsrEngine();
        if (asrExecutor != null) {
            asrExecutor.shutdownNow();
        }
        asrExecutor = Executors.newSingleThreadExecutor();
    }

    private void startDashScopeWavSpeechInquiry(String imageDataUrl) {
        stopDashScopeWavRecordingOnly();
        pendingSpeechImageDataUrl = imageDataUrl;

        if (!wavRecording.compareAndSet(false, true)) {
            sendError("语音识别正在进行中。");
            finishSpeechRequest();
            finishNativeSpeechUi();
            return;
        }

        sendSpeechStatus(true);
        executor.execute(() -> {
            byte[] pcm = new byte[0];
            try {
                pcm = recordPcmUntilStopped();
            } catch (Exception error) {
                sendError("录音失败：" + readableError(error));
            } finally {
                stopAudioRecordInstance();
                wavRecording.set(false);
                sendSpeechStatus(false);
            }

            if (pcm.length < 1600) {
                sendError("录音太短，请按住说完整问题。");
                finishSpeechRequest();
                finishNativeSpeechUi();
                return;
            }

            try {
                String audioDataUrl = wavDataUrl(pcm, 16000, 1, 16);
                long asrStarted = DiagnosticLogger.start();
                DiagnosticLogger.event("dashscope_asr_start", new JSONObject()
                    .put("pcm_bytes", pcm.length)
                    .put("audio_data_chars", audioDataUrl.length()));
                String transcript = new DashScopeClient(this).transcribe(audioDataUrl);
                DiagnosticLogger.event("dashscope_asr_end", new JSONObject()
                    .put("elapsed_ms", DiagnosticLogger.elapsed(asrStarted))
                    .put("transcript_chars", transcript == null ? 0 : transcript.length())
                    .put("transcript", DiagnosticLogger.excerpt(transcript)));
                processRecognizedSpeech(pendingSpeechImageDataUrl, transcript, false);
            } catch (Exception error) {
                sendError("处理语音失败：" + readableError(error));
                finishSpeechRequest();
                finishNativeSpeechUi();
            }
        });
    }

    private byte[] recordPcmUntilStopped() {
        long diagnosticStarted = DiagnosticLogger.start();
        int sampleRate = 16000;
        int minBuffer = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        );
        if (minBuffer <= 0) {
            throw new IllegalStateException("当前设备不支持 16kHz 单声道录音。");
        }

        int bufferSize = Math.max(minBuffer, sampleRate);
        AudioRecord recorder = new AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        );
        audioRecord = recorder;
        if (recorder.getState() != AudioRecord.STATE_INITIALIZED) {
            throw new IllegalStateException("录音器初始化失败。");
        }

        ByteArrayOutputStream pcm = new ByteArrayOutputStream();
        byte[] buffer = new byte[bufferSize];
        long startedAt = System.currentTimeMillis();
        DiagnosticLogger.eventPairs(
            "audio_record_start",
            "sample_rate", sampleRate,
            "buffer_size", bufferSize,
            "max_ms", SPEECH_RECORDING_MAX_MS
        );
        recorder.startRecording();
        boolean stoppedByMax = false;
        while (wavRecording.get()) {
            if (System.currentTimeMillis() - startedAt > SPEECH_RECORDING_MAX_MS) {
                wavRecording.set(false);
                stoppedByMax = true;
                break;
            }
            int read = recorder.read(buffer, 0, buffer.length);
            if (read > 0) {
                pcm.write(buffer, 0, read);
            }
        }
        byte[] bytes = pcm.toByteArray();
        DiagnosticLogger.eventPairs(
            "audio_record_end",
            "elapsed_ms", DiagnosticLogger.elapsed(diagnosticStarted),
            "pcm_bytes", bytes.length,
            "approx_audio_ms", Math.round(bytes.length / 2.0d / sampleRate * 1000.0d),
            "stopped_by_max", stoppedByMax
        );
        return bytes;
    }

    private void stopSpeechInquiry() {
        DiagnosticLogger.event("speech_stop_requested");
        runOnUiThread(() -> {
            stopDashScopeWavRecordingOnly();
            sendSpeechStatus(false);
        });
    }

    private void stopDashScopeWavRecordingOnly() {
        if (wavRecording != null) {
            wavRecording.set(false);
        }
        AudioRecord recorder = audioRecord;
        if (recorder == null) return;
        try {
            if (recorder.getRecordingState() == AudioRecord.RECORDSTATE_RECORDING) {
                recorder.stop();
            }
        } catch (Exception ignored) {
        }
    }

    private void stopAudioRecordInstance() {
        AudioRecord recorder = audioRecord;
        audioRecord = null;
        if (recorder == null) return;
        try {
            if (recorder.getRecordingState() == AudioRecord.RECORDSTATE_RECORDING) {
                recorder.stop();
            }
        } catch (Exception ignored) {
        }
        try {
            recorder.release();
        } catch (Exception ignored) {
        }
    }

    private void finishNativeSpeechUi() {
        sendSpeechStatus(false);
        if (webView != null) {
            webView.post(() -> webView.evaluateJavascript(
                "window.LONG_TERM_CARE_NATIVE_SPEECH_DONE && window.LONG_TERM_CARE_NATIVE_SPEECH_DONE();",
                null
            ));
        }
    }

    private void sendSpeechTranscript(String transcript) {
        try {
            send(new JSONObject()
                .put("type", "speech_transcript")
                .put("text", transcript == null ? "" : transcript.trim()));
        } catch (Exception ignored) {
        }
    }

    private void sendSpeechTranscriptCorrection(String sourceTranscript, String transcript) {
        try {
            send(new JSONObject()
                .put("type", "speech_transcript_correction")
                .put("source_text", sourceTranscript == null ? "" : sourceTranscript.trim())
                .put("text", transcript == null ? "" : transcript.trim()));
        } catch (Exception ignored) {
        }
    }

    private void sendSpeechBusy(String text) {
        try {
            send(new JSONObject()
                .put("type", "speech_busy")
                .put("text", text == null ? "上一条语音还在处理，请稍等。" : text));
        } catch (Exception ignored) {
        }
    }

    private static String wavDataUrl(byte[] pcm, int sampleRate, int channels, int bitsPerSample) {
        byte[] wav = wavBytes(pcm, sampleRate, channels, bitsPerSample);
        return "data:audio/wav;base64," + Base64.encodeToString(wav, Base64.NO_WRAP);
    }

    private static byte[] wavBytes(byte[] pcm, int sampleRate, int channels, int bitsPerSample) {
        int byteRate = sampleRate * channels * bitsPerSample / 8;
        int blockAlign = channels * bitsPerSample / 8;
        int dataSize = pcm.length;
        ByteBuffer header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
        header.put(new byte[] { 'R', 'I', 'F', 'F' });
        header.putInt(36 + dataSize);
        header.put(new byte[] { 'W', 'A', 'V', 'E' });
        header.put(new byte[] { 'f', 'm', 't', ' ' });
        header.putInt(16);
        header.putShort((short) 1);
        header.putShort((short) channels);
        header.putInt(sampleRate);
        header.putInt(byteRate);
        header.putShort((short) blockAlign);
        header.putShort((short) bitsPerSample);
        header.put(new byte[] { 'd', 'a', 't', 'a' });
        header.putInt(dataSize);

        ByteArrayOutputStream out = new ByteArrayOutputStream(44 + dataSize);
        out.write(header.array(), 0, header.array().length);
        out.write(pcm, 0, pcm.length);
        return out.toByteArray();
    }

    private void sendSpeechStatus(boolean listening) {
        try {
            send(new JSONObject()
                .put("type", "speech_status")
                .put("listening", listening));
        } catch (Exception ignored) {
        }
    }

    private void speakIfVoiceFirst(String text) {
        if (isVoiceFirstEnabledInternal()) {
            speakNative(text);
        }
    }

    @Override
    public String aiRuntimeMode() {
        return currentRuntimeMode().value;
    }

    @Override
    public String offlineModelDir() {
        String saved = preferences.getString(KEY_OFFLINE_MODEL_DIR, "");
        if (saved != null && !saved.trim().isEmpty()) {
            return saved;
        }
        return OfflineModelDownloader.automaticModelDir(this).getAbsolutePath();
    }

    private String offlineTextModel() {
        String saved = preferences.getString(KEY_OFFLINE_TEXT_MODEL, OfflineAiClient.TEXT_MODEL);
        return OfflineAiClient.isOfflineTextModel(saved) ? saved : OfflineAiClient.TEXT_MODEL;
    }

    @Override
    public String apiKey() {
        String savedKey = preferences.getString(KEY_API_KEY, "");
        if (savedKey != null && !savedKey.trim().isEmpty()) {
            return savedKey;
        }
        return BuildConfig.DEFAULT_DASHSCOPE_API_KEY;
    }

    @Override
    public String compatibleBaseUrl() {
        return preferences.getString(
            KEY_COMPATIBLE_BASE_URL,
            "https://dashscope.aliyuncs.com/compatible-mode/v1"
        );
    }

    @Override
    public String apiBaseUrl() {
        return preferences.getString(
            KEY_API_BASE_URL,
            "https://dashscope.aliyuncs.com/api/v1"
        );
    }

    @Override
    public String visionModel() {
        if (currentRuntimeMode().isOffline()) {
            return OfflineAiClient.DETECTOR_MODEL;
        }
        return preferences.getString(KEY_VISION_MODEL, "qwen3-vl-flash");
    }

    @Override
    public String microModel() {
        if (currentRuntimeMode().isOffline()) {
            return OfflineAiClient.DETECTOR_MODEL;
        }
        return preferences.getString(KEY_MICRO_MODEL, visionModel());
    }

    @Override
    public String textModel() {
        if (currentRuntimeMode().isOffline()) {
            return offlineTextModel();
        }
        return preferences.getString(KEY_TEXT_MODEL, "qwen-plus");
    }

    @Override
    public String asrModel() {
        if (currentAsrRuntimeMode().isLocal()) {
            return OfflineAiClient.DEVICE_ASR_MODEL;
        }
        return preferences.getString(KEY_ASR_MODEL, "qwen3-asr-flash");
    }

    @Override
    public String mnnLlmTuningMode() {
        return currentMnnLlmTuningProfile().value;
    }

    @Override
    public boolean voiceFirstEnabled() {
        return isVoiceFirstEnabledInternal();
    }

    @Override
    public boolean smartNavigationRefreshEnabled() {
        return isSmartNavigationRefreshEnabledInternal();
    }

    private static String trimTrailingSlash(String value) {
        String url = value == null ? "" : value.trim();
        while (url.endsWith("/")) {
            url = url.substring(0, url.length() - 1);
        }
        return url;
    }

    private static String readableError(Exception error) {
        String message = error == null ? "" : error.getMessage();
        return message == null || message.trim().isEmpty()
            ? String.valueOf(error)
            : message;
    }

    private static String summarizeEvidence(String value) {
        if (value == null || value.trim().isEmpty()) return "无";
        String clean = value.trim();
        if (clean.length() > 600) {
            return clean.substring(0, 600) + "...";
        }
        return clean;
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
            return;
        }
        super.onBackPressed();
    }

    @Override
    protected void onDestroy() {
        if (tts != null) {
            tts.shutdown();
        }
        if (executor != null) {
            executor.shutdownNow();
        }
        if (asrExecutor != null) {
            asrExecutor.shutdownNow();
        }
        if (asrCorrectionExecutor != null) {
            asrCorrectionExecutor.shutdownNow();
        }
        stopDashScopeWavRecordingOnly();
        releaseDashScopeTtsPlayer();
        if (localAsrEngine != null) {
            localAsrEngine.close();
        }
        if (localTtsRuntimeBridge instanceof java.io.Closeable closeable) {
            try {
                closeable.close();
            } catch (Exception ignored) {
                // Best-effort cleanup during Activity shutdown.
            }
        }
        if (webView != null) {
            webView.destroy();
        }
        super.onDestroy();
    }

    public final class SilverCareBridge {
        private final Context context;

        SilverCareBridge(Context context) {
            this.context = context;
        }

        @JavascriptInterface
        public boolean isStandalone() {
            return true;
        }

        @JavascriptInterface
        public boolean hasDashScopeKey() {
            return hasDashScopeKeyInternal();
        }

        @JavascriptInterface
        public String diagnosticLogPath() {
            return DiagnosticLogger.latestPath();
        }

        @JavascriptInterface
        public void diagnosticEvent(String event, String dataJson) {
            try {
                String name = event == null || event.trim().isEmpty() ? "js_event" : "js_" + event.trim();
                JSONObject data = dataJson == null || dataJson.trim().isEmpty()
                    ? new JSONObject()
                    : new JSONObject(dataJson);
                DiagnosticLogger.event(name, data);
            } catch (Exception error) {
                DiagnosticLogger.eventPairs(
                    "js_diagnostic_event_error",
                    "event", event == null ? "" : event,
                    "message", DiagnosticLogger.excerpt(error.getMessage())
                );
            }
        }

        @JavascriptInterface
        public String aiRuntimeMode() {
            return MainActivity.this.aiRuntimeMode();
        }

        @JavascriptInterface
        public String runtimeDisplayName() {
            return currentRuntimeMode().label;
        }

        @JavascriptInterface
        public boolean isOfflineRuntime() {
            return currentRuntimeMode().isOffline();
        }

        @JavascriptInterface
        public boolean offlineModelReady() {
            return offlineStatus().ready();
        }

        @JavascriptInterface
        public String offlineStatusText() {
            return offlineStatus().shortText();
        }

        @JavascriptInterface
        public boolean localAsrReady() {
            return MainActivity.this.localAsrReady(localAsrStatus());
        }

        @JavascriptInterface
        public boolean localAsrEnabled() {
            return currentAsrRuntimeMode().isLocal();
        }

        @JavascriptInterface
        public String localAsrStatusText() {
            return localAsrStatus().shortText();
        }

        @JavascriptInterface
        public String asrRuntimeMode() {
            return currentAsrRuntimeMode().value;
        }

        @JavascriptInterface
        public String asrRuntimeDisplayName() {
            return currentAsrRuntimeMode().label;
        }

        @JavascriptInterface
        public String ttsRuntimeMode() {
            return currentTtsRuntimeMode().value;
        }

        @JavascriptInterface
        public String ttsRuntimeDisplayName() {
            return currentTtsRuntimeMode().label;
        }

        @JavascriptInterface
        public String ttsStatusText() {
            return MainActivity.this.ttsStatusText();
        }

        @JavascriptInterface
        public boolean localTtsReady() {
            return localTtsStatus().ready;
        }

        @JavascriptInterface
        public boolean localTtsModelReady() {
            return localTtsStatus().modelReady;
        }

        @JavascriptInterface
        public boolean localTtsRuntimeAvailable() {
            return localTtsStatus().runtimeAvailable;
        }

        @JavascriptInterface
        public String localTtsStatusText() {
            return localTtsStatus().shortText();
        }

        @JavascriptInterface
        public boolean captionsEnabled() {
            return isCaptionsEnabledInternal();
        }

        @JavascriptInterface
        public String navigationRefreshMode() {
            return currentNavigationRefreshMode().value;
        }

        @JavascriptInterface
        public String navigationRefreshDisplayName() {
            return currentNavigationRefreshMode().label;
        }

        @JavascriptInterface
        public int navigationRefreshIntervalMs() {
            return currentNavigationRefreshIntervalSeconds() * 1000;
        }

        @JavascriptInterface
        public boolean smartNavigationRefreshEnabled() {
            return isSmartNavigationRefreshEnabledInternal();
        }

        @JavascriptInterface
        public String mnnLlmTuningMode() {
            return MainActivity.this.mnnLlmTuningMode();
        }

        @JavascriptInterface
        public String mnnLlmTuningDisplayName() {
            return currentMnnLlmTuningProfile().label;
        }

        @JavascriptInterface
        public boolean mnnSme2Supported() {
            return mnnRuntimeBridge != null && mnnRuntimeBridge.supportsSme2();
        }

        @JavascriptInterface
        public boolean isFallDetectionEnabled() {
            return isFallDetectionEnabledInternal();
        }

        @JavascriptInterface
        public boolean isVoiceFirstEnabled() {
            return isVoiceFirstEnabledInternal();
        }

        @JavascriptInterface
        public void sendFrame(String imageDataUrl) {
            submitFrame(imageDataUrl);
        }

        @JavascriptInterface
        public void sendInquiryData(String imageDataUrl, String audioDataUrl) {
            submitInquiry(imageDataUrl, audioDataUrl);
        }

        @JavascriptInterface
        public void startSpeechInquiry(String imageDataUrl) {
            MainActivity.this.startSpeechInquiry(imageDataUrl);
        }

        @JavascriptInterface
        public void stopSpeechInquiry() {
            MainActivity.this.stopSpeechInquiry();
        }

        @JavascriptInterface
        public void speak(String text) {
            speakNative(text);
        }

        @JavascriptInterface
        public void triggerFallAlarm(String evidenceJson) {
            MainActivity.this.triggerFallAlarm(evidenceJson);
        }

        @JavascriptInterface
        public void openSettings() {
            runOnUiThread(MainActivity.this::showSettingsDialog);
        }

        @JavascriptInterface
        public void openRuntimeSettings() {
            runOnUiThread(MainActivity.this::showRuntimeDialog);
        }

        @JavascriptInterface
        public void openKeySettings() {
            runOnUiThread(MainActivity.this::showApiKeyDialog);
        }
    }
}
