import AppKit
import Foundation
import UniformTypeIdentifiers

enum SummaryExportFormat: String, CaseIterable, Hashable {
    case plainText, markdown, image, pdf

    var menuTitle: String {
        switch self {
        case .plainText: "文本 (.txt)"
        case .markdown: "Markdown (.md)"
        case .image: "图片 (.png)"
        case .pdf: "PDF (.pdf)"
        }
    }
    var fileExtension: String {
        switch self {
        case .plainText: "txt"
        case .markdown: "md"
        case .image: "png"
        case .pdf: "pdf"
        }
    }
    var contentType: UTType {
        switch self {
        case .plainText: .plainText
        case .markdown: UTType(filenameExtension: "md") ?? .plainText
        case .image: .png
        case .pdf: .pdf
        }
    }
    func suggestedFileName(for title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let stem = title.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (stem.isEmpty ? "摘要" : stem) + "." + fileExtension
    }
}

enum SummaryExportError: LocalizedError, Equatable {
    case emptyDocument
    case renderFailed
    case imageTooLong

    var errorDescription: String? {
        switch self {
        case .emptyDocument: "摘要为空，暂无可导出的内容"
        case .renderFailed: "无法生成导出文件"
        case .imageTooLong: "摘要内容过多，无法导出图片，请改用 PDF"
        }
    }
}

/// 摘要「保存为」：纯文本、Markdown、PNG 长图与 PDF。
/// 文本/Markdown 保留文档块结构；图片与 PDF 用固定的浅色版式渲染，
/// 不依赖当前窗口主题，导出的文件可以直接分享。
enum SummaryExportService {
    @MainActor
    static func data(for document: NativeDocument, format: SummaryExportFormat) throws -> Data {
        switch format {
        case .plainText:
            let text = plainText(document)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SummaryExportError.emptyDocument
            }
            return Data(text.utf8)
        case .markdown:
            let text = markdown(document)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SummaryExportError.emptyDocument
            }
            return Data(text.utf8)
        case .image:
            return try imageData(document)
        case .pdf:
            return try pdfData(document)
        }
    }

    // MARK: - Plain text / Markdown

    static func plainText(_ document: NativeDocument) -> String {
        renderBlocks(document) { block, ordinal in
            let prefix: String
            switch block.kind {
            case .bullet: prefix = "• "
            case .ordered: prefix = "\(ordinal). "
            case .checklist(let checked): prefix = checked ? "☑ " : "☐ "
            case .quote: prefix = "│ "
            case .divider: prefix = ""
            default: prefix = ""
            }
            let text = block.kind == .divider ? "──────────" : plainRuns(block.runs)
            guard !text.isEmpty else { return "" }
            return listIndent(block) + prefix + text
        }
    }

    static func markdown(_ document: NativeDocument) -> String {
        renderBlocks(document) { block, ordinal in
            let indent = String(repeating: "  ", count: max(0, block.indentLevel))
            let body = block.runs.map(markdownRun).joined()
            switch block.kind {
            case .paragraph:
                return body
            case .heading(let level):
                return String(repeating: "#", count: max(1, min(6, level))) + " " + body
            case .bullet:
                return indent + "- " + body
            case .ordered:
                return indent + "\(ordinal). " + body
            case .checklist(let checked):
                return indent + (checked ? "- [x] " : "- [ ] ") + body
            case .quote:
                return "> " + body.replacingOccurrences(of: "\n", with: "\n> ")
            case .code:
                let fence = String(repeating: "`", count: max(3, longestBacktickRun(in: body) + 1))
                return fence + "\n" + body + "\n" + fence
            case .divider:
                return "---"
            }
        }
    }

    /// 相邻的有序块连续编号；标题前留空行，空块本身也保留。
    private static func renderBlocks(_ document: NativeDocument,
                                     line: (DocumentBlock, Int) -> String) -> String {
        var lines: [String] = []
        var ordinal = 1
        var previousWasOrdered = false
        for block in document.blocks {
            if case .heading = block.kind, !lines.isEmpty, lines.last?.isEmpty == false {
                lines.append("")
            }
            if case .ordered = block.kind {
                if !previousWasOrdered { ordinal = block.listStart ?? 1 }
                lines.append(line(block, ordinal))
                ordinal += 1
                previousWasOrdered = true
            } else {
                ordinal = 1
                previousWasOrdered = false
                lines.append(line(block, 1))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func listIndent(_ block: DocumentBlock) -> String {
        String(repeating: "  ", count: max(0, block.indentLevel))
    }

    private static func plainRuns(_ runs: [DocumentRun]) -> String {
        runs.map { run in
            if !run.text.isEmpty { return run.text }
            if let file = run.attachment { return "📎 " + file.name }
            if let diagram = run.diagram { return "流程图：" + diagram.title }
            return ""
        }.joined()
    }

    private static func markdownRun(_ run: DocumentRun) -> String {
        if let file = run.attachment {
            return "[" + escape(file.name, linkLabel: true) + "](<" + linkDestination(file.storedName) + ">)"
        }
        if let diagram = run.diagram {
            return "[流程图：" + escape(diagram.title, linkLabel: true) + "]"
        }
        guard !run.text.isEmpty else { return "" }
        var text: String
        if run.marks.contains(.code) {
            let fence = String(repeating: "`", count: max(1, longestBacktickRun(in: run.text) + 1))
            text = fence + run.text + fence
        } else {
            text = escape(run.text, linkLabel: false)
        }
        if run.marks.contains(.bold) { text = "**" + text + "**" }
        if run.marks.contains(.italic) { text = "*" + text + "*" }
        if run.marks.contains(.underline) { text = "~" + text + "~" }
        if run.marks.contains(.strikethrough) { text = "~~" + text + "~~" }
        if run.marks.contains(.highlight) { text = "::" + text + "::" }
        if let link = run.marks.compactMap({ mark -> String? in
            if case .link(let value) = mark { return value }
            return nil
        }).sorted().first {
            // Link labels may safely contain ordinary brackets, but nested
            // brackets would change the link target; escape only the label.
            let label = text.replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
            text = "[" + label + "](<" + linkDestination(link) + ">)"
        }
        return text
    }

    private static func escape(_ text: String, linkLabel: Bool) -> String {
        var special = Set("\\`*_<>#~|")
        if linkLabel { special.formUnion(["[", "]"]) }
        return text.map { special.contains($0) ? "\\" + String($0) : String($0) }.joined()
    }

    private static func linkDestination(_ value: String) -> String {
        value.replacingOccurrences(of: "<", with: "%3C")
            .replacingOccurrences(of: ">", with: "%3E")
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

    // MARK: - Image / PDF

    /// 长图超过这个像素高度时不再渲染，避免生成几十 MB 的 PNG。
    static let maximumImagePixelHeight = 16_000

    @MainActor
    static func imagePixelSize(for document: NativeDocument,
                               scale: CGFloat = 2) throws -> (width: Int, height: Int) {
        let canvas = try renderedCanvas(for: document)
        return pixelSize(for: canvas.bounds.size, scale: scale)
    }

    @MainActor
    static func imageData(_ document: NativeDocument, scale: CGFloat = 2,
                          maximumPixelHeight: Int = maximumImagePixelHeight) throws -> Data {
        let canvas = try renderedCanvas(for: document)
        let size = canvas.bounds.size
        let (pixelWidth, pixelHeight) = pixelSize(for: size, scale: scale)
        guard pixelHeight <= maximumPixelHeight else {
            throw SummaryExportError.imageTooLong
        }
        let pdf = canvas.dataWithPDF(inside: canvas.bounds)
        guard let provider = CGDataProvider(data: pdf as CFData),
              let pdfDocument = CGPDFDocument(provider),
              let page = pdfDocument.page(at: 1) else {
            throw SummaryExportError.renderFailed
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw SummaryExportError.renderFailed
        }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: CGFloat(pixelWidth) / size.width, y: CGFloat(pixelHeight) / size.height)
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw SummaryExportError.renderFailed }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw SummaryExportError.renderFailed
        }
        return data
    }

    private static func pixelSize(for size: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        (max(1, Int((size.width * scale).rounded())),
         max(1, Int((size.height * scale).rounded())))
    }

    @MainActor
    static func pdfData(_ document: NativeDocument) throws -> Data {
        let canvas = try renderedCanvas(for: document)
        let data = canvas.dataWithPDF(inside: canvas.bounds)
        guard !data.isEmpty else { throw SummaryExportError.renderFailed }
        return data
    }

    @MainActor
    static func attributedText(_ document: NativeDocument) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var ordinal = 1
        var previousWasOrdered = false
        for (index, block) in document.blocks.enumerated() {
            let number: Int
            if case .ordered = block.kind {
                if !previousWasOrdered { ordinal = block.listStart ?? 1 }
                number = ordinal
                ordinal += 1
                previousWasOrdered = true
            } else {
                ordinal = 1
                previousWasOrdered = false
                number = 1
            }
            append(block, ordinal: number, to: result)
            if index < document.blocks.count - 1 {
                let style = paragraphStyle(for: block)
                result.append(NSAttributedString(string: "\n",
                    attributes: attributes(for: block.kind, marks: [], style: style)))
            }
        }
        return result
    }

    @MainActor
    private static func renderedCanvas(for document: NativeDocument) throws -> NSView {
        let content = attributedText(document)
        guard content.length > 0,
              !content.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SummaryExportError.emptyDocument
        }
        let contentWidth: CGFloat = 620
        let inset: CGFloat = 40
        let measured = content.boundingRect(with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let height = max(24, ceil(measured.height) + 8)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: height))
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textStorage?.setAttributedString(content)
        textView.frame = NSRect(x: inset, y: inset, width: contentWidth, height: height)

        let canvas = SummaryExportCanvasView(frame: NSRect(x: 0, y: 0, width: contentWidth + inset * 2,
                                                           height: height + inset * 2))
        canvas.addSubview(textView)
        canvas.layoutSubtreeIfNeeded()
        return canvas
    }

    @MainActor
    private static func append(_ block: DocumentBlock, ordinal: Int, to result: NSMutableAttributedString) {
        let style = paragraphStyle(for: block)
        func add(_ text: String, marks: Set<DocumentMark> = []) {
            guard !text.isEmpty else { return }
            result.append(NSAttributedString(string: text,
                attributes: attributes(for: block.kind, marks: marks, style: style)))
        }
        switch block.kind {
        case .bullet: add("•\t")
        case .ordered: add("\(ordinal).\t")
        case .checklist(let checked): add(checked ? "☑\t" : "☐\t")
        case .quote: add("│ ")
        case .divider:
            add("──────────")
            return
        default: break
        }
        for run in block.runs {
            if !run.text.isEmpty {
                add(run.text, marks: run.marks)
            } else if let file = run.attachment {
                add("📎 " + file.name, marks: run.marks)
            } else if let diagram = run.diagram {
                add("流程图：" + diagram.title, marks: run.marks)
            }
        }
    }

    @MainActor
    private static func paragraphStyle(for block: DocumentBlock) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let indent = CGFloat(max(0, block.indentLevel)) * 18
        switch block.kind {
        case .heading(let level):
            style.lineSpacing = 2
            style.paragraphSpacingBefore = level <= 1 ? 0 : (level == 2 ? 18 : 12)
            style.paragraphSpacing = level == 1 ? 12 : 6
        case .bullet, .ordered, .checklist:
            style.lineSpacing = 4
            style.firstLineHeadIndent = indent
            style.headIndent = indent + 22
            style.tabStops = [NSTextTab(textAlignment: .left, location: indent + 22)]
            style.paragraphSpacing = 3
        case .quote:
            style.lineSpacing = 4
            style.firstLineHeadIndent = indent + 12
            style.headIndent = indent + 12
            style.paragraphSpacing = 6
        case .divider:
            style.paragraphSpacing = 10
        case .code:
            style.lineSpacing = 3
            style.paragraphSpacing = 6
        case .paragraph:
            style.lineSpacing = 4
            style.firstLineHeadIndent = indent
            style.headIndent = indent
            style.paragraphSpacing = 5
        }
        return style
    }

    @MainActor
    private static func attributes(for kind: DocumentBlockKind, marks: Set<DocumentMark>,
                                   style: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        var font = baseFont(for: kind)
        if marks.contains(.code) {
            font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        }
        if marks.contains(.bold) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if marks.contains(.italic) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        var color: NSColor = kind == .quote ? secondaryTextColor : textColor
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: style,
        ]
        let explicitlyUnderlined = marks.contains(.underline)
        if explicitlyUnderlined { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if marks.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if marks.contains(.highlight) { attrs[.backgroundColor] = NSColor.systemYellow.withAlphaComponent(0.35) }
        if marks.contains(.code) { attrs[.backgroundColor] = codeBackgroundColor }
        // Image/PDF recipients cannot open workfollow:// links; keep the
        // editor's blue task titles without AppKit's default link underline.
        if marks.contains(where: { mark in
            if case .link = mark { return true }
            return false
        }) {
            color = accentColor
        }
        attrs[.foregroundColor] = color
        return attrs
    }

    @MainActor
    private static func baseFont(for kind: DocumentBlockKind) -> NSFont {
        switch kind {
        case .heading(1): .systemFont(ofSize: 22, weight: .semibold)
        case .heading(2): .systemFont(ofSize: 16, weight: .semibold)
        case .heading: .systemFont(ofSize: 14.5, weight: .semibold)
        case .code: .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        default: .systemFont(ofSize: 14, weight: .regular)
        }
    }

    private static let textColor = NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
    private static let secondaryTextColor = NSColor(red: 0.42, green: 0.44, blue: 0.48, alpha: 1)
    private static let accentColor = NSColor(red: 0.388, green: 0.537, blue: 0.961, alpha: 1)
    private static let codeBackgroundColor = NSColor(red: 0.95, green: 0.955, blue: 0.965, alpha: 1)
}

private final class SummaryExportCanvasView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        super.draw(dirtyRect)
    }
}
