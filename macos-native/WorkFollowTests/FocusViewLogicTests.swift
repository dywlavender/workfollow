import XCTest
@testable import WorkFollow

/// 专注页改造抽出的纯展示逻辑测试：
/// 剩余时间文案、阶段文案、今日概览行、近 7 天小字与记录日期分组头。
final class FocusViewLogicTests: XCTestCase {
    private var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    // MARK: - clockText（环心 mm:ss）

    func testClockTextFormatsMinutesAndSeconds() {
        XCTAssertEqual(FocusViewLogic.clockText(0), "00:00")
        XCTAssertEqual(FocusViewLogic.clockText(65), "01:05")
        XCTAssertEqual(FocusViewLogic.clockText(599), "09:59")
        XCTAssertEqual(FocusViewLogic.clockText(3600), "60:00")     // 60 分钟以上分位继续累加
        XCTAssertEqual(FocusViewLogic.clockText(10_800), "180:00")  // 上限 180 分钟
    }

    func testClockTextClampsNegativeToZero() {
        XCTAssertEqual(FocusViewLogic.clockText(-1), "00:00")
    }

    // MARK: - phaseTitle（环心阶段文案）

    func testPhaseTitleCoversAllPhases() {
        XCTAssertEqual(FocusViewLogic.phaseTitle(for: .idle, isLongBreak: false), "就绪")
        XCTAssertEqual(FocusViewLogic.phaseTitle(for: .focusing, isLongBreak: false), "专注中")
        XCTAssertEqual(FocusViewLogic.phaseTitle(for: .breaking, isLongBreak: false), "休息中")
        XCTAssertEqual(FocusViewLogic.phaseTitle(for: .breaking, isLongBreak: true), "长休息")
        XCTAssertEqual(FocusViewLogic.phaseTitle(for: .pausedFocus, isLongBreak: false), "已暂停")
        XCTAssertEqual(FocusViewLogic.phaseTitle(for: .pausedBreak, isLongBreak: false), "休息已暂停")
    }

    // MARK: - 今日概览行

    func testTodayFocusSummaryJoinsMinutesAndPomodoros() {
        XCTAssertEqual(FocusViewLogic.todayFocusSummary(minutes: 32, pomodoros: 3),
                       "今日专注 32 分钟 · 3 个番茄")
        XCTAssertEqual(FocusViewLogic.todayFocusSummary(minutes: 0, pomodoros: 0),
                       "今日专注 0 分钟 · 0 个番茄")
    }

    func testTodayGoalTextCountsMissingAndReached() {
        XCTAssertEqual(FocusViewLogic.todayGoalText(pomodoros: 0, goal: 8), "距目标还差 8 个")
        XCTAssertEqual(FocusViewLogic.todayGoalText(pomodoros: 3, goal: 5), "距目标还差 2 个")
        XCTAssertEqual(FocusViewLogic.todayGoalText(pomodoros: 8, goal: 8), "已达目标")
        XCTAssertEqual(FocusViewLogic.todayGoalText(pomodoros: 10, goal: 8), "已达目标")  // 超出目标不出现负数
    }

    // MARK: - 近 7 天小字

    func testWeeklySummaryAddsTotalsAcrossDays() {
        let stats = [
            FocusViewLogic.DayStat(minutes: 25, pomodoros: 1),
            FocusViewLogic.DayStat(minutes: 0, pomodoros: 0),
            FocusViewLogic.DayStat(minutes: 55, pomodoros: 2),
        ]
        XCTAssertEqual(FocusViewLogic.weeklySummary(stats), "最近 7 天专注 80 分钟 · 3 个番茄")
    }

    func testWeeklySummaryShowsQuietHintWhenNoRecords() {
        XCTAssertEqual(FocusViewLogic.weeklySummary([]), "最近 7 天暂无专注记录")
        XCTAssertEqual(FocusViewLogic.weeklySummary([FocusViewLogic.DayStat(minutes: 0, pomodoros: 0)]),
                       "最近 7 天暂无专注记录")
    }

    // MARK: - 记录日期分组头

    func testDayLabelMarksTodayAndYesterday() {
        let calendar = gregorian
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        XCTAssertEqual(FocusViewLogic.dayLabel(for: today, calendar: calendar), "今天")
        XCTAssertEqual(FocusViewLogic.dayLabel(for: yesterday, calendar: calendar), "昨天")
    }

    func testDayLabelFallsBackToDateTextForOlderDays() {
        let calendar = gregorian
        let old = calendar.date(from: DateComponents(year: 2020, month: 1, day: 15, hour: 12))!
        let label = FocusViewLogic.dayLabel(for: old, calendar: calendar)
        XCTAssertFalse(label.isEmpty)
        XCTAssertNotEqual(label, "今天")
        XCTAssertNotEqual(label, "昨天")
    }
}
