package com.silvercare.aiassistant;

import org.json.JSONObject;
import org.junit.Test;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;

public class OfflineVisionInterpreterTest {
    @Test
    public void findsRequestedObjectDirectionFromDetectorBoxes() throws Exception {
        String result = OfflineVisionInterpreter.interpret(
            "Current task: 正在寻找：狗\n",
            """
            {
              "image_width": 640,
              "image_height": 480,
              "detections": [
                {"class":"dog","score":0.88,"box":[40,170,230,455]},
                {"class":"bicycle","score":0.77,"box":[260,130,620,410]}
              ]
            }
            """,
            "detector"
        );

        JSONObject json = new JSONObject(result);
        assertThat(json.optBoolean("target_detected"), equalTo(true));
        assertThat(json.optString("subject"), equalTo("狗"));
        assertThat(json.optString("direction"), equalTo("left"));
        assertThat(json.optString("speech"), containsString("狗在左侧"));
    }

    @Test
    public void producesObstacleNavigationFromLargestAheadObject() throws Exception {
        String result = OfflineVisionInterpreter.interpret(
            "Current task: 通用导航\n",
            """
            {
              "image_width": 640,
              "image_height": 480,
              "detections": [
                {"class":"chair","score":0.91,"box":[210,170,430,470]},
                {"class":"cup","score":0.80,"box":[20,220,80,310]}
              ]
            }
            """,
            "detector"
        );

        JSONObject json = new JSONObject(result);
        assertThat(json.optString("category"), equalTo("hazard"));
        assertThat(json.optString("subject"), equalTo("中型障碍"));
        assertThat(json.optString("direction"), equalTo("ahead"));
        assertThat(json.optString("speech"), containsString("前方约"));
        assertThat(json.optString("speech"), containsString("中型障碍"));
    }

    @Test
    public void normalizesBowlSearchFromPhoneticTarget() throws Exception {
        String result = OfflineVisionInterpreter.interpret(
            "Current task: 正在寻找：晚\n",
            """
            {
              "image_width": 640,
              "image_height": 480,
              "detections": [
                {"class":"bowl","score":0.86,"box":[240,210,420,380]}
              ]
            }
            """,
            "detector"
        );

        JSONObject json = new JSONObject(result);
        assertThat(json.optBoolean("target_detected"), equalTo(true));
        assertThat(json.optString("subject"), equalTo("碗"));
        assertThat(json.optString("speech"), containsString("碗在"));
        assertThat(json.getJSONArray("objects").getJSONObject(0).optString("name"), equalTo("碗"));
    }

    @Test
    public void localizesEnglishDetectorLabelsForDisplay() throws Exception {
        String result = OfflineVisionInterpreter.interpret(
            "Current task: 通用导航\n",
            """
            {
              "image_width": 640,
              "image_height": 480,
              "detections": [
                {"class":"remote","score":0.81,"box":[250,250,390,360]}
              ]
            }
            """,
            "detector"
        );

        JSONObject object = new JSONObject(result).getJSONArray("objects").getJSONObject(0);
        assertThat(object.optString("name"), equalTo("遥控器"));
        assertThat(object.optString("category"), equalTo("遥控器"));
    }

    @Test
    public void missingSearchTargetAsksUserToRotateAndRefresh() throws Exception {
        String result = OfflineVisionInterpreter.interpret(
            "Current task: 正在寻找：药盒\n",
            """
            {
              "image_width": 640,
              "image_height": 480,
              "detections": [
                {"class":"chair","score":0.82,"box":[240,210,420,380]}
              ]
            }
            """,
            "detector"
        );

        JSONObject json = new JSONObject(result);
        assertThat(json.optBoolean("target_detected"), equalTo(false));
        assertThat(json.optString("direction"), equalTo("unknown"));
        assertThat(json.optString("priority"), equalTo("low"));
        assertThat(json.optString("speech"), containsString("左右缓慢转动手机"));
        assertThat(json.optString("speech"), containsString("点击刷新"));
    }

    @Test
    public void microPromptReturnsVectorGuidance() throws Exception {
        String result = OfflineVisionInterpreter.interpret(
            "You are 多模态长护精确引导模式\nTarget: 杯子\n",
            """
            {
              "image_width": 640,
              "image_height": 480,
              "detections": [
                {"class":"cup","score":0.82,"box":[430,220,520,360]}
              ]
            }
            """,
            "detector"
        );

        JSONObject json = new JSONObject(result);
        assertThat(json.optString("action"), equalTo("move"));
        assertThat(json.optInt("x") > 0, equalTo(true));
        assertThat(json.optString("guidance_speech"), containsString("向右"));
    }
}
