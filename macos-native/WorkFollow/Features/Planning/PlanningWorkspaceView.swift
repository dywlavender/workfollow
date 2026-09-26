import SwiftUI

/// 对齐滴答清单 mac 版的低饱和度语义色：四象限红橙蓝绿、清单色板、过期红。
/// 打勾的紫色强调（WFColors.accent）保持不动，这里只补齐滴答的着色维度。
private enum WFPlanningPalette {
    static let quadrant: [Color] = [
        Color(red: 0.90, green: 0.38, blue: 0.40),  // Ⅰ 重要且紧急（红）
        Color(red: 0.94, green: 0.62, blue: 0.28),  // Ⅱ 重要不紧急（橙）
        Color(red: 0.38, green: 0.58, blue: 0.92),  // Ⅲ 不重要但紧急（蓝）
        Color(red: 0.36, green: 0.70, blue: 0.47),  // Ⅳ 不重要不紧急（绿）
    ]
    static let list: [Color] = [
        Color(red: 0.55, green: 0.46, blue: 0.90),  // 紫（与强调色同族）
        Color(red: 0.38, green: 0.58, blue: 0.92),  // 蓝
        Color(red: 0.36, green: 0.70, blue: 0.47),  // 绿
        Color(red: 0.90, green: 0.38, blue: 0.40),  // 红
        Color(red: 0.94, green: 0.62, blue: 0.28),  // 橙
        Color(red: 0.88, green: 0.52, blue: 0.74),  // 粉
        Color(red: 0.40, green: 0.66, blue: 0.86),  // 天蓝
        Color(red: 0.76, green: 0.60, blue: 0.34),  // 棕黄
    ]
    static let overdue = Color(red: 0.90, green: 0.38, blue: 0.40)
}

struct PlanningWorkspaceView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let matrix: Bool
    @State private var anchor: Date
    init(workspace: TaskWorkspaceModel, matrix: Bool) {
        self.workspace = workspace
        self.matrix = matrix
        _anchor = State(initialValue: workspace.clock())
    }
    private enum ViewMode { case month, week, year }
    @State private var mode: ViewMode = .month
    @State private var showCompleted = true
    private let quadrantTitles = ["重要且紧急", "重要不紧急", "不重要但紧急", "不重要不紧急"]
    private let quadrantNumerals = ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ"]
    private var tasks: [Task] {
        workspace.allTasks.filter { $0.deletedAt == nil && $0.skippedAt == nil && !$0.isAbandoned && (showCompleted || !$0.isClosed) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.lg) {
            HStack(spacing: WFSpace.md) {
                Text(matrix ? "四象限" : "日历").font(WFType.pageTitle)
                if !matrix {
                    HStack(spacing: WFSpace.sm) {
                        Button { step(-1) } label: { Image(systemName: "chevron.left") }
                        Text(headerTitle).font(WFType.navigation)
                        Button { step(1) } label: { Image(systemName: "chevron.right") }
                        Button(mode == .year ? "今年" : "今天") { anchor = workspace.clock() }
                    }
                }
                Spacer()
                if !matrix {
                    Picker("视图", selection: $mode) {
                        Text("月").tag(ViewMode.month)
                        Text("周").tag(ViewMode.week)
                        Text("年").tag(ViewMode.year)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented).controlSize(.small).frame(width: 120)
                }
                optionsMenu
            }
            if matrix { matrixBoard } else { calendarBoard }
        }.padding(WFSpace.xl)
            .sheet(isPresented: Binding(get: { workspace.selectedTask != nil }, set: { if !$0 { workspace.select(nil) } })) {
                TaskInspectorShell(workspace: workspace, showBack: true)
                    .frame(minWidth: 340, idealWidth: 560, minHeight: 460, idealHeight: 620)
            }
    }

    /// 头部唯一的入口："…"收纳"显示已完成"开关；四象限另收纳四个添加项，
    /// 象限/日期格内的"+"改为 hover 才出现（对齐滴答）。
    private var optionsMenu: some View {
        Menu {
            Toggle("显示已完成", isOn: $showCompleted)
            if matrix {
                Divider()
                ForEach(0..<4, id: \.self) { quadrant in
                    Button("添加到\(quadrantNumerals[quadrant]) \(quadrantTitles[quadrant])") { addToQuadrant(quadrant) }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("视图选项")
    }

    // MARK: - 四象限

    /// 整页固定 2×2 四张半屏卡片，不整页滚动；任务多时只在卡片任务区滚动。
    private var matrixBoard: some View {
        GeometryReader { geometry in
            if geometry.size.width < 650 {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: WFSpace.lg)], spacing: WFSpace.lg) {
                        ForEach(0..<4, id: \.self) { quadrant in
                            quadrantCard(quadrant, height: 340)
                        }
                    }
                }.background(WFColors.canvas)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: WFSpace.lg), count: 2), spacing: WFSpace.lg) {
                    ForEach(0..<4, id: \.self) { quadrant in
                        quadrantCard(quadrant, height: max(240, (geometry.size.height - WFSpace.lg) / 2))
                    }
                }.background(WFColors.canvas)
            }
        }
    }

    private func quadrantCard(_ quadrant: Int, height: CGFloat) -> some View {
        let values = tasks.filter { PlanningProjection.quadrant($0, now: workspace.clock(), calendar: workspace.calendar) == quadrant }
        return QuadrantCard(
            title: quadrantTitles[quadrant],
            numeral: quadrantNumerals[quadrant],
            color: WFPlanningPalette.quadrant[quadrant],
            tasks: values,
            now: workspace.clock(),
            calendar: workspace.calendar,
            listPalette: WFPlanningPalette.list,
            onToggle: { _ = workspace.changeStatus($0) },
            onSelect: { workspace.select($0) },
            onAdd: { addToQuadrant(quadrant) }
        )
        .frame(height: height)
        .dropDestination(for: String.self) { strings, _ in
            guard let id = strings.first.flatMap(UUID.init(uuidString:)) else { return false }
            moveToQuadrant(id, quadrant)
            return true
        }
    }

    // MARK: - 日历

    @ViewBuilder
    private var calendarBoard: some View {
        if mode == .year {
            yearBoard
        } else if mode == .week {
            weekBoard
        } else {
            monthBoard
        }
    }

    private var headerTitle: String {
        if mode == .year { return "\(workspace.calendar.component(.year, from: anchor))年" }
        return anchor.formatted(.dateTime.year().month(.wide).locale(.appDate))
    }

    /// 年视图：12 个月小网格，色深表示当天任务数量，点击某天回到月视图。
    private var yearBoard: some View {
        GeometryReader { geometry in
            ScrollView {
                let calendar = workspace.calendar
                let year = calendar.component(.year, from: anchor)
                let counts = PlanningProjection.countsByDay(tasks: workspace.allTasks, in: year,
                                                            calendar: calendar, includeCompleted: showCompleted)
                let today = calendar.startOfDay(for: workspace.clock())
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: WFSpace.md),
                                         count: geometry.size.width < 780 ? 2 : 3), spacing: WFSpace.md) {
                    ForEach(PlanningProjection.yearMonths(containing: year, calendar: calendar), id: \.self) { month in
                        yearMonthCard(month, counts: counts, today: today)
                    }
                }
            }.background(WFColors.canvas)
        }
    }

    private func yearMonthCard(_ month: Date, counts: [Date: Int], today: Date) -> some View {
        let weekdays = PlanningProjection.monthDays(containing: month, calendar: workspace.calendar).prefix(7)
        let grid = PlanningProjection.monthGrid(in: month, calendar: workspace.calendar)
        return VStack(alignment: .leading, spacing: WFSpace.sm) {
            Text(month.formatted(.dateTime.month(.wide).locale(.appDate))).font(WFType.section)
            HStack(spacing: WFSpace.xs) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day.formatted(.dateTime.weekday(.abbreviated).locale(.appDate)))
                        .font(.caption2).foregroundStyle(WFColors.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: WFSpace.xs) {
                    ForEach(0..<7, id: \.self) { column in
                        yearDayCell(grid[row * 7 + column], counts: counts, today: today)
                    }
                }
            }
            Spacer(minLength: 0)
        }.padding(WFSpace.md)
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
            .background(WFColors.content, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WFColors.border, lineWidth: 1))
    }

    private func yearDayCell(_ day: Date?, counts: [Date: Int], today: Date) -> some View {
        Group {
            if let day = day {
                let calendar = workspace.calendar
                let count = counts[calendar.startOfDay(for: day)] ?? 0
                let level = PlanningProjection.heatLevel(count: count)
                let isToday = calendar.isDate(day, inSameDayAs: today)
                let cell = Text(day.formatted(.dateTime.day()))
                    .font(.caption2).foregroundStyle(WFColors.text)
                    .frame(maxWidth: .infinity, minHeight: 20)
                    .background(RoundedRectangle(cornerRadius: 4).fill(heatColor(level)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(level == 0 ? WFColors.border : Color.clear, lineWidth: 1))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(WFColors.accent, lineWidth: isToday ? 1.5 : 0))
                    .contentShape(RoundedRectangle(cornerRadius: 4))
                    .onTapGesture { showMonth(containing: day) }
                if count > 0 { cell.help("\(count) 个任务") } else { cell }
            } else {
                Color.clear.frame(maxWidth: .infinity, minHeight: 20)
            }
        }
    }

    private func heatColor(_ level: Int) -> Color {
        switch level {
        case 0: return WFColors.content
        case 1: return WFColors.accent.opacity(0.20)
        case 2: return WFColors.accent.opacity(0.40)
        case 3: return WFColors.accent.opacity(0.65)
        default: return WFColors.accent.opacity(0.90)
        }
    }

    private func showMonth(containing day: Date) {
        anchor = day
        mode = .month
    }

    /// 月视图：灰底周头 + 白底细线日期格，跨天任务渲染为周行内的横跨圆角色带
    /// （lane 布局见 CalendarSpans），单日任务仍是清单着色小条，今天圆点、
    /// hover"+"不变。
    private var monthBoard: some View {
        // 只纵向滚动：横向轴会让网格收缩到最小宽度、两侧留白，
        // 去掉后网格随内容区满宽拉伸（对齐滴答的满宽月视图）。
        ScrollView(.vertical) {
            let days = PlanningProjection.monthDays(containing: anchor, calendar: workspace.calendar)
            VStack(spacing: 1) {
                // 表头用 offset 作 id：与日期格共用 Date id 会把第一周
                // （8/31–9/6 这类跨月格）当作重复身份丢掉。
                HStack(spacing: 1) {
                    ForEach(Array(days.prefix(7).enumerated()), id: \.offset) { _, day in
                        Text(day.formatted(.dateTime.weekday(.abbreviated).locale(.appDate)))
                            .font(.caption).foregroundStyle(WFColors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(WFColors.secondarySurface)
                    }
                }
                ForEach(Array(stride(from: 0, to: days.count, by: 7)), id: \.self) { offset in
                    CalendarMonthRow(
                        calendar: workspace.calendar,
                        today: workspace.clock(),
                        days: Array(days[offset..<offset + 7]),
                        monthReference: anchor,
                        tasks: tasks,
                        listPalette: WFPlanningPalette.list,
                        onSelect: { workspace.select($0) },
                        onAdd: { addOnDate($0) },
                        onDrop: dropTask
                    )
                }
            }
            .frame(minWidth: 620)
            .background(WFColors.border)
        }
    }

    /// 周视图：7 列卡片式日列（白底圆角卡 + 日期头 + 计数徽标），对齐打勾的
    /// 卡式周列；跨天色带同样在卡内渲染（排在单日小条之前），无任务日显示
    /// "没有安排"。整卡是投放目标：单日任务落卡改期，跨天任务平移整个区间。
    private var weekBoard: some View {
        let calendar = workspace.calendar
        let days = PlanningProjection.weekDays(containing: anchor, calendar: calendar)
        let spans = CalendarSpans.lanes(for: days, tasks: tasks, calendar: calendar)
        return HStack(spacing: WFSpace.sm) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                CalendarWeekCard(
                    calendar: calendar,
                    today: workspace.clock(),
                    day: day,
                    dayIndex: index,
                    tasks: tasks,
                    spans: spans,
                    listPalette: WFPlanningPalette.list,
                    onSelect: { workspace.select($0) },
                    onDrop: dropTask
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WFColors.canvas)
    }

    /// 落格改期：单日任务沿用 moveDueDate（只改 dueAt，保留时点）；跨天任务
    /// 平移整个区间——按「目标日 − 原安排日」同时移动 dueAt 与 deadlineAt。
    /// workspace 没有一次改两个字段的 API，用 moveDueDate（比 setDueDate 多
    /// 保留 hasTime）+ setDeadline 组合调用，两次独立写档。
    private func dropTask(_ id: UUID, on day: Date) {
        guard let task = workspace.allTasks.first(where: { $0.id == id }) else { return }
        if let shift = CalendarSpans.intervalShift(task: task, to: day, calendar: workspace.calendar) {
            _ = workspace.moveDueDate(id, to: shift.dueAt)
            _ = workspace.setDeadline(id, shift.deadlineAt)
        } else {
            _ = workspace.moveDueDate(id, to: day)
        }
    }

    private func addOnDate(_ date: Date) {
        guard let id = workspace.createTask(title: "", in: .inbox).taskID else { return }
        _ = workspace.setDueDate(id, date)
        workspace.select(id)
    }
    private func addToQuadrant(_ quadrant: Int) {
        guard let id = workspace.createTask(title: "", in: .inbox).taskID else { return }
        moveToQuadrant(id, quadrant)
        workspace.select(id)
    }
    private func moveToQuadrant(_ id: UUID, _ quadrant: Int) {
        _ = workspace.setPriority(id, quadrant < 2 ? .high : .none)
        _ = workspace.moveDueDate(id, to: quadrant == 0 || quadrant == 2 ? workspace.dateFromToday(0) : workspace.dateFromToday(4))
    }
    private func step(_ amount: Int) {
        let component: Calendar.Component
        switch mode {
        case .year: component = .year
        case .month: component = .month
        case .week: component = .weekOfYear
        }
        anchor = workspace.calendar.date(byAdding: component, value: amount, to: anchor) ?? anchor
    }
}

/// 四象限单卡：彩点序号 + 标题，白底圆角细边；清单分组可折叠，任务行 =
/// 复选框 + 标题 + 右对齐元信息（清单名 + 日期 chip）；"已完成 N"置底灰显。
/// 滚动只发生在任务区（ScrollView 包住分组列表，短内容时"已完成"沉底）。
private struct QuadrantCard: View {
    let title: String
    let numeral: String
    let color: Color
    let tasks: [Task]
    let now: Date
    let calendar: Calendar
    let listPalette: [Color]
    let onToggle: (Task) -> Void
    let onSelect: (UUID) -> Void
    let onAdd: () -> Void

    @State private var hovered = false
    @State private var collapsedLists: Set<String> = []
    @State private var completedCollapsed = false

    private var active: [Task] { tasks.filter { $0.status == .active } }
    private var completed: [Task] { tasks.filter { $0.status == .completed } }
    private var listNames: [String] { Array(Set(active.map { $0.list.name })).sorted() }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: WFSpace.sm) {
                Text(numeral)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(color))
                Text(title).font(WFType.section).foregroundStyle(color)
                Spacer()
                if hovered {
                    Button(action: onAdd) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                    }.buttonStyle(.plain).foregroundStyle(WFColors.secondaryText)
                        .help("添加任务")
                }
            }.padding(.horizontal, WFSpace.lg).padding(.vertical, 10)
            Rectangle().fill(WFColors.border).frame(height: 1)
            if tasks.isEmpty {
                VStack {
                    Spacer()
                    Text("暂无任务").font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                    Spacer()
                }
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(alignment: .leading, spacing: WFSpace.md) {
                            ForEach(listNames, id: \.self) { name in
                                listGroup(name: name, tasks: active.filter { $0.list.name == name })
                            }
                            if !completed.isEmpty {
                                // 紧跟活动分组之后（滴答不做沉底，沉底会造成大空档）。
                                completedGroup
                            }
                        }
                        .padding(WFSpace.md)
                        .padding(.bottom, WFSpace.sm)
                        .frame(minHeight: geometry.size.height, alignment: .topLeading)
                    }
                }
            }
        }
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WFColors.border, lineWidth: 1))
        .onHover { hovered = $0 }
    }

    private func listGroup(name: String, tasks: [Task]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { toggleCollapsed(name) }
            } label: {
                HStack(spacing: WFSpace.xs) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WFColors.tertiaryText)
                        .rotationEffect(.degrees(collapsedLists.contains(name) ? 0 : 90))
                    Text(name).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                    Text("\(tasks.count)").font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                    Spacer()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !collapsedLists.contains(name) {
                ForEach(tasks) { task in taskRow(task) }
            }
        }
    }

    private var completedGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { completedCollapsed.toggle() }
            } label: {
                HStack(spacing: WFSpace.xs) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WFColors.tertiaryText)
                        .rotationEffect(.degrees(completedCollapsed ? 0 : 90))
                    Text("已完成 \(completed.count)").font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                    Spacer()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !completedCollapsed {
                ForEach(completed) { task in taskRow(task) }
            }
        }
    }

    private func taskRow(_ task: Task) -> some View {
        let done = task.status == .completed
        let chipKind = PlanningProjection.dateChipKind(dueAt: task.schedule.dueAt, now: now, calendar: calendar)
        return HStack(spacing: WFSpace.sm) {
            Button { onToggle(task) } label: {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
            }.buttonStyle(.plain)
                .foregroundStyle(done ? WFColors.tertiaryText : WFColors.secondaryText)
            Button { onSelect(task.id) } label: {
                Text(task.title.isEmpty ? "未命名任务" : task.title)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            Text(task.list.name).font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
            if let dueAt = task.schedule.dueAt {
                Text(PlanningProjection.dateChipText(dueAt, hasTime: task.schedule.hasTime, now: now, calendar: calendar))
                    .font(WFType.supporting)
                    .foregroundStyle(done ? WFColors.tertiaryText : chipColor(chipKind))
            }
        }.font(WFType.listTitle)
            .foregroundStyle(done ? WFColors.tertiaryText : WFColors.text)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .draggable(task.id.uuidString)
    }

    /// 滴答规则：过期红、今天强调色、其余灰。
    private func chipColor(_ kind: PlanningProjection.DateChipKind) -> Color {
        switch kind {
        case .overdue: return WFPlanningPalette.overdue
        case .today: return WFColors.accent
        default: return WFColors.secondaryText
        }
    }

    private func toggleCollapsed(_ name: String) {
        if collapsedLists.contains(name) { collapsedLists.remove(name) } else { collapsedLists.insert(name) }
    }
}

/// 月视图的一周行：日期格铺底，跨天色带层绝对定位压在格子上方，竖向细线
/// 压顶（细线穿过色带而非止步于色带，对齐打勾的绘制顺序）。lane 布局按周行
/// 独立计算（CalendarSpans.lanes），格内小条让出被色带占用的槽位。
private struct CalendarMonthRow: View {
    let calendar: Calendar
    let today: Date
    /// 本行的 7 天（列 0 = 周首日，随 firstWeekday）。
    let days: [Date]
    /// 判断格内/格外的参照日（当前月的锚点）。
    let monthReference: Date
    /// 视图已过滤的可见任务（含跨天任务，色带层从中取）。
    let tasks: [Task]
    let listPalette: [Color]
    let onSelect: (UUID) -> Void
    let onAdd: (Date) -> Void
    let onDrop: (UUID, Date) -> Void

    private var spans: [CalendarSpanBar] {
        CalendarSpans.lanes(for: days, tasks: tasks, calendar: calendar)
    }

    var body: some View { content }

    private var content: some View {
        let spans = self.spans
        return HStack(spacing: 1) {
            ForEach(Array(days.enumerated()), id: \.offset) { column, day in
                CalendarDayCell(
                    dayText: String(calendar.component(.day, from: day)),
                    isToday: calendar.isDate(day, inSameDayAs: today),
                    inMonth: calendar.isDate(day, equalTo: monthReference, toGranularity: .month),
                    skipSlots: CalendarSpans.slotsOver(spans, column: column),
                    events: dayEvents(on: day),
                    listPalette: listPalette,
                    onSelect: onSelect,
                    onAdd: { onAdd(day) }
                )
                .frame(minWidth: 120, maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                .dropDestination(for: String.self) { strings, _ in
                    guard let id = strings.first.flatMap(UUID.init(uuidString:)) else { return false }
                    onDrop(id, day)
                    return true
                }
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                let columnWidth = (geometry.size.width - 6) / 7
                ZStack(alignment: .topLeading) {
                    ForEach(spans) { span in
                        spanBand(span, columnWidth: columnWidth)
                    }
                    verticalHairlines(columnWidth: columnWidth)
                }
            }
        }
    }

    /// 单日小条列表：跨天任务整个归色带层，格内不再重复出现。
    private func dayEvents(on day: Date) -> [Task] {
        PlanningProjection.tasks(on: day, from: tasks, calendar: calendar)
            .filter { !CalendarSpans.isMultiDay($0, calendar: calendar) }
    }

    /// 色带定位：left = 列起点 +（未被裁剪端的格内缩进），top = 事件区首行 +
    /// lane × 槽位步进；宽度覆盖本段各列与列间 1pt 细缝，两端各让出格内缩进。
    /// 被周边界裁剪的一端贴到行边缘，让上下两周的色带接得上。
    private func spanBand(_ span: CalendarSpanBar, columnWidth: CGFloat) -> some View {
        let inset = CGFloat(WFSpace.xs)
        let left = CGFloat(span.startDayIndex) * (columnWidth + 1) + (span.startClamped ? 0 : inset)
        let width = CGFloat(span.spanDays) * columnWidth + CGFloat(span.spanDays - 1)
            - (span.startClamped ? 0 : inset) - (span.endClamped ? 0 : inset)
        let top = CalendarDayCell.contentTop + CGFloat(span.laneIndex) * CalendarDayCell.slotStride
        return CalendarSpanBand(span: span, listPalette: listPalette, roundsClippedEdges: false, onSelect: onSelect)
            .frame(width: max(width, 0), height: CalendarDayCell.slotHeight)
            .offset(x: left, y: top)
    }

    /// 竖向细线画在色带之上：色带横跨列间细缝，线若不压顶就会在每条色带处断开。
    private func verticalHairlines(columnWidth: CGFloat) -> some View {
        ForEach(1..<7, id: \.self) { index in
            Rectangle()
                .fill(WFColors.border)
                .frame(width: 1)
                .offset(x: CGFloat(index) * (columnWidth + 1) - 0.5)
        }
    }
}

/// 日历日期格：白底、细线（共享周行的 1pt 间隙 + 边框底色），
/// 今天为强调色圆点，任务按清单着色成圆角小条，"+"仅 hover 显示。
private struct CalendarDayCell: View {
    let dayText: String
    let isToday: Bool
    let inMonth: Bool
    /// 跨天色带在本列占用的槽位数：格内自己的小条从色带之下开始
    /// （色带横穿格子，格子不能占用它的槽位——对齐打勾的 skipSlots）。
    var skipSlots: Int = 0
    let events: [Task]
    let listPalette: [Color]
    let onSelect: (UUID) -> Void
    let onAdd: () -> Void

    /// 小条/色带的标准高度（月格、周卡共用一套规格）。
    static let slotHeight: CGFloat = 18
    /// 相邻槽位的步进 = 小条高度 + 行距。
    static let slotStride: CGFloat = slotHeight + WFSpace.xs
    /// 事件区首行距格顶的距离：格 padding(8) + 日期头(18) + 行距(4)。
    /// 跨天色带的纵向定位依赖这套常量，改动时与色带层一起动。
    static let contentTop: CGFloat = WFSpace.sm + slotHeight + WFSpace.xs

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.xs) {
            HStack(spacing: WFSpace.xs) {
                if isToday {
                    Text(dayText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(WFColors.accent))
                } else {
                    Text(dayText)
                        .font(.system(size: 11))
                        .foregroundStyle(inMonth ? WFColors.text : WFColors.tertiaryText)
                }
                Spacer()
                if hovered {
                    Button(action: onAdd) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .medium))
                    }.buttonStyle(.plain).foregroundStyle(WFColors.secondaryText)
                        .help("添加任务")
                }
            }
            // 日期头固定 18pt：跨天色带的纵向定位以它为锚。
            .frame(height: Self.slotHeight)
            ForEach(0..<skipSlots, id: \.self) { _ in
                Color.clear.frame(height: Self.slotHeight)
            }
            ForEach(events) { event in
                CalendarEventBar(task: event, listPalette: listPalette, onSelect: onSelect)
            }
            Spacer(minLength: 0)
        }
        .padding(WFSpace.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WFColors.content)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

/// 单日任务的清单色小条：一行截断、不做复选框；点击 = 选中打开详情。
/// 月格与周卡片共用，保证两处同规格；周卡片里可拖动改期（月格保持不动，
/// 与打勾一致——月格里的拖放属于网格本身）。
private struct CalendarEventBar: View {
    let task: Task
    let listPalette: [Color]
    let onSelect: (UUID) -> Void
    var isDraggable: Bool = false

    var body: some View {
        let done = task.status == .completed
        let color = listPalette[PlanningProjection.listColorIndex(for: task.list.name)]
        let bar = Button { onSelect(task.id) } label: {
            Text(task.title.isEmpty ? "未命名任务" : task.title)
                .font(.caption2).lineLimit(1)
                .foregroundStyle(done ? WFColors.tertiaryText : color)
                .strikethrough(done, color: WFColors.tertiaryText)
                .padding(.horizontal, WFSpace.xs)
                .frame(maxWidth: .infinity, minHeight: CalendarDayCell.slotHeight, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4).fill(done ? WFColors.hover : color.opacity(0.16)))
        }
        .buttonStyle(.plain)
        Group {
            if isDraggable {
                bar.draggable(task.id.uuidString)
            } else {
                bar
            }
        }
    }
}

/// 跨天色带：清单色 0.16 透明度底 + 同色文字，18pt 高（与单日小条同规格）。
/// 月网格里被周边界裁剪的一端取方角，读起来仍是同一条延续；周卡片里两端
/// 都取圆角。点击选中任务；拖动以任务 id 为负载，落格后按区间整体平移
/// （见 PlanningWorkspaceView.dropTask），而非只挪抓取的那天。
private struct CalendarSpanBand: View {
    let span: CalendarSpanBar
    let listPalette: [Color]
    var roundsClippedEdges: Bool = false
    let onSelect: (UUID) -> Void

    var body: some View {
        let done = span.task.status == .completed
        let color = listPalette[PlanningProjection.listColorIndex(for: span.task.list.name)]
        Button { onSelect(span.task.id) } label: {
            Text(span.task.title.isEmpty ? "未命名任务" : span.task.title)
                .font(.caption2).lineLimit(1)
                .foregroundStyle(done ? WFColors.tertiaryText : color)
                .strikethrough(done, color: WFColors.tertiaryText)
                .padding(.horizontal, WFSpace.xs)
                .frame(maxWidth: .infinity, minHeight: CalendarDayCell.slotHeight, alignment: .leading)
                .background(done ? AnyShapeStyle(WFColors.hover) : AnyShapeStyle(color.opacity(0.16)),
                            in: bandShape)
        }
        .buttonStyle(.plain)
        .draggable(span.task.id.uuidString)
    }

    /// 被裁剪的一端方角、真实端点圆角；周卡片里不做裁剪端区分。
    private var bandShape: AnyShape {
        let corner: CGFloat = 4
        if roundsClippedEdges {
            return AnyShape(RoundedRectangle(cornerRadius: corner))
        }
        return AnyShape(UnevenRoundedRectangle(
            topLeadingRadius: span.startClamped ? 0 : corner,
            bottomLeadingRadius: span.startClamped ? 0 : corner,
            bottomTrailingRadius: span.endClamped ? 0 : corner,
            topTrailingRadius: span.endClamped ? 0 : corner))
    }
}

/// 周视图的一天卡片：白底圆角卡 + 日期头（今天强调色）+ 计数徽标。
/// 色带按 lane 顺序流式排在单日小条之前（卡内不做跨格绝对定位）；
/// 无任务日居中显示"没有安排"。
private struct CalendarWeekCard: View {
    let calendar: Calendar
    let today: Date
    let day: Date
    let dayIndex: Int
    let tasks: [Task]
    let spans: [CalendarSpanBar]
    let listPalette: [Color]
    let onSelect: (UUID) -> Void
    let onDrop: (UUID, Date) -> Void

    /// 本列上方的色带（lane 只决定次序）。
    private var coveringSpans: [CalendarSpanBar] {
        spans.filter { $0.startDayIndex <= dayIndex && dayIndex <= $0.endDayIndex }
    }

    private var dayEvents: [Task] {
        PlanningProjection.tasks(on: day, from: tasks, calendar: calendar)
            .filter { !CalendarSpans.isMultiDay($0, calendar: calendar) }
    }

    private var isToday: Bool { calendar.isDate(day, inSameDayAs: today) }

    /// 徽标计数 = 卡内可见条数（跨天色带 + 单日小条）。
    private var visibleCount: Int { coveringSpans.count + dayEvents.count }

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.sm) {
            HStack(spacing: WFSpace.xs) {
                Text(headerText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isToday ? WFColors.accent : WFColors.text)
                Spacer()
                if visibleCount > 0 {
                    Text("\(visibleCount)").font(WFType.supporting).foregroundStyle(WFColors.accent)
                }
            }
            if coveringSpans.isEmpty && dayEvents.isEmpty {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text("没有安排").font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                }
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: WFSpace.xs) {
                        ForEach(coveringSpans) { span in
                            CalendarSpanBand(span: span, listPalette: listPalette,
                                             roundsClippedEdges: true, onSelect: onSelect)
                        }
                        ForEach(dayEvents) { event in
                            CalendarEventBar(task: event, listPalette: listPalette,
                                             onSelect: onSelect, isDraggable: true)
                        }
                    }
                }
            }
        }
        .padding(WFSpace.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WFColors.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: String.self) { strings, _ in
            guard let id = strings.first.flatMap(UUID.init(uuidString:)) else { return false }
            onDrop(id, day)
            return true
        }
    }

    /// "周三 9/23"；今天不加字，强调色已经说了是今天。
    private var headerText: String {
        let weekday = ["日", "一", "二", "三", "四", "五", "六"][calendar.component(.weekday, from: day) - 1]
        return "周\(weekday) \(calendar.component(.month, from: day))/\(calendar.component(.day, from: day))"
    }
}
