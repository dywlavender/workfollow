import SwiftUI

/// Redesigned date popover: 日期/时间段 tabs, quick-date icons, lunar month
/// grid and 时间/提醒/重复 sub-pages driven by TaskDateDraftModel. A draft:
/// nothing mutates the task until 确定 (清除 applies the clear plan; Esc or
/// clicking away discards). The view only re-reads the current task and writes
/// the model's plan through the workspace.
struct TaskDatePopoverV2: View {
    enum Page {
        case main, time, reminder, recurrence
    }

    let taskID: UUID
    private let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    var deadline = false
    var initialPage: Page = .main
    let onClose: () -> Void

    @StateObject private var model: TaskDateDraftModel
    @State private var page: Page

    init(task: Task, workspace: TaskWorkspaceModel, deadline: Bool = false, initialPage: Page = .main,
         onClose: @escaping () -> Void) {
        taskID = task.id
        self.task = task
        self.workspace = workspace
        self.deadline = deadline
        self.initialPage = initialPage
        self.onClose = onClose
        _model = StateObject(wrappedValue: TaskDateDraftModel(
            task: task, calendar: workspace.calendar, now: workspace.clock, deadline: deadline))
        _page = State(initialValue: initialPage)
    }

    private let pageTransition = AnyTransition.move(edge: .trailing).combined(with: .opacity)

    var body: some View {
        ZStack {
            switch page {
            case .main: mainPage.transition(pageTransition)
            case .time: timePage.transition(pageTransition)
            case .reminder: reminderPage.transition(pageTransition)
            case .recurrence: recurrencePage.transition(pageTransition)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: page)
        .environment(\.calendar, workspace.calendar)
        .environment(\.timeZone, workspace.calendar.timeZone)
    }

    // MARK: Main page

    private var mainPage: some View {
        VStack(spacing: 12) {
            if !deadline {
                segmented
            }
            shortcutRow
            LunarMonthGridView(
                calendar: workspace.calendar,
                displayedMonth: $model.displayedMonth,
                today: workspace.dateFromToday(0),
                selection: deadline || model.tab == .date ? model.selectedDate : nil,
                range: !deadline && model.tab == .period ? model.periodRange : nil,
                onSelect: model.select
            )
            if !deadline {
                if model.tab == .period {
                    Text(rangeCaption)
                        .font(.system(size: 11))
                        .foregroundStyle(WFColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(spacing: 0) {
                    menuRow("时间", value: timeValue, icon: "clock") { page = .time }
                    menuRow("提醒", value: reminderValue, icon: "alarm") { page = .reminder }
                    menuRow("重复", value: repeatValue, icon: "repeat") { page = .recurrence }
                }
            }
            footer
        }
        .padding(14)
        .frame(width: 260)
    }

    /// Pill segmented control replicating the reference design: grey track,
    /// floating white capsule on the selected tab.
    private var segmented: some View {
        HStack(spacing: 3) {
            segment("日期", .date)
            segment("时间段", .period)
        }
        .padding(3)
        .background(WFColors.hover, in: RoundedRectangle(cornerRadius: 9))
    }

    private func segment(_ title: String, _ value: TaskDateDraftModel.Tab) -> some View {
        let selected = model.tab == value
        return Button {
            model.setTab(value)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? WFColors.text : WFColors.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(WFColors.content)
                            .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var rangeCaption: String {
        guard let range = model.periodRange else { return "在日历上点选开始与结束日期" }
        if range.lowerBound == range.upperBound {
            return "开始：\(dayText(range.lowerBound))，继续点选结束日期"
        }
        return "\(dayText(range.lowerBound)) – \(dayText(range.upperBound))"
    }

    private func dayText(_ date: Date) -> String {
        let components = workspace.calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)月\(components.day ?? 0)日"
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                clear()
            } label: {
                Text("清除")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WFColors.text)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(WFColors.border))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                save()
            } label: {
                Text("确定")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background(WFColors.accent, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var shortcutRow: some View {
        HStack(spacing: 0) {
            shortcutButton("sun.max", "今天") { model.quick(0) }
            shortcutButton("sunrise", "明天") { model.quick(1) }
            shortcutButton(badge: "+7", "下周") { model.quick(7) }
            shortcutButton("moon", "周末") { model.selectWeekend() }
        }
    }

    private func shortcutButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        shortcutLabel(help, action: action) {
            Image(systemName: symbol).font(.system(size: 16))
        }
    }

    private func shortcutButton(badge: String, _ help: String, action: @escaping () -> Void) -> some View {
        shortcutLabel(help, action: action) {
            Image(systemName: "calendar").font(.system(size: 16))
                .overlay(alignment: .topTrailing) {
                    Text(badge).font(.system(size: 7, weight: .bold)).offset(x: 4, y: -2)
                }
        }
    }

    private func shortcutLabel(_ help: String, action: @escaping () -> Void, @ViewBuilder icon: () -> some View) -> some View {
        Button {
            action()
        } label: {
            icon()
                .foregroundStyle(WFColors.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func menuRow(_ title: String, value: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(WFColors.secondaryText)
                    .frame(width: 18)
                Text(title).font(WFType.body).foregroundStyle(WFColors.text)
                Spacer()
                Text(value).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WFColors.tertiaryText)
            }
            .padding(.horizontal, 2)
            .frame(minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Sub pages

    private func subPage(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    page = .main
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WFColors.secondaryText)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("返回")
                Text(title).font(WFType.section)
                Spacer()
                Button("完成") { page = .main }.buttonStyle(.bordered).controlSize(.small)
            }
            content()
        }
        .padding(14)
        .frame(width: 260)
    }

    private var timePage: some View {
        subPage("时间") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("指定时间", isOn: Binding(get: { model.hasTime }, set: { model.setHasTime($0) }))
                if model.hasTime {
                    HStack(spacing: 8) {
                        timePreset(hour: 9, minute: 0, title: "早上 9:00")
                        timePreset(hour: 12, minute: 0, title: "中午 12:00")
                        timePreset(hour: 18, minute: 0, title: "下午 6:00")
                        timePreset(hour: 21, minute: 0, title: "晚上 9:00")
                    }
                    DatePicker("自定义时间", selection: Binding(
                        get: { model.timeAnchor ?? workspace.dateFromToday(0) },
                        set: { model.setTime($0) }), displayedComponents: .hourAndMinute)
                }
            }
        }
    }

    private func timePreset(hour: Int, minute: Int, title: String) -> some View {
        let anchor = model.timeAnchor
        let selected = anchor != nil
            && workspace.calendar.component(.hour, from: anchor!) == hour
            && workspace.calendar.component(.minute, from: anchor!) == minute
        let base = anchor ?? workspace.dateFromToday(0)
        let target = workspace.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        return Button(title) { model.setTime(target) }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(selected ? WFColors.accent : WFColors.text)
            .padding(.horizontal, 8)
            .frame(minHeight: 22)
            .background(
                selected ? WFColors.selection : WFColors.hover,
                in: RoundedRectangle(cornerRadius: 7)
            )
    }

    private var reminderPage: some View {
        subPage("提醒") {
            VStack(alignment: .leading, spacing: 2) {
                reminderRow(.none, "不提醒")
                if model.dueAnchor != nil {
                    ForEach(TaskDateDraftModel.presetOffsets, id: \.option) { preset in
                        reminderRow(preset.option, preset.title)
                    }
                }
                reminderRow(.custom, "自定义时间")
                if model.reminderOption == .custom {
                    DatePicker("提醒时间", selection: Binding(
                        get: { model.customReminder }, set: { model.chooseCustomReminder($0) }))
                        .labelsHidden().padding(.top, 6)
                }
                if model.dueAnchor == nil {
                    Text("先设置开始日期后，可按日期提醒。")
                        .font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                        .padding(.top, 6)
                }
            }
        }
    }

    private func reminderRow(_ option: TaskDateDraftModel.ReminderOption, _ title: String) -> some View {
        optionRow(title, isSelected: model.reminderOption == option) {
            model.chooseReminderOption(option)
        }
        .disabled(model.dueAnchor == nil && option != .none && option != .custom)
    }

    private var recurrencePage: some View {
        subPage("重复") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(TaskRepeat.allCases, id: \.self) { value in
                    optionRow(value.title, isSelected: model.frequency == value) {
                        model.chooseFrequency(value)
                    }
                }
                if model.frequency != .never {
                    Divider().padding(.vertical, 8)
                    recurrenceRuleFields
                }
            }
        }
    }

    @ViewBuilder
    private var recurrenceRuleFields: some View {
        if frequencyUsesInterval {
            Stepper("每 \(model.interval) \(intervalUnit)", value: Binding(
                get: { model.interval }, set: { model.chooseInterval($0) }), in: 1...365)
                .padding(.vertical, 4)
        }
        if model.frequency == .weekly {
            HStack(spacing: 6) {
                ForEach(Array(orderedWeekdays.enumerated()), id: \.offset) { _, weekday in
                    weekdayChip(weekday)
                }
            }
        }
        if model.frequency == .monthly || model.frequency == .yearly {
            Stepper("日期：\(model.monthDay) 日", value: Binding(
                get: { model.monthDay }, set: { model.chooseMonthDay($0) }), in: 1...31)
                .padding(.vertical, 4)
        }
        if model.frequency == .yearly {
            Stepper("月份：\(model.month) 月", value: Binding(
                get: { model.month }, set: { model.chooseMonth($0) }), in: 1...12)
                .padding(.vertical, 4)
        }
        if model.frequency == .workdays || model.frequency == .holidays {
            Text("内置 2025–2026 年中国节假日；其他年份按普通周末计算。")
                .font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                .padding(.vertical, 4)
        }
        Text("结束").font(WFType.supporting).foregroundStyle(WFColors.secondaryText).padding(.top, 4)
        optionRow("永不", isSelected: model.ending == .never) { model.chooseEnding(.never) }
        optionRow("指定日期（含当天）", isSelected: model.ending == .untilDate) { model.chooseEnding(.untilDate) }
        if model.ending == .untilDate {
            DatePicker("结束日期", selection: Binding(
                get: { model.repeatEndDate }, set: { model.chooseRepeatEndDate($0) }),
                displayedComponents: .date).labelsHidden().padding(.top, 4)
        }
        optionRow("指定次数", isSelected: model.ending == .count) { model.chooseEnding(.count) }
        if model.ending == .count {
            Stepper("剩余 \(model.repeatCount) 次（含当前任务）", value: Binding(
                get: { model.repeatCount }, set: { model.chooseRepeatCount($0) }), in: 1...999)
                .padding(.vertical, 4)
        }
        Text("按安排日期推算；月底不足时取最后一天。")
            .font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
            .padding(.vertical, 4)
    }

    private var frequencyUsesInterval: Bool {
        switch model.frequency {
        case .daily, .weekly, .monthly, .yearly: true
        default: false
        }
    }

    private var intervalUnit: String {
        switch model.frequency {
        case .daily: "天"
        case .weekly: "周"
        case .monthly: "月"
        default: "年"
        }
    }

    private var orderedWeekdays: [Int] {
        let days = Array(1...7)
        let start = workspace.calendar.firstWeekday - 1
        return Array(days[start...] + days[..<start])
    }

    private func weekdayChip(_ weekday: Int) -> some View {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        return Button {
            model.chooseWeekday(weekday)
        } label: {
            Text(symbols[weekday - 1])
                .font(WFType.supporting)
                .foregroundStyle(model.weekday == weekday ? Color.white : WFColors.secondaryText)
                .frame(width: 20, height: 20)
                .background(Circle().fill(model.weekday == weekday ? WFColors.accent : WFColors.hover))
        }
        .buttonStyle(.plain)
    }

    private func optionRow(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(WFType.body).foregroundStyle(WFColors.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WFColors.accent)
                }
            }
            .padding(.horizontal, 2)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Row values

    private var timeValue: String {
        guard model.hasTime else { return "无" }
        guard let anchor = model.timeAnchor else { return "无" }
        let components = workspace.calendar.dateComponents([.hour, .minute], from: anchor)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private var reminderValue: String {
        guard let reminder = model.reminderValue else { return "无" }
        return TaskDateLabel.text(reminder, hasTime: true, now: workspace.clock(), calendar: workspace.calendar)
    }

    private var repeatValue: String {
        (workspace.task(for: taskID)?.recurrence ?? task.recurrence).title
    }

    // MARK: Commit

    private func save() {
        // Read current task here, so an open popover cannot overwrite other edits.
        guard let current = workspace.task(for: taskID) else { onClose(); return }
        let plan = model.commitPlan(for: current)
        workspace.saveTiming(taskID, schedule: plan.schedule, reminder: plan.reminder,
                             frequency: plan.frequency, recurrenceRule: plan.recurrenceRule)
        onClose()
    }

    private func clear() {
        guard let current = workspace.task(for: taskID) else { onClose(); return }
        let plan = model.clearPlan(for: current)
        workspace.saveTiming(taskID, schedule: plan.schedule, reminder: plan.reminder,
                             frequency: plan.frequency, recurrenceRule: plan.recurrenceRule)
        onClose()
    }
}
