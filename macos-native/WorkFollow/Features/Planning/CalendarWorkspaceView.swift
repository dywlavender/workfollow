import AppKit
import SwiftUI

/// One viewport and one display configuration drive every calendar mode.
/// Shared task details and date drafts remain the same as the task workspace.
struct CalendarWorkspaceView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var settings: PlanningSettingsStore
    @ObservedObject private var integration: CalendarSyncCoordinator
    @EnvironmentObject private var environment: AppEnvironment
    @State private var systemEventDetails: SystemCalendarEvent?
    @State private var viewport: CalendarViewport
    @State private var topWeek: Date
    @State private var programmaticScrollTarget: Date?
    @State private var editingTaskID: UUID?
    @State private var composerRequest: PlanningComposerRequest?
    @State private var agendaDay: Date?
    @State private var showDisplayOptions = false
    @State private var anchorSink = PlanningAnchorRef()
    @State private var addAnchor = PlanningAnchorRef()
    @State private var occurrenceCache = CalendarOccurrenceCache()
    @State private var pendingOccurrenceSchedule: CalendarOccurrenceScheduleRequest?

    @MainActor
    init(workspace: TaskWorkspaceModel, settings: PlanningSettingsStore? = nil, systemCalendar: CalendarSyncCoordinator? = nil) {
        let settings = settings ?? PlanningSettingsStore.shared
        self.workspace = workspace; self.settings = settings
        self.integration = systemCalendar ?? CalendarSyncCoordinator()
        let calendar = settings.calendar.configuredCalendar(workspace.calendar)
        let now = workspace.clock()
        _viewport = State(initialValue: CalendarViewport(date: now, mode: settings.calendar.mode, calendar: calendar))
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let firstWeek = PlanningProjection.weekStart(containing: first, calendar: calendar)
        _topWeek = State(initialValue: firstWeek)
        _programmaticScrollTarget = State(initialValue: firstWeek)
    }
    private var calendar: Calendar { settings.calendar.configuredCalendar(workspace.calendar) }
    private var mode: CalendarViewMode { settings.calendar.mode }
    private var selectedDay: Date { viewport.selectedDate }
    private var month: Date {
        firstOfMonth(mode == .month ? calendar.date(byAdding: .day, value: 14, to: topWeek) ?? topWeek : selectedDay)
    }
    private var occurrenceWindow: DateInterval {
        let first: Date
        let last: Date
        if mode == .month {
            let days = PlanningProjection.monthGridDays(containing: month, calendar: calendar)
            first = calendar.date(byAdding: .weekOfYear, value: -2, to: days.first ?? topWeek)!
            last = calendar.date(byAdding: .weekOfYear, value: 2, to: days.last ?? topWeek)!
        } else {
            first = mode == .day ? selectedDay : PlanningProjection.weekStart(containing: selectedDay, calendar: calendar)
            last = calendar.date(byAdding: .day, value: mode == .day ? 1 : 7, to: first)!
        }
        return DateInterval(start: first, end: last)
    }
    private var occurrences: [TaskOccurrence] {
        occurrenceCache.occurrences(tasks: workspace.tasksInActiveLists, in: occurrenceWindow, revision: workspace.revision,
                                    dateRevision: workspace.dateRevision, calendar: calendar)
    }
    private var visibleTasks: [Task] {
        occurrenceCache.visibleTasks(tasks: workspace.tasksInActiveLists, preferences: settings.calendar, in: occurrenceWindow,
            revision: workspace.revision, dateRevision: workspace.dateRevision, calendar: calendar)
    }
    private var recurrenceScopeActions: [WorkfollowDialogAction] {
        RecurrenceEditScope.allCases.map { scope in
            .secondary(scope.title) {
                guard let request = pendingOccurrenceSchedule else { return }
                _ = workspace.saveOccurrenceSchedule(request.plan, occurrence: request.occurrence, scope: scope)
                pendingOccurrenceSchedule = nil
            }
        } + [.cancel { pendingOccurrenceSchedule = nil }]
    }

    /// 摘要「在日历中查看」与小组件「本周」共用的一次性定位：切到周视图并选中该日期。
    private func consumeCalendarRevealRequest() {
        guard let day = environment.navigation.calendarRevealRequest else { return }
        environment.navigation.calendarRevealRequest = nil
        if mode != .week { settings.updateCalendar { $0.mode = .week } }
        viewport.mode = .week
        viewport.select(day, calendar: calendar)
    }

    var body: some View {
        GeometryReader { geometry in
            let paneWidth = settings.calendar.showArrangePane ? WFCalendarTimelineMetrics.arrangeWidth : 0
            VStack(alignment: .leading, spacing: 0) {
                toolbar.frame(width: geometry.size.width)
                HStack(spacing: 0) {
                    calendarContent
                        .frame(width: max(0, geometry.size.width - paneWidth - (paneWidth > 0 ? 1 : 0)), alignment: .topLeading)
                    if paneWidth > 0 {
                        Divider().frame(width: 1)
                        CalendarArrangePane(tasks: CalendarProjection.arrangePool(tasks: workspace.tasksInActiveLists, preferences: settings.calendar),
                                            onOpen: openTask, onArrange: { id in
                            _ = handleDrop([id.uuidString], .allDay(selectedDay))
                        }, anchorSink: anchorSink)
                        .frame(width: paneWidth)
                    }
                }
                .frame(width: geometry.size.width, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .workfollowPageSurface(0.90)
        .modifier(CalendarSwipeGestureModifier { direction in step(direction) })
        .coordinateSpace(name: PlanningCoordinateSpace.name)
        .sheet(isPresented: $showDisplayOptions) {
            CalendarDisplayOptions(settings: settings, lists: workspace.availableListNames, tags: workspace.tagNames)
        }
        .sheet(item: $systemEventDetails) { SystemCalendarEventDetails(event: $0) }
        .onAppear { integration.showEvents(in: occurrenceWindow); consumeCalendarRevealRequest() }
        .onChange(of: occurrenceWindow) { _, range in integration.showEvents(in: range) }
        .onChange(of: environment.navigation.calendarRevealRequest) { _, _ in consumeCalendarRevealRequest() }
        .workfollowAlert(
            "修改重复任务",
            isPresented: Binding(get: { pendingOccurrenceSchedule != nil },
                                 set: { if !$0 { pendingOccurrenceSchedule = nil } }),
            actions: recurrenceScopeActions)
        .overlayPreferenceValue(PlanningTaskAnchorsKey.self) { taskAnchors in
            GeometryReader { geometry in
            if let agendaDay {
                PlanningOverlayLayer(anchor: anchorSink, placement: .bottomEnd,
                                     size: CGSize(width: 330, height: 380), onDismiss: { self.agendaDay = nil }) {
                    CalendarDayAgenda(day: agendaDay,
                        tasks: CalendarProjection.agenda(on: agendaDay, tasks: visibleTasks, preferences: settings.calendar, calendar: calendar),
                        calendar: calendar, color: barColor, onOpen: { id in
                            self.agendaDay = nil; openTask(id)
                        }, onToggle: toggleTask, onCreate: {
                            self.agendaDay = nil; presentComposer(on: agendaDay)
                        }, externalEvents: ExternalCalendarProjection.events(on: agendaDay, events: integration.externalEvents, calendar: calendar),
                        onOpenEvent: { self.agendaDay = nil; systemEventDetails = $0 })
                }
            } else {
                PlanningWorkspaceChrome(workspace: workspace, anchor: anchorSink,
                                        request: $composerRequest, editingTaskID: $editingTaskID,
                                        taskHitRects: taskAnchors.values.flatMap { $0.map { geometry[$0] } })
            }
            }
        }
        .onChange(of: topWeek) { _, _ in
            guard mode == .month else { return }
            if !calendar.isDate(viewport.browseDate, equalTo: month, toGranularity: .month) {
                viewport.browseMonth(month, calendar: calendar)
            }
        }
        .onChange(of: settings.calendar.mode) { _, value in viewport.mode = value }
        .onChange(of: settings.calendar.firstWeekday) { _, _ in jumpToMonth(viewport.browseDate) }
    }
    @ViewBuilder private var calendarContent: some View {
        if mode == .month {
            CalendarMonthGridView(topWeek: $topWeek, programmaticTarget: $programmaticScrollTarget,
                month: month, today: workspace.clock(), selectedDay: selectedDay,
                showCompleted: settings.calendar.showCompleted, calendar: calendar, tasks: visibleTasks,
                barColor: barColor, onSelectDay: select, onOpenTask: openTask,
                onCreateTask: presentComposer, onDropTask: moveToDay,
                onToggleTask: toggleTask, onShowAgenda: showAgenda, anchorSink: anchorSink,
                externalEvents: integration.externalEvents, onOpenEvent: { systemEventDetails = $0 })
        } else {
            CalendarTimelineView(workspace: workspace, days: mode == .day ? [selectedDay] : PlanningProjection.weekDays(containing: selectedDay, calendar: calendar),
                tasks: visibleTasks, preferences: settings.calendar, calendar: calendar,
                color: barColor, onSelectDay: select, onOpenTask: openTask, onCreate: presentComposer,
                onMove: applySchedule,
                onDrop: handleDrop,
                onToggle: toggleTask,
                onHourHeightChange: { value in settings.updateCalendar { $0.hourHeight = value } },
                onAllDayHeightChange: { value in settings.updateCalendar { $0.allDayHeight = value } },
                anchorSink: anchorSink, externalEvents: integration.externalEvents, onOpenEvent: { systemEventDetails = $0 })
        }
    }
    private var toolbar: some View {
        HStack(spacing: 8) {
            Text(CalendarDayLabels.monthTitle(month, calendar: calendar)).font(WFType.pageTitle).foregroundStyle(WFColors.text).lineLimit(1)
            if mode == .day { Text(String(calendar.component(.day, from: selectedDay)) + "日").font(WFType.pageTitle) }
            Spacer(minLength: 0)
            Button {
                anchorSink.rect = addAnchor.rect; presentComposer(on: selectedDay)
            } label: { Image(systemName: "plus").frame(width: 32, height: 32) }
            .buttonStyle(.plain).background(PlanningAnchorProbe(ref: addAnchor)).hoverTip("新建任务")
            BusinessMenu {
                ForEach(CalendarViewMode.allCases, id: \.self) { value in
                    BusinessMenuOption(value.label, selected: value == mode) { settings.updateCalendar { $0.mode = value } }
                }
            } label: { Text(mode.label).font(WFType.control).frame(minWidth: 38, minHeight: 30) }
            .fixedSize().help("日历视图")
            ToolbarPill {
                HStack(spacing: 0) {
                    rangeButton("chevron.left", help: mode.previousLabel) { step(-1) }
                    Button("今天", action: goToday).buttonStyle(.plain).padding(.horizontal, 10)
                    rangeButton("chevron.right", help: mode.nextLabel) { step(1) }
                }
            }
            Button { settings.updateCalendar { $0.showArrangePane.toggle() } } label: {
                Image(systemName: "sidebar.right").frame(width: 30, height: 30)
                    .foregroundStyle(settings.calendar.showArrangePane ? WFColors.accent : WFColors.secondaryText)
            }.buttonStyle(.plain).hoverTip("安排任务")
            BusinessMenu {
                Toggle("显示已完成任务", isOn: preference(\.showCompleted))
                Toggle("显示未来重复周期", isOn: preference(\.showFutureOccurrences))
                Toggle("显示子任务", isOn: preference(\.showSubtasks))
                Divider()
                Button("显示设置…") { showDisplayOptions = true }
            } label: { Image(systemName: "ellipsis").frame(width: 30, height: 30) }
            .fixedSize().hoverTip("日历设置")
        }
        .padding(.horizontal, WFSpace.pageHorizontal)
        .frame(height: WFCalendarMetrics.toolbarHeight)
    }
    private func preference(_ path: WritableKeyPath<CalendarPreferences, Bool>) -> Binding<Bool> {
        Binding(get: { settings.calendar[keyPath: path] }, set: { value in settings.updateCalendar { $0[keyPath: path] = value } })
    }
    private func rangeButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 30, height: 30) }.buttonStyle(.plain).hoverTip(help)
    }
    private func step(_ direction: Int) {
        viewport.mode = mode; viewport.step(direction, calendar: calendar)
        jumpToMonth(viewport.browseDate)
    }
    private func goToday() { viewport.select(workspace.clock(), calendar: calendar); jumpToMonth(viewport.browseDate) }
    private func select(_ day: Date) {
        viewport.select(day, calendar: calendar)
        if !calendar.isDate(day, equalTo: month, toGranularity: .month) { jumpToMonth(day) }
    }
    private func jumpToMonth(_ date: Date) {
        let week = PlanningProjection.weekStart(containing: firstOfMonth(date), calendar: calendar)
        programmaticScrollTarget = week
        withAnimation(.easeOut(duration: 0.2)) { topWeek = week }
    }
    private func firstOfMonth(_ date: Date) -> Date { calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date }
    private func openTask(_ id: UUID) {
        guard editingTaskID != id else { return }
        if let occurrence = occurrences.first(where: { $0.task.id == id }), occurrence.isVirtual {
            workspace.selectOccurrence(occurrence)
            editingTaskID = occurrence.task.id
        } else { editingTaskID = id; workspace.select(id) }
    }
    private func toggleTask(_ id: UUID) {
        if let occurrence = occurrences.first(where: { $0.task.id == id }), occurrence.isVirtual {
            _ = workspace.completeOccurrence(occurrence)
        } else if let task = workspace.task(for: id) { _ = workspace.changeStatus(task) }
    }
    private func moveToDay(_ id: UUID, _ day: Date) {
        _ = handleDrop([id.uuidString], .day(day))
    }
    private func applySchedule(_ id: UUID, _ schedule: TaskSchedule) {
        consume(interaction.apply(id, schedule: schedule))
    }
    private var interaction: CalendarInteractionController {
        CalendarInteractionController(workspace: workspace, occurrences: occurrences, calendar: calendar)
    }
    private func handleDrop(_ values: [String], _ destination: CalendarDropDestination) -> Bool {
        let result = interaction.drop(values, at: destination)
        consume(result)
        return result.acceptsDrop
    }
    private func consume(_ result: CalendarInteractionOutcome) {
        if case .requiresScope(let occurrence, let plan) = result {
            pendingOccurrenceSchedule = CalendarOccurrenceScheduleRequest(occurrence: occurrence, plan: plan)
        }
    }
    private func showAgenda(_ day: Date) { select(day); agendaDay = day }
    private func presentComposer(on day: Date) { presentComposer(TaskSchedule(dueAt: calendar.startOfDay(for: day))) }
    private func presentComposer(_ schedule: TaskSchedule) {
        workspace.select(nil); editingTaskID = nil
        composerRequest = PlanningComposerRequest(fallback: schedule, preset: schedule, priority: .none)
    }
    private func barColor(_ id: UUID) -> Color {
        _ = visibleTasks
        guard let task = occurrenceCache.task(for: id) else { return WFColors.accent }
        switch settings.calendar.colorSource {
        case .task: return WFPlanningPalette.taskColor(taskID: id)
        case .list: return WFPlanningPalette.listColor(name: task.list.name, meta: workspace.listMeta(for: task.list.name))
        case .tag: return WFPlanningPalette.listColor(name: task.tags.first ?? task.list.name, meta: nil)
        case .priority:
            let index = switch task.priority { case .high: 0; case .medium: 1; case .low: 2; case .none: 3 }
            return WFPlanningPalette.quadrant[index]
        }
    }
}

private struct CalendarOccurrenceScheduleRequest {
    var occurrence: TaskOccurrence
    var plan: SchedulePlan
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

/// 月网格按像素连续滚动，视口露出 5 行，松手可停在一周中间。
/// `topWeek` 只同步浏览日期与标题；按钮导航单独发起程序化跳转。
///
/// 月从它开始的那一天开始，所以网格开头是上月收尾的日子、结尾是下月开头的日子。
/// 那些日子是真的格子：有自己的任务、也能被投放。
///
/// 每一行是三层的叠放，顺序就是设计：格子（带自己的小条）在最下；本行的跨天色带
/// 压在格子底色之上，色带才读得成一整块颜色而不是被六格底色切碎的漆；今天的洗色
/// 随后，穿过今天的那条色带也要被这一天染一层；细线最后，于是它穿过色带而不是
/// 止步于色带。
struct CalendarMonthGridView: View {
    /// 顶行周的起始日（周日）：滚动位置双向绑定。横扫/按钮跳月时由父级
    /// 更新（带动画），用户手指滚动时被实时回写。
    @Binding var topWeek: Date
    /// 标题月：邻月日期置灰的基准。
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
    let onShowAgenda: (Date) -> Void
    /// 浮层锚的落脚点：格与条在点击时把「自己是哪一块」写进去。
    let anchorSink: PlanningAnchorRef
    let externalEvents: [SystemCalendarEvent]
    let onOpenEvent: (SystemCalendarEvent) -> Void

    // 滚动性能三件套（2026-10-07，用户报"不够流畅"）：周行流、每日任务、
    // 每周色带全部预计算进 State——滚动期间的网格重估**零任务过滤/布局**，
    // 行级 Equatable 跳过未变行。重建只在 tasks/showCompleted 变化时发生。
    @StateObject private var cache: GridCache
    @State private var mountingTarget: Date?
    private var weeks: [Date] { cache.weeks }
    private var daysByWeek: [Date: [Date]] { cache.values.days }
    private var dayTasks: [Date: [Task]] { cache.values.dayTasks }
    private var spansByWeek: [Date: [CalendarSpan]] { cache.values.spans }

    private final class GridCache: ObservableObject {
        @Published var weeks: [Date]
        @Published var values: (days: [Date: [Date]], dayTasks: [Date: [Task]], spans: [Date: [CalendarSpan]])
        init(today: Date, tasks: [Task], showCompleted: Bool, calendar: Calendar) {
            let initialWeeks = CalendarMonthGridView.buildWeeks(today: today, calendar: calendar)
            weeks = initialWeeks
            values = CalendarMonthGridView.buildCaches(weeks: initialWeeks, tasks: tasks,
                                                       showCompleted: showCompleted, calendar: calendar)
        }
    }
    /// 父级程序化跳转哨（见 CalendarWorkspaceView.programmaticScrollTarget）。
    @Binding var programmaticTarget: Date?

    init(topWeek: Binding<Date>, programmaticTarget: Binding<Date?>,
         month: Date, today: Date, selectedDay: Date,
         showCompleted: Bool, calendar: Calendar, tasks: [Task],
         barColor: @escaping (UUID) -> Color, onSelectDay: @escaping (Date) -> Void,
         onOpenTask: @escaping (UUID) -> Void, onCreateTask: @escaping (Date) -> Void,
         onDropTask: @escaping (UUID, Date) -> Void, onToggleTask: @escaping (UUID) -> Void,
         onShowAgenda: @escaping (Date) -> Void,
         anchorSink: PlanningAnchorRef, externalEvents: [SystemCalendarEvent] = [],
         onOpenEvent: @escaping (SystemCalendarEvent) -> Void = { _ in }) {
        _topWeek = topWeek
        _mountingTarget = State(initialValue: topWeek.wrappedValue)
        _programmaticTarget = programmaticTarget
        self.month = month; self.today = today; self.selectedDay = selectedDay
        self.showCompleted = showCompleted; self.calendar = calendar; self.tasks = tasks
        self.barColor = barColor
        self.onSelectDay = onSelectDay; self.onOpenTask = onOpenTask
        self.onCreateTask = onCreateTask; self.onDropTask = onDropTask
        self.onToggleTask = onToggleTask; self.onShowAgenda = onShowAgenda; self.anchorSink = anchorSink
        self.externalEvents = externalEvents; self.onOpenEvent = onOpenEvent
        // 周行流**时间正序**（过去 → 今天 → 未来，±30 周对称）：两个方向都
        // 能滚。初始定位 = defaultScrollAnchor(.center)（内容几何中心 ≈ 今天
        // 周，自动挂载其±预热行）+ onAppear 近距 scrollTo 微调到月首周——
        // scrollTo 只对**已挂载附近**的目标可靠（横扫跳月 4-5 行实测成功；
        // 首帧前跳 30 行远距实测失败，见 git 历史），微调 1-2 行在预热集内。
        // StateObject defers creation until mounting; subsequent View values
        // must not rebuild the 61-week projection only to discard it.
        _cache = StateObject(wrappedValue: GridCache(today: topWeek.wrappedValue, tasks: tasks,
                                                   showCompleted: showCompleted, calendar: calendar))
    }

    /// 以浏览周为原点的 ±30 周。macOS 15+ 使用懒布局与偏移回写，
    /// macOS 14 使用实体化布局，保持 scrollPosition 的日期跟踪可靠。
    private static func buildWeeks(today: Date, calendar: Calendar) -> [Date] {
        let origin = startOfWeek(containing: today, calendar: calendar)
        return (-30...30).compactMap {
            calendar.date(byAdding: .weekOfYear, value: $0, to: origin)
        }
    }

    private static func buildCaches(weeks: [Date], tasks: [Task], showCompleted: Bool,
                                    calendar: Calendar)
        -> (days: [Date: [Date]], dayTasks: [Date: [Task]], spans: [Date: [CalendarSpan]]) {
        var days: [Date: [Date]] = [:]
        var dayTasks: [Date: [Task]] = [:]
        var spans: [Date: [CalendarSpan]] = [:]
        for weekStart in weeks {
            let weekDays = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
            days[weekStart] = weekDays
            for day in weekDays {
                let visible = PlanningProjection.singleDayTasks(on: day, from: tasks, calendar: calendar)
                dayTasks[day] = showCompleted ? visible : visible.filter { $0.status != .completed }
            }
            let filtered = showCompleted ? tasks : tasks.filter { $0.status != .completed }
            let multiDay = PlanningProjection.multiDayTasks(from: filtered,
                                                            first: weekDays.first ?? weekStart,
                                                            last: weekDays.last ?? weekStart,
                                                            calendar: calendar)
            spans[weekStart] = CalendarSpans.lanes(for: weekDays, tasks: multiDay, calendar: calendar)
        }
        return (days, dayTasks, spans)
    }

    var body: some View {
        VStack(spacing: 0) {
            weekHeader
            GeometryReader { geo in
                let rowHeight = geo.size.height / 5 // 视口固定露出 5 行
                if #available(macOS 15.0, *) {
                    // **视口化挂载（用户方案"邻近提前合成、远处按需"）**：
                    // LazyVStack 只挂载可视 ±预热行，滚动中锚探针/日号/任务条
                    // 从 61 行常驻降到 ~10 行——探针的逐帧坐标写回（427 → ~35）
                    // 是比图层合成更大的滚动 CPU 项。回写走 onScrollGeometry
                    // Change（offset→顶行），绕开 scrollPosition 在懒内容上
                    // 回写失灵的坑；程序化跳转走 scrollTo + 跳转哨。
                    ScrollViewReader { proxy in
                        lazyColumn(rowHeight: rowHeight)
                            .defaultScrollAnchor(.center)
                            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                                geometry.contentOffset.y
                            } action: { _, offset in
                                syncTopWeek(fromOffset: offset, rowHeight: rowHeight)
                            }
                            .onAppear {
                                // center 锚把今天周带到视口中央并挂载其邻近行，
                                // 这里近距 scrollTo 微调 1-2 行到月首周在顶。
                                DispatchQueue.main.async {
                                    proxy.scrollTo(topWeek, anchor: .top)
                                }
                            }
                            .onChange(of: programmaticTarget) { _, target in
                                // 导航请求与浏览日期分开：半行滚动后即使目标
                                // 仍是当前周，“今天”也需要执行定位。
                                guard let target else { return }
                                ensureWindow(containing: target)
                                DispatchQueue.main.async {
                                    programmaticTarget = nil
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        proxy.scrollTo(target, anchor: .top)
                                    }
                                }
                            }
                    }
                } else {
                    // macOS 14 回退：非 lazy（scrollPosition 绑定在懒内容上会
                    // 回写停住，标题脱节——2026-10-07 实测），回写靠绑定。
                    ScrollViewReader { proxy in
                        solidColumn(rowHeight: rowHeight)
                        .scrollPosition(id: positionBinding, anchor: .top)
                        .onAppear {
                            DispatchQueue.main.async { proxy.scrollTo(topWeek, anchor: .top) }
                        }
                        .onChange(of: programmaticTarget) { _, target in
                            guard let target else { return }
                            ensureWindow(containing: target)
                            programmaticTarget = nil
                            DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
                        }
                    }
                }
            }
        }
        .onChange(of: tasks) { _, newValue in
            rebuildCaches(tasks: newValue)
        }
        .onChange(of: showCompleted) { _, _ in rebuildCaches(tasks: tasks) }
        .onChange(of: calendar) { _, _ in
            cache.weeks = Self.buildWeeks(today: topWeek, calendar: calendar)
            rebuildCaches(tasks: tasks)
        }
    }

    // MARK: 列内容（两分支共用一行构造）

    @ViewBuilder
    private func weekRow(_ weekStart: Date, rowHeight: CGFloat) -> some View {
        let weekDays = daysByWeek[weekStart] ?? []
        MonthWeekRow(
            days: weekDays,
            month: month,
            today: today,
            selectedDay: selectedDay,
            isLastRow: false,
            calendar: calendar,
            spans: spansByWeek[weekStart] ?? [],
            dayTasks: weekDays.map { dayTasks[$0] ?? [] },
            barColor: barColor,
            onSelectDay: onSelectDay,
            onOpenTask: onOpenTask,
            onCreateTask: onCreateTask,
            onDropTask: onDropTask,
            onToggleTask: onToggleTask,
            onShowAgenda: onShowAgenda,
            anchorSink: anchorSink, externalEvents: externalEvents, onOpenEvent: onOpenEvent)
        .id(weekStart)
        .frame(height: rowHeight)
    }

    @ViewBuilder
    private func lazyColumn(rowHeight: CGFloat) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(weeks, id: \.self) { weekStart in
                    weekRow(weekStart, rowHeight: rowHeight)
                }
            }
            .scrollTargetLayout()
        }
    }

    private func solidColumn(rowHeight: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(weeks, id: \.self) { weekStart in
                    weekRow(weekStart, rowHeight: rowHeight)
                }
            }
            .scrollTargetLayout()
        }
    }

    /// 14- 回退分支的 scrollPosition 回写绑定（非 lazy 内容上可靠）。
    private var positionBinding: Binding<Date?> {
        Binding(get: { topWeek }, set: { if let value = $0 { topWeek = value } })
    }

    /// 偏移只更新邻近顶行的日期，不改动像素位置，保留任意幅度的滚动。
    private func syncTopWeek(fromOffset offset: CGFloat, rowHeight: CGFloat) {
        guard rowHeight > 0 else { return }
        let index = min(max(Int((offset + rowHeight / 2) / rowHeight), 0), weeks.count - 1)
        let target = weeks[index]
        if let initial = mountingTarget {
            guard target == initial else { return }
            mountingTarget = nil
        }
        if let pending = programmaticTarget, pending != target { return }
        if programmaticTarget == target { programmaticTarget = nil }
        if topWeek != target { topWeek = target }
    }

    private func ensureWindow(containing target: Date) {
        guard !weeks.contains(target) else { return }
        cache.weeks = Self.buildWeeks(today: target, calendar: calendar)
        rebuildCaches(tasks: tasks)
    }

    private func rebuildCaches(tasks: [Task]) {
        let caches = Self.buildCaches(weeks: weeks, tasks: tasks,
                                      showCompleted: showCompleted, calendar: calendar)
        cache.values = caches
    }

    static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// 周日在前，与网格的列偏移同源。两者必须一致：表头顺序与首列偏移不一致不
    /// 只是标错一列，而是把这个月的每个日期都挪到错误的星期上。
    private var weekHeader: some View {
        HStack(spacing: 0) {
            ForEach((0..<7).map { CalendarWeekHeaderLabels.all[(calendar.firstWeekday - 1 + $0) % 7] }, id: \.self) { label in
                Text(label)
                    .font(WFType.listMeta)
                    .foregroundStyle(WFColors.taskMetaText)
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
///
/// **性能契约（2026-10-07，用户报"不够流畅"）**：`spans` 与 `dayTasks` 是
/// 网格级缓存的预计算结果，行内**不做任何任务过滤/布局**；本视图遵守
/// `Equatable`（忽略回调与引用类型锚——它们捕获的 workspace 变化时 tasks
/// 必然变化，相等性不会漏更新）。滚动中每次行经过触发的网格重估，未变的
/// 行在这里被 SwiftUI 整行跳过，滚动只剩纯合成。
struct MonthWeekRow: View, Equatable {
    let days: [Date]
    let month: Date
    let today: Date
    let selectedDay: Date
    let isLastRow: Bool
    let calendar: Calendar
    /// 预计算：本周的跨天色带（已按 lane 摆放、已按 showCompleted 过滤）。
    let spans: [CalendarSpan]
    /// 预计算：按列索引的单日任务（已按 showCompleted 过滤）。
    let dayTasks: [[Task]]
    let barColor: (UUID) -> Color
    let onSelectDay: (Date) -> Void
    let onOpenTask: (UUID) -> Void
    let onCreateTask: (Date) -> Void
    let onDropTask: (UUID, Date) -> Void
    let onToggleTask: (UUID) -> Void
    let onShowAgenda: (Date) -> Void
    let anchorSink: PlanningAnchorRef
    var externalEvents: [SystemCalendarEvent] = []
    var onOpenEvent: (SystemCalendarEvent) -> Void = { _ in }

    static func == (lhs: MonthWeekRow, rhs: MonthWeekRow) -> Bool {
        lhs.days == rhs.days && lhs.month == rhs.month && lhs.today == rhs.today
            && lhs.selectedDay == rhs.selectedDay && lhs.isLastRow == rhs.isLastRow
            && lhs.calendar == rhs.calendar
            && lhs.spans == rhs.spans && lhs.dayTasks == rhs.dayTasks
            && lhs.externalEvents == rhs.externalEvents
    }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = geometry.size.width / 7
            ZStack(alignment: .topLeading) {
                // 邻月不再铺灰底：对齐滴答（白底 + 只有日号退成浅灰）。
                HStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.offset) { column, day in
                        dayCell(day, column: column, height: geometry.size.height)
                            .frame(width: columnWidth, height: geometry.size.height)
                    }
                }
                ForEach(visibleSpans(height: geometry.size.height)) { span in
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
            }.clipped()
        }
        // ⚠️ 不要加 .drawingGroup()：本环境实测整行 GPU 栅格化失败，渲染出
        // macOS 的"禁止"占位图（2026-10-07 截图实锤）。图层合并与不透明化
        // （backgroundLayer / hairlines 单 Path / gridHairline 预混合色）已
        // 把每行图层从 ~15 降到 ~6，滚动合成成本大幅下降，足够。
    }

    private func visibleSpans(height: CGFloat) -> [CalendarSpan] {
        let area = height - WFCalendarMetrics.cellTopPadding - WFCalendarMetrics.cellBottomPadding
            - WFCalendarMetrics.dayCellSize - WFCalendarMetrics.dayNumberGap
        let capacity = max(0, Int((area + WFCalendarMetrics.taskBarGap) / WFCalendarMetrics.slotStride))
        let overflowing = (0..<days.count).contains { column in
            let singles = column < dayTasks.count ? dayTasks[column].count : 0
            return CalendarSpans.slotsOver(spans, column: column) + singles > capacity
        }
        return spans.filter { $0.lane < max(0, capacity - (overflowing ? 1 : 0)) }
    }

    private func dayCell(_ day: Date, column: Int, height: CGFloat) -> some View {
        let visible = visibleSpans(height: height)
        let hidden = spans.filter { $0.fromColumn <= column && column <= $0.toColumn && !visible.contains($0) }.count
        return CalendarDayCellView(
            date: day,
            height: height,
            inMonth: calendar.component(.month, from: day) == calendar.component(.month, from: month)
                && calendar.component(.year, from: day) == calendar.component(.year, from: month),
            isToday: calendar.isDate(day, inSameDayAs: today),
            selected: calendar.isDate(day, inSameDayAs: selectedDay),
            skipSlots: CalendarSpans.slotsOver(visible, column: column),
            hiddenSpanCount: hidden,
            tasks: column < dayTasks.count ? dayTasks[column] : [],
            calendar: calendar,
            barColor: barColor,
            onSelect: { onSelectDay(day) },
            onOpenTask: onOpenTask,
            onCreate: { onCreateTask(day) },
            onDropTask: { id in onDropTask(id, day) },
            onToggleTask: onToggleTask,
            onShowAgenda: { onShowAgenda(day) },
            anchorSink: anchorSink,
            externalEvents: ExternalCalendarProjection.events(on: day, events: externalEvents, calendar: calendar), onOpenEvent: onOpenEvent)
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
    /// 每条色带处。合并为**一个 Path**（原 6 竖 + 1 横共 7 个独立图层/行），
    /// 颜色用预混合不透明的 `WFColors.gridHairline`（原 separator.opacity(0.5)
    /// 的半透明混合是滚动顿挫的主要成本之一）。isLastRow 参数保留（周视图
    /// 复用同一形态），月网格恒为 false——横向线照画，连续滚动中行间需要线。
    private func hairlines(columnWidth: CGFloat, height: CGFloat) -> some View {
        Path { path in
            for index in 1..<7 {
                path.addRect(CGRect(x: CGFloat(index) * columnWidth - 1, y: 0,
                                    width: 1, height: height))
            }
            path.addRect(CGRect(x: 0, y: height - 1, width: columnWidth * 7, height: 1))
        }
        .fill(WFColors.gridHairline)
        .frame(width: columnWidth * 7, height: height)
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
    var hiddenSpanCount: Int = 0
    let tasks: [Task]
    let calendar: Calendar
    let barColor: (UUID) -> Color
    let onSelect: () -> Void
    let onOpenTask: (UUID) -> Void
    let onCreate: () -> Void
    let onDropTask: (UUID) -> Void
    let onToggleTask: (UUID) -> Void
    let onShowAgenda: () -> Void
    let anchorSink: PlanningAnchorRef
    var externalEvents: [SystemCalendarEvent] = []
    var onOpenEvent: (SystemCalendarEvent) -> Void = { _ in }

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
            // 格底不再各画各的（2026-10-07 性能）：当月透出页面底色，邻月
            // 灰底由 MonthWeekRow 的 backgroundLayer 一笔画——省 7 层/行。
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
        // 非本月：用与日期面板月历同一个浅灰，别用 tertiaryText（偏暗）。
        if !inMonth { return WFColors.outOfMonthText }
        return selected ? WFColors.accent : WFColors.text
    }

    /// 格高装得下几条就画几条，色带占掉的槽位先扣掉。
    ///
    /// 格子自己量而不接受「显示几条」的指令：行高取决于窗口，高窗口显五条、矮窗口
    /// 显两条。要计数时把最后一条槽位还给计数——只剩一条的位置时，计数会把唯一的
    /// 槽位吃掉、让这一天看起来是空的，所以一格一条时显示第一条、不显示计数。
    @ViewBuilder
    private var bars: some View {
        let totalCapacity = max(0, Int(floor((barAreaHeight + WFCalendarMetrics.taskBarGap) / WFCalendarMetrics.slotStride)))
        let capacity = max(0, totalCapacity - skipSlots)
        let items = ExternalCalendarProjection.items(tasks: tasks, events: externalEvents)
        let overflowing = items.count + hiddenSpanCount > capacity
        let counting = overflowing && capacity > 0
        let visibleCount = min(items.count, max(0, capacity - (counting ? 1 : 0)))
        VStack(alignment: .leading, spacing: WFCalendarMetrics.taskBarGap) {
            if skipSlots > 0 { Spacer().frame(height: CGFloat(skipSlots) * WFCalendarMetrics.slotStride - WFCalendarMetrics.taskBarGap) }
            ForEach(Array(items.prefix(visibleCount))) { item in
                switch item {
                case let .task(task): bar(task)
                case let .event(event): SystemCalendarEventBar(event: event) { onOpenEvent(event) }
                }
            }
            if counting {
                CalendarTaskOverflowView(hiddenCount: items.count - visibleCount + hiddenSpanCount, onTap: {
                    anchorSink.rect = anchor.rect
                    onShowAgenda()
                })
            }
            Spacer(minLength: 0)
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
        .planningTaskTarget(task.id)
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
        .planningTaskTarget(span.task.id)
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
                .hoverTip(completed ? "恢复任务" : "完成任务")
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
        // 滴答对齐（2026-10-07，用户拍板）：色带扁平化——不画投影（真投影每条
        // 每帧一次离屏高斯模糊，滚动时是最大的单点合成成本），改一圈预混合不
        // 透明浅描边与格底区分。格内单日任务条本来就是平的，两种条就此一致。
        .overlay {
            RoundedRectangle(cornerRadius: WFSpace.tight)
                .strokeBorder(WFColors.gridHairline, lineWidth: 1)
        }
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
        .background {
            if dropping {
                WFColors.accentSoft
            } else {
                ThemedPageSurface(opacity: 0.94)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                .hoverTip(completed ? "恢复任务" : "完成任务")
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
        .rowHoverBackground(cornerRadius: WFCalendarMetrics.controlRadius,
                            idleFill: color.opacity(WFCalendarMetrics.taskBarFill(completed: completed)),
                            hoverFill: color.opacity(min(1, WFCalendarMetrics.taskBarFill(completed: completed) + 0.08)))
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
            .planningTaskTarget(task.id)
    }
}
