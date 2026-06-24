import Foundation

enum JSONSupport {
    static func object(from text: String) throws -> [String: Any] {
        let value = try any(from: text)
        guard let object = value as? [String: Any] else {
            throw SilverCareCoreError.invalidJSON("Expected JSON object")
        }
        return object
    }

    static func array(from text: String) throws -> [[String: Any]] {
        let value = try any(from: text)
        guard let array = value as? [[String: Any]] else {
            throw SilverCareCoreError.invalidJSON("Expected JSON array")
        }
        return array
    }

    static func any(from text: String) throws -> Any {
        let clean = stripMarkdownFence(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if let value = try? parse(clean) {
            return value
        }
        guard let extracted = firstParseableJSON(in: clean) else {
            throw SilverCareCoreError.invalidJSON("No complete JSON value found")
        }
        return try parse(extracted)
    }

    static func string(from value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func parse(_ text: String) throws -> Any {
        guard let data = text.data(using: .utf8) else {
            throw SilverCareCoreError.invalidJSON("Input is not UTF-8")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func stripMarkdownFence(_ text: String) -> String {
        var clean = text
        if clean.hasPrefix("```json") {
            clean.removeFirst(7)
        } else if clean.hasPrefix("```") {
            clean.removeFirst(3)
        }
        if clean.hasSuffix("```") {
            clean.removeLast(3)
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstParseableJSON(in text: String) -> String? {
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "{" || character == "[" {
                if let candidate = completeJSON(in: text, startingAt: index),
                   (try? parse(candidate)) != nil {
                    return candidate
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func completeJSON(in text: String, startingAt start: String.Index) -> String? {
        var stack: [Character] = []
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                stack.append("}")
            } else if character == "[" {
                stack.append("]")
            } else if character == "}" || character == "]" {
                guard stack.last == character else { return nil }
                stack.removeLast()
                if stack.isEmpty {
                    return String(text[start...index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}

public enum SilverCareCoreError: Error, LocalizedError {
    case invalidJSON(String)
    case modelNotReady(String)
    case unsupported(String)
    case missingCredential(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let message),
             .modelNotReady(let message),
             .unsupported(let message),
             .missingCredential(let message),
             .transport(let message):
            return message
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String, default defaultValue: String = "") -> String {
        if let value = self[key] as? String { return value }
        if let value = self[key], !(value is NSNull) { return String(describing: value) }
        return defaultValue
    }

    func bool(_ key: String, default defaultValue: Bool = false) -> Bool {
        if let value = self[key] as? Bool { return value }
        if let value = self[key] as? NSNumber { return value.boolValue }
        return defaultValue
    }

    func double(_ key: String, default defaultValue: Double = 0) -> Double {
        if let value = self[key] as? Double { return value }
        if let value = self[key] as? Int { return Double(value) }
        if let value = self[key] as? NSNumber { return value.doubleValue }
        return defaultValue
    }

    func int(_ key: String, default defaultValue: Int = 0) -> Int {
        if let value = self[key] as? Int { return value }
        if let value = self[key] as? NSNumber { return value.intValue }
        return defaultValue
    }
}
