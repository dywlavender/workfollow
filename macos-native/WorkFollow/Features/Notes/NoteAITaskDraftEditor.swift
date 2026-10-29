import AppKit
import SwiftUI

/// 点击 AI 栏里的候选任务后，由笔记页的页面级浮层承载这里；400 × 356 与日历里
/// 的任务编辑浮层同尺寸，标题、正文与日程都复用任务详情的编辑面。草稿数据绑在
/// `AITaskDraft` 上，不会为了编辑先建一条临时任务。
struct NoteAITaskDraftEditorHost: View {
    @ObservedObject var session: AITaskDraftSession
    let draftID: UUID
    let request: AITaskRequest
    let destination: String
    @ObservedObject var tasks: TaskWorkspaceModel
    let onClose: () -> Void

    var body: some View {
        if let index = session.drafts.firstIndex(where: { $0.id == draftID }) {
            NoteAITaskDraftEditor(draft: $session.drafts[index], request: request,
                                  destination: destination, tasks: tasks, onClose: onClose)
        } else {
            Color.clear.onAppear(perform: onClose)
        }
    }
}

private struct NoteAITaskDraftEditor: View {
    @Binding var draft: AITaskDraft
    let request: AITaskRequest
    let destination: String
    @ObservedObject var tasks: TaskWorkspaceModel
    let onClose: () -> Void

    @StateObject private var editorHandle = DocumentEditorHandle()
    @State private var titleEditing = false
    @State private var showSchedulePopover = false
    @State private var editingDeadline = false
    @State private var showRepeatPopover = false

    private var now: Date { tasks.clock() }

    private var draftTask: Task {
        Task(id: draft.id, title: draft.title,
             recurrence: draft.plan.frequency,
             recurrenceRule: draft.plan.recurrenceRule,
             reminderAt: draft.plan.reminder,
             reminderOffsets: draft.plan.reminderOffsets,
             list: TaskList(name: destination),
             priority: draft.priority,
             schedule: draft.plan.schedule,
             childOrder: 0,
             createdAt: now, updatedAt: now)
    }

    private var scheduleLabel: String {
        TaskInspectorSchedulePresentation.label(schedule: draft.plan.schedule,
                                                now: now, calendar: tasks.calendar)
    }

    private var scheduleTint: NSColor {
        switch TaskInspectorSchedulePresentation.tone(schedule: draft.plan.schedule,
                                                      now: now, calendar: tasks.calendar) {
        case .overdue: .systemRed
        case .scheduled: NSColor(WFColors.accent)
        case .empty: .tertiaryLabelColor
        }
    }

    private var deadlineLabel: String? {
        guard let deadline = draft.plan.schedule.deadlineAt else { return nil }
        return "截止 " + TaskDateLabel.text(deadline, hasTime: false,
                                           now: now, calendar: tasks.calendar)
    }

    private var deadlineTint: Color {
        guard let deadline = draft.plan.schedule.deadlineAt else { return WFColors.secondaryText }
        let day = tasks.calendar.startOfDay(for: deadline)
        let today = tasks.calendar.startOfDay(for: now)
        return day < today ? WFColors.danger : WFColors.secondaryText
    }

    private var showsRepeat: Bool {
        draft.plan.frequency != .never || draft.plan.recurrenceRule != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            DocumentFormattingToolbarRow(handle: editorHandle,
                                         leadingPadding: TaskInspectorMetrics.documentLeadingPadding,
                                         trailingPadding: TaskInspectorMetrics.horizontalPadding)
            Divider()
            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        AppKitTaskTitleField(text: $draft.title,
                                             isEditing: $titleEditing,
                                             placeholder: "任务标题",
                                             onSubmit: { editorHandle.focusEditor() })
                            .id(draft.id)
                            .accessibilityLabel("候选任务标题")
                            .workflowActionAnchor("note.ai.draftEditor.title")
                            .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
                            .padding(.top, TaskInspectorMetrics.titleTopPadding)
                        documentEditor
                            .padding(.top, TaskInspectorMetrics.titleDocumentGap)
                    }
                    .padding(.bottom, WFSpace.xl)
                    .frame(minWidth: viewport.size.width,
                           minHeight: viewport.size.height,
                           alignment: .topLeading)
                    .background {
                        EditorWhitespaceHitTarget(handle: editorHandle, documentID: draft.id)
                    }
                    .compactScrollbars()
                }
            }
            Divider()
            footer
        }
        .frame(width: NoteAIPaneMetrics.draftEditorSize.width,
               height: NoteAIPaneMetrics.draftEditorSize.height)
        .background(WFColors.overlay)
        .hidesSystemFocusEffect()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("编辑候选任务")
        .workflowActionAnchor("note.ai.draftEditor")
        .schedulePopover(isPresented: $showSchedulePopover) {
            TaskDatePopoverV2(task: draftTask, workspace: tasks, deadline: editingDeadline,
                              draftCommit: { draft.plan = $0 }) {
                showSchedulePopover = false
            }
            .environment(\.calendar, tasks.calendar)
            .environment(\.timeZone, tasks.calendar.timeZone)
        }
        .schedulePopover(isPresented: $showRepeatPopover, trigger: .recurrence) {
            TaskDatePopoverV2(task: draftTask, workspace: tasks, initialPage: .recurrence,
                              draftCommit: { draft.plan = $0 }) {
                showRepeatPopover = false
            }
            .environment(\.calendar, tasks.calendar)
            .environment(\.timeZone, tasks.calendar.timeZone)
        }
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(spacing: 8) {
            AppKitScheduleChip(symbol: "calendar", title: scheduleLabel, tint: scheduleTint,
                               accessibilityLabel: scheduleLabel) {
                editingDeadline = false
                showRepeatPopover = false
                showSchedulePopover = true
            }
            .frame(height: WFMetrics.controlHeight)
            .scheduleTrigger(.date)
            .accessibilityLabel("安排日期：\(scheduleLabel)")
            .workflowActionAnchor("note.ai.draftEditor.schedule")

            if let deadlineLabel {
                Button {
                    editingDeadline = true
                    showRepeatPopover = false
                    showSchedulePopover = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 11))
                        Text(deadlineLabel)
                            .lineLimit(1)
                    }
                    .font(WFType.control)
                    .foregroundStyle(deadlineTint)
                    .padding(.horizontal, WFSpace.xs)
                    .padding(.vertical, WFSpace.xs)
                    .contentShape(Rectangle())
                    .popupMenuRowBackground()
                }
                .buttonStyle(.plain)
                .hoverTip("修改截止日期", placement: .above)
                .accessibilityLabel("截止日期：\(deadlineLabel)")
                .workflowActionAnchor("note.ai.draftEditor.deadline")
            }

            if showsRepeat {
                AppKitIconButton(symbol: "repeat", pointSize: 14,
                                 tint: NSColor(WFColors.accent), accessibilityLabel: "重复") {
                    showSchedulePopover = false
                    showRepeatPopover = true
                }
                .frame(width: 24, height: WFMetrics.controlHeight)
                .scheduleTrigger(.recurrence)
                .workflowActionAnchor("note.ai.draftEditor.repeat")
            }

            Spacer(minLength: 4)

            BusinessMenu {
                ForEach(TaskPriority.menuOrder, id: \.rawValue) { priority in
                    BusinessMenuOption(priority.title, selected: draft.priority == priority,
                                       symbol: "flag", color: priority.menuColor) {
                        draft.priority = priority
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: draft.priority == .none ? "flag" : "flag.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(draft.priority.menuColor)
                    Text(draft.priority == .none ? "优先级" : draft.priority.title)
                        .font(.system(size: 12))
                        .foregroundStyle(WFColors.secondaryText)
                }
            }
            .fixedSize()

            AppKitIconButton(symbol: "xmark", pointSize: 12, tint: .inspectorSecondary,
                             accessibilityLabel: "关闭任务编辑", action: onClose)
                .frame(width: 24, height: WFMetrics.controlHeight)
                .hoverTip("关闭任务编辑")
                .workflowActionAnchor("note.ai.draftEditor.close")
        }
        .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
        .frame(height: TaskInspectorMetrics.headerHeight)
    }

    private var documentEditor: some View {
        ZStack(alignment: .topLeading) {
            DocumentEditor(documentID: draft.id,
                           document: draft.document,
                           onDocumentChange: { draft.document = $0 },
                           onEscape: {
                               onClose()
                               return .dismissPopover
                           },
                           onEditingChanged: { _ in },
                           contentSized: true,
                           handle: editorHandle,
                           decorationVisibleMinX: max(0, DocumentEditorGeometry.decorationLane
                               - TaskInspectorMetrics.documentLeadingPadding))
            if DocumentEditorPlaceholder.isVisible(for: draft.document, handle: editorHandle) {
                DocumentEditorPlaceholder(title: "添加描述…")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .workflowActionAnchor("note.ai.draftEditor.body")
        .padding(.leading, TaskInspectorMetrics.documentLeadingPadding)
        .padding(.trailing, TaskInspectorMetrics.horizontalPadding)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("保存到「\(destination)」")
                .font(.system(size: 10))
                .foregroundStyle(WFColors.tertiaryText)
                .lineLimit(1)
            Spacer()
            Button("完成", action: onClose)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
        .frame(height: TaskInspectorMetrics.footerHeight)
    }
}
