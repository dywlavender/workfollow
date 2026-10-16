import SwiftUI

/// 看板视图：**以投影分组为列**（滴答：看板直接拿分组当列）。
///
/// 因此列不需要单独的数据结构——清单里有自定义分组时列就是分组，
/// 否则列就是当前的分组方式（优先级 / 日期 / 清单 / 标签 / 创建时间）。
/// 看板按同一分组规则归列，关闭任务留在所属列的可折叠小节。
struct TaskKanbanView: View {
    let groups: [TaskListGroup]
    @ObservedObject var workspace: TaskWorkspaceModel
    let onSelect: (UUID) -> Void
    var sortMode: TaskListSortMode = .manual
    var sortDescending = false
    var showsListBadge = true
    var hidesCompleted = false
    var hidesDetails = false
    var hiddenFields: [TaskRowDetailField] = []
    var scope: TaskListScope = .allTasks
    var allowsCreation = true
    @State private var addingGroupID: String?
    @State private var newCardTitle = ""
    @State private var closedExpansion = TaskGroupExpansionState()
    @FocusState private var newCardFocused: Bool

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
        let ordered = group.orderedTasks(using: sortMode, descending: sortDescending,
                                         calendar: workspace.calendar)
        let open = scope.isClosedScope ? ordered : ordered.filter { !$0.isClosed }
        let closed = scope.isClosedScope ? [] : group.tasks.filter(\.isClosed).sorted {
            ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast)
        }
        return VStack(alignment: .leading, spacing: WFSpace.sm) {
            HStack(spacing: WFSpace.xs) {
                Text(TaskGroupDisplay.title(group, now: workspace.clock()))
                    .font(WFType.sectionSemibold)
                    .foregroundStyle(WFColors.secondaryText)
                    .lineLimit(1)
                Text("\(open.count)")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.tertiaryText)
                Spacer(minLength: 0)
                if allowsCreation, group.creationTarget != nil {
                    Button {
                        addingGroupID = group.id
                        newCardTitle = ""
                        newCardFocused = true
                    } label: {
                        Image(systemName: "plus").frame(width: 22, height: 24).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("添加任务").accessibilityLabel("在" + (group.label ?? "此分组") + "添加任务")
                }
            }
            .padding(.horizontal, WFSpace.sm)

            if allowsCreation, addingGroupID == group.id {
                TextField("任务标题", text: $newCardTitle)
                    .textFieldStyle(.plain).font(WFType.listBody)
                    .focused($newCardFocused)
                    .padding(WFSpace.sm)
                    .background(WFColors.content, in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                    .overlay {
                        RoundedRectangle(cornerRadius: WFMetrics.corner)
                            .stroke(WFColors.accent, lineWidth: 1)
                    }
                    .padding(.horizontal, WFSpace.xs)
                    .onSubmit { addCard(in: group) }
                    .onExitCommand { addingGroupID = nil; newCardTitle = "" }
                    .accessibilityLabel("看板新任务标题")
            }

            ScrollView {
                VStack(spacing: WFSpace.xs) {
                    ForEach(open) { task in card(task) }
                    if !closed.isEmpty {
                        Button {
                            closedExpansion.toggle(group)
                        } label: {
                            HStack(spacing: WFSpace.xs) {
                                Image(systemName: closedExpansion.isCollapsed(group) ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(TaskListGroup.closedTitle(for: closed))
                                Text("\(closed.count)").foregroundStyle(WFColors.tertiaryText)
                                Spacer(minLength: 0)
                            }
                            .font(WFType.supporting)
                            .foregroundStyle(WFColors.secondaryText)
                            .contentShape(Rectangle())
                            .padding(.horizontal, WFSpace.xs)
                            .padding(.top, WFSpace.sm)
                            .padding(.bottom, WFSpace.xs)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel((closedExpansion.isCollapsed(group) ? "展开" : "收起")
                            + TaskGroupDisplay.title(group, now: workspace.clock()) + "的关闭任务")
                        .accessibilityValue("\(closed.count) 项")
                        if !closedExpansion.isCollapsed(group) {
                            ForEach(closed) { task in card(task) }
                        }
                    }
                }
                .padding(.horizontal, WFSpace.xs)
                .padding(.bottom, WFSpace.sm)
            }
        }
        .frame(width: Self.columnWidth, alignment: .topLeading)
        .background(WFColors.content)
        // 自定义分组的列拖放复用列表中的归属动作。
        .dropDestination(for: String.self) { values, _ in
            guard let id = TaskSectionDropTarget.taskID(for: values.first),
                  let intent = TaskSectionDropTarget.intent(
                      for: values.first,
                      target: .of(sectionID: group.sectionID,
                                  isUnsectionedBucket: group.isUnsectionedBucket)) else { return false }
            switch intent {
            case .assign(let sectionID):
                return workspace.setTaskSection(id, sectionID: sectionID).taskID != nil
            case .clear:
                return workspace.setTaskSection(id, sectionID: nil).taskID != nil
            }
        }
    }

    private func card(_ task: Task) -> some View {
        TaskKanbanCardView(task: task, workspace: workspace,
                           showsListBadge: showsListBadge,
                           hidesCompleted: hidesCompleted && !scope.isClosedScope,
                           hidesDetails: hidesDetails,
                           hiddenFields: hiddenFields,
                           onSelect: onSelect)
    }

    private func addCard(in group: TaskListGroup) {
        let title = newCardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let target = group.creationTarget,
              let id = workspace.createKanbanTask(title: title, target: target, in: scope) else { return }
        onSelect(id)
        newCardTitle = ""
        newCardFocused = true
    }

}
