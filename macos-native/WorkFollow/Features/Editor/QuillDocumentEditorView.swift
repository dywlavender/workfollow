import Combine
import SwiftUI
import WebKit

/// Quill 内核的正式文档编辑器宿主（内核切换 P3+）。
///
/// 与 `DocumentEditor` 同签名，宿主切换时逐个替换。职责边界：
/// - Web 侧拥有工具条/斜杠菜单/markdown 触发（滴答同款组件，见 quill-web/）；
/// - Swift 侧拥有文档真源装载（Delta）、变更回写、焦点、Esc 裁决、
///   requestAction（附件/图片/链接/drawio/时间/表格占位）。
/// 快速添加条、行内标题不在此列（滴答同样非富文本，保持原生）。
struct QuillDocumentEditorView: NSViewRepresentable {
    let documentID: UUID
    let document: NativeDocument
    let onDocumentChange: (NativeDocument) -> Void
    let onEscape: () -> InspectorEscapeEffect
    let onEditingChanged: (Bool) -> Void
    var contentSized = false
    var handle: DocumentEditorHandle?
    /// 滴答口径：工具条默认隐藏，由宿主的 Aa 开关控制（底部展开）。
    var toolbarVisible = false

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> QuillWebView {
        let view = QuillWebView()
        view.delegate = context.coordinator
        view.usesContentHeight = contentSized
        context.coordinator.attach(view: view)
        view.loadBridge()
        view.setGrows(contentSized)
        view.setToolbarVisible(toolbarVisible)
        return view
    }

    func updateNSView(_ view: QuillWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncDocumentIfNeeded()
        view.usesContentHeight = contentSized
        view.setGrows(contentSized)
        view.setToolbarVisible(toolbarVisible)
    }

    static func dismantleNSView(_ view: QuillWebView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, QuillWebView.Delegate {
        var parent: QuillDocumentEditorView
        private weak var view: QuillWebView?
        /// 最近一次已同步给内核 / 已从内核收回的 Delta 字符串（JSON）。
        private var lastSyncedDeltaJSON = ""

        private var subscribers: [AnyCancellable] = []

        init(parent: QuillDocumentEditorView) {
            self.parent = parent
            super.init()
        }

        func attach(view: QuillWebView) {
            self.view = view
        }

        func detach() {
            view?.teardown()
        }

        // MARK: 文档同步

        func syncDocumentIfNeeded() {
            guard let view, view.isBridgeReady else { return }
            let delta = QuillDeltaCodec.delta(from: parent.document)
            guard let data = try? JSONEncoder().encode(delta),
                  let json = String(data: data, encoding: .utf8),
                  json != lastSyncedDeltaJSON else { return }
            lastSyncedDeltaJSON = json
            view.loadDelta(json)
        }

        // MARK: QuillWebViewDelegate（桥事件都在主线程回调）

        func quillViewReady(_ view: QuillWebView) {
            syncDocumentIfNeeded()
        }

        func quillView(_ view: QuillWebView, deltaChanged deltaJSON: String, plainText: String) {
            lastSyncedDeltaJSON = deltaJSON
            guard let data = deltaJSON.data(using: .utf8),
                  let ops = try? JSONDecoder().decode([QuillDeltaOp].self, from: data) else { return }
            let document = QuillDeltaCodec.document(from: ops)
            guard document != parent.document else { return }
            parent.onDocumentChange(document)
        }

        func quillViewEscape(_ view: QuillWebView) {
            _ = parent.onEscape()
        }

        func quillViewTab(_ view: QuillWebView, shift: Bool) {
            // Tab 进描述是任务快速添加的语义；正文里 Tab 缩进列表（Quill 默认），
            // 这里不劫持——转回 Web 侧处理。
            view.performDefaultTab()
        }

        func quillView(_ view: QuillWebView, requestAction action: String,
                       payload: [String: Any]) {
            switch action {
            case "image":
                ImagePickPanel.present { data in
                    guard let data else { return }
                    view.insertImage(data: data)
                }
            case "diagram", "editDiagram":
                NotificationCenter.default.post(name: .quillEditorRequestDiagram, object: view)
            default:
                // attachment / link / time / table：P3 打磨批次接管线，先占位不静默失败。
                NSLog("[QuillEditor] requestAction 未接管线：\(action)")
            }
        }

        func quillView(_ view: QuillWebView, heightChanged height: CGFloat) {
            // contentSized 宿主（笔记页）靠 ScrollView 自然滚动；这里无需处理，
            // 任务详情（固定视口）在 P4 接管后使用该值。
        }
    }
}

extension Notification.Name {
    static let quillProbeInsert = Notification.Name("quillProbeInsert")
    static let quillEditorRequestDiagram = Notification.Name("quillEditorRequestDiagram")
}

/// WKWebView 宿主：进程池共享 + 桥消息路由。
@MainActor
final class QuillWebView: NSView, WKScriptMessageHandler, WKNavigationDelegate {
    nonisolated static let sharedProcessPool = WKProcessPool()

    protocol Delegate: AnyObject {
        func quillViewReady(_ view: QuillWebView)
        func quillView(_ view: QuillWebView, deltaChanged deltaJSON: String, plainText: String)
        func quillViewEscape(_ view: QuillWebView)
        func quillViewTab(_ view: QuillWebView, shift: Bool)
        func quillView(_ view: QuillWebView, requestAction action: String, payload: [String: Any])
        func quillView(_ view: QuillWebView, heightChanged height: CGFloat)
    }

    private let schemeHandler = QuillSchemeHandler()
    private(set) lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = Self.sharedProcessPool       // 多实例共享 WebContent
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: QuillSchemeHandler.scheme)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "quill")
        return webView
    }()

    weak var delegate: Delegate?
    private(set) var isBridgeReady = false
    /// contentSized 宿主（笔记页）：编辑器随内容长高，滚动全部交给
    /// 外层 SwiftUI ScrollView——内层 web 滚动与外层并存会让回车后
    /// 光标上下跳动（2026-10-24 实测 bug），因此内层滚动在 CSS 里禁用。
    var usesContentHeight = false {
        didSet { invalidateIntrinsicContentSize() }
    }
    private var reportedContentHeight: CGFloat = 0
    /// 内核侧自增版本：deltaChanged 的 rev 必须 > loadedRevision 才上报
    /// （load 用 silent 不触发 text-change，但 bridge 会主动 emit 一次"回声"）。
    private var loadedRevision = 0
    private var lastObservedRevision = 0
    private var loadTask: _Concurrency.Task<Void, Never>?
    private var pendingDeltaJSON: String?
    private var probeObserver: NSObjectProtocol?
    private var focusObserver: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // 约束式布局：autoresizing 在 SwiftUI 尺寸变化时不可靠（layout() 只在
        // 显式调用时跑），约束保证 WebView 永远铺满、命中测试永远正确。
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// 键盘可达性：SwiftUI 宿主点击后，WKWebView 必须能成为 key 视图，
    /// 否则 WebContent 收不到任何按键（P3 实测缺陷：编辑器点击后打字无效）。
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let accepted = webView.becomeFirstResponder()
        focusEditor()
        return accepted
    }

    /// 命中测试直达 webView：宿主 NSView 不拦截点击，WebView 自己处理
    /// 光标落点并（经由它自己的 responder 逻辑）成为 first responder。
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return webView.hitTest(convert(local, to: webView))
    }

    /// 内容自适应：内核上报的 root.scrollHeight 即编辑器理想高度，
    /// SwiftUI ScrollView 依此排布并统一滚动。
    override var intrinsicContentSize: NSSize {
        usesContentHeight
            ? NSSize(width: NSView.noIntrinsicMetric, height: max(reportedContentHeight, 56))
            : NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not intended") }

    func loadBridge() {
        // SwiftUI 宿主下 WKWebView 点击不总能夺焦：本地监听本视图内的
        // mouseDown，显式 makeFirstResponder。键盘输入走自然路径
        // （2026-10-24 CGEvent/HID 实测：真实键盘分发直达 WebContent，
        // 拦截注入通道反而破坏 IME 组合输入，已移除）。
        focusObserver = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) {
            [weak self] event in
            guard let self else { return event }
            guard let window = event.window, window == self.webView.window else { return event }
            if self.webView.hitTest(event.locationInWindow) != nil {
                window.makeFirstResponder(self.webView)
            }
            return event
        }
        // P3 诊断探针：Debug 菜单触发，绕过键盘验证 delta 上报链。
        self.probeObserver = NotificationCenter.default.addObserver(
            forName: .quillProbeInsert, object: nil, queue: .main
        ) { [weak self] _ in
            self?.call("quill.focus()")
            self?.insertTextProbe("PROBE")
        }
        loadTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                let index = try await QuillResources.prepare()
                self.schemeHandler.directory = index.deletingLastPathComponent()
                self.webView.load(URLRequest(url:
                    URL(string: "\(QuillSchemeHandler.scheme)://editor/index.html")!))
            } catch {
                NSLog("[QuillEditor] 资源准备失败：\(error.localizedDescription)")
            }
            _ = await MainActor.run {}
        }
    }

    func teardown() {
        if let probeObserver { NotificationCenter.default.removeObserver(probeObserver) }
        if let focusObserver { NSEvent.removeMonitor(focusObserver) }
        loadTask?.cancel()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "quill")
    }

    // MARK: Swift → JS

    func loadDelta(_ deltaJSON: String) {
        guard isBridgeReady else {
            pendingDeltaJSON = deltaJSON
            return
        }
        call("window.workfollowEditor.load(\(deltaJSON))")
    }

    func focusEditor() {
        call("window.workfollowEditor.focus()")
    }

    /// 滴答口径：工具条默认隐藏，Aa 开关展开（编辑器底部）。
    func setToolbarVisible(_ visible: Bool) {
        call("window.workfollowEditor.setToolbar(\(visible))")
    }

    /// 内容自适应模式（笔记页）：内核挂 body.wf-grows（内层滚动禁用），
    /// 高度经 intrinsicContentSize 交给外层 SwiftUI ScrollView 统一滚动。
    func setGrows(_ grows: Bool) {
        call("window.workfollowEditor.setGrows(\(grows))")
    }

    func performDefaultTab() {
        call("window.workfollowEditor.tab()")
    }

    private func insertBlockEmbed(_ value: [JSONValue: JSONValue]...) {
        // 占位：P3 打磨时接 NativeAttachment 存储管线。
    }

    /// P3 诊断：绕过键盘直接在内核里插文本（验证 delta 上报链）。
    func insertTextProbe(_ text: String) {
        call("window.workfollowEditor.insertText(\(String(reflecting: text)))")
    }

    func insertImage(data: Data) {
        let base64 = data.base64EncodedString()
        call("window.workfollowEditor.insertImage('\(base64)')")
    }

    private var queuedScripts: [String] = []

    private func call(_ script: String) {
        // 桥未就绪（资源解压/页面加载中）时排队，ready 后一并冲刷；
        // 否则 makeNSView 阶段推送的 setGrows/setToolbar 会静默丢失。
        guard isBridgeReady else {
            queuedScripts.append(script)
            return
        }
        webView.evaluateJavaScript(script) { _, _ in }
    }

    // MARK: WKScriptMessageHandler

    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let event = body["event"] as? String else { return }
        let event_ = event
        let body_ = body
        _Concurrency.Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            let body = body_
            switch event_ {
            case "ready":
                isBridgeReady = true
                let queue = queuedScripts
                queuedScripts.removeAll()
                queue.forEach { webView.evaluateJavaScript($0) { _, _ in } }
                if let pending = pendingDeltaJSON {
                    pendingDeltaJSON = nil
                    loadDelta(pending)
                }
                delegate?.quillViewReady(self)
            case "loaded":
                if let rev = body["rev"] as? Int {
                    loadedRevision = rev
                    lastObservedRevision = rev
                }
            case "deltaChanged":
                let rev = body["rev"] as? Int ?? 0
                guard rev > lastObservedRevision else { break }   // load 回声
                lastObservedRevision = rev
                if let delta = body["delta"] as? String, let text = body["plainText"] as? String {
                    delegate?.quillView(self, deltaChanged: delta, plainText: text)
                }
            case "escapePressed":
                delegate?.quillViewEscape(self)
            case "tabPressed":
                delegate?.quillViewTab(self, shift: body["shift"] as? Bool ?? false)
            case "requestAction":
                delegate?.quillView(self, requestAction: body["action"] as? String ?? "",
                                    payload: body["diagram"] as? [String: Any] ?? [:])
            case "heightChanged":
                let reportedHeight = (body["height"] as? Double).map { CGFloat($0) } ?? 0
                reportedContentHeight = reportedHeight
                if usesContentHeight { invalidateIntrinsicContentSize() }
                delegate?.quillView(self, heightChanged: reportedHeight)
            default:
                break
            }
        }
    }

    // MARK: WKNavigationDelegate（离线白名单）

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.request.url?.scheme == QuillSchemeHandler.scheme {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }
}

/// 图片选择（P2 先支持 PNG/JPEG → data URL；后续批次接附件存储）。
enum ImagePickPanel {
    static func present(_ completion: @escaping (Data?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg]
        panel.message = "选择要插入的图片"
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url) else {
                completion(nil)
                return
            }
            completion(data)
        }
    }
}
