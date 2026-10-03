import XCTest
@testable import WorkFollow

/// 日程显示投影（`ScheduleDisplay`）的回归。
///
/// 这些文案以前在 3~4 处各写一份（列表行 / 编辑栏 / 面板 / `TaskRepeat.title`）。
/// 用例分两部分：① 每套风格的输出；② **各宿主用的确实是同一实现**（防漂移）。
final class ScheduleDisplayTests: XCTestCase {

    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    // MARK: - 重复

    func testRepeatTitleIsContextFreeForMenus() {
        XCTAssertEqual(ScheduleDisplay.repeatTitle(.never), "不重复")
        XCTAssertEqual(ScheduleDisplay.repeatTitle(.daily), "每天")
        XCTAssertEqual(ScheduleDisplay.repeatTitle(.lunarYearly), "农历每年")
    }

    func testRepeatTextCarriesTheAnchorDay() {
        let context = ScheduleDisplay.RepeatContext(weekday: 3, monthDay: 15, month: 3,
                                                    lunarName: "正月初一", lunarDayText: "初一")
        XCTAssertEqual(ScheduleDisplay.repeatText(.weekly, context: context), "每周 (周二)")
        XCTAssertEqual(ScheduleDisplay.repeatText(.monthly, context: context), "每月 (15日)")
        XCTAssertEqual(ScheduleDisplay.repeatText(.yearly, context: context), "每年 (3月15日)")
        XCTAssertEqual(ScheduleDisplay.repeatText(.lunarYearly, context: context), "农历每年 (正月初一)")
        XCTAssertEqual(ScheduleDisplay.repeatText(.lunarMonthly, context: context), "农历每月 (初一)")
        XCTAssertEqual(ScheduleDisplay.repeatText(.never, context: context), "重复")
        XCTAssertEqual(ScheduleDisplay.repeatText(.workdays, context: context), "法定工作日")
        XCTAssertEqual(ScheduleDisplay.repeatText(.weekends, context: context), "每周六、周日")
    }

    // MARK: - 提醒偏移

    func testPanelStyleUsesWeekAndDayGranularity() {
        XCTAssertEqual(ScheduleDisplay.reminderOffsetText(minutes: 0, style: .panel), "当天")
        XCTAssertEqual(ScheduleDisplay.reminderOffsetText(minutes: -10_080, style: .panel), "提前1周")
        XCTAssertEqual(ScheduleDisplay.reminderOffsetText(minutes: -1_440, style: .panel), "提前1天")
        XCTAssertEqual(ScheduleDisplay.reminderOffsetText(minutes: -30, style: .panel), "提前30分钟")
    }

    func testPresetStyleKeepsTheEditorWording() {
        XCTAssertEqual(ScheduleDisplay.reminderOffsetText(minutes: 0, style: .preset), "准时")
        XCTAssertEqual(ScheduleDisplay.reminderOffsetText(minutes: -1_440, style: .preset), "提前1天")
        XCTAssertEqual(ScheduleDisplay.reminderOffsetText(minutes: -60, style: .preset), "提前1小时")
        XCTAssertEqual(ScheduleDisplay.reminderOffsetText(minutes: -5, style: .preset), "提前5分钟")
    }

    // MARK: - 日期

    func testCompactStyleForRows() {
        let now = date(2026, 10, 3, 9, 0)
        XCTAssertEqual(ScheduleDisplay.dateText(date(2026, 10, 3), hasTime: false, now: now,
                                                calendar: calendar, style: .compact), "今天")
        XCTAssertEqual(ScheduleDisplay.dateText(date(2026, 10, 3, 20, 30), hasTime: true, now: now,
                                                calendar: calendar, style: .compact), "今天 20:30")
        XCTAssertEqual(ScheduleDisplay.dateText(date(2026, 10, 4), hasTime: false, now: now,
                                                calendar: calendar, style: .compact), "明天")
        XCTAssertEqual(ScheduleDisplay.dateText(date(2026, 10, 2), hasTime: false, now: now,
                                                calendar: calendar, style: .compact), "昨天")
        XCTAssertEqual(ScheduleDisplay.dateText(date(2026, 9, 27), hasTime: false, now: now,
                                                calendar: calendar, style: .compact), "9月27日")
        XCTAssertEqual(ScheduleDisplay.dateText(date(2025, 12, 31), hasTime: false, now: now,
                                                calendar: calendar, style: .compact), "2025年12月31日")
    }

    func testFullStyleAddsRelativeWeekAndCommas() {
        let now = date(2026, 10, 3, 9, 0)   // 周六
        // 下周一是 10/5；上周二是 9/22（两种 firstWeekday 口径下都成立，避免用例依赖 Calendar 约定）
        XCTAssertEqual(ScheduleDisplay.dateText(date(2026, 10, 5, 20, 30), hasTime: true, now: now,
                                                calendar: calendar, style: .full),
                       "下周一, 10月5日, 20:30")
        XCTAssertEqual(ScheduleDisplay.dateText(date(2026, 9, 22, 20, 30), hasTime: true, now: now,
                                                calendar: calendar, style: .full),
                       "上周二, 9月22日, 20:30")
        XCTAssertEqual(ScheduleDisplay.dateText(date(2026, 10, 4), hasTime: false, now: now,
                                                calendar: calendar, style: .full), "明天, 10月4日")
    }

    func testDayTextIsMonthDay() {
        XCTAssertEqual(ScheduleDisplay.dayText(date(2026, 9, 26), calendar: calendar), "9月26日")
    }

    // MARK: - 各宿主共用同一实现（防漂移）

    func testHostsDelegateToTheSameImplementation() {
        let now = date(2026, 10, 3, 9, 0)
        let due = date(2026, 9, 22, 20, 30)
        XCTAssertEqual(TaskDateLabel.text(due, hasTime: true, now: now, calendar: calendar),
                       ScheduleDisplay.dateText(due, hasTime: true, now: now,
                                                calendar: calendar, style: .compact))
        XCTAssertEqual(TaskInspectorSchedulePresentation.label(date: due, hasTime: true, now: now,
                                                               calendar: calendar),
                       ScheduleDisplay.dateText(due, hasTime: true, now: now,
                                                calendar: calendar, style: .full))
        XCTAssertEqual(TaskDateDraftModel.offsetTitle(-1_440),
                       ScheduleDisplay.reminderOffsetText(minutes: -1_440, style: .preset))
        XCTAssertEqual(TaskRepeat.weekly.title, ScheduleDisplay.repeatTitle(.weekly))
        XCTAssertEqual(TaskInspectorSchedulePresentation.label(date: nil, hasTime: false, now: now,
                                                               calendar: calendar),
                       "设置日期", "空态文案留在视图层")
    }
}
