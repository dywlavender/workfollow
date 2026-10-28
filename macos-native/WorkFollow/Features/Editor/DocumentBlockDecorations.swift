import AppKit

/// 文档块的"行首装饰"：列表标记（• / 1. / 复选框）、引用左竖线，以及
/// **只随光标出现**的活动行标记——标题级别角标（H1/H2/H3）与空行的"+"。
///
/// 全部由视图层绘制——滴答同款做法（其 `AppestKit` 里 `NSTextView` 60 处、
/// `NSTextAttachment` 14 处、**`NSTextList` 0 处**）。段落样式不挂 `textLists`：
/// macOS 14+ 的 TextKit 2 会自绘 NSTextList 标记并挤占行首空间，叠出"双点/1.1"。
/// 模型不受影响：段落类型仍存在 blockKey 里，绘制只读不写。
extension NativeTextView {
    /// 代码块背景：画在文字层**之下**（`draw(_:)` 里先画背景再走 super），
    /// 连续的代码行合成一块圆角浅灰卡片。装饰层在选区之上，不能承担这个填充。
    /// 空代码块没有字符可看，卡片和"代码"占位提示也在这里一起补齐。
    func drawCodeBlockBackgrounds(in dirtyRect: NSRect) {
        for frame in codeBlockCardRects() where frame.intersects(dirtyRect) {
            let path = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
            Self.codeBlockBackgroundColor.setFill()
            path.fill()
            Self.codeBlockBorderColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        drawCodeBlockPlaceholders(in: dirtyRect)
    }

    /// 代码块卡片几何（视图坐标）。连续的代码段落合并成一块；文末空段没有
    /// 字符，主循环看不见，按待定/模型级别补一块——不输入内容也要看得见。
    func codeBlockCardRects() -> [NSRect] {
        guard let storage = textStorage else { return [] }
        let source = storage.string as NSString
        let right = bounds.maxX - (textContainer?.lineFragmentPadding ?? 5) - 2
        let inset = DocumentEditorGeometry.codeBlockTextInset
        var cards: [NSRect] = []
        var group: (top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat)?

        func flushGroup() {
            guard let rect = group else { return }
            group = nil
            cards.append(NSRect(x: rect.left, y: rect.top,
                                width: max(1, rect.right - rect.left),
                                height: max(1, rect.bottom - rect.top)))
        }
        func extendGroup(with line: NSRect) {
            if var current = group {
                current.bottom = max(current.bottom, line.maxY)
                current.right = max(current.right, right)
                group = current
            } else {
                group = (line.minY - DocumentEditorGeometry.codeBlockVerticalPadding,
                         line.maxY, line.minX - inset, right)
            }
        }

        // 按整篇归组、只画与脏矩形相交的卡片：按视口截断会让跨屏的代码块在
        // 可视边界处露出圆角/描边，滚动时像被切断。
        var offset = 0
        let end = source.length
        while offset < end {
            let paragraph = source.paragraphRange(for: NSRange(location: offset, length: 0))
            offset = NSMaxRange(paragraph)
            guard paragraph.length > 0 else { continue }
            let token = storage.attribute(DocumentTextCodec.blockKey, at: paragraph.location,
                                          effectiveRange: nil) as? String
            let isCode = DocumentTextCodec.kind(token ?? "paragraph") == .code
            if isCode, let first = viewRect(forCharacterAt: paragraph.location) {
                let lastIndex = max(paragraph.location, NSMaxRange(paragraph) - 1)
                let last = viewRect(forCharacterAt: lastIndex) ?? first
                extendGroup(with: NSRect(x: first.minX, y: first.minY,
                                         width: max(1, last.maxX - first.minX),
                                         height: max(1, last.maxY - first.minY)))
            } else {
                flushGroup()
            }
        }
        // 文末空段（整篇为空时也走这里）：光标行上的待定级别优先，其次模型级别。
        let trailingKind = pendingTrailingBlock ?? displayedTrailingBlock
        if trailingKind == .code, let line = viewRect(forCharacterAt: source.length) {
            extendGroup(with: line)
        }
        flushGroup()
        return cards
    }

    /// 空代码块里画一行浅灰"代码"，与卡片一起说明这里是一个可输入的代码块。
    private func drawCodeBlockPlaceholders(in dirtyRect: NSRect) {
        guard let storage = textStorage else { return }
        let source = storage.string as NSString
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let text = "代码" as NSString
        let size = text.size(withAttributes: attributes)

        func drawPlaceholder(at line: NSRect) {
            let frame = NSRect(x: line.minX,
                               y: line.midY - size.height / 2,
                               width: size.width, height: size.height)
            guard frame.intersects(dirtyRect) else { return }
            text.draw(at: frame.origin, withAttributes: attributes)
        }

        var offset = 0
        while offset < source.length {
            let paragraph = source.paragraphRange(for: NSRange(location: offset, length: 0))
            offset = NSMaxRange(paragraph)
            guard paragraph.length > 0 else { continue }
            let token = storage.attribute(DocumentTextCodec.blockKey, at: paragraph.location,
                                          effectiveRange: nil) as? String
            guard DocumentTextCodec.kind(token ?? "paragraph") == .code else { continue }
            let lastCharacter = source.character(at: NSMaxRange(paragraph) - 1)
            let contentLength = paragraph.length - (lastCharacter == 0x0A ? 1 : 0)
            guard contentLength == 0,
                  let line = viewRect(forCharacterAt: paragraph.location) else { continue }
            drawPlaceholder(at: line)
        }
        let trailingKind = pendingTrailingBlock ?? displayedTrailingBlock
        if trailingKind == .code, let line = viewRect(forCharacterAt: source.length) {
            drawPlaceholder(at: line)
        }
    }

    /// 行内代码底片：文字层之下的圆角浅灰小底块（与高亮色可叠）。
    func drawInlineCodeChips(in dirtyRect: NSRect) {
        let visible = characterRangeForViewport()
        for rect in inlineCodeChipRects(in: visible) where rect.intersects(dirtyRect) {
            let path = NSBezierPath(roundedRect: rect,
                                    xRadius: DocumentEditorGeometry.inlineCodeChipRadius,
                                    yRadius: DocumentEditorGeometry.inlineCodeChipRadius)
            Self.inlineCodeBackgroundColor.setFill()
            path.fill()
        }
    }

    /// 行内代码底片几何：TextKit 2 按行段枚举，折行的 run 会得到多块底片。
    /// 代码块整段已有卡片，不再叠行内底片。
    func inlineCodeChipRects(in range: NSRange? = nil) -> [NSRect] {
        guard let storage = textStorage, storage.length > 0 else { return [] }
        let full = NSRange(location: 0, length: storage.length)
        let search = range.map { NSIntersectionRange($0, full) } ?? full
        guard search.length > 0 else { return [] }
        var runs: [NSRange] = []
        storage.enumerateAttribute(DocumentTextCodec.inlineCodeKey, in: search, options: []) { value, run, _ in
            guard value as? Bool == true, run.length > 0 else { return }
            let token = storage.attribute(DocumentTextCodec.blockKey, at: run.location,
                                          effectiveRange: nil) as? String
            guard DocumentTextCodec.kind(token ?? "paragraph") != .code else { return }
            runs.append(run)
        }
        guard !runs.isEmpty, let manager = textLayoutManager,
              let content = manager.textContentManager as? NSTextContentStorage else { return [] }
        let origin = textContainerOrigin
        var rects: [NSRect] = []
        for run in runs {
            guard let start = content.location(content.documentRange.location, offsetBy: run.location),
                  let end = content.location(start, offsetBy: run.length),
                  let textRange = NSTextRange(location: start, end: end) else { continue }
            manager.enumerateTextSegments(in: textRange, type: .highlight, options: []) { _, rect, _, _ in
                var chip = rect.offsetBy(dx: origin.x, dy: origin.y)
                chip = chip.insetBy(dx: -DocumentEditorGeometry.inlineCodeChipPaddingX,
                                    dy: DocumentEditorGeometry.inlineCodeChipPaddingY)
                if chip.width > 0, chip.height > 0 { rects.append(chip) }
                return true
            }
        }
        return rects
    }

    /// 行内代码底片：浅色下黑 7%，深色下白 11%。
    static let inlineCodeBackgroundColor = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor.white.withAlphaComponent(0.11)
            : NSColor.black.withAlphaComponent(0.07)
    }

    /// 浅灰卡片：浅色下黑 5.5%，深色下白 8%（直接用动态 NSColor，切换外观自动重解析）。
    static let codeBlockBackgroundColor = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.055)
    }

    static let codeBlockBorderColor = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.07)
    }

    /// 由 `BlockDecorationOverlay` 调用（选区视图之上），不再走文本视图自己的 draw。
    func drawBlockDecorations(in dirtyRect: NSRect) {
        guard let storage = textStorage, window != nil else { return }
        let source = storage.string as NSString
        if source.length > 0 {
            let visible = characterRangeForViewport() ?? NSRange(location: 0, length: source.length)

            var offset = max(0, visible.location)
            let end = min(source.length, NSMaxRange(visible))
            var lineIndex = checklistLineIndex(for: offset)
            while offset < end {
                let paragraph = source.paragraphRange(for: NSRange(location: offset, length: 0))
                offset = NSMaxRange(paragraph)
                defer { lineIndex += 1 }
                guard paragraph.length > 0 else { continue }
                guard let token = storage.attribute(DocumentTextCodec.blockKey, at: paragraph.location,
                                                    effectiveRange: nil) as? String else { continue }
                let kind = DocumentTextCodec.kind(token)
                guard let lineRect = viewRect(forCharacterAt: paragraph.location) else { continue }
                switch kind {
                case .bullet, .ordered:
                    drawListMarker(kind: kind, paragraph: paragraph, lineRect: lineRect,
                                   storage: storage, lineIndex: lineIndex, dirtyRect: dirtyRect)
                case .checklist:
                    drawListMarker(kind: kind, paragraph: paragraph, lineRect: lineRect,
                                   storage: storage, lineIndex: lineIndex, dirtyRect: dirtyRect)
                    drawChecklistSeparator(paragraph: paragraph, firstLine: lineRect,
                                           storage: storage, dirtyRect: dirtyRect)
                case .quote:
                    drawQuoteRule(paragraph: paragraph, firstLine: lineRect, dirtyRect: dirtyRect)
                default:
                    break
                }
            }
        }
        // 文末空段没有字符，主循环看不到：待定/模型级别是列表时常驻补画标记
        // （不随光标消失；标题角标才是"只随光标"的活动行标记）。
        drawTrailingListMarkerIfPresent(in: dirtyRect)
        // 引用同理：文末空引用行的竖线也要在没有文字时可见。
        drawTrailingQuoteRuleIfPresent(in: dirtyRect)
        // 标题角标与空行"+"是"光标所在行"的标记，单独走活动行这一趟。
        drawActiveLineMarker(in: dirtyRect)
        // 检查项行尾控件：优先跟随鼠标悬停行，其次光标所在行。
        drawChecklistControlRow(in: dirtyRect)
    }

    private func drawListMarker(kind: DocumentBlockKind, paragraph: NSRange, lineRect: NSRect,
                                storage: NSAttributedString, lineIndex: Int, dirtyRect: NSRect) {
        let accent = NSColor(WFColors.accent)
        let centerY = (lineRect.minY + lineRect.maxY) / 2
        // 三种标记与段落文字**左对齐**：滴答实测圆点墨迹 x19..24、有序编号 x19..28.5、
        // 列表文字 x34，正文与标题文字也起于 x19——标记对齐的是文字左缘，不是右对齐成一列。
        // 段落文字起点 = 首字形起点 − 列表文字缩进（lineRect.minX 是首字形起点）。
        let textIndent = kind.isChecklist
            ? DocumentEditorGeometry.checklistTextIndent
            : DocumentEditorGeometry.listTextIndent
        let markerOrigin = lineRect.minX - textIndent
            + DocumentEditorGeometry.listMarkerOpticalOffset
        switch kind {
        case .bullet:
            let radius: CGFloat = 2.6
            let dot = NSRect(x: markerOrigin, y: centerY - radius, width: radius * 2, height: radius * 2)
            guard dot.intersects(dirtyRect), let context = NSGraphicsContext.current?.cgContext else { return }
            context.setFillColor(accent.cgColor)
            context.fillEllipse(in: dot)
        case .ordered:
            let trailing = paragraph.location == storage.length
            let ordinal = DocumentTextCodec.ordinal(forOrderedParagraphAt: paragraph.location, in: storage,
                indentLevel: trailing ? trailingIndentLevel : nil,
                listStart: trailing ? trailingListStart : nil)
            let marker = "\(ordinal)." as NSString
            let font = NSFont.systemFont(ofSize: 14)
            let size = marker.size(withAttributes: [.font: font])
            let frame = NSRect(x: markerOrigin, y: lineRect.minY + (lineRect.height - size.height) / 2,
                               width: size.width, height: size.height)
            guard frame.intersects(dirtyRect) else { return }
            marker.draw(at: frame.origin, withAttributes: [.font: font, .foregroundColor: accent])
        case .checklist(let checked):
            // 命中区仍按滴答 nib 的 17×17，可见描边框按截图收为 15×15
            // （勾选框四周各留 1pt 透明边）；与 24pt 行尾按钮同高居中。
            let frame = NSRect(x: markerOrigin + 1, y: centerY - 7.5, width: 15, height: 15)
            guard frame.intersects(dirtyRect) else { return }
            drawCheckbox(checked: checked, frame: frame)
            // 有提醒的检查项常驻一个小铃铛：不必点亮这一行也能看出提醒还在。
            if profile.checklistRemindersEnabled,
               profile.checklistItem(lineIndex)?.reminderAt != nil {
                drawChecklistBell(in: checklistReminderHitRect(centerY: centerY),
                                  color: NSColor.secondaryLabelColor, pointSize: 13,
                                  dirtyRect: dirtyRect)
            }
        default:
            break
        }
    }

    /// 圆角方框复选框：可见框 15×15，圆角/描边/勾线按截图比例缩放。
    /// 未勾选 = 透明底 + 深一档描边；已勾选 = 填浅灰 + 白色勾。
    private func drawCheckbox(checked: Bool, frame: NSRect) {
        let border = NSColor(WFColors.documentChecklistBorder)
        let fill = NSColor(WFColors.documentChecklistFill)
        let path = NSBezierPath(roundedRect: frame, xRadius: 4, yRadius: 4)
        if checked {
            fill.setFill()
            path.fill()
            fill.setStroke()
        } else {
            border.setStroke()
        }
        path.lineWidth = 1
        path.stroke()
        if checked {
            let checkColor = NSColor(WFColors.documentChecklistCheck)
            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: frame.minX + frame.width * 0.29,
                                  y: frame.minY + frame.height * 0.5))
            mark.line(to: NSPoint(x: frame.minX + frame.width * 0.43,
                                  y: frame.minY + frame.height * 0.665))
            mark.line(to: NSPoint(x: frame.minX + frame.width * 0.747,
                                  y: frame.minY + frame.height * 0.306))
            mark.lineWidth = frame.width * 0.12
            mark.lineCapStyle = .round
            mark.lineJoinStyle = .round
            checkColor.setStroke()
            mark.stroke()
        }
    }

    /// 文末空段的列表标记（常驻，不随光标消失）。
    /// 级别来源：光标在行上取输入待定（`pendingTrailingBlock`），否则取模型
    /// 同步值（`displayedTrailingBlock`）——两者都指向同一段，只是可见时机不同。
    private func drawTrailingListMarkerIfPresent(in dirtyRect: NSRect) {
        guard let storage = textStorage, window != nil else { return }
        guard let kind = pendingTrailingBlock ?? displayedTrailingBlock,
              isListMarkerKind(kind) else { return }
        let source = storage.string as NSString
        let anchor = source.length
        guard let lineRect = viewRect(forCharacterAt: anchor) else { return }
        drawListMarker(kind: kind, paragraph: NSRange(location: anchor, length: 0),
                       lineRect: lineRect, storage: storage,
                       lineIndex: checklistLineIndex(for: anchor), dirtyRect: dirtyRect)
    }

    private func isListMarkerKind(_ kind: DocumentBlockKind) -> Bool {
        switch kind {
        case .bullet, .ordered, .checklist: return true
        default: return false
        }
    }

    /// 文末空引用行的竖线。零字符段不在主循环的段落枚举里，按光标行上的
    /// 输入待定级别（`pendingTrailingBlock`）或模型同步级别补画。
    private func drawTrailingQuoteRuleIfPresent(in dirtyRect: NSRect) {
        guard let storage = textStorage, window != nil,
              (pendingTrailingBlock ?? displayedTrailingBlock) == .quote else { return }
        let anchor = storage.length
        guard let lineRect = viewRect(forCharacterAt: anchor) else { return }
        drawQuoteRule(paragraph: NSRange(location: anchor, length: 0),
                      firstLine: lineRect, dirtyRect: dirtyRect)
    }

    /// 光标所在行的沟槽标记（滴答同款：只随光标出现，点了这行才显示）：
    /// - 标题行 → 浅灰 `H1/H2/H3`；
    /// - 空行（含文末空段、整篇为空）→ 淡灰 `+`；
    /// - 列表/引用等常驻标记由主循环绘制，这里不重复。
    /// 编辑器失去焦点时全部隐藏。
    private func drawActiveLineMarker(in dirtyRect: NSRect) {
        guard isEditable, let storage = textStorage, window != nil,
              window?.firstResponder === self else { return }
        let source = storage.string as NSString
        let caret = min(max(selectedRange().location, 0), source.length)
        // 文末空段：全文以换行结尾（或整篇为空）且光标在最末——它没有字符可取
        // 段落区间；其余情况把锚点收回前一个字符，避免 NSString 把文末零长
        // 范围当成独立段落。
        let trailingEmpty = source.length == 0
            || (caret == source.length && source.character(at: source.length - 1) == 0x0A)
        let anchor = trailingEmpty ? caret : min(caret, max(source.length - 1, 0))
        guard let lineRect = viewRect(forCharacterAt: anchor) else { return }
        let centerY = (lineRect.minY + lineRect.maxY) / 2

        // 段落类型：文末空段没有字符可读属性，级别活在 typingAttributes 里。
        let kind: DocumentBlockKind? = {
            if let token = anchor < source.length
                ? storage.attribute(DocumentTextCodec.blockKey, at: anchor, effectiveRange: nil) as? String
                : typingAttributes[DocumentTextCodec.blockKey] as? String {
                return DocumentTextCodec.kind(token)
            }
            return nil
        }()

        switch kind {
        case .heading(let level):
            drawHeadingBadge(level: level, lineRect: lineRect, dirtyRect: dirtyRect)
        case .paragraph, .none:
            let paragraphRange = source.length == 0
                ? NSRange(location: 0, length: 0)
                : source.paragraphRange(for: NSRange(location: anchor, length: 0))
            let lastCharacter = paragraphRange.length > 0
                ? source.character(at: NSMaxRange(paragraphRange) - 1) : 0
            let contentLength = paragraphRange.length
                - (lastCharacter == 0x0A ? 1 : 0)
            if trailingEmpty || contentLength == 0 {
                drawEmptyLinePlus(centerY: centerY, dirtyRect: dirtyRect)
            } else {
                // TI2-21：非空正文行也给出块手柄（滴答 `TTTaskDetailMarkdownCell`
                // 的 `leadingButtonClicked:`），点它打开块类型菜单。
                drawBlockHandle(centerY: centerY, dirtyRect: dirtyRect)
            }
        case .checklist:
            // 行尾控件由 `drawChecklistControlRow` 统一绘制（悬停行优先）。
            break
        case .bullet, .ordered, .quote, .code, .divider:
            break
        }
    }

    /// 检查项行尾的铃铛/删除：鼠标悬停哪一行就在哪一行显示；没有悬停时
    /// 退回光标所在行。控件只在清单任务里出现。
    private func drawChecklistControlRow(in dirtyRect: NSRect) {
        guard profile.checklistRemindersEnabled else { return }
        let activeLine: Int? = {
            guard isEditable, window?.firstResponder === self,
                  let paragraph = activeChecklistParagraph() else { return nil }
            return checklistLineIndex(for: paragraph.location)
        }()
        guard let line = hoveredChecklistLine ?? activeLine,
              let paragraph = characterRange(forChecklistLine: line), paragraph.length > 0,
              let storage = textStorage,
              let lineRect = viewRect(forCharacterAt: paragraph.location) else { return }
        let token = storage.attribute(DocumentTextCodec.blockKey, at: paragraph.location,
                                      effectiveRange: nil) as? String
        guard token == "checklist" || token == "checked" else { return }
        drawChecklistReminderGlyph(centerY: lineRect.midY, lineIndex: line, dirtyRect: dirtyRect)
        drawChecklistDeleteGlyph(centerY: lineRect.midY, dirtyRect: dirtyRect)
    }

    /// 相邻检查项之间的细分隔线：1 物理像素、极浅灰，只画在留白中间。
    private func drawChecklistSeparator(paragraph: NSRange, firstLine: NSRect,
                                        storage: NSAttributedString, dirtyRect: NSRect) {
        let next = NSMaxRange(paragraph)
        guard next < storage.length,
              let token = storage.attribute(DocumentTextCodec.blockKey, at: next, effectiveRange: nil) as? String,
              DocumentTextCodec.kind(token).isChecklist else { return }
        let lastIndex = max(paragraph.location, NSMaxRange(paragraph) - 1)
        let lastLine = viewRect(forCharacterAt: lastIndex) ?? firstLine
        let scale = window?.backingScaleFactor ?? 2
        let thickness = 1 / scale
        let y = lastLine.maxY + DocumentEditorGeometry.checklistSeparatorOffset - thickness / 2
        // 与滴答一致：从文字左缘起，几乎铺到右缘（留 12pt）；颜色压到 #F3F3F3。
        let startX = firstLine.minX
        let rect = NSRect(x: startX, y: y,
                          width: max(0, bounds.maxX - 12 - startX), height: thickness)
        guard rect.intersects(dirtyRect) else { return }
        NSColor.separatorColor.withAlphaComponent(0.08).setFill()
        rect.fill()
    }

    /// 检查项行尾删除按钮：滴答为垃圾桶，24pt 命中区里画 13pt 图形。
    private func drawChecklistDeleteGlyph(centerY: CGFloat, dirtyRect: NSRect) {
        let rect = checklistDeleteHitRect(centerY: centerY)
        drawSymbol("trash", in: rect, pointSize: 13, color: NSColor.secondaryLabelColor,
                   dirtyRect: dirtyRect)
    }

    /// 检查项行尾铃铛；有提醒时实心加重，否则是空心入口。
    private func drawChecklistReminderGlyph(centerY: CGFloat, lineIndex: Int, dirtyRect: NSRect) {
        guard profile.checklistRemindersEnabled else { return }
        let hasReminder = profile.checklistItem(lineIndex)?.reminderAt != nil
        drawChecklistBell(in: checklistReminderHitRect(centerY: centerY),
                          color: NSColor.secondaryLabelColor, pointSize: 13,
                          filled: hasReminder, dirtyRect: dirtyRect)
    }

    private func drawChecklistBell(in rect: NSRect, color: NSColor, pointSize: CGFloat,
                                   filled: Bool = false, dirtyRect: NSRect) {
        drawSymbol(filled ? "bell.fill" : "bell", in: rect, pointSize: pointSize,
                   color: color, dirtyRect: dirtyRect)
    }

    private func drawSymbol(_ name: String, in rect: NSRect, pointSize: CGFloat,
                            color: NSColor, dirtyRect: NSRect) {
        guard rect.intersects(dirtyRect),
              let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let configured = image.withSymbolConfiguration(config) ?? image
        let size = configured.size
        configured.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                   width: size.width, height: size.height))
    }

    /// 光标所在正文行的六点块手柄：2 列 × 3 点，落在 20pt 行首沟槽里，
    /// 与"H 角标 / +"共用同一列，不侵占文字起点。
    private func drawBlockHandle(centerY: CGFloat, dirtyRect: NSRect) {
        let radius: CGFloat = 1.1
        let columnGap: CGFloat = 4.5
        let rowGap: CGFloat = 3.6
        let originX = DocumentEditorGeometry.decorationMarkerX(visibleMinX: decorationVisibleMinX)
        let top = centerY - rowGap - radius
        NSColor.tertiaryLabelColor.setFill()
        for row in 0..<3 {
            for column in 0..<2 {
                let frame = NSRect(x: originX + CGFloat(column) * columnGap,
                                   y: top + CGFloat(row) * rowGap,
                                   width: radius * 2, height: radius * 2)
                guard frame.intersects(dirtyRect) else { continue }
                NSBezierPath(ovalIn: frame).fill()
            }
        }
    }

    /// 空行的"+"：淡灰、行内垂直居中，提示这是一个可输入的空块。
    private func drawEmptyLinePlus(centerY: CGFloat, dirtyRect: NSRect) {
        let plus = "+" as NSString
        let font = NSFont.systemFont(ofSize: 13)
        let size = plus.size(withAttributes: [.font: font])
        let frame = NSRect(x: DocumentEditorGeometry.decorationMarkerX(visibleMinX: decorationVisibleMinX),
                           y: centerY - size.height / 2, width: size.width, height: size.height)
        guard frame.intersects(dirtyRect) else { return }
        plus.draw(at: frame.origin,
                  withAttributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor])
    }

    /// 标题的级别角标（滴答在标题左侧画浅灰 `H₁`，仅光标所在行显示）。
    /// 角标画在 20pt 行首沟槽里（各段落 headIndent 留出的空白，位于容器内——
    /// NSTextView 会把容器外的绘制裁掉），行内垂直居中随文字对齐；
    /// 标题文字与正文左对齐，角标不侵占文字起始位置。
    private func drawHeadingBadge(level: Int, lineRect: NSRect, dirtyRect: NSRect) {
        let badge = "H\(level)" as NSString
        let font = NSFont.systemFont(ofSize: decorationVisibleMinX > 0 ? 9 : 10, weight: .medium)
        let size = badge.size(withAttributes: [.font: font])
        let centerY = (lineRect.minY + lineRect.maxY) / 2
        let frame = NSRect(x: DocumentEditorGeometry.decorationMarkerX(visibleMinX: decorationVisibleMinX),
                           y: centerY - size.height / 2, width: size.width, height: size.height)
        guard frame.intersects(dirtyRect) else { return }
        badge.draw(at: frame.origin,
                   withAttributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor])
    }

    /// 引用左竖线：3pt `borderStrong`，纵跨整段（多行也连通）。
    /// 竖线画在正文起点处（20pt 沟槽 + 5pt 行内衬），与滴答一致。
    private func drawQuoteRule(paragraph: NSRange, firstLine: NSRect, dirtyRect: NSRect) {
        let lastLocation = max(paragraph.location, NSMaxRange(paragraph) - 1)
        guard let last = viewRect(forCharacterAt: lastLocation) else { return }
        var bottom = last.maxY
        // Adjacent quote paragraphs form one visual block. Bridge their spacing
        // without merging model blocks or changing Return/undo semantics.
        let next = NSMaxRange(paragraph)
        // 文末零长段没有下一段：next 指向自己，桥接会把高度算成 0。
        if let storage = textStorage, next > paragraph.location {
            let nextIsQuote = next < storage.length
                ? storage.attribute(DocumentTextCodec.blockKey, at: next, effectiveRange: nil) as? String == "quote"
                : (pendingTrailingBlock ?? displayedTrailingBlock) == .quote
            if nextIsQuote, let nextLine = viewRect(forCharacterAt: next) {
                bottom = nextLine.minY
            }
        }
        let rule = NSRect(x: firstLine.minX - DocumentEditorGeometry.quoteTextIndent
                            + DocumentEditorGeometry.quoteRuleInset, y: firstLine.minY,
                          width: DocumentEditorGeometry.quoteRuleWidth,
                          height: bottom - firstLine.minY)
        guard rule.intersects(dirtyRect) else { return }
        NSColor(WFColors.borderStrong).setFill()
        rule.fill()
    }

    // MARK: - 几何

    /// 字符处的首行矩形（屏幕坐标 → 视图坐标）。
    /// location 允许等于全文长度：文末空段没有字符，但插入点矩形（光标位）有效。
    func viewRect(forCharacterAt location: Int) -> NSRect? {
        guard let storage = textStorage, let window,
              location >= 0, location <= storage.length else { return nil }
        // Existing paragraphs belong to their stored character style, not the
        // current insertion style. A zero-length query can adopt the trailing
        // paragraph's typing indent when Return exits a list (16pt jump).
        // Only the characterless final paragraph needs an insertion rectangle.
        let length = location < storage.length ? 1 : 0
        let screen = firstRect(forCharacterRange: NSRange(location: location, length: length), actualRange: nil)
        guard screen.width > 0 || screen.height > 0 else { return nil }
        return convert(window.convertFromScreen(screen), from: nil)
    }

    /// 可见内容的字符范围（TextKit 2 视口；取不到时退回整篇）。
    private func characterRangeForViewport() -> NSRange? {
        guard let manager = textLayoutManager,
              let contentStorage = manager.textContentManager as? NSTextContentStorage else { return nil }
        guard let viewportRange = manager.textViewportLayoutController.viewportRange else { return nil }
        let start = viewportRange.location
        let end = viewportRange.endLocation
        let documentStart = contentStorage.documentRange.location
        let startOffset = contentStorage.offset(from: documentStart, to: start)
        let endOffset = contentStorage.offset(from: documentStart, to: end)
        guard startOffset != NSNotFound, endOffset != NSNotFound, endOffset >= startOffset else { return nil }
        return NSRange(location: startOffset, length: endOffset - startOffset)
    }
}
