package com.silvercare.aiassistant;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

final class SilverCareProcessor {
    private static final long SPEECH_COOLDOWN_MS = 3000;
    private static final long VOICE_FIRST_SPEECH_COOLDOWN_MS = 1300;
    private static final int OFFLINE_INQUIRY_MAX_NEW_TOKENS = 24;
    private static final int OFFLINE_SMART_REFRESH_MAX_NEW_TOKENS = 48;
    private static final int TASK_PLAN_MAX_NEW_TOKENS = 256;
    private static final String JSON_OBJECT_END = "}";

    private final SilverCareArtificialIntelligenceClient client;
    private final MessageSink sink;
    private final MemoryStore memoryStore;

    private String mode = "nav";
    private String currentGoal;
    private String microTarget;
    private JSONArray taskPlan = new JSONArray();
    private int currentStepIndex = 0;
    private long lastSpeechAt = 0L;
    private String lastSpeech = "";
    private String lastNavigationSemanticText = "";
    private String lastMicroGuidanceSpeech = "";
    private final List<String> socialContext = new ArrayList<>();

    SilverCareProcessor(SilverCareArtificialIntelligenceClient client, MemoryStore memoryStore, MessageSink sink) {
        this.client = client;
        this.memoryStore = memoryStore;
        this.sink = sink;
    }

    synchronized void processFrame(String imageDataUrl) {
        try {
            if ("micro".equals(mode)) {
                processMicroFrame(imageDataUrl);
            } else if ("task".equals(mode)) {
                processTaskFrame(imageDataUrl);
            } else {
                processNavigationFrame(imageDataUrl);
            }
        } catch (Exception e) {
            sendError("处理画面失败：" + readableError(e));
        }
    }

    synchronized void processInquiry(String imageDataUrl, String audioDataUrl) {
        long start = System.currentTimeMillis();
        try {
            String transcript = client.transcribe(audioDataUrl);
            if (transcript == null || transcript.trim().isEmpty()) {
                transcript = "未识别到清晰语音";
            }

            processTranscriptInquiry(imageDataUrl, transcript, start, false);
        } catch (Exception e) {
            sendError("处理语音失败：" + readableError(e));
        }
    }

    synchronized void processTextInquiry(String imageDataUrl, String transcript) {
        long start = System.currentTimeMillis();
        long diagnosticStarted = DiagnosticLogger.start();
        try {
            if (transcript == null || transcript.trim().isEmpty()) {
                transcript = "未识别到清晰语音";
            }
            DiagnosticLogger.event("processor_text_inquiry_start", new JSONObject()
                .put("mode", mode)
                .put("transcript", DiagnosticLogger.excerpt(transcript))
                .put("image_chars", imageDataUrl == null ? 0 : imageDataUrl.length()));
            processTranscriptInquiry(imageDataUrl, transcript, start, false);
        } catch (Exception e) {
            DiagnosticLogger.eventPairs(
                "processor_text_inquiry_error",
                "elapsed_ms", DiagnosticLogger.elapsed(diagnosticStarted),
                "error", e.getClass().getSimpleName() + ": " + e.getMessage()
            );
            sendError("处理语音失败：" + readableError(e));
        } finally {
            DiagnosticLogger.eventPairs(
                "processor_text_inquiry_end",
                "elapsed_ms", DiagnosticLogger.elapsed(diagnosticStarted),
                "mode", mode,
                "current_goal", currentGoal == null ? JSONObject.NULL : currentGoal
            );
        }
    }

    private void processTranscriptInquiry(
        String imageDataUrl,
        String transcript,
        long start,
        boolean preferDeterministicFirst
    ) throws Exception {
        if ("micro".equals(mode) && containsCloseKeyword(transcript)) {
            closeMicroGuidance(transcript, start);
            return;
        }
        if ("micro".equals(mode) && !containsGuidanceKeyword(transcript)) {
            processMicroFollowUpInquiry(imageDataUrl, transcript, start);
            return;
        }

        JSONObject result = deterministicCareRecord(transcript);
        if (result == null && preferDeterministicFirst) {
            result = applyTranscriptFallback(transcript, null);
        }
        if (result == null) {
            String prompt = inquiryPrompt(transcript);
            String routeModel = isOfflineRuntime() ? client.settings().textModel() : client.settings().visionModel();
            DiagnosticLogger.event("processor_inquiry_model_route", new JSONObject()
                .put("offline_runtime", isOfflineRuntime())
                .put("model", routeModel)
                .put("max_new_tokens", isOfflineRuntime() ? OFFLINE_INQUIRY_MAX_NEW_TOKENS : 0)
                .put("prompt_chars", prompt.length())
                .put("transcript", DiagnosticLogger.excerpt(transcript)));
            String rawResult = isOfflineRuntime()
                ? client.textJson(prompt, routeModel, OFFLINE_INQUIRY_MAX_NEW_TOKENS, JSON_OBJECT_END)
                : client.visionJson(prompt, imageDataUrl, routeModel);
            try {
                result = parseJson(rawResult);
                result = expandCompactInquiryResult(result);
            } catch (Exception parseError) {
                result = null;
            }
            result = applyTranscriptFallback(transcript, result);
        } else {
            DiagnosticLogger.event("processor_inquiry_deterministic_result", new JSONObject()
                .put("intent", result.optString("intent", ""))
                .put("speech", DiagnosticLogger.excerpt(result.optString("speech", "")))
                .put("thinking", DiagnosticLogger.excerpt(result.optString("thinking", ""))));
        }
        if (result == null) {
            result = fallbackIntent("info", "我暂时没有理解这句话，请再说一遍。")
                .put("thinking", "模型未返回可解析 JSON，已使用本地兜底回复");
            DiagnosticLogger.event("processor_inquiry_fallback_result");
        }

        String intent = normalizeIntent(result.optString("intent", "info"));
        result.put("intent", intent);
        String speech = result.optString("speech", "我没有听清。");
        if ("micro_nav".equals(intent) && !containsGuidanceKeyword(transcript)) {
            result = fallbackIntent("info", "如果需要精确引导，请说：引导我靠近目标。当前我不会自动开启精确引导。")
                .put("thinking", "用户没有说出“引导”，已阻止自动进入精确引导");
            intent = "info";
            speech = result.optString("speech", speech);
        }
        if ("search".equals(intent) && isOfflineRuntime() && isNavigationSafetyQuestion(transcript)) {
            result = fallbackIntent("nav_check", "正在查看前方是否可以通行。")
                .put("thinking", "LLM 将通行检查误判为找物，已按安全意图校正为避障导航。");
            intent = "nav_check";
            speech = result.optString("speech", speech);
        }
        if ("search".equals(intent) && isOfflineRuntime() && !isSearchIntentRequest(transcript)) {
            result = fallbackIntent("info", offlineCapabilitySpeech(transcript, speech))
                .put("thinking", "本地 LLM 返回找物，但用户原话没有找物意图，已校正为普通问答。");
            intent = "info";
            speech = result.optString("speech", speech);
        }
        if ("search".equals(intent) && isOfflineRuntime()) {
            result = normalizeOfflineSearchIntent(transcript, result);
            intent = normalizeIntent(result.optString("intent", "info"));
            result.put("intent", intent);
            speech = result.optString("speech", speech);
        }
        if ("info".equals(intent) && speech.trim().isEmpty()) {
            speech = offlineCapabilitySpeech(transcript, speech);
            result.put("speech", speech);
        } else if ("nav_check".equals(intent) && speech.trim().isEmpty()) {
            speech = "正在查看前方是否可以通行。";
            result.put("speech", speech);
        }
        String override = handleIntent(intent, result);
        if (override != null && !override.isEmpty()) {
            speech = override;
        }
        DiagnosticLogger.event("processor_inquiry_result_ready", new JSONObject()
            .put("intent", intent)
            .put("mode", mode)
            .put("speech", DiagnosticLogger.excerpt(speech))
            .put("current_goal", currentGoal == null ? JSONObject.NULL : currentGoal)
            .put("elapsed_ms", System.currentTimeMillis() - start));

        sink.send(new JSONObject()
            .put("type", "inquiry_result")
            .put("thinking", result.optString("thinking", ""))
            .put("current_goal", currentGoal == null ? JSONObject.NULL : currentGoal)
            .put("mode", mode)
            .put("intent", intent)
            .put("task_active", "task".equals(mode))
            .put("speech", speech)
            .put("transcript", transcript)
            .put("ms", System.currentTimeMillis() - start));
        speak(speech, true);

        if ("search".equals(intent) && currentGoal != null && hasImageData(imageDataUrl)) {
            try {
                processNavigationFrame(imageDataUrl, true);
            } catch (Exception navigationError) {
                sendError("已开始寻找" + currentGoal + "，但这次画面分析失败：" + readableError(navigationError));
            }
        } else if ("nav_check".equals(intent) && hasImageData(imageDataUrl)) {
            try {
                currentGoal = null;
                mode = "nav";
                processNavigationFrame(imageDataUrl, false);
            } catch (Exception navigationError) {
                sendError("正在查看前方通行情况，但这次画面分析失败：" + readableError(navigationError));
            }
        }
    }

    private void closeMicroGuidance(String transcript, long start) throws Exception {
        mode = "nav";
        microTarget = null;
        lastMicroGuidanceSpeech = "";
        sink.send(new JSONObject()
            .put("type", "inquiry_result")
            .put("thinking", "用户说出“关闭”，已退出精确引导")
            .put("current_goal", currentGoal == null ? JSONObject.NULL : currentGoal)
            .put("mode", mode)
            .put("task_active", false)
            .put("transcript", transcript)
            .put("ms", System.currentTimeMillis() - start));
        speak("已关闭精确引导。", true);
    }

    private void processMicroFollowUpInquiry(String imageDataUrl, String transcript, long start) throws Exception {
        JSONObject result;
        try {
            String prompt = microFollowUpPrompt(transcript);
            String rawResult = hasImageData(imageDataUrl)
                ? client.visionJson(prompt, imageDataUrl, client.settings().visionModel())
                : client.textJson(
                    prompt,
                    client.settings().textModel(),
                    OFFLINE_INQUIRY_MAX_NEW_TOKENS,
                    JSON_OBJECT_END
                );
            result = parseJson(rawResult);
        } catch (Exception error) {
            result = fallbackIntent(
                "info",
                "我正在继续引导你靠近" + microTarget + "。如果要结束，请说关闭引导。"
            ).put("thinking", "精确引导追问兜底：" + readableError(error));
        }

        String speech = result.optString("speech", "");
        if (speech.trim().isEmpty()) {
            speech = "我正在继续引导你靠近" + microTarget + "。如果要结束，请说关闭引导。";
        }
        sink.send(new JSONObject()
            .put("type", "inquiry_result")
            .put("thinking", result.optString("thinking", "精确引导中的追问"))
            .put("current_goal", currentGoal == null ? JSONObject.NULL : currentGoal)
            .put("mode", "micro")
            .put("task_active", false)
            .put("transcript", transcript)
            .put("ms", System.currentTimeMillis() - start));
        speak(speech, true);
    }

    private JSONObject applyTranscriptFallback(String transcript, JSONObject modelResult) throws Exception {
        String text = transcript == null ? "" : transcript.trim();
        if (text.isEmpty()) return modelResult;

        JSONObject control = deterministicTaskControl(text);
        if (control != null) return control;

        JSONObject careRecord = deterministicCareRecord(text);
        if (careRecord != null) return careRecord;

        String remembered = memoryStore.findObjectLocation(extractMemoryObject(text));
        if (!remembered.isEmpty() && isWhereQuestion(text)) {
            return fallbackIntent("info", remembered)
                .put("thinking", "根据本地记忆回答物体位置");
        }

        if (modelResult != null) {
            String intent = normalizeIntent(modelResult.optString("intent", "info"));
            modelResult.put("intent", intent);
            if ("search".equals(intent)) {
                String target = cleanTarget(modelResult.optString("search_target", ""));
                if (target.isEmpty() || "null".equalsIgnoreCase(target)) {
                    target = extractSearchTarget(text);
                    if (!target.isEmpty()) {
                        modelResult.put("search_target", target);
                        modelResult.put(
                            "thinking",
                            appendThinking(modelResult.optString("thinking", ""), "模型已判定找物，本地仅补全缺失目标。")
                        );
                    }
                }
            }
            if ("care_record".equals(intent)) {
                fillCareRecordFields(modelResult, text);
            }
            return modelResult;
        }

        String tag = extractAfter(text, "记住这里是", "把这里标记为", "这里叫");
        if (!tag.isEmpty()) {
            return fallbackIntent("tag", "已记住" + tag + "。")
                .put("tag_name", tag)
                .put("scene_description", tag)
                .put("thinking", "确定性识别地点标记指令");
        }

        String micro = containsGuidanceKeyword(text)
            ? extractAfter(text, "引导我摸到", "引导我靠近", "引导我按", "引导我找到", "引导")
            : "";
        if (containsGuidanceKeyword(text) && (!micro.isEmpty() || containsAny(text, "按钮", "开关", "把手", "水龙头"))) {
            if (micro.isEmpty()) micro = cleanTarget(text);
            return fallbackIntent("micro_nav", "正在引导你靠近" + micro + "。")
                .put("target", micro)
                .put("thinking", "确定性识别微导航指令");
        }

        String task = extractAfter(text, "教我", "帮我完成", "一步步指导我", "我想");
        if (!task.isEmpty()) {
            return fallbackIntent("task", "我来指导你" + task + "。")
                .put("task_name", task)
                .put("thinking", "确定性识别任务指导指令");
        }

        if (isCapabilityQuestion(text)) {
            return fallbackIntent("info", offlineCapabilitySpeech(text, ""))
                .put("thinking", "确定性识别能力询问");
        }

        if (isNavigationSafetyQuestion(text)) {
            return fallbackIntent("nav_check", "正在查看前方是否可以通行。")
                .put("thinking", "确定性识别通行和避障询问");
        }

        String search = extractSearchTarget(text);
        if (!search.isEmpty()) {
            JSONObject result = modelResult == null ? new JSONObject() : modelResult;
            result.put("intent", "search");
            result.put("search_target", search);
            result.put("speech", "好的，正在寻找" + search + "。");
            if (!result.has("thinking")) result.put("thinking", "确定性补全搜索目标");
            return result;
        }

        return modelResult;
    }

    private JSONObject normalizeOfflineSearchIntent(String transcript, JSONObject result) throws Exception {
        String rawTarget = cleanTarget(result.optString("search_target", result.optString("goal", "")));
        if (rawTarget.isEmpty() || "null".equalsIgnoreCase(rawTarget)) {
            rawTarget = extractSearchTarget(transcript);
        }

        String target = resolveOfflineSearchTargetWithAi(transcript, rawTarget);
        if (target.isEmpty()) {
            mode = "nav";
            currentGoal = null;
            return fallbackIntent(
                "info",
                "我听到你可能想找“" + (rawTarget.isEmpty() ? "某个东西" : rawTarget)
                    + "”，但它不在当前离线视觉可稳定识别的目标清单里。"
                    + "你可以改说：找杯子、碗、手机、椅子、桌子、行李箱等，或者直接问我问题。"
            ).put("thinking", "离线找物目标未通过可检测目标校验，未进入搜索模式。原始 ASR：" + transcript);
        }

        result.put("intent", "search");
        result.put("search_target", target);
        result.put("speech", "好的，正在寻找" + target + "。");
        result.put(
            "thinking",
            appendThinking(
                result.optString("thinking", ""),
                "离线找物目标已校正为可检测类别：“" + target + "”。原始目标：“" + rawTarget + "”。"
            )
        );
        return result;
    }

    private String resolveOfflineSearchTargetWithAi(String transcript, String rawTarget) {
        String direct = exactSupportedSearchTarget(rawTarget);
        if (!direct.isEmpty()) return direct;

        long diagnosticStarted = DiagnosticLogger.start();
        try {
            String raw = client.textJson(
                offlineSearchTargetCorrectionPrompt(transcript, rawTarget),
                client.settings().textModel(),
                OFFLINE_INQUIRY_MAX_NEW_TOKENS,
                JSON_OBJECT_END
            );
            JSONObject parsed = parseJson(raw);
            String target = exactSupportedSearchTarget(parsed.optString("target", ""));
            int confidence = parsed.optInt("confidence", 0);
            DiagnosticLogger.event("offline_search_target_ai_correction", new JSONObject()
                .put("elapsed_ms", DiagnosticLogger.elapsed(diagnosticStarted))
                .put("raw_target", rawTarget)
                .put("target", target)
                .put("confidence", confidence)
                .put("raw", DiagnosticLogger.excerpt(raw)));
            if (confidence >= 50) return target;
        } catch (Exception error) {
            DiagnosticLogger.eventPairs(
                "offline_search_target_ai_correction_error",
                "elapsed_ms", DiagnosticLogger.elapsed(diagnosticStarted),
                "raw_target", rawTarget,
                "error", error.getClass().getSimpleName(),
                "message", DiagnosticLogger.excerpt(error.getMessage())
            );
        }
        return "";
    }

    private static String exactSupportedSearchTarget(String value) {
        String normalized = normalizeText(value);
        if (normalized.isEmpty() || "none".equalsIgnoreCase(normalized) || "null".equalsIgnoreCase(normalized)) {
            return "";
        }
        String[] supported = OfflineVisionInterpreter.supportedSearchTargetList().split("、");
        for (String name : supported) {
            if (normalizeText(name).equals(normalized)) {
                return name;
            }
        }
        return "";
    }

    private static String normalizeText(String value) {
        if (value == null) return "";
        return value
            .trim()
            .toLowerCase(java.util.Locale.US)
            .replace(" ", "")
            .replace("，", "")
            .replace("。", "")
            .replace(",", "")
            .replace(".", "");
    }

    private static String appendThinking(String existing, String extra) {
        if (existing == null || existing.trim().isEmpty()) return extra;
        return existing.trim() + "\n" + extra;
    }

    private JSONObject deterministicTaskControl(String text) throws Exception {
        if (!"task".equals(mode) || taskPlan.length() == 0) return null;
        if (containsAny(text, "完成", "好了", "做完", "下一步")) {
            return fallbackIntent("task_done", "好的，这一步已完成。")
                .put("thinking", "确定性识别任务步骤完成");
        }
        if (containsAny(text, "跳过")) {
            return fallbackIntent("task_skip", "已跳过这一步。")
                .put("thinking", "确定性识别跳过当前步骤");
        }
        if (containsAny(text, "上一步", "上一部", "前一步")) {
            return fallbackIntent("task_previous", "返回上一步。")
                .put("thinking", "确定性识别返回上一步");
        }
        if (containsAny(text, "重复", "再说一遍")) {
            return fallbackIntent("task_repeat", "我再重复当前步骤。")
                .put("thinking", "确定性识别重复步骤");
        }
        if (containsAny(text, "第几步", "进度", "状态")) {
            return fallbackIntent("task_status", "正在查看当前步骤。")
                .put("thinking", "确定性识别任务状态查询");
        }
        return null;
    }

    private JSONObject deterministicCareRecord(String text) throws Exception {
        if (!isCareRecordCommand(text)) return null;
        String recordType = careRecordType(text);
        String recordText = cleanCareRecordText(text);
        String speech = "已记录：" + recordText + "。已加入" + recordType + "记录，照护端可复核。";
        return fallbackIntent("care_record", speech)
            .put("record_type", recordType)
            .put("record_text", recordText)
            .put("care_event_title", "照护助手记录：" + recordType)
            .put("care_event_detail", recordText)
            .put("care_event_severity", "medium")
            .put("thinking", "确定性识别照护记录指令");
    }

    private static boolean isCareRecordCommand(String text) {
        String value = text == null ? "" : text.trim();
        if (value.isEmpty()) return false;
        if (isSearchIntentRequest(value) || isNavigationSafetyQuestion(value) || isCapabilityQuestion(value)) return false;
        boolean explicitRecord = containsAny(value, "记录", "记一下", "记下", "帮我记", "补记", "打卡");
        boolean medicationAction = containsAny(value, "已吃", "吃了", "吃过", "服了", "服用", "用过", "刚吃", "刚服")
            && containsAny(value, "药", "降压", "降糖", "胰岛素", "药片", "药丸", "胶囊");
        boolean symptomRecord = containsAny(value, "头晕", "头疼", "疼", "不舒服", "胸闷", "心慌", "血压", "血糖", "摔倒", "跌倒")
            && containsAny(value, "记录", "记一下", "今天", "刚才", "我");
        return explicitRecord || medicationAction || symptomRecord;
    }

    private static String careRecordType(String text) {
        String value = text == null ? "" : text;
        if (containsAny(value, "药", "降压", "降糖", "胰岛素", "药片", "药丸", "胶囊", "服用", "用药")) {
            return "用药";
        }
        if (containsAny(value, "头晕", "头疼", "疼", "不舒服", "胸闷", "心慌", "血压", "血糖")) {
            return "症状";
        }
        if (containsAny(value, "摔倒", "跌倒", "报警")) {
            return "风险";
        }
        return "照护";
    }

    private static String cleanCareRecordText(String text) {
        String value = extractAfter(text, "帮我记录一下", "帮我记录", "请记录一下", "请记录", "记录一下", "记录", "记一下", "记下", "帮我记一下", "帮我记");
        if (value.isEmpty()) value = text == null ? "" : text.trim();
        value = value
            .replace("我已经", "")
            .replace("已经", "")
            .replace("我刚才", "")
            .replace("刚才", "")
            .replace("我", "")
            .replace("了了", "了")
            .replace("。", "")
            .replace("，", "")
            .replace(",", "")
            .replace("！", "")
            .replace("?", "")
            .replace("？", "")
            .trim();
        if (value.endsWith("了")) value = value.substring(0, value.length() - 1).trim();
        return value.isEmpty() ? "新增照护记录" : value;
    }

    private static void fillCareRecordFields(JSONObject result, String transcript) throws Exception {
        String recordText = result.optString("record_text", "").trim();
        if (recordText.isEmpty()) {
            recordText = cleanCareRecordText(transcript);
            result.put("record_text", recordText);
        }
        String recordType = result.optString("record_type", "").trim();
        if (recordType.isEmpty()) {
            recordType = careRecordType(recordText + transcript);
            result.put("record_type", recordType);
        }
        if (!result.has("care_event_title")) {
            result.put("care_event_title", "照护助手记录：" + recordType);
        }
        if (!result.has("care_event_detail")) {
            result.put("care_event_detail", recordText);
        }
        if (!result.has("care_event_severity")) {
            result.put("care_event_severity", "medium");
        }
        if (result.optString("speech", "").trim().isEmpty()) {
            result.put("speech", "已记录：" + recordText + "。已加入" + recordType + "记录，照护端可复核。");
        }
    }

    private JSONObject fallbackIntent(String intent, String speech) throws Exception {
        return new JSONObject()
            .put("thinking", "")
            .put("intent", intent)
            .put("search_target", JSONObject.NULL)
            .put("target", JSONObject.NULL)
            .put("tag_name", JSONObject.NULL)
            .put("task_name", JSONObject.NULL)
            .put("scene_description", JSONObject.NULL)
            .put("speech", speech);
    }

    private JSONObject expandCompactInquiryResult(JSONObject result) throws Exception {
        if (result == null) return null;
        JSONObject expanded = new JSONObject(result.toString());
        if (expanded.has("i") && !expanded.has("intent")) {
            expanded.put("intent", expandIntentCode(expanded.optString("i", "info")));
        }
        if (expanded.has("s") && !expanded.has("speech")) {
            expanded.put("speech", expanded.optString("s", ""));
        }
        if (expanded.has("r") && !expanded.has("thinking")) {
            expanded.put("thinking", expanded.optString("r", ""));
        }
        if (expanded.has("q") && !expanded.has("search_target")) {
            expanded.put("search_target", expanded.optString("q", ""));
        }
        if (expanded.has("t") && !expanded.has("target")) {
            expanded.put("target", expanded.optString("t", ""));
        }
        if (expanded.has("tag") && !expanded.has("tag_name")) {
            expanded.put("tag_name", expanded.optString("tag", ""));
        }
        if (expanded.has("task") && !expanded.has("task_name")) {
            expanded.put("task_name", expanded.optString("task", ""));
        }
        if (expanded.has("scene") && !expanded.has("scene_description")) {
            expanded.put("scene_description", expanded.optString("scene", ""));
        }
        if (!expanded.has("thinking")) expanded.put("thinking", "");
        if (!expanded.has("intent")) expanded.put("intent", "info");
        if (!expanded.has("speech")) expanded.put("speech", "");
        return expanded;
    }

    private static String expandIntentCode(String value) {
        String code = value == null ? "" : value.trim();
        String lower = code.toLowerCase(java.util.Locale.US);
        switch (lower) {
            case "search":
            case "nav_check":
            case "micro_nav":
            case "tag":
            case "task":
            case "task_done":
            case "task_skip":
            case "task_previous":
            case "task_repeat":
            case "task_status":
            case "care_record":
            case "stop":
            case "info":
                return lower;
            default:
                break;
        }
        if (code.length() > 1) {
            String first = code.substring(0, 1).toUpperCase(java.util.Locale.US);
            if ("SNMLPDKBRUXCI".contains(first)) {
                code = first;
            }
        }
        return switch (code.toUpperCase(java.util.Locale.US)) {
            case "S" -> "search";
            case "N" -> "nav_check";
            case "M" -> "micro_nav";
            case "L" -> "tag";
            case "P" -> "task";
            case "D" -> "task_done";
            case "K" -> "task_skip";
            case "B" -> "task_previous";
            case "R" -> "task_repeat";
            case "U" -> "task_status";
            case "C" -> "care_record";
            case "X" -> "stop";
            case "I" -> "info";
            default -> "info";
        };
    }

    private static String normalizeIntent(String value) {
        return expandIntentCode(value);
    }

    private static boolean isWhereQuestion(String text) {
        return containsAny(text, "在哪里", "在哪", "放哪", "哪里", "哪儿");
    }

    private static boolean isNavigationSafetyQuestion(String text) {
        String value = text == null ? "" : text.trim();
        if (value.isEmpty()) return false;
        if (containsAny(value, "障碍", "避障", "路况", "通行", "可不可以走", "能不能走", "能不能过", "能走吗")) {
            return true;
        }
        boolean asksFront = containsAny(value, "看看前面", "看下前面", "看一下前面", "看看前方", "看下前方", "前面", "前方");
        boolean asksSafety = containsAny(value, "能不能", "有没有", "能否", "危险", "安全", "走", "着", "过", "路");
        return asksFront && asksSafety && !containsAny(value, "找我的", "找到我的", "帮我找", "寻找", "找一下");
    }

    private static boolean isSearchIntentRequest(String text) {
        String value = text == null ? "" : text.trim();
        if (value.isEmpty()) return false;
        if (isNavigationSafetyQuestion(value)) return false;
        return containsAny(
            value,
            "帮我找",
            "帮我找到",
            "找一下",
            "寻找",
            "找找",
            "找到我的",
            "找我的",
            "我的",
            "在哪里",
            "在哪",
            "哪儿",
            "哪里",
            "定位"
        ) && !isCapabilityQuestion(value);
    }

    private static boolean isObjectSearchGoal(String goal) {
        String value = cleanTarget(goal);
        if (value.isEmpty()) return false;
        if (containsAny(
            value,
            "通过",
            "穿过",
            "进入",
            "走到",
            "走去",
            "前往",
            "到达",
            "通行",
            "巡路",
            "路线",
            "走廊",
            "门口",
            "门厅",
            "卫生间",
            "厕所",
            "浴室",
            "厨房",
            "客厅",
            "卧室",
            "楼梯",
            "电梯",
            "出口",
            "入口",
            "通道",
            "前方空间",
            "空地",
            "空间",
            "尽头"
        )) {
            return false;
        }
        return true;
    }

    private static boolean isCapabilityQuestion(String text) {
        String value = text == null ? "" : text.trim();
        return containsAny(
            value,
            "可以做什么",
            "可以说什么",
            "能做什么",
            "能说什么",
            "有什么功能",
            "你会什么",
            "你能干什么",
            "你能做什么",
            "你能说什么",
            "能帮我什么",
            "你提做什么"
        );
    }

    private static String offlineCapabilitySpeech(String transcript, String modelSpeech) {
        String speech = modelSpeech == null ? "" : modelSpeech.trim();
        if (!speech.isEmpty()
            && !"找物".equals(speech)
            && !"正在找物".equals(speech)
            && speech.length() >= 6
            && !speech.contains("某个东西")) {
            return speech;
        }
        if (isCapabilityQuestion(transcript)) {
            return "我可以看路、找东西、提醒风险。";
        }
        return "我可以继续回答，也可以帮你看路、找东西。";
    }

    private static String extractMemoryObject(String text) {
        String clean = cleanTarget(text);
        clean = clean.replace("我的", "").replace("我记的", "").replace("在哪里", "")
            .replace("在哪", "").replace("放哪了", "").replace("放哪", "")
            .replace("哪里", "").replace("哪儿", "");
        return clean.trim();
    }

    private static String extractSearchTarget(String text) {
        String value = extractAfter(text, "帮我找到", "帮我找", "找我的", "找到我的", "找一下", "带我去找", "我要找", "寻找");
        if (!value.isEmpty()) return value;
        if (isWhereQuestion(text) && !text.startsWith("我的")) {
            return extractMemoryObject(text);
        }
        return "";
    }

    private static String extractAfter(String text, String... prefixes) {
        for (String prefix : prefixes) {
            int index = text.indexOf(prefix);
            if (index >= 0) {
                return cleanTarget(text.substring(index + prefix.length()));
            }
        }
        return "";
    }

    private static String cleanTarget(String value) {
        if (value == null) return "";
        String clean = value.replace("请", "").replace("帮我", "").replace("我的", "")
            .replace("这个", "").replace("那个", "").replace("一个", "")
            .replace("一只", "").replace("一把", "").replace("一张", "")
            .replace("一台", "").replace("一部", "").replace("一下", "")
            .replace("。", "").replace("？", "").replace("?", "").replace("！", "")
            .replace("，", "").replace(",", "").trim();
        return clean.replaceFirst("^到+", "").trim();
    }

    private static boolean containsAny(String text, String... needles) {
        for (String needle : needles) {
            if (text != null && text.contains(needle)) return true;
        }
        return false;
    }

    private void processNavigationFrame(String imageDataUrl) throws Exception {
        processNavigationFrame(imageDataUrl, false);
    }

    private void processNavigationFrame(String imageDataUrl, boolean forceRefresh) throws Exception {
        long start = System.currentTimeMillis();
        long diagnosticStarted = DiagnosticLogger.start();
        DiagnosticLogger.event("processor_navigation_frame_start", new JSONObject()
            .put("force_refresh", forceRefresh)
            .put("mode", mode)
            .put("current_goal", currentGoal == null ? "" : currentGoal)
            .put("image_chars", imageDataUrl == null ? 0 : imageDataUrl.length()));
        JSONObject result = parseJson(client.visionJson(navigationPrompt(), imageDataUrl, client.settings().visionModel()));

        String priority = result.optString("priority", "low").toLowerCase();
        String category = result.optString("category", "navigation");
        String subject = result.optString("subject", "");
        double distance = result.optDouble("distance", 2.0);
        String direction = result.optString("direction", "ahead");
        String speech = result.optString("speech", "");
        String scene = result.optString("scene_description", "");

        if (!scene.isEmpty()) {
            socialContext.add(scene);
            while (socialContext.size() > 5) {
                socialContext.remove(0);
            }
        }

        if (!subject.isEmpty()) {
            memoryStore.logObject(subject, result.optString("current_location_tag", ""), scene);
        }

        if (!speech.isEmpty() && distance > 0 && !speech.contains("米") && !speech.contains("厘米")) {
            speech = speech + "，距离" + formatDistance(distance) + "。";
        }

        String semanticText = navigationSemanticText(speech, scene, subject, direction, distance);
        if (!forceRefresh && shouldSkipSmartNavigationRefresh(priority, semanticText)) {
            DiagnosticLogger.event("processor_navigation_frame_skip", new JSONObject()
                .put("elapsed_ms", DiagnosticLogger.elapsed(diagnosticStarted))
                .put("priority", priority)
                .put("semantic", DiagnosticLogger.excerpt(semanticText)));
            sink.send(new JSONObject()
                .put("type", "smart_refresh_skipped")
                .put("text", "画面语义与上次导航一致，已跳过刷新")
                .put("ms", System.currentTimeMillis() - start));
            return;
        }
        if (!semanticText.isEmpty()) {
            lastNavigationSemanticText = semanticText;
        }

        if (!speech.isEmpty() && (forceRefresh || shouldSpeak(priority, speech))) {
            speak(speech, true);
        }

        JSONArray objects = localizedObjects(result.optJSONArray("objects"));

        sink.send(new JSONObject()
            .put("type", "result")
            .put("priority", priority)
            .put("subject", subject)
            .put("speech", speech)
            .put("distance", distance)
            .put("direction", direction)
            .put("target_detected", result.optBoolean("target_detected", false))
            .put("current_goal", currentGoal == null ? JSONObject.NULL : currentGoal)
            .put("social_cues", result.optJSONObject("social_cues") != null ? result.optJSONObject("social_cues") : new JSONObject())
            .put("environment", result.optJSONObject("environment") != null ? result.optJSONObject("environment") : new JSONObject())
            .put("objects", objects)
            .put("scene", scene)
            .put("ms", System.currentTimeMillis() - start)
            .put("stats", new JSONObject()));
        DiagnosticLogger.event("processor_navigation_frame_end", new JSONObject()
            .put("elapsed_ms", DiagnosticLogger.elapsed(diagnosticStarted))
            .put("priority", priority)
            .put("subject", DiagnosticLogger.excerpt(subject))
            .put("direction", direction)
            .put("distance", distance)
            .put("speech", DiagnosticLogger.excerpt(speech)));
    }

    private static JSONArray localizedObjects(JSONArray source) throws Exception {
        JSONArray localized = new JSONArray();
        if (source == null) return localized;
        for (int index = 0; index < source.length(); index += 1) {
            JSONObject item = source.optJSONObject(index);
            if (item == null) continue;
            JSONObject copy = new JSONObject(item.toString());
            if (copy.has("name")) {
                copy.put("name", OfflineVisionInterpreter.localizeObjectName(copy.optString("name", "")));
            }
            if (copy.has("category")) {
                copy.put("category", OfflineVisionInterpreter.localizeObjectName(copy.optString("category", "")));
            }
            localized.put(copy);
        }
        return localized;
    }

    private boolean shouldSkipSmartNavigationRefresh(String priority, String semanticText) {
        if (!client.settings().smartNavigationRefreshEnabled()) return false;
        if ("critical".equals(priority)) return false;
        if (semanticText == null || semanticText.trim().isEmpty()) return false;
        if (lastNavigationSemanticText == null || lastNavigationSemanticText.trim().isEmpty()) return false;

        long diagnosticStarted = DiagnosticLogger.start();
        DiagnosticLogger.eventPairs(
            "smart_navigation_refresh_start",
            "previous", DiagnosticLogger.excerpt(lastNavigationSemanticText),
            "current", DiagnosticLogger.excerpt(semanticText)
        );
        try {
            String raw = client.textJson(
                smartNavigationConsistencyPrompt(lastNavigationSemanticText, semanticText),
                client.settings().textModel(),
                OFFLINE_SMART_REFRESH_MAX_NEW_TOKENS,
                JSON_OBJECT_END
            );
            JSONObject judgement = parseJson(raw);
            boolean consistent = judgement.optBoolean("consistent", false);
            DiagnosticLogger.event("smart_navigation_refresh_end", new JSONObject()
                .put("elapsed_ms", DiagnosticLogger.elapsed(diagnosticStarted))
                .put("consistent", consistent)
                .put("raw", DiagnosticLogger.excerpt(raw)));
            return consistent;
        } catch (Exception error) {
            DiagnosticLogger.eventPairs(
                "smart_navigation_refresh_error",
                "elapsed_ms", DiagnosticLogger.elapsed(diagnosticStarted),
                "error", error.getClass().getSimpleName(),
                "message", DiagnosticLogger.excerpt(error.getMessage())
            );
            return false;
        }
    }

    private static String navigationSemanticText(
        String speech,
        String scene,
        String subject,
        String direction,
        double distance
    ) {
        StringBuilder builder = new StringBuilder();
        appendPart(builder, "speech", speech);
        appendPart(builder, "scene", scene);
        appendPart(builder, "subject", subject);
        appendPart(builder, "direction", direction);
        if (distance > 0) appendPart(builder, "distance", formatDistance(distance));
        return builder.toString();
    }

    private static void appendPart(StringBuilder builder, String key, String value) {
        if (value == null || value.trim().isEmpty()) return;
        if (builder.length() > 0) builder.append('\n');
        builder.append(key).append(": ").append(value.trim());
    }

    private void processMicroFrame(String imageDataUrl) throws Exception {
        if (microTarget == null || microTarget.isEmpty()) {
            mode = "nav";
            return;
        }
        long start = System.currentTimeMillis();
        JSONObject result = parseJson(client.visionJson(microPrompt(), imageDataUrl, client.settings().microModel()));
        lastMicroGuidanceSpeech = result.optString("guidance_speech", lastMicroGuidanceSpeech);
        sink.send(new JSONObject()
            .put("type", "micro_result")
            .put("x", result.optInt("x", 0))
            .put("y", result.optInt("y", 0))
            .put("action", result.optString("action", "move"))
            .put("guidance_speech", result.optString("guidance_speech", ""))
            .put("ms", System.currentTimeMillis() - start));
    }

    private void processTaskFrame(String imageDataUrl) throws Exception {
        if (taskPlan.length() == 0 || currentStepIndex >= taskPlan.length()) {
            mode = "nav";
            taskPlan = new JSONArray();
            currentStepIndex = 0;
            return;
        }

        long start = System.currentTimeMillis();
        JSONObject step = taskPlan.getJSONObject(currentStepIndex);
        String prompt = taskGuidancePrompt(step.optString("instruction", ""));
        JSONObject result = parseJson(client.visionJson(prompt, imageDataUrl, client.settings().visionModel()));

        if (result.optBoolean("step_completed", false)) {
            step.put("completed", true);
            currentStepIndex += 1;
            if (currentStepIndex >= taskPlan.length()) {
                mode = "nav";
                speak("任务完成。", true);
            } else {
                speak("这一步完成。下一步：" + taskPlan.getJSONObject(currentStepIndex).optString("instruction"), true);
            }
        } else {
            String speech = result.optString("speech", "");
            if (!speech.isEmpty() && shouldSpeak("medium", speech)) {
                speak(speech, true);
            }
        }

        sink.send(new JSONObject()
            .put("type", "task_update")
            .put("plan", taskPlan)
            .put("current_step_index", currentStepIndex)
            .put("visual_feedback", result.optString("visual_feedback", ""))
            .put("mode", mode)
            .put("ms", System.currentTimeMillis() - start));
    }

    private String handleIntent(String intent, JSONObject result) throws Exception {
        if ("micro_nav".equals(intent)) {
            String target = result.optString("target", "");
            if (!target.isEmpty()) {
                mode = "micro";
                microTarget = target;
                lastMicroGuidanceSpeech = "";
                return "正在引导你靠近" + target + "。请保持稳定。";
            }
        } else if ("search".equals(intent)) {
            String goal = result.optString("search_target", result.optString("goal", ""));
            if (!goal.isEmpty()) {
                mode = "nav";
                currentGoal = goal;
                return "好的，正在寻找" + goal + "。";
            }
        } else if ("stop".equals(intent)) {
            mode = "nav";
            currentGoal = null;
            microTarget = null;
            taskPlan = new JSONArray();
            currentStepIndex = 0;
            return "已停止所有任务和搜索。";
        } else if ("tag".equals(intent)) {
            String name = result.optString("tag_name", "");
            String desc = result.optString("scene_description", "");
            if (!name.isEmpty()) {
                memoryStore.addLocation(name, desc);
                return "已将当前位置标记为" + name + "。";
            }
        } else if ("care_record".equals(intent)) {
            return handleCareRecord(result);
        } else if ("task".equals(intent)) {
            return generateTaskPlan(result.optString("task_name", ""));
        } else if (intent.startsWith("task_")) {
            return handleTaskControl(intent);
        }
        return null;
    }

    private String handleCareRecord(JSONObject result) throws Exception {
        fillCareRecordFields(result, result.optString("record_text", ""));
        String recordType = result.optString("record_type", "照护");
        String recordText = result.optString("record_text", "新增照护记录");
        String speech = result.optString("speech", "已记录：" + recordText + "。已加入" + recordType + "记录，照护端可复核。");
        sink.send(new JSONObject()
            .put("type", "care_record")
            .put("record_type", recordType)
            .put("record_text", recordText)
            .put("title", result.optString("care_event_title", "照护助手记录：" + recordType))
            .put("detail", result.optString("care_event_detail", recordText))
            .put("severity", result.optString("care_event_severity", "medium"))
            .put("source", "老人端语音记录")
            .put("speech", speech));
        return speech;
    }

    private String generateTaskPlan(String taskName) throws Exception {
        if (taskName == null || taskName.trim().isEmpty()) {
            return "我没有听清任务名称。";
        }

        String prompt = taskPlannerPrompt(taskName);
        Object parsed = parseJsonAny(client.textJson(prompt, client.settings().textModel(), TASK_PLAN_MAX_NEW_TOKENS));
        if (!(parsed instanceof JSONArray)) {
            return "我没能生成有效计划。";
        }

        taskPlan = (JSONArray) parsed;
        currentStepIndex = 0;
        mode = "task";
        sink.send(new JSONObject()
            .put("type", "task_update")
            .put("plan", taskPlan)
            .put("current_step_index", 0)
            .put("mode", mode));

        return "已为" + taskName + "生成计划。第一步：" + taskPlan.getJSONObject(0).optString("instruction");
    }

    private String handleTaskControl(String intent) throws Exception {
        if (!"task".equals(mode) || taskPlan.length() == 0) {
            return "当前没有可控制的任务。";
        }

        String response;
        if ("task_skip".equals(intent) || "task_done".equals(intent)) {
            taskPlan.getJSONObject(currentStepIndex).put("completed", true);
            currentStepIndex += 1;
            if (currentStepIndex >= taskPlan.length()) {
                mode = "nav";
                response = "任务完成。";
            } else {
                response = "已完成。下一步：" + taskPlan.getJSONObject(currentStepIndex).optString("instruction");
            }
        } else if ("task_previous".equals(intent)) {
            if (currentStepIndex > 0) {
                currentStepIndex -= 1;
                taskPlan.getJSONObject(currentStepIndex).put("completed", false);
                response = "返回上一步：" + taskPlan.getJSONObject(currentStepIndex).optString("instruction");
            } else {
                response = "已经在第一步。";
            }
        } else if ("task_repeat".equals(intent)) {
            response = "当前步骤：" + taskPlan.getJSONObject(currentStepIndex).optString("instruction");
        } else if ("task_status".equals(intent)) {
            response = "当前是第 " + (currentStepIndex + 1) + " 步，共 " + taskPlan.length() + " 步。";
        } else {
            response = "未知的任务指令。";
        }

        sink.send(new JSONObject()
            .put("type", "task_update")
            .put("plan", taskPlan)
            .put("current_step_index", currentStepIndex)
            .put("mode", mode));
        return response;
    }

    private boolean shouldSpeak(String priority, String speech) {
        long now = System.currentTimeMillis();
        if ("critical".equals(priority)) {
            lastSpeechAt = now;
            lastSpeech = speech;
            return true;
        }
        long duplicateWindow = client.settings().voiceFirstEnabled() ? 4200 : 8000;
        long cooldown = client.settings().voiceFirstEnabled()
            ? VOICE_FIRST_SPEECH_COOLDOWN_MS
            : SPEECH_COOLDOWN_MS;
        if (speech.equals(lastSpeech) && now - lastSpeechAt < duplicateWindow) {
            return false;
        }
        if (now - lastSpeechAt < cooldown) {
            return false;
        }
        lastSpeechAt = now;
        lastSpeech = speech;
        return true;
    }

    private void speak(String text, boolean force) throws Exception {
        if (text == null || text.isEmpty()) return;
        if (force || shouldSpeak("high", text)) {
            DiagnosticLogger.event("processor_speak_emit", new JSONObject()
                .put("force", force)
                .put("chars", text.length())
                .put("text", DiagnosticLogger.excerpt(text)));
            sink.send(new JSONObject().put("type", "speak").put("text", text));
        }
    }

    private void sendError(String text) {
        try {
            sink.send(new JSONObject().put("type", "error").put("text", text));
        } catch (Exception ignored) {
        }
    }

    private boolean isOfflineRuntime() {
        return AiRuntimeMode.from(client.settings().aiRuntimeMode()).isOffline();
    }

    private static String readableError(Exception e) {
        String message = e.getMessage();
        return message == null || message.isEmpty() ? e.getClass().getSimpleName() : message;
    }

    private static boolean hasImageData(String imageDataUrl) {
        return imageDataUrl != null && !imageDataUrl.trim().isEmpty();
    }

    private static boolean containsGuidanceKeyword(String text) {
        return text != null && text.contains("引导");
    }

    private static boolean containsCloseKeyword(String text) {
        return text != null && containsAny(text, "关闭", "停止", "退出", "结束", "取消");
    }

    private static JSONObject parseJson(String text) throws Exception {
        Object value = parseJsonAny(text);
        if (value instanceof JSONObject) {
            return (JSONObject) value;
        }
        throw new IllegalArgumentException("模型没有返回 JSON 对象。");
    }

    private static Object parseJsonAny(String text) throws Exception {
        String clean = text == null ? "" : text.trim();
        if (clean.startsWith("```json")) clean = clean.substring(7).trim();
        if (clean.startsWith("```")) clean = clean.substring(3).trim();
        if (clean.endsWith("```")) clean = clean.substring(0, clean.length() - 3).trim();
        try {
            if (clean.startsWith("[")) return new JSONArray(clean);
            return new JSONObject(clean);
        } catch (Exception ignored) {
            int objectStart = clean.indexOf('{');
            int arrayStart = clean.indexOf('[');
            int start;
            if (objectStart < 0) start = arrayStart;
            else if (arrayStart < 0) start = objectStart;
            else start = Math.min(objectStart, arrayStart);
            String json = firstCompleteJson(clean, start);
            if (json == null) throw ignored;
            if (json.startsWith("[")) return new JSONArray(json);
            return new JSONObject(json);
        }
    }

    private static String firstCompleteJson(String text, int start) {
        if (text == null || start < 0 || start >= text.length()) return null;
        ArrayList<Character> stack = new ArrayList<>();
        boolean inString = false;
        boolean escaped = false;
        for (int index = start; index < text.length(); index += 1) {
            char ch = text.charAt(index);
            if (inString) {
                if (escaped) {
                    escaped = false;
                } else if (ch == '\\') {
                    escaped = true;
                } else if (ch == '"') {
                    inString = false;
                }
                continue;
            }
            if (ch == '"') {
                inString = true;
            } else if (ch == '{') {
                stack.add('}');
            } else if (ch == '[') {
                stack.add(']');
            } else if (ch == '}' || ch == ']') {
                if (stack.isEmpty() || stack.get(stack.size() - 1) != ch) return null;
                stack.remove(stack.size() - 1);
                if (stack.isEmpty()) {
                    return text.substring(start, index + 1);
                }
            }
        }
        return null;
    }

    private String navigationPrompt() {
        String context = socialContext.isEmpty() ? "无" : String.join(" | ", socialContext);
        boolean objectSearchGoal = isObjectSearchGoal(currentGoal);
        String task = currentGoal == null
            ? "通用导航"
            : objectSearchGoal ? "找物目标：" + currentGoal : "导航目标：" + currentGoal;
        String missingTargetRule = objectSearchGoal
            ? """
            If Current task starts with "找物目标：" and the requested object is not clearly visible in the image:
            - Do not infer, hallucinate, or guess the object position from surrounding objects.
            - Set target_detected to false, confidence_score to 0, distance to 0, direction to "unknown".
            - speech must tell the user: "我还没有看到目标，请缓慢向左或向右转动手机，然后再次刷新。"
            - scene_description may summarize what is visible, but must not claim the object was found.
            If the object is visible, give body-relative, tactile guidance to approach or touch it.
            """
            : """
            If Current task is "通用导航" or starts with "导航目标：":
            - Do not use the missing-object phone-rotation instruction.
            - Do not say "我还没有看到目标" only because a hallway, doorway, room, path, or passage goal is not centered.
            - Give route guidance based on walkable space, obstacles, doorway edges, walls, and safe body-relative movement.
            """;
        return """
            You are 银龄智护, a socially aware visual navigation assistant for blind users.
            Keep JSON keys and enum values in English. All natural-language values must be Simplified Chinese.
            Current task: %s
            Temporal context: %s
            Memory: %s
            Known locations: %s

            Analyze hazards, navigable space, people, social intent, object states, text, and affordances.
            %s
            If immediate danger is within 0.5m, start speech with "停下".
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
            """.formatted(task, context, memoryStore.historyContext(), memoryStore.locationSummary(), missingTargetRule);
    }

    private String microPrompt() {
        return """
            You are 多模态长护精确引导模式, a high-speed precision guidance system.
            Target: %s
            Keep JSON keys and action enum values in English. guidance_speech must be Simplified Chinese.
            Locate the target and return relative vector from image center.
            X: -100 left to 100 right. Y: -100 down to 100 up.
            action: move, push, or stop.
            The user may be blind or low-vision. Use direct tactile and body-relative words in guidance_speech.
            Do not rely on color-only clues. Prefer "手机稍微向左", "向前半步", "右手沿桌边向下摸", "现在按下".
            Output JSON:
            {"x":0,"y":0,"action":"move|push|stop","guidance_speech":"向左|向右|向上|向下|慢慢向前|现在按下|null"}
            """.formatted(microTarget);
    }

    private String microFollowUpPrompt(String transcript) {
        return """
            You are 银龄智护 during an active precision guidance session for a blind or low-vision user.
            Current precision target: "%s"
            Last short guidance: "%s"
            User follow-up question: "%s"
            Memory: %s

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
            """.formatted(
                microTarget == null ? "" : microTarget,
                lastMicroGuidanceSpeech == null ? "" : lastMicroGuidanceSpeech,
                transcript == null ? "" : transcript,
                memoryStore.historyContext()
            );
    }

    private String smartNavigationConsistencyPrompt(String previous, String current) {
        return """
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
            %s

            当前：
            %s
            """.formatted(previous, current);
    }

    private String inquiryPrompt(String transcript) {
        return """
            You are 银龄智护, the brain of a smart navigation assistant for blind users.
            Understand Mandarin Chinese and English. Keep JSON keys and intent enum values in English.
            Write all natural-language values in Simplified Chinese.
            User command transcript: "%s"
            History: %s
            Task state: %s

            Intents:
            micro_nav: press/find/manipulate a small target. Set target.
            search: find or locate an object. Set search_target.
            tag: remember current place. Set tag_name and scene_description.
            care_record: record medication, symptom, care status, or health event. Set record_type and record_text.
            task: complex physical process. Set task_name.
            task_skip, task_previous, task_repeat, task_done, task_status: control active task.
            stop: cancel current search/task.
            info: answer question or describe scene/text.

            Rules:
            - Return exactly one JSON object.
            - Do not output Markdown, explanations, examples, or multiple JSON blocks.
            - intent must be one of the listed enum values; never invent another intent value.
            - intent must be one concrete string such as "search"; do not copy the whole enum list into intent.
            - intent must be written in English exactly as listed, never in Chinese.
            - Use null for fields that do not apply.
            - For a find/search command, always set search_target to the object named by the user, even if the object is not visible yet.
            - History is authoritative for "where is my object" questions.
            - If the user asks where a remembered object is, use intent "info" and answer from History.
            - If the user asks to record medicine taken, symptoms, blood pressure, blood sugar, or care status, use intent "care_record".
            - Task control overrides micro navigation. If Task state says a task is active and the user says this step is done/completed, use intent "task_done".
            - Use intent "micro_nav" ONLY when the user explicitly says the keyword "引导".
            - If the user asks to press, touch, align with, or manipulate a small object but does not say "引导", use intent "info" and explain that precision guidance starts only after saying "引导我靠近...".
            - If the user says "关闭" during precision guidance, close precision guidance.
            - The user is blind or low-vision. All speech must use body-relative, tactile, step-by-step language. Do not rely on color-only or vague visual references.

            Output fields:
            thinking, intent, search_target, target, tag_name, task_name, scene_description, record_type, record_text, speech.

            Reference examples:
            {"thinking":"用户要找门","intent":"search","search_target":"门","target":null,"tag_name":null,"task_name":null,"scene_description":null,"speech":"正在寻找门。"}
            {"thinking":"用户要按按钮","intent":"micro_nav","search_target":null,"target":"上行按钮","tag_name":null,"task_name":null,"scene_description":null,"speech":"正在引导你靠近上行按钮。"}
            {"thinking":"用户要记住地点","intent":"tag","search_target":null,"target":null,"tag_name":"办公室门口","task_name":null,"scene_description":"办公室门口","speech":"已记住办公室门口。"}
            {"thinking":"用户要任务指导","intent":"task","search_target":null,"target":null,"tag_name":null,"task_name":"倒一杯水","scene_description":null,"speech":"我来指导你倒水。"}
            {"thinking":"用户要记录用药","intent":"care_record","search_target":null,"target":null,"tag_name":null,"task_name":null,"scene_description":null,"record_type":"用药","record_text":"吃了降压药","speech":"已记录：吃了降压药。已加入用药记录，照护端可复核。"}
            {"thinking":"用户询问记忆中的物体位置","intent":"info","search_target":null,"target":null,"tag_name":null,"task_name":null,"scene_description":null,"speech":"水杯在厨房水槽左侧。"}
            {"thinking":"用户确认当前任务步骤完成","intent":"task_done","search_target":null,"target":null,"tag_name":null,"task_name":null,"scene_description":null,"speech":"这一步已完成。"}

            Output JSON:
            {"thinking":"中文推理","intent":"一个具体枚举值","search_target":null,"target":null,"tag_name":null,"task_name":null,"scene_description":null,"record_type":null,"record_text":null,"speech":"中文回答"}
            """.formatted(transcript, memoryStore.historyContext(), taskStateText());
    }

    private String offlineSearchTargetCorrectionPrompt(String transcript, String rawTarget) {
        return """
            你是银龄智护的离线找物目标校对器。
            语音识别结果可能有错，用户真实想找的物品必须从“当前离线视觉可稳定识别清单”中选择。

            当前离线视觉可稳定识别清单：
            %s

            ASR 原文：
            %s

            上游模型抽取的目标：
            %s

            判断规则：
            - 只在发音、语义或常见生活场景高度匹配时选择清单中的一个中文目标。
            - 例如“到我的晚”可能是“找我的碗”，但只有你确认时才输出“碗”。
            - 如果用户要找的物品不在清单中，target 必须为 "none"。
            - 不要为了触发找物而强行选择相近目标。
            - 只输出一个 JSON 对象，不要 Markdown。

            JSON 格式：
            {"target":"清单中的中文目标或none","confidence":0,"reason":"中文简短理由"}
            """.formatted(
                OfflineVisionInterpreter.supportedSearchTargetList(),
                transcript == null ? "" : transcript,
                rawTarget == null ? "" : rawTarget
            );
    }

    private String taskPlannerPrompt(String taskName) {
        return """
            You are 银龄智护's task planner.
            User request: "%s"
            Memory: %s
            Break the user's physical task into granular, observable, sequential steps.
            Keep JSON keys in English, but write instruction and item names in Simplified Chinese.
            Return exactly one JSON array. Do not output Markdown, explanations, examples, or repeated arrays.
            Output at least 3 steps. JSON array example:
            [
              {"step_id":1,"instruction":"找到杯子","items":["杯子"],"completed":false},
              {"step_id":2,"instruction":"把杯子放稳","items":["杯子"],"completed":false},
              {"step_id":3,"instruction":"倒入适量的水","items":["杯子","水"],"completed":false}
            ]
            """.formatted(taskName, memoryStore.historyContext() + "\n已知地点：" + memoryStore.locationSummary());
    }

    private String taskGuidancePrompt(String instruction) {
        return """
            You are 银龄智护, guiding a user through a physical task.
            Current step: "%s"
            Keep JSON keys in English. speech and visual_feedback must be Simplified Chinese.
            Verify whether the step is visually completed. If not, give short guidance.
            Return exactly one JSON object. Do not output Markdown, explanations, or multiple JSON blocks.
            Output JSON:
            {"step_completed":false,"speech":"中文引导","visual_feedback":"中文短状态"}
            """.formatted(instruction);
    }

    private String taskStateText() {
        if (!"task".equals(mode) || taskPlan.length() == 0 || currentStepIndex >= taskPlan.length()) {
            return "当前没有进行中的任务";
        }
        return "当前任务：第 " + (currentStepIndex + 1) + "/" + taskPlan.length()
            + " 步 - “" + taskPlan.optJSONObject(currentStepIndex).optString("instruction", "") + "”";
    }

    private static String formatDistance(double meters) {
        if (meters < 1.0) return Math.round(meters * 100) + "厘米";
        if (meters < 10.0) return String.format(java.util.Locale.US, "%.1f米", meters);
        return Math.round(meters) + "米";
    }

    interface MessageSink {
        void send(JSONObject data) throws Exception;
    }
}
