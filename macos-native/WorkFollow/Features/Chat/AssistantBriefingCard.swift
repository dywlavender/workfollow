import SwiftUI

struct AssistantBriefingCard: View {
    @ObservedObject var store: AssistantBriefingStore
    @ObservedObject var jobs: AIScheduledJobStore
    @ObservedObject var followUps: MeetingFollowUpStore
    @ObservedObject var conversation: AIConversationModel
    @EnvironmentObject private var environment: AppEnvironment
    let refresh: () -> Void
    @State private var expanded = true
    @State private var showAll = false
    @State private var reviewing: MeetingFollowUp?

    private enum Item: Identifiable {
        case task(AssistantBriefingFacts.Item)
        case delivery(AIScheduledDelivery)
        case meeting(MeetingFollowUp)
        var id: UUID {
            switch self {
            case let .task(item): item.id
            case let .delivery(item): item.id
            case let .meeting(item): item.id
            }
        }
    }

    private var items: [Item] {
        followUps.pending.map(Item.meeting) + jobs.deliveries.map(Item.delivery) + store.today.map(Item.task)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 8) {
                        Text("今日简报").font(WFType.sectionSemibold)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(WFType.caption)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).workflowActionAnchor("assistant.briefing.expand")
                Spacer()
                if store.isRunning {
                    ProgressView().controlSize(.small)
                    Button("停止") { store.stop() }.buttonStyle(.plain)
                } else {
                    Button("刷新", systemImage: "arrow.clockwise", action: refresh)
                        .buttonStyle(.plain).disabled(conversation.isRunning)
                        .workflowActionAnchor("assistant.briefing.refresh")
                }
                // 整卡关闭：只收 UI，简报照常生成（正文还是会话上下文）。
                // 页头会出现「今日简报」按钮随时再打开。
                Button {
                    do { try store.setCardHidden(true) }
                    catch { environment.feedback.show(FeedbackEvent(kind: .error, message: error.localizedDescription)) }
                } label: { Image(systemName: "xmark") }
                    .labelStyle(.iconOnly).buttonStyle(.plain)
                    .hoverTip("关闭今日简报").accessibilityLabel("关闭今日简报")
                    .workflowActionAnchor("assistant.briefing.close")
            }
            if !items.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items.prefix(showAll ? items.count : 3)) { item in
                            switch item {
                            case let .task(task): AssistantTaskRow(item: task)
                            case let .delivery(delivery): deliveryRow(delivery)
                            case let .meeting(batch): meetingRow(batch)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: CGFloat(min(items.count, showAll ? 6 : 3)) * 42 - 8)
                .compactScrollbars()
                if items.count > 3 {
                    Button(showAll ? "收起" : "查看更多") { showAll.toggle() }
                        .buttonStyle(.plain).foregroundStyle(WFColors.accent)
                }
            }
            if expanded {
                let text = store.isRunning ? store.preview : store.current?.text ?? ""
                if !text.isEmpty {
                    ScrollView { AIMessageContent(text: text).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(height: 104).compactScrollbars()
                } else if !store.isRunning && items.isEmpty {
                    Text("查看今天的重点、逾期和临近截止事项。")
                        .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                }
                if let error = store.error {
                    Text(error).font(WFType.supporting).foregroundStyle(WFColors.danger)
                }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .workfollowCardSurface(in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("assistant.briefing.card")
            .onAppear {
                expanded = conversation.record.messages.isEmpty
                environment.refreshAssistantToday()
            }
            .onChange(of: conversation.record.id) { _, _ in expanded = conversation.record.messages.isEmpty }
            .onChange(of: conversation.record.messages.isEmpty) { _, empty in expanded = empty }
            .sheet(item: $reviewing) { batch in
                if let request = environment.followUpRequest(for: batch) {
                    AITaskComposerView(request: request, followUp: batch)
                }
            }
    }

    private func deliveryRow(_ item: AIScheduledDelivery) -> some View {
        HStack {
            Button {
                environment.openAIScheduledResult(item.run.conversationID)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(WFType.control).lineLimit(1)
                    Text(deliveryStatus(item.run)).font(WFType.caption)
                        .foregroundStyle(WFColors.secondaryText).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).workflowActionAnchor("assistant.delivery.open.\(item.id)")
            Button("收起", systemImage: "checkmark") {
                do { try jobs.dismissDelivery(item.id) }
                catch { environment.feedback.show(FeedbackEvent(kind: .error, message: error.localizedDescription)) }
            }.labelStyle(.iconOnly).buttonStyle(.plain)
                .accessibilityLabel("收起\(item.title)").workflowActionAnchor("assistant.delivery.dismiss.\(item.id)")
        }.frame(height: 34)
    }

    private func deliveryStatus(_ run: AIScheduledRun) -> String {
        switch run.state {
        case .running: "正在执行"
        case .complete: "定时结果已就绪"
        case .failed: run.error ?? "执行未完成"
        case .interrupted: "执行已中断"
        }
    }

    private func meetingRow(_ batch: MeetingFollowUp) -> some View {
        HStack {
            Button {
                if batch.error == nil, environment.followUpRequest(for: batch) != nil {
                    reviewing = batch
                } else if let meeting = environment.meetingStore.meetings.first(where: { $0.id == batch.id }),
                          followUps.enabled {
                    environment.generateMeetingFollowUp(meeting, retry: true)
                    environment.feedback.show(FeedbackEvent(kind: .info, message: "正在整理会议待办"))
                } else {
                    environment.feedback.show(FeedbackEvent(kind: .info, message: "会议信息已不可用或跟进已关闭"))
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(batch.title).font(WFType.control).lineLimit(1)
                    Text(batch.error == nil ? "\(batch.drafts.count) 项会议待办待确认" : "会议待办提取未完成 · 点击重试")
                        .font(WFType.caption).foregroundStyle(WFColors.secondaryText).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).workflowActionAnchor("assistant.meeting.review.\(batch.id)")
            Button("收起", systemImage: "checkmark") {
                do { try followUps.dismiss(batch) }
                catch { environment.feedback.show(FeedbackEvent(kind: .error, message: error.localizedDescription)) }
            }.labelStyle(.iconOnly).buttonStyle(.plain)
                .accessibilityLabel("收起\(batch.title)")
        }.frame(height: 34)
    }
}

private struct AssistantTaskRow: View {
    enum Edit { case date, deadline, reminder }
    let item: AssistantBriefingFacts.Item
    @EnvironmentObject private var environment: AppEnvironment
    @State private var edit: Edit?

    var body: some View {
        HStack {
            Button {
                if let url = URL(string: item.url) { environment.openResourceLink(url) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title.isEmpty ? "无标题任务" : item.title).font(WFType.control).lineLimit(1)
                    Text(reason).font(WFType.caption).foregroundStyle(WFColors.secondaryText).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).workflowActionAnchor("assistant.task.open.\(item.id)")
            if let task = environment.taskWorkspace.task(for: item.id), !task.isClosed, task.deletedAt == nil {
                BusinessMenu(width: 142, title: "任务操作") {
                    BusinessMenuOption("改期", symbol: "calendar") {
                        edit = item.categories.contains("deadline") && !item.categories.contains("overdue") ? .deadline : .date
                    }
                    BusinessMenuOption("设提醒", symbol: "bell") { edit = .reminder }
                    BusinessMenuOption("完成", symbol: "checkmark") { environment.taskWorkspace.complete(task.id) }
                        .workflowActionAnchor("assistant.task.complete.\(item.id)")
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24).contentShape(Rectangle()) }
                    .workflowActionAnchor("assistant.task.actions.\(item.id)")
                    .schedulePopover(isPresented: Binding(get: { edit != nil }, set: { if !$0 { edit = nil } })) {
                        if let edit {
                            TaskDatePopoverV2(task: task, workspace: environment.taskWorkspace,
                                deadline: edit == .deadline, initialPage: edit == .reminder ? .reminder : .main,
                                defaultReminderMinutes: edit == .reminder ? environment.assistantBriefing.defaultReminderMinutes : nil) {
                                self.edit = nil
                            }
                        }
                    }
            }
        }.frame(height: 34)
    }

    private var reason: String {
        if item.categories.contains("overdue") { return "安排已逾期" + formatted(item.date, withTime: item.hasTime) }
        if item.categories.contains("deadline") { return "截止" + formatted(item.deadline, withTime: true) }
        if item.categories.contains("today") { return "今日安排" + formatted(item.date, withTime: item.hasTime) }
        return "高重要性 · \(item.list)"
    }

    private func formatted(_ value: String?, withTime: Bool) -> String {
        guard let value, let date = try? Date(value, strategy: .iso8601) else { return "" }
        let calendar = environment.taskWorkspace.calendar
        var format = Date.FormatStyle().month().day()
        if withTime && calendar.startOfDay(for: date) != date { format = format.hour().minute() }
        format.timeZone = calendar.timeZone
        return " · " + date.formatted(format)
    }
}
