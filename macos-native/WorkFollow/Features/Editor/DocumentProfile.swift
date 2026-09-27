import AppKit

/// Hosts supply business actions; the shared editor only executes descriptors.
struct DocumentCommand: Identifiable {
    let id: String
    let title: String
    let group: String
    var keywords: String = ""
    let perform: (NativeTextView) -> Void
    var performSlash: ((NativeTextView, SlashCommandInvocation) -> Void)?

    init(id: String, title: String, group: String, keywords: String = "",
         perform: @escaping (NativeTextView) -> Void) {
        self.id = id
        self.title = title
        self.group = group
        self.keywords = keywords
        self.perform = perform
        self.performSlash = nil
    }

    init(id: String, title: String, group: String, keywords: String = "",
         perform: @escaping (NativeTextView) -> Void,
         slash: @escaping (NativeTextView, SlashCommandInvocation) -> Void) {
        self.id = id
        self.title = title
        self.group = group
        self.keywords = keywords
        self.perform = perform
        self.performSlash = slash
    }
}

/// Offsets captured before `/query` is removed, in NSTextView's UTF-16 space.
/// This mirrors Flutter's DocumentSlashInvocation and anchors block commands
/// to the line where the user opened the palette.
struct SlashCommandInvocation {
    let lineStart: Int
    let slashOffset: Int
}

struct DocumentSelectionAction: Identifiable {
    let id: String
    let title: String
    let perform: (String) -> Void
}

struct DocumentProfile {
    var commands: [DocumentCommand] = []
    var selectionActions: [DocumentSelectionAction] = []
    var taskSlash = false
    var noteSlash = false
    var compactSlash: Bool { taskSlash || noteSlash }
    var onOpenLink: ((String) -> Bool)?
    var slashCommands: [DocumentCommand] {
        if compactSlash {
            let formats = [1, 2, 14, 5, 6, 7, 3].map { DocumentFormatCommand.commands[$0] }
            return formats.enumerated().map { index, format in
                DocumentCommand(id: "task.format.\(index)", title: format.title, group: "格式",
                                perform: { $0.applyFormat(format) },
                                slash: { view, invocation in
                                    view.applyFormat(format, lineStart: invocation.lineStart)
                                })
            } + [
                DocumentCommand(id: "shared.divider", title: "水平分割线", group: "格式",
                                perform: { $0.insertDocumentDivider() },
                                slash: { view, invocation in
                                    view.insertDocumentDivider(at: invocation.slashOffset)
                                }),
                DocumentCommand(id: "shared.attachment", title: "附件", group: "插入",
                                perform: { $0.insertDocumentAttachment(nil) },
                                slash: { view, invocation in
                                    view.insertDocumentAttachment(at: invocation.slashOffset)
                                })
            ] + commands
        }
        return DocumentFormatCommand.commands.enumerated().map { index, format in
            DocumentCommand(id: "format.\(index)", title: format.title,
                            group: format.block == nil ? "文字格式" : "段落",
                            keywords: format.keywords,
                            perform: { $0.applyFormat(format) },
                            slash: { view, invocation in
                                view.applyFormat(format, lineStart: invocation.lineStart)
                            })
        } + [
            DocumentCommand(id: "shared.link", title: "编辑链接", group: "正文", keywords: "link url") { $0.editDocumentLink(nil) },
            DocumentCommand(id: "shared.attachment", title: "插入附件", group: "正文", keywords: "attachment file",
                            perform: { $0.insertDocumentAttachment(nil) },
                            slash: { view, invocation in
                                view.insertDocumentAttachment(at: invocation.slashOffset)
                            })
        ] + commands
    }
}

struct SlashSession {
    let start: Int
    private(set) var range: NSRange
    private(set) var query = ""
    private(set) var selectedIndex = 0

    init(start: Int) { self.start = start; range = NSRange(location: start, length: 1) }

    mutating func update(text: String, selection: NSRange, allowsQuery: Bool = true) -> Bool {
        let text = text as NSString
        guard selection.length == 0, selection.location > start,
              selection.location <= text.length, start >= 0,
              text.substring(with: NSRange(location: start, length: 1)) == "/" else { return false }
        let range = NSRange(location: start, length: selection.location - start)
        let query = String(text.substring(with: range).dropFirst())
        guard allowsQuery || query.isEmpty else { return false }
        guard !query.contains("\n"), !query.contains("/") else { return false }
        if self.query != query { selectedIndex = 0 }
        self.query = query
        self.range = range
        return true
    }

    func results(in commands: [DocumentCommand]) -> [DocumentCommand] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return commands.filter { needle.isEmpty || ($0.title + " " + $0.keywords).localizedCaseInsensitiveContains(needle) }
    }

    mutating func move(_ offset: Int, count: Int) {
        guard count > 0 else { selectedIndex = 0; return }
        selectedIndex = (selectedIndex + offset + count) % count
    }
}
