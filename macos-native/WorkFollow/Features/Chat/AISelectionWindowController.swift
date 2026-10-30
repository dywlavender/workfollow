import AppKit
import SwiftUI

/// The source document and UTF-16 range are captured before focus leaves the editor.
@MainActor
final class AISelectionTarget {
    weak var editor: NativeTextView?
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
    #if DEBUG
    var actionObservation: ((String, NSView) -> Void)?
    #endif

    func present(editor: NativeTextView) {
        guard let client = makeClient?(), let target = AISelectionTarget(editor: editor) else { return }
        close()
        let model = AIConversationModel(scene: .selection, directory: client.directory)
        self.model = model
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "AI 润色"; panel.level = .floating
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.isMovableByWindowBackground = true
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
        if let owner = editor.window {
            panel.setFrameOrigin(NSPoint(x: owner.frame.midX - 320, y: owner.frame.midY - 280))
        } else { panel.center() }
        self.panel = panel; panel.makeKeyAndOrderFront(nil)
        model.ask(.polish, source: .init(kind: "selection", title: "选中文字", content: target.text), using: generate)
    }

    func close() { model?.stop(); model?.attachments.discard(); panel?.close(); panel = nil; model = nil }
    func windowWillClose(_ notification: Notification) { model?.stop(); model?.attachments.discard(); model = nil; panel = nil }
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
                if target.apply(text, inserting: inserting) { onAdopt() }
                else { error = "原文已改变或已切换笔记，请重新选择文字后生成。" }
            }, undoAction: undoAction, canUndoAction: canUndoAction)
            if let error { Text(error).font(WFType.caption).foregroundStyle(WFColors.danger).padding(12) }
        }
        .background(backgroundTheme.popupFill(for: colorScheme)).hidesSystemFocusEffect()
    }
}
