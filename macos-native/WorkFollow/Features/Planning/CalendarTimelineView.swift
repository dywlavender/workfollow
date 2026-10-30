import AppKit
import SwiftUI

/// These are centralized engineering defaults. Gesture step and geometry are
/// calibrated against the reference client rather than inferred from a nib.
enum WFCalendarTimelineMetrics {
    static let axisWidth: CGFloat = 48
    static let headerHeight: CGFloat = 44
    static let arrangeWidth: CGFloat = 220
    static let minimumBlockHeight: CGFloat = 22
    static let blockInset: CGFloat = 3
    static let resizeHandleHeight: CGFloat = 6
}

struct CalendarTimelineView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let days: [Date]
    let tasks: [Task]
    let preferences: CalendarPreferences
    let calendar: Calendar
    let color: (UUID) -> Color
    let onSelectDay: (Date) -> Void
    let onOpenTask: (UUID) -> Void
    let onCreate: (TaskSchedule) -> Void
    let onMove: (UUID, TaskSchedule) -> Void
    let onDrop: ([String], CalendarDropDestination) -> Bool
    let onToggle: (UUID) -> Void
    let onHourHeightChange: (Double) -> Void
    let onAllDayHeightChange: (Double) -> Void
    let anchorSink: PlanningAnchorRef
    var externalEvents: [SystemCalendarEvent] = []
    var onOpenEvent: (SystemCalendarEvent) -> Void = { _ in }
    @State private var scaleDraft: CalendarTimelineScaleDraft?
    @State private var pinchActive = false
    @State private var allDayHeightDraft: Double?
    @State private var scrollController = CalendarTimelineScrollController()
    @State private var scrollRequest: CalendarTimelineScrollRequest?
    @State private var scrollRequestID = 0
    private var hourHeight: Double { scaleDraft?.hourHeight ?? preferences.hourHeight }
    private var displayedPreferences: CalendarPreferences {
        var value = preferences
        value.hourHeight = hourHeight
        value.allDayHeight = allDayHeightDraft ?? preferences.allDayHeight
        return value
    }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = max(1, (geometry.size.width - WFCalendarTimelineMetrics.axisWidth) / CGFloat(max(1, days.count)))
            VStack(spacing: 0) {
                dayHeader(columnWidth: columnWidth)
                CalendarAllDayArea(days: days, tasks: tasks, preferences: displayedPreferences, calendar: calendar,
                    columnWidth: columnWidth, color: color, onOpen: onOpenTask, onToggle: onToggle,
                    onCreate: onCreate, onDrop: onDrop, anchorSink: anchorSink,
                    externalEvents: externalEvents, onOpenEvent: onOpenEvent)
                CalendarAllDayHeightHandle(height: displayedPreferences.allDayHeight,
                    onPreview: { allDayHeightDraft = $0 }, onCommit: onAllDayHeightChange)
                    ScrollView(.vertical) {
                        ZStack(alignment: .topLeading) {
                            timeLabels
                            HStack(alignment: .top, spacing: 0) {
                                Color.clear.frame(width: WFCalendarTimelineMetrics.axisWidth)
                                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                                    CalendarTimelineDay(day: day, dayIndex: index, days: days,
                                        placements: CalendarProjection.timed(on: day, tasks: tasks, preferences: preferences, calendar: calendar),
                                        hourHeight: CGFloat(hourHeight), columnWidth: columnWidth,
                                        calendar: calendar, color: color, onOpen: onOpenTask, onCreate: onCreate,
                                        onMove: onMove, onDrop: onDrop, onToggle: onToggle, anchorSink: anchorSink,
                                        externalEvents: externalEvents, onOpenEvent: onOpenEvent)
                                    .frame(width: columnWidth)
                                }
                            }
                            currentTimeLine(columnWidth: columnWidth)
                        }
                        .frame(width: geometry.size.width, height: CGFloat(hourHeight) * 24, alignment: .topLeading)
                        .background(CalendarTimelineScrollProbe(controller: scrollController,
                            hourHeight: hourHeight, request: scrollRequest,
                            onZoomWheel: zoomWheel, onZoomWheelEnded: finishZoom))
                    }
                    .simultaneousGesture(MagnifyGesture().onChanged { value in
                        if !pinchActive {
                            scrollController.cancelWheelFinish()
                            scaleDraft = CalendarTimelineScaleDraft(hourHeight: hourHeight,
                                scrollOffset: scrollController.scrollOffset, viewportHeight: scrollController.viewportHeight)
                            pinchActive = true
                        }
                        scaleDraft?.magnify(Double(value.magnification))
                        requestScaleScroll()
                    }.onEnded { _ in pinchActive = false; finishZoom() })
                    .help("双指缩放，或按住 Ctrl 滚动缩放时间轴")
                    .accessibilityIdentifier("calendar.timeline-scroll")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .onDisappear { pinchActive = false; finishZoom(); scrollController.detach() }
        .accessibilityIdentifier("calendar.timeline")
    }
    private func zoomWheel(_ delta: Double, anchorY: Double) {
        guard !pinchActive else { return }
        if scaleDraft == nil {
            scaleDraft = CalendarTimelineScaleDraft(hourHeight: hourHeight,
                scrollOffset: scrollController.scrollOffset, viewportHeight: scrollController.viewportHeight, anchorY: anchorY)
        }
        scaleDraft?.scroll(delta)
        requestScaleScroll()
    }
    private func requestScaleScroll() {
        guard let scaleDraft else { return }
        scrollRequestID += 1
        scrollRequest = CalendarTimelineScrollRequest(id: scrollRequestID, hourHeight: scaleDraft.hourHeight,
                                                     offset: scaleDraft.scrollOffset)
    }
    private func finishZoom() {
        guard let scaleDraft else { return }
        onHourHeightChange(scaleDraft.hourHeight)
        self.scaleDraft = nil
    }
    private func dayHeader(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: WFCalendarTimelineMetrics.axisWidth, height: WFCalendarTimelineMetrics.headerHeight)
            ForEach(days, id: \.self) { day in
                Button { onSelectDay(day) } label: {
                    VStack(spacing: 3) {
                        Text("周" + CalendarWeekHeaderLabels.weekdayName(calendar.component(.weekday, from: day))).font(WFType.caption)
                        Text(String(calendar.component(.day, from: day))).font(WFType.sectionSemibold)
                    }
                    .foregroundStyle(calendar.isDate(day, inSameDayAs: workspace.clock()) ? WFColors.accent : WFColors.text)
                    .frame(width: columnWidth, height: WFCalendarTimelineMetrics.headerHeight)
                }.buttonStyle(.plain)
            }
        }
        .frame(height: WFCalendarTimelineMetrics.headerHeight)
    }
    private var timeLabels: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 10)).foregroundStyle(WFColors.secondaryText)
                    .frame(width: WFCalendarTimelineMetrics.axisWidth - 5, height: CGFloat(hourHeight), alignment: .topTrailing)
                    .id("calendar-hour-\(hour)")
            }
        }.allowsHitTesting(false)
    }
    private func currentTimeLine(columnWidth: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let now = workspace.clock()
            if let index = days.firstIndex(where: { calendar.isDate($0, inSameDayAs: now) }) {
                let minutes = Double(calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now))
                Rectangle().fill(WFColors.danger).frame(width: columnWidth, height: 1)
                    .offset(x: WFCalendarTimelineMetrics.axisWidth + CGFloat(index) * columnWidth,
                            y: CGFloat(minutes / 60 * hourHeight))
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct CalendarAllDayHeightHandle: View {
    let height: Double
    let onPreview: (Double?) -> Void
    let onCommit: (Double) -> Void
    @State private var initialHeight: Double?
    @State private var session = CalendarGestureSession()
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Rectangle().fill(WFColors.border.opacity(0.5))
            .frame(height: 5)
            .overlay { Capsule().fill(WFColors.secondaryText.opacity(hovering || session.isActive ? 0.65 : 0))
                .frame(width: 28, height: 2) }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global).onChanged { value in
                focused = true
                if session.beginIfNeeded() { initialHeight = height }
                guard !session.isCancelled, let initialHeight else { return }
                onPreview(CalendarDisplaySizing.allDayHeight(initialHeight + Double(value.translation.height)))
            }.onEnded { value in
                let start = initialHeight
                initialHeight = nil
                if session.finish(), let start {
                    onCommit(CalendarDisplaySizing.allDayHeight(start + Double(value.translation.height)))
                }
                onPreview(nil)
            })
            .focusable().focusEffectDisabled().focused($focused)
            .onExitCommand { session.cancel(); onPreview(nil) }
            .onHover { entered in
                hovering = entered
                (entered ? NSCursor.resizeUpDown : NSCursor.arrow).set()
            }
            .help("拖动调整全天区域高度")
            .accessibilityLabel("调整全天区域高度")
            .accessibilityIdentifier("calendar.all-day-height-handle")
    }
}

private struct CalendarTimelineScrollRequest: Equatable {
    let id: Int
    let hourHeight: Double
    let offset: Double
}

/// Native scrolling is used only to preserve a time anchor while SwiftUI
/// changes the hour grid. Ordinary wheel events stay with NSScrollView.
private final class CalendarTimelineScrollController {
    private weak var scrollView: NSScrollView?
    private var monitor: Any?
    private var wheelFinish: DispatchWorkItem?
    private var didInitialScroll = false
    private var lastRequestID: Int?
    var onZoomWheel: ((Double, Double) -> Void)?
    var onZoomWheelEnded: (() -> Void)?

    var viewportHeight: Double { Double(scrollView?.contentView.bounds.height ?? 0) }
    var scrollOffset: Double {
        guard let scrollView, let document = scrollView.documentView else { return 0 }
        let bounds = scrollView.contentView.bounds
        return Double(document.isFlipped ? bounds.minY : max(0, document.bounds.height - bounds.maxY))
    }
    func attach(_ scrollView: NSScrollView, hourHeight: Double, request: CalendarTimelineScrollRequest?) {
        if self.scrollView !== scrollView {
            if let monitor { NSEvent.removeMonitor(monitor) }
            self.scrollView = scrollView
            didInitialScroll = false
            lastRequestID = nil
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.wheel(event)
            }
        }
        guard let document = scrollView.documentView,
              document.bounds.height + 1 >= CGFloat(hourHeight * 24),
              scrollView.contentView.bounds.height > 0 else { return }
        if !didInitialScroll {
            didInitialScroll = true
            scroll(to: hourHeight * 8, hourHeight: hourHeight)
        }
        if let request, request.id != lastRequestID {
            lastRequestID = request.id
            scroll(to: request.offset, hourHeight: request.hourHeight)
        }
    }
    func cancelWheelFinish() { wheelFinish?.cancel(); wheelFinish = nil }
    func detach() {
        cancelWheelFinish()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; scrollView = nil
        onZoomWheel = nil; onZoomWheelEnded = nil
    }
    private func wheel(_ event: NSEvent) -> NSEvent? {
        guard CalendarDisplaySizing.acceptsZoomWheel(control: event.modifierFlags.contains(.control),
            deltaX: Double(event.scrollingDeltaX), deltaY: Double(event.scrollingDeltaY)),
              let scrollView, event.window === scrollView.window else { return event }
        let clip = scrollView.contentView
        let point = clip.convert(event.locationInWindow, from: nil)
        guard clip.bounds.contains(point) else { return event }
        let anchorY = clip.isFlipped ? point.y - clip.bounds.minY : clip.bounds.maxY - point.y
        onZoomWheel?(Double(event.scrollingDeltaY), Double(anchorY))
        cancelWheelFinish()
        let work = DispatchWorkItem { [weak self] in self?.onZoomWheelEnded?() }
        wheelFinish = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        return nil
    }
    private func scroll(to offset: Double, hourHeight: Double) {
        guard let scrollView, let document = scrollView.documentView else { return }
        scrollView.layoutSubtreeIfNeeded()
        document.layoutSubtreeIfNeeded()
        let clip = scrollView.contentView
        let top = CGFloat(min(max(0, hourHeight * 24 - Double(clip.bounds.height)), max(0, offset)))
        let y = document.isFlipped ? top : max(0, document.bounds.height - clip.bounds.height - top)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(clip)
    }
}

private struct CalendarTimelineScrollProbe: NSViewRepresentable {
    let controller: CalendarTimelineScrollController
    let hourHeight: Double
    let request: CalendarTimelineScrollRequest?
    let onZoomWheel: (Double, Double) -> Void
    let onZoomWheelEnded: () -> Void

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {
        view.controller = controller
        view.hourHeight = hourHeight; view.request = request
        controller.onZoomWheel = onZoomWheel; controller.onZoomWheelEnded = onZoomWheelEnded
        view.refresh()
    }
    static func dismantleNSView(_ view: Probe, coordinator: ()) {
        view.controller?.detach(); view.controller = nil
    }
    final class Probe: NSView {
        weak var controller: CalendarTimelineScrollController?
        var hourHeight: Double = 64
        var request: CalendarTimelineScrollRequest?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refresh() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); refresh() }
        override func layout() { super.layout(); refresh() }
        func refresh() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, let scroll = self.enclosingScrollView else { return }
                self.controller?.attach(scroll, hourHeight: self.hourHeight, request: self.request)
            }
        }
    }
}

private struct CalendarAllDayArea: View {
    let days: [Date]
    let tasks: [Task]
    let preferences: CalendarPreferences
    let calendar: Calendar
    let columnWidth: CGFloat
    let color: (UUID) -> Color
    let onOpen: (UUID) -> Void
    let onToggle: (UUID) -> Void
    let onCreate: (TaskSchedule) -> Void
    let onDrop: ([String], CalendarDropDestination) -> Bool
    let anchorSink: PlanningAnchorRef
    var externalEvents: [SystemCalendarEvent] = []
    var onOpenEvent: (SystemCalendarEvent) -> Void = { _ in }
    @State private var anchor = PlanningAnchorRef()
    private var visible: [Task] {
        guard let start = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return [] }
        return CalendarProjection.allDay(tasks: tasks, range: DateInterval(start: start, end: end), preferences: preferences, calendar: calendar)
    }
    private var spans: [CalendarSpan] { CalendarSpans.lanes(for: days, tasks: visible, calendar: calendar) }
    private func entries(on day: Date) -> [Task] {
        CalendarProjection.agenda(on: day, tasks: visible, preferences: preferences, calendar: calendar)
            .filter { days.count == 1 || !PlanningProjection.spansMultipleDays($0, calendar: calendar) }
    }
    private var contentHeight: CGFloat {
        days.enumerated().reduce(CGFloat(preferences.allDayHeight)) { height, entry in
            let slots = CalendarSpans.slotsOver(spans, column: entry.offset)
            let eventCount = ExternalCalendarProjection.events(on: entry.element, events: externalEvents, calendar: calendar).filter { $0.fields.allDay }.count
            let rowHeight = CGFloat(entries(on: entry.element).count + eventCount) * (WFCalendarMetrics.taskBarHeight + 3)
            return max(height, CGFloat(slots) * WFCalendarMetrics.slotStride + rowHeight + 26)
        }
    }
    var body: some View {
        let height = contentHeight
        HStack(alignment: .top, spacing: 0) {
            Text("全天").font(WFType.caption).foregroundStyle(WFColors.secondaryText)
                .frame(width: WFCalendarTimelineMetrics.axisWidth, alignment: .trailing).padding(.top, 6)
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                            let entries = entries(on: day)
                            let slots = CalendarSpans.slotsOver(spans, column: index)
                            VStack(spacing: 3) {
                                if slots > 0 { Spacer().frame(height: CGFloat(slots) * WFCalendarMetrics.slotStride) }
                                ForEach(entries) { task in
                                    CalendarTaskBarView(task: task, listColor: color(task.id), calendar: calendar,
                                                        onOpen: { onOpen(task.id) }, onToggleTask: onToggle, anchorSink: anchorSink)
                                    .draggable(task.id.uuidString)
                                }
                                ForEach(ExternalCalendarProjection.events(on: day, events: externalEvents, calendar: calendar).filter { $0.fields.allDay }, id: \.displayID) { event in
                                    SystemCalendarEventBar(event: event) { onOpenEvent(event) }
                                }
                                Color.clear.frame(height: 20)
                            }
                            .padding(.horizontal, 3).padding(.top, 3)
                            // Empty columns accept a drop throughout the visible
                            // all-day area, including while a taller column scrolls.
                            .frame(width: columnWidth, height: height, alignment: .top)
                            .contentShape(Rectangle())
                            .background {
                                Color.clear.contentShape(Rectangle()).onTapGesture {
                                    anchorSink.rect = anchor.rect; onCreate(TaskSchedule(dueAt: day))
                                }
                            }
                            .dropDestination(for: String.self) { values, _ in
                                let accepted = onDrop(values, .allDay(day))
                                NativeAcceptanceInteractionTrace.record("all-day.drop", ["accepted": accepted, "day": day.timeIntervalSince1970])
                                return accepted
                            } isTargeted: { targeted in
                                NativeAcceptanceInteractionTrace.record("all-day.target", ["targeted": targeted, "day": day.timeIntervalSince1970])
                            }
                        }
                    }
                    ForEach(spans) { span in
                        CalendarTaskSpanBar(span: span, listColor: color(span.task.id), calendar: calendar,
                                            onOpen: { onOpen(span.task.id) }, onToggleTask: onToggle, anchorSink: anchorSink)
                            .frame(width: CGFloat(span.columnCount) * columnWidth - 6)
                            .offset(x: CGFloat(span.fromColumn) * columnWidth + 3,
                                    y: CGFloat(span.lane) * WFCalendarMetrics.slotStride + 3)
                            .draggable(span.task.id.uuidString)
                    }
                }
                .frame(height: height, alignment: .top)
            }
        }
        .frame(height: CGFloat(preferences.allDayHeight))
        .background(WFColors.calendarCanvas.opacity(0.45)).background(PlanningAnchorProbe(ref: anchor))
        .accessibilityIdentifier("calendar.all-day")
    }
}

private struct CalendarTimelineDay: View {
    let day: Date
    let dayIndex: Int
    let days: [Date]
    let placements: [CalendarTimedPlacement]
    let hourHeight: CGFloat
    let columnWidth: CGFloat
    let calendar: Calendar
    let color: (UUID) -> Color
    let onOpen: (UUID) -> Void
    let onCreate: (TaskSchedule) -> Void
    let onMove: (UUID, TaskSchedule) -> Void
    let onDrop: ([String], CalendarDropDestination) -> Bool
    let onToggle: (UUID) -> Void
    let anchorSink: PlanningAnchorRef
    var externalEvents: [SystemCalendarEvent] = []
    var onOpenEvent: (SystemCalendarEvent) -> Void = { _ in }
    @State private var creationStart: Double?
    @State private var creationEnd: Double?
    @State private var gestureSession = CalendarGestureSession()
    @State private var anchor = PlanningAnchorRef()
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            grid
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    focused = true
                    if gestureSession.beginIfNeeded() { creationStart = Double(value.startLocation.y / hourHeight * 60) }
                    guard !gestureSession.isCancelled else { return }
                    creationEnd = Double(value.location.y / hourHeight * 60)
                }.onEnded { value in
                    defer { creationStart = nil; creationEnd = nil }
                    guard gestureSession.finish() else { return }
                    let minute = Double(value.startLocation.y / hourHeight * 60)
                    let dragged = abs(value.translation.height) > 4
                    let rect = anchor.rect ?? .zero
                    anchorSink.rect = CGRect(x: rect.minX, y: rect.minY + value.location.y,
                                             width: columnWidth, height: 1)
                    onCreate(CalendarGestureDraft.creation(on: day, from: minute,
                        to: dragged ? Double(value.location.y / hourHeight * 60) : nil, calendar: calendar))
                })
            if let start = creationStart, let end = creationEnd {
                RoundedRectangle(cornerRadius: 4).fill(WFColors.accent.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(WFColors.accent, lineWidth: 1))
                    .frame(width: columnWidth - 6, height: max(WFCalendarTimelineMetrics.minimumBlockHeight, CGFloat(abs(end - start)) / 60 * hourHeight))
                    .offset(x: 3, y: CGFloat(min(start, end)) / 60 * hourHeight).allowsHitTesting(false)
            }
            let mixed = ExternalCalendarProjection.timed(on: day, tasks: placements, events: externalEvents, calendar: calendar)
            ForEach(mixed.tasks) { placement in
                CalendarTimeBlock(placement: placement, dayIndex: dayIndex, days: days,
                    hourHeight: hourHeight, columnWidth: columnWidth, calendar: calendar, color: color(placement.id),
                    onOpen: { onOpen(placement.id) }, onMove: { onMove(placement.id, $0) },
                    onToggle: { onToggle(placement.id) }, anchorSink: anchorSink)
                .frame(width: columnWidth / CGFloat(placement.laneCount) - 6)
                .offset(x: CGFloat(placement.lane) * columnWidth / CGFloat(placement.laneCount) + 3)
            }
            ForEach(mixed.events) { placement in
                Button { onOpenEvent(placement.event) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(placement.event.fields.title, systemImage: "calendar").lineLimit(2)
                        Text(placement.event.calendarTitle).font(.caption2).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }.font(WFType.listMeta).padding(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: max(22, CGFloat(placement.endMinute - placement.startMinute) / 60 * hourHeight))
                        .background(WFListPalette.swatch(placement.event.colorARGB).opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                }.buttonStyle(.plain)
                    .frame(width: max(1, columnWidth / CGFloat(placement.laneCount) - 6))
                    .offset(x: CGFloat(placement.lane) * columnWidth / CGFloat(placement.laneCount) + 3,
                            y: CGFloat(placement.startMinute) / 60 * hourHeight)
                    .accessibilityIdentifier("calendar.system-event.\(placement.id)")
            }
        }
        .frame(height: 24 * hourHeight)
        .focusable().focusEffectDisabled().focused($focused)
        .onExitCommand { creationStart = nil; creationEnd = nil; gestureSession.cancel() }
        .dropDestination(for: String.self) { values, point in
            let accepted = onDrop(values, .time(day: day, minute: Double(point.y / hourHeight * 60)))
            NativeAcceptanceInteractionTrace.record("timeline.drop", ["accepted": accepted, "count": values.count,
                "day": day.timeIntervalSince1970, "minute": Double(point.y / hourHeight * 60)])
            return accepted
        } isTargeted: { targeted in
            NativeAcceptanceInteractionTrace.record("timeline.target", ["targeted": targeted, "day": day.timeIntervalSince1970])
        }
        .background(PlanningAnchorProbe(ref: anchor))
    }
    private var grid: some View {
        Path { path in
            for hour in 0...24 {
                let y = CGFloat(hour) * hourHeight
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: columnWidth, y: y))
            }
            path.move(to: .zero); path.addLine(to: CGPoint(x: 0, y: hourHeight * 24))
        }.stroke(WFColors.border.opacity(0.6), lineWidth: 0.5)
    }
}

private struct CalendarTimeBlock: View {
    let placement: CalendarTimedPlacement
    let dayIndex: Int
    let days: [Date]
    let hourHeight: CGFloat
    let columnWidth: CGFloat
    let calendar: Calendar
    let color: Color
    let onOpen: () -> Void
    let onMove: (TaskSchedule) -> Void
    let onToggle: () -> Void
    let anchorSink: PlanningAnchorRef
    @State private var hovering = false
    @State private var translation = CGSize.zero
    @State private var resizeDraft = CalendarResizeDraft()
    @State private var gestureSession = CalendarGestureSession()
    @State private var anchor = PlanningAnchorRef()
    @FocusState private var focused: Bool
    private var task: Task { placement.task }
    private var displayedSchedule: TaskSchedule { resizeDraft.schedule ?? task.schedule }
    private var geometry: CalendarTimeBlockGeometry {
        CalendarTimeBlockGeometry(schedule: displayedSchedule, day: placement.day, calendar: calendar)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 5) {
                Button(action: onToggle) { TaskCompletionBox(size: 10, completed: task.status == .completed) }
                    .buttonStyle(.plain).accessibilityLabel("完成：\(task.title)")
                Text(task.title).font(WFType.listMeta).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }
            if displayedSchedule.dueEndAt != nil {
                Text(timeLabel).font(.system(size: 10)).foregroundStyle(WFColors.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(height: max(WFCalendarTimelineMetrics.minimumBlockHeight,
                           CGFloat(geometry.displayMinutes) / 60 * hourHeight), alignment: .topLeading)
        .foregroundStyle(task.status == .completed ? WFColors.tertiaryText : WFColors.text)
        .background(color.opacity(task.status == .completed ? 0.12 : 0.25), in: RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 2).allowsHitTesting(false) }
        .overlay(alignment: .top) { if displayedSchedule.dueEndAt != nil { resizeHandle(start: true) } }
        .overlay(alignment: .bottom) { resizeHandle(start: false) }
        .overlay(alignment: .topLeading) {
            if resizeDraft.schedule != nil {
                Text(timeLabel).font(.system(size: 10).monospacedDigit()).fixedSize()
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(WFColors.content, in: RoundedRectangle(cornerRadius: 3))
                    .offset(y: -22).allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { anchorSink.rect = anchor.rect; onOpen() }
        // 与列表行同理：窗口未激活时，第一次点击也要直接打开任务。
        .modifier(TaskRowActivationPolicy())
        .gesture(DragGesture(minimumDistance: 5).onChanged { value in
            focused = true; _ = gestureSession.beginIfNeeded()
            guard !gestureSession.isCancelled else { return }
            translation = value.translation
        }.onEnded { value in
            defer { translation = .zero }
            guard gestureSession.finish() else { return }
            let shift = Int((value.translation.width / columnWidth).rounded())
            let index = min(max(0, dayIndex + shift), days.count - 1)
            let minute = placement.startMinute + Double(value.translation.height / hourHeight * 60)
            let start = CalendarGestureDraft.date(on: days[index], minute: minute, calendar: calendar)
            onMove(CalendarGestureDraft.moved(task.schedule, to: start, hasTime: true, calendar: calendar))
        })
        .background(PlanningAnchorProbe(ref: anchor))
        .planningTaskTarget(task.id)
        .offset(x: translation.width, y: CGFloat(geometry.startMinute) / 60 * hourHeight + translation.height)
        .focusable().focusEffectDisabled().focused($focused)
        .onExitCommand { gestureSession.cancel(); translation = .zero; resizeDraft.cancel() }
        .onHover { hovering = $0 }
        .businessContextMenu { Button("打开任务", action: onOpen) }
        .accessibilityValue(timeLabel)
        .accessibilityIdentifier("calendar.time-block.\(task.id.uuidString)")
    }
    private var timeLabel: String {
        let schedule = displayedSchedule
        let start = calendarClock(schedule.dueAt, hasTime: true, calendar: calendar) ?? ""
        let end = calendarClock(schedule.dueEndAt, hasTime: true, calendar: calendar)
        return end.map { start + "–" + $0 } ?? start
    }
    private func resizeHandle(start: Bool) -> some View {
        Color.clear
            .frame(height: WFCalendarTimelineMetrics.resizeHandleHeight)
            .contentShape(Rectangle())
            .overlay { Capsule().fill(color.opacity(hovering ? 0.7 : 0)).frame(width: 18, height: 2) }
            .onHover { entered in (entered ? NSCursor.resizeUpDown : NSCursor.arrow).set() }
            .highPriorityGesture(DragGesture(minimumDistance: 3, coordinateSpace: .global).onChanged { value in
                focused = true
                resizeDraft.update(task.schedule, day: placement.day, edge: start ? .start : .end,
                    translationMinutes: Double(value.translation.height / hourHeight * 60), calendar: calendar)
            }.onEnded { value in
                resizeDraft.update(task.schedule, day: placement.day, edge: start ? .start : .end,
                    translationMinutes: Double(value.translation.height / hourHeight * 60), calendar: calendar)
                if let schedule = resizeDraft.finish() { onMove(schedule) }
            })
    }
}
