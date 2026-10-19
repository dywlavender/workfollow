import SwiftUI

/// 详情里的标签集合行（对齐滴答 `TTTaskDetailTagCollectionCell`）。
///
/// 滴答把标签做成正文下方的一行可编辑 chip（`TTTaskDetailTagCollectionViewItem`：
/// `inputTextField` + `addImageView` + `deleteButton`）；本地此前只有底栏图标 + 浮层面板，
/// 关掉面板就看不见任务带了什么标签。这里补的是**可见性**：chip 常驻、点 × 直接移除、
/// 末尾 + 仍走原来的 `TaskTagPickerPopover`（不新增第二套标签编辑）。
struct TaskTagStrip: View {
    let tags: [String]
    var colors: [String: UInt32] = [:]
    let onEdit: () -> Void
    let onRemove: (String) -> Void

    var body: some View {
        TagFlowLayout(spacing: 6, rowSpacing: 6) {
            ForEach(tags, id: \.self) { tag in
                TagChip(name: tag, color: colors[tag].map(WFListPalette.swatch), onEdit: onEdit) { onRemove(tag) }
            }
            Button(action: onEdit) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WFColors.tertiaryText)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(WFColors.hover, in: Capsule())
            .help("添加标签")
            .accessibilityLabel("添加标签")
        }
    }

    private struct TagChip: View {
        let name: String
        let color: Color?
        let onEdit: () -> Void
        let onRemove: () -> Void
        @State private var hovered = false

        var body: some View {
            HStack(spacing: 4) {
                Button(action: onEdit) {
                    Text(name)
                        .font(WFType.listMeta)
                        .foregroundStyle(color ?? WFColors.text)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("标签：\(name)")
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(WFColors.tertiaryText)
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("移除标签「\(name)」")
                .accessibilityLabel("移除标签：\(name)")
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(height: 22)
            .background(color?.opacity(hovered ? 0.18 : 0.1) ?? (hovered ? WFColors.border : WFColors.hover), in: Capsule())
            .onHover { hovered = $0 }
        }
    }
}

/// 流式布局：chip 按容器宽度换行（滴答用 `NSCollectionView` 的 flow layout）。
/// 只服务标签行，不追求通用——宽度按 proposal、高度按行数。
struct TagFlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
