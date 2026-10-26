import AppKit

final class DocumentDiagramCell: NSTextAttachmentCell {
    let diagram: NativeDiagram
    private let preview: NSImage?

    init(diagram: NativeDiagram) {
        self.diagram = diagram
        self.preview = NSImage(data: diagram.previewPNG)
        super.init(textCell: "")
    }
    required init(coder: NSCoder) { fatalError("DocumentDiagramCell is a document projection") }

    override func cellSize() -> NSSize { size(availableWidth: 440) }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let width = min(lineFrag.width, textContainer.containerSize.width)
            - DocumentEditorGeometry.decorationLane - textContainer.lineFragmentPadding * 2
        return NSRect(origin: .zero, size: size(availableWidth: width))
    }

    private func size(availableWidth: CGFloat) -> NSSize {
        let width = max(80, min(440, availableWidth))
        let imageSize = preview?.size ?? NSSize(width: 320, height: 180)
        let height = min(280, max(72, (width - 24) * imageSize.height / max(1, imageSize.width)))
        return NSSize(width: width, height: height + 44)
    }

    override func draw(withFrame frame: NSRect, in controlView: NSView?) {
        let card = frame.insetBy(dx: 1, dy: 3)
        let path = NSBezierPath(roundedRect: card, xRadius: 8, yRadius: 8)
        NSColor.textBackgroundColor.setFill(); path.fill()
        NSColor.separatorColor.setStroke(); path.lineWidth = 1; path.stroke()
        // NativeTextView is flipped. Keep the preview upright and the caption below it.
        let imageFrame = NSRect(x: card.minX + 12, y: card.minY + 10,
                                width: max(1, card.width - 24), height: max(1, card.height - 46))
        if let preview {
            NSGraphicsContext.current?.imageInterpolation = .high
            let ratio = min(imageFrame.width / max(1, preview.size.width),
                            imageFrame.height / max(1, preview.size.height))
            let size = NSSize(width: preview.size.width * ratio, height: preview.size.height * ratio)
            let fitted = NSRect(x: imageFrame.midX - size.width / 2, y: imageFrame.midY - size.height / 2,
                                width: size.width, height: size.height)
            preview.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: 1,
                         respectFlipped: true, hints: nil)
        }
        let label = (diagram.title + "  ·  双击编辑") as NSString
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
        label.draw(in: NSRect(x: card.minX + 12, y: card.maxY - 27, width: card.width - 24, height: 18),
                   withAttributes: [.font: NSFont.systemFont(ofSize: 12),
                                    .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style])
    }
}

extension NativeTextView {
    private static let diagramPasteboardType = NSPasteboard.PasteboardType("com.workfollow.document.drawio")

    func copyDiagramContent(to pasteboard: NSPasteboard, preservingExistingContent: Bool = false) -> Bool {
        let range = selectedRange()
        guard range.length > 0, NSMaxRange(range) <= attributedString().length else { return false }
        let selected = attributedString().attributedSubstring(from: range)
        let content = DocumentTextCodec.decode(selected, preserving: .empty)
        guard content.blocks.contains(where: { $0.runs.contains(where: { $0.diagram != nil }) }),
              let data = try? JSONEncoder().encode(content) else { return false }
        let plain = content.blocks.map { block in
            block.runs.map { $0.diagram.map { "[流程图：" + $0.title + "]" } ?? $0.text }.joined()
        }.joined(separator: "\n")
        if preservingExistingContent {
            pasteboard.addTypes([Self.diagramPasteboardType], owner: nil)
        } else {
            pasteboard.clearContents()
        }
        pasteboard.setData(data, forType: Self.diagramPasteboardType)
        if !preservingExistingContent { pasteboard.setString(plain, forType: .string) }
        return true
    }

    func pasteDiagramContent(from pasteboard: NSPasteboard) -> Bool {
        guard isEditable, let data = pasteboard.data(forType: Self.diagramPasteboardType),
              let source = try? JSONDecoder().decode(NativeDocument.self, from: data) else { return false }
        let copy = NativeDocument(blocks: source.blocks.map { block in
            DocumentBlock(kind: block.kind, runs: block.runs.map { run in
                var run = run
                if var diagram = run.diagram { diagram.id = UUID(); run.diagram = diagram }
                return run
            })
        })
        insertText(DocumentTextCodec.render(copy), replacementRange: selectedRange())
        typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
        return true
    }

    func diagram(at index: Int) -> NativeDiagram? {
        guard let storage = textStorage, index >= 0, index < storage.length,
              let data = storage.attribute(DocumentTextCodec.diagramKey, at: index, effectiveRange: nil) as? Data
        else { return nil }
        return try? JSONDecoder().decode(NativeDiagram.self, from: data)
    }

    func insertDocumentDiagram(at offset: Int?) {
        guard isEditable else { return }
        let range = offset.map { NSRange(location: min(max(0, $0), (string as NSString).length), length: 0) }
            ?? selectedRange()
        presentDiagramEditor(diagram: nil, replacing: range)
    }

    func editDocumentDiagram(at index: Int) {
        guard isEditable, let diagram = diagram(at: index) else { return }
        presentDiagramEditor(diagram: diagram, replacing: NSRange(location: index, length: 1))
    }

    private func presentDiagramEditor(diagram: NativeDiagram?, replacing range: NSRange) {
        guard let window, diagramEditor == nil else { return }
        dismissSlash(); dismissSelectionToolbar(); hideLinkHoverMenu()
        let identity = documentIdentity
        let controller = DrawioEditorWindowController(diagram: diagram, onSave: { [weak self] drawing in
            guard let self, self.documentIdentity == identity else { return false }
            return self.saveDiagram(drawing, replacing: range, existingID: diagram?.id)
        }, onClose: { [weak self] in self?.diagramEditor = nil })
        diagramEditor = controller
        controller.present(asSheetOf: window)
    }

    /// A drawing ID owns one attachment, even while a newly opened drawing
    /// session continues to save without an initial existingID.
    @discardableResult
    func saveDiagram(_ diagram: NativeDiagram, replacing originalRange: NSRange, existingID: UUID?) -> Bool {
        guard isEditable, let storage = textStorage else { return false }
        let targetID = existingID ?? diagram.id
        var matches: [NSRange] = []
        storage.enumerateAttribute(DocumentTextCodec.diagramKey, in: NSRange(location: 0, length: storage.length)) { value, candidate, _ in
            if let data = value as? Data,
               let current = try? JSONDecoder().decode(NativeDiagram.self, from: data), current.id == targetID {
                matches.append(candidate)
            }
        }
        if existingID != nil, matches.isEmpty { return false }
        let updating = !matches.isEmpty
        if let match = matches.first, matches.count == 1, self.diagram(at: match.location) == diagram {
            return true
        }
        var range = originalRange
        if let match = matches.first { range = match }
        guard range.location != NSNotFound, NSMaxRange(range) <= storage.length else { return false }
        var blocks: [DocumentBlock] = []
        if !updating, range.location > 0,
           (storage.string as NSString).substring(with: NSRange(location: range.location - 1, length: 1)) != "\n" {
            blocks.append(DocumentBlock(kind: .paragraph))
        }
        blocks.append(DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "\u{FFFC}", diagram: diagram)]))
        if !updating { blocks.append(DocumentBlock(kind: .paragraph)) }
        var content = DocumentTextCodec.render(NativeDocument(blocks: blocks))
        if matches.count > 1 {
            // Earlier saves could insert the same ID more than once. On the
            // next explicit save, retain the chosen editor's current version.
            // Preserve intervening text and drawings with independent IDs;
            // replace the complete span once so one Undo restores all versions.
            let plain = storage.string as NSString
            let removals = matches.dropFirst().map { match in
                let paragraph = plain.paragraphRange(for: match)
                return plain.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines) == "\u{FFFC}"
                    ? paragraph : match
            }
            let span = NSRange(location: range.location,
                               length: max(NSMaxRange(range), removals.map(NSMaxRange).max() ?? 0) - range.location)
            let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: span))
            let edits = [(range, content)] + removals.map { ($0, NSAttributedString(string: "")) }
            for (edit, value) in edits.sorted(by: { $0.0.location > $1.0.location }) {
                replacement.replaceCharacters(in: NSRange(location: edit.location - span.location, length: edit.length), with: value)
            }
            range = span
            content = replacement
        }
        breakUndoCoalescing()
        // Register NSTextView's own undo once, then replace the attributes
        // exactly. insertText can inherit the outgoing diagram attributes onto
        // intervening plain text when consolidating earlier duplicates.
        guard shouldChangeText(in: range, replacementString: content.string) else { return false }
        storage.replaceCharacters(in: range, with: content)
        setSelectedRange(NSRange(location: range.location + content.length, length: 0))
        didChangeText()
        breakUndoCoalescing()
        typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
        undoManager?.setActionName(updating ? "编辑流程图" : "插入流程图")
        return true
    }
}
