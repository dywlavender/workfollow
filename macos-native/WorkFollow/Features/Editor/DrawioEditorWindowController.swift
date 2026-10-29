import AppKit
import WebKit
import UniformTypeIdentifiers

/// A window-modal drawing workspace; its draft never mutates the document until Save.
@MainActor
final class DrawioEditorWindowController: NSWindowController, WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate {
    let webView: WKWebView
    private let schemeHandler = DrawioSchemeHandler()
    private let titleField = NSTextField(string: "流程图")
    private let status = NSTextField(labelWithString: "正在准备绘图工具…")
    private let importButton = NSButton(title: "导入…", target: nil, action: nil)
    private let exportButton = NSButton(title: "导出 .drawio…", target: nil, action: nil)
    private let saveButton = NSButton(title: "保存并关闭", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private let onSave: (NativeDiagram) -> Bool
    private let onClose: () -> Void
    private let drawingID: UUID
    private var initialXML: String
    private var pendingSave: (xml: String, title: String, exit: Bool)?
    private var exportingSource = false
    private var capturingSave = false
    private var resourceTask: _Concurrency.Task<Void, Never>?
    private var timeoutTask: _Concurrency.Task<Void, Never>?
    private var hasClosed = false
    private(set) var isReady = false
    private(set) var isModified = false
    private(set) var lastError: String?

    init(diagram: NativeDiagram?, onSave: @escaping (NativeDiagram) -> Bool, onClose: @escaping () -> Void) {
        self.onSave = onSave
        self.onClose = onClose
        drawingID = diagram?.id ?? UUID()
        initialXML = diagram?.xml ?? NativeDiagram.emptyXML
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: DrawioSchemeHandler.scheme)
        webView = WKWebView(frame: .zero, configuration: config)
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: min(1160, visible.width - 60),
                                                 height: min(780, visible.height - 80)),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "绘图 · draw.io"
        window.minSize = NSSize(width: 820, height: 560)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        titleField.stringValue = diagram?.title ?? "流程图"
        titleField.placeholderString = "图表名称"
        titleField.font = .systemFont(ofSize: 14, weight: .medium)
        titleField.focusRingType = .none
        titleField.isBezeled = false
        titleField.drawsBackground = false
        titleField.widthAnchor.constraint(equalToConstant: 280).isActive = true
        titleField.target = self
        titleField.action = #selector(titleChanged)
        NotificationCenter.default.addObserver(self, selector: #selector(titleChanged),
                                               name: NSControl.textDidChangeNotification, object: titleField)
        importButton.target = self; importButton.action = #selector(importDrawing)
        exportButton.target = self; exportButton.action = #selector(exportDrawing)
        saveButton.target = self; saveButton.action = #selector(saveDrawing)
        cancelButton.target = self; cancelButton.action = #selector(cancelDrawing)
        saveButton.bezelStyle = .rounded; cancelButton.bezelStyle = .rounded
        for button in [importButton, exportButton, saveButton, cancelButton] {
            button.focusRingType = .none
        }
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = .command
        cancelButton.keyEquivalent = "\u{1b}"
        importButton.bezelStyle = .rounded; exportButton.bezelStyle = .rounded
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [titleField, spacer, importButton, exportButton, cancelButton, saveButton])
        header.spacing = 10; header.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "drawio")
        let root = NSView()
        window.contentView = root
        for view in [header, webView, status] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 48),
            webView.topAnchor.constraint(equalTo: header.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
            status.heightAnchor.constraint(equalToConstant: 18)
        ])
        setControlsEnabled(false)
    }

    required init?(coder: NSCoder) { fatalError("Use init(diagram:onSave:onClose:)") }

    func present(asSheetOf parent: NSWindow) {
        guard let window else { return }
        parent.beginSheet(window)
        resourceTask = _Concurrency.Task { [weak self] in
            do {
                let entry = try await DrawioResources.prepare()
                guard !_Concurrency.Task.isCancelled, let self, !hasClosed else { return }
                schemeHandler.directory = entry.deletingLastPathComponent()
                // Drawings stay local, including the image export renderer.
                let rules = """
                [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]
                """
                let ruleList = try await WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: "WorkFollow.Drawio.Offline", encodedContentRuleList: rules)
                if let ruleList { webView.configuration.userContentController.add(ruleList) }
                webView.load(URLRequest(url: URL(string: DrawioSchemeHandler.scheme + "://editor/bridge.html")!))
                armTimeout("绘图工具加载超时，请关闭后重试。", seconds: 30)
            } catch {
                self?.showError(error.localizedDescription)
            }
        }
    }

    func send(_ message: [String: Any]) {
        webView.callAsyncJavaScript("window.workfollowDrawio.send(message)", arguments: ["message": message],
                                     in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result { self?.showError(error.localizedDescription) }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, !hasClosed,
              let payload = message.body as? [String: Any], let event = payload["event"] as? String else { return }
        if let error = payload["error"] as? String, !error.isEmpty {
            pendingSave = nil; exportingSource = false; capturingSave = false
            showError("绘图处理失败：" + error); return
        }
        switch event {
        case "configure":
            send(["action": "configure", "config": ["defaultFonts": ["Arial", "Helvetica", "PingFang SC"],
                                                          "suppressNewWindows": true]])
        case "init":
            send(["action": "load", "xml": initialXML, "autosave": 1, "title": titleField.stringValue,
                  "saveAndExit": 0, "noSaveBtn": 1, "noExitBtn": 1])
        case "load":
            timeoutTask?.cancel(); isReady = true; lastError = nil
            status.textColor = .secondaryLabelColor
            setControlsEnabled(true)
            status.stringValue = "离线绘图 · 保存后插入正文，双击图表可继续编辑"
        case "autosave":
            isModified = true
            status.stringValue = "有未保存的修改"
        case "save":
            guard pendingSave == nil, !exportingSource, let xml = payload["xml"] as? String, !xml.isEmpty else { return }
            beginSaving(xml: xml, closeAfter: payload["exit"] as? Bool == true, state: payload)
        case "export":
            timeoutTask?.cancel()
            if capturingSave {
                capturingSave = false
                if let xml = payload["xml"] as? String { beginSaving(xml: xml, closeAfter: true, state: payload) }
                else { showError("图源读取失败，请重试保存。") }
            } else if exportingSource {
                exportingSource = false; setControlsEnabled(true)
                if let xml = payload["xml"] as? String { saveSource(xml) }
            } else if let pending = pendingSave {
                pendingSave = nil; setControlsEnabled(true)
                guard let uri = payload["data"] as? String, let data = Self.pngData(from: uri),
                      NSImage(data: data) != nil else {
                    showError("无法生成图表预览，请确认画布中有图形后重试。"); return
                }
                let diagram = NativeDiagram(id: drawingID, title: pending.title, xml: pending.xml, previewPNG: data)
                guard onSave(diagram) else {
                    showError("正文已变化，图表未能保存。请先导出 .drawio 文件保留修改。"); return
                }
                initialXML = pending.xml; isModified = false; lastError = nil
                status.stringValue = "已保存到正文"
                status.textColor = .secondaryLabelColor
                send(["action": "status", "message": "已保存", "modified": false])
                if pending.exit { close() }
            }
        case "exit":
            if let window, windowShouldClose(window) { close() }
        default: break
        }
    }

    static func pngData(from uri: String) -> Data? {
        guard uri.hasPrefix("data:image/png;base64,"), let comma = uri.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(uri[uri.index(after: comma)...]))
    }

    @objc private func titleChanged() { isModified = true }

    @objc private func saveDrawing() {
        guard isReady, pendingSave == nil, !capturingSave, !exportingSource else { return }
        window?.makeFirstResponder(webView) // Finish the diagram name before capturing.
        capturingSave = true; setControlsEnabled(false)
        status.stringValue = "正在保存图表…"
        send(["action": "export", "format": "xml"])
        armTimeout("图源读取超时，修改仍在绘图窗口中，请重试保存。", seconds: 20)
    }

    private func beginSaving(xml: String, closeAfter: Bool, state: [String: Any]) {
        let name = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSave = (xml, name.isEmpty ? "流程图" : name, closeAfter)
        setControlsEnabled(false)
        status.stringValue = "正在生成预览并保存…"
        // draw.io's `width` parameter caps enlargement at 1x. Export with a
        // model-based scale so small diagrams also have a sharp Retina preview.
        let modelBounds = state["modelBounds"] as? [String: Any]
        let bounds = modelBounds ?? state["bounds"] as? [String: Any] ?? [:]
        let viewScale = modelBounds == nil ? (state["scale"] as? Double ?? 1) : 1
        let width = max(1, (bounds["width"] as? Double ?? 400) / max(0.01, viewScale)) + 24
        let height = max(1, (bounds["height"] as? Double ?? 240) / max(0.01, viewScale)) + 24
        let scale = min(8, min(1200 / width, 800 / height))
        send(["action": "export", "format": "png", "xml": xml, "scale": scale, "border": 12,
              "background": "#ffffff"])
        armTimeout("图表预览未能导出，修改仍在绘图窗口中，请重试保存。", seconds: 20)
    }

    @objc private func cancelDrawing() {
        if let window, windowShouldClose(window) { close() }
    }

    @objc private func importDrawing() {
        guard let window, isReady, pendingSave == nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "drawio") ?? .xml, .xml]
        panel.prompt = "导入图表"; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let xml = try String(contentsOf: url, encoding: .utf8)
                titleField.stringValue = url.deletingPathExtension().lastPathComponent
                send(["action": "load", "xml": xml, "autosave": 1])
                isModified = true
            } catch { showError(error.localizedDescription) }
        }
    }

    @objc private func exportDrawing() {
        guard isReady, pendingSave == nil else { return }
        exportingSource = true; setControlsEnabled(false)
        send(["action": "export", "format": "xml"])
        armTimeout("图源导出失败，请重试。", seconds: 20)
    }

    private func saveSource(_ xml: String) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (titleField.stringValue.isEmpty ? "流程图" : titleField.stringValue) + ".drawio"
        panel.allowedContentTypes = [UTType(filenameExtension: "drawio") ?? .xml]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try xml.write(to: url, atomically: true, encoding: .utf8) }
            catch { self?.showError(error.localizedDescription) }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard pendingSave == nil, !capturingSave else { return false }
        guard isModified else { return true }
        let alert = NSAlert()
        alert.messageText = "放弃未保存的图表修改？"
        alert.informativeText = "已保存到正文的版本会保留。"
        let discard = alert.addButton(withTitle: "放弃修改")
        let keep = alert.addButton(withTitle: "继续编辑")
        NativeDialogActions.configure(alert, primary: discard, cancel: keep, destructive: true)
        return NativeDialogActions.runModal(alert, cancel: keep) == .alertFirstButtonReturn
    }

    override func close() {
        guard !hasClosed else { return }
        hasClosed = true
        timeoutTask?.cancel(); resourceTask?.cancel()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "drawio")
        if let window, let parent = window.sheetParent { parent.endSheet(window) }
        super.close()
        onClose()
    }

    func windowWillClose(_ notification: Notification) { close() }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError("无法打开绘图工具：" + error.localizedDescription)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError("绘图工具加载失败：" + error.localizedDescription)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "about:blank" || (url.scheme == DrawioSchemeHandler.scheme && url.host == "editor") {
            decisionHandler(.allow)
        }
        else { decisionHandler(.cancel) }
    }

    private func setControlsEnabled(_ enabled: Bool) {
        importButton.isEnabled = enabled; exportButton.isEnabled = enabled
        saveButton.isEnabled = enabled
    }
    private func showError(_ message: String) {
        timeoutTask?.cancel(); lastError = message
        pendingSave = nil; exportingSource = false; capturingSave = false
        status.stringValue = message; status.textColor = .systemRed
        setControlsEnabled(isReady)
    }
    private func armTimeout(_ message: String, seconds: UInt64) {
        timeoutTask?.cancel()
        timeoutTask = _Concurrency.Task { [weak self] in
            do { try await _Concurrency.Task.sleep(nanoseconds: seconds * 1_000_000_000) }
            catch { return }
            guard let self, !hasClosed else { return }
            pendingSave = nil; exportingSource = false; capturingSave = false; showError(message)
        }
    }
}
