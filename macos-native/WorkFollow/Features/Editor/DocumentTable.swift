import AppKit

/// 表格附件单元：按正文宽度铺开，画表头 + 网格线；双击进入表格编辑窗。
final class DocumentTableCell: NSTextAttachmentCell {
    let table: NativeTable

    init(table: NativeTable) {
        self.table = table
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("DocumentTableCell is a document projection") }

    override func cellSize() -> NSSize { size(availableWidth: 440) }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let width = min(lineFrag.width, textContainer.containerSize.width)
            - DocumentEditorGeometry.decorationLane - textContainer.lineFragmentPadding * 2
        return NSRect(origin: .zero, size: size(availableWidth: width))
    }

    private func size(availableWidth: CGFloat) -> NSSize {
        let width = max(240, min(640, availableWidth))
        return NSSize(width: width, height: CGFloat(max(1, table.rowCount)) * 30 + 2)
    }

    override func draw(withFrame frame: NSRect, in controlView: NSView?) {
        let card = NSRect(x: frame.minX, y: frame.minY + 1, width: frame.width, height: frame.height - 2)
        let path = NSBezierPath(roundedRect: card, xRadius: 6, yRadius: 6)
        NSColor.textBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let rows = max(1, table.rowCount)
        let columns = max(1, table.columnCount)
        let rowHeight = card.height / CGFloat(rows)
        let columnWidth = card.width / CGFloat(columns)

        // 表头（第一行）浅底，和内容区分。
        let header = NSRect(x: card.minX + 1, y: card.minY + 1,
                            width: card.width - 2, height: rowHeight - 1)
        NSColor.labelColor.withAlphaComponent(0.045).setFill()
        header.fill()

        let lineColor = NSColor.separatorColor.withAlphaComponent(0.85)
        lineColor.setStroke()
        let hairline = 1 / max(1, controlView?.window?.backingScaleFactor ?? 2)
        for column in 1..<columns {
            let x = card.minX + CGFloat(column) * columnWidth
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: card.minY))
            line.line(to: NSPoint(x: x, y: card.maxY))
            line.lineWidth = hairline
            line.stroke()
        }
        for row in 1..<rows {
            let y = card.minY + CGFloat(row) * rowHeight
            let line = NSBezierPath()
            line.move(to: NSPoint(x: card.minX, y: y))
            line.line(to: NSPoint(x: card.maxX, y: y))
            line.lineWidth = hairline
            line.stroke()
        }

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = .left
        for row in 0..<rows {
            for column in 0..<columns {
                let text = table.text(row: row, column: column)
                let rect = NSRect(x: card.minX + CGFloat(column) * columnWidth + 8,
                                  y: card.minY + CGFloat(row) * rowHeight + 7,
                                  width: max(1, columnWidth - 16),
                                  height: max(1, rowHeight - 12))
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 13, weight: row == 0 ? .semibold : .regular),
                    .foregroundColor: text.isEmpty ? NSColor.tertiaryLabelColor : NSColor.labelColor,
                    .paragraphStyle: style
                ]
                (text.isEmpty ? " " as NSString : text as NSString).draw(in: rect, withAttributes: attributes)
            }
        }
    }
}

extension NativeTextView {
    func table(at index: Int) -> NativeTable? {
        guard let storage = textStorage, index >= 0, index < storage.length,
              let data = storage.attribute(DocumentTextCodec.tableKey, at: index, effectiveRange: nil) as? Data
        else { return nil }
        return try? JSONDecoder().decode(NativeTable.self, from: data)
    }

    func formula(at index: Int) -> NativeFormula? {
        guard let storage = textStorage, index >= 0, index < storage.length,
              let data = storage.attribute(DocumentTextCodec.formulaKey, at: index, effectiveRange: nil) as? Data
        else { return nil }
        return try? JSONDecoder().decode(NativeFormula.self, from: data)
    }

    // MARK: - 插入 / 编辑

    func insertDocumentTable(at offset: Int?) {
        guard isEditable else { return }
        let range = offset.map { NSRange(location: min(max(0, $0), (string as NSString).length), length: 0) }
            ?? selectedRange()
        presentTableEditor(table: nil, replacing: range)
    }

    func editDocumentTable(at index: Int) {
        guard isEditable, let table = table(at: index) else { return }
        presentTableEditor(table: table, replacing: NSRange(location: index, length: 1))
    }

    func insertDocumentFormula(at offset: Int?) {
        guard isEditable else { return }
        let range = offset.map { NSRange(location: min(max(0, $0), (string as NSString).length), length: 0) }
            ?? selectedRange()
        presentFormulaEditor(formula: nil, replacing: range)
    }

    func editDocumentFormula(at index: Int) {
        guard isEditable, let formula = formula(at: index) else { return }
        presentFormulaEditor(formula: formula, replacing: NSRange(location: index, length: 1))
    }

    private func presentTableEditor(table: NativeTable?, replacing range: NSRange) {
        guard let window, tableEditor == nil else { return }
        dismissSlash(); dismissSelectionToolbar(); hideLinkHoverMenu()
        let identity = documentIdentity
        let controller = TableEditorWindowController(table: table, onSave: { [weak self] updated in
            guard let self, self.documentIdentity == identity else { return false }
            return self.saveTable(updated, replacing: range, existingID: table?.id)
        }, onClose: { [weak self] in self?.tableEditor = nil })
        tableEditor = controller
        controller.present(asSheetOf: window)
    }

    private func presentFormulaEditor(formula: NativeFormula?, replacing range: NSRange) {
        guard let window, formulaEditor == nil else { return }
        dismissSlash(); dismissSelectionToolbar(); hideLinkHoverMenu()
        let identity = documentIdentity
        let controller = FormulaEditorWindowController(formula: formula, onSave: { [weak self] updated in
            guard let self, self.documentIdentity == identity else { return false }
            return self.saveFormula(updated, replacing: range, existingID: formula?.id)
        }, onClose: { [weak self] in self?.formulaEditor = nil })
        formulaEditor = controller
        controller.present(asSheetOf: window)
    }

    @discardableResult
    func saveTable(_ table: NativeTable, replacing originalRange: NSRange, existingID: UUID?) -> Bool {
        guard isEditable, let storage = textStorage else { return false }
        let targetID = existingID ?? table.id
        var matches: [NSRange] = []
        storage.enumerateAttribute(DocumentTextCodec.tableKey,
                                   in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let data = value as? Data,
               let current = try? JSONDecoder().decode(NativeTable.self, from: data),
               current.id == targetID {
                matches.append(range)
            }
        }
        if existingID != nil, matches.isEmpty { return false }
        let updating = !matches.isEmpty
        if let match = matches.first, matches.count == 1, self.table(at: match.location) == table {
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
        blocks.append(DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "\u{FFFC}", table: table)]))
        if !updating { blocks.append(DocumentBlock(kind: .paragraph)) }
        let content = DocumentTextCodec.render(NativeDocument(blocks: blocks))
        breakUndoCoalescing()
        guard shouldChangeText(in: range, replacementString: content.string) else { return false }
        storage.replaceCharacters(in: range, with: content)
        setSelectedRange(NSRange(location: range.location + content.length, length: 0))
        didChangeText()
        breakUndoCoalescing()
        typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
        undoManager?.setActionName(updating ? "编辑表格" : "插入表格")
        return true
    }

    @discardableResult
    func saveFormula(_ formula: NativeFormula, replacing originalRange: NSRange, existingID: UUID?) -> Bool {
        guard isEditable, let storage = textStorage else { return false }
        let targetID = existingID ?? formula.id
        var matches: [NSRange] = []
        storage.enumerateAttribute(DocumentTextCodec.formulaKey,
                                   in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let data = value as? Data,
               let current = try? JSONDecoder().decode(NativeFormula.self, from: data),
               current.id == targetID {
                matches.append(range)
            }
        }
        if existingID != nil, matches.isEmpty { return false }
        let updating = !matches.isEmpty
        if let match = matches.first, matches.count == 1, self.formula(at: match.location) == formula {
            return true
        }
        var range = originalRange
        if let match = matches.first { range = match }
        guard range.location != NSNotFound, NSMaxRange(range) <= storage.length else { return false }
        let base = range.location < storage.length
            ? storage.attributes(at: range.location, effectiveRange: nil) : typingAttributes
        var attributes = base
        for key in [DocumentTextCodec.attachmentKey, DocumentTextCodec.formulaKey,
                    NSAttributedString.Key.attachment, .toolTip] {
            attributes.removeValue(forKey: key)
        }
        if attributes[DocumentTextCodec.blockKey] == nil {
            attributes[DocumentTextCodec.blockKey] = DocumentTextCodec.blockToken(.paragraph)
        }
        guard let data = try? JSONEncoder().encode(formula) else { return false }
        attributes[DocumentTextCodec.formulaKey] = data
        attributes[.toolTip] = "公式 · 双击编辑"
        let attachment = NSTextAttachment()
        attachment.attachmentCell = DocumentFormulaCell(formula: formula)
        attributes[.attachment] = attachment
        let content = NSAttributedString(string: "\u{FFFC}", attributes: attributes)
        breakUndoCoalescing()
        guard shouldChangeText(in: range, replacementString: content.string) else { return false }
        storage.replaceCharacters(in: range, with: content)
        setSelectedRange(NSRange(location: range.location + content.length, length: 0))
        didChangeText()
        breakUndoCoalescing()
        undoManager?.setActionName(updating ? "编辑公式" : "插入公式")
        return true
    }
}
