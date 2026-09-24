import SwiftUI

struct TaskDateButton: View {
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: {
            if let date = task.schedule.dueAt {
                Text(date.formatted(date: .abbreviated, time: task.schedule.hasTime ? .shortened : .omitted))
                    .lineLimit(1)
            } else {
                Image(systemName: "calendar.badge.plus")
            }
        }.buttonStyle(.plain).font(WFType.supporting)
            .foregroundStyle(task.status == .completed ? WFColors.tertiaryText : WFColors.accent)
            .help("修改安排日期")
            .popover(isPresented: $presented) {
                TaskDatePopover(task: task, workspace: workspace) { presented = false }
            }
    }
}

/// A draft: selecting a day never mutates the task until Confirm is pressed.
struct TaskDatePopover: View {
    let taskID: UUID
    @ObservedObject var workspace: TaskWorkspaceModel
    var deadline = false
    let onClose: () -> Void
    @State private var date: Date
    @State private var hasTime: Bool

    init(task: Task, workspace: TaskWorkspaceModel, deadline: Bool = false, onClose: @escaping () -> Void) {
        taskID = task.id
        self.workspace = workspace
        self.deadline = deadline
        self.onClose = onClose
        _date = State(initialValue: (deadline ? task.schedule.deadlineAt : task.schedule.dueAt) ?? workspace.dateFromToday(0))
        _hasTime = State(initialValue: !deadline && task.schedule.hasTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(deadline ? "截止日期" : "安排日期").font(WFType.section)
            HStack {
                Button("今天") { chooseDay(workspace.dateFromToday(0)) }
                Button("明天") { chooseDay(workspace.dateFromToday(1)) }
                Button("下周") { chooseDay(workspace.dateFromToday(7)) }
            }
            DatePicker("日期", selection: Binding(get: { date }, set: chooseDay), displayedComponents: .date)
                .datePickerStyle(.graphical).labelsHidden()
            if !deadline {
                Toggle("指定时间", isOn: $hasTime)
                if hasTime { DatePicker("时间", selection: $date, displayedComponents: .hourAndMinute) }
                Text("提醒与重复可在任务更多属性中设置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("清除") { save(clear: true) }
                Spacer()
                Button("取消", action: onClose)
                Button("确定") { save(clear: false) }.buttonStyle(.borderedProminent)
            }
        }.padding(16).frame(width: 300)
            .environment(\.calendar, workspace.calendar)
            .environment(\.timeZone, workspace.calendar.timeZone)
    }

    private func chooseDay(_ day: Date) {
        date = TaskDateDraft.movingDay(date, to: day, calendar: workspace.calendar)
    }

    private func save(clear: Bool) {
        // Read current task here, so an open popover cannot overwrite other edits.
        guard let current = workspace.task(for: taskID)?.schedule else { onClose(); return }
        let schedule = TaskDateDraft.applying(date: clear ? nil : date, hasTime: hasTime,
                                             deadline: deadline, to: current, calendar: workspace.calendar)
        _ = workspace.setSchedule(taskID, schedule)
        onClose()
    }
}

struct TaskRecurrenceEditor: View {
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    @State private var presented = false
    var body: some View {
        Button {
            presented = true
        } label: {
            LabeledContent("重复", value: task.recurrence.title + ((task.recurrenceRule?.interval ?? 1) > 1 ? "（自定义）" : ""))
        }.popover(isPresented: $presented) {
            RecurrenceDraftView(task: task, workspace: workspace) { presented = false }
        }
    }
}

private struct RecurrenceDraftView: View {
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    let onClose: () -> Void
    @State private var frequency: TaskRepeat
    @State private var interval: Int
    @State private var ending: Int
    @State private var count: Int
    @State private var endDate: Date

    init(task: Task, workspace: TaskWorkspaceModel, onClose: @escaping () -> Void) {
        self.task = task; self.workspace = workspace; self.onClose = onClose
        _frequency = State(initialValue: task.recurrence)
        _interval = State(initialValue: task.recurrenceRule?.interval ?? 1)
        _ending = State(initialValue: task.recurrenceRule?.endDate != nil ? 1 : task.recurrenceRule?.remainingCount != nil ? 2 : 0)
        _count = State(initialValue: task.recurrenceRule?.remainingCount ?? 10)
        _endDate = State(initialValue: task.recurrenceRule?.endDate ?? workspace.dateFromToday(30))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("重复规则").font(.headline)
            Picker("频率", selection: $frequency) {
                ForEach(TaskRepeat.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if frequency != .never {
                Stepper("间隔：\(interval) 个周期", value: $interval, in: 1...365)
                Picker("结束", selection: $ending) {
                    Text("永不").tag(0); Text("指定日期（含当天）").tag(1); Text("指定次数").tag(2)
                }
                if ending == 1 { DatePicker("结束日期", selection: $endDate, displayedComponents: .date) }
                if ending == 2 { Stepper("剩余 \(count) 次（含当前任务）", value: $count, in: 1...999) }
                Text("按安排日期推算；月底不足时取最后一天。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("取消", action: onClose)
                Button("确定") {
                    let base = workspace.task(for: task.id)?.schedule.dueAt ?? workspace.clock()
                    workspace.setRecurrence(task.id, frequency: frequency,
                        rule: RecurrenceRule(interval: interval,
                            endDate: ending == 1 ? endDate : nil,
                            remainingCount: ending == 2 ? count : nil,
                            monthDay: frequency == task.recurrence ? task.recurrenceRule?.monthDay ?? workspace.calendar.component(.day, from: base) : workspace.calendar.component(.day, from: base)))
                    onClose()
                }.buttonStyle(.borderedProminent)
            }
        }.padding(16).frame(width: 320)
            .environment(\.calendar, workspace.calendar)
            .environment(\.timeZone, workspace.calendar.timeZone)
    }
}
