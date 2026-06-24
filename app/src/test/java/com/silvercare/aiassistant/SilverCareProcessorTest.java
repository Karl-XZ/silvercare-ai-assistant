package com.silvercare.aiassistant;

import org.json.JSONObject;
import org.junit.Test;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.lessThan;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.notNullValue;

public class SilverCareProcessorTest {
    @Test
    public void navigationFrameEmitsResultAndSpeechWithDistance() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.visionResponses.add("""
            {
              "thinking":"前方有门",
              "priority":"high",
              "category":"navigation",
              "subject":"门",
              "distance":0.75,
              "direction":"ahead",
              "speech":"前方有门",
              "scene_description":"走廊尽头有门",
              "objects":[{"name":"门","distance":0.75,"direction":"ahead"}]
            }
            """);
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processFrame("data:image/png;base64,test");

        JSONObject speak = sink.firstOfType("speak");
        JSONObject result = sink.firstOfType("result");
        assertThat(speak, notNullValue());
        assertThat(speak.optString("text"), containsString("距离75厘米"));
        assertThat(result, notNullValue());
        assertThat(result.optString("direction"), equalTo("ahead"));
        assertThat(result.optJSONArray("objects").length(), equalTo(1));
    }

    @Test
    public void smartRefreshSkipsSemanticallyConsistentNavigationText() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.settings.smartNavigationRefreshEnabled = true;
        ai.visionResponses.add("""
            {
              "thinking":"前方有门",
              "priority":"medium",
              "category":"navigation",
              "subject":"门",
              "distance":0.75,
              "direction":"ahead",
              "speech":"前方有门",
              "scene_description":"走廊尽头有门"
            }
            """);
        ai.visionResponses.add("""
            {
              "thinking":"前方还是门",
              "priority":"medium",
              "category":"navigation",
              "subject":"门",
              "distance":0.80,
              "direction":"ahead",
              "speech":"正前方仍然是门",
              "scene_description":"走廊尽头仍然有门"
            }
            """);
        ai.textResponses.add("""
            {"consistent":true,"reason":"同一扇门和同一方向，行动建议没有变化"}
            """);
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processFrame("data:image/png;base64,test");
        processor.processFrame("data:image/png;base64,test2");

        assertThat(countMessages(sink, "result"), equalTo(1));
        assertThat(countMessages(sink, "speak"), equalTo(1));
        assertThat(countMessages(sink, "smart_refresh_skipped"), equalTo(1));
        assertThat(ai.lastTextPrompt, containsString("判断两段面向盲人用户的导航提示是否语义一致"));
    }

    @Test
    public void searchInquiryUpdatesGoalAndSpeaksOverride() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.transcript = "帮我找门";
        ai.visionResponses.add("""
            {
              "thinking":"用户要找门",
              "intent":"search",
              "search_target":"门",
              "speech":"开始找门"
            }
            """);
        addNavigationResponse(ai, "门", "门在左前方，向左前方走。");
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        JSONObject inquiry = sink.firstOfType("inquiry_result");
        JSONObject speak = sink.firstOfType("speak");
        assertThat(inquiry, notNullValue());
        assertThat(inquiry.optString("current_goal"), equalTo("门"));
        assertThat(speak.optString("text"), equalTo("好的，正在寻找门。"));
        assertThat(countMessages(sink, "speak"), equalTo(2));
        assertThat(sink.messages.get(2).optString("text"), containsString("门在左前方"));
        assertThat(sink.firstOfType("result").optString("current_goal"), equalTo("门"));
    }

    @Test
    public void offlineInquiryUsesTextModelForIntent() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.settings.aiRuntimeMode = AiRuntimeMode.OFFLINE_MNN.value;
        ai.transcript = "帮我找杯子";
        ai.textResponses.add("""
            {
              "thinking":"离线文本模型理解用户要找杯子",
              "intent":"search",
              "search_target":"杯子",
              "speech":"开始找杯子"
            }
            """);
        addNavigationResponse(ai, "杯子", "杯子在右侧桌面，向右转。");
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        JSONObject inquiry = sink.firstOfType("inquiry_result");
        assertThat(inquiry, notNullValue());
        assertThat(inquiry.optString("current_goal"), equalTo("杯子"));
        assertThat(ai.lastTextPrompt, containsString("帮我找杯子"));
        assertThat(ai.lastTextModel, equalTo(ai.settings.textModel));
        assertThat(ai.lastTextMaxNewTokens, equalTo(24));
        assertThat(ai.lastTextEndWith, equalTo("}"));
        assertThat(ai.visionResponses.isEmpty(), equalTo(true));
        assertThat(ai.lastVisionPrompt, containsString("找物目标：杯子"));
        assertThat(ai.lastVisionPrompt, containsString("我还没有看到目标，请缓慢向左或向右转动手机，然后再次刷新。"));
        assertThat(sink.firstOfType("result").optString("current_goal"), equalTo("杯子"));
    }

    @Test
    public void navigationGoalDoesNotUseMissingObjectRotationRule() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.transcript = "帮我通过前方门口";
        ai.visionResponses.add("""
            {
              "thinking":"上游误判为找物，但目标实际是通行导航",
              "intent":"search",
              "search_target":"通过前方门口",
              "speech":"开始通过门口"
            }
            """);
        addNavigationResponse(ai, "门口", "前方门口可通行，请贴着右侧慢慢走。");
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        assertThat(ai.lastVisionPrompt, containsString("导航目标：通过前方门口"));
        assertThat(ai.lastVisionPrompt, not(containsString("找物目标：通过前方门口")));
        assertThat(ai.lastVisionPrompt, not(containsString("我还没有看到目标，请缓慢向左或向右转动手机，然后再次刷新。")));
        assertThat(sink.firstOfType("result").optString("current_goal"), equalTo("通过前方门口"));
    }

    @Test
    public void offlineCompactIntentNormalizesNoisyRouterCode() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.settings.aiRuntimeMode = AiRuntimeMode.OFFLINE_MNN.value;
        ai.transcript = "帮我找杯子";
        ai.textResponses.add("""
            {"i":"S找物","q":"杯子","s":"开始找杯子"}
            """);
        addNavigationResponse(ai, "杯子", "杯子在右侧桌面，向右转。");
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        JSONObject inquiry = sink.firstOfType("inquiry_result");
        assertThat(inquiry, notNullValue());
        assertThat(inquiry.optString("current_goal"), equalTo("杯子"));
        assertThat(sink.firstOfType("result").optString("current_goal"), equalTo("杯子"));
    }

    @Test
    public void offlineCompactIntentFallsBackToInfoWhenRouterReturnsInvalidCode() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.settings.aiRuntimeMode = AiRuntimeMode.OFFLINE_MNN.value;
        ai.transcript = "你好，你可以做什么";
        ai.textResponses.add("""
            {"i":"你好","s":"我可以帮你看路、找东西、提醒风险。"}
            """);
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        JSONObject inquiry = sink.firstOfType("inquiry_result");
        JSONObject speak = sink.firstOfType("speak");
        assertThat(inquiry, notNullValue());
        assertThat(inquiry.isNull("current_goal"), equalTo(true));
        assertThat(speak.optString("text"), containsString("看路"));
    }

    @Test
    public void offlineInfoInquiryUsesShortFourBPromptAndTokenBudget() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.settings.aiRuntimeMode = AiRuntimeMode.OFFLINE_MNN.value;
        ai.transcript = "我现在有点不知道该怎么办";
        ai.textResponses.add("""
            {
              "thinking":"用户需要能力说明和安全建议",
              "intent":"info",
              "search_target":null,
              "speech":"我可以帮你看路、找东西、提醒风险，也可以回答当前操作问题。"
            }
            """);
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        JSONObject speak = sink.firstOfType("speak");
        assertThat(speak, notNullValue());
        assertThat(speak.optString("text"), containsString("看路"));
        assertThat(ai.lastTextPrompt, containsString("我现在有点不知道该怎么办"));
        assertThat(ai.lastTextModel, equalTo(ai.settings.textModel));
        assertThat(ai.lastTextMaxNewTokens, equalTo(24));
        assertThat(ai.lastTextEndWith, equalTo("}"));
    }

    @Test
    public void offlineSearchCorrectsAsrTargetBeforeStartingSearch() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.settings.aiRuntimeMode = AiRuntimeMode.OFFLINE_MNN.value;
        ai.transcript = "帮我找到我的晚";
        ai.textResponses.add("""
            {
              "thinking":"ASR 可能把碗识别成晚",
              "intent":"search",
              "search_target":"到我的晚",
              "speech":"开始找晚"
            }
            """);
        ai.textResponses.add("""
            {"target":"碗","confidence":88,"reason":"ASR 的“晚”与用户找物语境中的“碗”发音接近"}
            """);
        addNavigationResponse(ai, "碗", "碗在左侧，距离约1.2米。");
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        JSONObject inquiry = sink.firstOfType("inquiry_result");
        assertThat(inquiry, notNullValue());
        assertThat(inquiry.optString("current_goal"), equalTo("碗"));
        assertThat(ai.lastTextPrompt, containsString("离线找物目标校对器"));
        assertThat(ai.lastTextPrompt, containsString("到我的晚"));
        assertThat(ai.lastTextModel, equalTo(ai.settings.textModel));
        assertThat(sink.firstOfType("speak").optString("text"), equalTo("好的，正在寻找碗。"));
        assertThat(sink.firstOfType("result").optString("current_goal"), equalTo("碗"));
    }

    @Test
    public void offlineNavigationQuestionDoesNotBecomeSearchTarget() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.settings.aiRuntimeMode = AiRuntimeMode.OFFLINE_MNN.value;
        ai.textResponses.add("""
            {"i":"N","s":"正在查看前方通行。"}
            """);
        addNavigationResponse(ai, "大型障碍", "前方有大型障碍，请向右侧绕开。");
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processTextInquiry(
            "data:image/png;base64,test",
            "帮我看看前面能不能着前方有没有障碍物"
        );

        JSONObject inquiry = sink.firstOfType("inquiry_result");
        JSONObject result = sink.firstOfType("result");
        assertThat(inquiry, notNullValue());
        assertThat(inquiry.isNull("current_goal"), equalTo(true));
        assertThat(result, notNullValue());
        assertThat(result.isNull("current_goal"), equalTo(true));
        assertThat(ai.lastTextModel, equalTo(ai.settings.textModel));
        assertThat(ai.lastTextPrompt, containsString("帮我看看前面能不能着前方有没有障碍物"));
        assertThat(ai.lastVisionPrompt, containsString("通用导航"));
        assertThat(sink.firstOfType("speak").optString("text"), containsString("通行"));
    }

    @Test
    public void offlineNavigationQuestionOverridesModelSearchMisroute() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.settings.aiRuntimeMode = AiRuntimeMode.OFFLINE_MNN.value;
        ai.transcript = "帮我看看前面能不能着前方有没有障碍物";
        ai.textResponses.add("""
            {
              "thinking":"误判为找物",
              "intent":"search",
              "search_target":"前方障碍物",
              "speech":"正在寻找障碍物"
            }
            """);
        addNavigationResponse(ai, "小型障碍", "左侧约3.5米有小型障碍，请注意避让。");
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/wav;base64,test");

        JSONObject inquiry = sink.firstOfType("inquiry_result");
        JSONObject result = sink.firstOfType("result");
        assertThat(inquiry, notNullValue());
        assertThat(inquiry.isNull("current_goal"), equalTo(true));
        assertThat(result, notNullValue());
        assertThat(result.isNull("current_goal"), equalTo(true));
        assertThat(ai.lastTextPrompt, containsString("帮我看看前面能不能着前方有没有障碍物"));
        assertThat(ai.lastTextModel, equalTo(ai.settings.textModel));
        assertThat(ai.lastTextPrompt, not(containsString("离线找物目标校正器")));
        assertThat(sink.firstOfType("speak").optString("text"), equalTo("正在查看前方是否可以通行。"));
    }

    @Test
    public void offlineSearchRejectsUnsupportedTargetAndStaysInConversation() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.settings.aiRuntimeMode = AiRuntimeMode.OFFLINE_MNN.value;
        ai.transcript = "帮我找药盒";
        ai.textResponses.add("""
            {
              "thinking":"用户想找药盒",
              "intent":"search",
              "search_target":"药盒",
              "speech":"开始找药盒"
            }
            """);
        ai.textResponses.add("""
            {"target":"none","confidence":15,"reason":"药盒不在离线视觉可识别物体清单中"}
            """);
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        JSONObject inquiry = sink.firstOfType("inquiry_result");
        JSONObject speak = sink.firstOfType("speak");
        assertThat(inquiry, notNullValue());
        assertThat(inquiry.isNull("current_goal"), equalTo(true));
        assertThat(inquiry.optString("mode"), equalTo("nav"));
        assertThat(speak.optString("text"), containsString("不在当前离线视觉可稳定识别的目标清单里"));
        assertThat(countMessages(sink, "result"), equalTo(0));
    }

    @Test
    public void offlineInquiryAcceptsFirstJsonWhenBackupModelAddsExtraText() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.settings.aiRuntimeMode = AiRuntimeMode.OFFLINE_MNN.value;
        ai.transcript = "帮我找杯子";
        ai.textResponses.add("""
            我会先给出结果：
            {"thinking":"用户要找杯子","intent":"search","search_target":"杯子","speech":"开始找杯子"}
            后续误输出：
            {"intent":"info","speech":"忽略这一段"}
            """);
        addNavigationResponse(ai, "杯子", "杯子在正前方。");
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        JSONObject inquiry = sink.firstOfType("inquiry_result");
        assertThat(inquiry, notNullValue());
        assertThat(inquiry.optString("current_goal"), equalTo("杯子"));
    }

    @Test
    public void offlineInquiryFallsBackWhenBackupModelReturnsNoJson() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.settings.aiRuntimeMode = AiRuntimeMode.OFFLINE_MNN.value;
        ai.transcript = "引导我按电梯的上行按钮";
        ai.textResponses.add("上行按钮通常在电梯门旁边，请慢慢靠近。");
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        JSONObject inquiry = sink.firstOfType("inquiry_result");
        assertThat(inquiry, notNullValue());
        assertThat(inquiry.optString("mode"), equalTo("micro"));
    }

    @Test
    public void microNavigationWithoutGuidanceKeywordFallsBackToGoalMode() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.transcript = "帮我按电梯的上行按钮";
        ai.visionResponses.add("""
            {
              "thinking":"模型误判为精确引导",
              "intent":"micro_nav",
              "target":"电梯上行按钮",
              "speech":"正在引导你靠近上行按钮。"
            }
            """);
        addNavigationResponse(ai, "电梯上行按钮", "电梯上行按钮在左前方，请靠近后再说引导。");
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        JSONObject inquiry = sink.firstOfType("inquiry_result");
        JSONObject speak = sink.firstOfType("speak");
        assertThat(inquiry, notNullValue());
        assertThat(inquiry.optString("mode"), equalTo("nav"));
        assertThat(inquiry.optString("intent"), equalTo("search"));
        assertThat(inquiry.optString("current_goal"), equalTo("电梯上行按钮"));
        assertThat(speak.optString("text"), equalTo("好的，正在寻找电梯上行按钮。"));
        assertThat(speak.optString("text"), not(containsString("请说：引导我靠近目标")));
        assertThat(ai.lastVisionPrompt, containsString("找物目标：电梯上行按钮"));
    }

    @Test
    public void corridorRequestMisclassifiedAsMicroNavFallsBackToNavigationGoal() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.transcript = "我要通过前方走廊";
        ai.visionResponses.add("""
            {
              "thinking":"模型误判为精确引导",
              "intent":"micro_nav",
              "target":"前方走廊",
              "speech":"正在引导你靠近前方走廊。"
            }
            """);
        addNavigationResponse(ai, "走廊", "前方走廊基本通畅，请靠右慢慢直走。");
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        JSONObject inquiry = sink.firstOfType("inquiry_result");
        JSONObject speak = sink.firstOfType("speak");
        assertThat(inquiry, notNullValue());
        assertThat(inquiry.optString("mode"), equalTo("nav"));
        assertThat(inquiry.optString("intent"), equalTo("search"));
        assertThat(inquiry.optString("current_goal"), equalTo("前方走廊"));
        assertThat(speak.optString("text"), equalTo("好的，正在查看前方走廊。"));
        assertThat(speak.optString("text"), not(containsString("请说：引导我靠近目标")));
        assertThat(ai.lastVisionPrompt, containsString("导航目标：前方走廊"));
        assertThat(ai.lastVisionPrompt, not(containsString("我还没有看到目标，请缓慢向左或向右转动手机，然后再次刷新。")));
    }

    @Test
    public void microFollowUpKeepsCurrentGuidanceMode() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.transcript = "引导我按电梯的上行按钮";
        ai.visionResponses.add("""
            {
              "thinking":"用户明确要求精确引导",
              "intent":"micro_nav",
              "target":"电梯上行按钮",
              "speech":"正在引导你靠近上行按钮。"
            }
            """);
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        ai.transcript = "它是在绿色行李箱旁边吗";
        ai.visionResponses.add("""
            {
              "thinking":"用户在精确引导中追问当前位置关系",
              "speech":"不要只依赖颜色。你前面有个行李箱，向前一步摸到行李箱后，沿它底部向下摸，排插在更靠近地面的方向。把手机对准排插再问我下一步。"
            }
            """);

        processor.processInquiry("data:image/png;base64,test2", "data:audio/webm;base64,test2");

        JSONObject inquiry = lastOfType(sink, "inquiry_result");
        JSONObject speak = lastOfType(sink, "speak");
        assertThat(inquiry.optString("mode"), equalTo("micro"));
        assertThat(ai.lastVisionPrompt, containsString("Current precision target"));
        assertThat(speak.optString("text"), containsString("向前一步摸到行李箱"));
    }

    @Test
    public void closeKeywordStopsMicroGuidance() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.transcript = "引导我按电梯的上行按钮";
        ai.visionResponses.add("""
            {
              "thinking":"用户明确要求精确引导",
              "intent":"micro_nav",
              "target":"电梯上行按钮",
              "speech":"正在引导你靠近上行按钮。"
            }
            """);
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        ai.transcript = "停止";
        processor.processInquiry("data:image/png;base64,test2", "data:audio/webm;base64,test2");

        JSONObject inquiry = lastOfType(sink, "inquiry_result");
        JSONObject speak = lastOfType(sink, "speak");
        assertThat(inquiry.optString("mode"), equalTo("nav"));
        assertThat(speak.optString("text"), equalTo("已关闭精确引导。"));
    }

    @Test
    public void transcriptFallbackRestoresSearchTargetWhenSmallModelLeavesItNull() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.settings.aiRuntimeMode = AiRuntimeMode.OFFLINE_MNN.value;
        ai.transcript = "帮我找杯子";
        ai.textResponses.add("""
            {"thinking":"缺少信息","intent":"search","search_target":null,"speech":"请提供更多信息"}
            """);
        addNavigationResponse(ai, "杯子", "杯子在正前方。");
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        JSONObject inquiry = sink.firstOfType("inquiry_result");
        assertThat(inquiry, notNullValue());
        assertThat(inquiry.optString("current_goal"), equalTo("杯子"));
    }

    @Test
    public void offlineMedicationRecordCommandCreatesCareRecordWithoutWaitingForLlm() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.settings.aiRuntimeMode = AiRuntimeMode.OFFLINE_MNN.value;
        ai.transcript = "记录我吃了降压药了";
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        JSONObject inquiry = sink.firstOfType("inquiry_result");
        JSONObject careRecord = sink.firstOfType("care_record");
        JSONObject speak = sink.firstOfType("speak");
        assertThat(inquiry, notNullValue());
        assertThat(inquiry.optString("intent"), equalTo("care_record"));
        assertThat(careRecord, notNullValue());
        assertThat(careRecord.optString("record_type"), equalTo("用药"));
        assertThat(careRecord.optString("record_text"), containsString("降压药"));
        assertThat(speak, notNullValue());
        assertThat(speak.optString("text"), containsString("已记录"));
        assertThat(ai.lastTextPrompt, equalTo(""));
    }

    @Test
    public void transcriptFallbackAnswersRememberedObjectLocation() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.settings.aiRuntimeMode = AiRuntimeMode.OFFLINE_MNN.value;
        ai.transcript = "我的水杯在哪里";
        ai.textResponses.add("""
            {"thinking":"误判","intent":"search","search_target":"水杯","speech":"正在寻找水杯"}
            """);
        TestFakes.Sink sink = new TestFakes.Sink();
        MemoryStore memory = new MemoryStore(new TestFakes.Preferences());
        memory.logObject("水杯", "厨房水槽左侧", "");
        SilverCareProcessor processor = new SilverCareProcessor(ai, memory, sink);

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        JSONObject speak = sink.firstOfType("speak");
        assertThat(speak, notNullValue());
        assertThat(speak.optString("text"), containsString("厨房水槽左侧"));
    }

    @Test
    public void transcriptFallbackTaskDoneOverridesSmallModelMicroNavMistake() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.settings.aiRuntimeMode = AiRuntimeMode.OFFLINE_MNN.value;
        ai.transcript = "教我倒一杯水";
        ai.textResponses.add("""
            {
              "thinking":"用户请求任务指导",
              "intent":"task",
              "task_name":"倒一杯水",
              "speech":"我来指导你倒一杯水。"
            }
            """);
        ai.textResponses.add("""
            [
              {"step_id":1,"instruction":"找到杯子","items":["杯子"],"completed":false},
              {"step_id":2,"instruction":"把杯口对准出水口","items":["杯子"],"completed":false}
            ]
            """);
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );
        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        ai.transcript = "这一步完成了";
        ai.textResponses.add("""
            {"thinking":"误判","intent":"micro_nav","target":"杯口","speech":"请对准杯口"}
            """);
        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        JSONObject taskUpdate = null;
        for (JSONObject message : sink.messages) {
            if ("task_update".equals(message.optString("type"))) taskUpdate = message;
        }
        assertThat(taskUpdate, notNullValue());
        assertThat(taskUpdate.optInt("current_step_index"), equalTo(1));
    }

    @Test
    public void taskInquiryCreatesTaskPlanAndAnnouncesFirstStep() {
        TestFakes.AiClient ai = new TestFakes.AiClient();
        ai.transcript = "帮我拿杯子";
        ai.visionResponses.add("""
            {
              "thinking":"用户需要任务计划",
              "intent":"task",
              "task_name":"拿杯子",
              "speech":"开始任务"
            }
            """);
        ai.textResponses.add("""
            [
              {"step_id":1,"instruction":"找到杯子","items":["杯子"],"completed":false},
              {"step_id":2,"instruction":"伸手拿起杯子","items":["杯子"],"completed":false}
            ]
            """);
        TestFakes.Sink sink = new TestFakes.Sink();
        SilverCareProcessor processor = new SilverCareProcessor(
            ai,
            new MemoryStore(new TestFakes.Preferences()),
            sink
        );

        processor.processInquiry("data:image/png;base64,test", "data:audio/webm;base64,test");

        JSONObject taskUpdate = sink.firstOfType("task_update");
        JSONObject inquiry = sink.firstOfType("inquiry_result");
        JSONObject speak = sink.firstOfType("speak");
        assertThat(taskUpdate, notNullValue());
        assertThat(taskUpdate.optString("mode"), equalTo("task"));
        assertThat(inquiry.optString("mode"), equalTo("task"));
        assertThat(speak.optString("text"), containsString("第一步：找到杯子"));
    }

    private static int countMessages(TestFakes.Sink sink, String type) {
        int count = 0;
        for (JSONObject message : sink.messages) {
            if (type.equals(message.optString("type"))) count += 1;
        }
        return count;
    }

    private static JSONObject lastOfType(TestFakes.Sink sink, String type) {
        JSONObject found = null;
        for (JSONObject message : sink.messages) {
            if (type.equals(message.optString("type"))) found = message;
        }
        return found;
    }

    private static void addNavigationResponse(TestFakes.AiClient ai, String subject, String speech) {
        ai.visionResponses.add("""
            {
              "thinking":"根据当前画面继续寻找目标",
              "priority":"high",
              "category":"target",
              "subject":"%s",
              "distance":1.2,
              "direction":"left",
              "target_detected":true,
              "speech":"%s",
              "scene_description":"目标已经出现在画面中",
              "objects":[{"name":"%s","distance":1.2,"direction":"left"}]
            }
            """.formatted(subject, speech, subject));
    }
}
