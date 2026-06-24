import SwiftUI
import WebKit

struct SilverCareWebView: UIViewRepresentable {
    let appModel: SilverCareAppModel

    func makeCoordinator() -> Coordinator {
        Coordinator(appModel: appModel)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "silverCare")
        if appModel.automationEnabled {
            contentController.add(context.coordinator, name: "silverCareAutomation")
            contentController.addUserScript(WKUserScript(
                source: SilverCareAutomationScript.make(),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
        }
        contentController.addUserScript(WKUserScript(
            source: appModel.runtimeBootstrapScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isUserInteractionEnabled = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        context.coordinator.attach(webView: webView)
        appModel.attach(webView: webView)
        context.coordinator.loadRootPage()
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        private let appModel: SilverCareAppModel
        private weak var webView: WKWebView?
        private var assetServer: LocalAssetServer?

        init(appModel: SilverCareAppModel) {
            self.appModel = appModel
        }

        func attach(webView: WKWebView) {
            self.webView = webView
        }

        func loadRootPage() {
            guard let webView else { return }
            do {
                let server = try LocalAssetServer()
                assetServer = server
                try server.start { [weak webView] result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let url):
                            webView?.load(URLRequest(url: url))
                        case .failure:
                            webView?.loadHTMLString(WebAssetLocator.failureHTML(), baseURL: nil)
                        }
                    }
                }
            } catch {
                webView.loadHTMLString(WebAssetLocator.failureHTML(), baseURL: nil)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let payload = message.body as? [String: Any] else { return }
            if message.name == "silverCareAutomation" {
                appModel.handleAutomationSnapshot(payload)
                return
            }
            if message.name == "silverCare" {
                appModel.handleBridgeMessage(payload)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            appModel.publishRuntimeStatus()
        }

        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.grant)
        }
    }
}
