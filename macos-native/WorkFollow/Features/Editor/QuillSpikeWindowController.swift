import AppKit
import Combine
import WebKit

/// P0 骨架验证窗口：Quill 内核 + 桥的最小宿主。
/// 不接任何业务（文档/宿主切换在 P1+）；只验证加载、编辑、Delta 上报、
/// 焦点与 Esc 路由这条链路。验收后由 P3 的正式组件取代。
@MainActor
final class QuillSpikeWindowController: NSWindowController, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    private let schemeHandler = QuillSchemeHandler()
    private var loadTask: _Concurrency.Task<Void, Never>?

    /// 桥事件的可观测状态（spike 断言用）。
    @Published private(set) var isReady = false
    @Published private(set) var lastPlainText: String?
    @Published private(set) var lastDeltaJSON: String?
    @Published private(set) var escapeCount = 0
    @Published private(set) var tabCount = 0
    @Published private(set) var reportedHeight: CGFloat = 0

    init() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: QuillSchemeHandler.scheme)
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(window: NSWindow(contentRect: NSRect(x: 200, y: 200, width: 560, height: 420),
                                    styleMask: [.titled, .closable, .resizable],
                                    backing: .buffered, defer: false))
        window?.title = "Quill 内核 Spike"
        window?.isReleasedWhenClosed = false
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "quill")
        window?.contentView = webView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not intended") }

    func presentWindow() {
        window?.makeKeyAndOrderFront(nil)
        loadTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                let bridge = try await QuillResources.prepare()
                self.schemeHandler.directory = bridge.deletingLastPathComponent()
                self.webView.load(URLRequest(url: URL(string: "\(QuillSchemeHandler.scheme)://editor/index.html")!))
            } catch {
                NSLog("[QuillSpike] 资源准备失败：\(error.localizedDescription)")
            }
        }
    }

    func dismiss() {
        loadTask?.cancel()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "quill")
        window?.close()
    }

    // MARK: Swift → JS

    func loadDelta(_ ops: [[String: Any]]) {
        send(["action": "load", "delta": ops])
    }

    func insertText(_ text: String) {
        webView.evaluateJavaScript(
            "quill.insertText(quill.getLength() - 1, \(String(reflecting: text))); quill.setSelection(quill.getLength() - 1);")
    }

    private func send(_ message: [String: Any]) {
        webView.callAsyncJavaScript("window.workfollowQuill.send(message)",
                                    arguments: ["message": message], in: nil, in: .page)
    }

    // MARK: WKScriptMessageHandler

    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        let body = message.body as? [String: Any] ?? [:]
        _Concurrency.Task { @MainActor in
            guard let event = body["event"] as? String else { return }
            switch event {
            case "ready":
                isReady = true
            case "deltaChanged":
                lastPlainText = body["plainText"] as? String
                if let ops = body["delta"], JSONSerialization.isValidJSONObject(ops) {
                    lastDeltaJSON = String(data: (try? JSONSerialization.data(withJSONObject: ops)) ?? Data(), encoding: .utf8)
                }
            case "escapePressed":
                escapeCount += 1
            case "tabPressed":
                tabCount += 1
            case "heightChanged":
                reportedHeight = body["height"] as? Double ?? 0
            default:
                break
            }
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, url.scheme == QuillSchemeHandler.scheme {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }
}
