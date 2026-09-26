import SwiftUI

/// 固定色板：与 `Habit.paletteSize`（Domain 白名单约定）数量保持一致。
private let habitPalette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]

/// 色板下标安全取色（负数/越界自动回绕）。
private func habitPaletteColor(_ index: Int) -> Color {
    let count = max(habitPalette.count, 1)
    return habitPalette[((index % count) + count) % count]
}

/// 空名称时的展示兜底。
private func habitDisplayName(_ habit: Habit) -> String {
    habit.name.isEmpty ? "未命名习惯" : habit.name
}

/// 纯展示逻辑（由 `HabitViewLogicTests` 覆盖）：页头概览文案、打卡日历日期数组、
/// 统计行文案。文案对齐滴答习惯页（"今日 x/y"、"打卡记录"、"打卡率"）。
enum HabitViewLogic {
    /// 页头轻量概览："今日 x/y · 连续最长 N 天"。
    static func overviewText(todayDone: Int, todayTotal: Int, longestStreak: Int) -> String {
        "今日 \(todayDone)/\(todayTotal) · 连续最长 \(longestStreak) 天"
    }

    /// 打卡日历的日期数组：周一为第一列，当月 1 日之前的位置用 nil 占位，
    /// 之后按天给出当月每一天（均取当天零点）。
    static func monthDates(inMonthOf anchor: Date, calendar: Calendar) -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: anchor),
              let dayCount = calendar.range(of: .day, in: .month, for: anchor)?.count
        else { return [] }
        let firstDay = calendar.startOfDay(for: monthInterval.start)
        // weekday 1 = 周日 → 6 个占位；2 = 周一 → 0 个占位。
        let leadingBlanks = (calendar.component(.weekday, from: firstDay) + 5) % 7
        var dates: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for offset in 0..<dayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { break }
            dates.append(day)
        }
        return dates
    }

    /// 详情统计行："共打卡 N 次 · 连续 M 天 · 本月打卡率 P%"。
    static func statsText(totalCheckIns: Int, currentStreak: Int, monthRate: String) -> String {
        "共打卡 \(totalCheckIns) 次 · 连续 \(currentStreak) 天 · 本月打卡率 \(monthRate)"
    }

    /// 打卡率百分比文案；区间内没有计划日时显示 "—"。
    static func monthRateText(checked: Int, scheduled: Int) -> String {
        guard scheduled > 0 else { return "—" }
        return "\(Int((Double(checked) / Double(scheduled) * 100).rounded()))%"
    }
}

/// Wave 1 (F2) 习惯打卡工作区（滴答式布局）：一行页头 + 轻量概览文字 +
/// 今日习惯小卡片流，点击卡片在右侧/下方展开该习惯的打卡日历与统计；
/// 打卡日志、新建/编辑、已归档习惯均收进 sheet。保持 `init(store:)` 不变。
struct HabitsWorkspaceView: View {
    @ObservedObject var store: HabitStore

    @State private var today = Date()
    @State private var sheet: SheetPresentation?
    @State private var selectedHabitID: UUID?

    private var calendar: Calendar { .current }
    private var todayKey: String { Habit.dayKey(today, calendar: calendar) }

    private static let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]
    /// 打卡日历表头（周一开头，与 `HabitViewLogic.monthDates` 的列序一致）。
    private static let calendarWeekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

    /// 一次 sheet 弹出的目标：新建/编辑/打卡日志/打卡后快速心得/已归档。id 在展示期间保持稳定。
    private enum SheetPresentation: Identifiable {
        case create
        case edit(Habit)
        case log(Habit)
        case quickNote(Habit)
        case archived

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let habit): return "edit-\(habit.id)"
            case .log(let habit): return "log-\(habit.id)"
            case .quickNote(let habit): return "quick-note-\(habit.id)"
            case .archived: return "archived"
            }
        }
    }

    init(store: HabitStore) {
        self.store = store
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: WFSpace.md) {
                header
                overviewLine
                mainContent(availableWidth: proxy.size.width)
            }
            .padding(WFSpace.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(WFColors.canvas)
        }
        .onAppear {
            today = Date()
            store.refresh()
        }
        .sheet(item: $sheet) { present in
            switch present {
            case .create:
                HabitEditorView(store: store, original: nil)
            case .edit(let habit):
                HabitEditorView(store: store, original: habit)
            case .log(let habit):
                HabitLogView(store: store, habit: habit)
            case .quickNote(let habit):
                HabitQuickNoteView(store: store, habit: habit, dayKey: todayKey)
            case .archived:
                ArchivedHabitsSheet(store: store)
            }
        }
    }

    // MARK: 页头与概览

    private var header: some View {
        HStack(spacing: WFSpace.sm) {
            Text("习惯").font(WFType.pageTitle)
            Spacer()
            moreMenu
            newHabitButton
        }
    }

    /// 右上角"…"管理菜单：新建入口与已归档习惯 sheet。
    private var moreMenu: some View {
        Menu {
            Button { sheet = .create } label: {
                Label("新建习惯", systemImage: "plus")
            }
            Button { sheet = .archived } label: {
                Label(
                    store.archivedHabits.isEmpty
                        ? "已归档习惯"
                        : "已归档习惯（\(store.archivedHabits.count)）",
                    systemImage: "archivebox")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("新建 / 已归档习惯")
    }

    private var newHabitButton: some View {
        Button { sheet = .create } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 26, height: 26)
                .background(WFColors.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .help("新建习惯")
    }

    /// 轻量概览：日期 + "今日 x/y · 连续最长 N 天"，其下只保留一条细进度线。
    private var overviewLine: some View {
        let overview = HabitViewLogic.overviewText(
            todayDone: todayDone, todayTotal: todayTotal, longestStreak: longestStreak)
        return VStack(alignment: .leading, spacing: WFSpace.sm) {
            Text("\(shortDateText) · \(overview)")
                .font(WFType.supporting)
                .foregroundStyle(WFColors.secondaryText)
            if todayTotal > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(WFColors.selection)
                        Capsule()
                            .fill(WFColors.accent)
                            .frame(width: geo.size.width * CGFloat(todayDone) / CGFloat(todayTotal))
                    }
                }
                .frame(height: 3)
                .animation(.easeInOut(duration: 0.25), value: todayDone)
            }
        }
    }

    private var shortDateText: String {
        let parts = calendar.dateComponents([.month, .day, .weekday], from: today)
        let weekday = Self.weekdayNames[(parts.weekday ?? 1) - 1]
        return "\(parts.month ?? 0)月\(parts.day ?? 0)日 周\(weekday)"
    }

    // MARK: 主体（卡片流 + 详情，宽窗口并排、窄窗口上下）

    @ViewBuilder
    private func mainContent(availableWidth width: CGFloat) -> some View {
        // 详情面板 300 + 间距 20 + 卡片至少两列 → 720 以下改为上下排布。
        let showsSideDetail = selectedHabit != nil && width >= 720
        ScrollView {
            VStack(alignment: .leading, spacing: WFSpace.lg) {
                if showsSideDetail, let habit = selectedHabit {
                    HStack(alignment: .top, spacing: WFSpace.xl) {
                        todayColumn
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        detailPanel(habit)
                            .frame(width: 300)
                    }
                } else {
                    todayColumn
                    if let habit = selectedHabit {
                        detailPanel(habit)
                            .frame(maxWidth: 320, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var todayColumn: some View {
        if store.habits.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: WFSpace.sm) {
                todaySectionHeader
                if store.todaysHabits.isEmpty {
                    noTodayHint
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: WFSpace.md)],
                        spacing: WFSpace.md
                    ) {
                        ForEach(store.todaysHabits) { habit in
                            habitCard(habit)
                        }
                    }
                }
            }
        }
    }

    private var todaySectionHeader: some View {
        HStack(spacing: WFSpace.sm) {
            Text("今日习惯").font(WFType.section)
            if isAllDone {
                Label("今天的习惯都完成了", systemImage: "checkmark.seal.fill")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.accent)
            }
        }
    }

    // MARK: 今日习惯小卡片

    private func habitCard(_ habit: Habit) -> some View {
        let color = habitPaletteColor(habit.colorIndex)
        let checked = store.isChecked(habit.id, dayKey: todayKey)
        let isSelected = selectedHabitID == habit.id
        let streak = store.currentStreak(of: habit)
        return VStack(alignment: .leading, spacing: WFSpace.sm) {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: habit.safeSymbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(checked ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: 7))
                Spacer()
                if streak > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                        Text("\(streak)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.orange)
                }
            }
            Text(habitDisplayName(habit))
                .font(WFType.listTitle)
                .foregroundStyle(checked ? WFColors.secondaryText : WFColors.text)
                .lineLimit(1)
            HStack(spacing: WFSpace.sm) {
                Text(checked ? "已打卡" : scheduleText(habit))
                    .font(WFType.supporting)
                    .foregroundStyle(checked ? color : WFColors.tertiaryText)
                Spacer()
                checkInButton(habit, color: color, checked: checked)
            }
        }
        .padding(WFSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            checked ? color.opacity(0.10) : WFColors.content,
            in: RoundedRectangle(cornerRadius: WFMetrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: WFMetrics.corner)
                .strokeBorder(
                    isSelected ? WFColors.accent : checked ? color.opacity(0.35) : WFColors.border,
                    lineWidth: isSelected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: WFMetrics.corner))
        .onTapGesture {
            selectedHabitID = isSelected ? nil : habit.id
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: checked)
        .contextMenu {
            Button { sheet = .edit(habit) } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button { sheet = .log(habit) } label: {
                Label("查看日志", systemImage: "list.bullet.rectangle")
            }
            Divider()
            Button { store.archive(habit.id) } label: {
                Label("归档", systemImage: "archivebox")
            }
        }
        .help("点击习惯标题查看详情")
    }

    /// 打卡大圆钮：未打卡为圆环，已打卡为实心加对勾；打卡后自动弹出心得 sheet（可跳过）。
    private func checkInButton(_ habit: Habit, color: Color, checked: Bool) -> some View {
        Button {
            let wasChecked = store.isChecked(habit.id, dayKey: todayKey)
            store.toggleCheckIn(habit.id, dayKey: todayKey)
            if !wasChecked {
                sheet = .quickNote(habit)
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(checked ? color : color.opacity(0.45), lineWidth: 2)
                if checked {
                    Circle().fill(color).padding(3)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .help(checked ? "取消打卡" : "打卡")
    }

    /// 计划日摘要文案；空计划 = 每天。展示顺序为周一到周日。
    private func scheduleText(_ habit: Habit) -> String {
        guard !habit.scheduleDays.isEmpty else { return "每天" }
        let order = { (weekday: Int) in (weekday + 5) % 7 }  // 周一为 0，周日为 6
        return habit.scheduleDays
            .sorted { order($0) < order($1) }
            .map { "周\(Self.weekdayNames[$0 - 1])" }
            .joined(separator: "、")
    }

    // MARK: 选中习惯详情（打卡日历 + 统计）

    private var selectedHabit: Habit? {
        guard let id = selectedHabitID else { return nil }
        return store.habits.first { $0.id == id }
    }

    private var todayTotal: Int { store.todaysHabits.count }
    private var todayDone: Int {
        store.todaysHabits.filter { store.isChecked($0.id, dayKey: todayKey) }.count
    }
    private var isAllDone: Bool { todayTotal > 0 && todayDone == todayTotal }
    private var longestStreak: Int {
        store.habits.map { store.currentStreak(of: $0) }.max() ?? 0
    }

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
    }

    private var monthLabel: String {
        let parts = calendar.dateComponents([.year, .month], from: today)
        return "\(parts.year ?? 0)年\(parts.month ?? 0)月"
    }

    private func detailPanel(_ habit: Habit) -> some View {
        let color = habitPaletteColor(habit.colorIndex)
        let monthDates = HabitViewLogic.monthDates(inMonthOf: today, calendar: calendar)
        let checkedKeys = Set(store.checkIns.filter { $0.habitID == habit.id }.map(\.dayKey))
        return VStack(alignment: .leading, spacing: WFSpace.md) {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: habit.safeSymbol)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habitDisplayName(habit)).font(WFType.detailTitle)
                    Text(scheduleText(habit))
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText)
                }
                Spacer()
                Button { sheet = .edit(habit) } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(WFColors.secondaryText)
                }
                .buttonStyle(.plain)
                .help("编辑习惯")
                Button { sheet = .log(habit) } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 12))
                        .foregroundStyle(WFColors.secondaryText)
                }
                .buttonStyle(.plain)
                .help("打卡日志")
            }
            Text(HabitViewLogic.statsText(
                totalCheckIns: store.checkIns(for: habit.id).count,
                currentStreak: store.currentStreak(of: habit),
                monthRate: HabitViewLogic.monthRateText(
                    checked: habit.checkedDayCount(
                        from: monthStart, to: today, checkIns: store.checkIns, calendar: calendar),
                    scheduled: habit.scheduledDayCount(from: monthStart, to: today, calendar: calendar))))
                .font(WFType.supporting)
                .foregroundStyle(WFColors.secondaryText)
            Divider()
            Text("打卡记录 · \(monthLabel)")
                .font(WFType.section)
                .foregroundStyle(WFColors.secondaryText)
            monthCalendar(habit, monthDates: monthDates, checkedKeys: checkedKeys, color: color)
        }
        .padding(WFSpace.lg)
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: WFMetrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: WFMetrics.corner)
                .strokeBorder(WFColors.border))
    }

    /// 本月打卡日历：周一开头 7 列，已打卡日期为习惯色实心圆，今天为强调色圆环。
    private func monthCalendar(
        _ habit: Habit, monthDates: [Date?], checkedKeys: Set<String>, color: Color
    ) -> some View {
        VStack(spacing: WFSpace.xs) {
            HStack(spacing: WFSpace.xs) {
                ForEach(Self.calendarWeekdayNames, id: \.self) { label in
                    Text(label)
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.tertiaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: WFSpace.xs), count: 7),
                spacing: WFSpace.xs
            ) {
                ForEach(monthDates.indices, id: \.self) { index in
                    if let date = monthDates[index] {
                        monthDayCell(habit, date: date, checkedKeys: checkedKeys, color: color)
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }

    private func monthDayCell(
        _ habit: Habit, date: Date, checkedKeys: Set<String>, color: Color
    ) -> some View {
        let day = calendar.component(.day, from: date)
        let checked = checkedKeys.contains(Habit.dayKey(date, calendar: calendar))
        let isToday = calendar.isDate(date, inSameDayAs: today)
        let isFuture = calendar.startOfDay(for: date) > calendar.startOfDay(for: today)
        let isScheduled = habit.isScheduled(on: date, calendar: calendar)
        return ZStack {
            if checked {
                Circle().fill(color)
            } else if isToday {
                Circle().strokeBorder(WFColors.accent, lineWidth: 1.5)
            }
            Text("\(day)")
                .font(.system(size: 10, weight: checked ? .semibold : .regular))
                .foregroundStyle(
                    checked ? Color.white
                        : isToday ? WFColors.accent
                        : isFuture ? WFColors.tertiaryText.opacity(0.6)
                        : isScheduled ? WFColors.secondaryText : WFColors.tertiaryText.opacity(0.7))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: WFSpace.md) {
            Image(systemName: "checkmark.seal")
                .font(.largeTitle)
                .foregroundStyle(WFColors.tertiaryText)
            Text("还没有习惯")
                .font(WFType.detailTitle)
            Text("创建一个习惯，每天来打卡坚持吧。")
                .font(WFType.body)
                .foregroundStyle(WFColors.secondaryText)
            Button { sheet = .create } label: {
                Label("新建习惯", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, WFSpace.page)
    }

    /// 有习惯但今天没有计划日时的空状态（文案对齐滴答）。
    private var noTodayHint: some View {
        VStack(spacing: WFSpace.md) {
            Text("今天没有要打卡的习惯哦")
                .font(WFType.body)
                .foregroundStyle(WFColors.secondaryText)
            Button { sheet = .create } label: {
                Label("新建习惯", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, WFSpace.xl)
    }
}

// MARK: - 打卡后快速心得 sheet（可跳过）

private struct HabitQuickNoteView: View {
    @ObservedObject var store: HabitStore
    let habit: Habit
    let dayKey: String
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.md) {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: habit.safeSymbol)
                    .font(.system(size: 16))
                    .foregroundStyle(habitPaletteColor(habit.colorIndex))
                VStack(alignment: .leading, spacing: 2) {
                    Text("打卡成功！记录一下心得吧").font(WFType.detailTitle)
                    Text("\(habitDisplayName(habit)) · \(dayTitle)")
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText)
                }
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft)
                    .font(WFType.body)
                    .frame(height: 88)
                if draft.isEmpty {
                    Text("写点打卡心得，也可以直接跳过")
                        .font(WFType.body)
                        .foregroundStyle(WFColors.tertiaryText)
                        .padding(.top, WFSpace.sm)
                        .padding(.leading, WFSpace.xs)
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Spacer()
                Button("跳过") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存心得") {
                    store.saveNote(habit.id, dayKey: dayKey, note: draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(WFSpace.xl)
        .frame(width: 380, alignment: .topLeading)
        .onAppear {
            draft = store.checkInRecord(habitID: habit.id, dayKey: dayKey)?.note ?? ""
        }
    }

    private var dayTitle: String {
        let current = Calendar.current
        guard let date = Habit.date(fromDayKey: dayKey, calendar: current) else { return dayKey }
        let parts = current.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)月\(parts.day ?? 0)日"
    }
}

// MARK: - 已归档习惯 sheet

private struct ArchivedHabitsSheet: View {
    @ObservedObject var store: HabitStore
    @Environment(\.dismiss) private var dismiss

    @State private var pendingDelete: Habit?

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.md) {
            HStack {
                Text("已归档习惯").font(WFType.detailTitle)
                Spacer()
                Button {
                    dismiss()
                } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .help("关闭")
            }

            if store.archivedHabits.isEmpty {
                VStack(spacing: WFSpace.xs) {
                    Text("还没有已归档的习惯")
                        .font(WFType.body)
                        .foregroundStyle(WFColors.secondaryText)
                    Text("你可以将暂时不再打卡的习惯归档到这儿")
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.tertiaryText)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, WFSpace.page)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.archivedHabits) { habit in
                            archivedRow(habit)
                        }
                    }
                }
            }
        }
        .padding(WFSpace.xl)
        .frame(width: 440, height: 380, alignment: .topLeading)
        .confirmationDialog(
            "删除习惯「\(pendingDelete.map(habitDisplayName) ?? "")」？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("同时删除全部打卡记录", role: .destructive) {
                if let habit = pendingDelete {
                    _ = store.hardDelete(habit.id)
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("该操作不可撤销，将一并删除它的所有打卡记录。")
        }
    }

    private func archivedRow(_ habit: Habit) -> some View {
        HStack(spacing: WFSpace.md) {
            Image(systemName: habit.safeSymbol)
                .font(.system(size: 14))
                .foregroundStyle(habitPaletteColor(habit.colorIndex))
                .frame(width: 20)
            Text(habitDisplayName(habit)).font(WFType.listTitle)
            Spacer()
            Button("恢复") { store.restore(habit.id) }
            Button("删除", role: .destructive) { pendingDelete = habit }
        }
        .padding(.vertical, WFSpace.xs)
    }
}

// MARK: - 新建/编辑 sheet

private struct HabitEditorView: View {
    @ObservedObject var store: HabitStore
    let original: Habit?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var symbol: String
    @State private var colorIndex: Int
    @State private var scheduleDays: Set<Int>

    // 展示顺序为周一到周日；weekday 值 1 = 周日。
    private static let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]
    private static let weekdayValues = [2, 3, 4, 5, 6, 7, 1]

    init(store: HabitStore, original: Habit?) {
        self.store = store
        self.original = original
        _name = State(initialValue: original?.name ?? "")
        _symbol = State(initialValue: original?.safeSymbol ?? Habit.symbolOptions[0])
        _colorIndex = State(initialValue: original?.colorIndex ?? 0)
        _scheduleDays = State(initialValue: Set(original?.scheduleDays ?? []))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.md) {
            Text(original == nil ? "新建习惯" : "编辑习惯").font(WFType.detailTitle)

            VStack(alignment: .leading, spacing: WFSpace.xs) {
                Text("名称")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
                TextField("例如：每天喝够 8 杯水", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: WFSpace.xs) {
                Text("符号")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
                HStack(spacing: WFSpace.sm) {
                    ForEach(Habit.symbolOptions, id: \.self) { option in
                        symbolButton(option)
                    }
                }
            }

            VStack(alignment: .leading, spacing: WFSpace.xs) {
                Text("颜色")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
                HStack(spacing: WFSpace.sm) {
                    ForEach(habitPalette.indices, id: \.self) { index in
                        colorButton(index)
                    }
                }
            }

            VStack(alignment: .leading, spacing: WFSpace.xs) {
                Text("计划日")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
                HStack(spacing: WFSpace.xs) {
                    ForEach(Self.weekdayValues.indices, id: \.self) { index in
                        weekdayChip(Self.weekdayValues[index], label: Self.weekdaySymbols[index])
                    }
                }
                Text("全不选表示每天打卡")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.tertiaryText)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(WFSpace.xl)
        .frame(width: 420, alignment: .topLeading)
    }

    private func symbolButton(_ option: String) -> some View {
        let selected = symbol == option
        return Button {
            symbol = option
        } label: {
            Image(systemName: option)
                .font(.system(size: 13))
                .frame(width: 28, height: 28)
                .foregroundStyle(selected ? Color.white : WFColors.text)
                .background(
                    selected ? habitPaletteColor(colorIndex) : WFColors.secondarySurface,
                    in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                .overlay(
                    RoundedRectangle(cornerRadius: WFMetrics.corner)
                        .strokeBorder(WFColors.border))
        }
        .buttonStyle(.plain)
        .help(option)
    }

    private func colorButton(_ index: Int) -> some View {
        let selected = colorIndex == index
        return Button {
            colorIndex = index
        } label: {
            Circle()
                .fill(habitPalette[index])
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .strokeBorder(selected ? WFColors.text : .clear, lineWidth: 2)
                        .padding(2))
        }
        .buttonStyle(.plain)
    }

    private func weekdayChip(_ value: Int, label: String) -> some View {
        let selected = scheduleDays.contains(value)
        return Button {
            if selected {
                scheduleDays.remove(value)
            } else {
                scheduleDays.insert(value)
            }
        } label: {
            Text("周\(label)")
                .font(WFType.supporting)
                .padding(.horizontal, WFSpace.sm)
                .padding(.vertical, WFSpace.xs)
                .foregroundStyle(selected ? Color.white : WFColors.text)
                .background(selected ? WFColors.accent : WFColors.secondarySurface, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let days = scheduleDays.sorted()
        if let original {
            store.update(
                original.id, name: trimmed, symbol: symbol,
                colorIndex: colorIndex, scheduleDays: days)
        } else {
            _ = store.add(name: trimmed, symbol: symbol, colorIndex: colorIndex, scheduleDays: days)
        }
        dismiss()
    }
}

// MARK: - 打卡日志 sheet

private struct HabitLogView: View {
    @ObservedObject var store: HabitStore
    let habit: Habit
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDayKey = ""
    @State private var draft = ""

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.md) {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: habit.safeSymbol)
                    .foregroundStyle(habitPaletteColor(habit.colorIndex))
                Text("\(habitDisplayName(habit)) · 打卡日志").font(WFType.detailTitle)
                Spacer()
                Button {
                    dismiss()
                } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .help("关闭")
            }

            VStack(alignment: .leading, spacing: WFSpace.xs) {
                HStack {
                    Text(dayTitle(selectedDayKey)).font(WFType.section)
                    Spacer()
                    Button(store.isChecked(habit.id, dayKey: selectedDayKey) ? "取消打卡" : "补打卡") {
                        store.toggleCheckIn(habit.id, dayKey: selectedDayKey)
                    }
                }
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft).font(WFType.body).frame(minHeight: 90)
                    if draft.isEmpty {
                        Text("写点打卡心得，记录今天的完成情况")
                            .font(WFType.body)
                            .foregroundStyle(WFColors.tertiaryText)
                            .padding(.top, WFSpace.sm)
                            .padding(.leading, WFSpace.xs)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 110)
                HStack {
                    Spacer()
                    Button("保存心得") {
                        store.saveNote(habit.id, dayKey: selectedDayKey, note: draft)
                    }
                    .disabled(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            == (store.checkInRecord(habitID: habit.id, dayKey: selectedDayKey)?
                                .note ?? ""))
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: WFSpace.xs) {
                    Text("历史记录").font(WFType.section)
                    let records = store.checkIns(for: habit.id)
                    if records.isEmpty {
                        Text("还没有打卡记录")
                            .font(WFType.supporting)
                            .foregroundStyle(WFColors.secondaryText)
                            .padding(.vertical, WFSpace.lg)
                    }
                    ForEach(records) { record in
                        Button {
                            selectDay(record.dayKey)
                        } label: {
                            logRow(record)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(WFSpace.xl)
        .frame(width: 460, height: 520, alignment: .topLeading)
        .onAppear { selectDay(Habit.dayKey(Date(), calendar: calendar)) }
        .onChange(of: selectedDayKey) { oldKey, _ in
            // 切换日期前把当前心得落库，避免丢字。
            store.saveNote(habit.id, dayKey: oldKey, note: draft)
            draft = store.checkInRecord(habitID: habit.id, dayKey: selectedDayKey)?.note ?? ""
        }
        .onDisappear {
            store.saveNote(habit.id, dayKey: selectedDayKey, note: draft)
        }
    }

    private func selectDay(_ dayKey: String) {
        selectedDayKey = dayKey
        draft = store.checkInRecord(habitID: habit.id, dayKey: dayKey)?.note ?? ""
    }

    private func logRow(_ record: HabitCheckIn) -> some View {
        HStack(alignment: .top, spacing: WFSpace.sm) {
            Circle()
                .fill(habitPaletteColor(habit.colorIndex))
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(dayTitle(record.dayKey))
                        .font(WFType.listTitle)
                        .foregroundStyle(
                            selectedDayKey == record.dayKey ? WFColors.accent : WFColors.text)
                    Spacer()
                    Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.tertiaryText)
                }
                if !record.note.isEmpty {
                    Text(record.note)
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, WFSpace.xs)
        .contentShape(Rectangle())
    }

    private func dayTitle(_ dayKey: String) -> String {
        guard let date = Habit.date(fromDayKey: dayKey, calendar: calendar) else { return dayKey }
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)月\(parts.day ?? 0)日"
    }
}
