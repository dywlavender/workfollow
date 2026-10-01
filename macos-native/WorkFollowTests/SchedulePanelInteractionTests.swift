import XCTest
import SwiftUI
@testable import WorkFollow

@MainActor
final class SchedulePanelInteractionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }

    private func date(_ hour: Int, _ minute: Int, day: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testDefaultTimeRoundsToNearestHalfHourWithoutMovingSelectedDate() {
        for (hour, minute, expectedHour, expectedMinute) in [(10, 7, 10, 0), (10, 18, 10, 30), (23, 44, 23, 30), (23, 50, 0, 0)] {
            let value = SchedulePanelInteraction.defaultTime(now: date(hour, minute), date: date(0, 0, day: 22), calendar: calendar)
            XCTAssertEqual(calendar.component(.hour, from: value), expectedHour)
            XCTAssertEqual(calendar.component(.minute, from: value), expectedMinute)
            XCTAssertEqual(calendar.component(.day, from: value), 22)
        }
    }

    func testOpenHoverClearAndDiscardDoNotWriteTask() {
        let now = date(10, 18)
        let workspace = TaskWorkspaceModel(clock: { now }, calendar: calendar, seedDemoData: false)
        let id = workspace.createTask(title: "时间状态验收", in: .inbox).taskID!
        let original = workspace.task(for: id)!
        let model = TaskDateDraftModel(task: original, calendar: calendar, now: { now }, deadline: false)
        var state = SchedulePanelPresentationState()
        XCTAssertFalse(model.hasTime)
        SchedulePanelInteraction.open(.time, state: &state, model: model, now: now, calendar: calendar)
        XCTAssertTrue(model.hasTime)
        XCTAssertEqual(state.expandedProperty, .time)
        XCTAssertEqual(calendar.component(.hour, from: model.startTimeAnchor!), 10)
        XCTAssertEqual(calendar.component(.minute, from: model.startTimeAnchor!), 30)
        state.hover(.time, inside: true)
        let row = SchedulePropertyPresentation(title: "时间", value: "10:30", isActive: true,
            isExpanded: true, isHovered: state.hoveredProperty == .time, canClear: true)
        XCTAssertEqual(row.trailingControl, .clear)
        SchedulePanelInteraction.clear(.time, state: &state, model: model)
        XCTAssertFalse(model.hasTime)
        XCTAssertNil(state.expandedProperty)
        XCTAssertEqual(workspace.task(for: id), original)
        let reopened = TaskDateDraftModel(task: original, calendar: calendar, now: { now }, deadline: false)
        XCTAssertFalse(reopened.hasTime)
    }

    func testOpeningAlreadyTimedDraftPreservesPreciseTime() {
        let workspace = TaskWorkspaceModel(clock: { self.date(10, 18) }, calendar: calendar, seedDemoData: false)
        let id = workspace.createTask(title: "已有时间", in: .inbox).taskID!
        workspace.saveTiming(id, schedule: TaskSchedule(dueAt: date(11, 43), hasTime: true), reminder: nil, frequency: .never)
        let model = TaskDateDraftModel(task: workspace.task(for: id)!, calendar: calendar, now: { self.date(10, 18) }, deadline: false)
        var state = SchedulePanelPresentationState()
        SchedulePanelInteraction.open(.time, state: &state, model: model, now: date(10, 18), calendar: calendar)
        XCTAssertEqual(model.startTimeAnchor, date(11, 43))
    }

    func testTrailingControlsAndHoverTransitionsAreSharedAcrossProperties() {
        for property in [ScheduleProperty.time, .endTime, .reminder, .repeat, .repeatEnd] {
            var state = SchedulePanelPresentationState(expandedProperty: property)
            state.hover(property, inside: true)
            XCTAssertEqual(state.hoveredProperty, property)
            func control(active: Bool, expanded: Bool, hovered: Bool) -> SchedulePropertyPresentation.TrailingControl {
                SchedulePropertyPresentation(title: "属性", value: active ? "值" : nil, isActive: active,
                    isExpanded: expanded, isHovered: hovered, canClear: active).trailingControl
            }
            XCTAssertEqual(control(active: false, expanded: false, hovered: true), .chevronRight)
            XCTAssertEqual(control(active: false, expanded: true, hovered: true), .chevronDown)
            XCTAssertEqual(control(active: true, expanded: false, hovered: true), .clear)
            XCTAssertEqual(control(active: true, expanded: true, hovered: true), .clear)
            state.hover(property, inside: false)
            XCTAssertNil(state.hoveredProperty)
        }
    }

    func testClearingReminderAndRepeatChangesOnlyDraftAndResetsRepeatEnd() {
        let workspace = TaskWorkspaceModel(clock: { self.date(10, 18) }, calendar: calendar, seedDemoData: false)
        let id = workspace.createTask(title: "属性清除", in: .inbox).taskID!
        let original = workspace.task(for: id)!
        let model = TaskDateDraftModel(task: original, calendar: calendar, now: { self.date(10, 18) }, deadline: false)
        model.setReminderOffsets([-1440])
        model.chooseFrequency(.monthly)
        model.chooseEnding(.count)
        var state = SchedulePanelPresentationState(expandedProperty: .reminder)
        SchedulePanelInteraction.clear(.reminder, state: &state, model: model)
        XCTAssertFalse(model.hasReminderDraft)
        XCTAssertEqual(model.frequency, .monthly)
        state.expandedProperty = .repeat
        SchedulePanelInteraction.clear(.repeat, state: &state, model: model)
        XCTAssertEqual(model.frequency, .never)
        XCTAssertEqual(model.ending, .never)
        XCTAssertNil(state.expandedProperty)
        XCTAssertEqual(workspace.task(for: id), original)
    }

    func testPropertyRowRendersDynamicValueAndTrailingControl() throws {
        for (active, expanded, hovered, expected) in [(false, false, false, "chevron.right"),
            (true, false, false, "chevron.right"), (true, true, false, "chevron.down"),
            (true, true, true, "xmark")] {
            var values: [ScheduleRenderAnchor: ScheduleRenderValue] = [:]
            let presentation = SchedulePropertyPresentation(title: "时间", value: active ? "10:30" : nil,
                isActive: active, isExpanded: expanded, isHovered: hovered, canClear: active)
            let root = SchedulePropertyRow(property: .time, icon: "clock", presentation: presentation,
                onOpen: {}, onClear: {}, onHover: { _ in })
                .coordinateSpace(name: "schedule-render")
                .onPreferenceChange(ScheduleFramesKey.self) { values = $0 }
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 232, height: 30),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            XCTAssertEqual(values[.row(.time)]?.label, active ? "10:30" : "时间")
            XCTAssertEqual(values[.trailing(.time)]?.label, expected)
            XCTAssertEqual(try XCTUnwrap(values[.row(.time)]).frame.height, 30, accuracy: 0.1)
            window.contentView = nil
            window.close()
        }
    }

    func testPropertyColumnsStayFixedWhenOpenedHoveredOrReplacedByTimeEditor() throws {
        for property in [ScheduleProperty.time, .repeat] {
            var baseline: [ScheduleRenderAnchor: ScheduleRenderValue]?
            for state in 0..<4 {
                var values: [ScheduleRenderAnchor: ScheduleRenderValue] = [:]
                let active = state > 0
                let presentation = SchedulePropertyPresentation(
                    title: property == .time ? "时间" : "重复",
                    value: active ? (property == .time ? "10:30" : "每周") : nil,
                    isActive: active, isExpanded: state > 1, isHovered: state == 3, canClear: active)
                let editor: AnyView? = property == .time && active
                    ? AnyView(TextField("", text: .constant("10:30"))
                        .textFieldStyle(.plain).font(WFType.body).frame(width: 52, alignment: .leading)) : nil
                let root = SchedulePropertyRow(property: property, icon: "clock",
                    presentation: presentation, editor: editor,
                    onOpen: {}, onClear: {}, onHover: { _ in })
                    .coordinateSpace(name: "schedule-render")
                    .onPreferenceChange(ScheduleFramesKey.self) { values = $0 }
                let host = NSHostingView(rootView: root)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 232, height: 30),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.orderFront(nil)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                if let baseline {
                    for anchor in [ScheduleRenderAnchor.icon(property), .value(property), .trailing(property)] {
                        XCTAssertEqual(try XCTUnwrap(values[anchor]).frame.minX,
                            try XCTUnwrap(baseline[anchor]).frame.minX, accuracy: 0.1,
                            "\(property) state \(state): \(anchor) must not move")
                    }
                    XCTAssertEqual(values[.row(property)]?.frame, baseline[.row(property)]?.frame)
                } else {
                    baseline = values
                }
                window.contentView = nil
                window.close()
            }
        }
    }
}
