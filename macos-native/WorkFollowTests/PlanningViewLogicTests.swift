import XCTest
@testable import WorkFollow

/// Planning 页面（日历/四象限）改造抽出的纯函数：
/// 清单名 → 色板稳定映射、日期 chip 归类与文案。
final class PlanningViewLogicTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2  // 周一，与滴答月网格一致
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    // MARK: - listColorIndex（清单名 → 色板槽位）

    func testListColorIndexIsStableInRangeAndPinnedForKnownNames() {
        // 回归锚点：FNV-1a 64 对以下名字命中的槽位是固定值，
        // 改算法（或误用 String.hashValue）会立刻失败。
        let pinned = [
            "收集箱": 4,
            "工作": 4,
            "学习": 3,
            "个人": 5,
            "欢迎": 1,
            "验收-Native-0925": 6,
            "去": 2,
            "": 5,
        ]
        for (name, expected) in pinned {
            let index = PlanningProjection.listColorIndex(for: name)
            XCTAssertTrue((0..<PlanningProjection.listPaletteCount).contains(index),
                          "槽位越界：\(name) → \(index)")
            XCTAssertEqual(index, expected, "清单名 \(name) 的色板槽位必须稳定")
            XCTAssertEqual(index, PlanningProjection.listColorIndex(for: name),
                           "同一清单名重复取色必须一致：\(name)")
        }
    }

    func testListColorIndexSpreadsAcrossPaletteSlots() {
        let names = (0..<40).map { "清单\($0)" }
        let used = Set(names.map { PlanningProjection.listColorIndex(for: $0) })
        XCTAssertGreaterThanOrEqual(used.count, 5,
                                    "hash 映射应在色板上有效散开，避免月视图整片同色")
    }

    // MARK: - dateChipKind（日期 chip 归类）

    func testDateChipKindClassifiesOverdueTodayUpcomingAndNone() {
        let now = date(2026, 9, 26, hour: 10)
        // 过期：昨天及更早，与时点无关
        XCTAssertEqual(PlanningProjection.dateChipKind(dueAt: date(2026, 9, 25, hour: 23, minute: 59),
                                                       now: now, calendar: calendar), .overdue)
        XCTAssertEqual(PlanningProjection.dateChipKind(dueAt: date(2026, 9, 20),
                                                       now: now, calendar: calendar), .overdue)
        // 今天：同一天任意时点都算今天
        XCTAssertEqual(PlanningProjection.dateChipKind(dueAt: date(2026, 9, 26, hour: 8),
                                                       now: now, calendar: calendar), .today)
        XCTAssertEqual(PlanningProjection.dateChipKind(dueAt: date(2026, 9, 26, hour: 23, minute: 59),
                                                       now: now, calendar: calendar), .today)
        // 未来
        XCTAssertEqual(PlanningProjection.dateChipKind(dueAt: date(2026, 9, 27),
                                                       now: now, calendar: calendar), .upcoming)
        XCTAssertEqual(PlanningProjection.dateChipKind(dueAt: date(2026, 10, 1),
                                                       now: now, calendar: calendar), .upcoming)
        // 无日期不出 chip
        XCTAssertEqual(PlanningProjection.dateChipKind(dueAt: nil,
                                                       now: now, calendar: calendar), .none)
    }

    // MARK: - dateChipText（日期 chip 文案）

    func testDateChipTextUsesRelativeWordsWithinOneDay() {
        let now = date(2026, 9, 26, hour: 10)
        XCTAssertEqual(PlanningProjection.dateChipText(date(2026, 9, 26), hasTime: false,
                                                       now: now, calendar: calendar), "今天")
        XCTAssertEqual(PlanningProjection.dateChipText(date(2026, 9, 27), hasTime: false,
                                                       now: now, calendar: calendar), "明天")
        XCTAssertEqual(PlanningProjection.dateChipText(date(2026, 9, 25), hasTime: false,
                                                       now: now, calendar: calendar), "昨天")
    }

    func testDateChipTextFallsBackToGregorianLabelAndAppendTime() {
        let now = date(2026, 9, 26, hour: 10)
        XCTAssertEqual(PlanningProjection.dateChipText(date(2026, 9, 29), hasTime: false,
                                                       now: now, calendar: calendar), "9月29日")
        XCTAssertEqual(PlanningProjection.dateChipText(date(2027, 1, 2), hasTime: false,
                                                       now: now, calendar: calendar), "2027年1月2日")
        XCTAssertEqual(PlanningProjection.dateChipText(date(2026, 9, 26, hour: 14, minute: 30),
                                                       hasTime: true, now: now, calendar: calendar), "今天 14:30")
    }
}
