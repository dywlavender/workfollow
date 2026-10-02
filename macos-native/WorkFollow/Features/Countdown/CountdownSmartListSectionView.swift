import SwiftUI

/// 智能清单里的「倒数纪念日」小节。
///
/// 参考图 `18-countdown-in-today-group.png`：
///
/// ```
/// ⌄ 倒数纪念日  1
///     [图标] 审计临时-102          今天
/// ⌄ 已过期  8
///     ☐ …
/// ```
///
/// 三个要点都照它来：① **自成一节**，标题 = 模块名 + 条数；② 行 = 图标 + 名称 +
/// **右对齐的相对日标签**（今天那行是蓝色的「今天」）；③ **没有勾选框**——
/// 它不是任务，不可完成。
///
/// 标题样式与任务组头共用同一套 token（`WFType.sectionSemibold` + 条数 +
/// `TaskListMetrics.groupHeaderHeight`），免得同一屏出现两种组头。
struct CountdownSmartListSectionView: View {
    let section: CountdownSmartListSection
    let collapsed: Bool
    let onToggle: () -> Void
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if !collapsed {
                ForEach(section.entries) { entry in
                    CountdownSmartListRow(entry: entry) { onSelect(entry.id) }
                }
            }
        }
    }

    private var header: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: TaskListMetrics.groupChevronSize, weight: .semibold))
                    .foregroundStyle(WFColors.secondaryText)
                    .frame(width: TaskListMetrics.groupChevronSize,
                           height: TaskListMetrics.groupChevronSize)
                Text(CountdownSmartListSection.title).font(WFType.sectionSemibold)
                Text("\(section.count)").font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: TaskListMetrics.groupHeaderHeight,
                   alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(CountdownSmartListSection.title) \(section.count)")
        .padding(.horizontal, WFSpace.sm)
        .frame(height: TaskListMetrics.groupHeaderHeight)
    }
}

/// 小节里的一行：图标 + 名称 + 右对齐的相对日标签，**没有勾选框**。
struct CountdownSmartListRow: View {
    let entry: CountdownSmartListEntry
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: WFSpace.sm) {
                iconBadge
                Text(entry.name)
                    .font(WFType.listTitle)
                    .foregroundStyle(WFColors.text)
                    .lineLimit(1)
                Spacer(minLength: WFSpace.sm)
                Text(entry.relativeLabel)
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.accent)
            }
            .padding(.horizontal, WFSpace.sm)
            .frame(maxWidth: .infinity, minHeight: TaskListMetrics.countdownRowHeight,
                   alignment: .leading)
            .background(hovering ? WFColors.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(entry.name) · \(entry.relativeLabel)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.name)，\(entry.relativeLabel)")
    }

    /// 与卡片上那枚徽章同一套画法（`CountdownCardView.iconBadge`）：
    /// 色板圆底 + 白色字形。两处都用 `countdownColor`，颜色不会漂。
    private var iconBadge: some View {
        ZStack {
            Circle().fill(countdownColor(entry.colorIndex))
            Image(systemName: entry.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
    }
}
