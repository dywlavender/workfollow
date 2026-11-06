import AppKit
import SwiftUI

/// AI 回复正文。
///
/// 为什么不是「每块一个 `Text`」：`.textSelection(.enabled)` 在 AppKit 上
/// **一份文本视图一份选区**，逐块渲染会把一条回复切成 N 个互不相通的选区，
/// 鼠标从第一段往下拖到段落末尾就断。这里改成整条消息一个只读 `NSTextView`，
/// 选区跨段落/标题/列表/代码块连续。
///
/// 排版对齐主流 agent（ChatGPT / Claude）的消息口径：行距 ≈1.6、段落间距 8pt、
/// 标题前留白大于后留白、代码块有底色面板、列表悬挂缩进。段落 14pt、
/// 标题 20/17/15pt 半粗、代码 12pt 等宽；「一个块一段富文本」，`NSTextStorage` 统一持有。
struct AIMessageContent: View {
    let text: String

    var body: some View {
        AISelectableMessageText(text: text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("ai.message.body")
    }
}

/// 只读、可选、随内容自适应高度的富文本视图。
///
/// 高度交给 `sizeThatFits`：外层 `ScrollView` 负责滚动，这条消息本身不能
/// 再套一层滚动视图，否则鼠标拖选到视图边缘就会被内部滚动劫持。
private struct AISelectableMessageText: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        /// 上一次渲染用的源文本与宽度，避免每次布局都重排富文本。
        var renderedText: String?
        var renderedWidth: CGFloat = 0
        var renderedAppearance: NSAppearance.Name?
    }

    func makeNSView(context: Context) -> NativeReadonlyTextView {
        let view = NativeReadonlyTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.focusRingType = .none
        view.textContainerInset = .zero
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        // 只读正文不参与光标/拖放，但要把链接点得动。
        view.isAutomaticLinkDetectionEnabled = false
        view.linkTextAttributes = [
            .foregroundColor: WFColors.nsAccent,
            .underlineStyle: 0,
            .cursor: NSCursor.pointingHand
        ]
        return view
    }

    func updateNSView(_ view: NativeReadonlyTextView, context: Context) {
        let appearanceName = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        let width = view.bounds.width
        guard context.coordinator.renderedText != text
                || context.coordinator.renderedAppearance != appearanceName else { return }
        context.coordinator.renderedText = text
        context.coordinator.renderedAppearance = appearanceName

        let rendered = AIMessageRichText.render(text)
        view.textStorage?.setAttributedString(rendered)
        // 换文档后旧选区失效，必须清掉，否则可能提示「选区越界」。
        view.setSelectedRange(NSRange(location: 0, length: 0))
        context.coordinator.renderedWidth = 0
        view.invalidateIntrinsicContentSize()
        _ = width
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NativeReadonlyTextView,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        guard let container = nsView.textContainer, let layout = nsView.textLayoutManager else { return nil }
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: NSRect(origin: .zero, size: container.containerSize))
        let height = layout.usageBoundsForTextContainer.height
        // 只用「宽度 + 高度」回报，宽度仍由外层 frame 决定。
        return CGSize(width: width, height: ceil(height))
    }

    static func dismantleNSView(_ view: NativeReadonlyTextView, coordinator: Coordinator) {
        view.textStorage?.setAttributedString(NSAttributedString(string: ""))
    }
}

/// 一个「不可编辑但可选中」的 `NSTextView`。
/// 不复用 `NativeTextView`：后者带着整套编辑器状态（工具条、斜杠面板、
/// 标签补全、撤销栈），只读正文用不上，也会让它多背一份文档生命周期。
private final class NativeReadonlyTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }
    // 只读但仍接受鼠标拖选。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Markdown → 富文本

/// 把 AI 回复的 Markdown 渲染成一段 `NSAttributedString`。
///
/// 分块口径与改造前的 `AIMessageContent.blocks` 一致：
/// 围栏代码块、`#` 标题、表格、列表、空行分段。
enum AIMessageRichText {
    private enum Block {
        case paragraph(String)
        case heading(String, Int)
        case code(String)
        case list([Item])
        case table([[String]])
        case divider

        struct Item {
            let level: Int
            let marker: String
            var content: String
        }
    }

    private static var bodyFont: NSFont { .systemFont(ofSize: 14) }
    private static var codeFont: NSFont { .monospacedSystemFont(ofSize: 12, weight: .regular) }

    private static func headingFont(level: Int) -> NSFont {
        // h3 与正文拉开一档字号，只靠粗细区分会和 14pt 正文糊在一起。
        .systemFont(ofSize: level == 1 ? 20 : level == 2 ? 17 : 15, weight: .semibold)
    }

    static func render(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let blocks = parse(text)
        for (index, block) in blocks.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(render(block, startsMessage: index == 0))
        }
        return result
    }

    private static func render(_ block: Block, startsMessage: Bool) -> NSAttributedString {
        switch block {
        case let .paragraph(value):
            return spaced(inline(value, font: bodyFont), lineSpacing: 6, before: 0, inner: 0, after: 8)
        case let .heading(value, level):
            let before: CGFloat = level == 1 ? 14 : level == 2 ? 12 : 10
            return spaced(inline(value, font: headingFont(level: level)), lineSpacing: 2,
                          before: startsMessage ? 0 : before, inner: 0, after: 8)
        case let .code(value):
            let content = NSMutableAttributedString()
            let lines = value.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                content.append(NSAttributedString(string: line, attributes: [
                    .font: codeFont,
                    .foregroundColor: WFColors.nsDocumentText,
                    .backgroundColor: WFColors.nsCodeFill
                ]))
                if index < lines.count - 1 { content.append(NSAttributedString(string: "\n")) }
            }
            return spaced(content, lineSpacing: 2, before: startsMessage ? 0 : 2,
                          inner: 0, after: 10, headIndent: 6)
        case let .list(items):
            return listContent(items, startsMessage: startsMessage)
        case let .table(rows):
            // 表格在单个文本视图里没有真列宽，用制表符分隔保证可读且可整段选中；
            // 首行当表头：半粗 + 底色，扫一眼分得开。
            let content = NSMutableAttributedString()
            for (index, row) in rows.enumerated() {
                let header = index == 0
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: header ? weight(bodyFont, .semibold) : bodyFont,
                    .foregroundColor: WFColors.nsDocumentText
                ]
                if header { attributes[.backgroundColor] = WFColors.nsCodeFill }
                content.append(NSAttributedString(
                    string: row.joined(separator: "    "), attributes: attributes))
                if index < rows.count - 1 { content.append(NSAttributedString(string: "\n")) }
            }
            return spaced(content, lineSpacing: 4, before: startsMessage ? 0 : 2,
                          inner: 0, after: 10)
        case .divider:
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineSpacing = 2
            paragraph.paragraphSpacingBefore = startsMessage ? 0 : 4
            paragraph.paragraphSpacing = 8
            return NSAttributedString(string: "———", attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ])
        }
    }

    /// 列表项逐条渲染：悬挂缩进（marker 在外、正文对齐到 tab 位），嵌套按层缩进。
    private static func listContent(_ items: [Block.Item], startsMessage: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            let base = CGFloat(min(item.level, 3)) * 14
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 5
            style.firstLineHeadIndent = base
            style.headIndent = base + 14
            style.tabStops = [NSTextTab(textAlignment: .left, location: base + 14)]
            style.paragraphSpacingBefore = index == 0 && startsMessage ? 0 : 2
            style.paragraphSpacing = index == items.count - 1 ? 8 : 2
            let start = result.length
            result.append(NSAttributedString(string: item.marker + "\t", attributes: [
                .font: bodyFont,
                .foregroundColor: WFColors.nsDocumentText
            ]))
            result.append(inline(item.content, font: bodyFont))
            // 段落样式必须铺满整段（含续行），只挂在 marker 上排版不可靠。
            result.addAttribute(.paragraphStyle, value: style,
                                range: NSRange(location: start, length: result.length - start))
        }
        return result
    }

    /// 给整块内容逐段落挂段落属性：块间距全走 `paragraphStyle`，块与块之间
    /// 不再只靠一个裸 `\n` 挤在一起。注意 AppKit 里相邻两段的间距是
    /// 上一段 `paragraphSpacing` + 下一段 `paragraphSpacingBefore` 相加。
    ///
    /// - `before` 块首段上方留白（首块由调用方压成 0，消息顶部不留空）
    /// - `inner` 块内段落之间的留白（代码块/表格行要贴紧，取 0）
    /// - `after` 末段下方留白
    private static func spaced(_ content: NSAttributedString, lineSpacing: CGFloat,
                               before: CGFloat, inner: CGFloat, after: CGFloat,
                               headIndent: CGFloat = 0) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: content)
        let ns = result.string as NSString
        guard ns.length > 0 else { return result }
        var paragraphRanges: [NSRange] = []
        var start = 0
        for index in 0..<ns.length where ns.character(at: index) == unichar(0x0A) {
            paragraphRanges.append(NSRange(location: start, length: index - start))
            start = index + 1
        }
        paragraphRanges.append(NSRange(location: start, length: ns.length - start))
        for (index, range) in paragraphRanges.enumerated() where range.length > 0 {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = lineSpacing
            style.paragraphSpacingBefore = index == 0 ? before : inner
            style.paragraphSpacing = index == paragraphRanges.count - 1 ? after : inner
            if headIndent > 0 {
                style.firstLineHeadIndent = headIndent
                style.headIndent = headIndent
            }
            result.addAttribute(.paragraphStyle, value: style, range: range)
        }
        return result
    }

    /// 行内 Markdown → 字体/删除线/链接。
    ///
    /// `AttributedString(markdown:)` 只产出 `inlinePresentationIntent` 标记，
    /// AppKit 不会据此自动换字体，所以这里把掩码解释成真实属性。
    private static func inline(_ source: String, font: NSFont) -> NSAttributedString {
        guard let parsed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return plain(source, font: font)
        }
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let piece = String(parsed[run.range].characters)
            guard !piece.isEmpty else { continue }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: WFColors.nsDocumentText
            ]
            var resolved = font
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { resolved = weight(font, .semibold) }
                if intent.contains(.emphasized) { resolved = italicize(resolved) }
                if intent.contains(.code) { resolved = .monospacedSystemFont(ofSize: font.pointSize - 2, weight: .regular) }
                if intent.contains(.strikethrough) {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
            }
            attributes[.font] = resolved
            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = WFColors.nsAccent
            }
            result.append(NSAttributedString(string: piece, attributes: attributes))
        }
        if result.length == 0 { return plain(source, font: font) }
        return result
    }

    private static func plain(_ source: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: source, attributes: [
            .font: font,
            .foregroundColor: WFColors.nsDocumentText
        ])
    }

    private static func weight(_ font: NSFont, _ weight: NSFont.Weight) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: weight == .semibold ? .boldFontMask : [])
    }

    private static func italicize(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    // MARK: 分块

    private static func parse(_ text: String) -> [Block] {
        let lines = text.components(separatedBy: "\n")
        var result: [Block] = [], paragraph: [String] = [], index = 0
        func flush() {
            if !paragraph.isEmpty {
                result.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }
        func cells(_ line: String) -> [String] {
            line.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        while index < lines.count {
            let line = lines[index], trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flush(); index += 1
                var code: [String] = []
                while index < lines.count
                        && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index]); index += 1
                }
                result.append(.code(code.joined(separator: "\n")))
            } else if trimmed.hasPrefix("#"), let space = trimmed.firstIndex(of: " "),
                      trimmed[..<space].allSatisfy({ $0 == "#" }) {
                flush()
                result.append(.heading(String(trimmed[trimmed.index(after: space)...]),
                                       trimmed.distance(from: trimmed.startIndex, to: space)))
            } else if line.contains("|"), index + 1 < lines.count,
                      lines[index + 1].contains("-"),
                      lines[index + 1].allSatisfy({ "|:- \t".contains($0) }) {
                flush(); var rows = [cells(line)]; index += 2
                while index < lines.count && lines[index].contains("|") {
                    rows.append(cells(lines[index])); index += 1
                }
                result.append(.table(rows)); continue
            } else if trimmed.isEmpty { flush() }
            else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flush(); result.append(.divider)
            } else if let (marker, content) = listItemMarker(trimmed) {
                flush()
                let level = min(leadingSpaces(line) / 2, 3)
                var items = [Block.Item(level: level, marker: marker, content: content)]
                index += 1
                while index < lines.count {
                    let next = lines[index]
                    let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                    if let (marker, content) = listItemMarker(nextTrimmed) {
                        let nextLevel = min(leadingSpaces(next) / 2, 3)
                        items.append(Block.Item(level: nextLevel, marker: marker, content: content))
                        index += 1
                    } else if !nextTrimmed.isEmpty, next.hasPrefix(" "),
                              !nextTrimmed.hasPrefix("```"), !nextTrimmed.hasPrefix("#") {
                        // 缩进续行归属上一个列表项；悬挂缩进下续行自动对齐正文。
                        items[items.count - 1].content += "\n" + nextTrimmed
                        index += 1
                    } else { break }
                }
                result.append(.list(items))
                continue
            } else {
                paragraph.append(line)
            }
            index += 1
        }
        flush()
        return result
    }

    /// 识别列表行：`- `/`* ` 无序，`1. `/`1）式数字编号有序（保留原编号）。
    private static func listItemMarker(_ trimmed: String) -> (marker: String, content: String)? {
        if trimmed.hasPrefix("- ") { return ("•", String(trimmed.dropFirst(2))) }
        if trimmed.hasPrefix("* ") { return ("•", String(trimmed.dropFirst(2))) }
        let chars = Array(trimmed)
        var digits = 0
        while digits < chars.count, chars[digits].isNumber { digits += 1 }
        guard digits > 0, digits + 1 < chars.count,
              chars[digits] == "." || chars[digits] == ")",
              chars[digits + 1] == " " else { return nil }
        return (String(chars[...digits]), String(chars[(digits + 2)...]))
    }

    private static func leadingSpaces(_ line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }
}
