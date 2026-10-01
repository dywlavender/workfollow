import SwiftUI

/// 斜杠面板每一项前面的图形。
///
/// 原版这套图标是**自己画的**（`document_slash_menu.dart:509-694`）：点列、`1 2 3`
/// 编号、勾选框、引号、堆叠分割线、嵌套分支、标签牌、双卡，注释里明说"没有哪个
/// Material 字形能替代而不改变这套语言"。所以这里按它同一套坐标重画，而不是挑
/// 语义接近的 SF Symbol——只有"附件"那种原版本来就用标准图标的项才走符号。
enum SlashGlyphKind: Equatable {
    case heading(Int)
    case bullet
    case ordered
    case checklist
    case quote
    case divider
    case nestedItems
    case labelTag
    case linkedCards
    /// 原版也用系统图标的项（附件）。
    case symbol(String)

    /// Semantic format glyphs come from the catalog, never from a row index.
    static func forCommand(_ id: String) -> SlashGlyphKind {
        if let format = EditorCommandCatalog.format(id) { return format.descriptor.glyph }
        switch id {
        case "shared.divider": return .divider
        case "shared.attachment": return .symbol("paperclip")
        case "shared.link": return .symbol("link")
        case "task.child": return .nestedItems
        case "task.tags": return .labelTag
        case "task.relation": return .linkedCards
        default: return .symbol("text.alignleft")
        }
    }
}

/// 原版画布的度量：14 × 14 网格、线宽 1.2、主干 1.5、行线 y = 2.25 / 6.5 / 10.75。
enum SlashGlyphMetrics {
    static let box: CGFloat = 14
    static let stroke: CGFloat = 1.2
    static let trunk: CGFloat = 1.5
    static let rows: [CGFloat] = [2.25, 6.5, 10.75]
    /// 原版 `WorkFollowMacDisplay`：`H` 15、下标级别 9、编号数字 4.5。
    static let headingText: CGFloat = 15
    static let headingIndexText: CGFloat = 9
    static let orderedNumeralText: CGFloat = 4.5
}

struct SlashMenuGlyph: View {
    let kind: SlashGlyphKind
    var color: Color = WFColors.text

    var body: some View {
        Group {
            if case .symbol(let name) = kind {
                Image(systemName: name).font(.system(size: 13))
            } else {
                Canvas { context, size in
                    let scale = min(size.width, size.height) / SlashGlyphMetrics.box
                    context.scaleBy(x: scale, y: scale)
                    draw(in: &context)
                }
            }
        }
        .foregroundStyle(color)
        .frame(width: SlashGlyphMetrics.box, height: SlashGlyphMetrics.box)
    }

    private func draw(in context: inout GraphicsContext) {
        let ink = GraphicsContext.Shading.color(color)
        let line = StrokeStyle(lineWidth: SlashGlyphMetrics.stroke, lineCap: .round, lineJoin: .round)
        let trunk = StrokeStyle(lineWidth: SlashGlyphMetrics.trunk, lineCap: .round, lineJoin: .round)

        func stroke(_ path: Path, _ style: StrokeStyle = line) {
            context.stroke(path, with: ink, style: style)
        }
        func segment(_ from: CGPoint, _ to: CGPoint, _ style: StrokeStyle = line) {
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            stroke(path, style)
        }
        func dot(_ center: CGPoint, _ radius: CGFloat) {
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                               width: radius * 2, height: radius * 2)), with: ink)
        }
        /// 原版按**基线**落字；Canvas 只给锚点，用"视觉中心 ≈ 基线 − 0.35 字高"折算。
        func text(_ string: String, _ size: CGFloat, _ weight: Font.Weight, x: CGFloat, baseline: CGFloat) {
            let resolved = context.resolve(Text(string)
                .font(.system(size: size, weight: weight))
                .foregroundColor(color))
            context.draw(resolved, at: CGPoint(x: x, y: baseline - size * 0.35), anchor: .center)
        }

        switch kind {
        case .symbol:
            break
        case .heading(let level):
            text("H", SlashGlyphMetrics.headingText, .regular, x: 0.2, baseline: 11.25)
            text("\(level)", SlashGlyphMetrics.headingIndexText, .medium, x: 9.8, baseline: 11.75)
        case .bullet:
            for y in SlashGlyphMetrics.rows {
                dot(CGPoint(x: 2, y: y), 1)
                segment(CGPoint(x: 4.4, y: y), CGPoint(x: 12.5, y: y))
            }
        case .ordered:
            for (index, y) in SlashGlyphMetrics.rows.enumerated() {
                segment(CGPoint(x: 4.4, y: y), CGPoint(x: 12.5, y: y))
                // 数字是"坐在行线上的标记"，不是基线对齐的字母。
                text("\(index + 1)", SlashGlyphMetrics.orderedNumeralText, .medium,
                     x: 0.9, baseline: y + 1.6)
            }
        case .checklist:
            stroke(Path(roundedRect: CGRect(x: 1, y: 0.75, width: 11.5, height: 11.5), cornerRadius: 2.5))
            var check = Path()
            check.move(to: CGPoint(x: 3.7, y: 6.5))
            check.addLine(to: CGPoint(x: 5.6, y: 8.6))
            check.addLine(to: CGPoint(x: 9.7, y: 4))
            stroke(check)
        case .quote:
            for origin in [CGPoint(x: 0.5, y: 1.6), CGPoint(x: 7.5, y: 7.1)] {
                for offset in [CGFloat(0), 3.5] {
                    let x = origin.x + offset
                    dot(CGPoint(x: x + 1.25, y: origin.y + 1.2), 1.2)
                    var tail = Path()
                    tail.move(to: CGPoint(x: x + 2.4, y: origin.y + 1.2))
                    tail.addLine(to: CGPoint(x: x + 0.2, y: origin.y + 4.5))
                    tail.addLine(to: CGPoint(x: x + 2.4, y: origin.y + 4.5))
                    tail.closeSubpath()
                    context.fill(tail, with: ink)
                }
            }
        case .divider:
            for y in [CGFloat(1.6), 6.5, 11.3] {
                segment(CGPoint(x: 1, y: y), CGPoint(x: 12.6, y: y))
            }
        case .nestedItems:
            segment(CGPoint(x: 1.75, y: 0.75), CGPoint(x: 1.75, y: 11.75), trunk)
            segment(CGPoint(x: 1.75, y: 4.5), CGPoint(x: 8, y: 4.5), trunk)
            segment(CGPoint(x: 1.75, y: 11), CGPoint(x: 8.5, y: 11), trunk)
            dot(CGPoint(x: 11.4, y: 4.5), 1.3)
            dot(CGPoint(x: 11.4, y: 11), 1.3)
        case .labelTag:
            var tag = Path()
            tag.move(to: CGPoint(x: 0.1, y: 6.9))
            tag.addLine(to: CGPoint(x: 0.1, y: 1.8))
            tag.addQuadCurve(to: CGPoint(x: 1.8, y: 0.1), control: CGPoint(x: 0.1, y: 0.1))
            tag.addLine(to: CGPoint(x: 5.4, y: 0.1))
            tag.addLine(to: CGPoint(x: 13.4, y: 8.1))
            tag.addLine(to: CGPoint(x: 8, y: 13.5))
            tag.closeSubpath()
            stroke(tag)
            dot(CGPoint(x: 4, y: 4), 1.25)
        case .linkedCards:
            stroke(Path(roundedRect: CGRect(x: 4, y: 0.25, width: 9.5, height: 9), cornerRadius: 2.5))
            stroke(Path(roundedRect: CGRect(x: 0, y: 4.25, width: 9.5, height: 9.5), cornerRadius: 2.5))
        }
    }
}
