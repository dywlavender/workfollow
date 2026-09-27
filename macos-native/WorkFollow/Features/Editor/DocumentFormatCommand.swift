import AppKit

struct DocumentFormatCommand {
    let title: String
    let block: DocumentBlockKind?
    let mark: DocumentMark?
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
        .init(title: "正文", block: .paragraph, mark: nil),
        .init(title: "一级标题", block: .heading(1), mark: nil),
        .init(title: "二级标题", block: .heading(2), mark: nil),
        .init(title: "引用", block: .quote, mark: nil),
        .init(title: "代码块", block: .code, mark: nil),
        .init(title: "无序列表", block: .bullet, mark: nil),
        .init(title: "有序列表", block: .ordered, mark: nil),
        .init(title: "检查项", block: .checklist(false), mark: nil),
        .init(title: "勾选清单项", block: .checklist(true), mark: nil),
        .init(title: "粗体", block: nil, mark: .bold),
        .init(title: "斜体", block: nil, mark: .italic),
        .init(title: "下划线", block: nil, mark: .underline),
        .init(title: "删除线", block: nil, mark: .strikethrough),
        .init(title: "高亮", block: nil, mark: .highlight),
        .init(title: "三级标题", block: .heading(3), mark: nil),
        .init(title: "行内代码", block: nil, mark: .code)
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
            if source.length == 0 {
                range = NSRange(location: 0, length: 0)
            } else if let lineStart {
                let location = min(max(0, lineStart), source.length - 1)
                range = source.paragraphRange(for: NSRange(location: location, length: 0))
            } else {
                range = source.paragraphRange(for: originalSelection)
            }
            if let block = command.block,
               block == .bullet || block == .ordered || isChecklist(block),
               let storage = textStorage {
                range = listRunRange(around: range, token: DocumentTextCodec.blockToken(block),
                                     source: source, storage: storage)
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
            typingAttributes = DocumentTextCodec.attributes(kind: command.block ?? DocumentTextCodec.kind(token), marks: marks)
            return
        }
        guard let storage = textStorage else { return }
        let selected = storage.attributedSubstring(from: range)
        var document = DocumentTextCodec.decode(selected, preserving: NativeDocument(plainText: selected.string))
        let remove = command.mark.map { mark in document.blocks.flatMap(\.runs).allSatisfy { $0.marks.contains(mark) } } ?? false
        for index in document.blocks.indices {
            if let block = command.block { document.blocks[index].kind = block }
            if let mark = command.mark {
                for run in document.blocks[index].runs.indices {
                    if remove { document.blocks[index].runs[run].marks.remove(mark) }
                    else { document.blocks[index].runs[run].marks.insert(mark) }
                }
            }
        }
        insertText(DocumentTextCodec.render(document), replacementRange: range)
        // Formatting expands to the paragraph, but must not replace the user's
        // caret/selection with that entire paragraph.
        let location = min(originalSelection.location, (string as NSString).length)
        let length = min(originalSelection.length, (string as NSString).length - location)
        setSelectedRange(NSRange(location: location, length: length))
    }

    private func listRunRange(around range: NSRange, token: String,
                              source: NSString, storage: NSTextStorage) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)

        while start > 0 {
            let previous = source.paragraphRange(for: NSRange(location: start - 1, length: 0))
            guard previous.location < start,
                  storage.attribute(DocumentTextCodec.blockKey, at: previous.location, effectiveRange: nil) as? String == token
            else { break }
            start = previous.location
            end = max(end, NSMaxRange(previous))
        }

        while end < source.length {
            let next = source.paragraphRange(for: NSRange(location: end, length: 0))
            guard next.location >= end, next.location < storage.length,
                  storage.attribute(DocumentTextCodec.blockKey, at: next.location, effectiveRange: nil) as? String == token
            else { break }
            end = max(end, NSMaxRange(next))
        }
        return NSRange(location: start, length: min(end, source.length) - start)
    }

    private func isChecklist(_ kind: DocumentBlockKind) -> Bool {
        if case .checklist = kind { return true }
        return false
    }
}
