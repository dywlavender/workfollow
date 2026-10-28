import AppKit

extension NativeTextView {
    func listEditingDocument() -> NativeDocument {
        DocumentTextCodec.decode(attributedString(), preserving: .empty,
            trailing: pendingTrailingBlock ?? displayedTrailingBlock,
            trailingIndentLevel: trailingIndentLevel, trailingListStart: trailingListStart)
    }

    func setCurrentListMetadata(indentLevel: Int, listStart: Int?) {
        var document = listEditingDocument()
        guard let index = selectedListParagraphs(in: document).min(), document.blocks[index].kind.isList else { return }
        document.blocks[index].indentLevel = min(8, max(0, indentLevel))
        document.blocks[index].listStart = document.blocks[index].kind == .ordered ? listStart : nil
        applyListDocument(document, selection: selectedRange(), typing: listTypingAttributes(for: document.blocks[index]))
    }

    private func selectedListParagraphs(in document: NativeDocument) -> Set<Int> {
        let selection = selectedRange()
        let end = selection.length == 0 ? selection.location : NSMaxRange(selection) - 1
        var offset = 0
        var indices = Set<Int>()
        for (index, block) in document.blocks.enumerated() {
            let length = (block.plainText as NSString).length
            if offset <= end, offset + length >= selection.location { indices.insert(index) }
            offset += length + 1
        }
        return indices
    }

    @discardableResult
    func changeListIndent(by delta: Int) -> Bool {
        guard isEditable, !hasMarkedText() else { return false }
        let document = listEditingDocument()
        let selected = selectedListParagraphs(in: document)
        guard selected.contains(where: { document.blocks[$0].kind.isList }) else { return false }
        let changed = DocumentListStructure.shifted(document.blocks, selected: selected, by: delta)
        guard changed != document.blocks else { return true }
        let active = selected.min() ?? 0
        let typing = listTypingAttributes(for: changed[active])
        applyListDocument(NativeDocument(blocks: changed), selection: selectedRange(), typing: typing)
        dismissSlash()
        dismissTagCompletion()
        return true
    }

    @discardableResult
    func outdentListAtParagraphStart() -> Bool {
        guard isEditable, !hasMarkedText(), selectedRange().length == 0 else { return false }
        let text = string as NSString
        let caret = selectedRange().location
        guard caret == 0 || (caret <= text.length && text.character(at: caret - 1) == 0x0A) else { return false }
        let document = listEditingDocument()
        guard let index = selectedListParagraphs(in: document).min(),
              document.blocks[index].kind.isList, document.blocks[index].indentLevel > 0 else { return false }
        return changeListIndent(by: -1)
    }

    @discardableResult
    func handleListNewline() -> Bool {
        guard isEditable, !hasMarkedText() else { return false }
        let document = listEditingDocument()
        guard let index = selectedListParagraphs(in: document).min(),
              document.blocks[index].kind.isList else { return false }
        let current = document.blocks[index]
        if current.plainText.isEmpty, selectedRange().length == 0 {
            if current.indentLevel > 0 { return changeListIndent(by: -1) }
            var blocks = document.blocks
            blocks[index].kind = .paragraph
            applyListDocument(NativeDocument(blocks: blocks), selection: selectedRange(),
                              typing: listTypingAttributes(for: blocks[index]))
            return true
        }

        let source = NSMutableAttributedString(attributedString: attributedString())
        let selection = selectedRange()
        source.replaceCharacters(in: selection, with: NSAttributedString(string: "\n",
            attributes: listTypingAttributes(for: current)))
        var nextKind = current.kind
        if case .checklist = nextKind { nextKind = .checklist(false) }
        var updated = DocumentTextCodec.decode(source, preserving: document, trailing: nextKind,
            trailingIndentLevel: current.indentLevel, trailingAlign: current.align)
        let nextIndex = min(index + 1, updated.blocks.count - 1)
        updated.blocks[nextIndex].kind = nextKind
        updated.blocks[nextIndex].indentLevel = current.indentLevel
        updated.blocks[nextIndex].listStart = nil
        applyListDocument(updated, selection: NSRange(location: selection.location + 1, length: 0),
                          typing: listTypingAttributes(for: updated.blocks[nextIndex]))
        return true
    }

    private func listTypingAttributes(for block: DocumentBlock) -> [NSAttributedString.Key: Any] {
        let marks = DocumentTextCodec.decode(NSAttributedString(string: " ", attributes: typingAttributes),
                                            preserving: .empty).blocks.first?.runs.first?.marks ?? []
        return DocumentTextCodec.attributes(kind: block.kind, marks: marks,
            indentLevel: block.indentLevel, listStart: block.listStart, align: block.align)
    }

    /// One semantic edit, one undo entry; no literal tabs or marker text enter
    /// the document. The native selection and marked-text boundary stay intact.
    private func applyListDocument(_ document: NativeDocument, selection: NSRange,
                                   typing: [NSAttributedString.Key: Any]) {
        guard let storage = textStorage else { return }
        let previous = listEditingDocument()
        let previousSelection = selectedRange()
        let previousTyping = typingAttributes
        breakUndoCoalescing()
        undoManager?.registerUndo(withTarget: self) { view in
            view.applyListDocument(previous, selection: previousSelection, typing: previousTyping)
        }
        storage.setAttributedString(DocumentTextCodec.render(document))
        let last = document.blocks.last
        displayedTrailingBlock = last?.plainText.isEmpty == true ? last?.kind : nil
        displayedTrailingIndentLevel = last?.indentLevel ?? 0
        displayedTrailingListStart = last?.listStart
        typingAttributes = typing
        setSelectedRange(selection)
        requestSelectionAfterUndoRedo(selection)
        didChangeText()
        onSelectionChanged?()
        invalidateIntrinsicContentSize()
    }
}
