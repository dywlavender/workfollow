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
        .init(title: "待办清单", block: .checklist(false), mark: nil),
        .init(title: "勾选清单项", block: .checklist(true), mark: nil),
        .init(title: "粗体", block: nil, mark: .bold),
        .init(title: "斜体", block: nil, mark: .italic),
        .init(title: "下划线", block: nil, mark: .underline),
        .init(title: "删除线", block: nil, mark: .strikethrough),
        .init(title: "高亮", block: nil, mark: .highlight)
    ]
}

extension NativeTextView {
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

    func applyFormat(_ command: DocumentFormatCommand) {
        var range = selectedRange()
        if command.block != nil { range = (string as NSString).paragraphRange(for: range) }
        if range.length == 0 {
            let token = typingAttributes[DocumentTextCodec.blockKey] as? String ?? "paragraph"
            typingAttributes = DocumentTextCodec.attributes(kind: command.block ?? DocumentTextCodec.kind(token), marks: command.mark.map { [$0] } ?? [])
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
        setSelectedRange(range)
    }
}
