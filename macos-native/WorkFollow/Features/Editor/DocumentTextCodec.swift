import AppKit

/// TextKit attributes are an editing projection, never the stored document.
enum DocumentTextCodec {
    static let blockKey = NSAttributedString.Key("WorkFollow.block")
    static let attachmentKey = NSAttributedString.Key("WorkFollow.attachment")
    static let inlineCodeKey = NSAttributedString.Key("WorkFollow.inlineCode")
    static let explicitBoldKey = NSAttributedString.Key("WorkFollow.explicitBold")
    static func blockToken(_ kind: DocumentBlockKind) -> String {
        switch kind {
        case .paragraph: "paragraph"
        case .heading(let level): "h\(level)"
        case .bullet: "bullet"
        case .ordered: "ordered"
        case .checklist(let checked): checked ? "checked" : "checklist"
        case .quote: "quote"
        case .code: "code"
        case .divider: "divider"
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
        case "divider": return .divider
        default: return .paragraph
        }
    }
    /// 读一段富文本的"段落类型 + 每个 run 都带的标记"，供工具条显示激活态。
    ///
    /// 与 `applyFormat` 走同一套解码口径，所以"工具条显示激活"与"再点一次会取消"
    /// 判断的是同一件事，不会出现按钮亮着却取消不掉的错位。
    static func style(of attributed: NSAttributedString) -> DocumentSelectionStyle {
        let document = decode(attributed, preserving: NativeDocument(plainText: attributed.string))
        let token = document.blocks.first.map { blockToken($0.kind) } ?? blockToken(.paragraph)
        var intersection: Set<DocumentMark>?
        for block in document.blocks {
            for run in block.runs {
                intersection = intersection.map { $0.intersection(run.marks) } ?? run.marks
            }
        }
        return DocumentSelectionStyle(blockToken: token, marks: intersection ?? [])
    }

    static func attributes(kind: DocumentBlockKind, marks: Set<DocumentMark>,
                           textList: NSTextList? = nil) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 8
        // 正文 14 配 ~4pt 行距：原版 `lineBody` 是 1.50（14 × 1.5 = 21 的行盒，
        // 扣掉系统字体的自然行高约 17，多出来的就是这 4pt）。标题按原版的
        // `documentHeadingLine` 1.35 走，行距不动——它们是短行。
        style.lineSpacing = 4
        var size: CGFloat = 14
        if case .heading(let level) = kind { size = level == 1 ? 22 : level == 2 ? 19 : 16 }
        let isHeading: Bool = { if case .heading = kind { return true }; return false }()
        var font: NSFont
        if kind == .code || marks.contains(.code) {
            font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        } else if isHeading {
            // 标题是**半粗**、不是粗体：原版 `WorkFollowMacWeight.semibold` 是这套字阶
            // 的上限（`document_styles.dart:114` "中文一上粗体就发闷"）。
            font = NSFont.systemFont(ofSize: size, weight: .semibold)
        } else {
            font = NSFont.systemFont(ofSize: size)
        }
        if marks.contains(.bold) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if marks.contains(.italic) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        if kind == .quote { style.headIndent = 18; style.firstLineHeadIndent = 18 }
        if let textList = textList ?? makeTextList(for: kind) {
            style.textLists = [textList]
            style.headIndent = 22
        }
        var attrs: [NSAttributedString.Key: Any] = [
            blockKey: blockToken(kind), explicitBoldKey: marks.contains(.bold), .font: font, .paragraphStyle: style,
            .foregroundColor: kind == .quote ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        if marks.contains(.code) { attrs[inlineCodeKey] = true }
        if marks.contains(.underline) { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if marks.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if marks.contains(.highlight) { attrs[.backgroundColor] = NSColor.systemYellow.withAlphaComponent(0.45) }
        for mark in marks { if case .link(let target) = mark { attrs[.link] = target } }
        return attrs
    }
    static func render(_ document: NativeDocument) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        var previousListKind: DocumentBlockKind?
        var currentTextList: NSTextList?
        for (index, block) in document.blocks.enumerated() {
            if listMarkerFormat(for: block.kind) != nil {
                if previousListKind != block.kind {
                    currentTextList = makeTextList(for: block.kind)
                }
                previousListKind = block.kind
            } else {
                previousListKind = nil
                currentTextList = nil
            }
            for run in block.runs {
                var attrs = attributes(kind: block.kind, marks: run.marks, textList: currentTextList)
                if block.kind == .divider {
                    let attachment = NSTextAttachment()
                    attachment.attachmentCell = DocumentDividerCell()
                    attrs[.attachment] = attachment
                }
                if let file = run.attachment, let data = try? JSONEncoder().encode(file) {
                    attrs[attachmentKey] = data
                    attrs[.toolTip] = file.name
                    let attachment = NSTextAttachment()
                    if let image = Self.pastedImage(from: file) {
                        // 粘贴图片以 data URL 存在附件里（NativeDocument 暂无图片块类型），
                        // 渲染成真实图片；其余附件保持 📎 文本单元。
                        attachment.image = image
                        attachment.bounds = Self.imageBounds(for: image)
                    } else {
                        let cell = NSTextAttachmentCell(textCell: "📎 " + file.name)
                        attachment.attachmentCell = cell
                    }
                    attrs[.attachment] = attachment
                }
                result.append(NSAttributedString(string: run.text, attributes: attrs))
            }
            if index < document.blocks.count - 1 {
                let separatorKind = block.kind == .divider ? DocumentBlockKind.paragraph : block.kind
                let separatorList = separatorKind == block.kind ? currentTextList : nil
                result.append(NSAttributedString(string: "\n", attributes: attributes(
                    kind: separatorKind, marks: [], textList: separatorList)))
            }
        }
        return result
    }

    private static func makeTextList(for kind: DocumentBlockKind) -> NSTextList? {
        guard let marker = listMarkerFormat(for: kind) else { return nil }
        return NSTextList(markerFormat: marker, options: 0)
    }

    private static func listMarkerFormat(for kind: DocumentBlockKind) -> NSTextList.MarkerFormat? {
        switch kind {
        case .bullet: .disc
        case .ordered: .decimal
        case .checklist(let checked): .init(rawValue: checked ? "☑" : "☐")
        default: nil
        }
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
                if attrs[inlineCodeKey] as? Bool == true { marks.insert(.code) }
                if let font = attrs[.font] as? NSFont {
                    let traits = NSFontManager.shared.traits(of: font)
                    // Heading weight is presentation, not a user-applied mark.
                    // Preserve explicit bold on headings, while plain/rich-text
                    // paragraphs still accept font traits from native editing.
                    let isHeading: Bool = { if case .heading = kind { return true }; return false }()
                    if traits.contains(.boldFontMask), !isHeading || attrs[explicitBoldKey] as? Bool == true {
                        marks.insert(.bold)
                    }
                    if traits.contains(.italicFontMask) { marks.insert(.italic) }
                    if font.isFixedPitch && kind != .code { marks.insert(.code) }
                }
                if let value = attrs[.underlineStyle] as? Int, value != 0 { marks.insert(.underline) }
                if let value = attrs[.strikethroughStyle] as? Int, value != 0 { marks.insert(.strikethrough) }
                if attrs[.backgroundColor] != nil { marks.insert(.highlight) }
                if let link = attrs[.link] { marks.insert(.link(String(describing: link))) }
                let attachment = (attrs[attachmentKey] as? Data).flatMap { try? JSONDecoder().decode(NativeAttachment.self, from: $0) }
                runs.append(DocumentRun(text: plain.substring(with: range), marks: marks, attachment: attachment))
            }
            offset += length + 1
            return DocumentBlock(id: block.id, kind: kind, runs: runs)
        }
        return NativeDocument(blocks: blocks)
    }
}

final class DocumentDividerCell: NSTextAttachmentCell {
    var lineWidth: CGFloat = 240
    override func cellSize() -> NSSize { NSSize(width: lineWidth, height: 20) }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        NSColor.separatorColor.setFill()
        NSRect(x: cellFrame.minX, y: cellFrame.midY, width: cellFrame.width, height: 1).fill()
    }
}

extension DocumentTextCodec {
    /// 识别以 data URL 承载的粘贴图片附件（NativeTextView.paste 写入）。
    static func pastedImage(from file: NativeAttachment) -> NSImage? {
        guard file.storedName.hasPrefix("data:image/"),
              let comma = file.storedName.firstIndex(of: ","),
              let data = Data(base64Encoded: String(file.storedName[file.storedName.index(after: comma)...])) else { return nil }
        return NSImage(data: data)
    }

    /// 等比放入正文宽度内：上限 480×320，小图保持原尺寸不放大。
    static func imageBounds(for image: NSImage) -> NSRect {
        var size = image.size
        guard size.width > 0, size.height > 0 else { return NSRect(x: 0, y: 0, width: 1, height: 1) }
        let maximum = NSSize(width: 480, height: 320)
        if size.height > maximum.height {
            size.width *= maximum.height / size.height
            size.height = maximum.height
        }
        if size.width > maximum.width {
            size.height *= maximum.width / size.width
            size.width = maximum.width
        }
        return NSRect(x: 0, y: 0, width: max(1, ceil(size.width)), height: max(1, ceil(size.height)))
    }
}
