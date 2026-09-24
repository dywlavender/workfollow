import AppKit

/// TextKit attributes are an editing projection, never the stored document.
enum DocumentTextCodec {
    static let blockKey = NSAttributedString.Key("WorkFollow.block")
    static func blockToken(_ kind: DocumentBlockKind) -> String {
        switch kind {
        case .paragraph: "paragraph"
        case .heading(let level): "h\(level)"
        case .bullet: "bullet"
        case .ordered: "ordered"
        case .checklist(let checked): checked ? "checked" : "checklist"
        case .quote: "quote"
        case .code: "code"
        }
    }
    static func kind(_ token: String) -> DocumentBlockKind {
        if token.hasPrefix("h"), let level = Int(token.dropFirst()) { return .heading(level) }
        switch token {
        case "bullet": return .bullet
        case "ordered": return .ordered
        case "checklist": return .checklist(false)
        case "checked": return .checklist(true)
        case "quote": return .quote
        case "code": return .code
        default: return .paragraph
        }
    }
    static func attributes(kind: DocumentBlockKind, marks: Set<DocumentMark>) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 6
        var size: CGFloat = 15
        if case .heading(let level) = kind { size = level == 1 ? 24 : 20 }
        var font = kind == .code || marks.contains(.code)
            ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular) : NSFont.systemFont(ofSize: size)
        if marks.contains(.bold) || { if case .heading = kind { return true }; return false }() {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if marks.contains(.italic) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        if kind == .quote { style.headIndent = 18; style.firstLineHeadIndent = 18 }
        if kind == .bullet || kind == .ordered {
            style.textLists = [NSTextList(markerFormat: kind == .bullet ? .disc : .decimal, options: 0)]
            style.headIndent = 22
        }
        var attrs: [NSAttributedString.Key: Any] = [
            blockKey: blockToken(kind), .font: font, .paragraphStyle: style,
            .foregroundColor: kind == .quote ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        if marks.contains(.underline) { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if marks.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if marks.contains(.highlight) { attrs[.backgroundColor] = NSColor.systemYellow.withAlphaComponent(0.45) }
        for mark in marks { if case .link(let target) = mark { attrs[.link] = target } }
        return attrs
    }
    static func render(_ document: NativeDocument) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for (index, block) in document.blocks.enumerated() {
            for run in block.runs {
                result.append(NSAttributedString(string: run.text, attributes: attributes(kind: block.kind, marks: run.marks)))
            }
            if index < document.blocks.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: attributes(kind: block.kind, marks: [])))
            }
        }
        return result
    }
    static func decode(_ text: NSAttributedString, preserving previous: NativeDocument) -> NativeDocument {
        let plain = text.string as NSString
        let skeleton = previous.replacingPlainText(text.string)
        var offset = 0
        let blocks = skeleton.blocks.map { block -> DocumentBlock in
            let length = (block.plainText as NSString).length
            var runs: [DocumentRun] = []
            var kind: DocumentBlockKind = .paragraph
            if offset < text.length, let token = text.attribute(blockKey, at: offset, effectiveRange: nil) as? String {
                kind = Self.kind(token)
            }
            text.enumerateAttributes(in: NSRange(location: min(offset, text.length), length: length)) { attrs, range, _ in
                var marks = Set<DocumentMark>()
                if let font = attrs[.font] as? NSFont {
                    let traits = NSFontManager.shared.traits(of: font)
                    if traits.contains(.boldFontMask) { marks.insert(.bold) }
                    if traits.contains(.italicFontMask) { marks.insert(.italic) }
                    if font.isFixedPitch { marks.insert(.code) }
                }
                if let value = attrs[.underlineStyle] as? Int, value != 0 { marks.insert(.underline) }
                if let value = attrs[.strikethroughStyle] as? Int, value != 0 { marks.insert(.strikethrough) }
                if attrs[.backgroundColor] != nil { marks.insert(.highlight) }
                if let link = attrs[.link] { marks.insert(.link(String(describing: link))) }
                runs.append(DocumentRun(text: plain.substring(with: range), marks: marks))
            }
            offset += length + 1
            return DocumentBlock(id: block.id, kind: kind, runs: runs)
        }
        return NativeDocument(blocks: blocks)
    }
}
