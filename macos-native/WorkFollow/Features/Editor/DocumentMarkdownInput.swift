import AppKit

/// 滴答 Markdown 的**输入期触发**（2026-10-16 产品口径修订，对齐滴答 8.0.80；
/// 行内与围栏为同日用户逐条确认的补充口径）。
///
/// 规格与 `MarkdownSyntax` 同出一处（编辑栏运行时探针 + `MarkdownSyntaxTests` 固化）。
/// 四类触发：
/// - **空格结尾的块级前缀**（完成标记的空格落下、光标紧跟标记之后）：
///   `# `～`###### `、`* `/`- `/`+ `、`1. `、`- [ ] `/`- [x] `、`> `；
/// - **整行敲完的分割线**：整行恰好 3+ 个相同符号（`---` / `***` / `___`）时
///   行文本换成分割线附件，光标跳到下一行（文末补一个空段落）；
/// - **整行敲完的围栏代码块**：整行恰为 3+ 个反引号（行首最多 3 个空格）时
///   行文本移除、段落转为代码；空代码行回车退回正文，有内容行回车延续；
/// - **闭合即转的行内标记**：`**粗**`、`*斜*`、`~~删除线~~`、`~下划线~`、
///   `::高亮::`、`` `码` ``、`[文字](url)` 在闭合标记的最后字符落下时转换。
/// 码内文本不转换（代码段落里的反引号保持字面）。
///
/// 触发后：标记串从正文里**移除**（对齐滴答的"符号隐藏"——标记由装饰层重画），
/// 段落类型/行内标记按**设值**语义应用。执行路径与斜杠面板一致
/// （先删触发串、再 `applyFormat(lineStart:)` / `applyFormat(inlineRange:)`，
/// 两步进同一撤销分组），所以输入属性、文末待定级别、"接着输入的字落在新块里"
/// （行内则继承标记）都沿用既有机制。
extension NativeTextView {
    /// 一次输入落下后的 Markdown 检查入口（由 `insertText` 调用）。
    /// 四类：空格结尾的块级前缀、整行敲完的分割线、整行敲完的围栏代码块、
    /// 闭合的行内标记。
    func applyTypedMarkdownInput(_ inserted: String) {
        if inserted.hasSuffix(" ") {
            applyTypedMarkdownBlockPrefix()
        }
        if let last = inserted.last, "-*_".contains(last) {
            applyTypedMarkdownDivider()
        }
        if inserted.hasSuffix("`") {
            applyTypedMarkdownFence()
        }
        if let last = inserted.last, "*~`):".contains(last) {
            applyTypedMarkdownInline()
        }
    }

    /// 整行恰好是 3+ 个相同符号（`---` / `***` / `___`）时立即成线：
    /// 行文本换成分割线附件，光标跳到下一行（文末则补一个空段落），
    /// 与 `insertDocumentDivider` 落出的结构一致。
    @discardableResult
    func applyTypedMarkdownDivider() -> Bool {
        guard !isApplyingTypedMarkdownInput else { return false }
        guard let storage = textStorage else { return false }
        let source = storage.string as NSString
        let selection = selectedRange()
        guard selection.length == 0, selection.location > 0 else { return false }
        let paragraph = source.paragraphRange(for: NSRange(location: selection.location - 1, length: 0))
        let lastCharacter = paragraph.length > 0 ? source.character(at: NSMaxRange(paragraph) - 1) : 0
        let contentLength = paragraph.length - (lastCharacter == 0x0A ? 1 : 0)
        let lineRange = NSRange(location: paragraph.location, length: contentLength)
        guard lineRange.length >= 3,
              selection.location == NSMaxRange(lineRange) else { return false }
        let line = source.substring(with: lineRange)
        // 滴答是整行判定：`abc---`、`---abc` 都不是分割线。
        guard MarkdownSyntax.isDividerLine(line) else { return false }
        // 代码段落里的符号保持字面；已是分割线的行不再转换。
        let token = storage.attribute(DocumentTextCodec.blockKey, at: lineRange.location,
                                      effectiveRange: nil) as? String ?? "paragraph"
        let current = DocumentTextCodec.kind(token)
        guard current != .code, current != .divider else { return false }

        isApplyingTypedMarkdownInput = true
        defer { isApplyingTypedMarkdownInput = false }
        convertTypedMarkdownDivider(lineRange: lineRange, hasFollowingLine: lastCharacter == 0x0A)
        return true
    }

    /// 整行恰好是 3+ 个反引号（允许行首最多 3 个空格）时立即成代码块：
    /// 行文本移除、段落转为代码（`.code`），光标留该段；后续行回车延续格式、
    /// 空代码行回车退回正文（2026-10-16 第二轮口径，用户确认；退出语义在
    /// `exitEmptyBlockOnNewline`）。带语言标记的整串写入与代码段内反引号保持
    /// 字面；行内 `` `码` `` 由行内触发处理（本函数只认整行）。
    @discardableResult
    func applyTypedMarkdownFence() -> Bool {
        guard !isApplyingTypedMarkdownInput else { return false }
        guard let storage = textStorage else { return false }
        let selection = selectedRange()
        guard selection.length == 0, selection.location > 0 else { return false }
        let source = storage.string as NSString
        let paragraph = source.paragraphRange(for: NSRange(location: selection.location - 1, length: 0))
        let lastCharacter = paragraph.length > 0 ? source.character(at: NSMaxRange(paragraph) - 1) : 0
        let contentLength = paragraph.length - (lastCharacter == 0x0A ? 1 : 0)
        let lineRange = NSRange(location: paragraph.location, length: contentLength)
        guard lineRange.length >= 3,
              selection.location == NSMaxRange(lineRange) else { return false }
        let line = source.substring(with: lineRange)
        // 整行判定：行内位置不得出现（`甲``` 不是围栏）。
        guard MarkdownSyntax.isFenceLine(line) else { return false }
        // 代码段落里的反引号是代码内容，保持字面；已是分割线的行不再转换。
        let token = storage.attribute(DocumentTextCodec.blockKey, at: lineRange.location,
                                      effectiveRange: nil) as? String ?? "paragraph"
        let current = DocumentTextCodec.kind(token)
        guard current != .code, current != .divider else { return false }

        isApplyingTypedMarkdownInput = true
        defer { isApplyingTypedMarkdownInput = false }
        convertTypedMarkdownPrefix(paragraphStart: lineRange.location, markerRange: lineRange, to: .code)
        return true
    }

    /// 光标前正好是完整的块级标记：移除标记、转换段落，返回是否触发。
    @discardableResult
    func applyTypedMarkdownBlockPrefix() -> Bool {
        guard !isApplyingTypedMarkdownInput else { return false }
        guard let storage = textStorage else { return false }
        let source = storage.string as NSString
        let selection = selectedRange()
        guard selection.length == 0, selection.location > 0 else { return false }
        // location == length（刚在文末空段里打字）也要定位到光标所在行：
        // 用光标**前一个字符**取段落，不依赖 NSString 对文末零长区间的口径。
        let paragraph = source.paragraphRange(for: NSRange(location: selection.location - 1, length: 0))
        let headRange = NSRange(location: paragraph.location,
                                length: selection.location - paragraph.location)
        guard headRange.length >= 2 else { return false }  // 最短的标记是 "# " / "- "
        let head = source.substring(with: headRange)
        // 代码段落的行内文本保持字面：码里不做格式转换。
        let token = storage.attribute(DocumentTextCodec.blockKey, at: paragraph.location,
                                      effectiveRange: nil) as? String ?? "paragraph"
        let current = DocumentTextCodec.kind(token)
        guard current != .code, current != .divider else { return false }
        guard let kind = inputTriggerBlockKind(head: head, current: current) else { return false }

        isApplyingTypedMarkdownInput = true
        defer { isApplyingTypedMarkdownInput = false }
        convertTypedMarkdownPrefix(paragraphStart: paragraph.location, markerRange: headRange, to: kind)
        return true
    }

    /// 光标前的这一串是不是"完整标记"。标记必须从段落起点开始、正好在光标处结束
    /// （多一个字符都不算：`## ` 在 `# ` 完成点才触发，之后的输入不该再触发一次）。
    private func inputTriggerBlockKind(head: String, current: DocumentBlockKind) -> DocumentBlockKind? {
        // 无序行里接着敲 `[ ] ` / `[x] `：升级为检查项。逐字符打字时 `- ` 先触发成
        // 无序列表（滴答的 `- ` 就是无序标记），方括号框才是检查项的完整签名。
        if current == .bullet, let checked = checklistUpgradeState(head) {
            return .checklist(checked)
        }
        let parsed = MarkdownSyntax.parse(head)
        guard parsed.blocks.count == 1, let block = parsed.blocks.first,
              let marker = block.markerRange, marker.length == (head as NSString).length else { return nil }
        return inputTriggerBlockKind(for: block.kind)
    }

    /// `[ ] ` / `[x] ` / `[X] `（4 个字符）→ 勾选状态。
    private func checklistUpgradeState(_ head: String) -> Bool? {
        let text = head as NSString
        guard text.length == 4,
              text.character(at: 0) == 0x5B, text.character(at: 2) == 0x5D,
              text.character(at: 3) == 0x20 else { return nil }
        switch text.character(at: 1) {
        case 0x20: return false
        case 0x78, 0x58: return true
        default: return nil
        }
    }

    /// 输入期可触发的块类型。分割线与围栏代码块不在内（附件/多行式渲染，另行处理）。
    private func inputTriggerBlockKind(for kind: MarkdownSyntax.BlockKind) -> DocumentBlockKind? {
        switch kind {
        case .heading(let level): .heading(level)
        case .bullet: .bullet
        case .ordered: .ordered
        case .checklist(let checked): .checklist(checked)
        case .quote: .quote
        case .paragraph, .codeBlock, .divider: nil
        }
    }

    /// 整行换成分割线附件：行尾还有下一行时只替换行内容、光标跳到下一行行首；
    /// 文末则补一个空段落供继续输入（与 `insertDocumentDivider` 落出的结构一致）。
    private func convertTypedMarkdownDivider(lineRange: NSRange, hasFollowingLine: Bool) {
        let insertion: NSAttributedString
        if hasFollowingLine {
            insertion = DocumentTextCodec.render(NativeDocument(blocks: [
                DocumentBlock(kind: .divider, runs: [DocumentRun(text: "\u{FFFC}")])
            ]))
        } else {
            insertion = DocumentTextCodec.render(NativeDocument(blocks: [
                DocumentBlock(kind: .divider, runs: [DocumentRun(text: "\u{FFFC}")]),
                DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "")])
            ]))
        }
        let caret = lineRange.location + insertion.length + (hasFollowingLine ? 1 : 0)
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        insertText(insertion, replacementRange: lineRange)
        setSelectedRange(NSRange(location: min(caret, (string as NSString).length), length: 0))
        typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
        undoManager?.endUndoGrouping()
        breakUndoCoalescing()
        resizeDocumentDividers()
    }

    /// 与斜杠面板同一条执行路径：先删触发串，再按"设值"语义应用段落类型；
    /// 两步进同一撤销分组，一次撤销回到标记敲下之前。
    private func convertTypedMarkdownPrefix(paragraphStart: Int, markerRange: NSRange,
                                            to kind: DocumentBlockKind) {
        // 只借 `block` 走 applyFormat 的设值分支；H4–H6 没有对应的工具条命令，
        // 所以这里构造一个描述符而不是去目录里找。
        let command = DocumentFormatCommand(id: "format.markdown", title: "Markdown",
                                            block: kind, mark: nil)
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        insertText("", replacementRange: markerRange)
        applyFormat(command, lineStart: paragraphStart)
        undoManager?.endUndoGrouping()
        breakUndoCoalescing()
    }

    /// 行内标记的输入期转换（2026-10-16 口径，用户逐条确认）：闭合标记的最后
    /// 一个字符落下时，开闭符号从正文移除、内容按**设值**语义应用标记。
    ///
    /// 只认"本次输入刚好补全、以光标结尾、同一行内"的最近一处闭合——双写标记
    /// 中间态的防抢跑守卫在 `MarkdownSyntax.parseInlines`；空 URL 的 `[文字]()`、
    /// 空内容（`[](b)`）、未闭合都不产生候选，保持字面（用户确认的口径）。
    @discardableResult
    func applyTypedMarkdownInline() -> Bool {
        guard !isApplyingTypedMarkdownInput else { return false }
        guard let storage = textStorage else { return false }
        let selection = selectedRange()
        let cursor = selection.location
        guard selection.length == 0, cursor > 0 else { return false }
        let source = storage.string as NSString
        // 标记不跨行：候选片段只可能在光标所在行内闭合。
        let lineBreak = source.range(of: "\n", options: .backwards,
                                     range: NSRange(location: 0, length: cursor))
        let lineStart = lineBreak.location == NSNotFound ? 0 : NSMaxRange(lineBreak)
        guard cursor > lineStart else { return false }
        // 代码段落的行内文本保持字面（与块级同款 guard）；引用照常触发。
        let token = storage.attribute(DocumentTextCodec.blockKey, at: lineStart,
                                      effectiveRange: nil) as? String ?? "paragraph"
        let current = DocumentTextCodec.kind(token)
        guard current != .code, current != .divider else { return false }
        let inlines = MarkdownSyntax.parseInlines(
            source, in: NSRange(location: lineStart, length: cursor - lineStart))
        // 最近一处以光标结尾、内容非空的闭合片段；未闭合/空 URL/空内容都不在内。
        guard let inline = inlines.last(where: {
            NSMaxRange($0.sourceRange) == cursor && !$0.marks.isEmpty && $0.contentRange.length > 0
        }), inline.marks.count == 1, let inlineMark = inline.marks.first else { return false }
        let mark = documentMark(of: inlineMark)

        isApplyingTypedMarkdownInput = true
        defer { isApplyingTypedMarkdownInput = false }
        convertTypedMarkdownInline(inline, mark: mark)
        return true
    }

    /// 与块级同一条执行路径：先删标记串，再走 `applyFormat` 的**设值**分支
    /// （`inlineRange`），两步进同一撤销分组，一次撤销回到标记敲下之前。
    private func convertTypedMarkdownInline(_ inline: MarkdownSyntax.Inline, mark: DocumentMark) {
        // 行内片段没有段落命令，只借 `mark` 走 applyFormat 的设值路径。
        let command = DocumentFormatCommand(id: "format.markdown.inline", title: "Markdown",
                                            block: nil, mark: mark)
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        for marker in inline.markerRanges.reversed() {
            insertText("", replacementRange: marker)
        }
        let contentRange = NSRange(location: inline.sourceRange.location,
                                   length: inline.contentRange.length)
        applyFormat(command, inlineRange: contentRange)
        undoManager?.endUndoGrouping()
        breakUndoCoalescing()
    }

    /// 解析器的行内标记 → 文档模型标记。
    private func documentMark(of mark: MarkdownSyntax.InlineMark) -> DocumentMark {
        switch mark {
        case .bold: return .bold
        case .italic: return .italic
        case .underline: return .underline
        case .highlight: return .highlight
        case .strikethrough: return .strikethrough
        case .code: return .code
        case .link(let url): return .link(url)
        }
    }

    // MARK: - 渲染期重解析（2026-10-17 口径修订）

    /// 渲染期重解析：把段落里**所有已闭合**的行内标记转成富文本——覆盖历史字面
    /// （文档加载、粘贴中段、编辑后揭示），不只"本次输入刚好补全"的那一处
    /// （对齐滴答的渲染期解析）。
    ///
    /// 加性（只加不减：工具条已有的 marks、未闭合字面都保留）、幂等；代码段与
    /// 分割线不动；段内从右到左处理，删除不会串扰左侧片段与光标。
    /// - Parameters:
    ///   - paragraphs: nil = 整篇；否则只处理这些范围所在的段落。
    ///   - registeringUndo: 加载期传 false（规范化不算用户编辑）。
    @discardableResult
    func reparseInlineMarkdown(paragraphs: [NSRange]? = nil,
                               registeringUndo: Bool = true) -> Bool {
        guard !isApplyingTypedMarkdownInput, !hasMarkedText(),
              let storage = textStorage else { return false }
        let source = storage.string as NSString
        guard source.length > 0 else { return false }

        var anchors: [Int] = []
        if let paragraphs {
            for range in paragraphs {
                let clamped = min(max(0, range.location), source.length - 1)
                anchors.append(source.paragraphRange(for: NSRange(location: clamped, length: 0)).location)
            }
        } else {
            var location = 0
            while location < source.length {
                let paragraph = source.paragraphRange(for: NSRange(location: location, length: 0))
                anchors.append(paragraph.location)
                location = NSMaxRange(paragraph)
            }
        }
        anchors = Array(Set(anchors)).sorted(by: >)

        // 先只读扫描：没有可转换片段就直接返回，不触碰撤销栈与选择。
        var candidates: [(span: MarkdownSyntax.Inline, expected: String, mark: DocumentMark)] = []
        for anchor in anchors {
            guard let rawCurrent = textStorage?.string else { continue }
            let current = rawCurrent as NSString
            guard current.length > 0, anchor < current.length else { continue }
            let paragraph = current.paragraphRange(for: NSRange(location: anchor, length: 0))
            guard paragraph.length > 0 else { continue }
            let token = storage.attribute(DocumentTextCodec.blockKey, at: paragraph.location,
                                          effectiveRange: nil) as? String ?? "paragraph"
            let kind = DocumentTextCodec.kind(token)
            guard kind != .code, kind != .divider else { continue }
            let text = current.substring(with: paragraph)
            guard text.contains("*") || text.contains("~") || text.contains("`")
                    || text.contains("[") || text.contains("::") else { continue }
            let spans = MarkdownSyntax.parseInlines(current, in: paragraph)
                .filter { !$0.marks.isEmpty && $0.contentRange.length > 0 && $0.marks.count == 1 }
                .sorted { $0.sourceRange.location > $1.sourceRange.location }
            for span in spans {
                guard let inlineMark = span.marks.first else { continue }
                candidates.append((span,
                                   current.substring(with: span.sourceRange),
                                   documentMark(of: inlineMark)))
            }
        }
        guard !candidates.isEmpty else { return false }

        let originalSelection = selectedRange()
        let originalTyping = typingAttributes
        var start = originalSelection.location
        var end = NSMaxRange(originalSelection)
        var changed = false

        isApplyingTypedMarkdownInput = true
        defer { isApplyingTypedMarkdownInput = false }
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        let undoWasDisabled = !registeringUndo
        if undoWasDisabled { undoManager?.disableUndoRegistration() }

        for candidate in candidates {
            guard let rawLatest = textStorage?.string else { continue }
            let latest = rawLatest as NSString
            // 右侧段落/片段的转换只删除其右侧字符，左侧候选的绝对范围仍然有效；
            // 仍核对一次字面，避免并发编辑后误删。
            guard NSMaxRange(candidate.span.sourceRange) <= latest.length,
                  latest.substring(with: candidate.span.sourceRange) == candidate.expected
            else { continue }
            convertReparsedSpan(candidate.span, mark: candidate.mark,
                                start: &start, end: &end)
            changed = true
        }

        undoManager?.endUndoGrouping()
        if undoWasDisabled { undoManager?.enableUndoRegistration() }
        breakUndoCoalescing()

        if changed {
            let length = ((textStorage?.string ?? "") as NSString).length
            let location = min(start, length)
            let tail = max(0, min(end, length) - location)
            setSelectedRange(NSRange(location: location, length: tail))
            typingAttributes = originalTyping
        }
        return changed
    }

    /// 单个已闭合片段的渲染期转换：删标记（右到左）、内容按设值语义加 mark。
    /// 删除会让光标左移，用 `start`/`end` 记录并按删除范围校正。
    private func convertReparsedSpan(_ span: MarkdownSyntax.Inline, mark: DocumentMark,
                                     start: inout Int, end: inout Int) {
        let command = DocumentFormatCommand(id: "format.markdown.reparse", title: "Markdown",
                                            block: nil, mark: mark)
        for marker in span.markerRanges.sorted(by: { $0.location > $1.location }) {
            start = mappedPoint(start, deleting: marker)
            end = mappedPoint(end, deleting: marker)
            insertText("", replacementRange: marker)
        }
        // 开标记删除后内容起点回到 sourceRange.location（与输入期同一算法）。
        let contentRange = NSRange(location: span.sourceRange.location,
                                   length: span.contentRange.length)
        applyFormat(command, inlineRange: contentRange)
    }

    /// 删除 `range` 后，一个点的新位置。
    private func mappedPoint(_ point: Int, deleting range: NSRange) -> Int {
        if range.location >= point { return point }
        if NSMaxRange(range) <= point { return point - range.length }
        return range.location
    }
}
