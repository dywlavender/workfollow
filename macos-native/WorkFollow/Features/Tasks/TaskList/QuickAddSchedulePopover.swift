import SwiftUI

struct QuickAddScheduleDraft: Equatable {
    var dueAt: Date?
    var dueEndAt: Date?
    var hasTime: Bool
    var reminderAt: Date?
    var repeatFrequency: TaskRepeat
    var recurrenceRule: RecurrenceRule?

    var schedule: TaskSchedule {
        TaskSchedule(dueAt: dueAt, hasTime: hasTime, dueEndAt: dueEndAt)
    }

    init(dueAt: Date? = nil, dueEndAt: Date? = nil, hasTime: Bool = false,
         reminderAt: Date? = nil,
         repeatFrequency: TaskRepeat = .never, recurrenceRule: RecurrenceRule? = nil) {
        self.dueAt = dueAt
        self.dueEndAt = dueAt == nil ? nil : dueEndAt
        self.hasTime = dueAt != nil && hasTime
        self.reminderAt = reminderAt
        self.repeatFrequency = repeatFrequency
        self.recurrenceRule = recurrenceRule
    }

    init(parsed: QuickAddParseResult, defaultDueAt: Date?) {
        self.init(dueAt: parsed.dueAt ?? defaultDueAt,
                  hasTime: parsed.hasTime,
                  reminderAt: parsed.reminderAt,
                  repeatFrequency: parsed.recurrence,
                  recurrenceRule: parsed.recurrenceRule)
    }
}

struct QuickAddSchedulePopover: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let initial: QuickAddScheduleDraft
    let onCancel: () -> Void
    let onApply: (QuickAddScheduleDraft) -> Void

    @State private var hasDate: Bool
    @State private var date: Date
    @State private var hasTime: Bool
    @State private var reminderEnabled: Bool
    @State private var reminderDate: Date
    @State private var frequency: TaskRepeat

    init(workspace: TaskWorkspaceModel, initial: QuickAddScheduleDraft,
         onCancel: @escaping () -> Void,
         onApply: @escaping (QuickAddScheduleDraft) -> Void) {
        self.workspace = workspace
        self.initial = initial
        self.onCancel = onCancel
        self.onApply = onApply
        _hasDate = State(initialValue: initial.dueAt != nil)
        _date = State(initialValue: initial.dueAt ?? workspace.dateFromToday(0))
        _hasTime = State(initialValue: initial.hasTime)
        _reminderEnabled = State(initialValue: initial.reminderAt != nil)
        _reminderDate = State(initialValue: initial.reminderAt ?? workspace.clock().addingTimeInterval(3600))
        _frequency = State(initialValue: initial.repeatFrequency)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("安排日期", isOn: $hasDate)
            if hasDate {
                HStack(spacing: WFSpace.sm) {
                    Button("今天") { chooseDay(workspace.dateFromToday(0)) }
                    Button("明天") { chooseDay(workspace.dateFromToday(1)) }
                    Button("下周") { chooseDay(workspace.dateFromToday(7)) }
                }
                .buttonStyle(.borderless)

                DatePicker("日期", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()

                Toggle("指定时间", isOn: $hasTime)
                if hasTime {
                    DatePicker("时间", selection: $date, displayedComponents: .hourAndMinute)
                }
            }

            Toggle("提醒", isOn: $reminderEnabled)
            if reminderEnabled {
                DatePicker("提醒时间", selection: $reminderDate)
            }

            Picker("重复", selection: $frequency) {
                ForEach(TaskRepeat.allCases, id: \.self) { Text($0.title).tag($0) }
            }

            Divider()
            HStack {
                Button("清除") {
                    onApply(QuickAddScheduleDraft())
                }
                Spacer()
                Button("取消", action: onCancel)
                Button("确定") {
                    let due = hasDate ? TaskDateDraft.applying(
                        date: date, hasTime: hasTime, deadline: false,
                        to: TaskSchedule(), calendar: workspace.calendar
                    ).dueAt : nil
                    let rule: RecurrenceRule?
                    if frequency == .never {
                        rule = nil
                    } else if frequency == initial.repeatFrequency {
                        rule = initial.recurrenceRule
                    } else {
                        let parts = workspace.calendar.dateComponents([.day, .weekday, .month], from: due ?? date)
                        rule = RecurrenceRule(monthDay: parts.day, weekday: parts.weekday, month: parts.month)
                    }
                    onApply(QuickAddScheduleDraft(
                        dueAt: due,
                        hasTime: hasTime,
                        reminderAt: reminderEnabled ? reminderDate : nil,
                        repeatFrequency: frequency,
                        recurrenceRule: rule
                    ))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 320)
        .environment(\.calendar, workspace.calendar)
        .environment(\.timeZone, workspace.calendar.timeZone)
        .onExitCommand(perform: onCancel)
    }

    private func chooseDay(_ day: Date) {
        date = TaskDateDraft.movingDay(date, to: day, calendar: workspace.calendar)
    }
}
