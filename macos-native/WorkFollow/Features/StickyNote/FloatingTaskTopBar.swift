import AppKit
import SwiftUI

/// 任务浮窗的上下文顶栏：沿用任务详情顶栏的完成、日期、重复、类型、笔记信息和优先级。
struct FloatingTaskTopBar: View {
    let taskID: UUID
    @ObservedObject var workspace: TaskWorkspaceModel
    @Environment(\.workfollowBackgroundTheme) private var backgroundTheme
    @Environment(\.colorScheme) private var colorScheme

    private enum SchedulePanel: Equatable { case due, deadline, recurrence }
    @State private var activeSchedule: SchedulePanel?
    @State private var showKind = false
    @State private var showInfo = false
    @State private var showPriority = false
    @State private var pendingChecklistTaskID: UUID?

    var body: some View {
        if let task = workspace.task(for: taskID), task.deletedAt == nil {
            TaskInspectorHeader(
                task: task, showBack: false,
                onBack: {},
                onComplete: { _ = workspace.changeStatus(task) },
                onRepeat: { activeSchedule = .recurrence },
                onInfo: task.document.isEmpty ? nil : { showInfo.toggle() },
                onKind: { showKind.toggle() },
                kindSymbol: task.kind.symbol,
                horizontalPadding: FloatingEditorMetrics.contentHorizontalPadding,
                height: FloatingEditorMetrics.topBarHeight,
                schedule: { scheduleChip(task) },
                priority: { priorityButton(task) })
            .anchoredPropertyPanel(isPresented: $showKind,
                                   trigger: TaskInspectorHeaderPanel.kind,
                                   width: PopupMetrics.taskMenuWidth, title: "任务类型") {
                kindPopover(task)
            }
            .anchoredPropertyPanel(isPresented: $showInfo,
                                   trigger: TaskInspectorHeaderPanel.info,
                                   width: PopupMetrics.noteInfoWidth, title: "笔记信息") {
                TaskNoteInfoPanel(info: TaskNoteInfo(task: task), calendar: workspace.calendar)
            }
            .schedulePopover(isPresented: scheduleBinding(.recurrence), trigger: .recurrence) {
                TaskDatePopoverV2(task: task, workspace: workspace, initialPage: .recurrence) {
                    activeSchedule = nil
                }
            }
            .onChange(of: task.id) { _, _ in closePanels() }
            .workfollowAlert(
                "切换模式后，当前排版格式将失效，是否继续？",
                message: "标题、引用、代码与分割线会保留，但不会变成检查事项，也不计入清单进度。",
                isPresented: Binding(get: { pendingChecklistTaskID != nil },
                                     set: { if !$0 { pendingChecklistTaskID = nil } }),
                actions: [
                    .cancel(),
                    .primary("继续") {
                        guard let id = pendingChecklistTaskID else { return }
                        pendingChecklistTaskID = nil
                        workspace.setKind(id, .checklist)
                    }
                ])
        }
    }

    private func scheduleChip(_ task: Task) -> some View {
        HStack(spacing: WFSpace.dense) {
            AppKitScheduleChip(symbol: "calendar",
                               title: scheduleLabel(task),
                               tint: scheduleTint(task),
                               accessibilityLabel: scheduleLabel(task),
                               action: { activeSchedule = .due })
                .frame(height: WFMetrics.controlHeight)
                .scheduleTrigger(.date)
                .schedulePopover(isPresented: scheduleBinding(.due)) {
                    TaskDatePopoverV2(task: task, workspace: workspace) {
                        activeSchedule = nil
                    }
                }
            if let deadline = task.schedule.deadlineAt {
                deadlineButton(task, deadline: deadline)
            }
        }
    }

    private func deadlineButton(_ task: Task, deadline: Date) -> some View {
        let now = workspace.clock()
        let overdue = !task.isClosed
            && workspace.calendar.startOfDay(for: deadline) < workspace.calendar.startOfDay(for: now)
        let day = TaskDateLabel.text(deadline, hasTime: false, now: now, calendar: workspace.calendar)
        return Button { activeSchedule = .deadline } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 11))
                Text("截止 \(day)")
                    .lineLimit(1)
            }
            .font(WFType.control)
            .foregroundStyle(overdue ? WFColors.danger : WFColors.secondaryText)
            .padding(.horizontal, WFSpace.xs)
            .padding(.vertical, WFSpace.xs)
            .contentShape(Rectangle())
            .popupMenuRowBackground()
        }
        .buttonStyle(.plain)
        .hoverTip("修改截止日期")
        .accessibilityLabel("截止日期：\(day)")
        .schedulePopover(isPresented: scheduleBinding(.deadline)) {
            TaskDatePopoverV2(task: task, workspace: workspace, deadline: true) {
                activeSchedule = nil
            }
        }
    }

    private func scheduleLabel(_ task: Task) -> String {
        TaskInspectorSchedulePresentation.label(schedule: task.schedule, now: workspace.clock(),
                                                calendar: workspace.calendar, isClosed: task.isClosed)
    }

    private func scheduleTint(_ task: Task) -> NSColor {
        if task.isClosed { return NSColor(WFColors.secondaryText) }
        switch TaskInspectorSchedulePresentation.tone(schedule: task.schedule, now: workspace.clock(),
                                                      calendar: workspace.calendar) {
        case .overdue: return NSColor(WFColors.danger)
        case .scheduled: return NSColor(WFColors.accent)
        case .empty: return NSColor(WFColors.tertiaryText)
        }
    }

    private func priorityButton(_ task: Task) -> some View {
        AppKitIconButton(symbol: task.priority == .none ? "flag" : "flag.fill",
                         pointSize: 14,
                         tint: NSColor(task.priority.menuColor),
                         accessibilityLabel: "优先级：\(task.priority.shortTitle)",
                         action: { showPriority.toggle() })
            .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
            .background {
                AnchoredPropertyPanel(isPresented: $showPriority,
                                      width: PopupMetrics.priorityMenuWidth,
                                      placement: .dropdown,
                                      focusPolicy: .preservePresenter,
                                      title: "优先级") {
                    priorityPopover(task)
                }
            }
            .onChange(of: task.id) { _, _ in showPriority = false }
    }

    private func priorityPopover(_ task: Task) -> some View {
        VStack(spacing: 2) {
            ForEach(TaskPriority.menuOrder, id: \.self) { priority in
                PopupMenuRow(action: {
                    showPriority = false
                    workspace.setPriority(task.id, priority)
                }) {
                    HStack(spacing: WFSpace.dense) {
                        Image(systemName: priority == .none ? "flag" : "flag.fill")
                            .foregroundStyle(priority.menuColor)
                        Text(priority.title)
                        Spacer(minLength: 0)
                    }
                    .font(WFType.menu)
                }
                .foregroundStyle(WFColors.text)
            }
        }
        .padding(8)
        .frame(width: PopupMetrics.priorityMenuWidth)
        .background(backgroundTheme.popupFill(for: colorScheme), in: RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius).stroke(WFColors.border))
        .background(PopupEscapeRouter(depth: 2) { showPriority = false })
    }

    private func kindPopover(_ task: Task) -> some View {
        VStack(spacing: 2) {
            ForEach(TaskKind.menuOrder, id: \.self) { kind in
                PopupMenuRow(action: { select(kind, task: task) }) {
                    HStack(spacing: 8) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 12))
                            .foregroundStyle(WFColors.secondaryText)
                            .frame(width: 16)
                        Text(kind.title)
                        Spacer(minLength: 0)
                        if task.kind == kind {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(WFColors.accent)
                        }
                    }
                    .font(WFType.menu)
                }
                .foregroundStyle(WFColors.text)
            }
        }
        .padding(8)
        .frame(width: PopupMetrics.taskMenuWidth)
        .background(backgroundTheme.popupFill(for: colorScheme), in: RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius).stroke(WFColors.border))
        .background(PopupEscapeRouter(depth: 2) { showKind = false })
    }

    private func select(_ kind: TaskKind, task: Task) {
        showKind = false
        if kind == .checklist,
           let document = try? task.document.materialized(),
           TaskActions.checklistConversionImpact(in: document).requiresConfirmation {
            pendingChecklistTaskID = task.id
        } else {
            workspace.setKind(task.id, kind)
        }
    }

    private func scheduleBinding(_ panel: SchedulePanel) -> Binding<Bool> {
        Binding(get: { activeSchedule == panel },
                set: { presented in
                    if presented { activeSchedule = panel }
                    else if activeSchedule == panel { activeSchedule = nil }
                })
    }

    private func closePanels() {
        activeSchedule = nil
        showKind = false
        showInfo = false
        showPriority = false
        pendingChecklistTaskID = nil
    }
}
