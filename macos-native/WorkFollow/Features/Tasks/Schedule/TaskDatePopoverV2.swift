import SwiftUI
import AppKit

/// TickTick 对齐的固定主面板 + 锚定子卡片日程编辑器。
/// - 主面板 = tabs + 快捷日 + 日历 + 属性行 + 清除/确定；
/// - 属性编辑属于独立子卡片：主面板所有行与Footer保持原位，
///   子卡片覆盖下方区域，并可越过主面板边界。
/// - 时间 = 头部可编辑 HH:mm + 48 个半小时选项（滚到当前值）；提醒 = “准时/提前…”多选 +
///   自定义提前量 + 取消/确定；重复 = 规则列表 + 工作日/节假日二级页；重复结束 =
///   永不结束/按日期结束/按次数结束。
/// A draft: nothing mutates the task until 确定 (清除 applies the clear plan; Esc or clicking away discards).
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
    /// 草稿宿主（日历/四象限的新建卡）：任务还没被创建，确定与清除只把计划交回
    /// 调用方，不写工作区，也不动批量选择。
    private let draftCommit: ((TaskDateDraftModel.CommitPlan) -> Void)?
    private let availableHeight: CGFloat
    private var panelHeight: CGFloat {
        SchedulePopoverLayoutV2.height(availableHeight: availableHeight,
            repeating: !deadline && model.frequency != .never,
            period: !deadline && model.tab == .period)
    }

    typealias InlineSheet = ScheduleExpandedSection

    /// 重复二级页（Flutter: 工作日›/节假日›）。
    private typealias RepeatGroup = SchedulePanelPresentationState.RecurrencePage

    /// 重复结束二级页（Flutter: 按日期结束/按次数结束）。
    /// 定义只有一处：导航 reducer 的子页变体。
    private typealias RepeatEndEdit = SchedulePanelPresentationState.SubPage.Edit

    /// 主面板仅随属性行数量增高；打开子卡片不改变尺寸。
    @StateObject private var model: TaskDateDraftModel
    @State private var presentation = SchedulePanelPresentationState()
    private var inlineSheet: InlineSheet? {
        get { presentation.expandedProperty }
        nonmutating set { presentation.expandedProperty = newValue }
    }
    private var repeatGroup: RepeatGroup? {
        get { presentation.recurrencePage }
        nonmutating set { presentation.recurrencePage = newValue }
    }
    /// 鼠标当前悬浮的属性行（已设值的行尾把 › 换成 ×）。
    /// 时间行内编辑的文本（展开时可改，提交后回写草稿）。
    @State private var timeFieldText = ""
    /// 结束时间行内编辑的文本（同上；分钟精度靠它，半小时列表只是快捷选择）。
    @State private var endTimeFieldText = ""
    /// 点过「确定」且区间非法时才显示错误（Flutter 的 `error` 同样是提交时才出现；
    /// 区间改回合法后它自动消失，因为文案由草稿实时算）。
    @State private var showRangeError = false
    @State private var reminderDraft = ScheduleReminderDraft(offsets: [])
    @State private var reminderInputError = false
    @State private var reminderCustomOpen = false
    @State private var customOffsetAmount = ""
    @State private var customOffsetUnit = 1
    @State private var repeatCountText = ""
    @State private var repeatEndDraftDate = Date()
    @State private var repeatEndDisplayedMonth = Date()

    init(task: Task, workspace: TaskWorkspaceModel, deadline: Bool = false, initialPage: Page = .main,
         draftCommit: ((TaskDateDraftModel.CommitPlan) -> Void)? = nil,
         onClose: @escaping () -> Void) {
        taskID = task.id
        self.task = task
        self.workspace = workspace
        self.deadline = deadline
        self.initialPage = initialPage
        self.draftCommit = draftCommit
        availableHeight = NSScreen.main?.visibleFrame.height ?? 900
        self.onClose = onClose
        let draftModel = TaskDateDraftModel(
            task: task, calendar: workspace.calendar, now: workspace.clock, deadline: deadline)
        _model = StateObject(wrappedValue: draftModel)
        _presentation = State(initialValue: SchedulePanelPresentationState(expandedProperty: initialPage == .time ? .time
            : initialPage == .reminder ? .reminder
            : initialPage == .recurrence ? .`repeat` : nil))
        _reminderDraft = State(initialValue: ScheduleReminderDraft(offsets: draftModel.reminderOffsets))
        _timeFieldText = State(initialValue: draftModel.hasTime
            ? Self.clockText(draftModel.startTimeAnchor ?? workspace.clock(), calendar: workspace.calendar)
            : Self.defaultClockText)
        _endTimeFieldText = State(initialValue: draftModel.endTimeAnchor
            .map { Self.clockText($0, calendar: workspace.calendar) } ?? Self.defaultClockText)
        _repeatCountText = State(initialValue: String(draftModel.repeatCount))
        _repeatEndDraftDate = State(initialValue: draftModel.repeatEndDate)
        _repeatEndDisplayedMonth = State(initialValue: draftModel.repeatEndDate)
    }

    var body: some View {
        mainPage
            .environment(\.calendar, workspace.calendar)
            .environment(\.timeZone, workspace.calendar.timeZone)
    }

    // MARK: Main page

    private var mainPage: some View {
        SchedulePopoverContainer(height: panelHeight) {
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
                    onSelect: { day in
                        model.select(day)
                        closeSheet()
                    }
                )
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
            }
        } propertyContent: {
            VStack(spacing: 12) {
                if !deadline && model.tab == .period {
                    Text(rangeCaption)
                        .font(.system(size: 11))
                        .foregroundStyle(WFColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !deadline {
                    propertyRows
                }
                if showRangeError, let message = model.rangeError {
                    Text(message)
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } footer: {
            footer
        }
        .background {
            ScheduleEscapeRouter {
                // 一级返回交给导航 reducer：子页 → 二级页 → 属性子卡 → 宿主关面板，
                // 视图不再自己判断"先关哪一层"。
                if !presentation.back() { onClose() }
            }
        }
        // macOS 27：`.popover` 不传 arrowEdge（默认 nil）就不画三角箭头，
        // 系统自带圆角卡片样式（对齐滴答/参考图），无需任何背景补丁。
        .onChange(of: model.startTimeAnchor) { _, _ in syncTimeField() }
        .onChange(of: model.endTimeAnchor) { _, _ in syncTimeField() }
        .onChange(of: model.hasTime) { _, _ in syncTimeField() }
        .onAppear {
            if inlineSheet == .time {
                SchedulePanelInteraction.open(.time, state: &presentation, model: model,
                                              now: workspace.clock(), calendar: workspace.calendar)
                syncTimeField()
            }
        }
        .onExitCommand {
            if inlineSheet != nil { closeSheet() } else { onClose() }
        }
        .onDisappear { closeSheet() }
    }

    // MARK: 属性行 + 子面板（Flutter `_property` / `showScheduleOptions`）

    private var propertyRows: some View {
        VStack(spacing: 0) {
            propertyRow(.time, icon: "clock", title: "时间", active: model.hasTime,
                     editor: AnyView(timeRowEditor),
                     canClear: model.hasTime) { timePanelBody }
            // 结束时间：只在时间段页签出现（Flutter `if (range) _property('schedule-end-time' …)`），
            // 紧跟在开始时间之后、提醒之前。
            if visiblePropertyRows.contains(.endTime) {
                propertyRow(.endTime, icon: "clock", title: "结束时间", active: model.hasEndTime,
                         editor: AnyView(endTimeRowEditor),
                         canClear: model.hasEndTime) { endTimePanelBody }
            }
            if visiblePropertyRows.contains(.reminder) {
                propertyRow(.reminder, icon: "alarm", title: reminderRowLabel,
                            active: model.hasReminderDraft,
                            canClear: model.hasReminderDraft) {
                    reminderPanelBody
                }
            }
            if visiblePropertyRows.contains(.repeat) {
                propertyRow(.repeat, icon: "repeat", title: repeatRowLabel,
                            active: model.frequency != .never,
                            canClear: model.frequency != .never) { repeatPanelBody }
            }
            if visiblePropertyRows.contains(.repeatEnd) {
                propertyRow(.repeatEnd, icon: "repeat", title: endRowLabel, active: model.ending != .never,
                            canClear: model.ending != .never) {
                    repeatEndPanelBody
                }
            }
        }
    }

    private var visiblePropertyRows: [InlineSheet] {
        InlineSheet.visibleRows(expanded: inlineSheet, period: model.tab == .period,
                               repeating: model.frequency != .never)
    }

    @ViewBuilder
    private func propertyRow<Body: View>(_ sheet: InlineSheet, icon: String, title: String,
                                       active: Bool, editor: AnyView? = nil,
                                       canClear: Bool = false,
                                       @ViewBuilder body: @escaping () -> Body) -> some View {
        sheetRow(sheet, icon: icon, title: title, active: active, editor: editor, canClear: canClear)
            .background {
                AnchoredPropertyPanel(isPresented: Binding(
                    get: { inlineSheet == sheet },
                    set: { if !$0, inlineSheet == sheet { closeSheet() } }),
                    width: ScheduleMetrics.optionPanelWidth,
                    horizontalOutset: ScheduleMetrics.childHorizontalOutset,
                    prefersAbove: sheet == .repeatEnd && presentation.repeatEndEdit == .date) {
                        body().scheduleRenderAnchor(.expandedContent(sheet))
                    }
            }
    }

    /// 当前行一直保留；子卡片开启时灰底，主面板后续行不移除。
    private func sheetRow(_ sheet: InlineSheet, icon: String, title: String,
                                      active: Bool,
                                      editor: AnyView? = nil,
                                      canClear: Bool = false) -> some View {
        let open = inlineSheet == sheet
        let value = active ? (editor != nil ? (sheet == .endTime ? "结束 \(endTimeFieldText)" : timeFieldText) : title) : nil
        return SchedulePropertyRow(
            property: sheet, icon: icon,
            presentation: SchedulePropertyPresentation(title: sheet == .repeatEnd ? title : propertyName(sheet), value: value,
                isActive: active, isExpanded: open, isHovered: presentation.hoveredProperty == sheet,
                canClear: canClear),
            editor: editor,
            onOpen: { toggleSheet(sheet) },
            onClear: {
                SchedulePanelInteraction.clear(sheet, state: &presentation, model: model)
                syncTimeField()
            },
            onHover: { presentation.hover(sheet, inside: $0) })
    }

    /// 时间行的行内编辑（滴答：行即 HH:mm 输入框，列表给半点粒度、输入框给分钟）。
    private var timeRowEditor: AnyView {
        AnyView(clockField(text: $timeFieldText, submit: submitTimeField))
    }

    /// 结束时间行的行内编辑：`结束` 前缀 + 同一个 HH:mm 输入框。
    /// Flutter 该行文案是 `结束 17:45`（源码 `'结束 ${scheduleClock(endTime)}'`）；
    /// 原生把值做成可编辑输入框，前缀保留——否则两行都只剩一个时刻、无法区分。
    private var endTimeRowEditor: AnyView {
        AnyView(
            HStack(spacing: 4) {
                Text("结束")
                    .font(WFType.body)
                    .foregroundStyle(WFColors.accent)
                clockField(text: $endTimeFieldText, submit: submitEndTimeField)
            }
        )
    }

    /// 两行共用的 HH:mm 输入框（固定宽度，行内不跳动）。
    private func clockField(text: Binding<String>, submit: @escaping () -> Void) -> some View {
        TextField(Self.defaultClockText, text: text)
            .textFieldStyle(.plain)
            .font(WFType.body)
            .foregroundStyle(WFColors.accent)
            .frame(width: 52, alignment: .leading)
            .onSubmit(submit)
    }

    /// 时间值在别处变化（列表点选、日历改天、清除）后同步两行的行内文本。
    private func syncTimeField() {
        timeFieldText = model.hasTime
            ? Self.clockText(model.startTimeAnchor ?? workspace.clock(), calendar: workspace.calendar)
            : Self.defaultClockText
        endTimeFieldText = model.endTimeAnchor
            .map { Self.clockText($0, calendar: workspace.calendar) } ?? Self.defaultClockText
    }

    /// 未设置时间时的默认显示（滴答：全天任务按 09:00 起算）。
    private static var defaultClockText: String {
        String(format: "%02d:00", ScheduleSemantics.allDayAnchorHour)
    }

    private func submitTimeField() {
        guard let value = parsedClock(timeFieldText, on: model.startTimeAnchor) else {
            syncTimeField()
            return
        }
        model.setHasTime(true)
        model.setStartTime(value)
    }

    private func submitEndTimeField() {
        guard let value = parsedClock(endTimeFieldText, on: model.endTimeAnchor) else {
            syncTimeField()
            return
        }
        model.setHasTime(true)
        model.setEndTime(value)
    }

    /// 解析 `HH:mm` 并落到锚点那一天；非法输入返回 nil（调用方回滚文本）。
    private func parsedClock(_ text: String, on anchor: Date?) -> Date? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let calendar = workspace.calendar
        let day = calendar.startOfDay(for: anchor ?? workspace.clock())
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    private func propertyName(_ sheet: InlineSheet) -> String {
        switch sheet {
        case .time: "时间"
        case .endTime: "结束时间"
        case .reminder: "提醒"
        case .repeat: "重复"
        case .repeatEnd: "重复结束"
        }
    }

    // MARK: 时间子面板（Flutter ScheduleTimeOptions）

    /// 时间展开内容 = 半小时步进列表（当前值强调色 + ✓），点选只写日程草稿；
    /// 精确到分钟与清除都在行内（`timeRowEditor` / 行尾 ×）。
    private var timePanelBody: some View {
        halfHourList(day: startTimeDay,
                     selected: model.hasTime ? model.startTimeAnchor : nil,
                     fallback: fallbackClock(for: nil)) { option in
            model.setHasTime(true)
            model.setStartTime(option)
            closeSheet()
        }
    }

    /// 结束时间展开内容：同一个半小时列表组件，只换锚定日与回写目标。
    private var endTimePanelBody: some View {
        halfHourList(day: endTimeDay,
                     selected: model.hasEndTime ? model.endTimeAnchor : nil,
                     fallback: fallbackClock(for: model.startTimeAnchor)) { option in
            model.setHasTime(true)
            model.setEndTime(option)
            closeSheet()
        }
    }

    /// 半小时步进列表（时间 / 结束时间共用一套，不复制第二份）。
    /// 列表只是**快捷选择**：精确分钟由行内输入框提供（Flutter 同款分工，
    /// 09:17 → 11:43 这类值必须能存下来）。
    private func halfHourList(day: Date, selected: Date?, fallback: (hour: Int, minute: Int),
                              onPick: @escaping (Date) -> Void) -> some View {
        let calendar = workspace.calendar
        let options = (0..<48).compactMap { calendar.date(byAdding: .minute, value: $0 * 30, to: day) }
        func matches(_ option: Date, _ value: Date) -> Bool {
            Self.isClock(option, hour: calendar.component(.hour, from: value),
                         minute: calendar.component(.minute, from: value), calendar: calendar)
        }
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(options, id: \.self) { option in
                        optionsRow(Self.clockText(option, calendar: calendar),
                                   checked: selected.map { matches(option, $0) } ?? false) {
                            onPick(option)
                        }
                        .id(option)
                    }
                }
            }
            .frame(height: ScheduleMetrics.timeOptionsHeight)
            .onAppear {
                let target = options.first { option in
                    guard let selected else { return false }
                    return matches(option, selected)
                } ?? options.first { Self.isClock($0, hour: fallback.hour,
                                                   minute: fallback.minute, calendar: calendar) }
                if let target { proxy.scrollTo(target, anchor: .top) }
            }
        }
    }

    /// 时间列表的锚定日：草稿那一天。
    private var startTimeDay: Date {
        workspace.calendar.startOfDay(for: model.startTimeAnchor ?? workspace.clock())
    }

    /// 结束时间列表的锚定日：结束那天（还没有结束时落在开始那天）。
    private var endTimeDay: Date {
        workspace.calendar.startOfDay(for: model.endTimeAnchor ?? workspace.clock())
    }

    /// 列表打开时滚到的兜底时刻。开始时间无值 → 09:00（滴答全天起点）；
    /// 结束时间无值 → 开始 +1 小时（Flutter `until = initial + 1h` 的同一默认）。
    private func fallbackClock(for start: Date?) -> (hour: Int, minute: Int) {
        guard let start else { return (ScheduleSemantics.allDayAnchorHour, 0) }
        let plus = start.addingTimeInterval(3600)
        return (workspace.calendar.component(.hour, from: plus),
                workspace.calendar.component(.minute, from: plus))
    }

    // MARK: 提醒子面板（Flutter ScheduleReminderOptions）

    private var reminderPanelBody: some View {
        VStack(spacing: 0) {
            ForEach(reminderOptionValues, id: \.self) { minutes in
                optionsRow(reminderOptionLabel(minutes),
                           checked: reminderDraft.offsets.contains(minutes)) {
                    reminderDraft.toggle(minutes)
                }
            }
            Divider()
            optionsRow("自定义") {
                // 子页开合走导航 reducer：Esc、×、再次点击用的是同一份判据。
                if presentation.shows(.reminderCustom) { presentation.close(.reminderCustom) }
                else { presentation.open(.reminderCustom) }
            }
            if presentation.shows(.reminderCustom) { customOffsetRow }
            if reminderInputError {
                Text("请输入有效的提前数量")
                    .font(WFType.supporting).foregroundStyle(WFColors.danger)
            }
            panelButtons(cancel: { closeSheet() }) {
                guard reminderDraft.confirm(into: model,
                    customAmount: presentation.shows(.reminderCustom) ? customOffsetAmount : nil,
                    unit: customOffsetUnit) else {
                    reminderInputError = true
                    return
                }
                closeSheet()
            }
        }
    }

    /// 滴答口径的预设：当天 / 提前 1 天 / 2 天 / 3 天 / 1 周，
    /// 外加草稿里已有的自定义提前量（降序 = 当天在最前）。
    private var reminderOptionValues: [Int] {
        Set([0, -1440, -2880, -4320, -10080])
            .union(reminderDraft.offsets)
            .union(model.reminderOffsets)
            .sorted(by: >)
    }

    /// 选项文案：`当天 (09:00)` / `提前1天 (09:00)` / 自定义量用分钟标题；
    /// 括号里是提醒时刻（全天任务默认 09:00，定时任务取定时钟点）。
    private func reminderOptionLabel(_ minutes: Int) -> String {
        "\(reminderOffsetTitle(minutes)) (\(reminderClockText))"
    }

    /// 提前量标题（滴答口径）：当天 / 提前1周 / 提前N天 / 分钟级自定义量。
    /// 实现只有一处：`ScheduleDisplay.reminderOffsetText(minutes:style: .panel)`。
    private func reminderOffsetTitle(_ minutes: Int) -> String {
        ScheduleDisplay.reminderOffsetText(minutes: minutes, style: .panel)
    }

    private var reminderClockText: String {
        if model.hasTime, let anchor = model.startTimeAnchor {
            return Self.clockText(anchor, calendar: workspace.calendar)
        }
        return Self.defaultClockText
    }

    /// 自定义提前量：提前 [数量] [分钟/小时/天]（确定时并入所选）。
    private var customOffsetRow: some View {
        HStack(spacing: 6) {
            Text("提前").font(.system(size: 12)).foregroundStyle(WFColors.text)
            TextField("10", text: $customOffsetAmount)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .frame(width: 36)
                .padding(.vertical, 2)
                .background(WFColors.hover, in: RoundedRectangle(cornerRadius: 5))
            Picker("", selection: $customOffsetUnit) {
                Text("分钟").tag(1)
                Text("小时").tag(60)
                Text("天").tag(1440)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 64)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: 重复子面板（Flutter ScheduleRepeatOptions）

    private var repeatPanelBody: some View {
        VStack(spacing: 0) {
            if let group = repeatGroup {
                optionsRow("‹ 返回") { repeatGroup = nil }
                ForEach(group == .work
                    ? [TaskRepeat.weekdays, TaskRepeat.workdays]
                    : [TaskRepeat.weekends, TaskRepeat.holidays], id: \.self) { value in
                    optionsRow(repeatOptionLabel(value), checked: model.frequency == value) {
                        applyFrequency(value)
                    }
                }
                Text(ChineseWorkCalendar.hasYear(calendar.component(.year, from: model.recurrenceAnchorDate))
                     ? "法定选项包含周末与调休安排。"
                     : "该年份尚无调休数据，法定选项暂按周一至周五／周末计算。")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            } else {
                ForEach([TaskRepeat.daily, TaskRepeat.weekly, TaskRepeat.monthly, TaskRepeat.yearly],
                        id: \.self) { value in
                    optionsRow(repeatOptionLabel(value), checked: model.frequency == value) {
                        applyFrequency(value)
                    }
                }
                Divider()
                optionsRow("工作日", arrow: true) { repeatGroup = .work }
                optionsRow("节假日", arrow: true) { repeatGroup = .holiday }
                Divider()
                optionsRow("自定义", checked: presentation.shows(.repeatCustom)) {
                    if !Self.frequencyUsesInterval(model.frequency) {
                        // 滴答的「自定义」是一套自己的规则：从"每天"起步再调间隔。
                        model.syncRecurrenceAnchor()
                        model.chooseFrequency(.daily)
                    }
                    if presentation.shows(.repeatCustom) { presentation.close(.repeatCustom) }
                    else { presentation.open(.repeatCustom) }
                }
                if presentation.shows(.repeatCustom) { intervalEditor }
            }
            Color.clear.frame(height: 8)
        }
    }

    /// 自定义区间：`每 [−] N [天/周/月/年] [+]`，直接写草稿的 interval。
    private var intervalEditor: some View {
        HStack(spacing: 10) {
            Text("每")
                .font(.system(size: 13))
                .foregroundStyle(WFColors.text)
            Text("\(model.interval)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WFColors.text)
                .frame(minWidth: 20)
            Text(Self.intervalUnitTitle(model.frequency))
                .font(.system(size: 13))
                .foregroundStyle(WFColors.text)
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                intervalStepButton("minus") { model.chooseInterval(max(1, model.interval - 1)) }
                intervalStepButton("plus") { model.chooseInterval(min(365, model.interval + 1)) }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: ScheduleMetrics.optionRowHeight)
    }

    private func intervalStepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 20, height: 20)
                .background(WFColors.hover, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func frequencyUsesInterval(_ frequency: TaskRepeat) -> Bool {
        switch frequency {
        case .daily, .weekly, .monthly, .yearly: true
        default: false
        }
    }

    private static func intervalUnitTitle(_ frequency: TaskRepeat) -> String {
        switch frequency {
        case .weekly: "周"
        case .monthly: "月"
        case .yearly: "年"
        default: "天"
        }
    }

    private var calendar: Calendar { workspace.calendar }

    /// 选中规则：周/月/年规则按锚定日同步（Flutter 的 ruleFor），随后立即生效并关闭。
    private func applyFrequency(_ value: TaskRepeat) {
        model.syncRecurrenceAnchor()
        model.chooseFrequency(value)
        closeSheet()
    }

    // MARK: 重复结束子面板（Flutter ScheduleEndOptions）

    private var repeatEndPanelBody: some View {
        VStack(spacing: 0) {
            if let edit = presentation.repeatEndEdit {
                if edit == .date {
                    LunarMonthGridView(calendar: calendar, displayedMonth: $repeatEndDisplayedMonth,
                        today: workspace.dateFromToday(0), selection: repeatEndDraftDate,
                        minimumDate: model.selectedDate, showsTodayButton: false) { date in
                            repeatEndDraftDate = date
                            applyEndEdit(.date)
                        }
                        .padding(14)
                        .scheduleRenderAnchor(.option("repeat-end-calendar"))
                } else {
                    HStack(spacing: 8) {
                        TextField("10", text: $repeatCountText)
                            .textFieldStyle(.plain)
                            .font(WFType.body)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(WFColors.hover, in: RoundedRectangle(cornerRadius: 5))
                            .scheduleRenderAnchor(.option("repeat-count-input"), label: repeatCountText)
                        Stepper("", value: Binding(get: { Int(repeatCountText) ?? model.repeatCount },
                            set: { repeatCountText = String($0) }), in: 1...Int.max)
                            .labelsHidden().fixedSize()
                            .scheduleRenderAnchor(.option("repeat-count-stepper"))
                        Text("次重复").font(WFType.body).fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    panelButtons(cancel: { presentation.closeRepeatEnd() }) { applyEndEdit(edit) }
                }
            } else {
                optionsRow("永不结束", checked: model.ending == .never) {
                    model.chooseEnding(.never)
                    closeSheet()
                }
                optionsRow("按日期结束", checked: model.ending == .untilDate) {
                    repeatEndDraftDate = model.repeatEndDate
                    repeatEndDisplayedMonth = model.repeatEndDate
                    presentation.open(.repeatEnd(.date))
                }
                optionsRow("按次数结束", checked: model.ending == .count) {
                    repeatCountText = String(model.repeatCount)
                    presentation.open(.repeatEnd(.count))
                }
                Spacer(minLength: 10)
            }
        }
    }

    private func applyEndEdit(_ edit: RepeatEndEdit) {
        switch edit {
        case .date:
            model.chooseRepeatEndDate(repeatEndDraftDate)
            model.chooseEnding(.untilDate)
        case .count:
            guard let count = Int(repeatCountText), count >= 1 else {
                repeatCountText = String(model.repeatCount)
                return
            }
            model.chooseRepeatCount(count)
            model.chooseEnding(.count)
        }
        closeSheet()
    }

    // MARK: 子面板零件

    /// 选项文案：括号部分（`每周 (周六)`、`当天 (09:00)`）用三级灰，其余按选中态着色。
    private func optionLabel(_ title: String, checked: Bool) -> Text {
        let mainColor = checked ? WFColors.accent : WFColors.text
        guard let paren = title.range(of: " (") else {
            return Text(title).foregroundColor(mainColor)
        }
        let head = String(title[title.startIndex..<paren.lowerBound])
        let tail = String(title[paren.lowerBound...])
        return Text(head).foregroundColor(mainColor)
            + Text(tail).foregroundColor(checked ? WFColors.accent.opacity(0.7) : WFColors.tertiaryText)
    }

    /// 子面板选项行（Flutter `ScheduleOptionRow`）：34pt、选中强调色 + ✓。
    private func optionsRow(_ title: String, checked: Bool = false, arrow: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                optionLabel(title, checked: checked)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WFColors.accent)
                } else if arrow {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WFColors.tertiaryText)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: ScheduleMetrics.optionRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 点选后不留系统焦点框（弹窗里的蓝色描边看起来像脏线）。
        .focusEffectDisabled()
        .scheduleRenderAnchor(.option(title), label: title, active: checked)
    }

    private func panelButtons(cancel: @escaping () -> Void, confirm: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            sheetFooterButton("取消", filled: false, action: cancel)
            sheetFooterButton("确定", filled: true, action: confirm)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .scheduleRenderAnchor(.editorFooter(inlineSheet ?? .reminder), label: "取消 / 确定")
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

    // MARK: 属性行文案

    private var reminderRowLabel: String {
        let offsets = model.reminderOffsetsDraft
        if !offsets.isEmpty {
            return offsets.map { $0 == 0 && model.hasTime ? "准时" : reminderOffsetTitle($0) }.joined(separator: ", ")
        }
        guard model.reminderOption != .none else { return "提醒" }
        return reminderChipTitle
    }

    /// 重复行：按存储的周/日/月规则渲染（Flutter `scheduleRepeatLabel`）。
    private var repeatRowLabel: String {
        repeatLabel(model.frequency,
                    weekday: model.weekday, monthDay: model.monthDay, month: model.month,
                    lunarName: ChineseWorkCalendar.lunarMonthName(model.lunarMonth, isLeapMonth: model.lunarIsLeapMonth)
                        + ChineseWorkCalendar.lunarDayName(model.lunarDay),
                    lunarDayText: ChineseWorkCalendar.lunarDayName(model.lunarDay))
    }

    /// 重复选项行：用锚定日渲染即将生效的规则。
    private func repeatOptionLabel(_ value: TaskRepeat) -> String {
        let day = model.recurrenceAnchorDate
        let lunar = ChineseWorkCalendar.lunarCalendar(matching: calendar)
        let lunarComps = lunar.dateComponents([.month, .day], from: day)
        return repeatLabel(value,
                           weekday: calendar.component(.weekday, from: day),
                           monthDay: calendar.component(.day, from: day),
                           month: calendar.component(.month, from: day),
                           lunarName: ChineseWorkCalendar.lunarMonthName(lunarComps.month ?? 1,
                                                                         isLeapMonth: lunarComps.isLeapMonth == true)
                               + ChineseWorkCalendar.lunarDayName(lunarComps.day ?? 1),
                           lunarDayText: ChineseWorkCalendar.lunarDayName(lunarComps.day ?? 1))
    }

    /// 实现只有一处：`ScheduleDisplay.repeatText(_:context:)`。
    private func repeatLabel(_ value: TaskRepeat, weekday: Int, monthDay: Int, month: Int,
                             lunarName: String? = nil, lunarDayText: String? = nil) -> String {
        ScheduleDisplay.repeatText(value, context: .init(weekday: weekday, monthDay: monthDay,
                                                         month: month, lunarName: lunarName,
                                                         lunarDayText: lunarDayText))
    }

    private var endRowLabel: String {
        switch model.ending {
        case .untilDate:
            let components = calendar.dateComponents([.year, .month, .day], from: model.repeatEndDate)
            return "直到 \(components.year ?? 0)/\(components.month ?? 0)/\(components.day ?? 0)"
        case .count:
            return "重复 \(model.repeatCount) 次后结束"
        case .never:
            return "永不结束"
        }
    }

    /// Chip label for a set reminder: preset title or the absolute time.
    private var reminderChipTitle: String {
        switch model.reminderOption {
        case .none: return "无"
        case .custom:
            return TaskDateLabel.text(model.customReminder, hasTime: true,
                                      now: workspace.clock(), calendar: workspace.calendar)
        case .onTime:
            return model.hasTime ? "准时" : "当天"
        default:
            return TaskDateDraftModel.presetOffsets
                .first { $0.option == model.reminderOption }?.title ?? "准时"
        }
    }

    private static func clockText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private static func isClock(_ date: Date, hour: Int, minute: Int, calendar: Calendar) -> Bool {
        calendar.component(.hour, from: date) == hour && calendar.component(.minute, from: date) == minute
    }

    // MARK: Sheet state

    private func toggleSheet(_ sheet: InlineSheet) {
        if inlineSheet == sheet { closeSheet() } else { openSheet(sheet) }
    }

    private func closeSheet() {
        // 收属性子卡时连同子页与二级页一起收，避免下次打开残留。
        presentation.collapseProperty()
    }

    private func openSheet(_ sheet: InlineSheet) {
        SchedulePanelInteraction.open(sheet, state: &presentation, model: model,
                                      now: workspace.clock(), calendar: workspace.calendar)
        switch sheet {
        case .time:
            timeFieldText = model.hasTime
                ? Self.clockText(model.startTimeAnchor ?? workspace.clock(), calendar: workspace.calendar)
                : Self.defaultClockText
        case .endTime:
            endTimeFieldText = model.endTimeAnchor
                .map { Self.clockText($0, calendar: workspace.calendar) } ?? Self.defaultClockText
        case .reminder:
            reminderDraft = ScheduleReminderDraft(offsets: model.reminderOffsets)
            reminderInputError = false
            presentation.close(.reminderCustom)
            customOffsetAmount = ""
            customOffsetUnit = 1
        case .repeat:
            repeatGroup = nil
            presentation.close(.repeatCustom)
        case .repeatEnd:
            presentation.closeRepeatEnd()
            repeatEndDraftDate = model.repeatEndDate
            repeatCountText = String(model.repeatCount)
        }
        inlineSheet = sheet
    }

    // MARK: 分段 / 快捷行 / 底部按钮

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
                // 原版分段文字取 `body`（14）配 regular：选中由下面那块填色胶囊表达，
                // 不再叠一层字重。
                .font(.system(size: 14))
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

    /// 实现只有一处：`ScheduleDisplay.dayText(_:calendar:)`。
    private func dayText(_ date: Date) -> String {
        ScheduleDisplay.dayText(date, calendar: workspace.calendar)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                clear()
            } label: {
                Text("清除")
                    .font(.system(size: 14))
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
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background(WFColors.accent, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("schedule-confirm")
        }
        .scheduleRenderAnchor(.mainFooter, label: "清除 / 确定")
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
        .scheduleRenderAnchor(.shortcut(help))
    }

    // MARK: Commit

    private func save() {
        // 结束早于开始 → 禁止确认（Flutter `apply()` 的同一判据；相等合法）。
        if model.rangeError != nil {
            showRangeError = true
            return
        }
        showRangeError = false
        // 草稿宿主：把计划交给调用方（新建卡把它带回草稿状态），不碰工作区。
        if let draftCommit {
            draftCommit(model.commitPlan(for: task))
            onClose()
            return
        }
        // Read current task here, so an open popover cannot overwrite other edits.
        guard let current = workspace.task(for: taskID) else { onClose(); return }
        let plan = model.commitPlan(for: current)
        workspace.saveSchedule(plan, to: .task(taskID))
        onClose()
    }

    private func clear() {
        if let draftCommit {
            draftCommit(model.clearPlan(for: task))
            onClose()
            return
        }
        guard let current = workspace.task(for: taskID) else { onClose(); return }
        let plan = model.clearPlan(for: current)
        workspace.saveSchedule(plan, to: .task(taskID))
        onClose()
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
