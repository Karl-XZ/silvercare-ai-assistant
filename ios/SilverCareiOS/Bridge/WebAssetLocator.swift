import Foundation

enum WebAssetLocator {
    static func assetRootURL(in bundle: Bundle = .main) -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            bundle.resourceURL?.appendingPathComponent("assets", isDirectory: true),
            bundle.resourceURL?.appendingPathComponent("WebAssets", isDirectory: true),
            bundle.resourceURL?.appendingPathComponent("app/src/main/assets", isDirectory: true),
            indexURL(in: bundle)?.deletingLastPathComponent()
        ]

        return candidates.compactMap { $0 }.first { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    static func indexURL(in bundle: Bundle = .main) -> URL? {
        let candidates = [
            bundle.url(forResource: "index", withExtension: "html", subdirectory: "WebAssets"),
            bundle.url(forResource: "index", withExtension: "html", subdirectory: "assets"),
            bundle.url(forResource: "index", withExtension: "html", subdirectory: "app/src/main/assets"),
            bundle.url(forResource: "index", withExtension: "html")
        ]
        if let url = candidates.compactMap({ $0 }).first {
            return url
        }

        let root = bundle.resourceURL
        let fileManager = FileManager.default
        let fallbackPaths = [
            "WebAssets/index.html",
            "assets/index.html",
            "app/src/main/assets/index.html",
            "index.html"
        ]
        for path in fallbackPaths {
            guard let url = root?.appendingPathComponent(path), fileManager.fileExists(atPath: url.path) else {
                continue
            }
            return url
        }
        return nil
    }

    static func failureHTML(resourceURL: URL? = Bundle.main.resourceURL) -> String {
        """
        <!doctype html>
        <html lang="zh-CN">
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <style>
              body { margin: 0; padding: 24px; font: -apple-system-body; background: #05070a; color: white; }
              code { color: #9be7ff; word-break: break-all; }
            </style>
          </head>
          <body>
            <h1>银龄智护资源未找到</h1>
            <p>iOS App 没有在 Bundle 中找到 <code>index.html</code>。请检查 Xcode 的 Copy Bundle Resources 是否包含 Android WebView assets 目录。</p>
            <p>Bundle resource path: <code>\(resourceURL?.path ?? "unknown")</code></p>
          </body>
        </html>
        """
    }
}
