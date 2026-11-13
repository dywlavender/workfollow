import SwiftUI

struct AIScheduledTasksView: View {
    @ObservedObject var store: AIScheduledJobStore
    @ObservedObject var runner: AIScheduledJobRunner
    let runNow: (UUID) throws -> Void
    let openResult: (UUID) -> Void
    let close: () -> Void
    @State private var editing: AIScheduledJob?
    @State private var showingEditor = false
    @State private var deletion: AIScheduledJob?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(showingEditor ? (editing == nil ? "新建定时任务" : "编辑定时任务") : "定时任务")
                    .font(WFType.detailTitle)
                Spacer()
                if !showingEditor {
                    Button("新建", systemImage: "plus") { editing = nil; showingEditor = true }
                        .workflowActionAnchor("ai.schedule.new")
                    Button("完成", action: close).keyboardShortcut(.cancelAction)
                        .workflowActionAnchor("ai.schedule.close")
                }
            }
            if showingEditor {
                AIJobEditor(job: editing, now: store.clock()) { instruction, schedule, enabled, deliverResult in
                    if let editing {
                        try store.update(editing.id, version: editing.version, title: String(instruction.prefix(28)),
                            instruction: instruction, schedule: schedule, enabled: enabled, deliverResult: deliverResult)
                    } else { try store.add(instruction: instruction, schedule: schedule, enabled: enabled, deliverResult: deliverResult) }
                    error = nil; showingEditor = false
                } cancel: { showingEditor = false }
            } else {
                if store.jobs.isEmpty {
                    VStack(spacing: 10) {
                        Text("还没有定时任务").font(WFType.sectionSemibold)
                        Text("到点让 AI 处理指定的事情，结果保存在对话历史。")
                            .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) { ForEach(store.jobs) { row($0) } }
                    }.compactScrollbars()
                }
                if let text = error ?? runner.error ?? store.storageError {
                    Text(text).font(WFType.supporting).foregroundStyle(WFColors.danger)
                }
                Text("App 运行时执行；恢复后只补最近错过的一轮。")
                    .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            }
        }.padding(22).frame(width: 570, height: 550)
            .workfollowPopupSurface().accessibilityIdentifier("ai.schedule.manager")
            .workfollowAlert("删除这个定时任务？", message: "删除计划，保留已经生成的对话和已保存的内容。",
                isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
                actions: [.cancel(), .destructive("删除") {
                    guard let deletion else { return }; self.deletion = nil
                    perform { try store.delete(deletion.id, version: deletion.version) }
                }])
    }

    private func row(_ job: AIScheduledJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(job.title).font(WFType.sectionSemibold).lineLimit(2)
                    Text(job.schedule.summary).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Toggle("启用：\(job.title)", isOn: Binding(get: { job.isEnabled }, set: { value in
                    perform { try store.update(job.id, version: job.version, enabled: value) }
                })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .workflowActionAnchor("ai.schedule.enabled.\(job.id)")
                BusinessMenu(width: 170, title: "定时任务操作") {
                    BusinessMenuOption("编辑", symbol: "pencil") { editing = job; showingEditor = true }
                        .workflowActionAnchor("ai.schedule.edit.\(job.id)")
                    BusinessMenuOption("删除", symbol: "trash", color: WFColors.danger) { deletion = job }
                        .workflowActionAnchor("ai.schedule.delete.\(job.id)")
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24).contentShape(Rectangle()) }
                    .workflowActionAnchor("ai.schedule.menu.\(job.id)")
            }
            HStack(spacing: 14) {
                if runner.runningJobID == job.id {
                    ProgressView().controlSize(.small)
                    Text("正在执行…").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                    Button("停止") { runner.stop(job.id) }.buttonStyle(.plain)
                } else {
                    Button("立即执行", systemImage: "play") { perform { try runNow(job.id) } }
                        .buttonStyle(.plain).workflowActionAnchor("ai.schedule.run.\(job.id)")
                    if let run = job.lastRun {
                        Text(status(run)).font(WFType.supporting).foregroundStyle(run.state == .failed ? WFColors.danger : WFColors.secondaryText)
                    }
                }
                Spacer(minLength: 0)
                if let run = job.lastRun {
                    Button("查看结果") { openResult(run.conversationID); close() }.buttonStyle(.plain)
                        .workflowActionAnchor("ai.schedule.result.\(job.id)")
                }
            }.font(WFType.supporting).foregroundStyle(WFColors.accent)
            if job.isEnabled, let next = job.nextRunAt {
                Text("下次 " + next.formatted(date: .abbreviated, time: .shortened))
                    .font(WFType.caption).foregroundStyle(WFColors.secondaryText)
            }
            if let message = job.lastRun?.error { Text(message).font(WFType.caption).foregroundStyle(WFColors.secondaryText) }
        }.padding(14).workfollowCardSurface(in: RoundedRectangle(cornerRadius: 10))
    }

    private func status(_ run: AIScheduledRun) -> String {
        switch run.state {
        case .running: "正在执行"
        case .complete: "上次已完成"
        case .failed: "上次未完成"
        case .interrupted: "上次已停止"
        }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action(); error = nil } catch { self.error = error.localizedDescription }
    }
}

private struct AIJobEditor: View {
    let job: AIScheduledJob?
    let now: Date
    let save: (String, AIJobSchedule, Bool, Bool) throws -> Void
    let cancel: () -> Void
    @State private var instruction: String
    @State private var frequency: AIJobSchedule.Frequency
    @State private var firstRunAt: Date
    @State private var weekday: Int
    @State private var enabled: Bool
    @State private var deliverResult: Bool
    @State private var error: String?
    private let timeZoneID: String

    init(job: AIScheduledJob?, now: Date, save: @escaping (String, AIJobSchedule, Bool, Bool) throws -> Void,
         cancel: @escaping () -> Void) {
        self.job = job; self.now = now; self.save = save; self.cancel = cancel
        let zone = job?.schedule.timeZoneID ?? TimeZone.current.identifier
        timeZoneID = zone
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: zone) ?? .current
        let date = job?.schedule.firstRunAt ?? now.addingTimeInterval(300)
        _instruction = State(initialValue: job?.instruction ?? "")
        _frequency = State(initialValue: job?.schedule.frequency ?? .daily)
        _firstRunAt = State(initialValue: date)
        _weekday = State(initialValue: cal.component(.weekday, from: date))
        _enabled = State(initialValue: job?.isEnabled ?? true)
        _deliverResult = State(initialValue: job?.deliverResult ?? false)
    }

    private var schedule: AIJobSchedule {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        var date = cal.dateInterval(of: .minute, for: firstRunAt)?.start ?? firstRunAt
        if frequency == .weekly {
            var components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear, .hour, .minute], from: date)
            components.weekday = weekday; date = cal.date(from: components) ?? date
        }
        return AIJobSchedule(frequency: frequency, firstRunAt: date, timeZoneID: timeZoneID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("要做什么").font(WFType.controlLabelStrong)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $instruction).font(WFType.body).scrollContentBackground(.hidden)
                    .padding(6).accessibilityIdentifier("ai.schedule.instruction")
                if instruction.isEmpty {
                    Text("例如：汇总今天未完成的待办和临近截止事项")
                        .font(WFType.body).foregroundStyle(WFColors.secondaryText).padding(11).allowsHitTesting(false)
                }
            }.frame(height: 126).background(WFColors.fieldFill, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Text("重复").font(WFType.controlLabelStrong)
                Spacer()
                Picker("重复", selection: $frequency) {
                    ForEach(AIJobSchedule.Frequency.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 180)
            }
            HStack {
                Text("执行时间").font(WFType.controlLabelStrong)
                Spacer()
                if frequency == .weekly {
                    Picker("星期", selection: $weekday) {
                        ForEach(1...7, id: \.self) { Text(["周日", "周一", "周二", "周三", "周四", "周五", "周六"][$0 - 1]).tag($0) }
                    }.labelsHidden().frame(width: 90)
                }
                DatePicker("执行时间", selection: $firstRunAt,
                    displayedComponents: frequency == .once ? [.date, .hourAndMinute] : [.hourAndMinute])
                    .labelsHidden().environment(\.timeZone, TimeZone(identifier: timeZoneID) ?? .current)
                    .fixedSize().accessibilityIdentifier("ai.schedule.time")
            }
            HStack {
                Toggle("启用", isOn: $enabled).toggleStyle(.switch)
                Spacer()
                Toggle("完成后告诉我", isOn: $deliverResult)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    .accessibilityIdentifier("ai.schedule.deliver")
                    .workflowActionAnchor("ai.schedule.deliver")
            }
            if enabled, let next = schedule.next(after: now) {
                Text("下次 " + next.formatted(date: .abbreviated, time: .shortened))
                    .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            }
            if let error { Text(error).font(WFType.supporting).foregroundStyle(WFColors.danger) }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
                Button("保存") {
                    do { try save(instruction.trimmingCharacters(in: .whitespacesAndNewlines), schedule, enabled, deliverResult) }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
                    .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .workflowActionAnchor("ai.schedule.save")
            }
        }
    }
}
