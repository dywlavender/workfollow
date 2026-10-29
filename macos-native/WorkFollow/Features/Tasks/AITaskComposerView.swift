import SwiftUI

struct AITaskComposerView: View {
    let request: AITaskRequest
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
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
            if let applyError { Text(applyError).font(WFType.supporting).foregroundStyle(.red).padding(.horizontal, 20).padding(.bottom, 8) }
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
        .background(WFColors.content)
        .task(id: attempt) {
            var client = SummaryPiOptimizer()
            client.executable = environment.meetingStore.configuration.executable
            client.model = environment.meetingStore.configuration.resolvedMinutesModel
            await session.generate(request: request) { source in
                client.textModel = try environment.aiModels.request()
                return try await client.generateTasks(source)
            }
        }
        .accessibilityIdentifier("ai-task-composer")
        .accessibilityElement(children: .contain)
    }

    private var isReady: Bool { if case .ready = session.phase { true } else { false } }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .loading:
            VStack(spacing: 12) { ProgressView().controlSize(.small); Text(request.isBreakdown ? "正在整理执行步骤…" : "正在提取待办…") }
                .font(WFType.body).foregroundStyle(WFColors.secondaryText)
        case let .failed(message):
            VStack(spacing: 12) {
                Text(message).multilineTextAlignment(.center)
                HStack {
                    Button("重新生成") { attempt += 1 }
                    Button("AI 模型设置…") { environment.settingsSection = .ai; openSettings() }
                }
            }.padding(24)
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
                            AITaskDraftRow(draft: $draft)
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

private struct AITaskDraftRow: View {
    @Binding var draft: AITaskDraft
    @State private var expanded = false

    private var summary: String {
        var parts: [String] = []
        if let date = draft.schedule.dueAt { parts.append("安排 " + date.formatted(.dateTime.month().day().locale(.appDate))) }
        if let due = draft.schedule.deadlineAt { parts.append("截止 " + due.formatted(.dateTime.month().day().locale(.appDate))) }
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
                } label: { Text(summary).font(WFType.caption).foregroundStyle(WFColors.secondaryText) }
            }
        }.padding(.vertical, 14)
    }

    private func dateRow(_ title: String, deadline: Bool) -> some View {
        let value = deadline ? draft.schedule.deadlineAt : draft.schedule.dueAt
        return HStack {
            Toggle(title, isOn: Binding(get: { value != nil }, set: { enabled in
                if deadline { draft.schedule.deadlineAt = enabled ? Calendar.current.startOfDay(for: Date()) : nil }
                else { draft.schedule.dueAt = enabled ? Calendar.current.startOfDay(for: Date()) : nil; draft.schedule.hasTime = false }
            })).toggleStyle(.checkbox)
            if value != nil {
                DatePicker(title, selection: Binding(get: { value ?? Date() }, set: { date in
                    if deadline { draft.schedule.deadlineAt = date } else { draft.schedule.dueAt = date }
                }), displayedComponents: !deadline && draft.schedule.hasTime ? [.date, .hourAndMinute] : [.date])
                .labelsHidden().datePickerStyle(.compact)
            }
        }
    }
}
