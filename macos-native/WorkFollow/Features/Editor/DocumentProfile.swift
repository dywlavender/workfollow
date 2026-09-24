import AppKit

/// Hosts supply business actions; the shared editor only executes descriptors.
struct DocumentCommand: Identifiable {
    let id: String
    let title: String
    let group: String
    var keywords: String = ""
    let perform: (NativeTextView) -> Void
}

struct DocumentSelectionAction: Identifiable {
    let id: String
    let title: String
    let perform: (String) -> Void
}

struct DocumentProfile {
    var commands: [DocumentCommand] = []
    var selectionActions: [DocumentSelectionAction] = []
    var slashCommands: [DocumentCommand] {
        DocumentFormatCommand.commands.enumerated().map { index, format in
            DocumentCommand(id: "format.\(index)", title: format.title,
                            group: format.block == nil ? "文字格式" : "段落",
                            keywords: format.keywords) { $0.applyFormat(format) }
        } + [
            DocumentCommand(id: "shared.link", title: "编辑链接", group: "正文", keywords: "link url") { $0.editDocumentLink(nil) },
            DocumentCommand(id: "shared.attachment", title: "插入附件", group: "正文", keywords: "attachment file") { $0.insertDocumentAttachment(nil) }
        ] + commands
    }
}

struct SlashSession {
    let start: Int
    private(set) var range: NSRange
    private(set) var query = ""
    private(set) var selectedIndex = 0

    init(start: Int) { self.start = start; range = NSRange(location: start, length: 1) }

    mutating func update(text: String, selection: NSRange) -> Bool {
        let text = text as NSString
        guard selection.length == 0, selection.location > start,
              selection.location <= text.length, start >= 0,
              text.substring(with: NSRange(location: start, length: 1)) == "/" else { return false }
        let range = NSRange(location: start, length: selection.location - start)
        let query = String(text.substring(with: range).dropFirst())
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
