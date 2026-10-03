import AppKit

/// 文档块的"行首装饰"：列表标记（• / 1. / 复选框）、引用左竖线，以及
/// **只随光标出现**的活动行标记——标题级别角标（H1/H2/H3）与空行的"+"。
///
/// 全部由视图层绘制——滴答同款做法（其 `AppestKit` 里 `NSTextView` 60 处、
/// `NSTextAttachment` 14 处、**`NSTextList` 0 处**）。段落样式不挂 `textLists`：
/// macOS 14+ 的 TextKit 2 会自绘 NSTextList 标记并挤占行首空间，叠出"双点/1.1"。
/// 模型不受影响：段落类型仍存在 blockKey 里，绘制只读不写。
extension NativeTextView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBlockDecorations(in: dirtyRect)
    }

    private func drawBlockDecorations(in dirtyRect: NSRect) {
        guard let storage = textStorage, window != nil else { return }
        let source = storage.string as NSString
        if source.length > 0 {
            let visible = characterRangeForViewport() ?? NSRange(location: 0, length: source.length)

            var offset = max(0, visible.location)
            let end = min(source.length, NSMaxRange(visible))
            while offset < end {
                let paragraph = source.paragraphRange(for: NSRange(location: offset, length: 0))
                offset = NSMaxRange(paragraph)
                guard paragraph.length > 0 else { continue }
                guard let token = storage.attribute(DocumentTextCodec.blockKey, at: paragraph.location,
                                                    effectiveRange: nil) as? String else { continue }
                let kind = DocumentTextCodec.kind(token)
                guard let lineRect = viewRect(forCharacterAt: paragraph.location) else { continue }
                switch kind {
                case .bullet, .ordered, .checklist:
                    drawListMarker(kind: kind, paragraph: paragraph, lineRect: lineRect,
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
        // 标题角标与空行"+"是"光标所在行"的标记，单独走活动行这一趟。
        drawActiveLineMarker(in: dirtyRect)
    }

    private func drawListMarker(kind: DocumentBlockKind, paragraph: NSRange, lineRect: NSRect,
                                storage: NSAttributedString, dirtyRect: NSRect) {
        let accent = NSColor(WFColors.accent)
        let centerY = (lineRect.minY + lineRect.maxY) / 2
        // 三种标记统一在文字左侧 7pt 处右对齐（lineRect.minX 是首字形的起点），
        // 住在列表段落自己的缩进沟槽里，不再留出大段空白。
        let markerRightEdge = lineRect.minX - 7
        switch kind {
        case .bullet:
            let radius: CGFloat = 2.6
            let dot = NSRect(x: markerRightEdge - radius * 2, y: centerY - radius, width: radius * 2, height: radius * 2)
            guard dot.intersects(dirtyRect), let context = NSGraphicsContext.current?.cgContext else { return }
            context.setFillColor(accent.cgColor)
            context.fillEllipse(in: dot)
        case .ordered:
            let ordinal = DocumentTextCodec.ordinal(forOrderedParagraphAt: paragraph.location, in: storage)
            let marker = "\(ordinal)." as NSString
            let font = NSFont.systemFont(ofSize: 14)
            let size = marker.size(withAttributes: [.font: font])
            let frame = NSRect(x: markerRightEdge - size.width, y: lineRect.minY + (lineRect.height - size.height) / 2,
                               width: size.width, height: size.height)
            guard frame.intersects(dirtyRect) else { return }
            marker.draw(at: frame.origin, withAttributes: [.font: font, .foregroundColor: accent])
        case .checklist(let checked):
            let frame = NSRect(x: markerRightEdge - 12.96, y: centerY - 6.5, width: 12.96, height: 12.96)
            guard frame.intersects(dirtyRect) else { return }
            drawCheckbox(checked: checked, frame: frame)
        default:
            break
        }
    }

    /// 圆角方框复选框：尺寸/圆角/边宽/勾线宽取原版 `TaskDocumentMetrics`
    /// （12.96 / 4.05 / 1.053 / 1.62）。未勾选 = 透明底 + borderStrong 描边；
    /// 已勾选 = 填 documentChecklistFill + 对比色勾（勾形同原版 painter）。
    private func drawCheckbox(checked: Bool, frame: NSRect) {
        let fill = NSColor(WFColors.documentChecklistFill)
        let path = NSBezierPath(roundedRect: frame, xRadius: 4.05, yRadius: 4.05)
        if checked {
            fill.setFill()
            path.fill()
        }
        fill.setStroke()
        path.lineWidth = 1.053
        path.stroke()
        if checked {
            let checkColor = NSColor(WFColors.documentChecklistCheck)
            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: frame.minX + 3.7, y: frame.minY + 6.5))
            mark.line(to: NSPoint(x: frame.minX + 5.6, y: frame.minY + 8.6))
            mark.line(to: NSPoint(x: frame.minX + 9.7, y: frame.minY + 4))
            mark.lineWidth = 1.62
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
                       lineRect: lineRect, storage: storage, dirtyRect: dirtyRect)
    }

    private func isListMarkerKind(_ kind: DocumentBlockKind) -> Bool {
        switch kind {
        case .bullet, .ordered, .checklist: return true
        default: return false
        }
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
            }
        case .bullet, .ordered, .checklist, .quote, .code, .divider:
            break
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
        if let storage = textStorage, next < storage.length,
           storage.attribute(DocumentTextCodec.blockKey, at: next, effectiveRange: nil) as? String == "quote",
           let nextLine = viewRect(forCharacterAt: next) {
            bottom = nextLine.minY
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
