import AppKit

/// 文档块的"行首装饰"：列表标记（• / 1. / 复选框）、标题级别角标、引用左竖线。
///
/// 全部由视图层绘制——滴答同款做法（其 `AppestKit` 里 `NSTextView` 60 处、
/// `NSTextAttachment` 14 处、**`NSTextList` 0 处**），原因是我们也实测到了同一堵墙：
/// TextKit 2 不绘制 `NSTextList` 的标记（段落属性里 textLists 在、渲染无缩进无标记），
/// 而标记要着强调色、画圆角方框、勾选后填色，文本字形统统做不到。
/// 模型不受影响：段落类型仍存在 blockKey 里，绘制只读不写。
extension NativeTextView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBlockDecorations(in: dirtyRect)
    }

    private func drawBlockDecorations(in dirtyRect: NSRect) {
        guard let storage = textStorage, window != nil else { return }
        let source = storage.string as NSString
        guard source.length > 0 else { return }
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
            case .heading(let level):
                drawHeadingBadge(level: level, lineRect: lineRect, dirtyRect: dirtyRect)
            case .quote:
                drawQuoteRule(paragraph: paragraph, firstLine: lineRect, dirtyRect: dirtyRect)
            default:
                break
            }
        }
    }

    private func drawListMarker(kind: DocumentBlockKind, paragraph: NSRange, lineRect: NSRect,
                                storage: NSAttributedString, dirtyRect: NSRect) {
        let accent = NSColor(WFColors.accent)
        let centerY = (lineRect.minY + lineRect.maxY) / 2
        switch kind {
        case .bullet:
            let radius: CGFloat = 2.6
            let dot = NSRect(x: 9 - radius, y: centerY - radius, width: radius * 2, height: radius * 2)
            guard dot.intersects(dirtyRect), let context = NSGraphicsContext.current?.cgContext else { return }
            context.setFillColor(accent.cgColor)
            context.fillEllipse(in: dot)
        case .ordered:
            let ordinal = DocumentTextCodec.ordinal(forOrderedParagraphAt: paragraph.location, in: storage)
            let marker = "\(ordinal)." as NSString
            let font = NSFont.systemFont(ofSize: 14)
            let size = marker.size(withAttributes: [.font: font])
            let frame = NSRect(x: 18 - size.width, y: lineRect.minY + (lineRect.height - size.height) / 2,
                               width: size.width, height: size.height)
            guard frame.intersects(dirtyRect) else { return }
            marker.draw(at: frame.origin, withAttributes: [.font: font, .foregroundColor: accent])
        case .checklist(let checked):
            let frame = NSRect(x: 2, y: centerY - 6.5, width: 12.96, height: 12.96)
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

    /// 标题左侧的级别角标（滴答在标题行左侧画浅灰 `H₁`）。
    private func drawHeadingBadge(level: Int, lineRect: NSRect, dirtyRect: NSRect) {
        let badge = "H\(level)" as NSString
        let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        let size = badge.size(withAttributes: [.font: font])
        let frame = NSRect(x: 0, y: lineRect.maxY - size.height, width: size.width, height: size.height)
        guard frame.intersects(dirtyRect) else { return }
        badge.draw(at: frame.origin,
                   withAttributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor])
    }

    /// 引用左竖线：3pt `borderStrong`，纵跨整段（多行也连通）。
    private func drawQuoteRule(paragraph: NSRange, firstLine: NSRect, dirtyRect: NSRect) {
        let lastLocation = max(paragraph.location, NSMaxRange(paragraph) - 1)
        guard let last = viewRect(forCharacterAt: lastLocation) else { return }
        let rule = NSRect(x: 5, y: firstLine.minY, width: 3, height: last.maxY - firstLine.minY)
        guard rule.intersects(dirtyRect) else { return }
        NSColor(WFColors.borderStrong).setFill()
        rule.fill()
    }

    // MARK: - 几何

    /// 字符处的首行矩形（屏幕坐标 → 视图坐标）。
    private func viewRect(forCharacterAt location: Int) -> NSRect? {
        guard let storage = textStorage, let window,
              location >= 0, location < storage.length else { return nil }
        let screen = firstRect(forCharacterRange: NSRange(location: location, length: 0), actualRange: nil)
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
