import Foundation

/// 滴答 Markdown 语法解析器（纯函数，无 UI 依赖）。
///
/// 规格来源：2026-10-16 对滴答清单 8.0.80 编辑栏的运行时探针（AX 写入 + 渲染采集 + 工具条点击回读），
/// 逐条断言见 `MarkdownSyntaxTests`。与标准 Markdown 的差异集中在：
/// - 下划线是 `~文字~`（单波浪线），删除线是 `~~文字~~`；
/// - 高亮是 `::文字::`；
/// - 块级标记（`#`/`*`/`-`/`1.`/`> `/` ``` `）后**必须**有空格，否则按普通文本；
/// - 未闭合的行内标记保持字面；
/// - 不支持：表格、HTML 标签、数学公式、`==`/`++`、嵌套引用（`> >` 的第二个 `>` 保留为字面）；
/// - 引用块内部的行内标记仍被移除符号，但样式不生效（由渲染层实现，解析层正常产出 marks）。
///
/// 块级标记的**输入期触发**（键入 `# `、`- [ ] ` 等即成块、标记串移除）实现见
/// `Features/Editor/DocumentMarkdownInput.swift`；本文件只负责解析，无 UI 依赖。
enum MarkdownSyntax {

    // MARK: - 模型

    enum BlockKind: Equatable {
        case paragraph
        /// 1...6（滴答实测 `#` 到 `######` 全部渲染，工具条 H 菜单只给 1-3）
        case heading(level: Int)
        case bullet
        case ordered
        case checklist(checked: Bool)
        case quote
        case codeBlock
        case divider
    }

    enum InlineMark: Hashable {
        case bold
        case italic
        case underline
        case highlight
        case strikethrough
        case code
        case link(url: String)
    }

    /// 行内片段。`markerRanges` 是渲染时需要隐藏的符号位置。
    struct Inline: Equatable {
        var text: String
        var marks: Set<InlineMark>
        /// 内容在源文本中的范围（不含标记）
        var contentRange: NSRange
        /// 该片段对应的完整源范围（含标记；渲染隐藏后视觉宽度应只剩内容）
        var sourceRange: NSRange
        /// 需要隐藏的标记符号范围
        var markerRanges: [NSRange]
    }

    struct Block: Equatable {
        var kind: BlockKind
        var inlines: [Inline]
        /// 整块源范围（含前缀标记，不含结尾换行）
        var sourceRange: NSRange
        /// 块前缀标记范围：`# `、`* `、`- [ ] `、`1. `、`> `、代码块围栏行；divider 为整行
        var markerRange: NSRange?
        /// 内容范围（不含前缀标记）
        var contentRange: NSRange
        /// 代码块：围栏内每一行的范围（滴答把围栏渲染为 `···`，内容保留）
        var codeLines: [NSRange] = []
    }

    struct Document: Equatable {
        var blocks: [Block]
        /// 归一化后的源码（\r\n → \n）
        var source: String
    }

    // MARK: - 解析入口

    static func parse(_ raw: String) -> Document {
        let source = normalize(raw)
        let ns = source as NSString
        var blocks: [Block] = []
        var scanner = LineScanner(ns: ns)

        while let line = scanner.peek() {
            if line.isBlank {
                _ = scanner.next()
                continue
            }

            // 代码块：``` 到闭合 ```（未闭合则到文末）
            if fenceMarker(line.text) != nil {
                _ = scanner.next()
                blocks.append(parseCodeBlock(fenceLine: line, scanner: &scanner, ns: ns))
                continue
            }

            if let block = parseLeafBlock(line, ns: ns) {
                _ = scanner.next()
                blocks.append(block)
                continue
            }

            // 普通段落：连续的非空、非块起始行合并
            blocks.append(parseParagraph(scanner: &scanner, ns: ns))
        }

        return Document(blocks: blocks, source: source)
    }

    // MARK: - 行工具

    private struct Line {
        var text: String
        var range: NSRange      // 不含换行符
        var fullRange: NSRange  // 含换行符
        var isBlank: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private struct LineScanner {
        let ns: NSString
        private var location = 0

        init(ns: NSString) { self.ns = ns }

        mutating func next() -> Line? {
            guard location < ns.length else { return nil }
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                            for: NSRange(location: location, length: 0))
            let textRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
            let fullRange = NSRange(location: lineStart, length: lineEnd - lineStart)
            location = lineEnd
            return Line(text: ns.substring(with: textRange), range: textRange, fullRange: fullRange)
        }

        /// 不消费地看下一行
        mutating func peek() -> Line? {
            let saved = location
            let line = next()
            location = saved
            return line
        }
    }

    private static func normalize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    // MARK: - 块级识别

    /// 代码围栏：行首最多 3 个空格 + 至少 3 个反引号
    private static func fenceMarker(_ line: String) -> NSRange? {
        let ns = line as NSString
        var index = 0
        while index < ns.length, index < 3, ns.character(at: index) == 0x20 { index += 1 }
        var ticks = 0
        while index + ticks < ns.length, ns.character(at: index + ticks) == 0x60 { ticks += 1 }
        guard ticks >= 3 else { return nil }
        return NSRange(location: index, length: ticks)
    }

    private static func parseLeafBlock(_ line: Line, ns: NSString) -> Block? {
        let text = line.text as NSString

        // 标题：# 后必须空格（marker 长度 = # 个数 + 1 个空格）
        if let marker = headingMarker(text) {
            let level = marker.length - 1
            let contentStart = line.range.location + marker.length
            let contentRange = NSRange(location: contentStart, length: line.range.length - marker.length)
            return Block(kind: .heading(level: min(level, 6)),
                         inlines: parseInlines(ns, in: contentRange),
                         sourceRange: line.range,
                         markerRange: NSRange(location: line.range.location, length: marker.length),
                         contentRange: contentRange)
        }

        // 任务项：`- [ ] ` / `- [x] `（工具条插入的就是 `- [ ] `）
        if let (markerLength, checked) = checklistMarker(text) {
            let contentStart = line.range.location + markerLength
            let contentRange = NSRange(location: contentStart, length: line.range.length - markerLength)
            return Block(kind: .checklist(checked: checked),
                         inlines: parseInlines(ns, in: contentRange),
                         sourceRange: line.range,
                         markerRange: NSRange(location: line.range.location, length: markerLength),
                         contentRange: contentRange)
        }

        // 无序列表：`* ` / `- ` / `+ `（工具条插入 `* `；探针确认 `- ` 同样解析）
        if let marker = prefixMarker(text, symbols: "*+-", count: 1) {
            let contentStart = line.range.location + marker.length
            let contentRange = NSRange(location: contentStart, length: line.range.length - marker.length)
            return Block(kind: .bullet,
                         inlines: parseInlines(ns, in: contentRange),
                         sourceRange: line.range,
                         markerRange: NSRange(location: line.range.location, length: marker.length),
                         contentRange: contentRange)
        }

        // 有序列表：`1. `
        if let marker = orderedMarker(text) {
            let contentStart = line.range.location + marker.length
            let contentRange = NSRange(location: contentStart, length: line.range.length - marker.length)
            return Block(kind: .ordered,
                         inlines: parseInlines(ns, in: contentRange),
                         sourceRange: line.range,
                         markerRange: NSRange(location: line.range.location, length: marker.length),
                         contentRange: contentRange)
        }

        // 引用：`> `（滴答不支持嵌套：`> > x` 渲染为引用 + 字面 `> x`）
        if let marker = prefixMarker(text, symbols: ">", count: 1) {
            let contentStart = line.range.location + marker.length
            let contentRange = NSRange(location: contentStart, length: line.range.length - marker.length)
            return Block(kind: .quote,
                         inlines: parseInlines(ns, in: contentRange),
                         sourceRange: line.range,
                         markerRange: NSRange(location: line.range.location, length: marker.length),
                         contentRange: contentRange)
        }

        // 分割线：独立行 3+ 个 `-` / `*` / `_`
        if isDivider(text) {
            return Block(kind: .divider, inlines: [],
                         sourceRange: line.range,
                         markerRange: line.range,
                         contentRange: NSRange(location: line.range.location, length: 0))
        }

        return nil
    }

    /// `#{1,6}` + 空格
    private static func headingMarker(_ text: NSString) -> NSRange? {
        var hashes = 0
        while hashes < text.length, text.character(at: hashes) == 0x23 { hashes += 1 }
        guard (1...6).contains(hashes) else { return nil }
        guard hashes < text.length, text.character(at: hashes) == 0x20 else { return nil }
        return NSRange(location: 0, length: hashes + 1)
    }

    private static func checklistMarker(_ text: NSString) -> (Int, Bool)? {
        guard text.length >= 5 else { return nil }
        let c0 = text.character(at: 0)
        guard c0 == 0x2D || c0 == 0x2A else { return nil }  // - 或 *
        guard text.character(at: 1) == 0x20 else { return nil }
        guard text.character(at: 2) == 0x5B else { return nil }  // [
        let state = text.character(at: 3)
        guard text.character(at: 4) == 0x5D else { return nil }  // ]
        guard text.length >= 6, text.character(at: 5) == 0x20 else { return nil }
        switch state {
        case 0x20: return (6, false)
        case 0x78, 0x58: return (6, true)  // x / X
        default: return nil
        }
    }

    private static func orderedMarker(_ text: NSString) -> NSRange? {
        var digits = 0
        while digits < text.length, (0x30...0x39).contains(text.character(at: digits)) { digits += 1 }
        guard digits >= 1, digits < text.length else { return nil }
        guard text.character(at: digits) == 0x2E else { return nil }  // .
        guard digits + 1 < text.length, text.character(at: digits + 1) == 0x20 else { return nil }
        return NSRange(location: 0, length: digits + 2)
    }

    private static func prefixMarker(_ text: NSString, symbols: String, count: Int) -> NSRange? {
        guard text.length >= count + 1 else { return nil }
        let set = Set(symbols.unicodeScalars.map { UInt16($0.value) })
        for index in 0..<count where !set.contains(text.character(at: index)) { return nil }
        guard text.character(at: count) == 0x20 else { return nil }
        return NSRange(location: 0, length: count + 1)
    }

    private static func isDivider(_ text: NSString) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces) as NSString
        guard trimmed.length >= 3 else { return false }
        let first = trimmed.character(at: 0)
        guard first == 0x2D || first == 0x2A || first == 0x5F else { return false }
        for index in 0..<trimmed.length where trimmed.character(at: index) != first { return false }
        return true
    }

    /// 独立行分割线（`---` / `***` / `___`，3+ 个相同符号，允许两侧空白）。
    /// 输入期触发用它判断"整行已敲完"。
    static func isDividerLine(_ text: String) -> Bool {
        isDivider(text as NSString)
    }

    /// 独立行围栏（整行仅由 3+ 个反引号构成，允许行首最多 3 个空格）。
    /// 输入期触发用它判断"整行已敲完"；带语言标记的行不属于此口径。
    static func isFenceLine(_ text: String) -> Bool {
        let ns = text as NSString
        var index = 0
        while index < ns.length, index < 3, ns.character(at: index) == 0x20 { index += 1 }
        var ticks = 0
        while index + ticks < ns.length, ns.character(at: index + ticks) == 0x60 { ticks += 1 }
        return ticks >= 3 && index + ticks == ns.length
    }

    // MARK: - 段落与代码块

    private static func parseParagraph(scanner: inout LineScanner, ns: NSString) -> Block {
        var lines: [Line] = []
        while let line = scanner.peek() {
            if line.isBlank { break }
            if fenceMarker(line.text) != nil { break }
            if parseLeafBlockStart(line) { break }
            guard let consumed = scanner.next() else { break }
            lines.append(consumed)
        }
        if lines.isEmpty, let forced = scanner.next() { lines = [forced] }

        let start = lines[0].range.location
        let end = lines[lines.count - 1].range.location + lines[lines.count - 1].range.length
        let range = NSRange(location: start, length: end - start)
        var inlines: [Inline] = []
        for (index, line) in lines.enumerated() {
            let part = parseInlines(ns, in: line.range)
            if index == 0 {
                inlines = part
            } else {
                for var item in part {
                    item.text = "\n" + item.text
                    inlines.append(item)
                }
            }
        }
        return Block(kind: .paragraph, inlines: inlines,
                     sourceRange: range, markerRange: nil, contentRange: range)
    }

    private static func parseLeafBlockStart(_ line: Line) -> Bool {
        let text = line.text as NSString
        return headingMarker(text) != nil
            || checklistMarker(text) != nil
            || prefixMarker(text, symbols: "*+-", count: 1) != nil
            || orderedMarker(text) != nil
            || prefixMarker(text, symbols: ">", count: 1) != nil
            || isDivider(text)
    }

    private static func parseCodeBlock(fenceLine: Line, scanner: inout LineScanner, ns: NSString) -> Block {
        var lines: [NSRange] = []
        var end = fenceLine.range.location + fenceLine.range.length
        while let line = scanner.next() {
            if fenceMarker(line.text) != nil {
                end = line.range.location + line.range.length
                break
            }
            lines.append(line.range)
            end = line.range.location + line.range.length
        }
        let start = fenceLine.range.location
        let range = NSRange(location: start, length: end - start)
        let contentStart = lines.first?.location ?? end
        let contentEnd = lines.last.map { $0.location + $0.length } ?? contentStart
        let inlines: [Inline] = lines.map {
            Inline(text: ns.substring(with: $0), marks: [.code],
                   contentRange: $0, sourceRange: $0, markerRanges: [])
        }
        return Block(kind: .codeBlock, inlines: inlines,
                     sourceRange: range,
                     markerRange: fenceLine.range,
                     contentRange: NSRange(location: contentStart, length: contentEnd - contentStart),
                     codeLines: lines)
    }

    // MARK: - 行内解析

    private struct Delimiter {
        var open: String
        var close: String
        var mark: InlineMark?
    }

    /// 顺序即优先级：先长后短（`~~` 在 `~` 前，`**` 在 `*` 前）
    private static let delimiters: [Delimiter] = [
        Delimiter(open: "::", close: "::", mark: .highlight),
        Delimiter(open: "~~", close: "~~", mark: .strikethrough),
        Delimiter(open: "**", close: "**", mark: .bold),
        Delimiter(open: "~", close: "~", mark: .underline),
        Delimiter(open: "*", close: "*", mark: .italic),
        Delimiter(open: "`", close: "`", mark: .code)
    ]

    static func parseInlines(_ ns: NSString, in range: NSRange) -> [Inline] {
        var result: [Inline] = []
        var index = range.location
        let end = range.location + range.length
        var plainStart = index
        // 上一个匹配片段的结束位置（闭标记末字符之后）。单字符标记的开标记若紧邻
        // 同字符，只有前一字符是**刚结束片段的闭标记**时才成立；否则那是双写标记
        // 的中间态（`~~删~` 里的 `~删~`、`**粗*` 里的 `*粗*`），必须保持字面——
        // 等第二个字符完成再匹配（2026-10-16 行内输入期口径的防抢跑守卫）。
        var lastMatchEnd = -1

        func flushPlain(upTo location: Int) {
            guard location > plainStart else { return }
            let r = NSRange(location: plainStart, length: location - plainStart)
            result.append(Inline(text: ns.substring(with: r), marks: [],
                                 contentRange: r, sourceRange: r, markerRanges: []))
        }

        while index < end {
            // 链接：[文字](url)
            if ns.character(at: index) == 0x5B,
               let link = matchLink(ns, at: index, limit: end) {
                flushPlain(upTo: index)
                var marks: Set<InlineMark> = []
                if let url = link.url { marks.insert(.link(url: url)) }
                result.append(Inline(text: link.text, marks: marks,
                                     contentRange: link.textRange,
                                     sourceRange: link.fullRange,
                                     markerRanges: link.markerRanges))
                index = link.fullRange.location + link.fullRange.length
                plainStart = index
                lastMatchEnd = index
                continue
            }

            var matched = false
            for delimiter in delimiters {
                if let match = matchDelimited(ns, delimiter: delimiter, at: index, limit: end,
                                              followsMatchEnd: lastMatchEnd == index) {
                    flushPlain(upTo: index)
                    let marks: Set<InlineMark> = delimiter.mark.map { [$0] } ?? []
                    result.append(Inline(text: match.content, marks: marks,
                                         contentRange: match.contentRange,
                                         sourceRange: match.fullRange,
                                         markerRanges: match.markerRanges))
                    index = match.fullRange.location + match.fullRange.length
                    plainStart = index
                    lastMatchEnd = index
                    matched = true
                    break
                }
            }
            if matched { continue }
            index += 1
        }
        flushPlain(upTo: end)
        return result
    }

    private struct InlineMatch {
        var content: String
        var contentRange: NSRange
        var fullRange: NSRange
        var markerRanges: [NSRange]
    }

    private static func matchDelimited(_ ns: NSString, delimiter: Delimiter, at index: Int, limit: Int,
                                       followsMatchEnd: Bool = false) -> InlineMatch? {
        let openLength = (delimiter.open as NSString).length
        let closeLength = (delimiter.close as NSString).length
        // 必须先确认开标记本身匹配（否则 `~` 会误吃 `~~` 的位置、`::` 会误吃 `*` 的位置）
        guard index + openLength <= limit else { return nil }
        guard ns.substring(with: NSRange(location: index, length: openLength)) == delimiter.open else { return nil }
        // 防抢跑：单字符标记（`*`/`~`）的开标记紧邻同字符、且前一字符不是刚结束的
        // 闭标记时，这是双写标记的中间态（`~~删~`、`**粗*`），不当成新的开标记。
        if openLength == 1, index > 0, !followsMatchEnd,
           ns.character(at: index - 1) == ns.character(at: index) {
            return nil
        }
        let contentStart = index + openLength
        guard contentStart < limit else { return nil }
        let searchRange = NSRange(location: contentStart, length: limit - contentStart)
        let closeRange = ns.range(of: delimiter.close, options: [], range: searchRange)
        // 未闭合：保持字面（滴答探针确认 `**未闭合` 原样显示）
        guard closeRange.location != NSNotFound, closeRange.location > contentStart else { return nil }
        let contentRange = NSRange(location: contentStart, length: closeRange.location - contentStart)
        let fullRange = NSRange(location: index, length: closeRange.location + closeLength - index)
        return InlineMatch(content: ns.substring(with: contentRange),
                           contentRange: contentRange,
                           fullRange: fullRange,
                           markerRanges: [NSRange(location: index, length: openLength),
                                          NSRange(location: closeRange.location, length: closeLength)])
    }

    private struct LinkMatch {
        var text: String
        var url: String?
        var textRange: NSRange
        var fullRange: NSRange
        var markerRanges: [NSRange]
    }

    private static func matchLink(_ ns: NSString, at index: Int, limit: Int) -> LinkMatch? {
        guard let closeBracket = find(ns, "]", from: index + 1, limit: limit) else { return nil }
        guard closeBracket + 1 < limit, ns.character(at: closeBracket + 1) == 0x28 else { return nil }  // (
        guard let closeParen = find(ns, ")", from: closeBracket + 2, limit: limit) else { return nil }
        let textRange = NSRange(location: index + 1, length: closeBracket - index - 1)
        let urlRange = NSRange(location: closeBracket + 2, length: closeParen - closeBracket - 2)
        let url = ns.substring(with: urlRange)
        return LinkMatch(text: ns.substring(with: textRange),
                         url: url.isEmpty ? nil : url,
                         textRange: textRange,
                         fullRange: NSRange(location: index, length: closeParen + 1 - index),
                         markerRanges: [NSRange(location: index, length: 1),
                                        NSRange(location: closeBracket, length: 1),
                                        NSRange(location: closeBracket + 1, length: closeParen + 1 - closeBracket - 1)])
    }

    private static func find(_ ns: NSString, _ needle: String, from: Int, limit: Int) -> Int? {
        guard from <= limit else { return nil }
        let range = ns.range(of: needle, options: [], range: NSRange(location: from, length: limit - from))
        return range.location == NSNotFound ? nil : range.location
    }
}
