import Foundation

public enum OfflineVisionInterpreter {
    private static let defaultImageWidth = 640.0
    private static let defaultImageHeight = 480.0
    private static let minimumScore = 0.25

    private static let zhNames: [String: String] = [
        "person": "人",
        "dog": "狗",
        "cat": "猫",
        "cup": "杯子",
        "mug": "杯子",
        "bowl": "碗",
        "cell phone": "手机",
        "phone": "手机",
        "chair": "椅子",
        "dining table": "桌子",
        "table": "桌子",
        "suitcase": "行李箱",
        "backpack": "背包",
        "handbag": "手提包",
        "bottle": "瓶子",
        "bed": "床",
        "couch": "沙发",
        "sofa": "沙发",
        "remote": "遥控器",
        "tv": "电视",
        "tvmonitor": "电视",
        "toilet": "马桶",
        "sink": "水槽",
        "refrigerator": "冰箱",
        "book": "书",
        "car": "汽车",
        "truck": "卡车",
        "bus": "公交车",
        "bicycle": "自行车"
    ]

    private static let displayOnlyNames: [String: String] = [
        "door": "门",
        "mat": "地垫",
        "rug": "地毯",
        "shoe": "鞋子",
        "slipper": "拖鞋",
        "box": "箱子",
        "cable": "电线",
        "wire": "电线",
        "power strip": "插排",
        "socket": "插座",
        "outlet": "插座",
        "stairs": "楼梯",
        "wall": "墙",
        "floor": "地面",
        "cabinet": "柜子",
        "mirror": "镜子",
        "lamp": "灯",
        "light": "灯",
        "trash bin": "垃圾桶"
    ]

    private static let aliases: [String: [String]] = [
        "杯子": ["cup", "mug", "水杯", "杯子"],
        "水杯": ["cup", "mug", "水杯", "杯子"],
        "碗": ["bowl", "饭碗", "晚", "碗"],
        "饭碗": ["bowl", "饭碗", "晚", "碗"],
        "手机": ["cell phone", "phone", "手机"],
        "椅子": ["chair", "椅子"],
        "桌子": ["dining table", "table", "桌子"],
        "人": ["person", "人"],
        "狗": ["dog", "狗"],
        "猫": ["cat", "猫"],
        "行李箱": ["suitcase", "行李箱"],
        "背包": ["backpack", "背包"],
        "包": ["backpack", "handbag", "包"],
        "遥控器": ["remote", "遥控器"],
        "电视": ["tv", "tvmonitor", "电视"],
        "马桶": ["toilet", "马桶"],
        "水槽": ["sink", "水槽"],
        "冰箱": ["refrigerator", "冰箱"],
        "瓶子": ["bottle", "瓶子"],
        "书": ["book", "书"],
        "床": ["bed", "床"],
        "沙发": ["couch", "sofa", "沙发"]
    ]

    private static let canonicalSearchTargetOrder = [
        "杯子", "水杯", "碗", "饭碗", "手机", "椅子", "桌子",
        "人", "狗", "猫", "行李箱", "背包", "包", "遥控器",
        "电视", "马桶", "水槽", "冰箱", "瓶子", "书", "床", "沙发"
    ]

    public static func interpret(prompt: String, rawJSON: String, role: String) throws -> String {
        let raw = try JSONSupport.object(from: rawJSON)
        if looksHighLevel(raw) {
            return try JSONSupport.string(from: raw)
        }

        let rawDetections = raw["detections"] as? [[String: Any]]
            ?? raw["objects"] as? [[String: Any]]
            ?? []
        let imageWidth = raw.double("image_width", default: defaultImageWidth)
        let imageHeight = raw.double("image_height", default: defaultImageHeight)
        let detections = rawDetections
            .compactMap { Detection(raw: $0, imageWidth: imageWidth, imageHeight: imageHeight) }
            .filter { $0.score >= minimumScore }
            .sorted { $0.score > $1.score }

        let target = extractTarget(from: prompt)
        let output = isMicroRole(role: role, prompt: prompt)
            ? microResult(target: target, detections: detections)
            : navigationOrSearchResult(target: target, detections: detections)
        return try JSONSupport.string(from: output)
    }

    public static func isSupportedSearchTarget(_ target: String) -> Bool {
        !canonicalSearchTarget(target).isEmpty
    }

    public static func canonicalSearchTarget(_ target: String) -> String {
        let normalized = normalize(target)
        guard !normalized.isEmpty else { return "" }
        for key in canonicalSearchTargetOrder where normalize(key) == normalized {
            return key
        }
        for key in canonicalSearchTargetOrder {
            guard let values = aliases[key] else { continue }
            if values.map(normalize).contains(normalized) {
                return key
            }
        }
        for (key, values) in aliases where values.map(normalize).contains(normalized) {
            return key
        }
        return ""
    }

    public static func supportedSearchTargetList() -> String {
        canonicalSearchTargetOrder.joined(separator: "、")
    }

    public static func localizeObjectName(_ name: String) -> String {
        let normalized = normalize(name)
        return zhNames[normalized] ?? displayOnlyNames[normalized] ?? name
    }

    private static func looksHighLevel(_ raw: [String: Any]) -> Bool {
        raw["priority"] != nil
            || raw["target_detected"] != nil
            || raw["guidance_speech"] != nil
            || raw["step_completed"] != nil
    }

    private static func navigationOrSearchResult(target: String?, detections: [Detection]) -> [String: Any] {
        let objects = detections.map { $0.object }
        if let target {
            guard let hit = bestTarget(target, detections: detections) else {
                return [
                    "thinking": "离线 DAMO-YOLO 未检测到目标类别。",
                    "target_detected": false,
                    "priority": "low",
                    "category": "target",
                    "subject": target,
                    "distance": 0,
                    "direction": "unknown",
                    "confidence_score": 0,
                    "speech": "画面里还没有找到\(target)。请左右缓慢转动手机，然后点击刷新。",
                    "scene_description": "离线检测到 \(detections.count) 个物体。",
                    "objects": objects
                ]
            }
            return [
                "thinking": "离线 DAMO-YOLO 检测到目标。",
                "target_detected": true,
                "priority": "high",
                "category": "target",
                "subject": hit.zhName,
                "distance": hit.distance,
                "direction": hit.direction,
                "confidence_score": Int((hit.score * 100).rounded()),
                "speech": "\(hit.zhName)在\(directionZH(hit.direction))，距离约\(formatDistance(hit.distance))。",
                "scene_description": "离线检测到目标 \(hit.zhName)。",
                "objects": objects
            ]
        }

        guard let hazard = bestHazard(detections) else {
            return [
                "thinking": "离线检测未发现明显障碍物。",
                "target_detected": false,
                "priority": "low",
                "category": "navigation",
                "subject": "通行空间",
                "distance": 3.0,
                "direction": "ahead",
                "confidence_score": 70,
                "speech": "前方未检测到明显障碍，请保持慢速直行。",
                "scene_description": "离线检测未发现明显障碍物。",
                "objects": objects
            ]
        }

        let obstacle = obstacleSizeName(hazard)
        let priority: String
        if hazard.distance <= 0.9 && hazard.direction == "ahead" {
            priority = "critical"
        } else if hazard.distance <= 1.5 && hazard.direction == "ahead" {
            priority = "high"
        } else {
            priority = "medium"
        }

        var speech = hazard.direction == "ahead"
            ? "前方约\(formatDistance(hazard.distance))有\(obstacle)，请放慢并向侧方绕开。"
            : "\(directionZH(hazard.direction))约\(formatDistance(hazard.distance))有\(obstacle)，请注意避让。"
        if priority == "critical" {
            speech = "停下，\(speech)"
        }

        return [
            "thinking": "离线 DAMO-YOLO 将最大且靠近画面下方的物体作为主要避障目标。",
            "target_detected": false,
            "priority": priority,
            "category": "hazard",
            "subject": obstacle,
            "distance": hazard.distance,
            "direction": hazard.direction,
            "confidence_score": Int((hazard.score * 100).rounded()),
            "speech": speech,
            "scene_description": "离线检测到主要通行障碍：\(obstacle)。",
            "objects": objects
        ]
    }

    private static func microResult(target: String?, detections: [Detection]) -> [String: Any] {
        guard let target, let hit = bestTarget(target, detections: detections) else {
            return [
                "x": 0,
                "y": 0,
                "action": "move",
                "guidance_speech": target == nil ? "请说出要找的目标。" : "画面里还没有找到\(target!)，请左右缓慢转动手机，然后点击刷新。"
            ]
        }

        let action = abs(hit.xVector) <= 12 && abs(hit.yVector) <= 12 ? "stop" : "move"
        let speech: String
        if action == "stop" {
            speech = "目标在正中。"
        } else if abs(hit.xVector) > abs(hit.yVector) {
            speech = hit.xVector < 0 ? "向左一点。" : "向右一点。"
        } else {
            speech = hit.yVector < 0 ? "向下一点。" : "向上一点。"
        }
        return ["x": hit.xVector, "y": hit.yVector, "action": action, "guidance_speech": speech]
    }

    private static func bestTarget(_ target: String, detections: [Detection]) -> Detection? {
        let canonicalTarget = canonicalSearchTarget(target)
        let normalizedTarget = normalize(canonicalTarget.isEmpty ? target : canonicalTarget)
        let searchAliases = aliases[normalizedTarget] ?? [normalizedTarget]
        return detections.first { detection in
            searchAliases.contains { detection.matches($0) }
        }
    }

    private static func bestHazard(_ detections: [Detection]) -> Detection? {
        detections.max { lhs, rhs in
            lhs.hazardScore < rhs.hazardScore
        }
    }

    private static func extractTarget(from prompt: String) -> String? {
        for marker in ["正在寻找：", "Target:"] {
            guard let range = prompt.range(of: marker) else { continue }
            let suffix = prompt[range.upperBound...]
            let line = suffix.split(whereSeparator: \.isNewline).first.map(String.init) ?? String(suffix)
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                let canonical = canonicalSearchTarget(clean)
                return canonical.isEmpty ? clean : canonical
            }
        }
        return nil
    }

    private static func isMicroRole(role: String, prompt: String) -> Bool {
        role.lowercased().contains("micro") || prompt.contains("精确引导")
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
    }

    private static func directionZH(_ direction: String) -> String {
        switch direction {
        case "left": return "左侧"
        case "right": return "右侧"
        case "behind": return "身后"
        case "ahead": return "正前方"
        default: return direction
        }
    }

    private static func obstacleSizeName(_ detection: Detection) -> String {
        if detection.areaRatio >= 0.32 || detection.distance <= 0.9 { return "大型障碍" }
        if detection.areaRatio >= 0.12 || detection.distance <= 1.8 { return "中型障碍" }
        return "小型障碍"
    }

    private static func formatDistance(_ meters: Double) -> String {
        if meters < 1.0 {
            return "\(Int((meters * 100).rounded()))厘米"
        }
        if meters < 10.0 {
            return String(format: "%.1f米", meters)
        }
        return "\(Int(meters.rounded()))米"
    }

    private struct Detection {
        let rawName: String
        let zhName: String
        let score: Double
        let x1: Double
        let y1: Double
        let x2: Double
        let y2: Double
        let imageWidth: Double
        let imageHeight: Double

        init?(raw: [String: Any], imageWidth: Double, imageHeight: Double) {
            let name = raw.string("class", default: raw.string("name", default: raw.string("label")))
            guard !name.isEmpty else { return nil }
            let score = raw.double("score", default: raw.double("confidence", default: 0))
            let box = raw["box"] as? [Any] ?? raw["bbox"] as? [Any] ?? []
            guard box.count >= 4 else { return nil }
            func number(_ index: Int) -> Double? {
                if let value = box[index] as? Double { return value }
                if let value = box[index] as? Int { return Double(value) }
                if let value = box[index] as? NSNumber { return value.doubleValue }
                return nil
            }
            guard
                let x1 = number(0),
                let y1 = number(1),
                let x2 = number(2),
                let y2 = number(3)
            else { return nil }
            self.rawName = name
            self.zhName = OfflineVisionInterpreter.localizeObjectName(name)
            self.score = score
            self.x1 = x1
            self.y1 = y1
            self.x2 = x2
            self.y2 = y2
            self.imageWidth = imageWidth
            self.imageHeight = imageHeight
        }

        var width: Double { max(1, x2 - x1) }
        var height: Double { max(1, y2 - y1) }
        var centerX: Double { (x1 + x2) / 2 }
        var centerY: Double { (y1 + y2) / 2 }
        var areaRatio: Double { (width * height) / max(1, imageWidth * imageHeight) }
        var xVector: Int { Int((((centerX / imageWidth) - 0.5) * 200).rounded()) }
        var yVector: Int { Int(((0.5 - (centerY / imageHeight)) * 200).rounded()) }

        var distance: Double {
            let size = max(areaRatio, 0.01)
            return max(0.45, min(4.0, 0.55 / sqrt(size)))
        }

        var direction: String {
            let third = imageWidth / 3
            if centerX < third { return "left" }
            if centerX > third * 2 { return "right" }
            return "ahead"
        }

        var hazardScore: Double {
            let lowerFrameWeight = centerY / max(1, imageHeight)
            return areaRatio * 2.2 + lowerFrameWeight * 0.7 + score * 0.2
        }

        var object: [String: Any] {
            [
                "name": zhName,
                "category": zhName,
                "distance": distance,
                "direction": direction,
                "confidence_score": Int((score * 100).rounded()),
                "risk_level": distance <= 1.2 ? "high" : "low"
            ]
        }

        func matches(_ alias: String) -> Bool {
            let normalized = OfflineVisionInterpreter.normalize(alias)
            return OfflineVisionInterpreter.normalize(rawName) == normalized
                || OfflineVisionInterpreter.normalize(zhName) == normalized
        }
    }
}
