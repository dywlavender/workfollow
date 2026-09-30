import CoreGraphics
import Foundation

/// Pure time-window and marker geometry for the active Focus timeline.
struct FocusTimelineProjection: Equatable {
    let visibleStart: Date
    let visibleEnd: Date
    let ticks: [Date]
    let currentAt: Date
    let projectedEndAt: Date?
    let visibleProjectedEndAt: Date?
    let currentYRatio: CGFloat
    let endYRatio: CGFloat?

    static func make(timing: FocusSessionTiming, now: Date,
                     calendar: Calendar) -> FocusTimelineProjection {
        let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let visibleStart = calendar.date(byAdding: .hour, value: -1, to: currentHour) ?? currentHour
        let ticks = (0...4).compactMap { calendar.date(byAdding: .hour, value: $0, to: visibleStart) }
        let visibleEnd = ticks.last ?? calendar.date(byAdding: .hour, value: 4, to: visibleStart) ?? visibleStart
        let currentAt = timing.phase == .pausedFocus ? (timing.pausedAt ?? now) : now
        let clippedEnd = timing.projectedEndAt.map { min($0, visibleEnd) }
        let total = max(1, visibleEnd.timeIntervalSince(visibleStart))

        return FocusTimelineProjection(
            visibleStart: visibleStart,
            visibleEnd: visibleEnd,
            ticks: ticks,
            currentAt: currentAt,
            projectedEndAt: timing.projectedEndAt,
            visibleProjectedEndAt: clippedEnd,
            currentYRatio: ratio(of: currentAt, start: visibleStart, duration: total),
            endYRatio: clippedEnd.map { ratio(of: $0, start: visibleStart, duration: total) }
        )
    }

    private static func ratio(of date: Date, start: Date, duration: TimeInterval) -> CGFloat {
        let value = date.timeIntervalSince(start) / duration
        return CGFloat(min(max(value, 0), 1))
    }
}
