import AppKit

/// The private flavor keeps document structure; the public flavor is readable
/// Markdown. A clipboard fragment owns no task identity or source block IDs.
@MainActor
enum DocumentClipboardCodec {
    static let pasteboardType = NSPasteboard.PasteboardType("com.workfollow.document-fragment")

    struct Fragment {
        let document: NativeDocument
        let startsAtParagraphBoundary: Bool
        let endsAtParagraphBoundary: Bool

        init(document: NativeDocument, startsAtParagraphBoundary: Bool,
             endsAtParagraphBoundary: Bool) {
            self.document = document
            self.startsAtParagraphBoundary = startsAtParagraphBoundary
            self.endsAtParagraphBoundary = endsAtParagraphBoundary
        }
    }

    private struct Payload: Codable {
        let version: Int
        // Encode blocks directly: NativeDocument's persistence adapter can
        // normalize runs and intentionally discards marks inside code blocks.
        let blocks: [DocumentBlock]
        let startsAtParagraphBoundary: Bool
        let endsAtParagraphBoundary: Bool
    }

    static func fragment(from source: NSAttributedString, range: NSRange,
                         trailingBlock: DocumentBlockKind? = nil,
                         trailingIndentLevel: Int = 0, trailingListStart: Int? = nil) -> Fragment? {
        guard valid(range, in: source), range.length > 0 else { return nil }
        let selected = source.attributedSubstring(from: range)
        let document = DocumentTextCodec.decode(selected,
            preserving: NativeDocument(plainText: selected.string),
            trailing: NSMaxRange(range) == source.length ? trailingBlock : nil,
            trailingIndentLevel: trailingIndentLevel, trailingListStart: trailingListStart)
        return Fragment(document: document,
            startsAtParagraphBoundary: startsParagraph(range.location, in: source.string as NSString),
            endsAtParagraphBoundary: endsParagraph(NSMaxRange(range), in: source.string as NSString))
    }

    static func encodedData(for fragment: Fragment) throws -> Data {
        let blocks = fragment.document.blocks.map {
            DocumentBlock(kind: $0.kind, runs: $0.runs, indentLevel: $0.indentLevel, listStart: $0.listStart)
        }
        return try JSONEncoder().encode(Payload(version: 1, blocks: blocks,
            startsAtParagraphBoundary: fragment.startsAtParagraphBoundary,
            endsAtParagraphBoundary: fragment.endsAtParagraphBoundary))
    }

    static func decode(_ data: Data) -> Fragment? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == 1, !payload.blocks.isEmpty else { return nil }
        let blocks = payload.blocks.map {
            DocumentBlock(kind: $0.kind, runs: $0.runs, indentLevel: $0.indentLevel, listStart: $0.listStart)
        }
        return Fragment(document: NativeDocument(blocks: blocks),
            startsAtParagraphBoundary: payload.startsAtParagraphBoundary,
            endsAtParagraphBoundary: payload.endsAtParagraphBoundary)
    }

    /// Use the private flavor before file, image, HTML or RTF fallbacks.
    static func read(from pasteboard: NSPasteboard) -> Fragment? {
        pasteboard.data(forType: pasteboardType).flatMap(decode)
    }

    /// A dedicated diagram selection may publish its PNG/XML flavors before
    /// this general path. General rich selections publish a private document,
    /// semantic HTML/RTF and public Markdown.
    @discardableResult
    static func write(_ fragment: Fragment, to pasteboard: NSPasteboard) -> Bool {
        guard let data = try? encodedData(for: fragment) else { return false }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(data, forType: pasteboardType)
        item.setString(markdown(fragment), forType: .string)
        item.setString(DocumentExternalClipboardCodec.html(for: fragment), forType: .html)
        let rich = DocumentExternalClipboardCodec.publicAttributedString(for: fragment)
        if let rtf = DocumentRTFStructureCodec.data(from: rich) {
            item.setData(rtf, forType: .rtf)
        }
        return pasteboard.writeObjects([item])
    }

    /// Full blocks split a populated destination paragraph. Partial first/last
    /// paragraphs merge with the destination and keep its paragraph style.
    /// The caller inserts this value as one replacement/undo operation.
    static func attributedContent(for fragment: Fragment, replacing range: NSRange,
                                  in destination: NSAttributedString,
                                  trailingBlock: DocumentBlockKind? = nil,
                                  trailingIndentLevel: Int = 0, trailingListStart: Int? = nil) -> NSAttributedString? {
        guard valid(range, in: destination) else { return nil }
        let text = destination.string as NSString
        var blocks = fragment.document.blocks
        guard !blocks.isEmpty else { return nil }
        let hasParagraphBreak = fragment.document.plainText.contains("\n")
        let singleWhole = fragment.startsAtParagraphBoundary && fragment.endsAtParagraphBoundary
        let firstIsWhole = hasParagraphBreak ? fragment.startsAtParagraphBoundary : singleWhole
        let lastIsWhole = hasParagraphBreak ? fragment.endsAtParagraphBoundary : singleWhole
        let leadingKind = paragraphKind(at: range.location, in: destination, trailing: trailingBlock)
        let trailingKind = paragraphKind(at: NSMaxRange(range), in: destination, trailing: trailingBlock)
        func adoptDestinationLayout(_ index: Int, at location: Int, kind: DocumentBlockKind) {
            blocks[index].kind = kind
            let atTrailing = location == destination.length && (destination.length == 0 || destination.string.hasSuffix("\n"))
            let attributes = destination.length > 0 && !atTrailing
                ? destination.attributes(at: min(location, destination.length - 1), effectiveRange: nil) : [:]
            blocks[index].indentLevel = kind.isList
                ? (atTrailing ? trailingIndentLevel : attributes[DocumentTextCodec.indentKey] as? Int ?? 0) : 0
            blocks[index].listStart = kind == .ordered
                ? (atTrailing ? trailingListStart : attributes[DocumentTextCodec.listStartKey] as? Int) : nil
        }
        if !firstIsWhole { adoptDestinationLayout(0, at: range.location, kind: leadingKind) }
        if !lastIsWhole, blocks.count > 1 {
            adoptDestinationLayout(blocks.count - 1, at: NSMaxRange(range), kind: trailingKind)
        }
        let value = NSMutableAttributedString(string: "")
        if firstIsWhole && !startsParagraph(range.location, in: text) {
            value.append(NSAttributedString(string: "\n",
                attributes: DocumentTextCodec.attributes(kind: leadingKind, marks: [])))
        }
        value.append(DocumentTextCodec.render(NativeDocument(blocks: blocks)))
        let alreadyEndsWithBreak = value.string.hasSuffix("\n")
        let hasTrailingContent = NSMaxRange(range) < text.length
            && text.character(at: NSMaxRange(range)) != 0x0A
        if lastIsWhole && !alreadyEndsWithBreak && hasTrailingContent {
            value.append(NSAttributedString(string: "\n",
                attributes: DocumentTextCodec.attributes(kind: blocks.last!.kind, marks: [])))
        }
        return value
    }

    /// Matches the editor's Markdown dialect, including ~underline~ and
    /// ::highlight::. Private data, rather than this text, carries attachments
    /// and editable diagrams when pasting inside WorkFollow.
    static func markdown(_ fragment: Fragment) -> String {
        var blocks = fragment.document.blocks
        let hasParagraphBreak = fragment.document.plainText.contains("\n")
        let singleWhole = fragment.startsAtParagraphBoundary && fragment.endsAtParagraphBoundary
        if !(hasParagraphBreak ? fragment.startsAtParagraphBoundary : singleWhole), !blocks.isEmpty {
            blocks[0].kind = .paragraph
        }
        if !(hasParagraphBreak ? fragment.endsAtParagraphBoundary : singleWhole), !blocks.isEmpty {
            blocks[blocks.count - 1].kind = .paragraph
        }
        var lines: [String] = []
        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            if block.kind == .code {
                var code: [String] = []
                while index < blocks.count, blocks[index].kind == .code {
                    code.append(blocks[index].plainText)
                    index += 1
                }
                let body = code.joined(separator: "\n")
                let fence = String(repeating: "`", count: max(3, longestBacktickRun(in: body) + 1))
                lines.append(fence + "\n" + body + "\n" + fence)
                continue
            }
            let body = block.runs.map(markdownRun).joined()
            let ordinal = DocumentListStructure.ordinal(at: index, in: blocks)
            let indent = String(repeating: "  ", count: block.indentLevel)
            switch block.kind {
            case .paragraph: lines.append(body)
            case .heading(let level): lines.append(String(repeating: "#", count: max(1, min(6, level))) + " " + body)
            case .bullet: lines.append(indent + "- " + body)
            case .ordered: lines.append(indent + "\(ordinal). " + body)
            case .checklist(let checked): lines.append(indent + (checked ? "- [x] " : "- [ ] ") + body)
            case .quote: lines.append("> " + body.replacingOccurrences(of: "\n", with: "\n> "))
            case .divider: lines.append("---")
            case .code: break
            }
            index += 1
        }
        return lines.joined(separator: "\n")
    }

    private static func markdownRun(_ run: DocumentRun) -> String {
        if let file = run.attachment {
            let label = escape(file.name)
            let image = file.storedName.hasPrefix("data:image/") ? "!" : ""
            return image + "[" + label + "](<" + linkDestination(file.storedName) + ">)"
        }
        if let diagram = run.diagram {
            let label = escape(diagram.title)
            guard !diagram.previewPNG.isEmpty else { return "[流程图：" + label + "]" }
            return "![" + label + "](<data:image/png;base64," + diagram.previewPNG.base64EncodedString() + ">)"
        }
        var text: String
        if run.marks.contains(.code) {
            let fence = String(repeating: "`", count: max(1, longestBacktickRun(in: run.text) + 1))
            let pad = run.text.hasPrefix("`") || run.text.hasSuffix("`") ? " " : ""
            text = fence + pad + run.text + pad + fence
        } else {
            text = escape(run.text)
        }
        if run.marks.contains(.bold) { text = "**" + text + "**" }
        if run.marks.contains(.italic) { text = "*" + text + "*" }
        if run.marks.contains(.underline) { text = "~" + text + "~" }
        if run.marks.contains(.strikethrough) { text = "~~" + text + "~~" }
        if run.marks.contains(.highlight) { text = "::" + text + "::" }
        let links = run.marks.compactMap { mark -> String? in
            if case .link(let value) = mark { return value }; return nil
        }.sorted()
        if let link = links.first { text = "[" + text + "](<" + linkDestination(link) + ">)" }
        return text
    }

    private static func escape(_ text: String) -> String {
        let special = Set("\\`*_{}[]<>#+-.!|~")
        return text.map { special.contains($0) ? "\\" + String($0) : String($0) }.joined()
    }

    private static func linkDestination(_ value: String) -> String {
        value.replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: ">", with: "%3E")
            .replacingOccurrences(of: "\n", with: "")
    }

    private static func longestBacktickRun(in text: String) -> Int {
        var longest = 0, current = 0
        for character in text {
            current = character == "`" ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }

    private static func valid(_ range: NSRange, in source: NSAttributedString) -> Bool {
        range.location != NSNotFound && range.location >= 0 && range.length >= 0
            && range.location <= source.length && range.length <= source.length - range.location
    }

    private static func startsParagraph(_ location: Int, in text: NSString) -> Bool {
        location == 0 || (location <= text.length && text.character(at: location - 1) == 0x0A)
    }

    private static func endsParagraph(_ location: Int, in text: NSString) -> Bool {
        location == text.length || (location < text.length && text.character(at: location) == 0x0A)
            || (location > 0 && text.character(at: location - 1) == 0x0A)
    }

    private static func paragraphKind(at location: Int, in source: NSAttributedString,
                                      trailing: DocumentBlockKind?) -> DocumentBlockKind {
        if location == source.length, source.length == 0 || source.string.hasSuffix("\n") {
            return trailing ?? .paragraph
        }
        guard source.length > 0 else { return trailing ?? .paragraph }
        let anchor = min(location, source.length - 1)
        let paragraph = (source.string as NSString).paragraphRange(for: NSRange(location: anchor, length: 0))
        let token = source.attribute(DocumentTextCodec.blockKey, at: paragraph.location, effectiveRange: nil) as? String
        return DocumentTextCodec.kind(token ?? "paragraph")
    }
}
