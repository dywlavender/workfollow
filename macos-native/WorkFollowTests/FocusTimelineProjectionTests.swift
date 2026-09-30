import XCTest
@testable import WorkFollow

final class FocusTimelineProjectionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testTimelineStartsAtPreviousHourAndHasFourHourWindow() throws {
        let now = date(2026, 9, 30, 13, 37)
        let projection = FocusTimelineProjection.make(
            timing: timing(start: date(2026, 9, 30, 13, 12), end: date(2026, 9, 30, 13, 57)),
            now: now, calendar: calendar
        )

        XCTAssertEqual(projection.visibleStart, date(2026, 9, 30, 12, 0))
        XCTAssertEqual(projection.visibleEnd, date(2026, 9, 30, 16, 0))
        XCTAssertEqual(projection.ticks, (12...16).map { date(2026, 9, 30, $0, 0) })
        XCTAssertEqual(projection.currentAt, now)
        XCTAssertEqual(projection.currentYRatio, 97.0 / 240.0, accuracy: 0.0001)
    }

    func testProjectedEndControlsFocusFillBottom() throws {
        let now = date(2026, 9, 30, 13, 37)
        let end = date(2026, 9, 30, 13, 57)
        let projection = FocusTimelineProjection.make(
            timing: timing(start: date(2026, 9, 30, 13, 12), end: end),
            now: now, calendar: calendar
        )

        XCTAssertEqual(projection.projectedEndAt, end)
        XCTAssertEqual(projection.visibleProjectedEndAt, end)
        XCTAssertEqual(try XCTUnwrap(projection.endYRatio), 117.0 / 240.0, accuracy: 0.0001)
    }

    func testProjectedEndBeyondWindowIsClippedAtBottomTick() throws {
        let now = date(2026, 9, 30, 13, 37)
        let end = date(2026, 9, 30, 16, 37)
        let projection = FocusTimelineProjection.make(
            timing: timing(start: now, end: end), now: now, calendar: calendar
        )

        XCTAssertEqual(projection.projectedEndAt, end)
        XCTAssertEqual(projection.visibleProjectedEndAt, projection.visibleEnd)
        XCTAssertEqual(try XCTUnwrap(projection.endYRatio), 1, accuracy: 0.0001)
    }

    func testPausedTimelineFreezesAtPauseTimeEvenWhenNowAdvances() {
        let pausedAt = date(2026, 9, 30, 13, 35)
        let projection = FocusTimelineProjection.make(
            timing: FocusSessionTiming(phase: .pausedFocus,
                                       phaseStart: date(2026, 9, 30, 13, 10),
                                       projectedEndAt: date(2026, 9, 30, 13, 55),
                                       pausedAt: pausedAt,
                                       remainingSeconds: 20 * 60),
            now: date(2026, 9, 30, 13, 50), calendar: calendar
        )

        XCTAssertEqual(projection.currentAt, pausedAt)
        XCTAssertEqual(projection.currentYRatio, 95.0 / 240.0, accuracy: 0.0001)
    }

    func testStopwatchProjectionHasNoProjectedEndMarker() {
        let projection = FocusTimelineProjection.make(
            timing: FocusSessionTiming(phase: .focusing,
                                       phaseStart: date(2026, 9, 30, 13, 10),
                                       projectedEndAt: nil,
                                       pausedAt: nil,
                                       remainingSeconds: 0),
            now: date(2026, 9, 30, 13, 37), calendar: calendar
        )

        XCTAssertNil(projection.projectedEndAt)
        XCTAssertNil(projection.endYRatio)
    }

    private func timing(start: Date, end: Date) -> FocusSessionTiming {
        FocusSessionTiming(phase: .focusing, phaseStart: start,
                           projectedEndAt: end, pausedAt: nil,
                           remainingSeconds: 20 * 60)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute))!
    }
}
