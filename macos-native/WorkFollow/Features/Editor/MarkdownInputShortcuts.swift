import AppKit

/// 滴答同款：敲 Markdown 前缀自动成块（`# ` `## ` `### ` `- ` `1. ` `[] ` `[x] ` `> `）。
/// 只在"光标紧跟触发串、且该段还是普通段落"时触发；输入法合成期不触发。
extension NativeTextView {
    func applyMarkdownBlockTriggers() {
        guard isEditable, !hasMarkedText(), selectedRange().length == 0,
              let storage = textStorage, slashSession == nil else { return }
        let source = storage.string as NSString
        let caret = selectedRange().location
        guard caret <= source.length else { return }
        let paragraph = source.paragraphRange(for: NSRange(location: caret, length: 0))
        // 文末空段落没有字符可读属性（也敲不出触发串）。
        guard paragraph.location < source.length else { return }

        // 已是某种块（含检查项）就不重复触发：触发串只认普通段落。
        if let token = storage.attribute(DocumentTextCodec.blockKey, at: paragraph.location,
                                         effectiveRange: nil) as? String, token != "paragraph" {
            return
        }
        let line = source.substring(with: paragraph)
        guard let (kind, prefixLength) = Self.markdownBlockTrigger(for: line),
              caret == paragraph.location + prefixLength else { return }

        let target = DocumentTextCodec.attributes(kind: kind, marks: [])
        breakUndoCoalescing()
        // 1) 删掉触发串（剩余文字原样保留）。
        insertText("", replacementRange: NSRange(location: paragraph.location, length: prefixLength))
        // 2) 段落设成目标类型：
        //    - 段落里还有字符（换行或正文）：属性直接写上去；
        //    - 整篇变空（文末空段落）：级别走 `pendingTrailingBlock` 交给模型。
        let updated = storage.string as NSString
        let newParagraph = updated.paragraphRange(for: NSRange(location: paragraph.location, length: 0))
        if newParagraph.length > 0 {
            storage.setAttributes(target, range: newParagraph)
            invalidateDocumentLayout(for: newParagraph)
            didChangeText()
        } else {
            pendingTrailingBlock = kind == .paragraph ? nil : kind
        }
        // 3) 接着输入的内容继承该级别。
        typingAttributes = target
        needsDisplay = true
    }

    /// 触发串 → 段落类型 + 前缀长度。顺序有讲究：`### ` 要先于 `# ` 判断。
    static func markdownBlockTrigger(for line: String) -> (DocumentBlockKind, Int)? {
        if line.hasPrefix("### ") { return (.heading(3), 4) }
        if line.hasPrefix("## ") { return (.heading(2), 3) }
        if line.hasPrefix("# ") { return (.heading(1), 2) }
        if line.hasPrefix("- ") || line.hasPrefix("* ") { return (.bullet, 2) }
        if line.hasPrefix("[] ") { return (.checklist(false), 3) }
        if line.hasPrefix("[x] ") || line.hasPrefix("[X] ") { return (.checklist(true), 4) }
        if line.hasPrefix("> ") { return (.quote, 2) }
        // `1. `：数字 + 点 + 空格（上限 3 位数字，避免把「1998. 」当编号）
        if let space = line.firstIndex(of: " ") {
            let head = String(line[line.startIndex..<space])
            if head.count >= 2, head.count <= 4, head.hasSuffix("."),
               Int(head.dropLast()) != nil {
                return (.ordered, head.count + 1)
            }
        }
        return nil
    }

    /// `---` 整行 + 回车 → 水平分割线（滴答同款）。返回是否已处理。
    func convertDividerTriggerIfNeeded() -> Bool {
        guard isEditable, !hasMarkedText(), selectedRange().length == 0,
              let storage = textStorage else { return false }
        let source = storage.string as NSString
        let caret = selectedRange().location
        guard caret <= source.length else { return false }
        let paragraph = source.paragraphRange(for: NSRange(location: caret, length: 0))
        guard source.substring(with: paragraph) == "---",
              caret == NSMaxRange(paragraph) else { return false }
        // 先删掉整行 `---`，再插入分割线（与斜杠面板同一条插入路径）。
        insertText("", replacementRange: paragraph)
        insertDocumentDivider(at: paragraph.location)
        return true
    }
}
