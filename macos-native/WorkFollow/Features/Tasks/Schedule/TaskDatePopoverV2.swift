import SwiftUI

/// 日程面板（Flutter `TaskSchedulePanel` 的原生对照）。
///
/// 结构照搬 Flutter 版：
/// - 主面板 = 日期/时间段 tabs + 快捷日 + 日历 + 属性行（时间/提醒/重复/重复结束）+ 清除/确定；
/// - 点属性行打开的是**独立子面板**（Flutter `showScheduleOptions`）：从该行顶部开始、
///   盖住该行往下展开，宽度 = 行宽、无间隙、高度受限可滚动，永远浮在其它内容之上——
///   因此子面板既不会被下方属性行遮住，也不会被弹框边界裁掉；
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

    /// 子面板（Flutter 子菜单层）：贴着自己的属性行顶展开、覆盖该行往下。
    enum InlineSheet: Hashable {
        case time, reminder, `repeat`, repeatEnd
    }

    /// 重复二级页（Flutter: 工作日›/节假日›）。
    private enum RepeatGroup {
        case work, holiday
    }

    /// 重复结束二级页（Flutter: 按日期结束/按次数结束）。
    private enum RepeatEndEdit {
        case date, count
    }

    /// 尺寸契约统一走 `ScheduleMetrics`（主面板宽 260 / 行高 30 / 选项行 34 /
    /// 时间列表 280 / 子浮层宽 232）。
    @StateObject private var model: TaskDateDraftModel
    @State private var inlineSheet: InlineSheet?
    @State private var repeatGroup: RepeatGroup?
    @State private var repeatEndEdit: RepeatEndEdit?
    /// 鼠标当前悬浮的属性行（已设值的行尾把 › 换成 ×）。
    @State private var hoveredSheet: InlineSheet?
    /// 时间行内编辑的文本（展开时可改，提交后回写草稿）。
    @State private var timeFieldText = ""
    /// 重复浮层的「自定义」区间编辑是否展开。
    @State private var repeatCustomOpen = false
    @State private var reminderDraft: Set<Int> = []
    @State private var reminderCustomOpen = false
    @State private var customOffsetAmount = ""
    @State private var customOffsetUnit = 1
    @State private var repeatCountText = ""
    @State private var repeatEndDraftDate = Date()

    init(task: Task, workspace: TaskWorkspaceModel, deadline: Bool = false, initialPage: Page = .main,
         draftCommit: ((TaskDateDraftModel.CommitPlan) -> Void)? = nil,
         onClose: @escaping () -> Void) {
        taskID = task.id
        self.task = task
        self.workspace = workspace
        self.deadline = deadline
        self.initialPage = initialPage
        self.draftCommit = draftCommit
        self.onClose = onClose
        let draftModel = TaskDateDraftModel(
            task: task, calendar: workspace.calendar, now: workspace.clock, deadline: deadline)
        _model = StateObject(wrappedValue: draftModel)
        _inlineSheet = State(initialValue: initialPage == .time ? .time
            : initialPage == .reminder ? .reminder
            : initialPage == .recurrence ? .`repeat` : nil)
        _reminderDraft = State(initialValue: Set(draftModel.reminderOffsets))
        _timeFieldText = State(initialValue: draftModel.hasTime
            ? Self.clockText(draftModel.timeAnchor ?? workspace.clock(), calendar: workspace.calendar)
            : Self.defaultClockText)
        _repeatCountText = State(initialValue: String(draftModel.repeatCount))
        _repeatEndDraftDate = State(initialValue: draftModel.repeatEndDate)
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
                    propertyRows
                }
                footer
            }
        }
        .padding(ScheduleMetrics.horizontalPadding)
        .frame(width: ScheduleMetrics.panelWidth)
        // macOS 27：`.popover` 不传 arrowEdge（默认 nil）就不画三角箭头，
        // 系统自带圆角卡片样式（对齐滴答/参考图），无需任何背景补丁。
        .onChange(of: model.timeAnchor) { _, _ in syncTimeField() }
        .onChange(of: model.hasTime) { _, _ in syncTimeField() }
    }

    // MARK: 属性行 + 子面板（Flutter `_property` / `showScheduleOptions`）

    private var propertyRows: some View {
        VStack(spacing: 0) {
            sheetRow(.time, icon: "clock", title: timeRowTitle, active: model.hasTime,
                     editor: AnyView(timeRowEditor),
                     clear: model.hasTime ? {
                         model.setHasTime(false)
                         timeFieldText = Self.defaultClockText
                     } : nil) { timePanelBody }
            sheetRow(.reminder, icon: "alarm", title: reminderRowLabel,
                     active: model.hasReminderDraft,
                     clear: model.hasReminderDraft ? { model.clearReminder() } : nil) {
                reminderPanelBody
            }
            sheetRow(.repeat, icon: "repeat", title: repeatRowLabel,
                     active: model.frequency != .never,
                     clear: model.frequency != .never ? {
                         model.chooseFrequency(.never)
                     } : nil) { repeatPanelBody }
            if model.frequency != .never {
                sheetRow(.repeatEnd, icon: "repeat", title: endRowLabel, active: false) {
                    repeatEndPanelBody
                }
            }
        }
    }

    /// 属性行 + 浮层子面板（滴答口径）。
    ///
    /// 子面板是**独立浮层**：点行弹出、浮在主面板之上，主面板尺寸与布局完全不动。
    /// 行自己就是面板头部——展开时**变灰底、chevron 转 ˅**，按属性需要出现
    /// 行内编辑（时间：可编辑 HH:mm）或清除（×）；浮层里只放选项，不重复当前值。
    private func sheetRow<Body: View>(_ sheet: InlineSheet, icon: String, title: String,
                                      active: Bool,
                                      editor: AnyView? = nil,
                                      clear: (() -> Void)? = nil,
                                      @ViewBuilder body: @escaping () -> Body) -> some View {
        let open = inlineSheet == sheet
        // 行尾控件：未设值 = ›/˅；已设值且（悬浮或已展开）= ×（点击清除）。
        let showClear = clear != nil && (open || hoveredSheet == sheet)
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(active || open ? WFColors.accent : WFColors.secondaryText)
                .frame(width: 18)
            if let editor, active {
                // 时间：设了时间就是行内 HH:mm 输入框（可精确到分钟）。
                editor
            } else {
                Text(title)
                    .font(WFType.body)
                    .foregroundStyle(active ? WFColors.accent : WFColors.text)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if showClear, let clear {
                clearControl(clear)
            } else {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WFColors.tertiaryText)
                    .frame(width: 18, height: 18)
            }
        }
        .padding(.horizontal, open ? 10 : 2)
        .frame(height: ScheduleMetrics.rowHeight)
        .background(open ? WFColors.hover : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        // 整行开合的命中区放在**内容之下**：输入框与清除按钮在它前面，先拿到自己的
        // 点击；点行内其余任何位置都能开合（行上有输入框时也照常能展开）。
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleSheet(sheet) }
        }
        .onHover { inside in
            if inside {
                hoveredSheet = sheet
            } else if hoveredSheet == sheet {
                hoveredSheet = nil
            }
        }
        .schedulePopover(isPresented: sheetBinding(sheet)) {
            panel(body: body)
        }
    }

    /// 行尾清除（×）：清除本属性，不影响其它行。
    private func clearControl(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WFColors.tertiaryText)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("清除")
        .accessibilityLabel("清除")
    }

    /// 时间行的行内编辑（滴答：行即 HH:mm 输入框，列表给半点粒度、输入框给分钟）。
    private var timeRowEditor: AnyView {
        AnyView(
            TextField(Self.defaultClockText, text: $timeFieldText)
                .textFieldStyle(.plain)
                .font(WFType.body)
                .foregroundStyle(WFColors.accent)
                .frame(width: 52, alignment: .leading)
                .onSubmit(submitTimeField)
        )
    }

    /// 时间值在别处变化（列表点选、日历改天、清除）后同步行内文本。
    private func syncTimeField() {
        timeFieldText = model.hasTime
            ? Self.clockText(model.timeAnchor ?? workspace.clock(), calendar: workspace.calendar)
            : Self.defaultClockText
    }

    /// 未设置时间时的默认显示（滴答：全天任务按 09:00 起算）。
    private static var defaultClockText: String {
        String(format: "%02d:00", TaskDateDraftModel.allDayAnchorHour)
    }

    private func submitTimeField() {
        let parts = timeFieldText.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else {
            timeFieldText = model.hasTime
                ? Self.clockText(model.timeAnchor ?? workspace.clock(), calendar: workspace.calendar)
                : Self.defaultClockText
            return
        }
        let calendar = workspace.calendar
        let day = calendar.startOfDay(for: model.timeAnchor ?? workspace.clock())
        guard let value = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return }
        model.setHasTime(true)
        model.setTime(value)
    }

    /// 浮层开关绑定：点行打开，点浮层外部（系统 dismiss）收起。
    private func sheetBinding(_ sheet: InlineSheet) -> Binding<Bool> {
        Binding(
            get: { inlineSheet == sheet },
            set: { presented in
                if !presented, inlineSheet == sheet { closeSheet() }
            })
    }

    /// 浮层内容 = 选项本身。Flutter 的子菜单把"属性行 + 当前值 + 清除"当头部，
    /// 是因为菜单从行顶部展开、行即头部；原生弹窗浮在行下方，行本身已经显示
    /// 当前值，再画一层头部就是重复，所以这里只放选项。
    private func panel<Body: View>(@ViewBuilder body: () -> Body) -> some View {
        body()
            .frame(width: ScheduleMetrics.optionPanelWidth)
    }

    // MARK: 时间子面板（Flutter ScheduleTimeOptions）

    /// 时间浮层 = 半小时步进列表（当前值强调色 + ✓），点即选即用；
    /// 精确到分钟与清除都在行内（`timeRowEditor` / 行尾 ×）。
    private var timePanelBody: some View {
        timeOptionsList
    }

    private var timeOptionsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(halfHourOptions, id: \.self) { option in
                        optionsRow(Self.clockText(option, calendar: workspace.calendar),
                                   checked: isDraftTime(option)) {
                            model.setHasTime(true)
                            model.setTime(option)
                            closeSheet()
                        }
                        .id(option)
                    }
                }
            }
            .frame(height: ScheduleMetrics.timeOptionsHeight)
            .onAppear {
                if let target = halfHourOptions.first(where: { isDraftTime($0) })
                    ?? halfHourOptions.first(where: { Self.isClock($0, hour: 9, minute: 0,
                                                                  calendar: workspace.calendar) }) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }

    /// 48 个半小时选项（00:00–23:30），锚在草稿那一天的零点上。
    private var halfHourOptions: [Date] {
        let calendar = workspace.calendar
        let day = calendar.startOfDay(for: model.timeAnchor ?? workspace.clock())
        return (0..<48).compactMap { calendar.date(byAdding: .minute, value: $0 * 30, to: day) }
    }

    private func isDraftTime(_ option: Date) -> Bool {
        guard model.hasTime, let anchor = model.timeAnchor else { return false }
        return Self.isClock(option, hour: workspace.calendar.component(.hour, from: anchor),
                            minute: workspace.calendar.component(.minute, from: anchor),
                            calendar: workspace.calendar)
    }

    // MARK: 提醒子面板（Flutter ScheduleReminderOptions）

    private var reminderPanelBody: some View {
        VStack(spacing: 0) {
            ForEach(reminderOptionValues, id: \.self) { minutes in
                optionsRow(reminderOptionLabel(minutes),
                           checked: reminderDraft.contains(minutes)) {
                    if !reminderDraft.insert(minutes).inserted {
                        reminderDraft.remove(minutes)
                    }
                }
            }
            Divider()
            optionsRow("自定义") { reminderCustomOpen.toggle() }
            if reminderCustomOpen { customOffsetRow }
            panelButtons(cancel: { closeSheet() }) {
                model.setReminderOffsets(reminderDraft)
                closeSheet()
            }
        }
    }

    /// 滴答口径的预设：当天 / 提前 1 天 / 2 天 / 3 天 / 1 周，
    /// 外加草稿里已有的自定义提前量（降序 = 当天在最前）。
    private var reminderOptionValues: [Int] {
        Set([0, -1440, -2880, -4320, -10080])
            .union(reminderDraft)
            .union(model.reminderOffsets)
            .sorted(by: >)
    }

    /// 选项文案：`当天 (09:00)` / `提前1天 (09:00)` / 自定义量用分钟标题；
    /// 括号里是提醒时刻（全天任务默认 09:00，定时任务取定时钟点）。
    private func reminderOptionLabel(_ minutes: Int) -> String {
        "\(reminderOffsetTitle(minutes)) (\(reminderClockText))"
    }

    /// 提前量标题（滴答口径）：当天 / 提前1周 / 提前N天 / 分钟级自定义量。
    private func reminderOffsetTitle(_ minutes: Int) -> String {
        if minutes == 0 { return "当天" }
        if minutes % 10080 == 0 { return "提前\(-minutes / 10080)周" }
        if minutes % 1440 == 0 { return "提前\(-minutes / 1440)天" }
        return TaskDateDraftModel.offsetTitle(minutes)
    }

    private var reminderClockText: String {
        if model.hasTime, let anchor = model.timeAnchor {
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
                optionsRow("自定义", checked: repeatCustomOpen) {
                    if !Self.frequencyUsesInterval(model.frequency) {
                        // 滴答的「自定义」是一套自己的规则：从"每天"起步再调间隔。
                        model.syncRecurrenceAnchor()
                        model.chooseFrequency(.daily)
                    }
                    repeatCustomOpen.toggle()
                }
                if repeatCustomOpen { intervalEditor }
            }
            Spacer(minLength: 8)
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
            if let edit = repeatEndEdit {
                optionsRow("‹ 返回") { repeatEndEdit = nil }
                if edit == .date {
                    DatePicker("", selection: $repeatEndDraftDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(.horizontal, 8)
                } else {
                    VStack(spacing: 6) {
                        TextField("10", text: $repeatCountText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .multilineTextAlignment(.center)
                            .frame(width: 60)
                            .padding(.vertical, 4)
                            .background(WFColors.hover, in: RoundedRectangle(cornerRadius: 5))
                        Text("包含当前这一次任务")
                            .font(WFType.supporting)
                            .foregroundStyle(WFColors.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                panelButtons(cancel: { repeatEndEdit = nil }) { applyEndEdit(edit) }
            } else {
                optionsRow("永不结束", checked: model.ending == .never) {
                    model.chooseEnding(.never)
                    closeSheet()
                }
                optionsRow("按日期结束", checked: model.ending == .untilDate) {
                    repeatEndDraftDate = model.repeatEndDate
                    repeatEndEdit = .date
                }
                optionsRow("按次数结束", checked: model.ending == .count) {
                    repeatCountText = String(model.repeatCount)
                    repeatEndEdit = .count
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
    }

    private func panelButtons(cancel: @escaping () -> Void, confirm: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            sheetFooterButton("取消", filled: false, action: cancel)
            sheetFooterButton("确定", filled: true, action: confirm)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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

    private var timeRowTitle: String {
        guard model.hasTime, let anchor = model.timeAnchor else { return "时间" }
        return Self.clockText(anchor, calendar: workspace.calendar)
    }

    private var reminderRowLabel: String {
        let offsets = model.reminderOffsetsDraft
        if !offsets.isEmpty {
            return offsets.map(reminderOffsetTitle).joined(separator: ", ")
        }
        guard model.reminderOption != .none else { return "提醒" }
        return reminderChipTitle
    }

    /// 重复行：按存储的周/日/月规则渲染（Flutter `scheduleRepeatLabel`）。
    private var repeatRowLabel: String {
        repeatLabel(model.frequency, weekday: model.weekday, monthDay: model.monthDay, month: model.month)
    }

    /// 重复选项行：用锚定日渲染即将生效的规则。
    private func repeatOptionLabel(_ value: TaskRepeat) -> String {
        let day = model.recurrenceAnchorDate
        return repeatLabel(value,
                           weekday: calendar.component(.weekday, from: day),
                           monthDay: calendar.component(.day, from: day),
                           month: calendar.component(.month, from: day))
    }

    private func repeatLabel(_ value: TaskRepeat, weekday: Int, monthDay: Int, month: Int) -> String {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        let index = max(1, min(7, weekday)) - 1
        switch value {
        case .never: return "重复"
        case .daily: return "每天"
        case .weekly: return "每周 (周\(symbols[index]))"
        case .monthly: return "每月 (\(monthDay)日)"
        case .yearly: return "每年 (\(month)月\(monthDay)日)"
        case .weekdays: return "每周一至周五"
        case .weekends: return "每周六、周日"
        case .workdays: return "法定工作日"
        case .holidays: return "法定休息日"
        }
    }

    private var endRowLabel: String {
        switch model.ending {
        case .untilDate:
            let components = calendar.dateComponents([.year, .month, .day], from: model.repeatEndDate)
            return "\(components.year ?? 0)年\(components.month ?? 0)月\(components.day ?? 0)日结束"
        case .count:
            return "\(model.repeatCount)次后结束"
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
        inlineSheet = nil
    }

    private func openSheet(_ sheet: InlineSheet) {
        switch sheet {
        case .time:
            timeFieldText = model.hasTime
                ? Self.clockText(model.timeAnchor ?? workspace.clock(), calendar: workspace.calendar)
                : Self.defaultClockText
        case .reminder:
            reminderDraft = model.reminderOffsets
            reminderCustomOpen = false
            customOffsetAmount = ""
            customOffsetUnit = 1
        case .repeat:
            repeatGroup = nil
            repeatCustomOpen = false
        case .repeatEnd:
            repeatEndEdit = nil
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

    // MARK: Commit

    private func save() {
        // 草稿宿主：把计划交给调用方（新建卡把它带回草稿状态），不碰工作区。
        if let draftCommit {
            draftCommit(model.commitPlan(for: task))
            onClose()
            return
        }
        // Read current task here, so an open popover cannot overwrite other edits.
        guard let current = workspace.task(for: taskID) else { onClose(); return }
        let plan = model.commitPlan(for: current)
        workspace.saveTiming(taskID, schedule: plan.schedule, reminder: plan.reminder,
                             frequency: plan.frequency, recurrenceRule: plan.recurrenceRule)
        persistReminderOffsets(plan.reminderOffsets, on: current)
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
