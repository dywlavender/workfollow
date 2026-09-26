import SwiftUI

struct TaskDateButton: View {
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    var timeOnly = false
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: {
            if let date = task.schedule.dueAt {
                Text(timeOnly && task.schedule.hasTime
                     ? Self.clockLabel(date, calendar: workspace.calendar)
                     : TaskDateLabel.text(date, hasTime: task.schedule.hasTime, now: workspace.clock(), calendar: workspace.calendar))
                    .lineLimit(1)
            } else {
                Image(systemName: "calendar.badge.plus")
            }
        }.buttonStyle(.plain).font(WFType.supporting)
            .foregroundStyle(task.isClosed ? WFColors.tertiaryText : isOverdue ? .red : WFColors.accent)
            .help("修改安排日期")
            .popover(isPresented: $presented) {
                TaskDatePopoverV2(task: task, workspace: workspace) { presented = false }
            }
    }

    private var isOverdue: Bool {
        guard let dueAt = task.schedule.dueAt else { return false }
        return workspace.calendar.startOfDay(for: dueAt) < workspace.calendar.startOfDay(for: workspace.clock())
    }

    private static func clockLabel(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

/// A draft: selecting a day never mutates the task until Confirm is pressed.
/// The redesigned popover lives in TaskDatePopoverV2.

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

/// Recurrence rule editor. Standalone in its own popover, or embedded as the
/// 重复 sub-page of TaskDatePopoverV2 (same width, back instead of cancel).
/// Saves immediately on 确定, matching TaskRecurrenceEditor's contract.
struct RecurrenceDraftView: View {
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    var embedded = false
    let onClose: () -> Void
    @State private var frequency: TaskRepeat
    @State private var interval: Int
    @State private var ending: Int
    @State private var count: Int
    @State private var endDate: Date
    @State private var weekday: Int
    @State private var monthDay: Int
    @State private var month: Int

    init(task: Task, workspace: TaskWorkspaceModel, embedded: Bool = false, onClose: @escaping () -> Void) {
        self.task = task; self.workspace = workspace; self.embedded = embedded; self.onClose = onClose
        _frequency = State(initialValue: task.recurrence)
        _interval = State(initialValue: task.recurrenceRule?.interval ?? 1)
        _ending = State(initialValue: task.recurrenceRule?.endDate != nil ? 1 : task.recurrenceRule?.remainingCount != nil ? 2 : 0)
        _count = State(initialValue: task.recurrenceRule?.remainingCount ?? 10)
        _endDate = State(initialValue: task.recurrenceRule?.endDate ?? workspace.dateFromToday(30))
        let base = task.schedule.dueAt ?? workspace.clock()
        _weekday = State(initialValue: task.recurrenceRule?.weekday ?? workspace.calendar.component(.weekday, from: base))
        _monthDay = State(initialValue: task.recurrenceRule?.monthDay ?? workspace.calendar.component(.day, from: base))
        _month = State(initialValue: task.recurrenceRule?.month ?? workspace.calendar.component(.month, from: base))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("重复规则").font(.headline)
            Picker("频率", selection: $frequency) {
                ForEach(TaskRepeat.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if frequency != .never {
                Stepper("间隔：\(interval) 个周期", value: $interval, in: 1...365)
                if frequency == .weekly {
                    Picker("星期", selection: $weekday) {
                        ForEach(1...7, id: \.self) { day in Text(["周日", "周一", "周二", "周三", "周四", "周五", "周六"][day - 1]).tag(day) }
                    }
                }
                if frequency == .yearly { Stepper("月份：\(month)", value: $month, in: 1...12) }
                if frequency == .monthly || frequency == .yearly { Stepper("日期：\(monthDay) 日", value: $monthDay, in: 1...31) }
                if frequency == .workdays || frequency == .holidays {
                    Text("内置 2025–2026 年中国节假日；其他年份按普通周末计算。")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                Button(embedded ? "返回" : "取消", action: onClose)
                Button("确定") {
                    workspace.setRecurrence(task.id, frequency: frequency,
                        rule: RecurrenceRule(interval: interval,
                            endDate: ending == 1 ? endDate : nil,
                            remainingCount: ending == 2 ? count : nil,
                            monthDay: monthDay, weekday: weekday, month: month))
                    onClose()
                }.buttonStyle(.borderedProminent)
            }
        }.padding(16).frame(width: 320)
            .environment(\.calendar, workspace.calendar)
            .environment(\.timeZone, workspace.calendar.timeZone)
    }
}
