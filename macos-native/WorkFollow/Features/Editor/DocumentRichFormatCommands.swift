import AppKit

/// 基础格式批：对齐、缩进、清除格式、文字/高亮颜色、撤销重做、格式刷。
/// 与 `applyFormat` 共用同一套 TextKit 替换与撤销口径。
extension NativeTextView {
    // MARK: - 撤销 / 重做

    var canUndoDocumentEdit: Bool { undoManager?.canUndo ?? false }
    var canRedoDocumentEdit: Bool { undoManager?.canRedo ?? false }

    func undoDocumentEdit() {
        guard isEditable, let manager = undoManager, manager.canUndo, !hasMarkedText() else { return }
        breakUndoCoalescing()
        manager.undo()
        window?.makeFirstResponder(self)
    }

    func redoDocumentEdit() {
        guard isEditable, let manager = undoManager, manager.canRedo, !hasMarkedText() else { return }
        breakUndoCoalescing()
        manager.redo()
        window?.makeFirstResponder(self)
    }

    // MARK: - 段落对齐 / 缩进

    func applyAlignment(_ alignment: DocumentAlignment) {
        guard isEditable else { return }
        let normalized: DocumentAlignment? = alignment == .left ? nil : alignment
        let (range, trailingEmpty) = toolbarParagraphRange()
        if trailingEmpty || range.length == 0 {
            applyEmptyParagraphState { kind, marks, indent, start, _, bodySize in
                (kind, marks, indent, start, normalized, bodySize)
            }
            return
        }
        guard let storage = textStorage else { return }
        let selection = selectedRange()
        let selected = storage.attributedSubstring(from: range)
        var document = DocumentTextCodec.decode(selected, preserving: NativeDocument(plainText: selected.string))
        for index in document.blocks.indices { document.blocks[index].align = normalized }
        replaceFormattedSelection(range: range, document: document, selection: selection)
    }

    func adjustIndent(by delta: Int) {
        guard isEditable else { return }
        let (range, trailingEmpty) = toolbarParagraphRange()
        if trailingEmpty || range.length == 0 {
            applyEmptyParagraphState { kind, marks, indent, start, align, bodySize in
                (kind, marks, min(8, max(0, indent + delta)), start, align, bodySize)
            }
            return
        }
        guard let storage = textStorage else { return }
        let selection = selectedRange()
        let selected = storage.attributedSubstring(from: range)
        var document = DocumentTextCodec.decode(selected, preserving: NativeDocument(plainText: selected.string))
        for index in document.blocks.indices {
            document.blocks[index].indentLevel = min(8, max(0, document.blocks[index].indentLevel + delta))
        }
        replaceFormattedSelection(range: range, document: document, selection: selection)
    }

    func clearFormatting() {
        guard isEditable else { return }
        let (range, trailingEmpty) = toolbarParagraphRange()
        if trailingEmpty || range.length == 0 {
            replaceEmptyBlock(range: range, content: NSAttributedString(string: ""),
                              typing: paragraphAttributes(kind: .paragraph, marks: []),
                              trailing: nil)
            return
        }
        guard let storage = textStorage else { return }
        let selection = selectedRange()
        let selected = storage.attributedSubstring(from: range)
        var document = DocumentTextCodec.decode(selected, preserving: NativeDocument(plainText: selected.string))
        for index in document.blocks.indices {
            guard document.blocks[index].kind != .divider else { continue }
            document.blocks[index].kind = .paragraph
            document.blocks[index].indentLevel = 0
            document.blocks[index].align = nil
            document.blocks[index].bodySize = nil
            document.blocks[index].runs = document.blocks[index].runs.map { run in
                var run = run
                run.marks = run.marks.filter { mark in
                    if case .symbol = mark { return true }
                    return false
                }
                return run
            }
        }
        replaceFormattedSelection(range: range, document: document, selection: selection)
    }

    // MARK: - 文字颜色 / 高亮颜色

    func applyTextColor(_ hex: String?) {
        let normalized = hex.flatMap(QuillDeltaCodec.normalizedColor)
        applyInlineMarkChange(matches: { mark in
            if case .textColor = mark { return true }
            return false
        }, applying: normalized.map { .textColor($0) })
    }

    func applyHighlightColor(_ hex: String?) {
        let normalized = hex.flatMap(QuillDeltaCodec.normalizedColor)
        applyInlineMarkChange(matches: { mark in
            switch mark {
            case .highlight: true
            case .highlightColor: true
            default: false
            }
        }, applying: normalized.map { .highlightColor($0) })
    }

    // MARK: - 格式刷

    /// 把取到的样式应用在当前选区或输入位置。
    func applyCapturedStyle(_ style: DocumentSelectionStyle) {
        guard isEditable else { return }
        let (range, trailingEmpty) = toolbarParagraphRange()
        if trailingEmpty || range.length == 0 {
            applyEmptyParagraphState { _, _, _, _, _, _ in
                (style.blockKind, style.marks, style.indentLevel, nil, style.align, style.bodySize)
            }
            return
        }
        guard let storage = textStorage else { return }
        let selection = selectedRange()
        let selected = storage.attributedSubstring(from: range)
        var document = DocumentTextCodec.decode(selected, preserving: NativeDocument(plainText: selected.string))
        for index in document.blocks.indices {
            guard document.blocks[index].kind != .divider else { continue }
            document.blocks[index].kind = style.blockKind
            document.blocks[index].indentLevel = style.indentLevel
            document.blocks[index].align = style.align
            document.blocks[index].bodySize = style.bodySize
            if style.blockKind != .ordered { document.blocks[index].listStart = nil }
            document.blocks[index].runs = document.blocks[index].runs.map { run in
                var run = run
                let contentMarks = run.marks.filter { mark in
                    if case .symbol = mark { return true }
                    return false
                }
                run.marks = style.marks.union(contentMarks)
                return run
            }
        }
        replaceFormattedSelection(range: range, document: document, selection: selection)
    }

    // MARK: - 共用管道

    /// 段级命令（对齐/缩进）选中的整段范围；文末空段返回零长范围并标记。
    private func toolbarParagraphRange() -> (NSRange, Bool) {
        let source = string as NSString
        let selection = selectedRange()
        let trailingEmpty = source.length == 0
            || (selection.length == 0 && selection.location == source.length
                && source.character(at: source.length - 1) == 0x0A)
        if source.length == 0 || trailingEmpty {
            return (NSRange(location: source.length, length: 0), true)
        }
        return (source.paragraphRange(for: selection), false)
    }

    /// 空段落/文末空段的格式只改变输入属性；用块级命令的同一路径记录撤销。
    private func applyEmptyParagraphState(
        _ transform: (DocumentBlockKind, Set<DocumentMark>, Int, Int?, DocumentAlignment?, DocumentBodySize?) ->
            (DocumentBlockKind, Set<DocumentMark>, Int, Int?, DocumentAlignment?, DocumentBodySize?)
    ) {
        let sample = NSAttributedString(string: " ", attributes: typingAttributes)
        let block = DocumentTextCodec.decode(sample, preserving: .empty).blocks.first
        let kind = block?.kind ?? .paragraph
        let marks = block?.runs.first?.marks ?? []
        let indent = block?.indentLevel ?? 0
        let start = block?.listStart
        let align = block?.align
        let bodySize = block?.bodySize
        let result = transform(kind, marks, indent, start, align, bodySize)
        let typing = paragraphAttributes(kind: result.0, marks: result.1,
            indentLevel: result.2, listStart: result.3, align: result.4, bodySize: result.5)
        let (range, _) = toolbarParagraphRange()
        replaceEmptyBlock(range: range, content: NSAttributedString(string: ""),
                          typing: typing, trailing: result.0)
    }

    /// 行内标记替换：有选区改选中文字，无选区只改输入属性（后续输入沿用）。
    private func applyInlineMarkChange(matches: (DocumentMark) -> Bool, applying: DocumentMark?) {
        guard isEditable else { return }
        let selection = selectedRange()
        if selection.length == 0 {
            let sample = NSAttributedString(string: " ", attributes: typingAttributes)
            let block = DocumentTextCodec.decode(sample, preserving: .empty).blocks.first
            var marks = block?.runs.first?.marks ?? []
            marks = marks.filter { !matches($0) }
            if let applying { marks.insert(applying) }
            let typing = paragraphAttributes(kind: block?.kind ?? .paragraph, marks: marks,
                indentLevel: block?.indentLevel ?? 0, listStart: block?.listStart, align: block?.align,
                bodySize: block?.bodySize)
            typingAttributes = typing
            return
        }
        guard let storage = textStorage else { return }
        let selected = storage.attributedSubstring(from: selection)
        var document = DocumentTextCodec.decode(selected, preserving: NativeDocument(plainText: selected.string))
        for blockIndex in document.blocks.indices {
            for runIndex in document.blocks[blockIndex].runs.indices {
                var marks = document.blocks[blockIndex].runs[runIndex].marks
                marks = marks.filter { !matches($0) }
                if let applying { marks.insert(applying) }
                document.blocks[blockIndex].runs[runIndex].marks = marks
            }
        }
        replaceFormattedSelection(range: selection, document: document, selection: selection)
    }

    /// 用渲染后的富文本替换选区，并保持撤销、选区、输入属性与最终存储一致。
    private func replaceFormattedSelection(range: NSRange, document: NativeDocument, selection: NSRange) {
        guard let storage = textStorage else { return }
        let replacement = renderDocument(document)
        var cleanTyping = paragraphAttributes(
            kind: document.blocks.first?.kind ?? .paragraph, marks: [],
            indentLevel: document.blocks.first?.indentLevel ?? 0,
            listStart: document.blocks.first?.listStart,
            align: document.blocks.first?.align,
            bodySize: document.blocks.first?.bodySize)
        cleanTyping.removeValue(forKey: DocumentTextCodec.completedChecklistPresentationKey)
        typingAttributes = cleanTyping
        insertText(replacement, replacementRange: range)
        if range.location + replacement.length <= storage.length {
            replacement.enumerateAttributes(in: NSRange(location: 0, length: replacement.length)) {
                attributes, localRange, _ in
                storage.setAttributes(attributes, range: NSRange(location: range.location + localRange.location,
                                                                 length: localRange.length))
            }
        }
        let location = min(selection.location, (string as NSString).length)
        let length = min(selection.length, (string as NSString).length - location)
        setSelectedRange(NSRange(location: location, length: length))
        syncParagraphStyleAfterEdit(at: location)
        didChangeText()
    }
}
