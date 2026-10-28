import AppKit

/// Public clipboard formats carry semantic paragraphs, rather than relying on
/// the editor's painted list markers or guessing headings from font sizes.
@MainActor
enum DocumentExternalClipboardCodec {
    typealias Fragment = DocumentClipboardCodec.Fragment

    static func read(from pasteboard: NSPasteboard,
                     destinationKind: DocumentBlockKind = .paragraph) -> Fragment? {
        guard destinationKind != .code else { return nil }
        let htmlValue = pasteboard.string(forType: .html).flatMap {
            fragment(fromHTML: $0, destinationKind: destinationKind)
        }
        var rtfValue: Fragment?
        if let data = pasteboard.data(forType: .rtf),
           let rich = DocumentRTFStructureCodec.attributedString(from: data),
           let value = fragment(from: rich, destinationKind: destinationKind) { rtfValue = value }
        if let htmlValue {
            // Some apps publish styled <p> HTML beside a fully structured RTF.
            // Restore only explicit headings on exactly matching paragraphs.
            if let rtfValue, htmlValue.document.plainText == rtfValue.document.plainText,
               htmlValue.document.blocks.count == rtfValue.document.blocks.count {
                var document = htmlValue.document
                var restored = false
                for index in document.blocks.indices where document.blocks[index].kind == .paragraph {
                    if case .heading = rtfValue.document.blocks[index].kind {
                        document.blocks[index].kind = rtfValue.document.blocks[index].kind
                        restored = true
                    }
                }
                if restored {
                    return Fragment(document: document, startsAtParagraphBoundary: true, endsAtParagraphBoundary: true)
                }
            }
            return htmlValue
        }
        if let rtfValue { return rtfValue }
        return pasteboard.string(forType: .string).flatMap {
            fragment(fromMarkdown: $0, destinationKind: destinationKind)
        }
    }

    static func fragment(from rich: NSAttributedString,
                         destinationKind: DocumentBlockKind = .paragraph) -> Fragment? {
        guard destinationKind != .code, rich.length > 0 else { return nil }
        let source = rich.string as NSString
        var blocks: [DocumentBlock] = []
        var listOrdinals: [ObjectIdentifier: Int] = [:]
        var structural = false, marked = false, offset = 0
        while offset < source.length {
            let paragraph = source.paragraphRange(for: NSRange(location: offset, length: 0))
            var range = paragraph
            if range.length > 0, source.character(at: NSMaxRange(range) - 1) == 0x0A { range.length -= 1 }
            let style = rich.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
            var kind: DocumentBlockKind = .paragraph
            var indentLevel = 0
            var listStart: Int?
            var visibleOrdinal: Int?
            if let level = style?.headerLevel, level > 0 {
                kind = .heading(min(6, level)); structural = true
            } else if let list = style?.textLists.last {
                kind = listKind(list); structural = true
                indentLevel = min(8, max(0, (style?.textLists.count ?? 1) - 1))
                // Cocoa's RTF reader can materialize its list label as tabs
                // and text, in addition to retaining NSTextList metadata.
                let line = source.substring(with: range) as NSString
                if let prefix = try? NSRegularExpression(pattern: "^\\t[^\\t\\r\\n]{1,16}\\t"),
                   let match = prefix.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length)) {
                    let label = line.substring(with: match.range).trimmingCharacters(in: .whitespaces)
                    visibleOrdinal = Int(label.trimmingCharacters(in: CharacterSet(charactersIn: ".)")))
                    range.location += match.range.length; range.length -= match.range.length
                }
                if kind == .ordered {
                    let identity = ObjectIdentifier(list)
                    let ordinal = visibleOrdinal ?? (listOrdinals[identity].map { $0 + 1 } ?? max(1, list.startingItemNumber))
                    listOrdinals[identity] = ordinal
                    let candidate = DocumentBlock(kind: .ordered, indentLevel: indentLevel)
                    let expected = DocumentListStructure.ordinal(at: blocks.count, in: blocks + [candidate])
                    if ordinal != expected { listStart = ordinal }
                }
            }
            var runs: [DocumentRun] = []
            rich.enumerateAttributes(in: range) { attributes, runRange, _ in
                let marks = inlineMarks(attributes)
                marked = marked || !marks.isEmpty
                append(DocumentRun(text: source.substring(with: runRange), marks: marks), to: &runs)
            }
            blocks.append(DocumentBlock(kind: kind, runs: runs.isEmpty ? [DocumentRun(text: "")] : runs,
                                        indentLevel: indentLevel, listStart: listStart))
            offset = NSMaxRange(paragraph)
        }
        if rich.string.hasSuffix("\n") { blocks.append(DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "")])) }
        return makeFragment(blocks, structural: structural, marked: marked)
    }

    static func fragment(fromMarkdown text: String,
                         destinationKind: DocumentBlockKind = .paragraph) -> Fragment? {
        guard destinationKind != .code, !text.isEmpty else { return nil }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var blocks: [DocumentBlock] = []
        var structural = false, marked = false, index = 0
        while index < lines.count {
            let line = lines[index]
            if let fence = openingFence(line) {
                structural = true
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.count >= fence, candidate.allSatisfy({ $0 == "`" }) { index += 1; break }
                    codeLines.append(lines[index]); index += 1
                }
                if codeLines.isEmpty { codeLines = [""] }
                blocks += codeLines.map { DocumentBlock(kind: .code, runs: [DocumentRun(text: $0)]) }
                continue
            }
            if line.isEmpty {
                blocks.append(DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "")]))
            } else if let parsedLine = markdownLine(line) {
                let parsed = parsedLine.block
                let kind = nativeKind(parsed.kind)
                structural = structural || kind != .paragraph
                let runs = parsed.inlines.map { inline -> DocumentRun in
                    let marks = Set(inline.marks.map(nativeMark))
                    marked = marked || !marks.isEmpty
                    return DocumentRun(text: inline.text, marks: marks)
                }
                var block = DocumentBlock(kind: kind,
                    runs: kind == .divider ? [DocumentRun(text: "\u{FFFC}")]
                        : (runs.isEmpty ? [DocumentRun(text: line)] : runs), indentLevel: parsedLine.indentLevel)
                if kind == .ordered, let ordinal = parsedLine.ordinal {
                    let expected = DocumentListStructure.ordinal(at: blocks.count, in: blocks + [block])
                    if ordinal != expected { block.listStart = ordinal }
                }
                blocks.append(block)
            } else {
                blocks.append(DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: line)]))
            }
            index += 1
        }
        return makeFragment(blocks, structural: structural, marked: marked)
    }

    static func fragment(fromHTML html: String,
                         destinationKind: DocumentBlockKind = .paragraph) -> Fragment? {
        // The system's older HTML tidy parser otherwise treats fragments as
        // Latin-1, even when their Swift string was encoded as UTF-8.
        var content = html.replacingOccurrences(of: #"^\s*<\?xml[^>]*\?>"#,
            with: "", options: .regularExpression)
        if content.range(of: #"<html(?:\s|>)"#, options: [.regularExpression, .caseInsensitive]) == nil {
            content = "<html><body>" + content + "</body></html>"
        }
        let encoded = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + content
        guard destinationKind != .code, let data = encoded.data(using: .utf8),
              let document = try? XMLDocument(data: data, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
              let root = document.rootElement() else { return nil }
        let reader = HTMLReader()
        reader.walk(root)
        reader.flush()
        return makeFragment(reader.blocks, structural: reader.structural, marked: reader.marked)
    }

    /// Publish native paragraph metadata instead of painted markers. Cocoa
    /// retains NSTextList in RTF but may discard headerLevel; semantic HTML is
    /// preferred when exact heading structure must survive between apps.
    static func publicAttributedString(for fragment: Fragment) -> NSAttributedString {
        let blocks = publicBlocks(fragment)
        let result = NSMutableAttributedString(attributedString: DocumentTextCodec.render(NativeDocument(blocks: blocks)))
        var offset = 0
        var chain: [(kind: DocumentBlockKind, list: NSTextList)] = []
        for (index, block) in blocks.enumerated() {
            let length = (block.plainText as NSString).length + (index < blocks.count - 1 ? 1 : 0)
            guard length > 0 else { continue }
            let style = (result.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)?
                .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.headerLevel = { if case .heading(let level) = block.kind { return min(6, max(1, level)) }; return 0 }()
            let format: NSTextList.MarkerFormat?
            switch block.kind {
            case .bullet: format = .disc
            case .ordered: format = .decimal
            case .checklist(let checked): format = checked ? .check : .box
            default: format = nil
            }
            if let format {
                let depth = min(8, max(0, block.indentLevel))
                if chain.count > depth + 1 { chain.removeLast(chain.count - depth - 1) }
                while chain.count < depth {
                    chain.append((.bullet, NSTextList(markerFormat: .disc, options: 0)))
                }
                let start = block.kind == .ordered ? DocumentListStructure.ordinal(at: index, in: blocks) : 1
                if chain.count == depth || chain[depth].kind != block.kind || block.listStart != nil {
                    let list = NSTextList(markerFormat: format, options: 0)
                    list.startingItemNumber = start
                    if chain.count > depth { chain[depth] = (block.kind, list) }
                    else { chain.append((block.kind, list)) }
                }
                style.textLists = chain.map(\.list)
                style.firstLineHeadIndent = CGFloat(depth) * 18
                style.headIndent = CGFloat(depth + 1) * 18
            } else {
                style.textLists = []; chain = []
            }
            result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: offset, length: length))
            offset += length
        }
        return result
    }

    static func html(for fragment: Fragment) -> String {
        let blocks = publicBlocks(fragment)
        var parts: [String] = [], index = 0
        while index < blocks.count {
            let block = blocks[index]
            if block.kind == .code {
                var lines: [String] = []
                while index < blocks.count, blocks[index].kind == .code {
                    lines.append(blocks[index].plainText); index += 1
                }
                parts.append("<pre><code>" + escapeHTML(lines.joined(separator: "\n")) + "</code></pre>")
                continue
            }
            if block.kind == .bullet || block.kind == .ordered || isChecklist(block.kind) {
                parts.append(htmlList(blocks, index: &index, depth: block.indentLevel))
                continue
            }
            let body = block.runs.map(htmlRun).joined()
            switch block.kind {
            case .heading(let level):
                let tag = "h\(min(6, max(1, level)))"; parts.append("<\(tag)>\(body)</\(tag)>")
            case .quote: parts.append("<blockquote><p>" + body + "</p></blockquote>")
            case .divider: parts.append("<hr />")
            default: parts.append("<p>" + body + "</p>")
            }
            index += 1
        }
        return "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" /></head><body>"
            + parts.joined() + "</body></html>"
    }

    private static func makeFragment(_ blocks: [DocumentBlock], structural: Bool, marked: Bool) -> Fragment? {
        guard !blocks.isEmpty, structural || marked else { return nil }
        let whole = structural || blocks.count > 1
        return Fragment(document: NativeDocument(blocks: blocks), startsAtParagraphBoundary: whole,
                        endsAtParagraphBoundary: whole)
    }

    private static func publicBlocks(_ fragment: Fragment) -> [DocumentBlock] {
        var blocks = fragment.document.blocks
        let multiline = fragment.document.plainText.contains("\n")
        let whole = fragment.startsAtParagraphBoundary && fragment.endsAtParagraphBoundary
        if !(multiline ? fragment.startsAtParagraphBoundary : whole), !blocks.isEmpty { blocks[0].kind = .paragraph }
        if !(multiline ? fragment.endsAtParagraphBoundary : whole), !blocks.isEmpty { blocks[blocks.count - 1].kind = .paragraph }
        return blocks
    }

    private static func listKind(_ list: NSTextList) -> DocumentBlockKind {
        if list.markerFormat == .check { return .checklist(true) }
        if list.markerFormat == .box { return .checklist(false) }
        let value = list.markerFormat.rawValue.lowercased()
        return ["decimal", "alpha", "roman", "hexadecimal", "octal"].contains(where: value.contains) ? .ordered : .bullet
    }

    private static func inlineMarks(_ attributes: [NSAttributedString.Key: Any]) -> Set<DocumentMark> {
        var marks: Set<DocumentMark> = []
        if let font = attributes[.font] as? NSFont {
            let traits = NSFontManager.shared.traits(of: font)
            if traits.contains(.boldFontMask) { marks.insert(.bold) }
            if traits.contains(.italicFontMask) { marks.insert(.italic) }
            if font.isFixedPitch { marks.insert(.code) }
        }
        if let value = attributes[.underlineStyle] as? Int, value != 0 { marks.insert(.underline) }
        if let value = attributes[.strikethroughStyle] as? Int, value != 0 { marks.insert(.strikethrough) }
        if let color = attributes[.backgroundColor] as? NSColor, color.alphaComponent > 0 { marks.insert(.highlight) }
        if let url = attributes[.link] as? URL { marks.insert(.link(url.absoluteString)) }
        else if let value = attributes[.link] as? String { marks.insert(.link(value)) }
        return marks
    }

    private static func nativeKind(_ value: MarkdownSyntax.BlockKind) -> DocumentBlockKind {
        switch value {
        case .paragraph: .paragraph
        case .heading(let level): .heading(level)
        case .bullet: .bullet
        case .ordered: .ordered
        case .checklist(let checked): .checklist(checked)
        case .quote: .quote
        case .codeBlock: .code
        case .divider: .divider
        }
    }

    private static func markdownLine(_ line: String) -> (block: MarkdownSyntax.Block, indentLevel: Int, ordinal: Int?)? {
        let prefix = line.prefix { $0 == " " || $0 == "\t" }
        let unindented = String(line.dropFirst(prefix.count))
        let nested = MarkdownSyntax.parse(unindented).blocks.first
        let parsed: MarkdownSyntax.Block?
        let indent: Int
        if let nested, nativeKind(nested.kind).isList {
            parsed = nested
            indent = min(8, prefix.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2)
        } else {
            parsed = MarkdownSyntax.parse(line).blocks.first; indent = 0
        }
        guard let parsed else { return nil }
        let ordinal = nativeKind(parsed.kind) == .ordered ? Int(unindented.prefix { $0.isNumber }) : nil
        return (parsed, indent, ordinal)
    }

    private static func htmlList(_ blocks: [DocumentBlock], index: inout Int, depth: Int) -> String {
        let first = blocks[index], firstIndex = index
        let ordered = first.kind == .ordered
        let category = listCategory(first.kind)
        let tag = ordered ? "ol" : "ul"
        let initial = ordered ? DocumentListStructure.ordinal(at: index, in: blocks) : 1
        let start = ordered && (initial != 1 || first.listStart != nil) ? " start=\"\(initial)\"" : ""
        // Preserve a copied subtree's absolute level without fabricating empty
        // parent items. Normal nested HTML still supplies its own hierarchy.
        let level = depth > 0 ? " data-workfollow-indent=\"\(depth)\"" : ""
        var value = "<" + tag + start + level + ">"
        var expected = initial
        while index < blocks.count, blocks[index].kind.isList,
              blocks[index].indentLevel == depth, listCategory(blocks[index].kind) == category {
            let item = blocks[index]
            let ordinal = ordered ? DocumentListStructure.ordinal(at: index, in: blocks) : 1
            let explicit = ordered && index != firstIndex && (item.listStart != nil || ordinal != expected)
                ? " value=\"\(ordinal)\"" : ""
            let checkbox: String
            if case .checklist(let checked) = item.kind {
                checkbox = "<input type=\"checkbox\"" + (checked ? " checked=\"checked\"" : "") + " />"
            } else { checkbox = "" }
            value += "<li" + explicit + ">" + checkbox + item.runs.map(htmlRun).joined()
            index += 1
            while index < blocks.count, blocks[index].kind.isList, blocks[index].indentLevel > depth {
                value += htmlList(blocks, index: &index, depth: blocks[index].indentLevel)
            }
            value += "</li>"; expected = ordinal + 1
        }
        return value + "</" + tag + ">"
    }

    private static func nativeMark(_ value: MarkdownSyntax.InlineMark) -> DocumentMark {
        switch value {
        case .bold: .bold
        case .italic: .italic
        case .underline: .underline
        case .highlight: .highlight
        case .strikethrough: .strikethrough
        case .code: .code
        case .link(let url): .link(url)
        }
    }

    private static func openingFence(_ text: String) -> Int? {
        let prefix = text.prefix { $0 == " " }
        guard prefix.count <= 3 else { return nil }
        let count = text.dropFirst(prefix.count).prefix { $0 == "`" }.count
        return count >= 3 ? count : nil
    }

    private static func isChecklist(_ kind: DocumentBlockKind) -> Bool {
        if case .checklist = kind { return true }; return false
    }

    private static func listCategory(_ kind: DocumentBlockKind) -> Int {
        if kind == .bullet { return 1 }; if kind == .ordered { return 2 }; if isChecklist(kind) { return 3 }; return 0
    }

    private static func append(_ run: DocumentRun, to runs: inout [DocumentRun]) {
        guard !run.text.isEmpty || run.attachment != nil || run.diagram != nil
                || run.table != nil || run.formula != nil else { return }
        if let last = runs.last, last.marks == run.marks, last.attachment == nil,
           last.diagram == nil, last.table == nil, last.formula == nil,
           run.attachment == nil, run.diagram == nil, run.table == nil, run.formula == nil {
            runs[runs.count - 1].text += run.text
        } else { runs.append(run) }
    }

    private static func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func htmlTable(_ table: NativeTable) -> String {
        var html = "<table>"
        for (row, cells) in table.rows.enumerated() {
            html += "<tr>"
            for cell in cells {
                let tag = row == 0 ? "th" : "td"
                html += "<\(tag)>" + escapeHTML(cell) + "</\(tag)>"
            }
            html += "</tr>"
        }
        return html + "</table>"
    }

    private static func htmlRun(_ run: DocumentRun) -> String {
        if let file = run.attachment {
            let target = escapeHTML(file.storedName), name = escapeHTML(file.name)
            return file.storedName.hasPrefix("data:image/") ? "<img src=\"\(target)\" alt=\"\(name)\" />"
                : "<a href=\"\(target)\">\(name)</a>"
        }
        if let diagram = run.diagram {
            return diagram.previewPNG.isEmpty ? escapeHTML(diagram.title)
                : "<img src=\"data:image/png;base64,\(diagram.previewPNG.base64EncodedString())\" alt=\"\(escapeHTML(diagram.title))\" />"
        }
        if let table = run.table {
            return htmlTable(table)
        }
        if let formula = run.formula {
            return "<code>" + escapeHTML(formula.latex) + "</code>"
        }
        var value = escapeHTML(run.text)
        for (mark, tag) in [(DocumentMark.bold, "strong"), (.italic, "em"), (.underline, "u"),
                            (.strikethrough, "s"), (.highlight, "mark"), (.code, "code")] {
            if run.marks.contains(mark) { value = "<\(tag)>\(value)</\(tag)>" }
        }
        for mark in run.marks {
            if case .link(let target) = mark { value = "<a href=\"\(escapeHTML(target))\">\(value)</a>"; break }
        }
        return value
    }

    @MainActor private final class HTMLReader {
        final class ListContext {
            let kind: DocumentBlockKind
            let depth: Int
            let start: Int?
            private var first = true
            init(kind: DocumentBlockKind, depth: Int, start: Int?) {
                self.kind = kind; self.depth = min(8, max(0, depth)); self.start = start
            }
            func itemStart(_ value: Int?) -> Int? {
                defer { first = false }
                return kind == .ordered ? (value ?? (first ? start : nil)) : nil
            }
        }
        var blocks: [DocumentBlock] = []
        var structural = false, marked = false
        private var runs: [DocumentRun] = []
        private var kind: DocumentBlockKind = .paragraph
        private var indentLevel = 0
        private var listStart: Int?
        private var started = false

        func flush(force: Bool = false) {
            if started || force {
                blocks.append(DocumentBlock(kind: kind, runs: runs.isEmpty ? [DocumentRun(text: "")] : runs,
                                            indentLevel: indentLevel, listStart: listStart))
            }
            runs = []; started = false
        }

        private func begin(_ value: DocumentBlockKind, indent: Int, start: Int?) {
            if !runs.isEmpty { flush() }
            runs = []; kind = value; indentLevel = indent; listStart = start; started = true
        }

        func walk(_ node: XMLNode, defaultKind: DocumentBlockKind = .paragraph,
                  list: ListContext? = nil, marks: Set<DocumentMark> = []) {
            if node.kind == .text {
                let text = node.stringValue ?? ""
                guard started || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                if !started { kind = defaultKind; indentLevel = list?.depth ?? 0; listStart = nil }
                started = true; marked = marked || !marks.isEmpty
                append(DocumentRun(text: text, marks: marks), to: &runs); return
            }
            guard let element = node as? XMLElement else { return }
            let tag = (element.localName ?? element.name ?? "").lowercased()
            if ["head", "style", "script", "meta", "input"].contains(tag) { return }
            if tag == "pre" {
                flush(); structural = true
                blocks += (element.stringValue ?? "").replacingOccurrences(of: "\r\n", with: "\n")
                    .components(separatedBy: "\n").map { DocumentBlock(kind: .code, runs: [DocumentRun(text: $0)]) }
                return
            }
            if tag == "hr" { flush(); structural = true; blocks.append(DocumentBlock(kind: .divider, runs: [DocumentRun(text: "\u{FFFC}")])); return }
            if tag == "br" { flush(force: true); started = true; return }
            if tag == "img", let src = element.attribute(forName: "src")?.stringValue, src.hasPrefix("data:image/") {
                started = true; structural = true
                append(DocumentRun(text: "\u{FFFC}", attachment: NativeAttachment(id: UUID(),
                    name: element.attribute(forName: "alt")?.stringValue ?? "图片", storedName: src)), to: &runs)
                return
            }
            if tag == "ol" || tag == "ul" {
                flush(); structural = true
                let explicitDepth = element.attribute(forName: "data-workfollow-indent")?.stringValue.flatMap(Int.init)
                let context = ListContext(kind: tag == "ol" ? .ordered : .bullet,
                    depth: explicitDepth ?? ((list?.depth ?? -1) + 1),
                    start: tag == "ol" ? element.attribute(forName: "start")?.stringValue.flatMap(Int.init) : nil)
                for child in element.children ?? [] { walk(child, defaultKind: defaultKind, list: context, marks: marks) }
                flush(); return
            }
            var localMarks = marks
            switch tag {
            case "b", "strong": localMarks.insert(.bold)
            case "i", "em": localMarks.insert(.italic)
            case "u": localMarks.insert(.underline)
            case "s", "strike", "del": localMarks.insert(.strikethrough)
            case "mark": localMarks.insert(.highlight)
            case "code": localMarks.insert(.code)
            case "a": if let target = element.attribute(forName: "href")?.stringValue { localMarks.insert(.link(target)) }
            default: break
            }
            let css = element.attribute(forName: "style")?.stringValue?.lowercased() ?? ""
            if css.range(of: #"font-weight\s*:\s*(bold|[6-9]00)"#, options: .regularExpression) != nil { localMarks.insert(.bold) }
            if css.contains("font-style: italic") || css.contains("font-style:italic") { localMarks.insert(.italic) }
            if css.contains("text-decoration"), css.contains("underline") { localMarks.insert(.underline) }
            if css.contains("text-decoration"), css.contains("line-through") { localMarks.insert(.strikethrough) }
            if css.contains("background-color"), !css.contains("transparent") { localMarks.insert(.highlight) }
            let heading = tag.count == 2 && tag.hasPrefix("h") ? Int(tag.dropFirst()) : nil
            let isBlock = ["p", "div", "li", "blockquote"].contains(tag) || (heading.map { (1...6).contains($0) } ?? false)
            var childKind = defaultKind
            var start: Int?
            if let heading, (1...6).contains(heading) { childKind = .heading(heading); structural = true }
            else if tag == "blockquote" { childKind = .quote; structural = true }
            else if tag == "li" {
                childKind = list?.kind ?? .bullet; structural = true
                start = list?.itemStart(element.attribute(forName: "value")?.stringValue.flatMap(Int.init))
                if let input = checkbox(in: element) {
                    childKind = .checklist(input.attribute(forName: "checked") != nil)
                }
            }
            let blockCount = blocks.count
            if isBlock {
                if tag != "li", started, runs.isEmpty, kind == childKind { start = listStart }
                begin(childKind, indent: childKind.isList ? (list?.depth ?? 0) : 0, start: start)
            }
            for child in element.children ?? [] { walk(child, defaultKind: childKind, list: list, marks: localMarks) }
            if isBlock { flush(force: blocks.count == blockCount && !["div", "blockquote"].contains(tag)) }
        }

        private func checkbox(in element: XMLElement) -> XMLElement? {
            for child in element.children ?? [] {
                guard let child = child as? XMLElement else { continue }
                let tag = (child.localName ?? child.name)?.lowercased()
                if ["ol", "ul", "li"].contains(tag) { continue }
                if tag == "input",
                   child.attribute(forName: "type")?.stringValue?.lowercased() == "checkbox" { return child }
                if let found = checkbox(in: child) { return found }
            }
            return nil
        }
    }
}
