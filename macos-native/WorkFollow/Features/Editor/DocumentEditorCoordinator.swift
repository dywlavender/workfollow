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
    private var committedTrailingIndentLevel = 0
    private var committedTrailingListStart: Int?
    private var committedTrailingAlign: DocumentAlignment?
    private(set) var decodeCount = 0
    /// 宿主工具条/占位文案观察的句柄；编辑器每次文本变化都回写实时空状态。
    weak var handle: DocumentEditorHandle?

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
            prepareForDocumentChange(in: textView)
            textView.resetDocumentInteraction(for: documentID)
            self.documentID = documentID
            editorState.bind(to: documentID)
            // Replacing storage emits selection callbacks synchronously; do
            // not let that transient end-of-document range replace the reset.
            let incomingSelection = editorState.selectedRange
            textView.typingAttributes = textView.paragraphAttributes()
            self.document = document
            textView.textStorage?.setAttributedString(textView.renderDocument(document))
            textView.setSelectedRange(incomingSelection)
            // 文末空段落的级别只能从模型带回输入属性（它的样式在文档里没有字符可承载），
            // 否则切回来接着在文末输入会退回正文。
            textView.seedTrailingParagraphKind(Self.trailingBlockKind(of: document),
                indentLevel: document.blocks.last?.indentLevel ?? 0, listStart: document.blocks.last?.listStart,
                align: document.blocks.last?.align)
            didLoadDocument(in: textView, reparseInline: true)
        } else if self.document != document {
            if Self.sameContent(self.document, document) {
                // 仅检查项元数据（提醒/完成时间）变化：正文投影没变，不重建
                // text storage，保住光标、选区、输入法组合串与提醒面板。
                self.document = document
                textView.needsDisplay = true
            } else if !textView.hasMarkedText() {
                let selection = textView.selectedRange()
                self.document = document
                textView.textStorage?.setAttributedString(textView.renderDocument(document))
                let location = min(selection.location, (document.plainText as NSString).length)
                let length = min(selection.length, (document.plainText as NSString).length - location)
                textView.setSelectedRange(NSRange(location: location, length: length))
                didLoadDocument(in: textView)
            }
        }
        self.onDocumentChange = onDocumentChange
        self.onEscape = onEscape
        self.onEditingChanged = onEditingChanged
        textView.onEscape = onEscape
        textView.onEditingChanged = onEditingChanged
        // 文末空段的级别供装饰层常驻绘制（它没有字符，主循环看不见）。
        textView.displayedTrailingBlock = Self.trailingBlockKind(of: document)
        textView.displayedTrailingIndentLevel = document.blocks.last?.indentLevel ?? 0
        textView.displayedTrailingListStart = document.blocks.last?.listStart
        textView.displayedTrailingAlign = document.blocks.last?.align
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
        if let native = textView as? NativeTextView, native.diagram(at: charIndex) != nil {
            native.editDocumentDiagram(at: charIndex)
            return
        }
        if let native = textView as? NativeTextView, native.table(at: charIndex) != nil {
            native.editDocumentTable(at: charIndex)
            return
        }
        if let native = textView as? NativeTextView, native.formula(at: charIndex) != nil {
            native.editDocumentFormula(at: charIndex)
            return
        }
        guard let storage = textView.textStorage, charIndex < storage.length,
              let data = storage.attribute(DocumentTextCodec.attachmentKey, at: charIndex, effectiveRange: nil) as? Data,
              let attachment = try? JSONDecoder().decode(NativeAttachment.self, from: data) else { return }
        // 粘贴图片是 data URL 附件（不是磁盘文件）：双击开预览窗，而不是
        // 交给 NSWorkspace 静默失败（`url(for:)` 对 data URL 返回 nil）。
        if let image = DocumentTextCodec.pastedImage(from: attachment) {
            ImagePreviewWindowController.present(image: image, name: attachment.name)
            return
        }
        guard let url = NativeAttachmentFiles.url(for: attachment) else { return }
        NSWorkspace.shared.open(url)
    }

    func flushPendingComposition(in textView: NativeTextView) {
        let trailing = textView.pendingTrailingBlock ?? Self.trailingBlockKind(of: document)
        if !textView.hasMarkedText(), textView.documentCommandCommit == nil,
           committedStorageRevision == textView.storageRevision,
           committedTrailingBlock == trailing,
           committedTrailingIndentLevel == textView.trailingIndentLevel,
           committedTrailingListStart == textView.trailingListStart,
           committedTrailingAlign == textView.trailingAlign { return }
        if textView.hasMarkedText() {
            textView.unmarkText()
        }
        commit(textView, force: true)
    }

    func prepareForDocumentChange(in textView: NativeTextView) {
        flushPendingComposition(in: textView)
        if textView.window?.firstResponder === textView {
            textView.window?.makeFirstResponder(nil)
        }
    }

    /// 设置页改了正文字号：按当前模型重排，保留选区、滚动位置与文末段落级别。
    func reloadBodyTypography(in textView: NativeTextView) {
        flushPendingComposition(in: textView)
        let selection = textView.selectedRange()
        let scrollOrigin = textView.enclosingScrollView?.contentView.bounds.origin
        let length = (document.plainText as NSString).length
        textView.font = .systemFont(ofSize: EditorPreferences.bodyFontSize)
        textView.textStorage?.setAttributedString(textView.renderDocument(document))
        let location = min(selection.location, length)
        let selectedLength = min(selection.length, length - location)
        textView.setSelectedRange(NSRange(location: location, length: selectedLength))
        if selectedLength == 0, let storage = textView.textStorage, storage.length > 0 {
            // 光标处接着输入的样式跟住所在段落（标题/列表/加粗），不要退回纯正文。
            let probe = location > 0 ? location - 1 : 0
            textView.typingAttributes = storage.attributes(at: probe, effectiveRange: nil)
        }
        textView.seedTrailingParagraphKind(Self.trailingBlockKind(of: document),
            indentLevel: document.blocks.last?.indentLevel ?? 0,
            listStart: document.blocks.last?.listStart,
            align: document.blocks.last?.align)
        if let scrollView = textView.enclosingScrollView, let scrollOrigin {
            scrollView.contentView.scroll(to: scrollOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        didLoadDocument(in: textView)
    }

    func didLoadDocument(in textView: NativeTextView, reparseInline: Bool = false) {
        handle?.syncLiveTextIsEmpty(textView.string.isEmpty)
        committedStorageRevision = textView.storageRevision
        committedTrailingBlock = textView.pendingTrailingBlock ?? Self.trailingBlockKind(of: document)
        committedTrailingIndentLevel = textView.trailingIndentLevel
        committedTrailingListStart = textView.trailingListStart
        committedTrailingAlign = textView.trailingAlign
        guard reparseInline else { return }
        // 渲染期解析（2026-10-17 口径）：加载/切换文档后把已有字面标记渲染成富文本。
        // 放到下一轮 runloop，避免在 SwiftUI update 过程中改模型。
        let identity = textView.documentIdentity
        DispatchQueue.main.async { [weak textView] in
            guard let textView, textView.documentIdentity == identity else { return }
            textView.reparseInlineMarkdown(registeringUndo: false)
        }
    }

    func detach(_ textView: NativeTextView) {
        flushPendingComposition(in: textView)
        textView.resetDocumentInteraction(for: UUID())
        textView.delegate = nil
        textView.onEscape = nil
        textView.onCancelTransient = nil
        textView.onEditingChanged = nil
        textView.onSelectionChanged = nil
        textView.onLiveTextChange = nil
        textView.profile = DocumentProfile()
    }

    private func commit(_ textView: NSTextView, force: Bool) {
        guard force || !textView.hasMarkedText() else { return }
        // 文末空段的级别：优先用输入待定（光标在行上的最新意图），光标不在时
        // 回退到模型当前值——否则在别处编辑一次，文末列表就会丢级别。
        let pending = (textView as? NativeTextView)?.pendingTrailingBlock
        let native = textView as? NativeTextView
        let trailingIndent = native?.trailingIndentLevel ?? document.blocks.last?.indentLevel ?? 0
        let trailingStart = native != nil ? native?.trailingListStart : document.blocks.last?.listStart
        let trailingAlign = native != nil ? native?.trailingAlign : document.blocks.last?.align
        decodeCount += 1
        let updated = DocumentTextCodec.decode(textView.attributedString(), preserving: document,
                                              trailing: pending ?? native?.displayedTrailingBlock ?? Self.trailingBlockKind(of: document),
                                              trailingIndentLevel: trailingIndent, trailingListStart: trailingStart,
                                              trailingAlign: trailingAlign)
        if let native = textView as? NativeTextView {
            committedStorageRevision = native.storageRevision
            committedTrailingBlock = pending ?? Self.trailingBlockKind(of: updated)
            committedTrailingIndentLevel = trailingIndent
            committedTrailingListStart = trailingStart
            committedTrailingAlign = trailingAlign
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

    /// 两个文档的编辑器投影是否一致。清单元数据不参与渲染，只有它变化时
    /// 不应重建正文。
    static func sameContent(_ lhs: NativeDocument, _ rhs: NativeDocument) -> Bool {
        let left = lhs.blocks
        let right = rhs.blocks
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { lhs, rhs in
            lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.runs == rhs.runs
                && lhs.indentLevel == rhs.indentLevel && lhs.listStart == rhs.listStart
                && lhs.align == rhs.align
        }
    }

    /// 模型里最后一个块没有字符时，它的段落类型只存在于"输入属性"这一层。
    private static func trailingBlockKind(of document: NativeDocument) -> DocumentBlockKind? {
        guard let last = document.blocks.last, last.kind != .paragraph,
              last.runs.allSatisfy({ $0.text.isEmpty }) else { return nil }
        return last.kind
    }
}
