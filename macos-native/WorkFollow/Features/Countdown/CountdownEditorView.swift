import SwiftUI

/// 固定色板；与 `CountdownWorkspaceView.swift` 的同名调色板必须同序同值
/// （Domain 只存下标，颜色映射在界面侧）。
private let countdownEditorPalette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]

private func countdownEditorColor(_ index: Int) -> Color {
    let count = max(countdownEditorPalette.count, 1)
    return countdownEditorPalette[((index % count) + count) % count]
}

/// 新建 / 编辑倒数纪念日。布局照参考图的「添加」面板：图标 + 名称输入框一行，
/// 其下 日期 / 提醒 / 重复 / 类型 / 显示 五行（生日多一行「显示岁数」），
/// 底部 取消 / 添加。
///
/// 五个下拉都是**浮层**（`overlayPreferenceValue` + `RowAnchorKey` 定位），
/// 不是行内展开：行内展开会把面板撑高、把底部按钮推走，而参考图的面板是定高的。
///
/// 注意浮层必须留在面板内：macOS 的 sheet 就是一块真实窗口、会裁掉伸出去的内容，
/// 所以「下方放不下就翻到上方」（见 `popupY`），而不是让浮层溢出面板。
struct CountdownEditorView: View {
    @ObservedObject var store: CountdownStore
    /// nil = 新建。
    let original: CountdownEvent?

    @Environment(\.dismiss) private var dismiss

    /// 一次只展开一行。
    private enum Row: String, Identifiable {
        case date, reminder, recurrence, kind, display
        var id: String { rawValue }
    }

    @State private var kind: CountdownKind
    @State private var name: String
    @State private var symbol: String
    @State private var colorIndex: Int
    @State private var pickedDate: Date?
    /// 日期浮层里月历当前显示的月份。与 `pickedDate` 分开存：翻月不改选中值。
    @State private var displayedMonth: Date
    @State private var pickedFestival: CountdownFestival.Option?
    @State private var repeatSelection: CountdownRepeat
    @State private var reminders: Set<Int>
    @State private var smartListDisplay: CountdownSmartListDisplay
    @State private var showsAge: Bool
    @State private var note: String
    @State private var noteExpanded: Bool
    @State private var openRow: Row?
    /// 「提醒 → 自定义」里的提前天数。存量里已有的非预设值回填到这里。
    @State private var customReminderDays: Int
    /// 「重复 → 自定义」里的间隔天数。
    @State private var customIntervalDays: Int

    private var calendar: Calendar { .current }
    private var isNew: Bool { original == nil }

    // 参考面板实测（1512pt 窗口下的原版「添加」面板）：
    // 面板 460×448，左右内边距 39，行高 34，行间距 10，标签列宽 54，
    // 行内控件 322×34，底部按钮 102×32。这里按同一组数排，别凭感觉调。
    private static let panelWidth: CGFloat = 460
    private static let inset: CGFloat = 40
    private static let labelWidth: CGFloat = 54
    private static let rowHeight: CGFloat = 34
    private static let rowGap: CGFloat = 10
    private static let buttonWidth: CGFloat = 102
    /// 下拉浮层里选项行的高度。
    ///
    /// 参考图的下拉行距是 34（跟面板行一样），但参考图里浮层是**伸出面板之外**画的，
    /// 而 macOS 的 sheet 会把伸出去的部分裁掉。面板又不能变高（那正是要修的毛病），
    /// 所以只能让行距小一点，把选项塞进面板里：
    /// - 34 时「提醒」「重复」都放不下，被迫翻到行上方；
    /// - 30 时能挂在行下方，但最底下的「自定义」会被面板下沿切掉一点；
    /// - 28 时 7 行 = 208pt，稳稳落在可用高度（约 215pt）内，最后一行完整可见。
    private static let popupRowHeight: CGFloat = 28

    init(store: CountdownStore, original: CountdownEvent?, defaultKind: CountdownKind = .anniversary) {
        self.store = store
        self.original = original
        let kind = original?.kind ?? defaultKind
        _kind = State(initialValue: kind)
        _name = State(initialValue: original?.name ?? "")
        _symbol = State(initialValue: original?.safeSymbol ?? kind.defaultSymbol)
        _colorIndex = State(initialValue: original?.colorIndex ?? kind.defaultColorIndex)
        // 编辑时把规则摊回「一个具体日期」：重复规则取它的下一次发生日，
        // 这样切换类型或改重复都不会把已选的日期丢掉。**生日例外**——它必须落回
        // 出生那天，否则出生年在「编辑一次再保存」的往返里就被磨掉了，
        // 「显示岁数」也就永远算不出来。
        //
        // 新建时**故意留空**：参考图的「日期」行是灰色的「选择日期」占位，
        // 「添加」按钮同时是禁用的——即日期属于必填，但初始不预设。
        let calendar = Calendar.current
        let today = Date()
        let initialDate = original.map { event -> Date in
            if case .birthday(let month, let day, let year) = event.rule,
               let birth = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
                return birth
            }
            return event.occurrence(onOrAfter: today, calendar: calendar)
        }
        _pickedDate = State(initialValue: initialDate)
        // 月历从已选那天开屏；新建（还没选日期）就从今天。
        _displayedMonth = State(initialValue: initialDate ?? today)
        _pickedFestival = State(initialValue: original.flatMap {
            $0.kind == .festival ? CountdownFestival.name(for: $0.rule).flatMap { name in
                CountdownFestival.all.first { $0.name == name }
            } : nil
        })
        _repeatSelection = State(initialValue: original?.repeatValue ?? kind.defaultRepeat)
        _reminders = State(initialValue: Set(original?.reminderOffsets
            ?? CountdownEvent.defaultReminderOffsets))
        _smartListDisplay = State(initialValue: original?.effectiveSmartListDisplay ?? .sameDay)
        _showsAge = State(initialValue: original?.showsAge ?? false)
        _note = State(initialValue: original?.note ?? "")
        _noteExpanded = State(initialValue: !(original?.note ?? "").isEmpty)
        // 「自定义」两个输入框：存量里已经有非预设值的就回填，否则给 30。
        let presetDays = Set(CountdownEvent.reminderChoices.map { $0 / CountdownEvent.minutesPerDay })
        let existingCustomDays = (original?.reminderOffsets ?? [])
            .map { $0 / CountdownEvent.minutesPerDay }
            .first { !presetDays.contains($0) }
        _customReminderDays = State(initialValue: existingCustomDays ?? 30)
        let existingInterval: Int
        if let rule = original?.rule, case .interval(let days, _, _) = rule {
            existingInterval = days
        } else {
            existingInterval = 30
        }
        _customIntervalDays = State(initialValue: existingInterval)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? "添加" : "编辑")
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 30)
                .padding(.bottom, 16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Self.rowGap) {
                    nameRow
                    if noteExpanded { noteField }
                    dateRow
                    reminderRow
                    repeatRow
                    kindRow
                    displayRow
                    if kind.hasAgeOption { ageRow }
                }
                .padding(.horizontal, Self.inset)
                .padding(.vertical, WFSpace.xxl)
            }
            // 固定高度：下拉是浮层，不再把面板撑高（参考图的面板就是固定大小）。
            // 410 是「提醒」「重复」都能挂在行下方的最小高度（「显示」在最底下，
            // 无论如何都要翻到上面）。
            .frame(maxHeight: 410)
            Divider()
            footer
        }
        .frame(width: Self.panelWidth)
        .background(WFColors.canvas)
        // 下拉浮层：浮在对应行的旁边、盖在面板内容之上，**不参与布局**。
        .overlayPreferenceValue(RowAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let openRow, let anchor = anchors[openRow] {
                    let rect = proxy[anchor]
                    let height = popupHeight(for: openRow)
                    let y = popupY(row: rect, height: height,
                                   containerHeight: proxy.size.height)
                    popup {
                        popupBody(for: openRow,
                                  maxHeight: popupRoom(row: rect, y: y,
                                                       containerHeight: proxy.size.height))
                    }
                    .frame(width: rect.width)
                    .offset(x: rect.minX, y: y)
                }
            }
        }
    }

    /// 浮层的纵向落点。
    ///
    /// 默认挂在行的正下方；下方放不下就翻到行的上方（底边贴着行上沿）。
    /// **必须留在面板里**：sheet 的边界就是面板边界，伸出去的部分会被裁掉
    /// （表现成「浮层被编辑框挡住」）；而面板又不能在展开时变高——那正是要修的毛病。
    private func popupY(row rect: CGRect, height: CGFloat, containerHeight: CGFloat) -> CGFloat {
        let gap: CGFloat = 6
        let top: CGFloat = 8
        let bottom = containerHeight - 8
        let below = rect.maxY + gap
        if below + height <= bottom { return below }
        let above = rect.minY - gap - height
        if above >= top { return above }
        // 两边都放不下（列表比面板还高）：贴着余量大的那一侧，超出的部分靠滚动。
        return (bottom - below) >= (rect.minY - top) ? below : top
    }

    /// 浮层实际能占的高度。
    private func popupRoom(row rect: CGRect, y: CGFloat, containerHeight: CGFloat) -> CGFloat {
        max(120, containerHeight - 8 - y)
    }

    /// 浮层的高度。
    ///
    /// 选项行高是固定的，所以能算出来——**不去量**：浮层伸出面板时会被裁，
    /// 量到的就是裁过之后的值，「放不下→翻上去」的判断会跟着反复横跳。
    private func popupHeight(for row: Row) -> CGFloat {
        // 上下内边距（WFSpace.xs × 2）+ 分隔线。估大了会让明明放得下的浮层翻上去。
        let chrome: CGFloat = 12
        switch row {
        case .date:
            // 节日目录是定高的滚动列表；其余是项目自己的月历（`LunarMonthGridView`）：
            // 头部 18 + 星期行 15 + 6×30 网格 + 5 处 2pt 行距 + 2 处 4pt 间距 = 231，
            // 再加浮层自身的内边距。`MonthGridCalculator.weeks` 固定 6，所以是个定值。
            return kind.usesFestivalCatalog ? 188 : 243
        case .reminder:
            return CGFloat(7 + (isCustomReminder ? 1 : 0)) * Self.popupRowHeight + chrome
        case .recurrence:
            return CGFloat(6 + (repeatSelection == .custom ? 1 : 0)) * Self.popupRowHeight + chrome
        case .kind:
            return 4 * Self.popupRowHeight + chrome
        case .display:
            return 22 + 5 * Self.popupRowHeight + chrome
        }
    }

    /// 放不下时给浮层套一层滚动，别把内容裁掉。
    @ViewBuilder
    private func popupBody(for row: Row, maxHeight: CGFloat) -> some View {
        if popupHeight(for: row) > maxHeight {
            ScrollView { editor(for: row) }.frame(height: maxHeight)
        } else {
            editor(for: row)
        }
    }

    @ViewBuilder
    private func editor(for row: Row) -> some View {
        switch row {
        case .date: dateEditor
        case .reminder: reminderEditor
        case .recurrence: repeatEditor
        case .kind: kindEditor
        case .display: displayEditor
        }
    }

    /// 行 → 面板坐标系里的位置。下拉浮层要靠它定位。
    private struct RowAnchorKey: PreferenceKey {
        static let defaultValue: [Row: Anchor<CGRect>] = [:]
        static func reduce(value: inout [Row: Anchor<CGRect>],
                           nextValue: () -> [Row: Anchor<CGRect>]) {
            value.merge(nextValue()) { _, new in new }
        }
    }

    /// 弹层外壳。
    ///
    /// 参考图里下拉是**浮在面板上的弹框**：与行同宽、带圆角边框和投影，盖住下面的行。
    /// 原来是行内展开（会把面板撑高、把底部按钮推走），用户明确指出「不是弹框、还把
    /// 编辑框撑大了、边框也没有」，所以改成 overlay。
    private func popup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.vertical, WFSpace.xs)
            .frame(maxWidth: .infinity)
            .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).stroke(WFColors.border)
            }
            .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    }

    // MARK: 名称

    private var nameRow: some View {
        HStack(spacing: WFSpace.lg) {
            ZStack {
                Circle().fill(countdownEditorColor(colorIndex))
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .overlay(alignment: .bottomTrailing) {
                // 参考图里图标右下角挂着一支小铅笔（表示「点它换图标/颜色」）。
                Image(systemName: "pencil")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(WFColors.secondaryText)
                    .frame(width: 13, height: 13)
                    .background(WFColors.canvas, in: Circle())
                    .overlay { Circle().stroke(WFColors.border) }
            }

            TextField(kind.namePlaceholder, text: $name)
                .textFieldStyle(.plain)
                .font(WFType.body)
                .padding(.horizontal, WFSpace.sm)
                .frame(height: Self.rowHeight)
                .background(WFColors.content, in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                .overlay {
                    RoundedRectangle(cornerRadius: WFMetrics.corner).stroke(WFColors.border)
                }
                .onSubmit { if canSubmit { submit() } }

            // 参考图里输入框右端有个小方块图标按钮。它对应的行为在图上不可见，
            // 这里接成「备注」的展开开关——否则整页没有写备注的入口。
            Button {
                noteExpanded.toggle()
            } label: {
                Image(systemName: "note.text")
                    .font(.system(size: 13))
                    .foregroundStyle(noteExpanded ? WFColors.accent : WFColors.secondaryText)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("备注")
            .accessibilityLabel("备注")
        }
    }

    private var noteField: some View {
        TextField("备注", text: $note, axis: .vertical)
            .textFieldStyle(.plain)
            .font(WFType.supporting)
            .lineLimit(2...4)
            .padding(WFSpace.sm)
            .background(WFColors.content, in: RoundedRectangle(cornerRadius: WFMetrics.corner))
            .overlay {
                RoundedRectangle(cornerRadius: WFMetrics.corner).stroke(WFColors.border)
            }
    }

    // MARK: 属性行

    private func propertyRow(_ row: Row, label: String, value: String, isPlaceholder: Bool) -> some View {
        HStack(spacing: WFSpace.inline) {
            Text(label)
                .font(WFType.supporting)
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: Self.labelWidth, alignment: .leading)
            Button {
                let next: Row? = openRow == row ? nil : row
                // 每次打开日期浮层都回到已选那天所在的月份，别停在上次翻到的地方。
                if next == .date { displayedMonth = pickedDate ?? Date() }
                openRow = next
            } label: {
                HStack(spacing: WFSpace.xs) {
                    Text(value)
                        .font(WFType.supporting)
                        .foregroundStyle(isPlaceholder ? WFColors.tertiaryText : WFColors.text)
                        .lineLimit(1)
                    Spacer(minLength: WFSpace.xs)
                    Image(systemName: openRow == row ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WFColors.tertiaryText)
                }
                .padding(.horizontal, WFSpace.sm)
                .frame(height: Self.rowHeight)
                .frame(maxWidth: .infinity)
                .background(WFColors.content, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6).stroke(WFColors.border)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label)：\(value)")
        }
        // 下拉浮层按这一行的位置定位。
        .anchorPreference(key: RowAnchorKey.self, value: .bounds) { [row: $0] }
    }

    private var dateRow: some View {
        propertyRow(.date, label: "日期",
                    value: dateText ?? "选择日期", isPlaceholder: dateText == nil)
    }

    @ViewBuilder
    private var dateEditor: some View {
        if kind.usesFestivalCatalog {
            // 节日走目录：选项自带农历/公历规则，不需要用户自己挑日子。
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(CountdownFestival.all) { option in
                        optionRow(option.name, checked: pickedFestival?.name == option.name) {
                            pickedFestival = option
                            // 名称还空着就顺手填上节日名：选了「春节」再手打一遍
                            // 「春节」是白费一次输入。只在空的时候填，不会覆盖用户写的。
                            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                name = option.name
                            }
                            openRow = nil
                        }
                    }
                }
            }
            .frame(height: 180)
        } else {
            // 用**项目自己的月历**（`LunarMonthGridView`，任务面板的日期浮层也是它），
            // 不用系统 `DatePicker`：系统那个不显示农历与节日，而倒数纪念日恰恰是
            // 农历语义最重的地方（春节落在正月初一），两者对不上。月历还自带
            // 今天圆环 / 选中实心点 / 月份导航，与任务侧是同一套观感。
            LunarMonthGridView(
                calendar: calendar,
                displayedMonth: $displayedMonth,
                today: calendar.startOfDay(for: Date()),
                selection: pickedDate,
                // 点一天即定案并收起浮层——与 `TaskDatePopoverV2` 里
                // `model.select(day); closeSheet()` 同一口径。
                onSelect: { date in
                    pickedDate = date
                    openRow = nil
                }
            )
            .frame(maxWidth: .infinity)
        }
    }

    /// 「提醒」行。参考图里空集显示的是黑色的「无」，不是灰色占位。
    private var reminderRow: some View {
        propertyRow(.reminder, label: "提醒",
                    value: CountdownEvent.reminderText(Array(reminders)) ?? "无",
                    isPlaceholder: false)
    }

    /// 「提醒」下拉，照参考图：
    /// `无 / 当天 (09:00) / 提前 1 天 (09:00) / 提前 2 天 (09:00) /
    ///  提前 3 天 (09:00) / 提前 1 周 (09:00)` ── `自定义`。
    ///
    /// 「无」= 空集；中间几项是**多选**（参考图的「添加」面板实测默认值是
    /// `当天, 提前 3 天` 两条，所以不是单选）。
    private var reminderEditor: some View {
        VStack(spacing: 0) {
            optionRow("无", checked: reminders.isEmpty) {
                reminders.removeAll()
                openRow = nil
            }
            ForEach(CountdownEvent.reminderChoices, id: \.self) { minutes in
                optionRow(CountdownEvent.reminderOptionLabel(minutes),
                          checked: reminders.contains(minutes)) {
                    if !reminders.insert(minutes).inserted { reminders.remove(minutes) }
                }
            }
            optionSeparator
            optionRow("自定义", checked: isCustomReminder) {
                reminders = [customReminderDays * CountdownEvent.minutesPerDay]
            }
            if isCustomReminder {
                Stepper(value: $customReminderDays, in: 1...365) {
                    Text("提前 \(customReminderDays) 天 (\(CountdownEvent.reminderTimeText))")
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.text)
                }
                .font(WFType.supporting)
                .padding(.horizontal, WFSpace.sm)
                .frame(height: Self.popupRowHeight)
                .onChange(of: customReminderDays) { _, days in
                    reminders = [days * CountdownEvent.minutesPerDay]
                }
            }
        }
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 6))
    }

    /// 选中了预设项以外的整天提醒，就算「自定义」。
    private var isCustomReminder: Bool {
        let presets = Set(CountdownEvent.reminderChoices)
        return reminders.contains { !presets.contains($0) }
    }

    private var optionSeparator: some View {
        Divider().padding(.vertical, 2)
    }

    /// 「重复」行。参考图里的值是带括注的：`每周（周二）` / `每月（初一）` / `每年（正月初一）`。
    private var repeatRow: some View {
        propertyRow(.recurrence, label: "重复",
                    value: repeatLabel(repeatSelection),
                    isPlaceholder: false)
    }

    /// 括注是算出来的（见 `CountdownRepeat.label`）。规则优先用面板里**当前**的
    /// 选择，编辑时退回原记录——不然刚换完日期，括注还停在旧锚点上。
    private func repeatLabel(_ value: CountdownRepeat) -> String {
        CountdownRepeat.label(value, rule: resolvedRule ?? original?.rule,
                              asOf: Date(), calendar: calendar)
    }

    /// 「重复」下拉，照参考图：
    /// `无 / 每天 / 每周（周二）/ 每月（初一）/ 每年（正月初一）` ── `自定义`。
    ///
    /// 「自定义」在参考图里点开会是什么样**没有截图**，这里是自定的最小实现
    /// （「每 N 天」的步进器），属于**取舍**，不是对齐结果。
    private var repeatEditor: some View {
        VStack(spacing: 0) {
            ForEach(CountdownRepeat.allCases) { option in
                if option == .custom { optionSeparator }
                optionRow(repeatLabel(option), checked: repeatSelection == option) {
                    repeatSelection = option
                    openRow = nil
                }
            }
            if repeatSelection == .custom {
                Stepper(value: $customIntervalDays, in: 1...365) {
                    Text("每 \(customIntervalDays) 天")
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.text)
                }
                .font(WFType.supporting)
                .padding(.horizontal, WFSpace.sm)
                .frame(height: Self.popupRowHeight)
            }
        }
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 6))
    }

    private var kindRow: some View {
        propertyRow(.kind, label: "类型", value: kind.title, isPlaceholder: false)
    }

    private var kindEditor: some View {
        VStack(spacing: 0) {
            ForEach(CountdownKind.allCases) { option in
                optionRow(option.title, checked: kind == option) {
                    applyKind(option)
                    openRow = nil
                }
            }
        }
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 6))
    }

    private var displayRow: some View {
        propertyRow(.display, label: "显示", value: smartListDisplay.rowText, isPlaceholder: false)
    }

    /// 「显示」下拉：一个「在智能清单中」分组标题，下面五项
    /// （当天显示 / 提前 3 天显示 / 提前 7 天显示 / 一直显示 / 不显示）。
    private var displayEditor: some View {
        VStack(spacing: 0) {
            Text(CountdownSmartListDisplay.groupTitle)
                .font(WFType.caption)
                .foregroundStyle(WFColors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WFSpace.sm)
                .padding(.top, WFSpace.sm)
                .padding(.bottom, WFSpace.xs)
            ForEach(CountdownSmartListDisplay.allCases) { option in
                optionRow(option.title, checked: smartListDisplay == option) {
                    smartListDisplay = option
                    openRow = nil
                }
            }
        }
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 6))
    }

    /// 「显示岁数」这一行参考图里是**开关在左、文字在右**（和上面几行
    /// 「标签在左、控件在右」正好相反），而且开关落在标签列上、不再缩进。
    private var ageRow: some View {
        HStack(spacing: WFSpace.sm) {
            Toggle("", isOn: $showsAge)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel("显示岁数")
            Text("显示岁数")
                .font(WFType.supporting)
                .foregroundStyle(WFColors.text)
            Spacer(minLength: 0)
        }
        .frame(height: Self.rowHeight)
    }

    private func optionRow(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: WFSpace.sm) {
                Text(title).font(WFType.supporting).lineLimit(1)
                Spacer(minLength: WFSpace.xs)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WFColors.accent)
                }
            }
            .foregroundStyle(WFColors.text)
            .padding(.horizontal, WFSpace.sm)
            .frame(height: Self.popupRowHeight)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: Self.rowGap) {
            Spacer()
            // 宽度得给到 label 上：`.frame(minWidth:)` 加在 Button 外面只撑布局框，
            // 撑不开 `.bordered` 自己画的那颗胶囊（实测仍是 54 宽）。
            Button { dismiss() } label: {
                Text("取消").frame(width: Self.buttonWidth - 24, height: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Button { submit() } label: {
                // 参考图：新建面板的确认按钮是「添加」，编辑面板是「确定」。
                Text(isNew ? "添加" : "确定").frame(width: Self.buttonWidth - 24, height: 20)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSubmit)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 32)
    }

    // MARK: 派生

    /// 「日期」行显示的文本。节日取目录里那条规则的日期写法（`农历正月初一`），
    /// 其余是公历日期——参考图里这一行写的是**日期**，不是节日名。
    private var dateText: String? {
        if kind.usesFestivalCatalog {
            return pickedFestival.flatMap { $0.rule.dateText ?? $0.name }
        }
        return pickedDate.map { CountdownEvent.solarText($0, calendar: calendar) }
    }

    /// 提交时的规则：把「日期」与「重复」两行合成一条。
    private var resolvedRule: CountdownRule? {
        if kind.usesFestivalCatalog {
            if let pickedFestival {
                return combinedRule(base: pickedFestival.rule, repeatSelection: repeatSelection)
            }
            // 目录里认不出的农历规则（历史数据）原样保留，免得因为编辑器不认得
            // 就把日期丢了。
            if let rule = original?.rule, rule.isRepeating, CountdownFestival.name(for: rule) == nil {
                return rule
            }
            return nil
        }
        guard let pickedDate else { return nil }
        return combinedRule(base: .once(pickedDate), repeatSelection: repeatSelection)
    }

    /// 把「日期」（`base`）与「重复」合成一条规则。
    ///
    /// `重复 = 每年` 时**原样返回 base**：节日的 `.lunarEve`（除夕）这类规则没法
    /// 从月/日重建，只能留着。其余节奏都要一个锚点——单次日期用日期本身，
    /// 节日用目录规则的下一次落点。
    private func combinedRule(base: CountdownRule, repeatSelection: CountdownRepeat) -> CountdownRule? {
        let anchor: Date
        let lunar: Bool
        switch base {
        case .once(let date):
            anchor = date
            lunar = false
        case .lunarYearly, .lunarEve:
            anchor = nextOccurrence(of: base)
            lunar = true
        default:
            anchor = nextOccurrence(of: base)
            lunar = false
        }
        switch repeatSelection {
        case .never:
            return .once(anchor)
        case .daily:
            return .daily(lunar: lunar, anchor: anchor)
        case .weekly:
            // 参考图的括注也是「今天」的星期（见 `CountdownRepeat.label`），
            // 这里让规则与括注指向同一天，免得两处各说各话。
            return .weekly(weekday: calendar.component(.weekday, from: Date()),
                           lunar: lunar, anchor: anchor)
        case .monthly:
            let day = lunar
                ? (CountdownLunar.lunarComponents(of: anchor, calendar: calendar)?.day ?? 1)
                : (calendar.dateComponents([.day], from: anchor).day ?? 1)
            return .monthly(day: day, lunar: lunar, anchor: anchor)
        case .yearly:
            if case .once(let date) = base {
                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                guard let month = parts.month, let day = parts.day else { return .once(date) }
                // 生日要把出生年一起带上，岁数才算得出来。
                if kind == .birthday, let year = parts.year {
                    return .birthday(month: month, day: day, birthYear: year)
                }
                return .solarYearly(month: month, day: day)
            }
            return base
        case .custom:
            return .interval(days: customIntervalDays, lunar: lunar, anchor: anchor)
        }
    }

    private func nextOccurrence(of rule: CountdownRule) -> Date {
        CountdownEvent.occurrence(of: rule, onOrAfter: Date(), calendar: calendar)
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && resolvedRule != nil
    }

    /// 切类型：换图标与颜色，并把「重复」带回该类型的默认值。
    /// 日期一律清空——参考图里换完类型「日期」仍是「选择日期」，
    /// 而且公历日期与农历节日本来就不是同一套落点，留着上一个只会误导。
    private func applyKind(_ next: CountdownKind) {
        kind = next
        symbol = next.defaultSymbol
        colorIndex = next.defaultColorIndex
        repeatSelection = next.defaultRepeat
        pickedFestival = nil
        pickedDate = nil
    }

    private func submit() {
        guard let rule = resolvedRule else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if var original {
            original.name = trimmed
            original.kind = kind
            original.rule = rule
            original.symbol = symbol
            original.colorIndex = colorIndex
            original.reminderOffsets = Array(reminders)
            original.smartListDisplay = smartListDisplay
            // 老字段跟着新字段走，存量读的是它。
            original.showsInSmartList = smartListDisplay.showsInSmartList
            original.showsAge = showsAge
            original.note = note
            store.update(original)
        } else {
            store.add(name: trimmed, kind: kind, rule: rule, symbol: symbol, colorIndex: colorIndex,
                      reminderOffsets: Array(reminders),
                      smartListDisplay: smartListDisplay,
                      showsAge: showsAge, note: note)
        }
        dismiss()
    }
}

// MARK: - 样式

/// 卡片菜单「样式」：只改符号与颜色，点即生效。参考图里这一项的界面不可见，
/// 这里是自定的最小实现（顺带补上了添加面板里那个改不了图标的缺口）。
struct CountdownStyleView: View {
    @ObservedObject var store: CountdownStore
    let event: CountdownEvent

    @Environment(\.dismiss) private var dismiss
    @State private var symbol: String
    @State private var colorIndex: Int

    init(store: CountdownStore, event: CountdownEvent) {
        self.store = store
        self.event = event
        _symbol = State(initialValue: event.safeSymbol)
        _colorIndex = State(initialValue: event.colorIndex)
    }

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: WFSpace.sm), count: 6)

    var body: some View {
        VStack(spacing: 0) {
            Text("样式").font(.system(size: 14, weight: .semibold)).padding(.vertical, WFSpace.md)
            Divider()
            VStack(alignment: .leading, spacing: WFSpace.md) {
                HStack(spacing: WFSpace.sm) {
                    ZStack {
                        Circle().fill(countdownEditorColor(colorIndex))
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 30, height: 30)
                    Text(event.displayName).font(WFType.body).lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text("颜色").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                HStack(spacing: WFSpace.sm) {
                    ForEach(0..<CountdownEvent.paletteSize, id: \.self) { index in
                        Button {
                            colorIndex = index
                            apply()
                        } label: {
                            ZStack {
                                Circle().fill(countdownEditorColor(index)).frame(width: 22, height: 22)
                                if index == colorIndex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("颜色 \(index + 1)")
                    }
                    Spacer(minLength: 0)
                }
                Text("图标").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                LazyVGrid(columns: columns, spacing: WFSpace.sm) {
                    ForEach(CountdownEvent.symbolOptions, id: \.self) { option in
                        Button {
                            symbol = option
                            apply()
                        } label: {
                            Image(systemName: option)
                                .font(.system(size: 14))
                                .foregroundStyle(option == symbol ? WFColors.accent : WFColors.secondaryText)
                                .frame(width: 34, height: 30)
                                .background(option == symbol ? WFColors.selection : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option)
                    }
                }
            }
            .padding(WFSpace.xl)
            Divider()
            HStack {
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .padding(WFSpace.lg)
        }
        .frame(width: 320)
        .background(WFColors.canvas)
    }

    private func apply() {
        store.setStyle(event.id, symbol: symbol, colorIndex: colorIndex)
    }
}

// MARK: - 备注

/// 卡片菜单「备注」。
struct CountdownNoteView: View {
    @ObservedObject var store: CountdownStore
    let event: CountdownEvent

    @Environment(\.dismiss) private var dismiss
    @State private var note: String

    init(store: CountdownStore, event: CountdownEvent) {
        self.store = store
        self.event = event
        _note = State(initialValue: event.note)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("备注").font(.system(size: 14, weight: .semibold)).padding(.vertical, WFSpace.md)
            Divider()
            TextField("写点什么…", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(WFType.body)
                .lineLimit(6...12)
                .padding(WFSpace.md)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(WFColors.content, in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                .overlay {
                    RoundedRectangle(cornerRadius: WFMetrics.corner).stroke(WFColors.border)
                }
                .padding(WFSpace.xl)
            Divider()
            HStack(spacing: WFSpace.sm) {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(.bordered)
                Button("保存") {
                    store.setNote(event.id, note: note)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(WFSpace.lg)
        }
        .frame(width: 360)
        .background(WFColors.canvas)
    }
}

// MARK: - 已归档

/// 页头「更多 → 已归档」：恢复或彻底删除。
struct ArchivedCountdownsView: View {
    @ObservedObject var store: CountdownStore

    @Environment(\.dismiss) private var dismiss
    @State private var today = Date()

    var body: some View {
        VStack(spacing: 0) {
            // 参照物语言包：`archived_countdowns` = 已归档倒数纪念日
            Text("已归档倒数纪念日").font(.system(size: 14, weight: .semibold)).padding(.vertical, WFSpace.md)
            Divider()
            if store.archivedEvents.isEmpty {
                VStack(spacing: WFSpace.sm) {
                    // `no_archived_countdowns_dida` = 还没有已归档的纪念日
                    Text("还没有已归档的纪念日").font(WFType.body)
                }
                .foregroundStyle(WFColors.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.archivedEvents) { event in
                            row(event)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
            Divider()
            HStack {
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .padding(WFSpace.lg)
        }
        .frame(width: 380)
        .background(WFColors.canvas)
        .onAppear { today = Date() }
    }

    private func row(_ event: CountdownEvent) -> some View {
        let projection = event.projection(asOf: today)
        return HStack(spacing: WFSpace.sm) {
            ZStack {
                Circle().fill(countdownEditorColor(event.colorIndex))
                Image(systemName: event.safeSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.displayName).font(WFType.listTitle).lineLimit(1)
                Text(projection.caption).font(WFType.caption)
                    .foregroundStyle(WFColors.secondaryText).lineLimit(1)
            }
            Spacer(minLength: WFSpace.sm)
            Button("恢复") { store.restore(event.id) }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("删除") {
                if TaskNamePrompt.confirm("删除“\(event.displayName)”？", message: "删除后无法恢复。") {
                    _ = store.hardDelete(event.id)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, WFSpace.lg)
        .padding(.vertical, WFSpace.sm)
    }
}
