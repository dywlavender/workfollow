import AppKit
import CoreFoundation

/// Cocoa retains RTF characters and list formatting, but currently drops the
/// heading level. Restore only explicit RTF paragraph/style metadata.
@MainActor
enum DocumentRTFStructureCodec {
    static func attributedString(from data: Data) -> NSAttributedString? {
        guard let value = NSAttributedString(rtf: data, documentAttributes: nil) else { return nil }
        let ranges = paragraphRanges(value.string)
        var scanner = Scanner(data)
        let structure = scanner.scan()
        guard structure.paragraphs.count == ranges.count else { return value }
        let result = NSMutableAttributedString(attributedString: value)
        for (paragraph, range) in zip(structure.paragraphs, ranges) {
            guard let level = structure.headerLevel(for: paragraph.format) else { continue }
            let style = (result.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?
                .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.headerLevel = level
            result.addAttribute(.paragraphStyle, value: style, range: range)
        }
        return result
    }

    /// Keep Cocoa's complete RTF payload, adding standard outlinelevel controls
    /// at body paragraph boundaries. Fonts, Unicode, lists and attachments are
    /// not reserialized by this compatibility layer.
    static func data(from value: NSAttributedString) -> Data? {
        guard let encoded = try? value.data(from: NSRange(location: 0, length: value.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) else { return nil }
        let ranges = paragraphRanges(value.string)
        let levels = ranges.map { range in
            (value.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel ?? 0
        }
        guard levels.contains(where: { $0 > 0 }) else { return encoded }
        var scanner = Scanner(encoded)
        let structure = scanner.scan()
        guard structure.paragraphs.count == levels.count else { return encoded }
        var output = Data(), offset = 0
        for (paragraph, level) in zip(structure.paragraphs, levels) {
            guard paragraph.insertion >= offset, paragraph.insertion <= encoded.count else { return encoded }
            output.append(encoded.subdata(in: offset..<paragraph.insertion))
            let outline = level > 0 ? min(8, level - 1) : 9
            output.append(Data("\\outlinelevel\(outline) ".utf8))
            offset = paragraph.insertion
        }
        output.append(encoded.subdata(in: offset..<encoded.count))
        return output
    }

    private static func paragraphRanges(_ string: String) -> [NSRange] {
        let text = string as NSString
        var ranges: [NSRange] = [], offset = 0
        while offset < text.length {
            let range = text.paragraphRange(for: NSRange(location: offset, length: 0))
            ranges.append(range); offset = NSMaxRange(range)
        }
        return ranges
    }

    private struct Format {
        var styleID = 0
        var outline: Int?
    }

    private struct Paragraph {
        let insertion: Int
        let format: Format
    }

    private struct Style {
        let outline: Int?
        let basedOn: Int?
        let name: String
    }

    private struct Structure {
        var styles: [Int: Style] = [:]
        var paragraphs: [Paragraph] = []

        func headerLevel(for format: Format) -> Int? {
            if let outline = format.outline { return Self.level(outline) }
            var next: Int? = format.styleID
            var visited: Set<Int> = []
            while let id = next, visited.insert(id).inserted, let style = styles[id] {
                if let outline = style.outline { return Self.level(outline) }
                let name = style.name.components(separatedBy: ";").first ?? style.name
                for alias in name.components(separatedBy: ",") {
                    let pattern = #"^\s*(?:heading|标题|標題)\s*([1-9])\s*$"#
                    if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                       let match = regex.firstMatch(in: alias, range: NSRange(location: 0, length: (alias as NSString).length)),
                       let level = Int((alias as NSString).substring(with: match.range(at: 1))) { return level }
                }
                next = style.basedOn
            }
            return nil
        }

        private static func level(_ outline: Int) -> Int? {
            guard (0...9).contains(outline) else { return nil }
            return outline == 9 ? 0 : outline + 1
        }
    }

    private struct Draft {
        let id: Int
        var outline: Int?
        var basedOn: Int?
        var units: [UInt16] = []
        var pendingBytes: [UInt8] = []

        mutating func flushBytes(encoding: String.Encoding) {
            guard !pendingBytes.isEmpty else { return }
            let text = String(data: Data(pendingBytes), encoding: encoding)
                ?? String(decoding: pendingBytes, as: UTF8.self)
            units += text.utf16; pendingBytes = []
        }
    }

    private struct Frame {
        var format = Format()
        var ignored = false
        var stylesheet = false
        var firstControl = true
        var unicodeFallback = 1
        var style: Draft?
    }

    /// This scanner reads paragraph metadata only. Cocoa remains the text/RTF
    /// decoder. Unknown destinations and binary image payloads are not text.
    private struct Scanner {
        private var lexer: Lexer
        private var frames = [Frame()]
        private var structure = Structure()
        private var current: Paragraph?
        private var rootInsertion = 0
        private var fallback = 0
        private var encoding = String.Encoding.windowsCP1252
        private let nonBody: Set<String> = ["fonttbl", "colortbl", "info", "pict", "object", "listtable",
            "listoverridetable", "listtext", "pntext", "header", "footer", "footnote", "annotation"]

        init(_ data: Data) { lexer = Lexer(data) }

        mutating func scan() -> Structure {
            while let token = lexer.next() {
                switch token.kind {
                case .open:
                    var copy = frames.last!; copy.firstControl = true; copy.style = nil
                    frames.append(copy)
                case .close:
                    if var draft = frames.last?.style {
                        draft.flushBytes(encoding: encoding)
                        structure.styles[draft.id] = Style(outline: draft.outline, basedOn: draft.basedOn,
                                                          name: String(decoding: draft.units, as: UTF16.self))
                    }
                    if frames.count > 1 { frames.removeLast() }
                case .star: frames[frames.count - 1].ignored = true
                case .characters(let bytes): consume(bytes, at: token.start)
                case .control(let name, let number): control(name, number: number, token: token)
                }
            }
            if let current { structure.paragraphs.append(current) }
            return structure
        }

        private mutating func consume(_ bytes: [UInt8], at start: Int) {
            let skipped = min(fallback, bytes.count)
            fallback -= skipped
            let bytes = Array(bytes.dropFirst(skipped))
            guard !bytes.isEmpty, !frames.last!.ignored else { return }
            if frames.last!.stylesheet {
                if let owner = frames.lastIndex(where: { $0.style != nil }) {
                    frames[owner].style!.pendingBytes += bytes
                }
            } else { beginParagraph(at: start) }
        }

        private mutating func beginParagraph(at start: Int) {
            guard current == nil else { return }
            current = Paragraph(insertion: min(rootInsertion, start), format: frames.last!.format)
        }

        private mutating func control(_ name: String, number: Int?, token: Token) {
            let index = frames.count - 1
            let first = frames[index].firstControl
            frames[index].firstControl = false
            if name == "stylesheet", first { frames[index].stylesheet = true; return }
            if first, nonBody.contains(name) { frames[index].ignored = true }
            if name == "uc", let number { frames[index].unicodeFallback = max(0, number) }
            if name == "ansicpg", let number, number >= 0, number <= 65535 {
                let value = CFStringConvertWindowsCodepageToEncoding(UInt32(number))
                if value != kCFStringEncodingInvalidId { encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(value)) }
            }
            guard !frames[index].ignored else { return }
            if frames[index].stylesheet {
                if name == "s", let number { frames[index].style = Draft(id: number) }
                if let owner = frames.lastIndex(where: { $0.style != nil }) {
                    if name == "outlinelevel" { frames[owner].style!.outline = number }
                    if name == "sbasedon" { frames[owner].style!.basedOn = number }
                    if name == "u", let number {
                        frames[owner].style!.flushBytes(encoding: encoding)
                        frames[owner].style!.units.append(UInt16(truncatingIfNeeded: number))
                        fallback = frames[index].unicodeFallback
                    }
                }
                return
            }
            switch name {
            case "pard": frames[index].format = Format()
            case "s":
                if let number { frames[index].format.styleID = number; frames[index].format.outline = nil }
            case "outlinelevel": frames[index].format.outline = number
            case "u":
                beginParagraph(at: token.start); fallback = frames[index].unicodeFallback; return
            case "tab", "line", "emdash", "endash", "bullet", "lquote", "rquote", "ldblquote", "rdblquote":
                beginParagraph(at: token.start); return
            case "par":
                beginParagraph(at: token.start)
                if let current { structure.paragraphs.append(current) }
                current = nil; rootInsertion = token.end; return
            default: break
            }
            if frames.count == 2, current == nil { rootInsertion = token.end }
        }
    }

    private struct Token {
        enum Kind { case open, close, star, control(String, Int?), characters([UInt8]) }
        let kind: Kind
        let start: Int
        let end: Int
    }

    private struct Lexer {
        let bytes: [UInt8]
        var offset = 0
        init(_ data: Data) { bytes = Array(data) }

        mutating func next() -> Token? {
            while offset < bytes.count {
                let start = offset, byte = bytes[offset]
                offset += 1
                if byte == 13 || byte == 10 { continue }
                if byte == 123 { return Token(kind: .open, start: start, end: offset) }
                if byte == 125 { return Token(kind: .close, start: start, end: offset) }
                guard byte == 92 else {
                    while offset < bytes.count, ![92, 123, 125, 13, 10].contains(bytes[offset]) { offset += 1 }
                    return Token(kind: .characters(Array(bytes[start..<offset])), start: start, end: offset)
                }
                guard offset < bytes.count else { return nil }
                let next = bytes[offset]; offset += 1
                if next == 42 { return Token(kind: .star, start: start, end: offset) }
                if next == 13 || next == 10 {
                    if next == 13, offset < bytes.count, bytes[offset] == 10 { offset += 1 }
                    return Token(kind: .control("par", nil), start: start, end: offset)
                }
                if next == 39, offset + 1 < bytes.count,
                   let high = hex(bytes[offset]), let low = hex(bytes[offset + 1]) {
                    offset += 2
                    return Token(kind: .characters([high * 16 + low]), start: start, end: offset)
                }
                if isLetter(next) {
                    let wordStart = offset - 1
                    while offset < bytes.count, isLetter(bytes[offset]) { offset += 1 }
                    let name = String(decoding: bytes[wordStart..<offset], as: UTF8.self).lowercased()
                    let numberStart = offset
                    if offset < bytes.count, bytes[offset] == 45 { offset += 1 }
                    while offset < bytes.count, (48...57).contains(bytes[offset]) { offset += 1 }
                    let number = Int(String(decoding: bytes[numberStart..<offset], as: UTF8.self))
                    if offset < bytes.count, bytes[offset] == 32 { offset += 1 }
                    if name == "bin", let number, number > 0 { offset += min(number, bytes.count - offset) }
                    return Token(kind: .control(name, number), start: start, end: offset)
                }
                return Token(kind: .characters([next == 126 ? 32 : next]), start: start, end: offset)
            }
            return nil
        }

        private func isLetter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
        private func hex(_ byte: UInt8) -> UInt8? {
            if (48...57).contains(byte) { return byte - 48 }
            if (65...70).contains(byte) { return byte - 55 }
            if (97...102).contains(byte) { return byte - 87 }
            return nil
        }
    }
}
