import Foundation

final class IOSDiagnosticLogger {
    private let queue = DispatchQueue(label: "silvercare.ios.diagnostics")
    private let session: String
    private let latestURL: URL?
    private let sessionURL: URL?

    var latestLogPath: String {
        latestURL?.path ?? ""
    }

    init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        session = formatter.string(from: Date())
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("diagnostics", isDirectory: true)
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            latestURL = directory.appendingPathComponent("latest.jsonl")
            sessionURL = directory.appendingPathComponent("session-\(session).jsonl")
            try? Data().write(to: latestURL!)
            try? Data().write(to: sessionURL!)
        } else {
            latestURL = nil
            sessionURL = nil
        }
        event("app_start", data: [:])
    }

    func event(_ name: String, data: [String: Any]) {
        var payload = data
        payload["ts"] = Int(Date().timeIntervalSince1970 * 1000)
        payload["session"] = session
        payload["event"] = name
        write(payload)
    }

    func event(_ name: String, dataJSON: String) {
        let data: [String: Any]
        if let bytes = dataJSON.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
            data = object
        } else {
            data = ["raw": dataJSON]
        }
        event(name, data: data)
    }

    private func write(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: data, encoding: .utf8)?.appending("\n").data(using: .utf8)
        else { return }
        queue.async { [latestURL, sessionURL] in
            for url in [latestURL, sessionURL].compactMap({ $0 }) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: line)
                    try? handle.close()
                }
            }
        }
    }
}
