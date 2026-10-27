import AppKit
import Combine
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class CalendarMonthScrollTests: XCTestCase {
    private final class Position: ObservableObject {
        let calendar: Calendar
        let origin: Date
        @Published var topWeek: Date
        @Published var jump: Date?

        init() {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            calendar.firstWeekday = 1
            self.calendar = calendar
            let first = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
            origin = PlanningProjection.weekStart(containing: first, calendar: calendar)
            topWeek = origin
        }
    }

    private struct Grid: View {
        @ObservedObject var position: Position
        var body: some View {
            CalendarMonthGridView(topWeek: $position.topWeek, programmaticTarget: $position.jump,
                month: position.calendar.date(from: position.calendar.dateComponents([.year, .month], from: position.topWeek))!,
                today: position.origin, selectedDay: position.origin, showCompleted: true,
                calendar: position.calendar, tasks: [], barColor: { _ in .blue },
                onSelectDay: { _ in }, onOpenTask: { _ in }, onCreateTask: { _ in },
                onDropTask: { _, _ in }, onToggleTask: { _ in }, onShowAgenda: { _ in },
                anchorSink: PlanningAnchorRef())
                .frame(width: 840, height: 620)
        }
    }

    private final class Wheel: NSEvent {
        let owner: NSWindow
        let point: NSPoint
        let amount: CGFloat
        let eventPhase: NSEvent.Phase
        init(owner: NSWindow, point: NSPoint, amount: CGFloat, phase: NSEvent.Phase) {
            self.owner = owner; self.point = point; self.amount = amount; eventPhase = phase
            super.init()
        }
        required init?(coder: NSCoder) { fatalError("not intended") }
        override var type: NSEvent.EventType { .scrollWheel }
        override var window: NSWindow? { owner }
        override var locationInWindow: NSPoint { point }
        override var scrollingDeltaX: CGFloat { 0 }
        override var scrollingDeltaY: CGFloat { amount }
        override var deltaY: CGFloat { amount }
        override var hasPreciseScrollingDeltas: Bool { true }
        override var phase: NSEvent.Phase { eventPhase }
        override var momentumPhase: NSEvent.Phase { [] }
        override var modifierFlags: NSEvent.ModifierFlags { [] }
    }

    private func fixture() throws -> (Position, NSWindow, NSScrollView) {
        let position = Position()
        let host = NSHostingView(rootView: Grid(position: position))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 840, height: 620)
        InspectorPanelTestSupport.settle(window, duration: 0.3)
        func find(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, (scroll.documentView?.frame.height ?? 0) > 2000 { return scroll }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        let scroll = try XCTUnwrap(find(host))
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0, "Initial month must be positioned before scrolling")
        return (position, window, scroll)
    }

    func testSmallWheelGestureKeepsItsPartialRowOffsetAfterRelease() throws {
        let (_, window, scroll) = try fixture()
        defer { window.close() }
        let initial = scroll.contentView.bounds.minY
        let point = scroll.convert(NSPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: nil)
        scroll.scrollWheel(with: Wheel(owner: window, point: point, amount: -12, phase: .began))
        scroll.scrollWheel(with: Wheel(owner: window, point: point, amount: -6, phase: .changed))
        InspectorPanelTestSupport.settle(window, duration: 0.1)
        let moved = scroll.contentView.bounds.minY
        XCTAssertGreaterThan(moved - initial, 1, "The native wheel event must actually move the grid")
        XCTAssertLessThan(moved - initial, scroll.contentSize.height / 10, "Small gestures must not require a whole week")
        scroll.scrollWheel(with: Wheel(owner: window, point: point, amount: 0, phase: .ended))
        InspectorPanelTestSupport.settle(window, duration: 0.6)
        XCTAssertEqual(scroll.contentView.bounds.minY, moved, accuracy: 1,
                       "Releasing a small gesture must not snap back to a week boundary")
    }

    func testExplicitWeekJumpStillWorksFromAPartialRowPosition() throws {
        let (position, window, scroll) = try fixture()
        defer { window.close() }
        let initial = scroll.contentView.bounds.minY
        scroll.contentView.scroll(to: NSPoint(x: 0, y: initial + 23))
        scroll.reflectScrolledClipView(scroll.contentView)
        InspectorPanelTestSupport.settle(window)
        let target = try XCTUnwrap(position.calendar.date(byAdding: .weekOfYear, value: 4, to: position.origin))
        position.jump = target
        position.topWeek = target
        InspectorPanelTestSupport.settle(window, duration: 0.6)
        XCTAssertNil(position.jump)
        XCTAssertEqual(position.topWeek, target)
        let rowHeight = (try XCTUnwrap(scroll.documentView)).frame.height / 61
        XCTAssertEqual(scroll.contentView.bounds.minY - initial, rowHeight * 4, accuracy: 1)
    }

    func testExplicitJumpToTheSameWeekResetsAPartialRowPosition() throws {
        let (position, window, scroll) = try fixture()
        defer { window.close() }
        let initial = scroll.contentView.bounds.minY
        scroll.contentView.scroll(to: NSPoint(x: 0, y: initial + 23))
        scroll.reflectScrolledClipView(scroll.contentView)
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(position.topWeek, position.origin)
        position.jump = position.topWeek
        InspectorPanelTestSupport.settle(window, duration: 0.6)
        XCTAssertNil(position.jump, "An explicit request must be consumed even when the week is unchanged")
        XCTAssertEqual(scroll.contentView.bounds.minY, initial, accuracy: 1)
    }
}
