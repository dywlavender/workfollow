import AppKit
import Combine
import WebKit

struct MilkdownSelection: Decodable {
    struct Style: Decodable {
        var blockToken: String
        var marks: [MilkdownDocument.Mark]
        var indentLevel: Int
        var align: DocumentAlignment?
        var bodySize: DocumentBodySize?
    }
    var revision: Int
    var from: Int
    var to: Int
    var text: String
    var plainFrom: Int
    var plainTo: Int
    var style: Style
    var canUndo: Bool
    var canRedo: Bool
    var empty: Bool
    var fragment: MilkdownDocument?
    var formatPainterActive: Bool?
}

@MainActor
final class MilkdownEditorRegistry: ObservableObject {
    static let shared = MilkdownEditorRegistry()
    private final class Entry { weak var view: MilkdownWebView?; init(_ view: MilkdownWebView) { self.view = view } }
    private var entries: [Entry] = []
    var focusedEditor: MilkdownWebView? {
        guard let responder = NSApp.keyWindow?.firstResponder as? NSView else { return nil }
        return entries.compactMap(\.view).first { responder === $0.webView || responder.isDescendant(of: $0.webView) }
    }
    func register(_ view: MilkdownWebView) { entries.removeAll { $0.view == nil }; entries.append(Entry(view)) }
    func changed() { objectWillChange.send() }
    func flushAll() async {
        for view in entries.compactMap(\.view) { await view.flush() }
    }
}

@MainActor
final class MilkdownWebView: NSView, WKNavigationDelegate {
    struct Binding {
        var id: UUID
        var document: NativeDocument
        var profile: DocumentProfile
        var readOnly: Bool
        var fontSize: CGFloat
        var onChange: (NativeDocument) -> Void
        var onEscape: () -> InspectorEscapeEffect
        var onEditingChanged: (Bool) -> Void
    }
    private final class MessageHandler: NSObject, WKScriptMessageHandler {
        weak var owner: MilkdownWebView?
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            owner?.receive(message.body)
        }
    }
    private final class WebView: WKWebView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
    let webView: WKWebView
    let scheme = MilkdownSchemeHandler()
    weak var handle: DocumentEditorHandle?
    private var desired: Binding?
    private(set) var active: Binding?
    private(set) var document = NativeDocument.empty
    private(set) var epoch = UUID()
    private(set) var revision = 0
    private(set) var selection: MilkdownSelection?
    private(set) var isBridgeReady = false
    private(set) var loadError: String?
    private(set) var codec = MilkdownDocumentCodec()
    /// 增量提交的块缓存：全量提交时重建，差量提交时按 order 裁剪。
    private var blockCache: [String: DocumentBlock] = [:]
    private var bindTask: _Concurrency.Task<Void, Never>?
    private var resourceTask: _Concurrency.Task<Void, Never>?
    private var configurationData: Data?
    private var focusObserver: Any?
    private var scrollObserver: Any?
    private var clipObserver: NSObjectProtocol?
    private var spellingObserver: NSObjectProtocol?
    private var reminderInkObserver: NSObjectProtocol?
    private var shortcutObserver: AnyCancellable?
    private var internalScrollRegions: [NSRect] = []
    private var reportedHeight: CGFloat = 56
    private var assetVersion = 0
    private var pendingFocus: String?
    private var pendingReveal: NSRect?
    private var detached = false
    var diagramEditor: DrawioEditorWindowController?
    lazy var menuPresenter = MilkdownMenuPresenter(editor: self)
    var menuPanel: NSPanel? { menuPresenter.panel }
    private let statusLabel = NSTextField(labelWithString: "正在载入正文…")
    var reminderPanel: ChecklistItemReminderPanel?
    /// text.generate 被模型服务策略性拒绝后本轮运行置位，续写不再重复请求。
    var ghostDisabled = false
    struct HostOperation {
        var before: NativeDocument
        var after: NativeDocument?
        var commit: (NativeDocument) -> Void
        var inverse: (NativeDocument) -> Void
    }
    private var hostOperations: [String: HostOperation] = [:]
    var usesContentHeight = false {
        didSet { if oldValue != usesContentHeight { configurationData = nil; invalidateIntrinsicContentSize() } }
    }
    var decorationVisibleMinX: CGFloat = 0 {
        didSet { if oldValue != decorationVisibleMinX { configurationData = nil } }
    }
    var documentIdentity: UUID? { desired?.id ?? active?.id }
    var isReadOnly: Bool { active?.readOnly ?? true }
    var canUndo: Bool { selection?.canUndo == true }
    var canRedo: Bool { selection?.canRedo == true }
    var isDocumentReady: Bool { isBridgeReady && desired == nil && bindTask == nil && active != nil && loadError == nil }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: usesContentHeight ? max(56, reportedHeight) : NSView.noIntrinsicMetric)
    }

    override init(frame: NSRect) {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(scheme, forURLScheme: MilkdownSchemeHandler.scheme)
        let handler = MessageHandler()
        configuration.userContentController.add(handler, name: "milkdown")
        webView = WebView(frame: .zero, configuration: configuration)
        super.init(frame: frame)
        handler.owner = self; webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.translatesAutoresizingMaskIntoConstraints = false; addSubview(webView)
        NSLayoutConstraint.activate([webView.leadingAnchor.constraint(equalTo: leadingAnchor), webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor), webView.bottomAnchor.constraint(equalTo: bottomAnchor)])
        statusLabel.font = .systemFont(ofSize: 13); statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false; addSubview(statusLabel)
        NSLayoutConstraint.activate([statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor), statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12)])
        scheme.asset = { [weak self] id in self?.asset(id) }
        MilkdownEditorRegistry.shared.register(self)
        installRouting(); loadResources()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override func becomeFirstResponder() -> Bool { focus(); return window?.makeFirstResponder(webView) ?? false }
    override func layout() { super.layout(); updateViewport(); revealPendingSelection() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); configurationData = nil; configure() }

    func bind(_ binding: Binding, handle: DocumentEditorHandle?) {
        self.handle = handle; handle?.webView = self
        if active?.id == binding.id, desired == nil, document == binding.document {
            active = binding; configure(); return
        }
        if desired?.id == binding.id, desired?.document == binding.document { desired = binding; return }
        desired = binding
        applyDesired()
    }
    private func loadResources() {
        resourceTask = _Concurrency.Task { [weak self] in
            do {
                let file = try await MilkdownResources.prepare()
                guard let self, !detached else { return }
                scheme.directory = file.deletingLastPathComponent()
                webView.load(URLRequest(url: URL(string: "workfollow-milkdown://editor/index.html")!))
            } catch { self?.report(error) }
        }
    }
    private func applyDesired() {
        guard isBridgeReady, bindTask == nil, !detached else { return }
        bindTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            while let next = desired, !detached {
                menuPresenter.dismiss()
                desired = nil
                if active != nil { await flush() }
                if desired != nil { continue }
                let changedIdentity = active?.id != next.id
                if changedIdentity { hostOperations = [:]; codec = MilkdownDocumentCodec(); selection = nil; pendingReveal = nil }
                active = next; document = next.document; epoch = UUID(); revision = 0; assetVersion += 1
                codec.assetURL = { [weak self] id in "workfollow-milkdown://editor/asset/\(id.uuidString)?v=\(self?.assetVersion ?? 0)" }
                do {
                    let wire = try codec.encode(next.document)
                    let packet: [String: Any] = ["documentID": next.id.uuidString, "epoch": epoch.uuidString,
                        "doc": try object(wire), "settings": settings()]
                    _ = try await call("load", packet)
                    loadError = nil; statusLabel.isHidden = true
                    if let pendingFocus { self.pendingFocus = nil; perform(pendingFocus) }
                } catch { report(error) }
            }
            bindTask = nil
        }
    }
    func call(_ method: String, _ payload: [String: Any] = [:]) async throws -> Any {
        let result = try await webView.callAsyncJavaScript("const api=window.workfollowEditor; if(!api) throw new Error('编辑器未就绪'); return method==='command' ? api.command(payload.name,payload.payload||{}) : api[method](payload);",
            arguments: ["method": method, "payload": payload], in: nil, contentWorld: .page)
        return result ?? NSNull()
    }
    func perform(_ name: String, payload: [String: Any] = [:]) {
        if !isBridgeReady || active == nil {
            if ["focus", "focusEnd", "focusFirstLine", "focusFirstLineStart"].contains(name) { pendingFocus = name }
            return
        }
        _Concurrency.Task { [weak self] in
            do { _ = try await self?.call("command", ["name": name, "payload": payload]) }
            catch { self?.report(error) }
        }
    }
    func focus(end: Bool = false) {
        window?.makeFirstResponder(webView)
        perform(end ? "focusEnd" : "focus")
    }
    /// 标题回车接力：焦点给正文，选区落在第一行末尾。
    func focusFirstLine() {
        window?.makeFirstResponder(webView)
        perform("focusFirstLine")
    }
    /// 标题右方向键接力：焦点给正文，选区落在第一行行首。
    func focusFirstLineStart() {
        window?.makeFirstResponder(webView)
        perform("focusFirstLineStart")
    }
    func selectFromHost(_ event: NSEvent, phase: String) {
        guard !isReadOnly else { return }
        let point = webView.convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(webView)
        perform("hostPointer", payload: ["x": point.x, "y": webView.isFlipped ? point.y : webView.bounds.height - point.y,
            "phase": phase, "shift": event.modifierFlags.contains(.shift), "clickCount": event.clickCount])
    }
    func prepareForDocumentChange() {
        if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: webView) { window?.makeFirstResponder(nil) }
        _Concurrency.Task { [self] in await flush() }
    }
    func flush() async {
        guard isBridgeReady, let context = active else { return }
        do {
            guard let value = try await call("flush") as? [String: Any],
                  value["documentID"] as? String == context.id.uuidString,
                  value["epoch"] as? String == epoch.uuidString,
                  let wire = value["doc"] else { return }
            revision = value["revision"] as? Int ?? revision
            try accept(wire, context: context, token: value["hostToken"] as? String, operation: value["operation"] as? String)
        } catch { report(error) }
    }
    func detach() {
        guard !detached else { return }
        detached = true; resourceTask?.cancel()
        if let focusObserver { NSEvent.removeMonitor(focusObserver) }; focusObserver = nil
        if let scrollObserver { NSEvent.removeMonitor(scrollObserver) }; scrollObserver = nil
        if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }; clipObserver = nil
        if let spellingObserver { NotificationCenter.default.removeObserver(spellingObserver) }; spellingObserver = nil
        if let reminderInkObserver { NotificationCenter.default.removeObserver(reminderInkObserver) }; reminderInkObserver = nil
        shortcutObserver = nil
        reminderPanel?.dismiss(); reminderPanel = nil
        menuPresenter.dismiss()
        diagramEditor?.close(); diagramEditor = nil
        _Concurrency.Task { [self] in
            await flush(); webView.configuration.userContentController.removeScriptMessageHandler(forName: "milkdown")
            active?.onEditingChanged(false)
        }
    }
    func insert(_ value: NativeDocument, whole: Bool = false, commit: ((NativeDocument) -> Void)? = nil,
                inverse: ((NativeDocument) -> Void)? = nil, wholeBlocks: Bool = false) -> Bool {
        guard isBridgeReady, active != nil, !isReadOnly else { return false }
        do {
            var wire = try object(encode(value)) as! [String: Any]
            wire["wholeBlocks"] = wholeBlocks
            var payload: [String: Any] = ["doc": wire]
            if let commit {
                let token = UUID().uuidString
                hostOperations[token] = HostOperation(before: document, commit: commit, inverse: inverse ?? commit)
                payload["hostToken"] = token
            }
            perform(whole ? "replaceDocument" : "insertFragment", payload: payload)
            return true
        } catch { report(error); return false }
    }
    func encode(_ value: NativeDocument) throws -> MilkdownDocument { assetVersion += 1; return try codec.encode(value) }
    func update(_ embed: MilkdownDocument.Embed) {
        do { perform("updateEmbed", payload: ["id": embed.id.uuidString, "value": try object(embed)]) }
        catch { report(error) }
    }
    func accept(_ value: Any, context: Binding, token: String? = nil, operation: String? = nil) throws {
        let wire = try JSONDecoder().decode(MilkdownDocument.self, from: JSONSerialization.data(withJSONObject: value))
        let next = try codec.decode(wire)
        // 全量提交是差量缓存的唯一重建点
        blockCache = Dictionary(next.blocks.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { _, later in later })
        try commitDecoded(next, context: context, token: token, operation: operation)
    }

    /// 增量提交：web 端按块差量过桥（`order` 全量、`changed` 仅变化块），
    /// 原生只解码变化块、按 order 重组并裁剪缓存。缓存缺口时请求 web 重发全量。
    private func acceptIncremental(order: [String], changed: [String: Any], context: Binding,
                                   token: String?, operation: String?) throws {
        for (id, wire) in changed {
            let data = try JSONSerialization.data(withJSONObject: wire)
            let block = try JSONDecoder().decode(MilkdownDocument.Block.self, from: data)
            blockCache[id] = try codec.decodeBlock(block)
        }
        var blocks: [DocumentBlock] = []
        blocks.reserveCapacity(order.count)
        var live = Set<String>()
        for id in order {
            guard let block = blockCache[id] else {
                blockCache.removeAll()
                perform("reloadDocument")
                throw MilkdownDocumentCodec.Failure.missingBlock
            }
            blocks.append(block); live.insert(id)
        }
        blockCache = blockCache.filter { live.contains($0.key) }
        try commitDecoded(NativeDocument(blocks: blocks), context: context, token: token, operation: operation)
    }

    private func commitDecoded(_ next: NativeDocument, context: Binding, token: String?, operation: String?) throws {
        guard next != document else { return }
        if active?.id == context.id { document = next }
        if let token, var host = hostOperations[token] {
            if operation == "undo" { host.inverse(next) }
            else {
                host.after = next; hostOperations[token] = host; host.commit(next)
            }
        } else { context.onChange(next) }
    }
    private func receive(_ body: Any) {
        guard let value = body as? [String: Any], let event = value["event"] as? String else { return }
        if event == "ready" { isBridgeReady = true; applyDesired(); return }
        if event == "error" { report(AIBackendError.failed(value["message"] as? String ?? "编辑器加载失败")); return }
        guard let context = active,
              value["documentID"] as? String == context.id.uuidString,
              value["epoch"] as? String == epoch.uuidString else { return }
        do {
            switch event {
            case "docChanged":
                let next = value["revision"] as? Int ?? 0
                guard next >= revision else { return }
                revision = next
                if let wire = value["doc"] {
                    try accept(wire, context: context, token: value["hostToken"] as? String, operation: value["operation"] as? String)
                } else if let order = value["order"] as? [String] {
                    try acceptIncremental(order: order, changed: value["changed"] as? [String: Any] ?? [:],
                                          context: context, token: value["hostToken"] as? String,
                                          operation: value["operation"] as? String)
                }
            case "selectionChanged":
                if let object = value["selection"] {
                    let next = try JSONDecoder().decode(MilkdownSelection.self, from: JSONSerialization.data(withJSONObject: object))
                    selection = next; handle?.updateFromWeb(next); MilkdownEditorRegistry.shared.changed()
                }
            case "heightChanged":
                let height = max(56, value["height"] as? CGFloat ?? 56)
                if abs(height - reportedHeight) > 0.5 { reportedHeight = height; if usesContentHeight { invalidateIntrinsicContentSize() } }
            case "scrollRegionsChanged":
                internalScrollRegions = (value["regions"] as? [[String: CGFloat]] ?? []).map {
                    NSRect(x: $0["x"] ?? 0, y: $0["y"] ?? 0, width: $0["width"] ?? 0, height: $0["height"] ?? 0)
                }
            case "popupChanged":
                if let packet = value["popup"] {
                    let state = try JSONDecoder().decode(MilkdownMenuPresenter.State.self, from: JSONSerialization.data(withJSONObject: packet))
                    menuPresenter.show(state)
                } else { menuPresenter.dismiss() }
            case "revealRect":
                if usesContentHeight, let rect = value["rect"] as? [String: CGFloat] {
                    pendingReveal = NSRect(x: rect["x"] ?? 0, y: rect["y"] ?? 0,
                        width: max(1, rect["width"] ?? 1), height: max(22, rect["height"] ?? 22))
                    revealPendingSelection()
                }
            case "focusChanged": context.onEditingChanged(value["focused"] as? Bool ?? false); MilkdownEditorRegistry.shared.changed()
            case "escapePressed": _ = context.onEscape()
            case "leftEdgePressed": handle?.onLeftEdge?()
            case "requestAction": handleAction(value["action"] as? String ?? "", payload: value["payload"] as? [String: Any] ?? [:])
            default: break
            }
        } catch { report(error) }
    }
    private func settings() -> [String: Any] {
        guard let active else { return [:] }
        let profile = active.profile
        func commands(_ values: [DocumentCommand]) -> [[String: String]] { values.map { ["id": $0.id, "title": $0.title, "group": $0.group, "keywords": $0.keywords] } }
        var actions = profile.selectionActions.map { ["id": $0.id, "title": $0.displayTitle] }
        if AISelectionWindowController.shared.isAvailable {
            // 润色/翻译/总结共用一套选区 AI 动作，只换预设问句；笔记宿主接进右侧
            // AI 栏，其它宿主用独立选区浮窗（路由见 MilkdownEditorActions）。
            actions.append(contentsOf: [["id": "ai.polish", "title": "AI 润色"],
                                        ["id": "ai.translate", "title": "AI 翻译"],
                                        ["id": "ai.summarize", "title": "AI 总结"]])
        }
        return ["grows": usesContentHeight, "readOnly": active.readOnly, "bodyFontSize": active.fontSize,
            "markerLeft": DocumentEditorGeometry.decorationMarkerX(visibleMinX: decorationVisibleMinX),
            "paragraphSpacing": profile.paragraphSpacing ?? 10, "selectionToolbar": profile.supportsSelectionToolbar,
            "commands": commands(profile.slashCommands), "blockCommands": commands(profile.blockMenuCommands ?? DocumentProfile.standardBlockMenuCommands),
            "selectionActions": actions, "tags": profile.tagCandidates(), "lists": profile.listCandidates(),
            "mentions": profile.mentionCandidates().map { ["id": $0.id.uuidString, "kind": $0.kind.rawValue, "title": $0.title] },
            "checklistReminders": profile.checklistRemindersEnabled,
            "inlineDateReminders": true,
            "inlineDateTaskLink": profile.setInlineDateReminder != nil,
            "editorShortcuts": AppShortcutStore.shared.webBindings(),
            "removedEditorShortcuts": AppShortcutStore.shared.webBindings(removedDefaults: true),
            "reminderInk": EditorPreferences.reminderInk,
            "ghostEnabled": AISelectionWindowController.shared.isAvailable,
            "spellChecking": EditorPreferences.spellCheckingEnabled,
            "textColor": Self.cssColor(NSColor(WFColors.documentText), appearance: effectiveAppearance),
            "accentColor": Self.cssColor(WFColors.nsAccent, appearance: effectiveAppearance),
            "dark": effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua]
    }
    private func configure() {
        guard isBridgeReady, active != nil else { return }
        let next = settings()
        guard let data = try? JSONSerialization.data(withJSONObject: next, options: .sortedKeys), data != configurationData else { return }
        configurationData = data
        _Concurrency.Task { [weak self] in _ = try? await self?.call("configure", next) }
    }
    private func installRouting() {
        shortcutObserver = AppShortcutStore.shared.$overrides.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.configure() }
        }
        spellingObserver = NotificationCenter.default.addObserver(forName: EditorPreferences.spellCheckingDidChange,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.configure() }
            }
        reminderInkObserver = NotificationCenter.default.addObserver(forName: EditorPreferences.reminderInkDidChange,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.configurationData = nil; self?.configure() }
            }
        focusObserver = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, EditorHostScrollRouting.contains(event, in: self) else { return event }
            window?.makeFirstResponder(webView); return event
        }
        scrollObserver = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            updateViewport()
            return EditorHostScrollRouting.forward(event, over: self, enabled: usesContentHeight, internalScrollRegions: internalScrollRegions) ? nil : event
        }
        clipObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let clip = notification.object as? NSClipView, clip === self.enclosingScrollView?.contentView else { return }
                self.updateViewport()
            }
        }
    }
    private func updateViewport() {
        guard isBridgeReady, active != nil else { return }
        let visible = bounds.intersection(visibleRect)
        let top = isFlipped ? visible.minY - bounds.minY : bounds.maxY - visible.maxY
        _Concurrency.Task { [weak self] in _ = try? await self?.call("configure", ["viewport": ["top": top, "bottom": top + visible.height]]) }
    }
    private func revealPendingSelection() {
        guard usesContentHeight, var target = pendingReveal, webView.bounds.height + 1 >= target.maxY else { return }
        pendingReveal = nil
        if !webView.isFlipped { target.origin.y = webView.bounds.height - target.maxY }
        guard let documentView = enclosingScrollView?.documentView else { return }
        documentView.scrollToVisible(documentView.convert(target, from: webView).insetBy(dx: 0, dy: -12))
    }
    func asset(_ id: UUID) -> (Data, String)? {
        guard let run = codec.asset(id) else { return nil }
        if let drawing = run.diagram { return (drawing.previewPNG, "image/png") }
        if let file = run.attachment {
            if file.storedName.hasPrefix("data:"), let comma = file.storedName.firstIndex(of: ","),
               let data = Data(base64Encoded: String(file.storedName[file.storedName.index(after: comma)...])) {
                let header = String(file.storedName[..<comma]).dropFirst(5)
                return (data, String(header.split(separator: ";").first ?? "image/png"))
            }
            if let url = NativeAttachmentFiles.url(for: file), let data = try? Data(contentsOf: url) { return (data, "application/octet-stream") }
        }
        return nil
    }
    func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
    func report(_ error: Error) {
        loadError = error.localizedDescription
        statusLabel.stringValue = "正文暂时无法打开，请重新打开此页面。"; statusLabel.isHidden = false
        NSLog("[Milkdown] %@", error.localizedDescription)
    }
    static func cssColor(_ color: NSColor, appearance: NSAppearance) -> String {
        var result = "#242426"
        appearance.performAsCurrentDrawingAppearance {
            if let value = color.usingColorSpace(.deviceRGB) { result = String(format: "rgba(%.0f,%.0f,%.0f,%.3f)", value.redComponent * 255, value.greenComponent * 255, value.blueComponent * 255, value.alphaComponent) }
        }
        return result
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.scheme == MilkdownSchemeHandler.scheme ? .allow : .cancel)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isBridgeReady = false
        if var active { active.document = document; desired = active }
        webView.reload()
    }
}
