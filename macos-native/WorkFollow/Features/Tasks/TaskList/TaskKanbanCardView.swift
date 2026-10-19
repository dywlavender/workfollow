import SwiftUI

struct TaskKanbanCardView: View {
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    var showsListBadge = true
    var hidesCompleted = false
    var hidesDetails = false
    var hiddenFields: [TaskRowDetailField] = []
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(workspace.kanbanNodes(for: task, hidesCompleted: hidesCompleted), id: \.task.id) { node in
                TaskKanbanTaskRow(node: node, workspace: workspace,
                                  showsListBadge: showsListBadge,
                                  hidesDetails: hidesDetails, hiddenFields: hiddenFields,
                                  onSelect: { onSelect(node.task.id) })
                    .padding(.leading, node.depth == 0 ? 0 : 32)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: WFMetrics.corner)
                .fill(WFColors.content)
                .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: WFMetrics.corner)
                .stroke(WFColors.border, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }
}

private struct TaskKanbanTaskRow: View {
    let node: TaskTreeNode
    @ObservedObject var workspace: TaskWorkspaceModel
    let showsListBadge: Bool
    let hidesDetails: Bool
    let hiddenFields: [TaskRowDetailField]
    let onSelect: () -> Void
    @EnvironmentObject private var environment: AppEnvironment
    @State private var hovering = false
    @State private var showDatePopover = false
    @State private var contextDateAnchor: CGRect?

    private var task: Task { node.task }

    private var details: TaskKanbanCardDetails {
        .init(task: task, subtaskProgress: workspace.subtaskProgress(for: task.id),
              showsListBadge: showsListBadge, hidesDetails: hidesDetails, hiddenFields: hiddenFields)
    }

    private var muted: Color {
        task.status == .completed ? WFColors.taskCompletedMetadata
            : task.isClosed ? WFColors.tertiaryText : WFColors.secondaryText
    }

    var body: some View {
        HStack(alignment: .top, spacing: WFSpace.sm) {
            if node.hasChildren {
                Button { workspace.toggleExpanded(task.id) } label: {
                    Image(systemName: node.expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WFColors.tertiaryText)
                        .frame(width: 8, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel((node.expanded ? "收起子任务：" : "展开子任务：") + task.title)
                .taskTreeRenderAnchor(task.id, .disclosure)
            }
            Button { _ = workspace.changeStatus(task) } label: {
                TaskRowCompletionBox(task: task).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isClosed ? "恢复：\(task.title)" : "完成：\(task.title)")
            .taskTreeRenderAnchor(task.id, .checkbox)

            VStack(alignment: .leading, spacing: WFSpace.xs) {
                Text(task.title.isEmpty ? "无标题" : task.title)
                    .font(WFType.listBody)
                    .foregroundStyle(task.status == .completed ? WFColors.taskCompletedTitle
                                     : task.isClosed ? WFColors.secondaryText : WFColors.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .taskTreeRenderAnchor(task.id, .title)
                if let preview = details.preview {
                    Text(preview)
                        .font(WFType.supporting)
                        .foregroundStyle(muted)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .taskTreeRenderAnchor(task.id, .preview)
                }
                metadataDetails
            }
            .font(WFType.supporting)
            .foregroundStyle(muted)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(WFSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: WFMetrics.corner)
                .fill(workspace.selectedTaskID == task.id ? WFColors.listSelection
                      : hovering ? WFColors.hover : WFColors.content)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .modifier(TaskRowActivationPolicy())
        .onHover { hovering = $0 }
        .taskTreeRenderAnchor(task.id, .row)
        .overlay {
            SecondaryClickCapture { rowView, point in
                guard let current = workspace.task(for: task.id) else { return }
                TaskContextMenuPresenter.show(in: rowView, at: point,
                                              environment: environment,
                                              workspace: workspace, task: current,
                                              onCustomDate: {
                                                  contextDateAnchor = CGRect(origin: point, size: CGSize(width: 1, height: 1))
                                                  showDatePopover = true
                                              })
            }
        }
        .schedulePopover(isPresented: $showDatePopover, explicitAnchor: contextDateAnchor) {
            if let current = workspace.task(for: task.id) {
                TaskDatePopoverV2(task: current, workspace: workspace) { showDatePopover = false }
            }
        }
        .draggable(SidebarDragPayload.encode(.task(task.id)))
    }

    @ViewBuilder
    private var metadataDetails: some View {
        if details.showsDate || showsIndicators || details.listName != nil || !details.tags.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: WFSpace.xs) {
                    if details.showsDate { scheduleDetails }
                    if showsIndicators { indicatorDetails }
                    ownershipDetails
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 2) {
                    if details.showsDate || showsIndicators {
                        HStack(spacing: WFSpace.xs) {
                            if details.showsDate { scheduleDetails }
                            if showsIndicators { indicatorDetails }
                        }
                    }
                    ownershipDetails
                }
            }
        }
    }

    private var showsIndicators: Bool {
        details.showsPinned || details.showsAbandoned || details.showsPriority || !details.indicators.isEmpty
    }

    private var ownershipDetails: some View {
        HStack(spacing: WFSpace.xs) {
            if let list = details.listName {
                Label(list, systemImage: "list.bullet.rectangle")
                    .lineLimit(1)
                    .frame(maxWidth: 72, alignment: .leading)
                    .help(list)
            }
            if !details.tags.isEmpty {
                let tags = details.tags.map { "#" + $0 }.joined(separator: "  ")
                Text(coloredTags).lineLimit(1).frame(maxWidth: 112, alignment: .leading)
                    .help(tags).accessibilityLabel("标签：" + tags)
            }
        }
    }

    private var coloredTags: AttributedString {
        var text = AttributedString()
        for (index, name) in details.tags.enumerated() {
            var part = AttributedString((index == 0 ? "" : "  ") + "#" + name)
            part.foregroundColor = workspace.tag(named: name)?.colorARGB.map(WFListPalette.swatch) ?? muted
            text.append(part)
        }
        return text
    }

    private var scheduleDetails: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let due = task.schedule.dueAt {
                Button {
                    contextDateAnchor = nil
                    showDatePopover = true
                } label: {
                    Text(TaskDateLabel.text(due, hasTime: task.schedule.hasTime,
                                            now: workspace.clock(), calendar: workspace.calendar))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(scheduleColor)
                .help("修改安排日期")
                .accessibilityLabel("安排日期：\(task.title.isEmpty ? "无标题" : task.title)")
                .taskTreeRenderAnchor(task.id, .date)
                .scheduleTrigger()
            }
            if let deadline = task.schedule.deadlineAt {
                let overdue = !task.isClosed && workspace.calendar.startOfDay(for: deadline)
                    <= workspace.calendar.startOfDay(for: workspace.clock())
                Text(TaskDateLabel.text(deadline, hasTime: false,
                                        now: workspace.clock(), calendar: workspace.calendar) + "截止")
                    .lineLimit(1)
                    .foregroundStyle(overdue ? Color.red : muted)
            }
        }
    }

    private var scheduleColor: Color {
        guard !task.isClosed else { return muted }
        return TaskListViewDefaults.rowDateColor(for: TaskListViewDefaults.dateBadgeStyle(
            dueAt: task.schedule.dueAt, isClosed: task.isClosed,
            now: workspace.clock(), calendar: workspace.calendar))
    }

    private var indicatorDetails: some View {
        HStack(spacing: WFSpace.xs) {
            if details.showsPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(task.isClosed ? muted : WFColors.accent)
                    .accessibilityLabel("已置顶")
            }
            if details.showsAbandoned { Text("已放弃") }
            if details.showsPriority {
                Image(systemName: "flag.fill")
                    .foregroundStyle(task.isClosed ? muted : TaskRowPriority.color(task.priority))
                    .accessibilityLabel(TaskRowPriority.title(task.priority))
            }
            ForEach(details.indicators) { item in
                if let value = item.value {
                    Text(value).accessibilityLabel(item.accessibilityLabel)
                } else if let symbol = item.symbol {
                    Image(systemName: symbol).accessibilityLabel(item.accessibilityLabel)
                }
            }
        }
        .lineLimit(1)
    }
}
