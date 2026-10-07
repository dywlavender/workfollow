import AppKit
import SwiftUI

/// 日历页。
///
/// 一眼读完的一个月，并且就地可改：任务就在日期格里，所以页面下面不需要再来
/// 一份日程表；打开任务与新建任务都发生在贴着被点那一格的浮层里，而不是换掉
/// 整个网格的面板。
///
/// 页面只保留四份状态——屏幕上是哪个月、当前是哪一天、时间怎么呈现、以及哪个
/// 任务正被编辑。工具条、月网格、周视图各自是独立的视图：一个既算网格又画格子
/// 的屏幕，会成为这些东西唯一能被读到的地方。
///
/// 与 Flutter `screens/calendar_screen.dart` 逐项对齐；唯一的差异是编辑器的呈现
/// 方式，见 `PlanningWorkspaceChrome`。
struct CalendarWorkspaceView: View {
    @ObservedObject var workspace: TaskWorkspaceModel

    /// 屏幕上这个月的第一天。周模式下它跟着当前日走。
    @State private var month: Date
    /// 页面的当前日：网格上被标出的那天、周视图的锚点、工具条加号落款的日期。
    @State private var selectedDay: Date
    @State private var mode: CalendarViewMode = .month
    @State private var showCompleted = true

    /// 浮层正在编辑的任务，避免同页叠开第二个编辑器。
    @State private var editingTaskID: UUID?
    /// 正在开着的新建卡；nil 表示没有。
    @State private var composerRequest: PlanningComposerRequest?
    /// 浮层的锚：被点的那一条任务/那一格/工具条加号，在点击时把宿主视图写进来。
    @State private var anchorSink = PlanningAnchorRef()
    /// 工具条加号自己的锚（其余锚由网格与周视图里的元素提供）。
    @State private var addAnchor = PlanningAnchorRef()

    init(workspace: TaskWorkspaceModel) {
        self.workspace = workspace
        let calendar = PlanningProjection.sundayFirstWeek(workspace.calendar)
        let now = workspace.clock()
        let today = calendar.startOfDay(for: now)
        _month = State(initialValue: calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)) ?? today)
        _selectedDay = State(initialValue: today)
    }

    private var calendar: Calendar { PlanningProjection.sundayFirstWeek(workspace.calendar) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            if mode == .month {
                CalendarMonthGridView(
                    month: month,
                    today: workspace.clock(),
                    selectedDay: selectedDay,
                    showCompleted: showCompleted,
                    calendar: calendar,
                    tasks: workspace.allTasks,
                    barColor: barColor,
                    onSelectDay: select(day:),
                    onOpenTask: openTask,
                    onCreateTask: { day in presentComposer(on: day) },
                    onDropTask: { id, day in _ = workspace.moveDueDate(id, to: day) },
                    onToggleTask: toggleTask,
                    anchorSink: anchorSink)
            } else {
                CalendarWeekStripView(
                    anchor: selectedDay,
                    today: workspace.clock(),
                    calendar: calendar,
                    tasks: workspace.allTasks,
                    barColor: barColor,
                    onSelectDay: select(day:),
                    onOpenTask: openTask,
                    onDropTask: { id, day in _ = workspace.moveDueDate(id, to: day) },
                    onToggleTask: toggleTask,
                    anchorSink: anchorSink)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WFColors.content)
        // 触控板/滚轮手势翻页（2026-10-07 用户需求"左右切换"；纵向不翻月，
        // 留给内容滚动——周格任务列表）。累积/阈值/冷却与 NSEvent 桥接在
        // CalendarSwipeGestureModifier；方向反了改它的 directionSign。
        .modifier(CalendarSwipeGestureModifier { direction in
            withAnimation(.easeOut(duration: 0.2)) { step(direction) }
        })
        // 浮层的坐标基准：锚点矩形与弹框位置都在这一个坐标系里算。
        .coordinateSpace(name: PlanningCoordinateSpace.name)
        .overlay {
            PlanningWorkspaceChrome(workspace: workspace,
                                    anchor: anchorSink,
                                    request: $composerRequest,
                                    editingTaskID: $editingTaskID)
        }
    }

    /// 页面没有自己的标题：年月**就是**标题，在它上面再印一行「日历」等于把页面
    /// 命名两遍、白占一行。工具条上其余每一项都对应页面能做的一件事。
    private var toolbar: some View {
        HStack(spacing: 0) {
            Image(systemName: "calendar")
                .font(.system(size: 20))
                .foregroundStyle(WFColors.secondaryText)
            Spacer().frame(width: WFSpace.compact)
            Text(CalendarDayLabels.monthTitle(month, calendar: calendar))
                .font(WFType.pageTitle)
                .foregroundStyle(WFColors.text)
            Spacer(minLength: 0)
            Button {
                anchorSink.rect = addAnchor.rect
                presentComposer(on: selectedDay)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(PlanningAnchorProbe(ref: addAnchor))
            .help("新建任务")
            Spacer().frame(width: WFSpace.xs)
            viewModeControl
            Spacer().frame(width: WFSpace.xs)
            rangeControl
            Spacer().frame(width: WFSpace.xs)
            calendarMenu
        }
        .padding(.horizontal, WFSpace.pageHorizontal)
        .padding(.top, WFSpace.pageTop)
        .frame(height: WFCalendarMetrics.toolbarHeight, alignment: .bottom)
    }

    // MARK: - 工具条控件

    /// 月 / 周。用「显示当前值、点开换一个」的控件，而不是分段控件：分段控件
    /// 拿两个可见槽位去说一个词已经说完的事。
    private var viewModeControl: some View {
        ToolbarPill {
            HStack(spacing: 0) {
                Text(mode.label).font(WFType.control).foregroundStyle(WFColors.text)
                Spacer().frame(width: WFSpace.dense)
                Image(systemName: "chevron.down")
                    .font(.system(size: 15))
                    .foregroundStyle(WFColors.tertiaryText)
            }
            .padding(.horizontal, WFSpace.sm)
        }
        .overlay {
            Menu {
                ForEach(CalendarViewMode.allCases, id: \.self) { value in
                    Button {
                        mode = value
                    } label: {
                        if value == mode {
                            Label(value.label, systemImage: "checkmark")
                        } else {
                            Text(value.label)
                        }
                    }
                }
            } label: {
                Color.clear.contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .fixedSize()
        .help("视图：\(mode.label)")
    }

    /// 后退、今天、前进——一组，因为「今天」只在两个离开它的方向之间才有意义。
    private var rangeControl: some View {
        ToolbarPill {
            HStack(spacing: 0) {
                toolbarSegment(icon: "chevron.left", tooltip: mode.previousLabel) { step(-1) }
                toolbarSegment(label: "今天", tooltip: "回到今天") { goToday() }
                toolbarSegment(icon: "chevron.right", tooltip: mode.nextLabel) { step(1) }
            }
        }
        .fixedSize()
    }

    /// 页面自己的设置。今天只有一项——已完成的任务要不要显示在网格里。
    private var calendarMenu: some View {
        Menu {
            Button {
                showCompleted.toggle()
            } label: {
                if showCompleted {
                    Label("显示已完成任务", systemImage: "checkmark")
                } else {
                    Text("显示已完成任务")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("日历设置")
    }

    /// 胶囊里的一个命中目标：图标或一个词，不会两者都有。
    @ViewBuilder
    private func toolbarSegment(icon: String? = nil, label: String? = nil,
                               tooltip: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Group {
                if let icon {
                    Image(systemName: icon).font(.system(size: 15))
                        .foregroundStyle(WFColors.secondaryText)
                } else {
                    Text(label ?? "").font(WFType.control).foregroundStyle(WFColors.text)
                }
            }
            .padding(.horizontal, WFSpace.sm)
            .frame(height: WFCalendarMetrics.chipHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - 交互

    private func step(_ direction: Int) {
        if mode == .month {
            month = calendar.date(byAdding: .month, value: direction, to: month) ?? month
            return
        }
        // 周模式移动的是当前日，月份跟着走，这样离开周模式会落在最后看的那个月。
        guard let moved = calendar.date(byAdding: .day, value: 7 * direction, to: selectedDay) else { return }
        selectedDay = moved
        month = firstOfMonth(moved)
    }

    private func goToday() {
        let today = calendar.startOfDay(for: workspace.clock())
        selectedDay = today
        month = firstOfMonth(today)
    }

    /// 点一天：网格显示邻月收尾与开头的日子，所以点击可能落在屏幕之外的月份上；
    /// 跟着它走，选中的格子才会留在页内而不是挂在页边。
    private func select(day: Date) {
        selectedDay = day
        if calendar.component(.month, from: day) != calendar.component(.month, from: month)
            || calendar.component(.year, from: day) != calendar.component(.year, from: month) {
            month = firstOfMonth(day)
        }
    }

    private func firstOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func openTask(_ id: UUID) {
        guard editingTaskID == nil else { return }
        editingTaskID = id
        workspace.select(id)
    }

    /// 条/胶囊上的勾选框：点一下完成或恢复（原版里这个框只报状态，见
    /// `CalendarTaskBarView` 的说明）。走的是与象限行同一个动作入口。
    private func toggleTask(_ id: UUID) {
        guard let task = workspace.task(for: id) else { return }
        _ = workspace.changeStatus(task)
    }

    /// 打开新建卡：日期预置成被点的那一天（原版 `TaskScheduleDraft.forDay(day)`），
    /// 用户清空日期也仍然是他的决定——所以 fallback 同样是这一天，只有卡上真的没有
    /// 日期时才用得上。
    private func presentComposer(on day: Date) {
        workspace.select(nil)
        let target = calendar.startOfDay(for: day)
        let schedule = TaskSchedule(dueAt: target)
        composerRequest = PlanningComposerRequest(fallback: schedule, preset: schedule, priority: .none)
    }

    /// 日历条的颜色：按**任务**取色，不按清单。
    ///
    /// 这里曾经是 `listColor(task.list.name)`，与侧栏圆点同色。改掉的原因是「收集箱不可
    /// 着色」（`setListColor` 明确拒绝它），而 35 条任务里 20 条都在收集箱——日历因此永远
    /// 是一整片同色的蓝。代价：日历条不再告诉你任务在哪个清单。侧栏圆点、象限行、专注
    /// 面板仍然按清单着色，没有跟着改。
    private func barColor(_ id: UUID) -> Color {
        WFPlanningPalette.taskColor(taskID: id)
    }
}

// MARK: - 纯展示规则（可单测）

/// 日号与日期键的写法。抽出来是为了让用例问的是「这格回答的那个问题」，
/// 而不是把规则再写一遍。
enum CalendarDayLabels {
    /// 工具条上的年月标题，`2026年9月`。
    ///
    /// 必须拼成 String 再交给 `Text`：`Text("\(年份)年")` 走的是本地化插值，
    /// 整数会带上千分位，标题会变成「2,026年9月」。
    static func monthTitle(_ date: Date, calendar: Calendar) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return "\(year)年\(month)月"
    }

    /// 每月 1 日带上月份——月网格开头与结尾都是邻月的日子，三张月份同时在屏时
    /// 一个孤零零的「1」分不清属于哪个月。其余日子没有歧义，一个月只有一个。
    static func label(_ date: Date, calendar: Calendar) -> String {
        let day = calendar.component(.day, from: date)
        guard day == 1 else { return "\(day)" }
        return "\(calendar.component(.month, from: date))月1日"
    }

    /// 稳定日期键，供标识与用例共用。
    static func key(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// 条上的时刻 `HH:mm`，没有时刻就是全天。
///
/// 任务行的日期文案是「9 月 21 日 15:00」，而这条任务所在的格子已经说明了是哪一
/// 天，再印一遍日期等于重复格子、占掉标题要用的地方。没有时刻的任务就是全天，
/// 「全天」是给「没有时刻」这件事硬造的一个词。
func calendarClock(_ at: Date?, hasTime: Bool, calendar: Calendar) -> String? {
    guard hasTime, let at else { return nil }
    let parts = calendar.dateComponents([.hour, .minute], from: at)
    return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
}

/// 星期日到星期六的表头文字，以及周视图的星期名。
enum CalendarWeekHeaderLabels {
    static let all = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    /// Calendar 的星期编号是 周日 1 … 周六 7。
    static func weekdayName(_ weekday: Int) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        return names[min(max(weekday - 1, 0), 6)]
    }
}

// MARK: - 工具条胶囊

/// 工具条上每个控件都穿的描边盒子，让这条线读起来是一排控件而不是三个无关的形状。
struct ToolbarPill<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(height: WFCalendarMetrics.chipHeight)
            .overlay {
                RoundedRectangle(cornerRadius: WFCalendarMetrics.controlRadius)
                    .stroke(WFColors.borderStrong, lineWidth: 1)
            }
    }
}

// MARK: - 月网格

/// 月网格。它是一个连续的日期面，不是摆在页面上的卡片墙。
///
/// 月从它开始的那一天开始，所以网格开头是上月收尾的日子、结尾是下月开头的日子。
/// 那些日子是真的格子：有自己的任务、也能被投放。行数跟着月份走而不补齐六行，
/// 五周装得下的月份就画五周。
///
/// 每一行是三层的叠放，顺序就是设计：格子（带自己的小条）在最下；本行的跨天色带
/// 压在格子底色之上，色带才读得成一整块颜色而不是被六格底色切碎的漆；今天的洗色
/// 随后，穿过今天的那条色带也要被这一天染一层；细线最后，于是它穿过色带而不是
/// 止步于色带。
struct CalendarMonthGridView: View {
    let month: Date
    let today: Date
    let selectedDay: Date
    let showCompleted: Bool
    let calendar: Calendar
    let tasks: [Task]
    let barColor: (UUID) -> Color
    let onSelectDay: (Date) -> Void
    let onOpenTask: (UUID) -> Void
    let onCreateTask: (Date) -> Void
    let onDropTask: (UUID, Date) -> Void
    /// 条上勾选框的动作：点一下完成或恢复。
    let onToggleTask: (UUID) -> Void
    /// 浮层锚的落脚点：格与条在点击时把「自己是哪一块」写进去。
    let anchorSink: PlanningAnchorRef

    private var days: [Date] { PlanningProjection.monthGridDays(containing: month, calendar: calendar) }
    private var rows: Int { max(days.count / 7, 1) }

    var body: some View {
        VStack(spacing: 0) {
            weekHeader
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    MonthWeekRow(
                        days: Array(days[(row * 7)..<min(row * 7 + 7, days.count)]),
                        month: month,
                        today: today,
                        selectedDay: selectedDay,
                        showCompleted: showCompleted,
                        isLastRow: row == rows - 1,
                        calendar: calendar,
                        tasks: tasks,
                        barColor: barColor,
                        onSelectDay: onSelectDay,
                        onOpenTask: onOpenTask,
                        onCreateTask: onCreateTask,
                        onDropTask: onDropTask,
                        onToggleTask: onToggleTask,
                        anchorSink: anchorSink)
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }

    /// 周日在前，与网格的列偏移同源。两者必须一致：表头顺序与首列偏移不一致不
    /// 只是标错一列，而是把这个月的每个日期都挪到错误的星期上。
    private var weekHeader: some View {
        HStack(spacing: 0) {
            ForEach(CalendarWeekHeaderLabels.all, id: \.self) { label in
                Text(label)
                    .font(WFType.listMeta)
                    .foregroundStyle(WFColors.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, WFCalendarMetrics.weekHeaderPadding)
            }
        }
        .frame(height: WFCalendarMetrics.weekHeaderHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(WFColors.border).frame(height: 1)
        }
    }
}

/// 网格的一周：格子 + 跨天色带 + 今天的洗色 + 细线。
struct MonthWeekRow: View {
    let days: [Date]
    let month: Date
    let today: Date
    let selectedDay: Date
    let showCompleted: Bool
    let isLastRow: Bool
    let calendar: Calendar
    let tasks: [Task]
    let barColor: (UUID) -> Color
    let onSelectDay: (Date) -> Void
    let onOpenTask: (UUID) -> Void
    let onCreateTask: (Date) -> Void
    let onDropTask: (UUID, Date) -> Void
    let onToggleTask: (UUID) -> Void
    let anchorSink: PlanningAnchorRef

    /// 与本周有交集的跨天任务，已按原版口径排序（开始早优先、同日时长优先），
    /// 再按列区间摆进条位。
    private var spans: [CalendarSpan] {
        let multiDay = PlanningProjection.multiDayTasks(from: tasks,
                                                        first: days.first ?? month,
                                                        last: days.last ?? month,
                                                        calendar: calendar)
        return CalendarSpans.lanes(for: days, tasks: multiDay, calendar: calendar)
            .filter { showCompleted || $0.task.status != .completed }
    }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = geometry.size.width / 7
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.offset) { column, day in
                        dayCell(day, column: column, height: geometry.size.height)
                            .frame(width: columnWidth, height: geometry.size.height)
                    }
                }
                ForEach(spans) { span in
                    spanBand(span, columnWidth: columnWidth)
                }
                if let todayColumn {
                    Rectangle()
                        .fill(WFColors.accent.opacity(WFCalendarMetrics.todayCellAlpha))
                        .frame(width: columnWidth, height: geometry.size.height)
                        .offset(x: CGFloat(todayColumn) * columnWidth)
                        .allowsHitTesting(false)
                }
                hairlines(columnWidth: columnWidth, height: geometry.size.height)
            }
        }
    }

    private func dayCell(_ day: Date, column: Int, height: CGFloat) -> some View {
        let visible = PlanningProjection.singleDayTasks(on: day, from: tasks, calendar: calendar)
        return CalendarDayCellView(
            date: day,
            height: height,
            inMonth: calendar.component(.month, from: day) == calendar.component(.month, from: month)
                && calendar.component(.year, from: day) == calendar.component(.year, from: month),
            isToday: calendar.isDate(day, inSameDayAs: today),
            selected: calendar.isDate(day, inSameDayAs: selectedDay),
            skipSlots: CalendarSpans.slotsOver(spans, column: column),
            tasks: showCompleted ? visible : visible.filter { $0.status != .completed },
            calendar: calendar,
            barColor: barColor,
            onSelect: { onSelectDay(day) },
            onOpenTask: onOpenTask,
            onCreate: { onCreateTask(day) },
            onDropTask: { id in onDropTask(id, day) },
            onToggleTask: onToggleTask,
            anchorSink: anchorSink)
    }

    /// 一条色带：左端 = 列起点（未被裁剪的一端让出格内缩进），宽度覆盖本段各列，
    /// 顶 = 事件区首行 + lane × 槽位步进。被周边界裁掉的一端贴到行边，上下两周
    /// 的色带才接得上。
    private func spanBand(_ span: CalendarSpan, columnWidth: CGFloat) -> some View {
        let startInset = span.continuesFromPreviousRow ? 0 : WFCalendarMetrics.cellHorizontalPadding
        let endInset = span.continuesIntoNextRow ? 0 : WFCalendarMetrics.cellHorizontalPadding
        let width = max(0, CGFloat(span.columnCount) * columnWidth - startInset - endInset)
        let y = WFCalendarMetrics.cellTopPadding + WFCalendarMetrics.dayCellSize
            + WFCalendarMetrics.dayNumberGap + CGFloat(span.lane) * WFCalendarMetrics.slotStride
        let color = barColor(span.task.id)
        return CalendarTaskSpanBar(span: span, listColor: color, calendar: calendar,
                                   onOpen: { onOpenTask(span.task.id) },
                                   onToggleTask: onToggleTask,
                                   anchorSink: anchorSink)
            .frame(width: width, height: WFCalendarMetrics.taskBarHeight)
            .offset(x: CGFloat(span.fromColumn) * columnWidth + startInset, y: y)
            .draggable(span.task.id.uuidString) {
                CalendarTaskDragPreview(task: span.task, listColor: color,
                                        width: width, calendar: calendar)
            }
    }

    private var todayColumn: Int? {
        days.firstIndex { calendar.isDate($0, inSameDayAs: today) }
    }

    /// 细线画在这里而不是各格自己的边框上：色带横跨列间，画在格子上的线会停在
    /// 每条色带处。最后一列与最后一行不画，网格的外缘才是一条线而不是两条。
    private func hairlines(columnWidth: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(1..<7, id: \.self) { index in
                Rectangle()
                    .fill(WFColors.border)
                    .frame(width: 1, height: height)
                    .offset(x: CGFloat(index) * columnWidth - 1)
            }
            if !isLastRow {
                Rectangle()
                    .fill(WFColors.border)
                    .frame(width: columnWidth * 7, height: 1)
                    .offset(y: height - 1)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 日期格

/// 月网格的一格。
///
/// 格子是一张写了日期的纸，不是卡片：没有圆角、没有外边距、除页面底色外没有自己
/// 的填充。它有的空间都花在任务条上，用完了就停下来用数字说还剩几个。
///
/// 两种手势权重不同。单击选日——网格保有页面的当前日，工具条的加号就是拿它给新
/// 任务落款。双击在那天建一个。
///
/// 承载这两种手势的面在格子内容的**下面**而不是外面，这是布局的全部要点。双击
/// 识别器会从第一次点击起握住手势仲裁直到它自己的时限过去，凡是挂在它下面的东西
/// 都得等完那段静默；任务条若在这个面里面，每次点任务都要先空等三分之一秒才打开
/// 编辑器。所以日面放在内容的下一层：落在任务条上的按击在那里就被接走，根本到不了
/// 这个面，指针一抬就有结果。
struct CalendarDayCellView: View {
    let date: Date
    /// 格子被分到的高度。任务条的容量由它推出来，不另外量。
    let height: CGFloat
    let inMonth: Bool
    let isToday: Bool
    let selected: Bool
    let skipSlots: Int
    let tasks: [Task]
    let calendar: Calendar
    let barColor: (UUID) -> Color
    let onSelect: () -> Void
    let onOpenTask: (UUID) -> Void
    let onCreate: () -> Void
    let onDropTask: (UUID) -> Void
    let onToggleTask: (UUID) -> Void
    let anchorSink: PlanningAnchorRef

    @State private var dropping = false
    /// 这一格自己的锚：双击新建时新建卡贴着这一格弹出来。
    @State private var anchor = PlanningAnchorRef()

    /// 日期号与任务条之间的可用高度：格高 − 上下内边距 − 日号 − 间距。
    private var barAreaHeight: CGFloat {
        height - WFCalendarMetrics.cellTopPadding - WFCalendarMetrics.cellBottomPadding
            - WFCalendarMetrics.dayCellSize - WFCalendarMetrics.dayNumberGap
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            (inMonth ? WFColors.content : WFColors.calendarCanvas)
            // 日面在最下。落在任务条上的按击由上层接走，永远到不了这里。
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    anchorSink.rect = anchor.rect
                    onCreate()
                }
                .onTapGesture { onSelect() }
            if dropping {
                Rectangle()
                    .fill(WFColors.accent.opacity(WFCalendarMetrics.dropHighlightAlpha))
                    .allowsHitTesting(false)
            }
            VStack(alignment: .leading, spacing: 0) {
                dayNumber
                Spacer().frame(height: WFCalendarMetrics.dayNumberGap)
                bars
            }
            .padding(.leading, WFCalendarMetrics.cellHorizontalPadding)
            .padding(.trailing, WFCalendarMetrics.cellHorizontalPadding)
            .padding(.top, WFCalendarMetrics.cellTopPadding)
            .padding(.bottom, WFCalendarMetrics.cellBottomPadding)
        }
        .dropDestination(for: String.self) { values, _ in
            guard let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
            onDropTask(id)
            return true
        } isTargeted: { dropping = $0 }
        .background(PlanningAnchorProbe(ref: anchor))
    }

    /// 日号是装饰：点在它上面属于下面的日面，和点在格内任何不是任务条的地方一样。
    private var dayNumber: some View {
        HStack(spacing: 0) {
            // 标记是胶囊不是定径圆，才能装下 1 日携带的月份；固定 24pt 时「9月1日」
            // 不是被裁掉就是溢出填充。寻常日子没变：24pt 方块按半个自己收圆就是圆。
            Text(CalendarDayLabels.label(date, calendar: calendar))
                .font(WFType.listBody)
                .foregroundStyle(dayNumberColor)
                // 徽标挂在**文字自己**的右缘上，不是那个 24pt 的框上。
                //
                // 挂在框上时，一位数的墨迹只占框宽的三分之一，徽标被框的空档推开
                // 约 6pt，读起来是「号旁边浮了个点」而不是上标。滴答 2026-10 实测是
                // **紧贴墨迹**（间隙≈0，见 `workdayBadgeGap`），今天那格它甚至压住
                // 蓝圆边缘——那是"上标"该有的关系，不是画错了。挂在这里才复现同一个
                // 关系。
                //
                // 浮层要在 `padding` **之前**：1 日那格「10月1日」左右各垫 5pt 胶囊余量，
                // 挂在 padding 之后徽标会跟着被推右 5pt（实测格内偏移 +66.3，滴答 +59.5）。
                //
                // 浮层不占布局宽度，所以日号框仍是 24pt、今天的蓝圆仍是 24pt 正圆；
                // 徽标溢到框外也不裁——与滴答压住蓝圆边缘是同一件事。
                .overlay(alignment: .trailing) {
                    if let badge = workdayBadgeKind {
                        WorkdayBadge(kind: badge)
                            .offset(x: WorkdayBadgeMetrics.diameter + WFCalendarMetrics.workdayBadgeGap,
                                    y: -WFCalendarMetrics.workdayBadgeRise)
                    }
                }
                .padding(.horizontal, calendar.component(.day, from: date) == 1 ? WFSpace.dense : 0)
                .frame(minWidth: WFCalendarMetrics.dayCellSize,
                       minHeight: WFCalendarMetrics.dayCellSize)
                .background(isToday ? WFColors.accent : .clear,
                            in: RoundedRectangle(cornerRadius: WFCalendarMetrics.dayCellSize / 2))
            // 这一天"是什么"——有的话。绿色与原版日程面板给节假日的颜色一致。
            if let festival = LunarCalendarService.festivalLabelIncludingStatutory(for: date,
                                                                                  calendar: calendar) {
                Text(festival)
                    .font(WFType.caption)
                    .foregroundStyle(WFColors.success)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(height: WFCalendarMetrics.dayCellSize)
        .allowsHitTesting(false)
    }

    /// 只有国务院公布的调休安排才给徽标：普通周末没有（它是常识，印成「休」会把
    /// 真正要提醒的那几天淹掉），工作日也没有。
    ///
    /// **非本月的日子照样给。** 9 月 27 日是中秋假期最后一天，在 10 月的网格里虽然
    /// 只是上月收尾的格子，可它就是放假——滴答在那里也画了绿徽标。日号退墨色说的是
    /// 「不属于本月」，徽标说的是「这一天特殊」，两件事互不冲突。
    private var workdayBadgeKind: WorkdayBadgeKind? {
        WorkdayBadgeKind(ChineseWorkCalendar.override(for: date, calendar: calendar))
    }

    private var dayNumberColor: Color {
        if isToday { return WFColors.content }
        if !inMonth { return WFColors.tertiaryText }
        return selected ? WFColors.accent : WFColors.text
    }

    /// 格高装得下几条就画几条，色带占掉的槽位先扣掉。
    ///
    /// 格子自己量而不接受「显示几条」的指令：行高取决于窗口，高窗口显五条、矮窗口
    /// 显两条。要计数时把最后一条槽位还给计数——只剩一条的位置时，计数会把唯一的
    /// 槽位吃掉、让这一天看起来是空的，所以一格一条时显示第一条、不显示计数。
    @ViewBuilder
    private var bars: some View {
        if tasks.isEmpty {
            Spacer(minLength: 0)
        } else {
            let capacity = Int(floor((barAreaHeight + WFCalendarMetrics.taskBarGap)
                                     / WFCalendarMetrics.slotStride)) - skipSlots
            if capacity < 1 {
                Spacer(minLength: 0)
            } else {
                let overflowing = tasks.count > capacity
                let counting = overflowing && capacity > 1
                let visibleCount = overflowing ? (counting ? capacity - 1 : capacity) : tasks.count
                VStack(alignment: .leading, spacing: 0) {
                    if skipSlots > 0 {
                        Spacer().frame(height: CGFloat(skipSlots) * WFCalendarMetrics.slotStride)
                    }
                    ForEach(0..<visibleCount, id: \.self) { index in
                        if index > 0 { Spacer().frame(height: WFCalendarMetrics.taskBarGap) }
                        bar(tasks[index])
                    }
                    if counting {
                        Spacer().frame(height: WFCalendarMetrics.taskBarGap)
                        CalendarTaskOverflowView(hiddenCount: tasks.count - visibleCount,
                                                 onTap: onSelect)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func bar(_ task: Task) -> some View {
        let color = barColor(task.id)
        return CalendarTaskBarView(task: task, listColor: color, calendar: calendar,
                                   onOpen: { onOpenTask(task.id) },
                                   onToggleTask: onToggleTask,
                                   anchorSink: anchorSink)
            .draggable(task.id.uuidString) {
                CalendarTaskDragPreview(task: task, listColor: color, width: nil, calendar: calendar)
            }
    }
}

// MARK: - 任务条与色带

/// 月格里的一个任务。
///
/// 它不是缩小版的 TaskRow。一格要在一条竖向窄缝里装下一天的工作，所以条是单行的
/// ——勾选框、标题、时刻——满行会写成文字的东西在这里改为用颜色表达。
///
/// 底色**按任务取**，不按清单（见 `WFListPalette.taskColorIndex`）：它曾经是清单色、
/// 与侧栏圆点同值，但「收集箱不可着色」而多数任务都在收集箱，日历因此永远是一整片
/// 同色的蓝。代价是月份不再告诉你任务属于哪个清单；换来的是相邻的条彼此可分。
///
/// 这个尺寸下底色深浅也是完成态除了标题墨色外唯一能改的东西，所以未完成的条拿满
/// 一档、完成的退到浅档——就是 `WFCalendarMetrics` 里那一对，周视图的胶囊也取同一对。
///
/// 条本身是惰性的：拖动、投放、打开都归安排这些条的网格管，因为只有网格知道月份里
/// 的一个位置是什么意思。
///
/// 一处与原版不同：条上的勾选框自己接点击（原版只报状态）。点框＝完成/恢复该任务，
/// 点条上其余任何地方＝打开编辑器；两层都是手势而不是嵌套按钮，里层的手势天然优先，
/// 框以外的地方不会既勾又开。
struct CalendarTaskBarView: View {
    let task: Task
    let listColor: Color
    let calendar: Calendar
    let onOpen: () -> Void
    let onToggleTask: (UUID) -> Void
    let anchorSink: PlanningAnchorRef

    /// 这一条自己的锚：编辑器贴着被点的这条弹出来，而不是贴着整格。
    @State private var anchor = PlanningAnchorRef()

    var body: some View {
        CalendarTaskBarLine(
            task: task,
            showBox: true,
            clock: calendarClock(task.schedule.dueAt,
                                 hasTime: task.schedule.hasTime, calendar: calendar),
            onToggleCompletion: { onToggleTask(task.id) })
        .frame(height: WFCalendarMetrics.taskBarHeight)
        .background(listColor.opacity(
            WFCalendarMetrics.taskBarFill(completed: task.status == .completed)),
            in: RoundedRectangle(cornerRadius: WFCalendarMetrics.taskBarRadius))
        .contentShape(Rectangle())
        .onTapGesture {
            anchorSink.rect = anchor.rect
            onOpen()
        }
        .help(task.title)
        .background(PlanningAnchorProbe(ref: anchor))
    }
}

/// 一条色带在某一周行里的那一份。
///
/// 色带是一个横跨若干列的整盒，这是它的全部要点：五天的一条读成一件事，而不是五
/// 个恰好同色的邻居，列边也不会有任何重描。只有任务真实的两端是圆角；被行边界切
/// 掉的一侧取方角并贴到行边，上一行的那一份才能无缝接上。
///
/// 一份带什么也遵循同一条规则：勾选框标记任务从哪里开始，所以只有含首日的那一份
/// 有；时刻属于区间的末端，所以只有含末日的那一份印。标题每一份都有——一条周三
/// 续上却没有字的色带，是一根谁也认不出来的彩色棒。
struct CalendarTaskSpanBar: View {
    let span: CalendarSpan
    let listColor: Color
    let calendar: Calendar
    let onOpen: () -> Void
    let onToggleTask: (UUID) -> Void
    let anchorSink: PlanningAnchorRef

    /// 这一份色带自己的锚。
    @State private var anchor = PlanningAnchorRef()

    private var done: Bool { span.task.status == .completed }

    private var shape: UnevenRoundedRectangle {
        let corner = WFCalendarMetrics.taskBarRadius
        return UnevenRoundedRectangle(
            topLeadingRadius: span.continuesFromPreviousRow ? 0 : corner,
            bottomLeadingRadius: span.continuesFromPreviousRow ? 0 : corner,
            bottomTrailingRadius: span.continuesIntoNextRow ? 0 : corner,
            topTrailingRadius: span.continuesIntoNextRow ? 0 : corner)
    }

    var body: some View {
        CalendarTaskBarLine(
            task: span.task,
            showBox: span.startsInRow,
            // 时刻属于区间的末端：色带从左往右读，印在远端的那一刻必须是它结束
            // 的那一刻。全天区间在当天零点结束，没有时刻可印。
            clock: span.endsInRow
                ? calendarClock(span.task.schedule.dueEndAt,
                                hasTime: span.task.schedule.hasTime, calendar: calendar)
                : nil,
            // 勾选框只出现在含首日的那一份（`showBox`），动作与月格里的条一致。
            onToggleCompletion: { onToggleTask(span.task.id) })
        .frame(height: WFCalendarMetrics.taskBarHeight)
        .background(listColor.opacity(WFCalendarMetrics.taskBarFill(completed: done)),
                    in: shape)
        .contentShape(Rectangle())
        .onTapGesture {
            anchorSink.rect = anchor.rect
            onOpen()
        }
        .help(span.task.title)
        .background(PlanningAnchorProbe(ref: anchor))
    }
}

/// 月网格里任何一种条的里面。
///
/// 两种条是同样的色带、同样的勾选框与标题、同样的字号，所以这些零件放在这里而不是
/// 写两遍。
struct CalendarTaskBarLine: View {
    let task: Task
    let showBox: Bool
    let clock: String?
    /// 勾选框的点击动作。为 nil 时框只表达状态——拖动预览就是这一种。
    var onToggleCompletion: (() -> Void)? = nil

    private var completed: Bool { task.status == .completed }
    private var interactiveBox: Bool { showBox && onToggleCompletion != nil }
    private var hitPadding: CGFloat { WFCalendarMetrics.taskBarCheckboxHitPadding }

    var body: some View {
        HStack(spacing: 0) {
            if showBox {
                completionBox
                // 命中区左右各外扩 3pt，这部分空间从条的前内边距与框后间距里让回来，
                // 框的落点与标题的起点与原来完全一致。
                Spacer().frame(width: interactiveBox ? WFSpace.dense - hitPadding : WFSpace.dense)
            }
            Text(task.title)
                .font(WFCalendarMetrics.taskBarTitleFont)
                .foregroundStyle(completed ? WFColors.tertiaryText : WFColors.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let clock {
                Spacer().frame(width: WFSpace.dense)
                Text(clock)
                    .font(WFCalendarMetrics.taskBarClockFont)
                    .foregroundStyle(WFColors.tertiaryText)
            }
        }
        .padding(.leading, interactiveBox ? WFSpace.dense - hitPadding : WFSpace.dense)
        .padding(.trailing, WFSpace.dense)
    }

    /// 与任务行同一个框，只是缩到这个条装得下的边长——并且用同一个默认描边：条的底色
    /// 已经说明了任务在哪个清单，再在框里读第二遍就是给它描上一圈清单色。参考图的月
    /// 网格里每个框都是纯灰，不论条是什么色，框于是成了这行上唯一一处到处含义相同的
    /// 记号。
    ///
    /// 原版里这个框只报状态、点了开的是编辑器。这里按需求让它自己接点击：方框本身
    /// 仍是那个形状，外扩出来的命中区是它的包装，框的落点不变。
    @ViewBuilder
    private var completionBox: some View {
        let box = TaskCompletionBox(size: WFCalendarMetrics.taskBarCheckboxSize,
                                    completed: completed)
        if let onToggleCompletion {
            box
                .padding(hitPadding)
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggleCompletion)
                .help(completed ? "恢复任务" : "完成任务")
                .accessibilityLabel(completed ? "恢复：\(task.title)" : "完成：\(task.title)")
        } else {
            box
        }
    }
}

/// 格子里还有几条没画出来。
///
/// 它是格子自己的入口而不是一天的摘要：数字说的是少了几条，点它会选中这一天，
/// 剩下的列表因此只差一步。
struct CalendarTaskOverflowView: View {
    let hiddenCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("+\(String(hiddenCount))")
                .font(WFType.caption)
                .foregroundStyle(WFColors.secondaryText)
                .frame(maxWidth: .infinity, minHeight: WFCalendarMetrics.taskBarHeight,
                       alignment: .leading)
                .padding(.horizontal, WFSpace.dense)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 拖动时跟着指针走的预览：条按它在屏幕上的样子画出来。
/// 不给宽度的话，无约束的浮层会把标题压成零宽。
struct CalendarTaskDragPreview: View {
    let task: Task
    let listColor: Color
    let width: CGFloat?
    let calendar: Calendar

    var body: some View {
        CalendarTaskBarLine(
            task: task,
            showBox: true,
            clock: calendarClock(task.schedule.dueAt,
                                 hasTime: task.schedule.hasTime, calendar: calendar))
        .frame(width: width, height: WFCalendarMetrics.taskBarHeight)
        .background(listColor.opacity(
            WFCalendarMetrics.taskBarFill(completed: task.status == .completed)),
            in: RoundedRectangle(cornerRadius: WFCalendarMetrics.taskBarRadius))
        .padding(WFSpace.hairline)
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: WFSpace.tight))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }
}

// MARK: - 周视图

/// 一周，七个日列。
///
/// 与月网格一样从周日开始，切换模式不会悄悄换掉哪一列属于星期几。列仍是较老的
/// 一天一卡形状，任务按「开始于这一天」取（`PlanningProjection.tasks(on:)`），
/// 跨天区间不在这一列里画色带——那是月网格的事。
struct CalendarWeekStripView: View {
    let anchor: Date
    let today: Date
    let calendar: Calendar
    let tasks: [Task]
    let barColor: (UUID) -> Color
    let onSelectDay: (Date) -> Void
    let onOpenTask: (UUID) -> Void
    let onDropTask: (UUID, Date) -> Void
    let onToggleTask: (UUID) -> Void
    let anchorSink: PlanningAnchorRef

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(PlanningProjection.weekDays(containing: anchor, calendar: calendar).enumerated()),
                    id: \.offset) { _, day in
                CalendarWeekDayColumn(
                    day: day,
                    today: today,
                    calendar: calendar,
                    tasks: PlanningProjection.tasks(on: day, from: tasks, calendar: calendar),
                    barColor: barColor,
                    onSelectDay: onSelectDay,
                    onOpenTask: onOpenTask,
                    onDropTask: onDropTask,
                    onToggleTask: onToggleTask,
                    anchorSink: anchorSink)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WFColors.content)
    }
}

struct CalendarWeekDayColumn: View {
    let day: Date
    let today: Date
    let calendar: Calendar
    let tasks: [Task]
    let barColor: (UUID) -> Color
    let onSelectDay: (Date) -> Void
    let onOpenTask: (UUID) -> Void
    let onDropTask: (UUID, Date) -> Void
    let onToggleTask: (UUID) -> Void
    let anchorSink: PlanningAnchorRef

    @State private var dropping = false

    private var isToday: Bool { calendar.isDate(day, inSameDayAs: today) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(headerText)
                    .font(WFType.sectionSemibold)
                    .foregroundStyle(isToday ? WFColors.accent : WFColors.text)
                Spacer(minLength: 0)
                if !tasks.isEmpty {
                    Text(String(tasks.count))
                        .font(WFType.caption)
                        .foregroundStyle(WFColors.accent)
                }
            }
            Spacer().frame(height: WFSpace.sm)
            if tasks.isEmpty {
                Text("没有安排")
                    .font(WFType.caption)
                    .foregroundStyle(WFColors.tertiaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: WFSpace.dense) {
                        ForEach(tasks) { task in
                            weekPill(task)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.leading, WFSpace.compactInset)
        .padding(.top, WFSpace.compactInset)
        .padding(.trailing, WFSpace.compactInset)
        .padding(.bottom, WFSpace.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(dropping ? WFColors.accentSoft : WFColors.content,
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(dropping ? WFColors.accent.opacity(0.6) : WFColors.border, lineWidth: 1)
        }
        .padding(.trailing, WFSpace.sm)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { onSelectDay(day) }
        .dropDestination(for: String.self) { values, _ in
            guard let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
            onDropTask(id, day)
            return true
        } isTargeted: { dropping = $0 }
    }

    private func weekPill(_ task: Task) -> some View {
        CalendarWeekPillButton(task: task,
                               color: barColor(task.id),
                               completed: task.status == .completed,
                               anchorSink: anchorSink,
                               onOpen: { onOpenTask(task.id) },
                               onToggleTask: onToggleTask)
    }

    /// 「周三 9/23」；今天不额外加字，强调色已经说了是今天。
    private var headerText: String {
        "周\(CalendarWeekHeaderLabels.weekdayName(calendar.component(.weekday, from: day))) "
            + "\(calendar.component(.month, from: day))/\(calendar.component(.day, from: day))"
    }
}

/// 周视图里的一条任务胶囊。
///
/// 独立成一个视图只为一件事：它要拿着自己的锚，点击该条时编辑器才贴着**这一条**弹
/// 出来（原版 `CalendarWeekView` 的胶囊同样以自身为锚，不是整列）。
struct CalendarWeekPillButton: View {
    let task: Task
    let color: Color
    let completed: Bool
    let anchorSink: PlanningAnchorRef
    let onOpen: () -> Void
    let onToggleTask: (UUID) -> Void

    @State private var anchor = PlanningAnchorRef()

    private var hitPadding: CGFloat { WFCalendarMetrics.taskBarCheckboxHitPadding }

    private var pill: some View {
        HStack(alignment: .top, spacing: 0) {
            // 与月格的条同一条规则：框自己接点击，胶囊其余地方打开编辑器。外扩的命中
            // 区从内边距里让出来，胶囊的尺寸与内容落点都不变。
            TaskCompletionBox(size: WFCalendarMetrics.taskBarCheckboxSize, completed: completed)
                .padding(hitPadding)
                .contentShape(Rectangle())
                .onTapGesture { onToggleTask(task.id) }
                .help(completed ? "恢复任务" : "完成任务")
                .accessibilityLabel(completed ? "恢复：\(task.title)" : "完成：\(task.title)")
            Spacer().frame(width: WFSpace.dense - hitPadding)
            Text(task.title)
                .font(WFType.caption)
                .foregroundStyle(completed ? WFColors.tertiaryText : WFColors.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, WFSpace.compact - hitPadding)
        .padding(.trailing, WFSpace.compact)
        .padding(.vertical, WFSpace.inline - hitPadding)
        .background(color.opacity(WFCalendarMetrics.taskBarFill(completed: completed)),
                    in: RoundedRectangle(cornerRadius: WFCalendarMetrics.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: WFCalendarMetrics.controlRadius)
                .stroke(color.opacity(WFCalendarMetrics.taskBarBorderAlpha), lineWidth: 1)
        }
    }

    var body: some View {
        pill
            .contentShape(Rectangle())
            .onTapGesture {
                anchorSink.rect = anchor.rect
                onOpen()
            }
            .draggable(task.id.uuidString) {
                pill.frame(width: 200)
            }
            .background(PlanningAnchorProbe(ref: anchor))
    }
}

// MARK: - 视图模式

/// 日历怎么呈现时间。
enum CalendarViewMode: String, CaseIterable {
    case month, week

    var label: String {
        switch self {
        case .month: "月"
        case .week: "周"
        }
    }

    /// 这个模式下后退一步是什么意思，给范围控件的提示用。控件本身只报告移动。
    var previousLabel: String {
        switch self {
        case .month: "上个月"
        case .week: "上一周"
        }
    }

    var nextLabel: String {
        switch self {
        case .month: "下个月"
        case .week: "下一周"
        }
    }
}
