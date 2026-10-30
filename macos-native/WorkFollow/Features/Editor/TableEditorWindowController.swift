import AppKit

/// 表格编辑窗：直接编辑单元格，支持增删行列；保存后写回正文附件。
@MainActor
final class TableEditorWindowController: NSWindowController, NSWindowDelegate {
    private var working: NativeTable
    private let documentView = TableGridDocumentView()
    private let scroll = NSScrollView()
    private let status = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: "保存表格", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private let onSave: (NativeTable) -> Bool
    private let onClose: () -> Void
    private var fields: [[NSTextField]] = []
    private var hasClosed = false

    private static let cellWidth: CGFloat = 150
    private static let cellHeight: CGFloat = 26
    private static let gap: CGFloat = 6

    init(table: NativeTable?, onSave: @escaping (NativeTable) -> Bool,
         onClose: @escaping () -> Void) {
        working = table ?? .empty()
        self.onSave = onSave
        self.onClose = onClose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 430),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = table == nil ? "插入表格" : "编辑表格"
        window.minSize = NSSize(width: 460, height: 300)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        let addRow = NSButton(title: "添加行", target: self, action: #selector(addRow))
        let removeRow = NSButton(title: "删除行", target: self, action: #selector(removeRow))
        let addColumn = NSButton(title: "添加列", target: self, action: #selector(addColumn))
        let removeColumn = NSButton(title: "删除列", target: self, action: #selector(removeColumn))
        for button in [addRow, removeRow, addColumn, removeColumn] {
            button.bezelStyle = .rounded
            button.focusRingType = .none
        }
        let toolSpacer = NSView()
        toolSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let tools = NSStackView(views: [addRow, removeRow, addColumn, removeColumn, toolSpacer])
        tools.spacing = 8

        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        CompactScrollStyle.apply(to: scroll)
        scroll.documentView = documentView

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.stringValue = "第一行作为表头；双击正文里的表格可再次编辑。"

        saveButton.target = self
        saveButton.action = #selector(saveTable)
        saveButton.bezelStyle = .rounded
        saveButton.focusRingType = .none
        saveButton.keyEquivalent = "\r"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.bezelStyle = .rounded
        cancelButton.focusRingType = .none
        cancelButton.keyEquivalent = "\u{1b}"
        let buttonSpacer = NSView()
        buttonSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [buttonSpacer, cancelButton, saveButton])
        buttons.spacing = 8

        let root = NSView()
        window.contentView = root
        for view in [tools, scroll, status, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            tools.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            tools.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            tools.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            tools.heightAnchor.constraint(equalToConstant: 26),
            scroll.topAnchor.constraint(equalTo: tools.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            status.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            buttons.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 8),
            buttons.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14)
        ])
        rebuildGrid()
    }

    required init?(coder: NSCoder) { fatalError("Use init(table:onSave:onClose:)") }

    func present(asSheetOf parent: NSWindow) {
        guard let window else { return }
        parent.beginSheet(window) { [weak self] _ in self?.finishClose() }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, let first = self.fields.first?.first else { return }
            window.makeFirstResponder(first)
        }
    }

    private func rebuildGrid() {
        documentView.subviews.forEach { $0.removeFromSuperview() }
        fields = []
        let columns = max(1, working.columnCount)
        let rows = max(1, working.rowCount)
        let gap = Self.gap
        let contentWidth = CGFloat(columns) * Self.cellWidth + CGFloat(columns - 1) * gap
        let contentHeight = CGFloat(rows) * Self.cellHeight + CGFloat(rows - 1) * gap
        documentView.frame = NSRect(x: 0, y: 0,
                                    width: max(contentWidth, scroll.contentSize.width),
                                    height: max(contentHeight, scroll.contentSize.height))
        for row in 0..<rows {
            var rowFields: [NSTextField] = []
            for column in 0..<columns {
                let field = NSTextField(frame: NSRect(
                    x: CGFloat(column) * (Self.cellWidth + gap),
                    y: CGFloat(row) * (Self.cellHeight + gap),
                    width: Self.cellWidth, height: Self.cellHeight))
                field.stringValue = working.text(row: row, column: column)
                field.placeholderString = "单元格"
                field.font = .systemFont(ofSize: 13)
                field.bezelStyle = .roundedBezel
                field.lineBreakMode = .byTruncatingTail
                documentView.addSubview(field)
                rowFields.append(field)
            }
            fields.append(rowFields)
        }
    }

    private func capture() {
        for (row, rowFields) in fields.enumerated() {
            for (column, field) in rowFields.enumerated() {
                working.setText(field.stringValue, row: row, column: column)
            }
        }
    }

    @objc private func addRow() { capture(); working.addRow(); rebuildGrid() }
    @objc private func removeRow() { capture(); working.removeLastRow(); rebuildGrid() }
    @objc private func addColumn() { capture(); working.addColumn(); rebuildGrid() }
    @objc private func removeColumn() { capture(); working.removeLastColumn(); rebuildGrid() }

    @objc private func saveTable() {
        capture()
        guard onSave(working) else {
            status.textColor = .systemRed
            status.stringValue = "正文已变化，表格未能保存，请重试。"
            return
        }
        close()
    }

    @objc private func cancel() { close() }

    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
    func windowWillClose(_ notification: Notification) { finishClose() }

    override func close() {
        guard let window, let parent = window.sheetParent else { super.close(); finishClose(); return }
        parent.endSheet(window)
        super.close()
    }

    private func finishClose() {
        guard !hasClosed else { return }
        hasClosed = true
        onClose()
    }
}

/// 表格网格的文档视图：左上角为原点，和字段坐标一致。
final class TableGridDocumentView: NSView {
    override var isFlipped: Bool { true }
}
