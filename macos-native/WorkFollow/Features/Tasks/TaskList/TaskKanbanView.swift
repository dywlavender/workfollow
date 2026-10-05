import SwiftUI

/// 看板视图：**以投影分组为列**（滴答：看板直接拿分组当列）。
///
/// 因此列不需要单独的数据结构——清单里有自定义分组时列就是分组，
/// 否则列就是当前的分组方式（优先级 / 日期 / 清单 / 标签 / 创建时间）。
/// 移动端/桌面端的滴答都可以把某个分组选中为看板列，这里是同一份投影直接铺开。
struct TaskKanbanView: View {
    let groups: [TaskListGroup]
    @ObservedObject var workspace: TaskWorkspaceModel
    let onSelect: (UUID) -> Void

    private static let columnWidth: CGFloat = 264

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: WFSpace.md) {
                ForEach(groups, id: \.id) { group in
                    column(group)
                }
            }
            .padding(.horizontal, WFSpace.md)
            .padding(.vertical, WFSpace.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func column(_ group: TaskListGroup) -> some View {
        VStack(alignment: .leading, spacing: WFSpace.sm) {
            HStack(spacing: WFSpace.xs) {
                Text(TaskGroupDisplay.title(group, now: workspace.clock()))
                    .font(WFType.sectionSemibold)
                    .foregroundStyle(WFColors.secondaryText)
                    .lineLimit(1)
                Text("\(group.tasks.count)")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.tertiaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, WFSpace.sm)

            ScrollView {
                VStack(spacing: WFSpace.xs) {
                    ForEach(group.tasks) { task in
                        card(task)
                    }
                }
                .padding(.horizontal, WFSpace.xs)
                .padding(.bottom, WFSpace.sm)
            }
        }
        .frame(width: Self.columnWidth, alignment: .topLeading)
        .background(WFColors.listSelection.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: WFMetrics.corner))
        // 换列 = 改归属：只有"列 = 自定义分组"时才接拖放（其它分组方式没有可写的归属字段）。
        .dropDestination(for: String.self) { values, _ in
            guard let sectionID = TaskSectionDropTarget.sectionID(for: values.first, target: group.sectionID),
                  let id = TaskSectionDropTarget.taskID(for: values.first) else { return false }
            return workspace.setTaskSection(id, sectionID: sectionID).taskID != nil
        }
    }

    /// 卡片：标题两行 + 日期 / 优先级 / 标签三枚轻标记（点一下 = 选中该任务）。
    private func card(_ task: Task) -> some View {
        Button {
            onSelect(task.id)
        } label: {
            VStack(alignment: .leading, spacing: WFSpace.xs) {
                Text(task.title.isEmpty ? "无标题" : task.title)
                    .font(WFType.listBody)
                    .foregroundStyle(task.isClosed ? WFColors.taskCompletedPreview : WFColors.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: WFSpace.xs) {
                    if let due = task.schedule.dueAt {
                        Text(TaskDateLabel.text(due, hasTime: task.schedule.hasTime,
                                                now: workspace.clock(),
                                                calendar: workspace.calendar))
                            .font(WFType.supporting)
                            .foregroundStyle(WFColors.secondaryText)
                    }
                    if task.priority != .none {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(TaskRowPriority.color(task.priority))
                    }
                    if !task.tags.isEmpty {
                        Image(systemName: "tag")
                            .font(.system(size: 9))
                            .foregroundStyle(WFColors.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(WFSpace.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WFColors.content, in: RoundedRectangle(cornerRadius: WFMetrics.corner))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(SidebarDragPayload.encode(.task(task.id)))
    }
}
