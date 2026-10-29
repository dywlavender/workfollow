import SwiftUI

/// 列表区的批量动作条（任务栏优化第三批）。
///
/// 滴答的 `TTTaskListViewController` 有 `isMultipleModeForOneSelected` /
/// `firstModelForMultipleSelection`：多选是一个**显式模式**，选中多条时操作入口
/// 就在手边。本地多选（Cmd/Shift 点击）早就有了，但动作只在右侧
/// `TaskBatchPanelView`——鼠标要横穿整个窗口才能删掉刚框住的十条。
///
/// 这条 bar 是"手边入口"，不是第二套语义：所有动作都转发到 `TaskBatchOperation`
/// （`TaskActions.swift`），撤销/HUD 与右侧面板完全一致。
struct TaskBulkActionBar: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    /// 打开完整面板（右侧详情栏那份），留给"更多"。
    var onOpenPanel: () -> Void

    private var count: Int { workspace.bulkSelection.count }

    var body: some View {
        HStack(spacing: WFSpace.sm) {
            Text("已选择 \(count) 项")
                .font(WFType.control)
                .foregroundStyle(WFColors.text)
                .lineLimit(1)
            Spacer(minLength: WFSpace.sm)
            compactAction("完成", symbol: "checkmark.circle") { workspace.applyBulk(.complete) }
            compactAction("置顶", symbol: "pin") { workspace.applyBulk(.pin(true)) }
            compactAction("删除", symbol: "trash") { workspace.applyBulk(.delete) }
            compactAction("更多", symbol: "ellipsis.circle", action: onOpenPanel)
            Button { workspace.clearBulkSelection() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WFColors.secondaryText)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverTip("取消选择")
            .accessibilityLabel("取消选择")
        }
        .padding(.horizontal, WFSpace.sm)
        .frame(height: TaskListMetrics.bulkBarHeight)
        .background(WFColors.secondarySurface, in: RoundedRectangle(cornerRadius: WFMetrics.corner))
        .overlay(RoundedRectangle(cornerRadius: WFMetrics.corner)
            .stroke(WFColors.border, lineWidth: 1))
        .padding(.horizontal, WFSpace.xl)
        .padding(.vertical, WFSpace.xs)
        // Esc 退出批量（与右侧面板同一个出口口径）。
        .onExitCommand { workspace.clearBulkSelection() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("批量操作，已选择 \(count) 项")
    }

    private func compactAction(_ title: String, symbol: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(title).font(WFType.supporting)
            }
            .foregroundStyle(WFColors.secondaryText)
            .padding(.horizontal, WFSpace.sm)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
