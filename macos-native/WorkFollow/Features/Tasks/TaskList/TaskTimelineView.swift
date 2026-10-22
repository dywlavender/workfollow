import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Inputs have already passed the caller's scope, saved filter and completion rules.
struct TaskTimelineView: View {
    let tasks: [Task]
    @ObservedObject var workspace: TaskWorkspaceModel
    let allowsCreation: Bool
    let onCreate: (TaskSchedule) -> Void
    let onSelect: (UUID) -> Void
    @State private var viewport: TaskTimelineViewport
    @State private var colorSource: TaskTimelineColorSource = .list
    @State private var showsPool = true
    @State private var dropTargeted = false
    @State private var scrollRevision = 0
    @State private var pendingSchedule: TaskTimelinePendingSchedule?

    init(tasks: [Task], workspace: TaskWorkspaceModel, allowsCreation: Bool = true,
         onCreate: @escaping (TaskSchedule) -> Void = { _ in },
         onSelect: @escaping (UUID) -> Void) {
        self.tasks = tasks; self.workspace = workspace
        self.allowsCreation = allowsCreation; self.onCreate = onCreate; self.onSelect = onSelect
        _viewport = State(initialValue: TaskTimelineViewport(anchorDate: workspace.clock()))
    }

    private var partition: TaskTimelineTaskPartition { TaskTimelineLayout.partition(tasks) }
    private var interaction: TaskTimelineInteractionController {
        TaskTimelineInteractionController(workspace: workspace, tasks: tasks)
    }

    var body: some View {
        GeometryReader { geometry in
            let poolWidth = min(224, max(166, geometry.size.width * 0.24))
            let mainWidth = max(1, geometry.size.width - (showsPool ? poolWidth + 1 : 0))
            let labelWidth = min(208, max(126, mainWidth * 0.27))
            let gridWidth = max(1, mainWidth - labelWidth - 1)
            let range = viewport.range(availableWidth: gridWidth, calendar: workspace.calendar)
            VStack(spacing: 0) {
                toolbar(range: range, gridWidth: gridWidth)
                Divider()
                HStack(alignment: .top, spacing: 0) {
                    GeometryReader { timelineGeometry in
                        timeline(range: range, labelWidth: labelWidth,
                                 availableHeight: timelineGeometry.size.height)
                    }
                    .frame(width: mainWidth)
                    if showsPool {
                        Divider()
                        unscheduledPool.frame(width: poolWidth)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(minHeight: 220)
        .background(WFColors.content)
        .coordinateSpace(name: TaskTimelineRenderFramesKey.coordinateSpace)
        .onChange(of: viewport.scale) { _, _ in scrollRevision += 1 }
        .confirmationDialog("修改重复任务", isPresented: Binding(
            get: { pendingSchedule != nil }, set: { if !$0 { pendingSchedule = nil } }
        ), titleVisibility: .visible) {
            if let request = pendingSchedule {
                ForEach(RecurrenceEditScope.allCases) { scope in
                    Button(scope.title) {
                        _ = interaction.confirm(request, scope: scope)
                        pendingSchedule = nil
                    }
                }
                Button("取消", role: .cancel) { pendingSchedule = nil }
            }
        }
        .accessibilityIdentifier("tasks.timeline")
    }

    private func toolbar(range: TaskTimelineRange, gridWidth: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                navigationControls(gridWidth: gridWidth)
                rangeTitle(range)
                Spacer(minLength: 8)
                displayControls
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack { navigationControls(gridWidth: gridWidth); rangeTitle(range); Spacer(minLength: 0) }
                HStack { displayControls; Spacer(minLength: 0) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(WFColors.content)
    }

    private func navigationControls(gridWidth: CGFloat) -> some View {
        HStack(spacing: 4) {
            Button {
                viewport.step(-1, availableWidth: gridWidth, calendar: workspace.calendar)
                scrollRevision += 1
            } label: { Image(systemName: "chevron.left").frame(width: 24, height: 24) }
                .help("上一段日期").accessibilityLabel("上一段日期")
            Button("今天") {
                viewport.goToday(workspace.clock(), calendar: workspace.calendar)
                scrollRevision += 1
            }
            .padding(.horizontal, 4).accessibilityIdentifier("tasks.timeline.today")
            Button {
                viewport.step(1, availableWidth: gridWidth, calendar: workspace.calendar)
                scrollRevision += 1
            } label: { Image(systemName: "chevron.right").frame(width: 24, height: 24) }
                .help("下一段日期").accessibilityLabel("下一段日期")
        }
        .buttonStyle(.plain).font(WFType.supporting)
    }

    private func rangeTitle(_ range: TaskTimelineRange) -> some View {
        Text(range.start.formatted(.dateTime.year().month().day().locale(.appDate)))
            .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }

    private var displayControls: some View {
        HStack(spacing: 10) {
            Picker("刻度", selection: $viewport.scale) {
                ForEach(TaskTimelineScale.allCases) { scale in Text(scale.title).tag(scale) }
            }
            .pickerStyle(.segmented).frame(width: 132).controlSize(.small)
            .accessibilityIdentifier("tasks.timeline.scale")
            BusinessMenu {
                BusinessMenuChoices(selection: $colorSource, options: TaskTimelineColorSource.allCases.map { BusinessChoice($0, $0.title) })
            } label: { Image(systemName: "paintpalette").frame(width: 22, height: 24) }
            .fixedSize()
            .help("按\(colorSource.title)显示任务颜色")
            Button { showsPool.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sidebar.right")
                    Text("未安排 \(partition.unscheduled.count)")
                }
                .font(WFType.supporting).padding(.horizontal, 7).padding(.vertical, 5)
                .background(showsPool ? WFColors.listSelection : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain).accessibilityIdentifier("tasks.timeline.pool-toggle")
        }
    }

    /// Both columns share one vertical scroll; the dates alone scroll horizontally.
    private func timeline(range: TaskTimelineRange, labelWidth: CGFloat,
                          availableHeight: CGFloat) -> some View {
        let rows = partition.scheduled
        // 保留原生滚动条的完整高度；叠加模式下这部分留在网格底部。
        let scrollerHeight = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        let contentHeight = max(CGFloat(rows.count) * TaskTimelineLayout.rowHeight,
                                availableHeight - TaskTimelineLayout.headerHeight - scrollerHeight)
        let scrollHeight = contentHeight + TaskTimelineLayout.headerHeight + scrollerHeight
        return ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Text("任务").font(WFType.sectionSemibold).foregroundStyle(WFColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
                        .frame(height: TaskTimelineLayout.headerHeight)
                        .overlay(alignment: .bottom) { Divider() }
                    VStack(spacing: 0) {
                        ForEach(rows) { task in taskLabel(task) }
                        if rows.isEmpty {
                            Text("尚无已安排任务").font(WFType.supporting)
                                .foregroundStyle(WFColors.tertiaryText).padding(.top, 18)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: contentHeight, alignment: .top)
                }
                .frame(width: labelWidth).background(WFColors.content)
                .taskTimelineFrame(.labels)
                Rectangle().fill(WFColors.border).frame(width: 1)
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        dateHeader(range)
                        dateCanvas(range: range, rows: rows, height: contentHeight)
                    }
                    .frame(width: range.contentWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .id(TaskTimelineScrollIdentity(start: range.start, scale: viewport.scale, revision: scrollRevision))
                .frame(height: scrollHeight)
                .accessibilityIdentifier("tasks.timeline.date-scroll")
            }
            .frame(height: scrollHeight)
        }
    }

    private func taskLabel(_ task: Task) -> some View {
        Button { onSelect(task.id) } label: {
            HStack(spacing: 7) {
                Circle().fill(color(task)).frame(width: 6, height: 6)
                Text(task.title.isEmpty ? "无标题" : task.title)
                    .font(WFType.listBody).lineLimit(1)
                    .foregroundStyle(task.isClosed ? WFColors.taskCompletedPreview : WFColors.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity).frame(height: TaskTimelineLayout.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(workspace.selectedTaskID == task.id ? WFColors.listSelection : Color.clear)
        .overlay(alignment: .bottom) { Divider() }.help(task.title)
        .accessibilityIdentifier("tasks.timeline.label.\(task.id.uuidString)")
    }

    private func dateHeader(_ range: TaskTimelineRange) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(TaskTimelineLayout.headerSegments(in: range, scale: viewport.scale, calendar: workspace.calendar)) { segment in
                    Text(headerContext(segment.date)).font(WFType.supporting).lineLimit(1)
                        .foregroundStyle(WFColors.tertiaryText)
                        .frame(width: CGFloat(segment.dayCount) * range.dayWidth, height: TaskTimelineLayout.headerRowHeight,
                               alignment: viewport.scale == .day ? .center : .leading)
                        .overlay(alignment: .leading) { Rectangle().fill(WFColors.border.opacity(0.55)).frame(width: 1) }
                }
            }
            HStack(spacing: 0) {
                ForEach(0..<range.dayCount, id: \.self) { index in
                    let day = range.day(index, calendar: workspace.calendar)
                    let today = workspace.calendar.isDate(day, inSameDayAs: workspace.clock())
                    Text(day, format: .dateTime.day().locale(.appDate))
                        .font(WFType.supporting).foregroundStyle(today ? WFColors.accent : WFColors.secondaryText)
                        .frame(width: range.dayWidth, height: TaskTimelineLayout.headerRowHeight)
                        .background(today ? WFColors.accent.opacity(0.08) : Color.clear)
                        .overlay(alignment: .leading) { Rectangle().fill(WFColors.border.opacity(0.55)).frame(width: 1) }
                }
            }
        }
        .padding(.vertical, TaskTimelineLayout.headerVerticalPadding)
        .frame(height: TaskTimelineLayout.headerHeight)
        .overlay(alignment: .bottom) { Divider() }
        .taskTimelineFrame(.header)
    }

    private func headerContext(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = workspace.calendar; formatter.timeZone = workspace.calendar.timeZone
        formatter.locale = .appDate
        switch viewport.scale {
        case .day: formatter.dateFormat = "EE"
        case .week: formatter.dateFormat = " M月d日"
        case .month: formatter.dateFormat = " yyyy年M月"
        }
        return formatter.string(from: day)
    }

    private func dateCanvas(range: TaskTimelineRange, rows: [Task], height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            TaskTimelineGrid(range: range, calendar: workspace.calendar, now: workspace.clock())
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    guard allowsCreation else { return }
                    onCreate(TaskTimelineLayout.creation(at: value.location.x, in: range, calendar: workspace.calendar))
                })
                .modifier(TaskRowActivationPolicy())
            VStack(spacing: 0) {
                ForEach(rows) { task in
                    TaskTimelineTaskBar(task: task, range: range, calendar: workspace.calendar,
                        color: color(task), allowsEditing: allowsCreation,
                        onSelect: { onSelect(task.id) },
                        onCommit: { consume(interaction.apply(task.id, schedule: $0)) },
                        onLocate: {
                            if let due = task.schedule.dueAt { viewport.anchorDate = due; scrollRevision += 1 }
                        })
                }
            }
            if rows.isEmpty {
                Text(allowsCreation ? "点击空白日期添加任务，或从右侧拖入未安排任务" : "当前范围没有已安排任务")
                    .font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                    .padding(18).allowsHitTesting(false)
            }
        }
        .frame(width: range.contentWidth, height: height, alignment: .topLeading)
        .overlay {
            if dropTargeted { Rectangle().stroke(WFColors.accent, lineWidth: 2).allowsHitTesting(false) }
        }
        .onDrop(of: [UTType.utf8PlainText], delegate: TaskTimelineDropDelegate(
            allowsDrop: allowsCreation, onTargeted: { dropTargeted = $0 },
            onDrop: { id, location in
                let outcome = interaction.drop([id.uuidString],
                    on: range.date(at: location.x, calendar: workspace.calendar))
                NativeAcceptanceInteractionTrace.record("task-timeline.drop.commit", ["accepted": outcome.acceptsDrop])
                consume(outcome)
            }))
        .taskTimelineFrame(.grid)
        .accessibilityIdentifier("tasks.timeline.grid")
    }

    private var unscheduledPool: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("未安排").font(WFType.sectionSemibold)
                Text("\(partition.unscheduled.count)").font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(height: TaskTimelineLayout.headerHeight)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(allowsCreation ? "拖到日期上安排任务" : "当前清单不可安排任务")
                        .font(WFType.supporting).foregroundStyle(WFColors.tertiaryText).padding(.bottom, 4)
                    ForEach(partition.unscheduled) { task in poolTask(task) }
                    if partition.unscheduled.isEmpty {
                        Text("当前范围没有未安排任务").font(WFType.supporting)
                            .foregroundStyle(WFColors.tertiaryText).padding(.top, 12)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity).background(WFColors.secondarySurface)
        .accessibilityIdentifier("tasks.timeline.pool")
    }

    @ViewBuilder private func poolTask(_ task: Task) -> some View {
        if allowsCreation {
            // Transferable destinations negotiate copy, while the shared action
            // updates this task's schedule. Match the board's in-app policy.
            poolCard(task).draggable(task.id.uuidString)
                .modifier(TaskReorderDragPolicy(allowsCopyWithinApp: true))
        }
        else { poolCard(task) }
    }

    private func poolCard(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(task.title.isEmpty ? "无标题" : task.title).font(WFType.listBody).lineLimit(2)
            Text(task.list.name).font(WFType.supporting).foregroundStyle(WFColors.secondaryText).lineLimit(1)
        }
        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1).fill(color(task)).frame(width: 3) }
        .contentShape(Rectangle()).onTapGesture { onSelect(task.id) }
        .modifier(TaskRowActivationPolicy())
        .accessibilityIdentifier("tasks.timeline.unscheduled.\(task.id.uuidString)")
        .taskTimelineFrame(.poolTask(task.id))
    }

    private func color(_ task: Task) -> Color {
        switch colorSource {
        case .list: return WFListPalette.color(for: task.list.name, meta: workspace.listMeta(for: task.list.name))
        case .tag:
            if let name = task.tags.first, let value = workspace.tag(named: name)?.colorARGB { return WFListPalette.swatch(value) }
            return WFColors.accent
        case .priority: return task.priority == .none ? WFColors.accent : TaskRowPriority.color(task.priority)
        }
    }

    private func consume(_ outcome: CalendarInteractionOutcome) {
        if case .requiresScope(let occurrence, let plan) = outcome {
            pendingSchedule = TaskTimelinePendingSchedule(occurrence: occurrence, plan: plan)
        }
    }
}

private struct TaskTimelineScrollIdentity: Hashable {
    let start: Date
    let scale: TaskTimelineScale
    let revision: Int
}

private struct TaskTimelineGrid: View {
    let range: TaskTimelineRange
    let calendar: Calendar
    let now: Date

    var body: some View {
        Canvas { context, size in
            let today = calendar.startOfDay(for: now)
            let index = calendar.dateComponents([.day], from: range.start, to: today).day ?? -1
            if (0..<range.dayCount).contains(index) {
                context.fill(Path(CGRect(x: CGFloat(index) * range.dayWidth, y: 0,
                    width: range.dayWidth, height: size.height)), with: .color(WFColors.accent.opacity(0.045)))
            }
            var lines = Path()
            for day in 0...range.dayCount {
                let x = CGFloat(day) * range.dayWidth
                lines.move(to: CGPoint(x: x, y: 0)); lines.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(lines, with: .color(WFColors.border.opacity(0.55)), lineWidth: 1)
            var rows = Path()
            for row in 0...Int(ceil(size.height / TaskTimelineLayout.rowHeight)) {
                let y = CGFloat(row) * TaskTimelineLayout.rowHeight
                rows.move(to: CGPoint(x: 0, y: y)); rows.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(rows, with: .color(WFColors.border.opacity(0.4)), lineWidth: 1)
        }
    }
}

private struct TaskTimelineTaskBar: View {
    let task: Task
    let range: TaskTimelineRange
    let calendar: Calendar
    let color: Color
    let allowsEditing: Bool
    let onSelect: () -> Void
    let onCommit: (TaskSchedule) -> Void
    let onLocate: () -> Void
    @State private var draft = TaskTimelineGestureDraft()
    @State private var hovering = false
    @FocusState private var focused: Bool
    private var displayed: TaskSchedule { draft.schedule ?? task.schedule }

    var body: some View {
        ZStack(alignment: .leading) {
            if let geometry = TaskTimelineLayout.bar(for: displayed, in: range, calendar: calendar) {
                bar(width: max(1, geometry.width - 4)).offset(x: geometry.x + 2)
            } else {
                Button(action: onLocate) {
                    Label("定位安排日期", systemImage: "arrow.right.to.line")
                        .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                }
                .buttonStyle(.plain).padding(.leading, 8)
            }
        }
        .frame(width: range.contentWidth, height: TaskTimelineLayout.rowHeight, alignment: .leading)
    }

    private func bar(width: CGFloat) -> some View {
        Text(task.title.isEmpty ? "无标题" : task.title)
            .font(WFType.supporting).lineLimit(1).padding(.horizontal, 10)
            .frame(width: width, height: 26, alignment: .leading)
            .foregroundStyle(task.isClosed ? WFColors.taskCompletedPreview : WFColors.text)
            .background(color.opacity(task.isClosed ? 0.12 : 0.23), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(hovering ? 0.8 : 0.3), lineWidth: 1))
            .overlay(alignment: .leading) { if allowsEditing { resizeHandle(.start) } }
            .overlay(alignment: .trailing) { if allowsEditing { resizeHandle(.end) } }
            .overlay(alignment: .topLeading) {
                if draft.isActive, draft.schedule != nil {
                    Text(scheduleLabel).font(.system(size: 10).monospacedDigit())
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 3))
                        .fixedSize().offset(y: -22).allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle()).onTapGesture(perform: onSelect)
            .gesture(drag(.move), including: allowsEditing ? .all : .none)
            .modifier(TaskRowActivationPolicy())
            .focusable().focusEffectDisabled().focused($focused)
            .onExitCommand { draft.cancel() }.onHover { hovering = $0 }
            .background(TaskTimelineGestureEscapeRouter(isActive: draft.isActive) { draft.cancel() })
            .help(scheduleLabel)
            .accessibilityLabel(task.title.isEmpty ? "无标题任务" : task.title)
            .accessibilityValue(scheduleLabel)
            .accessibilityIdentifier("tasks.timeline.bar.\(task.id.uuidString)")
            .taskTimelineFrame(.taskBar(task.id))
    }

    private func resizeHandle(_ edge: TaskTimelineGestureOperation) -> some View {
        Color.clear.frame(width: range.dayWidth < 24 ? 4 : 8, height: 26).contentShape(Rectangle())
            .overlay { Capsule().fill(color.opacity(hovering ? 0.75 : 0)).frame(width: 2, height: 12) }
            .onHover { entered in (entered ? NSCursor.resizeLeftRight : NSCursor.arrow).set() }
            .highPriorityGesture(drag(edge))
            .accessibilityLabel(edge == .start ? "调整开始日期" : "调整结束日期")
    }

    private func drag(_ operation: TaskTimelineGestureOperation) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                focused = true
                draft.update(task.schedule, operation: operation, translation: value.translation.width,
                             dayWidth: range.dayWidth, calendar: calendar)
            }
            .onEnded { value in
                draft.update(task.schedule, operation: operation, translation: value.translation.width,
                             dayWidth: range.dayWidth, calendar: calendar)
                if let schedule = draft.finish() { onCommit(schedule) }
            }
    }

    private var scheduleLabel: String {
        let formatter = DateFormatter()
        formatter.locale = .appDate; formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = displayed.hasTime ? "M/d HH:mm" : "M/d"
        guard let start = displayed.dueAt else { return "未安排" }
        let first = formatter.string(from: start)
        return displayed.dueEndAt.map { first + " – " + formatter.string(from: $0) } ?? first
    }
}

/// Registered only for an active press, even if another native responder owns focus.
struct TaskTimelineGestureEscapeRouter: View {
    let isActive: Bool
    let onEscape: () -> Void
    var body: some View {
        if isActive { PopupEscapeRouter(depth: PopupEscapeRank.embedded, onEscape: onEscape) }
    }
}

enum TaskTimelineRenderAnchor: Hashable { case labels, header, grid, taskBar(UUID), poolTask(UUID) }

struct TaskTimelineRenderFramesKey: PreferenceKey {
    static let coordinateSpace = "tasks.timeline.layout"
    static var defaultValue: [TaskTimelineRenderAnchor: CGRect] { [:] }
    static func reduce(value: inout [TaskTimelineRenderAnchor: CGRect],
                       nextValue: () -> [TaskTimelineRenderAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, last in last })
    }
}

private extension View {
    func taskTimelineFrame(_ anchor: TaskTimelineRenderAnchor) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: TaskTimelineRenderFramesKey.self,
                value: [anchor: geometry.frame(in: .named(TaskTimelineRenderFramesKey.coordinateSpace))])
        }.allowsHitTesting(false))
    }
}
