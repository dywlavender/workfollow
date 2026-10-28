import AppKit

extension NativeTextView {
    @discardableResult
    func copyDocumentFragment(to pasteboard: NSPasteboard) -> Bool {
        guard let fragment = DocumentClipboardCodec.fragment(from: attributedString(),
            range: selectedRange(), trailingBlock: pendingTrailingBlock ?? displayedTrailingBlock,
            trailingIndentLevel: trailingIndentLevel, trailingListStart: trailingListStart),
              DocumentClipboardCodec.write(fragment, to: pasteboard) else { return false }
        // Keep the existing diagram flavor for clients that understand it.
        _ = copyDiagramContent(to: pasteboard, preservingExistingContent: true)
        return true
    }

    @discardableResult
    func pasteDocumentFragment(from pasteboard: NSPasteboard) -> Bool {
        guard isEditable, !hasMarkedText(),
              let fragment = DocumentClipboardCodec.read(from: pasteboard),
              let value = DocumentClipboardCodec.attributedContent(for: fragment,
                  replacing: selectedRange(), in: attributedString(),
                  trailingBlock: pendingTrailingBlock ?? displayedTrailingBlock,
                  trailingIndentLevel: trailingIndentLevel, trailingListStart: trailingListStart) else { return false }
        insertStructuredClipboardContent(value)
        restorePastedTrailingParagraph(fragment)
        return true
    }

    @discardableResult
    func pasteExternalDocumentFragment(from pasteboard: NSPasteboard,
                                       destinationKind: DocumentBlockKind) -> Bool {
        guard isEditable, !hasMarkedText(),
              let fragment = DocumentExternalClipboardCodec.read(from: pasteboard,
                  destinationKind: destinationKind),
              let value = DocumentClipboardCodec.attributedContent(for: fragment,
                  replacing: selectedRange(), in: attributedString(),
                  trailingBlock: pendingTrailingBlock ?? displayedTrailingBlock,
                  trailingIndentLevel: trailingIndentLevel, trailingListStart: trailingListStart) else { return false }
        insertStructuredClipboardContent(value)
        restorePastedTrailingParagraph(fragment)
        return true
    }

    private func restorePastedTrailingParagraph(_ fragment: DocumentClipboardCodec.Fragment) {
        guard fragment.endsAtParagraphBoundary,
              let last = fragment.document.blocks.last, last.plainText.isEmpty,
              selectedRange().location == (string as NSString).length,
              string.isEmpty || string.hasSuffix("\n") else { return }
        seedTrailingParagraphKind(last.kind, indentLevel: last.indentLevel, listStart: last.listStart)
        didChangeText()
        onSelectionChanged?()
    }

    /// Rich payloads already have their formatting. Do not reinterpret literal
    /// Markdown characters in copied text as fresh keyboard shortcuts.
    func insertStructuredClipboardContent(_ value: NSAttributedString) {
        guard isEditable, !hasMarkedText() else { return }
        let previous = isApplyingTypedMarkdownInput
        isApplyingTypedMarkdownInput = true
        defer { isApplyingTypedMarkdownInput = previous }
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        insertText(value, replacementRange: selectedRange())
        undoManager?.endUndoGrouping()
        breakUndoCoalescing()

        // A pasted image's attachment metadata must not leak into subsequent
        // ordinary typing at the end of the fragment.
        if let storage = textStorage, storage.length > 0 {
            let index = min(max(0, selectedRange().location - 1), storage.length - 1)
            var attributes = storage.attributes(at: index, effectiveRange: nil)
            for key in [NSAttributedString.Key.attachment, .toolTip,
                        DocumentTextCodec.attachmentKey, DocumentTextCodec.diagramKey,
                        DocumentTextCodec.tableKey, DocumentTextCodec.formulaKey] {
                attributes.removeValue(forKey: key)
            }
            typingAttributes = attributes
            if selectedRange().location == storage.length,
               let token = attributes[DocumentTextCodec.blockKey] as? String {
                pendingTrailingBlock = storage.string.hasSuffix("\n") ? DocumentTextCodec.kind(token) : nil
            }
        }
        onSelectionChanged?()
    }
}
