import AppKit
import SwiftUI

/// The source document and UTF-16 range are captured before focus leaves the editor.
@MainActor
final class AISelectionTarget {
    weak var editor: NativeTextView?
    private weak var webEditor: MilkdownWebView?
    private var webSelection: MilkdownSelection?
    private var webEpoch: UUID?
    private var postWriteRevision: Int?
    private let identity: UUID
    private let range: NSRange
    private let original: String
    let text: String

    init?(editor: NativeTextView) {
        let range = editor.selectedRange(), source = editor.string as NSString
        guard editor.isEditable, range.length > 0, range.location != NSNotFound,
              NSMaxRange(range) <= source.length else { return nil }
        self.editor = editor; identity = editor.documentIdentity
        self.range = range; original = editor.string; text = source.substring(with: range)
    }

    init?(editor: MilkdownWebView, selection: MilkdownSelection) {
        guard !editor.isReadOnly, selection.from < selection.to, let id = editor.documentIdentity else { return nil }
        webEditor = editor; webSelection = selection; webEpoch = editor.epoch
        identity = id; range = NSRange(location: selection.plainFrom, length: max(0, selection.plainTo - selection.plainFrom))
        original = editor.document.plainText; text = selection.text
    }

    func applyAsync(_ text: String, inserting: Bool) async -> Bool {
        guard let webEditor else { return apply(text, inserting: inserting) }
        guard let selection = webSelection, let webEpoch, webEditor.documentIdentity == identity,
              webEditor.epoch == webEpoch, !webEditor.isReadOnly else { return false }
        do {
            var payload: [String: Any] = ["documentID": identity.uuidString,
                "epoch": webEpoch.uuidString, "revision": selection.revision, "from": selection.from,
                "to": selection.to, "text": text, "inserting": inserting]
            let content = (inserting ? "\n" : "") + text
            if let fragment = DocumentExternalClipboardCodec.fragment(fromMarkdown: content,
                destinationKind: DocumentTextCodec.kind(selection.style.blockToken)) {
                payload["doc"] = try webEditor.object(webEditor.encode(fragment.document))
            }
            return try await webEditor.call("applySelection", payload) as? Bool == true
        } catch { return false }
    }

    @discardableResult
    func apply(_ text: String, inserting: Bool) -> Bool {
        guard let editor, editor.isEditable, editor.documentIdentity == identity,
              editor.string == original, !editor.hasMarkedText() else { return false }
        let replacement = inserting ? NSRange(location: NSMaxRange(range), length: 0) : range
        editor.breakUndoCoalescing()
        editor.window?.makeFirstResponder(editor)
        editor.insertText(inserting ? "\n" + text : text, replacementRange: replacement)
        editor.breakUndoCoalescing()
        return true
    }

    /// 回写成功后记录当时的文档版本：撤销前校验「写入之后没有再改过」。
    func noteApplied() { postWriteRevision = webEditor?.revision }

    /// 撤销本次写入：触发编辑器自身的撤销栈；写入之后文档又被改过（版本对不上）
    /// 则拒绝，交给用户在编辑器里手动 ⌘Z，绝不盲退到未知状态。
    func undoWriteAsync() async -> Bool {
        if let webEditor {
            guard let webEpoch, webEditor.documentIdentity == identity, webEditor.epoch == webEpoch,
                  let postWriteRevision, webEditor.revision == postWriteRevision else { return false }
            do { return try await webEditor.call("command", ["name": "undo", "payload": [:]]) as? Bool == true }
            catch { return false }
        }
        guard let editor else { return false }
        editor.undoManager?.undo()
        return true
    }
}

@MainActor
final class AISelectionWindowController: NSObject, NSWindowDelegate {
    static let shared = AISelectionWindowController()
    var makeClient: (() -> AIConversationClient?)?
    var undoAction: ((AIActionReceipt) -> Void)?
    var canUndoAction: ((AIActionReceipt) -> Bool)?
    var isAvailable: Bool { makeClient != nil }
    private(set) var panel: NSPanel?
    private(set) var model: AIConversationModel?
    /// 与日期/属性浮层共用一套收起规则；窗口关闭时一并注销，避免注册表留残项。
    private var interactionRegistration: UUID?
    private var escapeRegistration: UUID?
    /// 切到别的页面时窗口只是隐藏，回来要原样恢复。
    private var pageHidden = false
    #if DEBUG
    var actionObservation: ((String, NSView) -> Void)?
    #endif

    func present(editor: NativeTextView, intent: AIConversationPreset = .polish) {
        guard let target = AISelectionTarget(editor: editor) else { return }
        present(target: target, owner: editor.window, intent: intent)
    }

    func present(editor: MilkdownWebView, selection: MilkdownSelection,
                 intent: AIConversationPreset = .polish) {
        guard let target = AISelectionTarget(editor: editor, selection: selection) else { return }
        present(target: target, owner: editor.window, intent: intent)
    }

    private func present(target: AISelectionTarget, owner: NSWindow?, intent: AIConversationPreset) {
        guard let client = makeClient?() else { return }
        close()
        let model = AIConversationModel(scene: .selection, directory: client.directory)
        self.model = model
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = intent.selectionWindowTitle; panel.level = .floating
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.isMovableByWindowBackground = true
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.minSize = NSSize(width: 440, height: 360); panel.delegate = self
        let generate = client.generator(for: model)
        let content = AISelectionConversationView(model: model, generate: generate,
            target: target, onAdopt: { [weak self] in self?.close() },
            undoAction: undoAction, canUndoAction: canUndoAction)
            .workfollowNativeTheme()
        #if DEBUG
        panel.contentView = NSHostingView(rootView: AnyView(content.environment(\.workflowActionObservation, actionObservation)))
        #else
        panel.contentView = NSHostingView(rootView: AnyView(content))
        #endif
        if let owner {
            panel.setFrameOrigin(NSPoint(x: owner.frame.midX - 320, y: owner.frame.midY - 280))
        } else { panel.center() }
        self.panel = panel
        registerDismissals(panel)
        panel.makeKeyAndOrderFront(nil)
        model.ask(intent, source: .init(kind: "selection", title: "选中文字", content: target.text), using: generate)
    }

    /// 这个窗口绑定的是某个编辑器里的一段选区，切页、切笔记、点外部或按 Esc
    /// 之后留着既挡页面也应用不了结果：和其它弹层走同一套收起规则。
    /// 但它是有流式生成和历史的会话窗，切到别的 App 时不能被"失焦清场"收掉。
    private func registerDismissals(_ panel: NSPanel) {
        interactionRegistration = PopupInteractionRegistry.shared.register(window: panel,
            contains: { [weak panel] event in
                var current = event.window
                while let window = current {
                    if window === panel { return true }
                    current = window.parent
                }
                return false
            }, dismiss: { [weak self] reason in
                // 会话窗不是锚在控件上的弹层：应用失焦、key window 归属变化、
                // 同族分支切换都不该销毁它，只有点浮窗以外才收起。
                // 切到别的页面时窗口只是隐藏，这期间一律忽略。
                guard reason == .outsideClick, self?.pageHidden != true else { return }
                self?.close()
            })
        if let contentView = panel.contentView {
            escapeRegistration = PopupEscapeRegistry.shared.register(view: contentView,
                depth: PopupEscapeRank.shell) { [weak self] in
                guard self?.pageHidden != true else { return }
                self?.close()
            }
        }
    }

    private func unregisterDismissals() {
        if let id = interactionRegistration { PopupInteractionRegistry.shared.unregister(id) }
        if let id = escapeRegistration { PopupEscapeRegistry.shared.unregister(id) }
        interactionRegistration = nil; escapeRegistration = nil
    }

    /// 切到别的页面：只把窗口收起来，会话、流式生成和结果都留着。
    /// 注册保持不动（注销再注册会被 orderOut 引起的 key window 变化误关），
    /// 隐藏期间由 pageHidden 让所有收起原因落空。
    func hideForPageSwitch() {
        guard let panel, panel.isVisible else { return }
        pageHidden = true
        panel.orderOut(nil)
    }

    /// 切回笔记页：同一个窗口、同一份会话原样恢复，不重新生成。
    /// 必须重新成为 key window，否则恢复后到达的 key window 变化会把这个
    /// 独立浮窗判为"别的窗口族"而收掉（与 present 的落点保持一致）。
    func restoreIfNeeded() {
        guard pageHidden, let panel else { return }
        pageHidden = false
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        pageHidden = false
        unregisterDismissals()
        model?.stop(); model?.attachments.discard(); panel?.close(); panel = nil; model = nil
    }
    func windowWillClose(_ notification: Notification) {
        pageHidden = false
        unregisterDismissals()
        model?.stop(); model?.attachments.discard(); model = nil; panel = nil
    }
}

extension AIConversationPreset {
    /// 选中浮窗的标题（工具条按钮/右键菜单/面板标题共用一套叫法）。
    var selectionWindowTitle: String {
        switch self {
        case .polish: "AI 润色"
        case .translate: "AI 翻译"
        case .organize: "AI 总结"
        case .extract: "AI 提取"
        }
    }
}

private struct AISelectionConversationView: View {
    @ObservedObject var model: AIConversationModel
    let generate: AIConversationModel.Generate
    let target: AISelectionTarget
    let onAdopt: () -> Void
    let undoAction: ((AIActionReceipt) -> Void)?
    let canUndoAction: ((AIActionReceipt) -> Bool)?
    @Environment(\.workfollowBackgroundTheme) private var backgroundTheme
    @Environment(\.colorScheme) private var colorScheme
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            AIConversationView(model: model, generate: generate, adopt: { text, inserting in
                _Concurrency.Task { @MainActor in
                    if await target.applyAsync(text, inserting: inserting) { onAdopt() }
                    else { error = "原文已改变或已切换笔记，请重新选择文字后生成。" }
                }
            }, undoAction: undoAction, canUndoAction: canUndoAction)
            if let error { Text(error).font(WFType.caption).foregroundStyle(WFColors.danger).padding(12) }
        }
        .background {
            ZStack {
                WFGlassScrim(opacity: 0.78)
                WFGlassSurface(shape: Rectangle(), fallback: backgroundTheme.popupFill(for: colorScheme))
            }
        }
        .hidesSystemFocusEffect()
    }
}
