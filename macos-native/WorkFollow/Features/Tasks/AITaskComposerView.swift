import AppKit
import SwiftUI

struct AITaskComposerView: View {
    let request: AITaskRequest
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: AITaskDraftSession
    @State private var attempt = 0
    @State private var list = TaskList.inbox.name
    @State private var sectionID: String?
    @State private var applyError: String?

    init(request: AITaskRequest, session: AITaskDraftSession? = nil) {
        self.request = request
        _session = StateObject(wrappedValue: session ?? AITaskDraftSession())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(request.actionTitle).font(WFType.detailTitle)
                Text(request.title).font(WFType.supporting).foregroundStyle(WFColors.secondaryText).lineLimit(1)
                if !request.isBreakdown { destination }
            }.padding(20)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let applyError { Text(applyError).font(WFType.supporting).foregroundStyle(WFColors.danger).padding(.horizontal, 20).padding(.bottom, 8) }
            Divider()
            HStack {
                Text(request.isBreakdown ? "添加到当前任务，可一次撤销" : "保留来源，可一次撤销")
                    .font(WFType.caption).foregroundStyle(WFColors.secondaryText)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(request.isBreakdown ? "添加 \(session.selectedCount) 个子任务" : "创建 \(session.selectedCount) 项待办") { apply() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                    .tint(WFColors.accent)
                    .disabled(!isReady || session.selectedCount == 0)
            }.padding(16)
        }
        .frame(width: 560, height: 500)
        .workfollowPopupSurface()
        .task(id: attempt) {
            await session.generate(request: request) { source, updates in
                try await environment.textAIClient().generateTasks(source, updates: updates)
            }
        }
        .accessibilityIdentifier("ai-task-composer")
        .accessibilityElement(children: .contain)
    }

    private var isReady: Bool { if case .ready = session.phase { true } else { false } }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .loading:
            AIStreamingTextView(text: session.preview, status: session.status)
        case let .failed(message):
            AIWorkflowFailureView(message: message, retryAt: session.retryAt) { attempt += 1 }.padding(24)
        case .ready:
            if session.drafts.isEmpty {
                VStack(spacing: 10) {
                    Text("没有发现新的\(request.isBreakdown ? "执行步骤" : "待办")").font(WFType.sectionSemibold)
                    Text("原有内容和任务保持不变").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                    Button("重新生成") { attempt += 1 }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($session.drafts) { $draft in
                            AITaskDraftRow(draft: $draft, destination: list)
                            Divider()
                        }
                    }.padding(.horizontal, 20)
                }.compactScrollbars()
            }
        }
    }

    private var destination: some View {
        HStack(spacing: 8) {
            Text("保存到").foregroundStyle(WFColors.secondaryText)
            BusinessMenu {
                ForEach(environment.taskWorkspace.availableListNames, id: \.self) { name in
                    BusinessMenuOption(name, selected: list == name, symbol: "list.bullet") { list = name; sectionID = nil }
                }
            } label: { Label(list, systemImage: list == TaskList.inbox.name ? "tray" : "list.bullet") }
            let sections = environment.taskWorkspace.listSections(forList: list)
            if !sections.isEmpty {
                BusinessMenu {
                    BusinessMenuOption("未分组", selected: sectionID == nil) { sectionID = nil }
                    ForEach(sections) { section in
                        BusinessMenuOption(section.title, selected: sectionID == section.id) { sectionID = section.id }
                    }
                } label: { Text(sections.first { $0.id == sectionID }?.title ?? "未分组") }
            }
        }.font(WFType.supporting).padding(.top, 6)
    }

    private func apply() {
        do {
            try environment.applyAITasks(session.drafts, request: request, list: list, sectionID: sectionID)
            dismiss()
        } catch { applyError = error.localizedDescription }
    }
}

struct AITaskDraftRow: View {
    @Binding var draft: AITaskDraft
    let destination: String
    @EnvironmentObject private var environment: AppEnvironment
    @State private var expanded: Bool
    @State private var activeDateField: DateField?

    private enum DateField: Equatable { case due, deadline }

    init(draft: Binding<AITaskDraft>, destination: String, initiallyExpanded: Bool = false) {
        _draft = draft
        self.destination = destination
        _expanded = State(initialValue: initiallyExpanded)
    }

    private var workspace: TaskWorkspaceModel { environment.taskWorkspace }
    private var now: Date { workspace.clock() }
    private var calendar: Calendar { workspace.calendar }

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

    private var dueLabel: String {
        guard let start = draft.schedule.dueAt else { return "设置日期" }
        var text = TaskDateLabel.text(start, hasTime: draft.schedule.hasTime, now: now, calendar: calendar)
        if let end = draft.schedule.dueEndAt {
            if calendar.isDate(start, inSameDayAs: end), draft.schedule.hasTime {
                text += " - " + ScheduleDisplay.clockText(end, calendar: calendar)
            } else {
                text += " - " + TaskDateLabel.text(end, hasTime: draft.schedule.hasTime, now: now, calendar: calendar)
            }
        }
        return text
    }

    private var dueTint: NSColor {
        switch TaskInspectorSchedulePresentation.tone(schedule: draft.schedule, now: now, calendar: calendar) {
        case .overdue: .systemRed
        case .scheduled: NSColor(WFColors.accent)
        case .empty: .tertiaryLabelColor
        }
    }

    private var deadlineText: String {
        guard let deadline = draft.schedule.deadlineAt else { return "设置日期" }
        return TaskDateLabel.text(deadline, hasTime: false, now: now, calendar: calendar)
    }

    private var deadlineTint: NSColor {
        guard let deadline = draft.schedule.deadlineAt else { return .secondaryLabelColor }
        let day = calendar.startOfDay(for: deadline)
        let today = calendar.startOfDay(for: now)
        return day < today ? .systemRed : .secondaryLabelColor
    }

    private var summary: String {
        var parts: [String] = []
        if draft.schedule.dueAt != nil { parts.append("安排 " + dueLabel) }
        if draft.schedule.deadlineAt != nil { parts.append("截止 " + deadlineText) }
        if draft.priority != .none { parts.append(draft.priority.title) }
        return parts.isEmpty ? "日期与优先级" : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("采用这项任务", isOn: $draft.selected).labelsHidden().toggleStyle(.checkbox).padding(.top, 3)
            VStack(alignment: .leading, spacing: 8) {
                TextField("任务标题", text: $draft.title, axis: .vertical)
                    .textFieldStyle(.plain).font(WFType.body).lineLimit(1...3)
                    .accessibilityLabel("候选任务标题")
                DisclosureGroup(isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        dateRow("安排日期", deadline: false)
                        dateRow("截止日期", deadline: true)
                        HStack {
                            Text("优先级")
                            BusinessMenu {
                                ForEach(TaskPriority.menuOrder, id: \.rawValue) { priority in
                                    BusinessMenuOption(priority.title, selected: draft.priority == priority) { draft.priority = priority }
                                }
                            } label: { Text(draft.priority.title) }
                        }
                        if !draft.quote.isEmpty { Text("原文：" + draft.quote).lineLimit(3).foregroundStyle(WFColors.secondaryText).textSelection(.enabled) }
                    }.padding(.top, 8).font(WFType.supporting)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: { Text(summary).font(WFType.caption).foregroundStyle(WFColors.secondaryText) }
            }
        }.padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dateRow(_ title: String, deadline: Bool) -> some View {
        let field: DateField = deadline ? .deadline : .due
        let value = deadline ? draft.schedule.deadlineAt : draft.schedule.dueAt
        return HStack {
            Toggle(title, isOn: Binding(get: { value != nil }, set: { enabled in
                if !enabled, activeDateField == field { activeDateField = nil }
                if deadline {
                    draft.schedule.deadlineAt = enabled ? calendar.startOfDay(for: now) : nil
                } else {
                    draft.schedule.dueAt = enabled ? calendar.startOfDay(for: now) : nil
                    draft.schedule.hasTime = false
                }
            })).toggleStyle(.checkbox)
            if value != nil {
                if deadline { deadlineButton } else { dueButton }
            }
        }
    }

    private var dueButton: some View {
        AppKitScheduleChip(symbol: "calendar", title: dueLabel, tint: dueTint,
                           accessibilityLabel: "安排日期：\(dueLabel)",
                           action: { activeDateField = .due })
            .frame(height: WFMetrics.controlHeight)
            .fixedSize(horizontal: true, vertical: false)
            .scheduleTrigger(.date)
            .schedulePopover(isPresented: dateBinding(.due)) {
                TaskDatePopoverV2(task: draftTask, workspace: workspace,
                                  draftCommit: { draft.plan = $0 }) {
                    activeDateField = nil
                }
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)
            }
    }

    private var deadlineButton: some View {
        AppKitScheduleChip(symbol: "calendar.badge.exclamationmark", title: deadlineText,
                           tint: deadlineTint,
                           accessibilityLabel: "截止日期：\(deadlineText)",
                           action: { activeDateField = .deadline })
            .frame(height: WFMetrics.controlHeight)
            .fixedSize(horizontal: true, vertical: false)
            .scheduleTrigger(.date)
            .schedulePopover(isPresented: dateBinding(.deadline)) {
                TaskDatePopoverV2(task: draftTask, workspace: workspace, deadline: true,
                                  draftCommit: { draft.plan = $0 }) {
                    activeDateField = nil
                }
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)
            }
    }

    private func dateBinding(_ field: DateField) -> Binding<Bool> {
        Binding(
            get: { activeDateField == field },
            set: { presented in
                if presented {
                    activeDateField = field
                } else if activeDateField == field {
                    activeDateField = nil
                }
            }
        )
    }
}
