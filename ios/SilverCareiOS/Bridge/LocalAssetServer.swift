import Foundation
import Network

final class LocalAssetServer {
    private let queue = DispatchQueue(label: "com.silvercare.aiassistant.assetserver")
    private let rootDirectory: URL
    private let port: UInt16
    private var listener: NWListener?
    private var isReady = false

    init(port: UInt16 = 8848, rootDirectory: URL? = WebAssetLocator.assetRootURL()) throws {
        guard let rootDirectory else {
            throw LocalAssetServerError.missingBundleAssets
        }
        self.port = port
        self.rootDirectory = rootDirectory.standardizedFileURL
    }

    func start(onReady: @escaping (Result<URL, Error>) -> Void) throws {
        if listener != nil, isReady {
            onReady(.success(rootURL()))
            return
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isReady = true
                onReady(.success(self.rootURL()))
            case .failed(let error):
                self.isReady = false
                onReady(.failure(error))
            case .cancelled:
                self.isReady = false
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isReady = false
    }

    private func rootURL() -> URL {
        URL(string: "http://127.0.0.1:\(port)/index.html")!
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }

            let request = String(decoding: data, as: UTF8.self)
            let response = self.response(for: self.path(from: request))
            connection.send(
                content: response,
                contentContext: .defaultMessage,
                isComplete: true,
                completion: .contentProcessed { _ in
                    self.queue.asyncAfter(deadline: .now() + 0.1) {
                        connection.cancel()
                    }
                }
            )
        }
    }

    private func path(from request: String) -> String {
        guard let firstLine = request.split(separator: "\r\n").first else { return "/index.html" }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return "/index.html" }
        let rawPath = String(parts[1])
        return rawPath == "/" ? "/index.html" : rawPath
    }

    private func response(for path: String) -> Data {
        guard let fileURL = sanitizedFileURL(for: path) else {
            return httpResponse(
                status: "404 Not Found",
                contentType: "text/plain; charset=utf-8",
                body: Data("Not Found".utf8)
            )
        }

        do {
            let body = try Data(contentsOf: fileURL)
            return httpResponse(
                status: "200 OK",
                contentType: mimeType(for: fileURL.pathExtension),
                body: body
            )
        } catch {
            return httpResponse(
                status: "500 Internal Server Error",
                contentType: "text/plain; charset=utf-8",
                body: Data("Internal Server Error".utf8)
            )
        }
    }

    private func sanitizedFileURL(for path: String) -> URL? {
        let decoded = path.removingPercentEncoding ?? path
        let trimmed = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let candidate = rootDirectory.appendingPathComponent(trimmed.isEmpty ? "index.html" : trimmed)
        let standardized = candidate.standardizedFileURL
        guard standardized.path.hasPrefix(rootDirectory.path) else { return nil }
        guard FileManager.default.fileExists(atPath: standardized.path) else { return nil }
        return standardized
    }

    private func httpResponse(status: String, contentType: String, body: Data) -> Data {
        var response = Data()
        let header = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-cache",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")
        response.append(Data(header.utf8))
        response.append(body)
        return response
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html":
            return "text/html; charset=utf-8"
        case "css":
            return "text/css; charset=utf-8"
        case "js", "mjs":
            return "application/javascript; charset=utf-8"
        case "json":
            return "application/json; charset=utf-8"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "svg":
            return "image/svg+xml"
        case "webp":
            return "image/webp"
        case "ico":
            return "image/x-icon"
        case "mnn":
            return "application/octet-stream"
        default:
            return "application/octet-stream"
        }
    }
}

enum LocalAssetServerError: LocalizedError {
    case missingBundleAssets

    var errorDescription: String? {
        switch self {
        case .missingBundleAssets:
            return "未找到打包进 iOS 应用的 Web assets 资源目录。"
        }
    }
}
