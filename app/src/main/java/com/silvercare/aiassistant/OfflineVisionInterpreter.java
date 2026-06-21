package com.silvercare.aiassistant;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

final class OfflineVisionInterpreter {
    private static final double DEFAULT_IMAGE_WIDTH = 640.0;
    private static final double DEFAULT_IMAGE_HEIGHT = 480.0;
    private static final double MIN_SCORE = 0.25;

    private static final Map<String, String> ZH_NAMES = new LinkedHashMap<>();
    private static final Map<String, String> DISPLAY_ONLY_NAMES = new HashMap<>();
    private static final Map<String, String[]> TARGET_ALIASES = new HashMap<>();

    static {
        putName("person", "人");
        putName("bicycle", "自行车");
        putName("car", "汽车");
        putName("motorcycle", "摩托车");
        putName("airplane", "飞机");
        putName("bus", "公交车");
        putName("train", "火车");
        putName("truck", "卡车");
        putName("boat", "船");
        putName("traffic light", "红绿灯");
        putName("fire hydrant", "消防栓");
        putName("stop sign", "停止标志");
        putName("parking meter", "停车计时器");
        putName("bench", "长椅");
        putName("bird", "鸟");
        putName("cat", "猫");
        putName("dog", "狗");
        putName("horse", "马");
        putName("sheep", "羊");
        putName("cow", "牛");
        putName("elephant", "大象");
        putName("bear", "熊");
        putName("zebra", "斑马");
        putName("giraffe", "长颈鹿");
        putName("backpack", "背包");
        putName("umbrella", "雨伞");
        putName("handbag", "手提包");
        putName("tie", "领带");
        putName("suitcase", "行李箱");
        putName("frisbee", "飞盘");
        putName("skis", "滑雪板");
        putName("snowboard", "单板滑雪板");
        putName("sports ball", "球");
        putName("kite", "风筝");
        putName("baseball bat", "棒球棒");
        putName("baseball glove", "棒球手套");
        putName("skateboard", "滑板");
        putName("surfboard", "冲浪板");
        putName("tennis racket", "网球拍");
        putName("bottle", "瓶子");
        putName("wine glass", "酒杯");
        putName("cup", "杯子");
        putName("fork", "叉子");
        putName("knife", "刀");
        putName("spoon", "勺子");
        putName("bowl", "碗");
        putName("banana", "香蕉");
        putName("apple", "苹果");
        putName("sandwich", "三明治");
        putName("orange", "橙子");
        putName("broccoli", "西兰花");
        putName("carrot", "胡萝卜");
        putName("hot dog", "热狗");
        putName("pizza", "披萨");
        putName("donut", "甜甜圈");
        putName("cake", "蛋糕");
        putName("chair", "椅子");
        putName("couch", "沙发");
        putName("sofa", "沙发");
        putName("potted plant", "盆栽");
        putName("bed", "床");
        putName("dining table", "桌子");
        putName("table", "桌子");
        putName("toilet", "马桶");
        putName("tv", "电视");
        putName("tvmonitor", "电视");
        putName("laptop", "笔记本电脑");
        putName("mouse", "鼠标");
        putName("remote", "遥控器");
        putName("keyboard", "键盘");
        putName("cell phone", "手机");
        putName("microwave", "微波炉");
        putName("oven", "烤箱");
        putName("toaster", "烤面包机");
        putName("sink", "水槽");
        putName("refrigerator", "冰箱");
        putName("book", "书");
        putName("clock", "时钟");
        putName("vase", "花瓶");
        putName("scissors", "剪刀");
        putName("teddy bear", "玩具熊");
        putName("hair drier", "吹风机");
        putName("toothbrush", "牙刷");

        alias("杯子", "cup", "mug", "水杯");
        alias("水杯", "cup", "mug", "杯子");
        alias("碗", "bowl", "饭碗", "晚");
        alias("饭碗", "bowl", "碗", "晚");
        alias("晚", "bowl", "碗", "饭碗");
        alias("碟子", "bowl");
        alias("盘子", "bowl");
        alias("手机", "cell phone", "phone");
        alias("椅子", "chair");
        alias("桌子", "dining table", "table");
        alias("人", "person");
        alias("狗", "dog");
        alias("猫", "cat");
        alias("车", "car", "truck", "bus");
        alias("汽车", "car");
        alias("自行车", "bicycle");
        alias("背包", "backpack");
        alias("包", "backpack", "handbag");
        alias("行李箱", "suitcase");
        alias("遥控器", "remote");
        alias("电视", "tv", "tvmonitor");
        alias("马桶", "toilet");
        alias("水槽", "sink");
        alias("冰箱", "refrigerator");
        alias("瓶子", "bottle");
        alias("书", "book");
        alias("床", "bed");
        alias("沙发", "couch", "sofa");

        displayName("door", "门");
        displayName("mat", "地垫");
        displayName("rug", "地毯");
        displayName("shoe", "鞋子");
        displayName("slipper", "拖鞋");
        displayName("box", "箱子");
        displayName("carton", "纸箱");
        displayName("cable", "电线");
        displayName("wire", "电线");
        displayName("power strip", "插排");
        displayName("socket", "插座");
        displayName("outlet", "插座");
        displayName("stairs", "楼梯");
        displayName("stair", "台阶");
        displayName("wall", "墙");
        displayName("floor", "地面");
        displayName("cabinet", "柜子");
        displayName("wardrobe", "衣柜");
        displayName("mirror", "镜子");
        displayName("lamp", "灯");
        displayName("light", "灯");
        displayName("trash bin", "垃圾桶");
        displayName("trash can", "垃圾桶");
    }

    private OfflineVisionInterpreter() {
    }

    static String interpret(String prompt, String rawJson, String role) throws Exception {
        JSONObject raw = parseObject(rawJson);
        if (looksHighLevel(raw)) return raw.toString();

        JSONArray rawDetections = raw.optJSONArray("detections");
        if (rawDetections == null) rawDetections = raw.optJSONArray("objects");
        if (rawDetections == null) rawDetections = new JSONArray();

        double imageWidth = raw.optDouble("image_width", DEFAULT_IMAGE_WIDTH);
        double imageHeight = raw.optDouble("image_height", DEFAULT_IMAGE_HEIGHT);
        List<Detection> detections = detectionsFrom(rawDetections, imageWidth, imageHeight);

        String target = extractTarget(prompt);
        if (isMicroRole(role, prompt)) {
            return microResult(target, detections).toString();
        }
        return navigationOrSearchResult(target, detections).toString();
    }

    private static boolean looksHighLevel(JSONObject raw) {
        return raw.has("priority")
            || raw.has("target_detected")
            || raw.has("guidance_speech")
            || raw.has("step_completed");
    }

    private static JSONObject navigationOrSearchResult(String target, List<Detection> detections) throws Exception {
        JSONArray objects = new JSONArray();
        for (Detection detection : detections) {
            objects.put(detection.toObject());
        }

        Detection targetHit = target == null ? null : bestTarget(target, detections);
        if (target != null) {
            if (targetHit == null) {
                return new JSONObject()
                    .put("thinking", "离线 DAMO-YOLO 未检测到目标类别。")
                    .put("target_detected", false)
                    .put("priority", "low")
                    .put("category", "target")
                    .put("subject", target)
                    .put("distance", 0)
                    .put("direction", "unknown")
                    .put("confidence_score", 0)
                    .put("speech", "还没有找到" + target + "。请缓慢转动手机继续扫描。")
                    .put("scene_description", "离线检测到 " + detections.size() + " 个物体。")
                    .put("objects", objects);
            }
            return new JSONObject()
                .put("thinking", "离线 DAMO-YOLO 检测到目标。")
                .put("target_detected", true)
                .put("priority", "high")
                .put("category", "target")
                .put("subject", targetHit.zhName)
                .put("distance", targetHit.distance)
                .put("direction", targetHit.direction)
                .put("confidence_score", Math.round(targetHit.score * 100))
                .put("speech", targetHit.zhName + "在" + directionZh(targetHit.direction)
                    + "，距离约" + formatDistance(targetHit.distance) + "。")
                .put("scene_description", "离线检测到目标 " + targetHit.zhName + "。")
                .put("objects", objects);
        }

        Detection hazard = bestHazard(detections);
        if (hazard == null) {
            return new JSONObject()
                .put("thinking", "离线检测未发现明显障碍物。")
                .put("target_detected", false)
                .put("priority", "low")
                .put("category", "navigation")
                .put("subject", "通行空间")
                .put("distance", 3.0)
                .put("direction", "ahead")
                .put("confidence_score", 70)
                .put("speech", "前方未检测到明显障碍，请保持慢速直行。")
                .put("scene_description", "离线检测未发现明显障碍物。")
                .put("objects", objects);
        }

        String obstacle = obstacleSizeName(hazard);
        String priority = hazard.distance <= 0.9 && "ahead".equals(hazard.direction) ? "critical"
            : hazard.distance <= 1.5 && "ahead".equals(hazard.direction) ? "high"
            : "medium";
        String speech = "ahead".equals(hazard.direction)
            ? "前方约" + formatDistance(hazard.distance) + "有" + obstacle + "，请放慢并向侧方绕开。"
            : directionZh(hazard.direction) + "约" + formatDistance(hazard.distance) + "有" + obstacle + "，请注意避让。";
        if ("critical".equals(priority)) speech = "停下，" + speech;

        return new JSONObject()
            .put("thinking", "离线 DAMO-YOLO 将最大且靠近画面下方的物体作为主要避障目标。")
            .put("target_detected", false)
            .put("priority", priority)
            .put("category", "hazard")
            .put("subject", obstacle)
            .put("distance", hazard.distance)
            .put("direction", hazard.direction)
            .put("confidence_score", Math.round(hazard.score * 100))
            .put("speech", speech)
            .put("scene_description", "离线检测到主要通行障碍：" + obstacle + "。")
            .put("objects", objects);
    }

    private static JSONObject microResult(String target, List<Detection> detections) throws Exception {
        Detection hit = target == null ? null : bestTarget(target, detections);
        if (hit == null) {
            return new JSONObject()
                .put("x", 0)
                .put("y", 0)
                .put("action", "move")
                .put("guidance_speech", target == null ? "请说出要找的目标。" : "未找到" + target + "，请缓慢移动手机。");
        }

        String action = Math.abs(hit.xVector) <= 12 && Math.abs(hit.yVector) <= 12 ? "stop" : "move";
        String speech;
        if ("stop".equals(action)) {
            speech = "目标在正中。";
        } else if (Math.abs(hit.xVector) > Math.abs(hit.yVector)) {
            speech = hit.xVector < 0 ? "向左一点。" : "向右一点。";
        } else {
            speech = hit.yVector < 0 ? "向下一点。" : "向上一点。";
        }
        return new JSONObject()
            .put("x", hit.xVector)
            .put("y", hit.yVector)
            .put("action", action)
            .put("guidance_speech", speech);
    }

    private static List<Detection> detectionsFrom(JSONArray raw, double imageWidth, double imageHeight) {
        List<Detection> detections = new ArrayList<>();
        for (int i = 0; i < raw.length(); i += 1) {
            JSONObject item = raw.optJSONObject(i);
            if (item == null) continue;
            Detection detection = Detection.from(item, imageWidth, imageHeight);
            if (detection != null && detection.score >= MIN_SCORE) detections.add(detection);
        }
        detections.sort(Comparator.comparingDouble((Detection d) -> d.score).reversed());
        return detections;
    }

    private static Detection bestTarget(String target, List<Detection> detections) {
        String normalizedTarget = normalize(target);
        String[] aliases = TARGET_ALIASES.getOrDefault(normalizedTarget, new String[] { normalizedTarget });
        for (Detection detection : detections) {
            for (String alias : aliases) {
                if (detection.matches(alias)) return detection;
            }
        }
        return null;
    }

    static boolean isSupportedSearchTarget(String target) {
        return !canonicalSearchTarget(target).isEmpty();
    }

    static String canonicalSearchTarget(String target) {
        String normalized = normalize(target);
        if (normalized.isEmpty()) return "";
        String[] aliases = TARGET_ALIASES.get(normalized);
        if (aliases != null && aliases.length > 0) {
            String label = firstDetectorLabel(aliases);
            return zhName(label);
        }
        for (Map.Entry<String, String> entry : ZH_NAMES.entrySet()) {
            String label = entry.getKey();
            String zh = entry.getValue();
            if (normalize(label).equals(normalized) || normalize(zh).equals(normalized)) {
                return zh;
            }
        }
        return "";
    }

    static String supportedSearchTargetList() {
        ArrayList<String> names = new ArrayList<>();
        for (String zh : ZH_NAMES.values()) {
            if (!names.contains(zh)) names.add(zh);
        }
        return String.join("、", names);
    }

    static String localizeObjectName(String value) {
        String localized = zhName(value);
        return localized == null || localized.trim().isEmpty() ? "物体" : localized;
    }

    private static String firstDetectorLabel(String[] aliases) {
        for (String alias : aliases) {
            String normalized = normalize(alias);
            if (ZH_NAMES.containsKey(normalized)) return normalized;
        }
        return aliases[0];
    }

    private static Detection bestHazard(List<Detection> detections) {
        return detections.stream()
            .max(Comparator.comparingDouble(Detection::hazardScore))
            .orElse(null);
    }

    private static boolean isMicroRole(String role, String prompt) {
        return "micro".equals(role) || (prompt != null && prompt.contains("多模态长护精确引导模式"));
    }

    private static String extractTarget(String prompt) {
        if (prompt == null) return null;
        String value = between(prompt, "正在寻找：", "\n");
        if (value == null) value = between(prompt, "Target:", "\n");
        if (value == null) value = between(prompt, "用户正在找“", "”");
        if (value == null) return null;
        value = value.trim();
        if (value.isEmpty() || "通用导航".equals(value)) return null;
        return value;
    }

    private static String between(String text, String startToken, String endToken) {
        int start = text.indexOf(startToken);
        if (start < 0) return null;
        start += startToken.length();
        int end = text.indexOf(endToken, start);
        if (end < 0) end = text.length();
        return text.substring(start, end);
    }

    private static JSONObject parseObject(String rawJson) throws Exception {
        String text = rawJson == null ? "" : rawJson.trim();
        if (text.startsWith("[")) {
            return new JSONObject().put("detections", new JSONArray(text));
        }
        return new JSONObject(text);
    }

    private static void putName(String label, String zh) {
        String normalizedLabel = normalize(label);
        ZH_NAMES.put(normalizedLabel, zh);
        TARGET_ALIASES.putIfAbsent(normalize(zh), new String[] { normalizedLabel });
    }

    private static void alias(String target, String... labels) {
        TARGET_ALIASES.put(normalize(target), labels);
    }

    private static void displayName(String label, String zh) {
        DISPLAY_ONLY_NAMES.put(normalize(label), zh);
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim().toLowerCase(Locale.US).replace('_', ' ');
    }

    private static boolean hasAsciiLetter(String value) {
        if (value == null) return false;
        for (int index = 0; index < value.length(); index += 1) {
            char ch = value.charAt(index);
            if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) return true;
        }
        return false;
    }

    private static String zhName(String label) {
        String normalized = normalize(label);
        String zh = ZH_NAMES.get(normalized);
        if (zh != null) return zh;
        String displayOnly = DISPLAY_ONLY_NAMES.get(normalized);
        if (displayOnly != null) return displayOnly;
        if (hasAsciiLetter(label)) return "物体";
        return label == null || label.isEmpty() ? "物体" : label;
    }

    private static String directionZh(String direction) {
        if ("left".equals(direction)) return "左侧";
        if ("right".equals(direction)) return "右侧";
        if ("ahead".equals(direction)) return "正前方";
        return "附近";
    }

    private static String directionFrom(double centerX) {
        if (centerX < 0.42) return "left";
        if (centerX > 0.58) return "right";
        return "ahead";
    }

    private static double approximateDistance(double areaRatio) {
        if (areaRatio >= 0.35) return 0.6;
        if (areaRatio >= 0.22) return 0.9;
        if (areaRatio >= 0.12) return 1.3;
        if (areaRatio >= 0.06) return 2.0;
        return 3.5;
    }

    private static String obstacleSizeName(Detection detection) {
        if (detection.areaRatio >= 0.22 || detection.distance <= 0.9) return "大型障碍";
        if (detection.areaRatio >= 0.08 || detection.distance <= 1.6) return "中型障碍";
        return "小型障碍";
    }

    private static String formatDistance(double meters) {
        if (meters < 1.0) return Math.round(meters * 100) + "厘米";
        return String.format(Locale.US, "%.1f米", meters);
    }

    private static final class Detection {
        final String label;
        final String normalizedLabel;
        final String zhName;
        final double score;
        final double x1;
        final double y1;
        final double x2;
        final double y2;
        final double centerX;
        final double centerY;
        final double areaRatio;
        final String direction;
        final double distance;
        final int xVector;
        final int yVector;

        private Detection(String label, double score, double x1, double y1, double x2, double y2, double imageWidth, double imageHeight) {
            this.label = label;
            this.normalizedLabel = normalize(label);
            this.zhName = zhName(label);
            this.score = score;
            this.x1 = x1;
            this.y1 = y1;
            this.x2 = x2;
            this.y2 = y2;
            this.centerX = clamp(((x1 + x2) / 2.0) / imageWidth);
            this.centerY = clamp(((y1 + y2) / 2.0) / imageHeight);
            this.areaRatio = Math.max(0.0, (x2 - x1) * (y2 - y1)) / Math.max(1.0, imageWidth * imageHeight);
            this.direction = directionFrom(centerX);
            this.distance = approximateDistance(areaRatio);
            this.xVector = (int) Math.round((centerX - 0.5) * 200.0);
            this.yVector = (int) Math.round((0.5 - centerY) * 200.0);
        }

        static Detection from(JSONObject item, double imageWidth, double imageHeight) {
            String label = item.optString("class", item.optString("label", item.optString("name", "")));
            double score = item.optDouble("score", item.optDouble("confidence_score", 0.0));
            JSONArray box = item.optJSONArray("box");
            if (box == null) box = item.optJSONArray("bbox");
            if (label.isEmpty() || box == null || box.length() < 4) return null;
            return new Detection(
                label,
                score,
                box.optDouble(0),
                box.optDouble(1),
                box.optDouble(2),
                box.optDouble(3),
                item.optDouble("image_width", imageWidth),
                item.optDouble("image_height", imageHeight)
            );
        }

        boolean matches(String alias) {
            String normalizedAlias = normalize(alias);
            return normalizedLabel.equals(normalizedAlias) || normalize(zhName).equals(normalizedAlias);
        }

        double hazardScore() {
            double aheadBoost = "ahead".equals(direction) ? 1.7 : 1.0;
            double lowerFrameBoost = centerY > 0.55 ? 1.35 : 1.0;
            return score * areaRatio * aheadBoost * lowerFrameBoost;
        }

        JSONObject toObject() throws Exception {
            return new JSONObject()
                .put("name", zhName)
                .put("category", zhName)
                .put("distance", distance)
                .put("direction", direction)
                .put("confidence_score", Math.round(score * 100))
                .put("risk_level", riskLevel());
        }

        private String riskLevel() {
            if ("ahead".equals(direction) && distance <= 1.0) return "high";
            if (distance <= 1.5) return "med";
            return "low";
        }

        private static double clamp(double value) {
            return Math.max(0.0, Math.min(1.0, value));
        }
    }
}
