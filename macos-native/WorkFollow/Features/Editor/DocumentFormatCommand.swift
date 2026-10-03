import AppKit

/// Pure metadata; existing TextKit methods remain the execution boundary.
struct EditorCommandDescriptor: Identifiable {
    let id: String
    let title: String
    let keywords: String
    let glyph: SlashGlyphKind
    let block: DocumentBlockKind?
    let mark: DocumentMark?

    // Entry-specific labels preserve the existing product language.
    var formatToolbarTitle: String { id == "format.inlineCode" ? "代码" : title }
    var toolbarSymbol: String {
        switch mark {
        case .bold: return "bold"
        case .italic: return "italic"
        case .underline: return "underline"
        case .strikethrough: return "strikethrough"
        case .highlight: return "highlighter"
        case .code: return "chevron.left.forwardslash.chevron.right"
        default:
            switch block {
            case .bullet: return "list.bullet"
            case .ordered: return "list.number"
            case .checklist: return "checklist"
            case .quote: return "text.quote"
            default: return "textformat"
            }
        }
    }

    func isActive(in style: DocumentSelectionStyle) -> Bool {
        style.has(mark) || style.isBlock(block)
    }
}

enum EditorCommandCatalog {
    static var formats: [EditorCommandDescriptor] {
        DocumentFormatCommand.commands.map(\.descriptor)
    }

    static func format(_ id: String) -> DocumentFormatCommand? {
        DocumentFormatCommand.commands.first { $0.id == id }
    }

    // Product order is explicit, but identity is never derived from this order.
    static let compactSlashFormatIDs = [
        "format.heading1", "format.heading2", "format.heading3", "format.bullet",
        "format.ordered", "format.checklist", "format.quote"
    ]
    static let headingPickerIDs = ["format.paragraph", "format.heading1", "format.heading2", "format.heading3"]
    static let selectionFormatIDs = [
        "format.bold", "format.italic", "format.underline", "format.strikethrough",
        "format.highlight", "format.inlineCode"
    ]
}

struct DocumentFormatCommand {
    let id: String
    let title: String
    let block: DocumentBlockKind?
    let mark: DocumentMark?
    var descriptor: EditorCommandDescriptor {
        let glyph: SlashGlyphKind
        switch block {
        case .heading(let level): glyph = .heading(level)
        case .bullet: glyph = .bullet
        case .ordered: glyph = .ordered
        case .checklist: glyph = .checklist
        case .quote: glyph = .quote
        default: glyph = .symbol("text.alignleft")
        }
        return EditorCommandDescriptor(id: id, title: title, keywords: keywords,
                                       glyph: glyph, block: block, mark: mark)
    }

    func slashCommand(group: String, includeKeywords: Bool = false,
                      useFormatGlyph: Bool = false) -> DocumentCommand {
        DocumentCommand(id: descriptor.id, title: descriptor.title, group: group,
                        keywords: includeKeywords ? descriptor.keywords : "",
                        glyph: useFormatGlyph ? descriptor.glyph : .symbol("text.alignleft"),
                        perform: { $0.applyFormat(self) },
                        slash: { view, invocation in
                            view.applyFormat(self, lineStart: invocation.lineStart)
                        })
    }
    var keywords: String {
        switch block {
        case .paragraph: return "paragraph text"
        case .heading: return "heading title h1 h2"
        case .quote: return "quote"
        case .code: return "code"
        case .bullet: return "bullet list"
        case .ordered: return "ordered list"
        case .checklist: return "checklist todo checkbox"
        default: return String(describing: mark)
        }
    }
    static let commands: [Self] = [
        .init(id: "format.paragraph", title: "正文", block: .paragraph, mark: nil),
        .init(id: "format.heading1", title: "一级标题", block: .heading(1), mark: nil),
        .init(id: "format.heading2", title: "二级标题", block: .heading(2), mark: nil),
        .init(id: "format.quote", title: "引用", block: .quote, mark: nil),
        .init(id: "format.codeBlock", title: "代码块", block: .code, mark: nil),
        .init(id: "format.bullet", title: "无序列表", block: .bullet, mark: nil),
        .init(id: "format.ordered", title: "有序列表", block: .ordered, mark: nil),
        .init(id: "format.checklist", title: "检查项", block: .checklist(false), mark: nil),
        .init(id: "format.checkedChecklist", title: "勾选清单项", block: .checklist(true), mark: nil),
        .init(id: "format.bold", title: "粗体", block: nil, mark: .bold),
        .init(id: "format.italic", title: "斜体", block: nil, mark: .italic),
        .init(id: "format.underline", title: "下划线", block: nil, mark: .underline),
        .init(id: "format.strikethrough", title: "删除线", block: nil, mark: .strikethrough),
        .init(id: "format.highlight", title: "高亮", block: nil, mark: .highlight),
        .init(id: "format.heading3", title: "三级标题", block: .heading(3), mark: nil),
        .init(id: "format.inlineCode", title: "行内代码", block: nil, mark: .code)
    ]
}

extension NativeTextView {
    func insertDocumentTime(_ date: Date = Date(), format: String = "yyyy年M月d日 HH:mm") {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        insertText(formatter.string(from: date), replacementRange: selectedRange())
    }

    func insertDocumentDivider(at offset: Int? = nil) {
        let range: NSRange
        if let offset {
            let location = min(max(0, offset), (string as NSString).length)
            range = NSRange(location: location, length: 0)
        } else {
            range = selectedRange()
        }
        let text = string as NSString
        let needsLeadingBreak = range.location > 0 && text.substring(with: NSRange(location: range.location - 1, length: 1)) != "\n"
        let insertion = NSMutableAttributedString(string: needsLeadingBreak ? "\n" : "",
            attributes: DocumentTextCodec.attributes(kind: .paragraph, marks: []))
        insertion.append(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .divider, runs: [DocumentRun(text: "\u{FFFC}")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "")])
        ])))
        insertText(insertion, replacementRange: range)
        typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
        resizeDocumentDividers()
    }

    func resizeDocumentDividers() {
        guard let storage = textStorage else { return }
        let width = max(1, bounds.width - textContainerInset.width * 2 - (textContainer?.lineFragmentPadding ?? 5) * 2)
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment,
          let cell = attachment.attachmentCell as? DocumentDividerCell,
                  cell.lineWidth != width else { return }
            cell.lineWidth = width
            invalidateDocumentLayout(for: range)
        }
    }

    func formatMenu() -> NSMenu {
        let menu = NSMenu(title: "格式")
        for (index, command) in DocumentFormatCommand.commands.enumerated() {
            let item = NSMenuItem(title: command.title, action: #selector(applyDocumentFormat(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (title, selector) in [("编辑链接…", #selector(editDocumentLink(_:))), ("移除链接", #selector(removeDocumentLink(_:))), ("插入附件…", #selector(insertDocumentAttachment(_:)))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @objc func applyDocumentFormat(_ sender: NSMenuItem) {
        guard DocumentFormatCommand.commands.indices.contains(sender.tag) else { return }
        let command = DocumentFormatCommand.commands[sender.tag]
        applyFormat(command)
    }

    func applyFormat(_ command: DocumentFormatCommand, lineStart: Int? = nil) {
        let originalSelection = selectedRange()
        var range = originalSelection
        if command.block != nil {
            let source = string as NSString
            // 文末空段（光标在末尾、文档以换行结尾）：它没有字符可定位，
            // 必须走"无字符段落"分支（输入属性 + 待定级别）。若按常规钳制到
            // length-1，段落解析会落到**上一行**——列表格式跑到上面一行的
            // 就是这个（斜杠先删"/"再应用格式，触发这个边界）。
            let atTrailingEmpty = source.length > 0
                && originalSelection.length == 0
                && originalSelection.location == source.length
                && source.character(at: source.length - 1) == 0x0A
            if source.length == 0 || atTrailingEmpty {
                range = NSRange(location: source.length, length: 0)
            } else if let lineStart {
                let location = min(max(0, lineStart), source.length - 1)
                range = source.paragraphRange(for: NSRange(location: location, length: 0))
            } else {
                range = source.paragraphRange(for: originalSelection)
            }
        }
        if range.length == 0 {
            let token = typingAttributes[DocumentTextCodec.blockKey] as? String ?? "paragraph"
            let sample = NSAttributedString(string: " ", attributes: typingAttributes)
            var marks = DocumentTextCodec.decode(sample, preserving: .empty).blocks.first?.runs.first?.marks ?? []
            if let mark = command.mark {
                if marks.contains(mark) { marks.remove(mark) }
                else { marks.insert(mark) }
            }
            let current = DocumentTextCodec.kind(token)
            let resolved = resolvedBlock(command.block, current: current, lineStart: lineStart)
            // 这个分支只在"段落里一个字符都没有"时走（文末空行或空文档）。TextKit 把
            // 段落样式挂在字符上，而这里没有字符，所以把级别记成"待定"交给模型，并
            // 当场让协调器收到变更——否则在文末空行上选完标题、不输入就切走会丢掉
            // 这一级（原版把行属性存在 Delta 里，没有这个边界）。
            replaceEmptyBlock(range: range, content: NSAttributedString(string: ""),
                              typing: DocumentTextCodec.attributes(kind: resolved, marks: marks),
                              trailing: resolved == .paragraph ? nil : resolved)
            return
        }
        guard let storage = textStorage else { return }
        let selected = storage.attributedSubstring(from: range)
        var document = DocumentTextCodec.decode(selected, preserving: NativeDocument(plainText: selected.string))
        // 段尾换行解码会产生一个无字符的占位块，它不属于本次选中的段落，
        // 不能参与“全部已是此格式”的判断，否则再次点击列表按钮无法取消。
        let selectedBlocks = selected.string.hasSuffix("\n")
            ? Array(document.blocks.dropLast()) : document.blocks
        let remove = command.mark.map { mark in document.blocks.flatMap(\.runs).allSatisfy { $0.marks.contains(mark) } } ?? false
        // 段落类型：工具条与选区浮条（无 lineStart）是**切换**，斜杠面板带 lineStart 是**设值**。
        // 原版就是这么分的（`_toggleBlock` vs `_formatLine`，`document_commands.dart:242-279`）。
        let targetBlock = command.block.map { block in
            resolvedBlock(block,
                          current: document.blocks.first?.kind ?? .paragraph,
                          lineStart: lineStart,
                          allMatchCurrent: selectedBlocks.allSatisfy {
                              DocumentTextCodec.blockToken($0.kind) == DocumentTextCodec.blockToken(block)
                          })
        }
        for index in document.blocks.indices {
            if let block = targetBlock { document.blocks[index].kind = block }
            if let mark = command.mark {
                for run in document.blocks[index].runs.indices {
                    if remove { document.blocks[index].runs[run].marks.remove(mark) }
                    else { document.blocks[index].runs[run].marks.insert(mark) }
                }
            }
        }
        if command.mark != nil {
            // NSTextView may merge attributes omitted by the replacement string
            // from typingAttributes. Rendered runs carry their own marks, so clear
            // stale typing marks while replacing the selected attributed text.
            var cleanTypingAttributes = DocumentTextCodec.attributes(
                kind: document.blocks.first?.kind ?? .paragraph, marks: [])
            cleanTypingAttributes.removeValue(forKey: DocumentTextCodec.completedChecklistPresentationKey)
            typingAttributes = cleanTypingAttributes
        }
        let replacement = NSMutableAttributedString(attributedString: DocumentTextCodec.render(document))
        if case .strikethrough? = command.mark, !remove, replacement.length > 0 {
            // This deletion line now represents an explicit user mark, not just
            // the checked checklist's derived presentation.
            replacement.removeAttribute(DocumentTextCodec.completedChecklistPresentationKey,
                                        range: NSRange(location: 0, length: replacement.length))
        }
        insertText(replacement, replacementRange: range)
        if command.mark != nil,
           let storage = textStorage,
           range.location + replacement.length <= storage.length {
            // Replacing text with an attributed string can retain old keys when
            // the new run omits them. Reapply the rendered runs as exact attribute
            // sets so removed marks and presentation-only keys cannot leak through.
            replacement.enumerateAttributes(in: NSRange(location: 0, length: replacement.length)) {
                attributes, localRange, _ in
                let targetRange = NSRange(location: range.location + localRange.location,
                                          length: localRange.length)
                storage.setAttributes(attributes, range: targetRange)
            }
        }
        // Formatting expands to the paragraph, but must not replace the user's
        // caret/selection with that entire paragraph.
        let location = min(originalSelection.location, (string as NSString).length)
        let length = min(originalSelection.length, (string as NSString).length - location)
        setSelectedRange(NSRange(location: location, length: length))
        syncParagraphStyleAfterEdit(at: location)
        if command.mark != nil {
            // insertText publishes before the exact attribute correction above.
            // Publish the final storage as well, or persistence retains removed marks.
            didChangeText()
        }
    }

    /// 编辑之后把光标所在段的字号/段落样式再落一次，并让"接着输入"继承它。
    ///
    /// 两个原因，都对应"选完标题当场没变化、切走再回来才变"这个实测现象：
    ///
    /// 1. 空行在文档里就只有那一个换行字符。TextKit 在编辑时会把**段落分隔符**的
    ///    字体修正回基础字体（段落类型是我们自己的键，它不碰），于是空行看起来
    ///    还是 14pt，要等整篇重新渲染才按标题重排。原版 Quill 直接改 Delta 并重排
    ///    那一行，没有这道二次修正，所以在编辑之后把字号**再写一次**。
    /// 2. 原版 `formatText` 会把行格式留在输入位置上，之后敲进去的字就是标题字号。
    ///    原生只在"段落里一个字符都没有"时才设 `typingAttributes`，空行（有一个
    ///    换行）这条路上漏了，于是输入的字仍是旧字号。
    private func syncParagraphStyleAfterEdit(at location: Int) {
        guard let storage = textStorage else { return }
        let source = string as NSString
        guard source.length > 0 else { return }
        let caret = min(max(0, location), source.length)
        let paragraph = source.paragraphRange(for: NSRange(location: caret, length: 0))
        guard paragraph.length > 0 else { return }

        let selected = storage.attributedSubstring(from: paragraph)
        let decoded = DocumentTextCodec.decode(selected, preserving: NativeDocument(plainText: selected.string))
        let attributes = DocumentTextCodec.attributes(kind: decoded.blocks.first?.kind ?? .paragraph,
                                                      marks: decoded.blocks.first?.runs.first?.marks ?? [])
        typingAttributes = attributes

        // 段落分隔符（空行的唯一字符）承受整段的字号与段落样式。
        let separator = NSRange(location: NSMaxRange(paragraph) - 1, length: 1)
        if NSMaxRange(separator) <= storage.length, source.substring(with: separator) == "\n" {
            var patch: [NSAttributedString.Key: Any] = [:]
            if let font = attributes[.font] { patch[.font] = font }
            if let style = attributes[.paragraphStyle] { patch[.paragraphStyle] = style }
            if !patch.isEmpty {
                storage.addAttributes(patch, range: separator)
                invalidateDocumentLayout(for: separator)
            }
        }
        invalidateDocumentLayout(for: paragraph)
        needsDisplay = true
    }

    /// 段落类命令最终落到哪一种段落。
    ///
    /// - 带 `lineStart`：斜杠面板那条路，按**设值**处理（原版 `_formatLine`）。
    /// - 不带 `lineStart`：工具条与选区浮条那条路，按**切换**处理（原版 `_toggleBlock`）：
    ///   当前段落（或选区里每一段）已经是同一种，就回到正文；否则设成目标。
    /// - 「正文」永远按设值：它本身就是"取消段落格式"，没有可切换的目标。
    ///
    /// 此前段落类一律设值，于是"再点一次引用"不会取消，用户读成按钮失效。
    private func resolvedBlock(_ block: DocumentBlockKind?,
                               current: DocumentBlockKind,
                               lineStart: Int?,
                               allMatchCurrent: Bool = true) -> DocumentBlockKind {
        guard let block else { return current }
        guard lineStart == nil else { return block }
        let target = DocumentTextCodec.blockToken(block)
        guard target != DocumentTextCodec.blockToken(.paragraph) else { return block }
        let matches = allMatchCurrent && DocumentTextCodec.blockToken(current) == target
        return matches ? .paragraph : block
    }

}
