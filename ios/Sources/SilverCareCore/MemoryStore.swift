import Foundation

public final class SilverCareMemoryStore {
    private struct ObjectHistoryEntry {
        let name: String
        let location: String
        let scene: String
        let timestamp: Date
    }

    private static let maxHistoryCount = 100
    private static let dedupeWindowSeconds: TimeInterval = 10

    private var locations: [String: String]
    private var objectLocations: [String: String]
    private var objectHistory: [ObjectHistoryEntry]

    public init(
        locations: [String: String] = [:],
        objectLocations: [String: String] = [:],
        objectHistory: [String] = []
    ) {
        self.locations = locations
        self.objectLocations = objectLocations
        self.objectHistory = objectHistory.map { entry in
            let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
            return ObjectHistoryEntry(
                name: parts.first ?? entry,
                location: "",
                scene: parts.dropFirst().first ?? entry,
                timestamp: Date()
            )
        }
    }

    public func addLocation(_ name: String, description: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        locations[cleanName] = description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func logObject(_ object: String, locationTag: String, scene: String) {
        let cleanObject = object.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanObject.isEmpty else { return }
        let cleanLocation = locationTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanScene = scene.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = objectHistory.last,
           last.name == cleanObject,
           Date().timeIntervalSince(last.timestamp) < Self.dedupeWindowSeconds {
            return
        }

        if !cleanLocation.isEmpty {
            if !cleanScene.isEmpty {
                objectLocations[cleanObject] = "\(cleanObject)在\(cleanLocation)，\(cleanScene)"
            } else {
                objectLocations[cleanObject] = "\(cleanObject)在\(cleanLocation)"
            }
        } else if !cleanScene.isEmpty {
            objectLocations[cleanObject] = "\(cleanObject)最近出现在：\(cleanScene)。"
        }

        objectHistory.append(ObjectHistoryEntry(
            name: cleanObject,
            location: cleanLocation,
            scene: cleanScene,
            timestamp: Date()
        ))
        if objectHistory.count > Self.maxHistoryCount {
            objectHistory.removeFirst(objectHistory.count - Self.maxHistoryCount)
        }
    }

    public func findObjectLocation(_ object: String) -> String {
        let clean = object.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }
        if let entry = objectHistory.reversed().first(where: { history in
            history.name.contains(clean) || clean.contains(history.name)
        }) {
            if !entry.location.isEmpty && !entry.scene.isEmpty {
                return "\(entry.name)在\(entry.location)，\(entry.scene)"
            }
            if !entry.location.isEmpty {
                return "\(entry.name)在\(entry.location)"
            }
            if !entry.scene.isEmpty {
                return "\(entry.name)最近出现在：\(entry.scene)"
            }
            return "\(entry.name)最近被看见过，但没有明确位置。"
        }
        if let exact = objectLocations[clean] {
            return exact
        }
        if let fuzzy = objectLocations.first(where: { $0.key.contains(clean) || clean.contains($0.key) }) {
            return fuzzy.value
        }
        return ""
    }

    public func historyContext() -> String {
        guard !objectHistory.isEmpty else { return "还没有记录过物体历史。" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return objectHistory
            .suffix(30)
            .map { entry in
                var line = "[\(formatter.string(from: entry.timestamp))] 看到 \(entry.name)"
                if !entry.location.isEmpty {
                    line += " 在“\(entry.location)”"
                }
                if !entry.scene.isEmpty {
                    line += "（\(entry.scene)）"
                }
                return line
            }
            .joined(separator: "\n")
    }

    public func locationSummary() -> String {
        guard !locations.isEmpty else { return "还没有标记过的地点。" }
        return locations
            .sorted { $0.key < $1.key }
            .map { "“\($0.key)”：\($0.value)" }
            .joined(separator: "，")
    }
}
