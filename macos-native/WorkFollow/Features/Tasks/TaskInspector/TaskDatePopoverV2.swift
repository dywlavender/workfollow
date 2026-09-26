import SwiftUI

/// Redesigned date popover: 日期/时间段 tabs, quick-date icons, lunar month
/// grid, driven by TaskDateDraftModel. 时间/提醒 use inline sheets below their
/// rows (editable time field with half-hour option list; reminder presets with
/// 自定义 and 取消/确定), 重复 pushes a sub-page. A draft: nothing mutates the
/// task until 确定 (清除 applies the clear plan; Esc or clicking away discards).
/// The view only re-reads the current task and writes the model's plan through
/// the workspace.
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

    /// Floating sheet over the popover: 时间/提醒 open below their row,
    /// 重复 opens above its row covering the calendar (TickTick-style). The
    /// base layout never reflows, so the calendar does not move.
    enum InlineSheet {
        case time, reminder, `repeat`
    }

    /// Submenu of the repeat sheet (Flutter parity: 工作日›/节假日›).
    private enum RepeatGroup {
        case work, holiday
    }

    @StateObject private var model: TaskDateDraftModel
    @State private var inlineSheet: InlineSheet?
    @State private var customReminderDraft: Date
    @State private var stagedCustomReminder = false
    @State private var timeSheetBase: Date
    @State private var stagedCustomOffset = false
    @State private var customOffsetAmount = ""
    @State private var customOffsetUnit = 1
    @State private var repeatGroup: RepeatGroup?

    init(task: Task, workspace: TaskWorkspaceModel, deadline: Bool = false, initialPage: Page = .main,
         onClose: @escaping () -> Void) {
        taskID = task.id
        self.task = task
        self.workspace = workspace
        self.deadline = deadline
        self.initialPage = initialPage
        self.onClose = onClose
        let draftModel = TaskDateDraftModel(
            task: task, calendar: workspace.calendar, now: workspace.clock, deadline: deadline)
        _model = StateObject(wrappedValue: draftModel)
        _inlineSheet = State(initialValue: initialPage == .time ? .time
            : initialPage == .reminder ? .reminder
            : initialPage == .recurrence ? .`repeat` : nil)
        _customReminderDraft = State(initialValue: draftModel.reminderDate(for: .custom)
            ?? workspace.clock().addingTimeInterval(3600))
        _timeSheetBase = State(initialValue: draftModel.timeAnchor ?? workspace.clock())
    }

    var body: some View {
        mainPage
            .environment(\.calendar, workspace.calendar)
            .environment(\.timeZone, workspace.calendar.timeZone)
    }

    // MARK: Main page

    private var mainPage: some View {
        ZStack(alignment: .top) {
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
                .simultaneousGesture(TapGesture().onEnded { closeSheet() })
                .overlay(alignment: .top) {
                    // Pale accent discs for future occurrences, plus 班/休 badges
                    // and statutory festival names from ChineseWorkCalendar.
                    CalendarAnnotationOverlay(
                        calendar: workspace.calendar,
                        displayedMonth: model.displayedMonth,
                        occurrenceDays: model.occurrencePreviewDays(),
                        showBadges: true)
                        .allowsHitTesting(false)
                }
                if !deadline && model.tab == .period {
                    Text(rangeCaption)
                        .font(.system(size: 11))
                        .foregroundStyle(WFColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !deadline {
                    scheduleRows
                }
                footer
            }
            if inlineSheet == .time {
                timeSheet.offset(y: timeSheetY).zIndex(10)
            }
            if inlineSheet == .reminder {
                reminderSheet.offset(y: reminderSheetY).zIndex(10)
            }
        }
        .overlay(alignment: .bottom) {
            if inlineSheet == .`repeat` {
                repeatSheet.padding(.bottom, repeatSheetBottomPadding)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    // Sheet positions, derived from the fixed base layout so the calendar
    // never reflows when a sheet opens.
    private var rowsTopY: CGFloat {
        let base: CGFloat = 14 + 30 + 12 + 26 + 12 + 233 + 12
        return !deadline && model.tab == .period ? base + 16 + 14 : base
    }

    private var timeRowHeight: CGFloat { model.hasTime && model.timeAnchor != nil ? 28 : 30 }
    private var reminderRowHeight: CGFloat { model.hasReminderDraft ? 28 : 30 }

    private var timeSheetY: CGFloat { rowsTopY + timeRowHeight + 4 }
    private var reminderSheetY: CGFloat { rowsTopY + timeRowHeight + reminderRowHeight + 2 }
    private var repeatSheetBottomPadding: CGFloat { 28 + 12 + 30 + 4 }

    // MARK: Inline 时间/提醒 rows and sheets

    private var scheduleRows: some View {
        VStack(spacing: 0) {
            timeRowView
            reminderRowView
            menuRow("重复", value: repeatValue, icon: "repeat") { toggleSheet(.repeat) }
        }
    }

    @ViewBuilder
    private var timeRowView: some View {
        if model.hasTime, let anchor = model.timeAnchor {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 13))
                    .foregroundStyle(WFColors.accent)
                TextField("", text: chipHourBinding(of: anchor))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WFColors.text)
                    .multilineTextAlignment(.center)
                    .frame(width: 18)
                Text(":")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WFColors.text)
                TextField("", text: chipMinuteBinding(of: anchor))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WFColors.text)
                    .multilineTextAlignment(.center)
                    .frame(width: 18)
                Spacer()
                sheetClearButton { model.setHasTime(false); closeSheet() }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(WFColors.hover, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .onTapGesture { toggleSheet(.time) }
        } else {
            menuRow("时间", value: "无", icon: "clock") {
                model.setHasTime(true)
                openSheet(.time)
            }
        }
    }

    @ViewBuilder
    private var reminderRowView: some View {
        if model.hasReminderDraft {
            HStack(spacing: 6) {
                Image(systemName: "alarm")
                    .font(.system(size: 13))
                    .foregroundStyle(WFColors.accent)
                Text(reminderRowTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(WFColors.text)
                    .lineLimit(1)
                Spacer()
                sheetClearButton { model.clearReminder(); closeSheet() }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(WFColors.hover, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .onTapGesture { toggleSheet(.reminder) }
        } else {
            menuRow("提醒", value: "无", icon: "alarm") { openSheet(.reminder) }
        }
    }

    /// Row label: joined offset titles (multi-select) or the legacy chip.
    private var reminderRowTitle: String {
        let offsets = model.reminderOffsetsDraft
        if !offsets.isEmpty {
            return offsets.map(TaskDateDraftModel.offsetTitle).joined(separator: ", ")
        }
        return reminderChipTitle
    }

    private func sheetClearButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(WFColors.tertiaryText)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sheetCard: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(WFColors.content)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(WFColors.border))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    /// Half-hour steps starting at the drafted time (or now), like the reference.
    private var timeOptions: [Date] {
        var cursor = timeSheetBase
        var options: [Date] = []
        for _ in 0..<48 {
            options.append(cursor)
            cursor = workspace.calendar.date(byAdding: .minute, value: 30, to: cursor) ?? cursor
        }
        return options
    }

    private var timeSheet: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(timeOptions, id: \.self) { option in
                        sheetOptionRow(timeText(option), checked: isSelectedTime(option)) {
                            model.setTime(option)
                            closeSheet()
                        }
                    }
                }
            }
            .onAppear {
                if let selected = timeOptions.first(where: isSelectedTime) {
                    proxy.scrollTo(selected, anchor: .top)
                }
            }
        }
        .frame(height: 92)
        .frame(maxWidth: .infinity)
        .background(sheetCard)
    }

    private var reminderSheet: some View {
        Group {
            if stagedCustomReminder {
                VStack(spacing: 8) {
                    DatePicker("", selection: $customReminderDraft, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                    HStack(spacing: 8) {
                        sheetFooterButton("取消", filled: false) { stagedCustomReminder = false }
                        sheetFooterButton("确定", filled: true) {
                            model.chooseCustomReminder(customReminderDraft)
                            model.chooseReminderOption(.custom)
                            closeSheet()
                        }
                    }
                }
                .padding(10)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if !model.hasTime {
                            Text("全天任务将按当天 09:00 提醒")
                                .font(.system(size: 10))
                                .foregroundStyle(WFColors.tertiaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                        }
                        ForEach(TaskDateDraftModel.offsetChoices, id: \.self) { minutes in
                            sheetOptionRow(TaskDateDraftModel.offsetTitle(minutes),
                                           checked: model.reminderOffsets.contains(minutes)) {
                                model.toggleReminderOffset(minutes)
                            }
                        }
                        if stagedCustomOffset {
                            customOffsetRow
                        } else {
                            sheetOptionRow("自定义", checked: hasCustomOffsetChoice) {
                                customOffsetAmount = ""
                                stagedCustomOffset = true
                            }
                            sheetOptionRow("自定义时间…", checked: model.reminderOption == .custom) {
                                customReminderDraft = model.reminderDate(for: .custom)
                                    ?? model.dueAnchor ?? workspace.clock().addingTimeInterval(3600)
                                stagedCustomReminder = true
                            }
                        }
                    }
                }
            }
        }
        .frame(height: stagedCustomReminder ? 88 : 158)
        .frame(maxWidth: .infinity)
        .background(sheetCard)
    }

    /// 自定义提前量: amount + unit, mirroring the Flutter panel's custom row.
    private var customOffsetRow: some View {
        HStack(spacing: 6) {
            Text("提前").font(.system(size: 11)).foregroundStyle(WFColors.text)
            TextField("10", text: $customOffsetAmount)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .frame(width: 34)
                .padding(.vertical, 2)
                .background(WFColors.hover, in: RoundedRectangle(cornerRadius: 5))
            Picker("", selection: $customOffsetUnit) {
                Text("分钟").tag(1)
                Text("小时").tag(60)
                Text("天").tag(1440)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 62)
            sheetFooterButton("添加", filled: true) {
                if let amount = Int(customOffsetAmount), amount > 0 {
                    model.addCustomReminderOffset(minutes: amount * customOffsetUnit)
                }
                stagedCustomOffset = false
            }
            .frame(width: 44)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var hasCustomOffsetChoice: Bool {
        !model.reminderOffsets.isSubset(of: Set(TaskDateDraftModel.offsetChoices))
    }

    private func sheetOptionRow(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(checked ? WFColors.accent : WFColors.text)
                Spacer()
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WFColors.accent)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sheetFooterButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: filled ? .semibold : .medium))
                .foregroundStyle(filled ? Color.white : WFColors.text)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(filled ? WFColors.accent : WFColors.content, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(filled ? Color.clear : WFColors.border))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleSheet(_ sheet: InlineSheet) {
        if inlineSheet == sheet { closeSheet() } else { openSheet(sheet) }
    }

    private func closeSheet() {
        inlineSheet = nil
    }

    private func openSheet(_ sheet: InlineSheet) {
        if sheet == .reminder {
            stagedCustomReminder = false
            stagedCustomOffset = false
        }
        if sheet == .`repeat` {
            repeatGroup = nil
        }
        if sheet == .time {
            if let anchor = model.timeAnchor {
                timeSheetBase = anchor
            } else {
                // No start day drafted: list times from the coming half hour.
                let now = workspace.clock()
                let minute = workspace.calendar.component(.minute, from: now)
                let add = minute % 30 == 0 ? 0 : 30 - minute % 30
                timeSheetBase = workspace.calendar.date(byAdding: .minute, value: add, to: now) ?? now
            }
        }
        inlineSheet = sheet
    }

    private func isSelectedTime(_ option: Date) -> Bool {
        guard let anchor = model.timeAnchor else { return false }
        let calendar = workspace.calendar
        return calendar.component(.hour, from: anchor) == calendar.component(.hour, from: option)
            && calendar.component(.minute, from: anchor) == calendar.component(.minute, from: option)
    }

    private func timeText(_ date: Date) -> String {
        let components = workspace.calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private func chipHourBinding(of anchor: Date) -> Binding<String> {
        Binding(
            get: { String(format: "%02d", workspace.calendar.component(.hour, from: anchor)) },
            set: { text in
                guard let hour = Int(text), (0...23).contains(hour) else { return }
                model.setTime(workspace.calendar.date(
                    bySettingHour: hour, minute: workspace.calendar.component(.minute, from: anchor),
                    second: 0, of: anchor) ?? anchor)
            })
    }

    private func chipMinuteBinding(of anchor: Date) -> Binding<String> {
        Binding(
            get: { String(format: "%02d", workspace.calendar.component(.minute, from: anchor)) },
            set: { text in
                guard let minute = Int(text), (0...59).contains(minute) else { return }
                model.setTime(workspace.calendar.date(
                    bySettingHour: workspace.calendar.component(.hour, from: anchor), minute: minute,
                    second: 0, of: anchor) ?? anchor)
            })
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
            closeSheet()
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
            shortcutButton("moon.stars", "今晚") { model.selectTonight() }
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
            closeSheet()
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

    private var repeatSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("重复规则").font(WFType.section)
                Spacer()
                sheetClearButton { closeSheet() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if let group = repeatGroup {
                        optionRow("‹ 返回", isSelected: false) { repeatGroup = nil }
                        ForEach(group == .work ? [TaskRepeat.weekdays, .workdays] : [TaskRepeat.weekends, .holidays], id: \.self) { value in
                            optionRow(value.title, isSelected: model.frequency == value) {
                                model.chooseFrequency(value)
                            }
                        }
                        Text(ChineseWorkCalendar.hasYear(recurrenceAnchorYear)
                             ? "法定选项包含周末与调休安排。"
                             : "该年份尚无调休数据，法定选项暂按周一至周五／周末计算。")
                            .font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                            .padding(.vertical, 4)
                    } else {
                        ForEach([TaskRepeat.never, .daily, .weekly, .monthly, .yearly], id: \.self) { value in
                            optionRow(value.title, isSelected: model.frequency == value) {
                                model.chooseFrequency(value)
                            }
                        }
                        Divider().padding(.vertical, 6)
                        optionRow("工作日", isSelected: [TaskRepeat.weekdays, .workdays].contains(model.frequency), arrow: true) {
                            repeatGroup = .work
                        }
                        optionRow("节假日", isSelected: [TaskRepeat.weekends, .holidays].contains(model.frequency), arrow: true) {
                            repeatGroup = .holiday
                        }
                    }
                    if model.frequency != .never {
                        Divider().padding(.vertical, 6)
                        recurrenceRuleFields
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .background(sheetCard)
    }

    /// Year of the drafted start day: decides the 法定选项 disclosure copy.
    private var recurrenceAnchorYear: Int {
        let anchor = model.tab == .period ? (model.periodStart ?? model.selectedDate) : model.selectedDate
        return workspace.calendar.component(.year, from: anchor)
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
        if model.frequency == .weekdays || model.frequency == .weekends
            || model.frequency == .workdays || model.frequency == .holidays {
            Text("内置 2025–2026 年中国节假日；其他年份按普通周一至五／周末计算。")
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

    private func optionRow(_ title: String, isSelected: Bool, arrow: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(WFType.body).foregroundStyle(WFColors.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WFColors.accent)
                } else if arrow {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WFColors.tertiaryText)
                }
            }
            .padding(.horizontal, 2)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Row values

    /// Chip label for a set reminder: preset title or the absolute time.
    private var reminderChipTitle: String {
        switch model.reminderOption {
        case .none: return "无"
        case .custom:
            return TaskDateLabel.text(model.customReminder, hasTime: true,
                                      now: workspace.clock(), calendar: workspace.calendar)
        default:
            return TaskDateDraftModel.presetOffsets
                .first { $0.option == model.reminderOption }?.title ?? "准时"
        }
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
        persistReminderOffsets(plan.reminderOffsets, on: current)
        onClose()
    }

    private func clear() {
        guard let current = workspace.task(for: taskID) else { onClose(); return }
        let plan = model.clearPlan(for: current)
        workspace.saveTiming(taskID, schedule: plan.schedule, reminder: plan.reminder,
                             frequency: plan.frequency, recurrenceRule: plan.recurrenceRule)
        persistReminderOffsets(plan.reminderOffsets, on: current)
        onClose()
    }

    /// The workspace model has no direct offsets passthrough yet; the public
    /// bulk channel carries the write (TaskActions.batch handles
    /// .reminderOffsets). No-op when the stored offsets already match.
    private func persistReminderOffsets(_ offsets: [Int], on current: Task) {
        guard offsets != (current.reminderOffsets ?? []) else { return }
        workspace.bulkSelection = [taskID]
        workspace.applyBulk(.reminderOffsets(offsets))
    }
}

/// Pixel-aligned marks over LunarMonthGridView: the overlay replicates the
/// grid's exact VStack/header/weekday structure with empty placeholders, so
/// occurrence discs, 班/休 badges and statutory festival names land on the
/// right cells without touching the grid itself.
private struct CalendarAnnotationOverlay: View {
    let calendar: Calendar
    let displayedMonth: Date
    let occurrenceDays: Set<Date>
    let showBadges: Bool

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    /// The reference grid always lays out weeks from Sunday.
    private var layoutCalendar: Calendar {
        var value = calendar
        value.firstWeekday = 1
        return value
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 14) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.clear)
                Spacer()
                ForEach(0..<3, id: \.self) { _ in Color.clear.frame(width: 18, height: 18) }
            }
            LazyVGrid(columns: Self.columns, spacing: 0) {
                ForEach(0..<7, id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, minHeight: 15)
                }
            }
            LazyVGrid(columns: Self.columns, spacing: 2) {
                ForEach(MonthGridCalculator.cells(displayedMonth: displayedMonth, calendar: layoutCalendar)) { cell in
                    markCell(cell.date)
                }
            }
        }
    }

    private var title: String {
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        return "\(components.year ?? 0)年\(components.month ?? 0)月"
    }

    private func markCell(_ date: Date) -> some View {
        let day = calendar.startOfDay(for: date)
        let override = showBadges ? ChineseWorkCalendar.override(for: day, calendar: calendar) : nil
        // The grid already labels lunar/solar festivals; only fill the gaps
        // (e.g. 清明节) from the statutory table to avoid double labels.
        let festival = LunarCalendarService.festivalLabel(for: day, calendar: calendar) == nil
            ? ChineseWorkCalendar.festivalName(date: day, calendar: calendar) : nil
        return ZStack {
            if occurrenceDays.contains(day) {
                Circle().fill(WFColors.accent.opacity(0.30))
                    .frame(width: 26, height: 26)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .overlay(alignment: .bottom) {
            if let festival {
                Text(festival)
                    .font(.system(size: 7))
                    .foregroundStyle(WFColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let override {
                Text(override ? "班" : "休")
                    .font(.system(size: 6, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 10, height: 10)
                    .background(Circle().fill(override ? Color(nsColor: .systemOrange)
                                                       : Color(nsColor: .systemGreen)))
                    .offset(x: 3, y: -1)
            }
        }
    }
}
