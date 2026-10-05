import AppKit
import SwiftUI

@MainActor
final class DocumentEditorCoordinator: NSObject, NSTextViewDelegate {
    private(set) var documentID: UUID
    private(set) var editorState: DocumentEditorState
    private var document: NativeDocument
    private var onDocumentChange: (NativeDocument) -> Void
    private var onEscape: () -> InspectorEscapeEffect
    private var onEditingChanged: (Bool) -> Void
    private var committedStorageRevision: Int?
    private var committedTrailingBlock: DocumentBlockKind?
    private(set) var decodeCount = 0

    init(documentID: UUID, document: NativeDocument,
         onDocumentChange: @escaping (NativeDocument) -> Void,
         onEscape: @escaping () -> InspectorEscapeEffect,
         onEditingChanged: @escaping (Bool) -> Void) {
        self.documentID = documentID
        self.editorState = DocumentEditorState(documentID: documentID)
        self.document = document
        self.onDocumentChange = onDocumentChange
        self.onEscape = onEscape
        self.onEditingChanged = onEditingChanged
    }

    func update(_ textView: NativeTextView, documentID: UUID, document: NativeDocument,
                onDocumentChange: @escaping (NativeDocument) -> Void,
                onEscape: @escaping () -> InspectorEscapeEffect,
                onEditingChanged: @escaping (Bool) -> Void) {
        if self.documentID != documentID {
            flushPendingComposition(in: textView)
            if textView.window?.firstResponder === textView {
                textView.window?.makeFirstResponder(nil)
            }
            textView.resetDocumentInteraction(for: documentID)
            self.documentID = documentID
            editorState.bind(to: documentID)
            textView.typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
            self.document = document
            textView.textStorage?.setAttributedString(DocumentTextCodec.render(document))
            textView.setSelectedRange(editorState.selectedRange)
            // 文末空段落的级别只能从模型带回输入属性（它的样式在文档里没有字符可承载），
            // 否则切回来接着在文末输入会退回正文。
            textView.seedTrailingParagraphKind(Self.trailingBlockKind(of: document))
            didLoadDocument(in: textView)
        } else if self.document != document,
                  !textView.hasMarkedText() {
            let selection = textView.selectedRange()
            self.document = document
            textView.textStorage?.setAttributedString(DocumentTextCodec.render(document))
            let location = min(selection.location, (document.plainText as NSString).length)
            let length = min(selection.length, (document.plainText as NSString).length - location)
            textView.setSelectedRange(NSRange(location: location, length: length))
            didLoadDocument(in: textView)
        }
        self.onDocumentChange = onDocumentChange
        self.onEscape = onEscape
        self.onEditingChanged = onEditingChanged
        textView.onEscape = onEscape
        textView.onEditingChanged = onEditingChanged
        // 文末空段的级别供装饰层常驻绘制（它没有字符，主循环看不见）。
        textView.displayedTrailingBlock = Self.trailingBlockKind(of: document)
    }


    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        commit(textView, force: false)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? NativeTextView else { return }
        editorState.updateSelection(textView.selectedRange())
        // 光标停/离开文末空段时同步待定级别（标题换行延续、切回不丢级别）。
        textView.syncPendingTrailingBlock()
        textView.refreshSelectionToolbar()
        // 活动行标记（标题角标 / 空行"+"）跟着光标走：沟槽在文本区外，
        // 选区变化不会自动把它标脏，这里显式重绘。
        textView.needsDisplay = true
        textView.onSelectionChanged?()
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        (textView as? NativeTextView)?.profile.onOpenLink?(String(describing: link)) ?? false
    }

    func textView(_ textView: NSTextView, doubleClickedOn cell: NSTextAttachmentCellProtocol,
                  in cellFrame: NSRect, at charIndex: Int) {
        guard let storage = textView.textStorage, charIndex < storage.length,
              let data = storage.attribute(DocumentTextCodec.attachmentKey, at: charIndex, effectiveRange: nil) as? Data,
              let attachment = try? JSONDecoder().decode(NativeAttachment.self, from: data),
              let url = NativeAttachmentFiles.url(for: attachment) else { return }
        NSWorkspace.shared.open(url)
    }

    func flushPendingComposition(in textView: NativeTextView) {
        let trailing = textView.pendingTrailingBlock ?? Self.trailingBlockKind(of: document)
        if !textView.hasMarkedText(), textView.documentCommandCommit == nil,
           committedStorageRevision == textView.storageRevision,
           committedTrailingBlock == trailing { return }
        if textView.hasMarkedText() {
            textView.unmarkText()
        }
        commit(textView, force: true)
    }

    func didLoadDocument(in textView: NativeTextView) {
        committedStorageRevision = textView.storageRevision
        committedTrailingBlock = textView.pendingTrailingBlock ?? Self.trailingBlockKind(of: document)
    }

    func detach(_ textView: NativeTextView) {
        flushPendingComposition(in: textView)
        textView.resetDocumentInteraction(for: UUID())
        textView.delegate = nil
        textView.onEscape = nil
        textView.onEditingChanged = nil
        textView.onSelectionChanged = nil
        textView.profile = DocumentProfile()
    }

    private func commit(_ textView: NSTextView, force: Bool) {
        guard force || !textView.hasMarkedText() else { return }
        // 文末空段的级别：优先用输入待定（光标在行上的最新意图），光标不在时
        // 回退到模型当前值——否则在别处编辑一次，文末列表就会丢级别。
        let pending = (textView as? NativeTextView)?.pendingTrailingBlock
        decodeCount += 1
        let updated = DocumentTextCodec.decode(textView.attributedString(), preserving: document,
                                              trailing: pending ?? Self.trailingBlockKind(of: document))
        if let native = textView as? NativeTextView {
            committedStorageRevision = native.storageRevision
            committedTrailingBlock = pending ?? Self.trailingBlockKind(of: updated)
        }
        if let commit = (textView as? NativeTextView)?.documentCommandCommit {
            document = updated
            commit(updated)
            return
        }
        guard updated != document else { return }
        document = updated
        onDocumentChange(updated)
    }

    /// 模型里最后一个块没有字符时，它的段落类型只存在于"输入属性"这一层。
    private static func trailingBlockKind(of document: NativeDocument) -> DocumentBlockKind? {
        guard let last = document.blocks.last, last.kind != .paragraph,
              last.runs.allSatisfy({ $0.text.isEmpty }) else { return nil }
        return last.kind
    }
}
