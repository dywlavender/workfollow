import AppKit
import SwiftUI

/// 当前选区的样式：段落类型 + 行内标记。
///
/// 工具条靠它显示"现在是什么样式"——原版每个按钮都有
/// `selected: _active(attribute)`（`document_editor_toolbar.dart:148,168,177`），
/// 原生此前没有这一层，按钮永远是灰的，用户点完看不出到底生效没有。
struct DocumentSelectionStyle: Equatable {
    var blockToken: String = DocumentTextCodec.blockToken(.paragraph)
    /// 选区里**每个** run 都带的标记（空选区取输入属性）。只有全选都是粗体才算
    /// 粗体激活——与原版 `isActive` 的口径一致。
    var marks: Set<DocumentMark> = []

    func isBlock(_ kind: DocumentBlockKind?) -> Bool {
        guard let kind else { return false }
        return blockToken == DocumentTextCodec.blockToken(kind)
    }

    func has(_ mark: DocumentMark?) -> Bool {
        guard let mark else { return false }
        return marks.contains(mark)
    }
}

/// Host-produced content, deliberately independent of Task/Note models.
struct EditorReference {
    let title: String
    let target: String
}

@MainActor
final class DocumentEditorHandle: ObservableObject {
    weak var textView: NativeTextView?
    /// 工具条据此显示激活态；选区变化与每次格式化后都会重算。
    @Published private(set) var style = DocumentSelectionStyle()

    func format(_ command: DocumentFormatCommand) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.applyFormat(command)
        refreshStyle()
    }

    /// 从当前选区重算样式。空选区读 `typingAttributes`——那正是"接下来输入会是什么
    /// 样式"，所以空文档里点段落格式也能在工具条上看到反馈（原版同理）。
    func refreshStyle() {
        guard let textView, let storage = textView.textStorage else {
            style = DocumentSelectionStyle()
            return
        }
        let range = textView.selectedRange()
        let sample = range.length == 0
            ? NSAttributedString(string: " ", attributes: textView.typingAttributes)
            : storage.attributedSubstring(from: range)
        let next = DocumentTextCodec.style(of: sample)
        if next != style { style = next }
    }

    func focusEditor() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    func focusEnd() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    func editLink() { textView?.editDocumentLink(nil); refreshStyle() }
    func removeLink() { textView?.removeDocumentLink(nil); refreshStyle() }
    func insertAttachment() { textView?.insertDocumentAttachment(nil); refreshStyle() }
    func insertTime(format: String) { textView?.window?.makeFirstResponder(textView); textView?.insertDocumentTime(format: format); refreshStyle() }
    func insertDivider() { textView?.window?.makeFirstResponder(textView); textView?.insertDocumentDivider(); refreshStyle() }
    func insertReference(_ reference: EditorReference) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        let content = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [
            DocumentRun(text: reference.title, marks: [.link(reference.target)])
        ])])
        textView.insertText(DocumentTextCodec.render(content), replacementRange: textView.selectedRange())
        textView.typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
    }

    /// Reference command with host fields sharing the document's undo/redo.
    @discardableResult
    func insertReference(_ reference: EditorReference,
                         commit: @escaping (NativeDocument) -> Void,
                         undoCommit: @escaping (NativeDocument) -> Void) -> Bool {
        guard let textView else { return false }
        textView.window?.makeFirstResponder(textView)
        let range = textView.selectedRange()
        let content = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [
            DocumentRun(text: reference.title, marks: [.link(reference.target)])
        ])])
        let value = DocumentTextCodec.render(content)
        guard textView.replaceDocumentContent(value, range: range,
            selection: NSRange(location: range.location + value.length, length: 0),
            commit: commit, inverseCommit: undoCommit) else { return false }
        textView.typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
        refreshStyle()
        return true
    }
}

/// The decoration lane lives before the host's content origin. TextKit needs
/// it inside its drawable bounds, but it must not consume host text width.
enum DocumentEditorGeometry {
    static let decorationLane: CGFloat = 20
    static let listTextIndent: CGFloat = 16
    static let quoteTextIndent: CGFloat = 16
    static let structuredParagraphSpacing: CGFloat = 2
    static let quoteRuleInset: CGFloat = 4
    static let quoteRuleWidth: CGFloat = 2
}

struct DocumentEditor: View {
    let documentID: UUID
    let document: NativeDocument
    let onDocumentChange: (NativeDocument) -> Void
    let onEscape: () -> InspectorEscapeEffect
    let onEditingChanged: (Bool) -> Void
    var profile = DocumentProfile()
    var contentSized = false
    var handle: DocumentEditorHandle?
    var decorationVisibleMinX: CGFloat = 0

    var body: some View {
        DocumentEditorContent(documentID: documentID, document: document,
                              onDocumentChange: onDocumentChange, onEscape: onEscape,
                              onEditingChanged: onEditingChanged, profile: profile,
                                  contentSized: contentSized, handle: handle,
                                  decorationVisibleMinX: decorationVisibleMinX)
            .padding(.leading, -DocumentEditorGeometry.decorationLane)
    }
}

private struct DocumentEditorContent: NSViewRepresentable {
    let documentID: UUID
    let document: NativeDocument
    let onDocumentChange: (NativeDocument) -> Void
    let onEscape: () -> InspectorEscapeEffect
    let onEditingChanged: (Bool) -> Void
    var profile = DocumentProfile()
    var contentSized = false
    var handle: DocumentEditorHandle?
    var decorationVisibleMinX: CGFloat = 0

    func makeCoordinator() -> DocumentEditorCoordinator {
        DocumentEditorCoordinator(documentID: documentID, document: document,
                                  onDocumentChange: onDocumentChange,
                                  onEscape: onEscape,
                                  onEditingChanged: onEditingChanged)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = !contentSized
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        // NSScrollView draws the system focus ring around the whole editor
        // while its text view is first responder; the design keeps editing
        // affordances to the caret and selection only.
        scrollView.focusRingType = .none

        let textView = NativeTextView(frame: .zero, textContainer: nil)
        textView.decorationVisibleMinX = decorationVisibleMinX
        textView.documentIdentity = documentID
        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        textView.seedTrailingParagraphKind(document.blocks.last.flatMap { block in
            block.runs.allSatisfy { $0.text.isEmpty } ? block.kind : nil
        })
        textView.onEscape = onEscape
        textView.onEditingChanged = onEditingChanged
        textView.onSelectionChanged = { [weak handle] in handle?.refreshStyle() }
        textView.profile = profile
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        handle?.textView = textView
        handle?.refreshStyle()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NativeTextView else { return }
        textView.decorationVisibleMinX = decorationVisibleMinX
        textView.profile = profile
        handle?.textView = textView
        textView.onSelectionChanged = { [weak handle] in handle?.refreshStyle() }
        context.coordinator.update(textView, documentID: documentID, document: document,
                                   onDocumentChange: onDocumentChange,
                                   onEscape: onEscape,
                                   onEditingChanged: onEditingChanged)
        // Refresh after model/selection rebind, not from the outgoing document.
        handle?.refreshStyle()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView,
                      context: Context) -> CGSize? {
        guard contentSized, let width = proposal.width, width > 0,
              let textView = nsView.documentView as? NativeTextView,
              let container = textView.textContainer,
              let layout = textView.textLayoutManager else { return nil }
        textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        textView.resizeDocumentDividers()
        // 容器宽 = 视图宽 − 左右 textContainerInset（与 widthTracksTextView 的
        // 自动口径一致），否则行宽会超出视图右缘 20pt。
        container.containerSize = NSSize(
            width: max(1, width - textView.textContainerInset.width * 2),
            height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: NSRect(origin: .zero, size: container.containerSize))
        let bottom = layout.usageBoundsForTextContainer.maxY
        let height = max(48, ceil(bottom + textView.textContainerInset.height * 2 + 8))
        textView.revealCaretInHostAfterLayout()
        return CGSize(width: width, height: height)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: DocumentEditorCoordinator) {
        guard let textView = scrollView.documentView as? NativeTextView else { return }
        coordinator.detach(textView)
    }
}
