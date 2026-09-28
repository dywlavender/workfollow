import XCTest
@testable import WorkFollow

/// 日历与四象限页抽出来的纯展示规则：
/// 清单名 → 色板稳定映射、格内日号写法、条上时刻、四象限行内日期标签。
final class PlanningViewLogicTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 1   // 周日，与打勾月网格一致
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    private func makeTask(_ title: String,
                          dueAt: Date? = nil,
                          completed: Bool = false) -> Task {
        let stamp = Date(timeIntervalSince1970: 0)
        return Task(id: UUID(), title: title, list: .inbox, priority: .none,
                    schedule: TaskSchedule(dueAt: dueAt), status: completed ? .completed : .active,
                    parentID: nil, childOrder: 0, createdAt: stamp, updatedAt: stamp)
    }

    // MARK: - 清单名 → 色板槽位

    func testListColorIndexIsStableInRangeAndPinnedForKnownNames() {
        // 回归锚点：色板下标 = Unicode 标量和 % 14（Flutter `listColorValueForName`
        // 同款算法）。换算法（或误用 String.hashValue，它在 Swift 里逐进程随机）
        // 会立刻让这批值变红。
        let pinned = [
            "收集箱": 7,
            "工作": 1,
            "学习": 6,
            "个人": 12,
            "欢迎": 8,
            "验收-Native-0925": 13,
            "去": 1,
            "项目A": 6,
        ]
        for (name, expected) in pinned {
            let index = WFListPalette.colorIndex(for: name, explicit: nil)
            XCTAssertTrue((0..<WFListPalette.argb.count).contains(index),
                          "槽位越界：\(name) → \(index)")
            XCTAssertEqual(index, expected, "清单名 \(name) 的色板槽位必须稳定")
            XCTAssertEqual(index, WFListPalette.colorIndex(for: name, explicit: nil),
                           "同一清单名重复取色必须一致：\(name)")
        }
    }

    func testListColorIndexFallsBackToFirstSlotForBlankNames() {
        XCTAssertEqual(WFListPalette.colorIndex(for: "", explicit: nil), 0)
        XCTAssertEqual(WFListPalette.colorIndex(for: "   ", explicit: nil), 0)
    }

    func testListColorIndexPrefersTheExplicitChoice() {
        XCTAssertEqual(WFListPalette.colorIndex(for: "工作", explicit: 11), 11)
        // 越界的显式值退回按名字推导，而不是钳到某个端点色。
        XCTAssertEqual(WFListPalette.colorIndex(for: "工作", explicit: 99), 1)
        XCTAssertEqual(WFListPalette.colorIndex(for: "工作", explicit: -1), 1)
    }

    func testListColorIndexSpreadsAcrossPaletteSlots() {
        let names = (0..<40).map { "清单\($0)" }
        let used = Set(names.map { WFListPalette.colorIndex(for: $0, explicit: nil) })
        XCTAssertGreaterThanOrEqual(used.count, 5,
                                   "名字折叠应在色板上有效散开，避免月视图整片同色")
    }

    func testPaletteMatchesTheFlutterTokenTable() {
        // 色板是与 Flutter 共享的契约表：顺序即下标，改一处两边同时漂移。
        XCTAssertEqual(WFListPalette.argb.count, 14)
        XCTAssertEqual(WFListPalette.argb.first, 0xFFE35D6A)   // red
        XCTAssertEqual(WFListPalette.argb.last, 0xFF8A909B)    // grey
    }

    // MARK: - 格内日号

    func testDayNumberCarriesTheMonthOnlyOnTheFirst() {
        XCTAssertEqual(CalendarDayLabels.label(date(2026, 9, 1), calendar: calendar), "9月1日")
        XCTAssertEqual(CalendarDayLabels.label(date(2026, 9, 2), calendar: calendar), "2")
        XCTAssertEqual(CalendarDayLabels.label(date(2026, 9, 30), calendar: calendar), "30")
        // 月网格开头与结尾是邻月的日子，那边的 1 日同样带月份。
        XCTAssertEqual(CalendarDayLabels.label(date(2026, 10, 1), calendar: calendar), "10月1日")
    }

    func testMonthTitleHasNoThousandsSeparator() {
        // `Text("\(年份)年")` 走本地化插值会把 2026 写成 2,026；标题必须拼成
        // String 再交给 Text。
        let title = CalendarDayLabels.monthTitle(date(2026, 9, 1), calendar: calendar)
        XCTAssertEqual(title, "2026年9月")
        XCTAssertFalse(title.contains(","), "年月标题不许出现千分位分隔符")
        XCTAssertEqual(CalendarDayLabels.monthTitle(date(2026, 12, 20), calendar: calendar),
                       "2026年12月")
    }

    func testDateKeyIsZeroPaddedAndSortable() {
        XCTAssertEqual(CalendarDayLabels.key(date(2026, 9, 2), calendar: calendar), "2026-09-02")
        XCTAssertEqual(CalendarDayLabels.key(date(2026, 12, 31), calendar: calendar), "2026-12-31")
    }

    // MARK: - 条上时刻

    func testClockIsPrintedOnlyWhenTheTaskHasATime() {
        XCTAssertEqual(calendarClock(date(2026, 9, 21, hour: 15, minute: 5),
                                     hasTime: true, calendar: calendar), "15:05")
        XCTAssertNil(calendarClock(date(2026, 9, 21, hour: 15), hasTime: false,
                                   calendar: calendar),
                     "没有时刻就是全天，不该硬造「全天」这个词")
        XCTAssertNil(calendarClock(nil, hasTime: true, calendar: calendar))
    }

    // MARK: - 星期表头

    func testWeekHeaderStartsOnSunday() {
        XCTAssertEqual(CalendarWeekHeaderLabels.all.first, "周日")
        XCTAssertEqual(CalendarWeekHeaderLabels.all.last, "周六")
        XCTAssertEqual(CalendarWeekHeaderLabels.weekdayName(1), "日")
        XCTAssertEqual(CalendarWeekHeaderLabels.weekdayName(2), "一")
        XCTAssertEqual(CalendarWeekHeaderLabels.weekdayName(7), "六")
    }

    // MARK: - 四象限行内日期标签

    func testDateLabelUsesRelativeWordsForTheThreeNeighbouringDays() {
        let now = date(2026, 9, 26, hour: 10)
        XCTAssertEqual(MatrixProjection.dateLabel(for: date(2026, 9, 26), now: now,
                                                  calendar: calendar), "今天")
        XCTAssertEqual(MatrixProjection.dateLabel(for: date(2026, 9, 27), now: now,
                                                  calendar: calendar), "明天")
        XCTAssertEqual(MatrixProjection.dateLabel(for: date(2026, 9, 25), now: now,
                                                  calendar: calendar), "昨天")
        XCTAssertNil(MatrixProjection.dateLabel(for: nil, now: now, calendar: calendar))
    }

    /// 星期以**周一**起算，与日历页的周日起始是两件事：标签表读的是「本周三」
    /// 这种口语说法，而口语里的本周从周一开始。
    func testDateLabelUsesMondayBasedWeeks() {
        // 2026-09-26 是周六 → 本周一是 9/21，下周一是 9/28。
        let now = date(2026, 9, 26, hour: 10)
        XCTAssertEqual(MatrixProjection.dateLabel(for: date(2026, 9, 23), now: now,
                                                  calendar: calendar), "周三")
        XCTAssertEqual(MatrixProjection.dateLabel(for: date(2026, 9, 28), now: now,
                                                  calendar: calendar), "下周一")
        XCTAssertEqual(MatrixProjection.dateLabel(for: date(2026, 10, 4), now: now,
                                                  calendar: calendar), "下周日")
    }

    func testDateLabelFallsBackToCalendarDateAndKeepsTheYearWhenItDiffers() {
        let now = date(2026, 9, 26, hour: 10)
        // 下周之后才落到日历日期：本轮周一 9/21，下周一是 9/28，所以 9/29 仍是
        // 「下周二」；要走到日历日期得跨过再下一周。
        XCTAssertEqual(MatrixProjection.dateLabel(for: date(2026, 9, 29), now: now,
                                                  calendar: calendar), "下周二")
        XCTAssertEqual(MatrixProjection.dateLabel(for: date(2026, 10, 7), now: now,
                                                  calendar: calendar), "10月7日")
        XCTAssertEqual(MatrixProjection.dateLabel(for: date(2027, 1, 2), now: now,
                                                  calendar: calendar), "2027年1月2日")
    }

    // MARK: - 四象限投影

    func testProjectGroupsActiveTasksByListAndAppendsCompletedGroup() {
        let tasks = [
            makeTask("工作一", dueAt: date(2026, 9, 22)),
            makeTask("工作二", dueAt: date(2026, 9, 22)),
            makeTask("做完了", dueAt: date(2026, 9, 20), completed: true),
        ]
        let quadrants = MatrixProjection.project(tasks: tasks, now: date(2026, 9, 22, hour: 10),
                                                 listOrder: ["收集箱"],
                                                 calendar: calendar)
        XCTAssertEqual(quadrants.count, 4)
        // 三条任务都是「不重要但紧急」（无优先级 + 今天安排）→ 全在 Ⅲ。
        let delegate = quadrants[MatrixQuadrant.delegate.rawValue]
        XCTAssertEqual(delegate.quadrant, .delegate)
        XCTAssertEqual(delegate.groups.map(\.title), ["收集箱", "已完成"])
        XCTAssertEqual(delegate.groups.map(\.count), [2, 1])
        XCTAssertFalse(delegate.groups[0].completedGroup)
        XCTAssertTrue(delegate.groups[1].completedGroup)
        // 其余象限是空的，不产生空分组。
        XCTAssertTrue(quadrants[MatrixQuadrant.doNow.rawValue].groups.isEmpty)
    }

    func testProjectGroupIdentifiersAreQuadrantScoped() {
        let tasks = [makeTask("工作一", dueAt: date(2026, 9, 22))]
        let quadrants = MatrixProjection.project(tasks: tasks, now: date(2026, 9, 22, hour: 10),
                                                 listOrder: ["收集箱"], calendar: calendar)
        let group = quadrants[MatrixQuadrant.delegate.rawValue].groups[0]
        XCTAssertEqual(group.id, MatrixProjection.listGroupID(.delegate, "收集箱"),
                       "折叠按 id 记：两个象限里可能有同名清单")
        XCTAssertEqual(group.id, "delegate:list:收集箱")
    }

    func testProjectDropsHiddenTasksAndHonoursIncludeCompleted() {
        let stamp = Date(timeIntervalSince1970: 0)
        var deleted = makeTask("已删除", dueAt: date(2026, 9, 22))
        deleted.deletedAt = stamp
        var skipped = makeTask("已跳过", dueAt: date(2026, 9, 22))
        skipped.skippedAt = stamp
        var abandoned = makeTask("已放弃", dueAt: date(2026, 9, 22))
        abandoned.abandonedAt = stamp
        var converted = makeTask("已转笔记", dueAt: date(2026, 9, 22))
        converted.convertedNoteID = UUID()
        let tasks = [deleted, skipped, abandoned, converted,
                     makeTask("留下的", dueAt: date(2026, 9, 22)),
                     makeTask("做完了", dueAt: date(2026, 9, 22), completed: true)]

        let withCompleted = MatrixProjection.project(tasks: tasks, now: date(2026, 9, 22, hour: 10),
                                                     listOrder: ["收集箱"], calendar: calendar)
        XCTAssertEqual(withCompleted[MatrixQuadrant.delegate.rawValue].groups.map(\.title),
                       ["收集箱", "已完成"])
        XCTAssertEqual(withCompleted[MatrixQuadrant.delegate.rawValue].taskCount, 2)

        let withoutCompleted = MatrixProjection.project(tasks: tasks,
                                                        now: date(2026, 9, 22, hour: 10),
                                                        listOrder: ["收集箱"],
                                                        includeCompleted: false,
                                                        calendar: calendar)
        XCTAssertEqual(withoutCompleted[MatrixQuadrant.delegate.rawValue].groups.map(\.title),
                       ["收集箱"], "关掉已完成时连那个分组都不出现")
        XCTAssertEqual(withoutCompleted[MatrixQuadrant.delegate.rawValue].taskCount, 1)
    }

    func testProjectRowMetadataAndDateAnchor() {
        let now = date(2026, 9, 26, hour: 10)
        let overdue = makeTask("过期", dueAt: date(2026, 9, 20))
        let done = makeTask("完成的行", dueAt: date(2026, 9, 20), completed: true)
        let quadrants = MatrixProjection.project(tasks: [overdue, done], now: now,
                                                 listOrder: ["收集箱"], calendar: calendar)
        let groups = quadrants[MatrixQuadrant.delegate.rawValue].groups
        // 9/20 是上周日：本轮周一是 9/21，比它早一天，仍是同一周 → 「周日」。
        XCTAssertEqual(groups[0].tasks[0].dateLabel, "周日")
        XCTAssertTrue(groups[0].tasks[0].overdue)
        XCTAssertEqual(groups[0].tasks[0].listName, "收集箱")
        // 已完成的行走 completedAt 当锚点；这里没有完成时点，所以只是不判过期。
        XCTAssertFalse(groups[1].tasks[0].overdue, "完成态不再报过期")
    }

    func testProjectFallsBackToInboxForBlankListNames() {
        let stamp = Date(timeIntervalSince1970: 0)
        let blank = Task(id: UUID(), title: "无清单名", list: TaskList(name: ""),
                         priority: .none, schedule: TaskSchedule(dueAt: date(2026, 9, 22)),
                         status: .active, parentID: nil, childOrder: 0,
                         createdAt: stamp, updatedAt: stamp)
        let quadrants = MatrixProjection.project(tasks: [blank], now: date(2026, 9, 22, hour: 10),
                                                 listOrder: [], calendar: calendar)
        XCTAssertEqual(quadrants[MatrixQuadrant.delegate.rawValue].groups.map(\.title), ["收集箱"])
    }

    func testProjectReportsSubtaskMarkerThroughTheInjectedResolver() {
        let parent = makeTask("有子任务", dueAt: date(2026, 9, 22))
        let base = makeTask("子任务", dueAt: date(2026, 9, 22))
        // 子任务通过 parentID 挂到父任务上；投影只问 resolver，不自己爬树。
        let child = Task(id: base.id, title: base.title, list: base.list,
                         priority: base.priority, schedule: base.schedule,
                         status: base.status, parentID: parent.id, childOrder: 0,
                         createdAt: base.createdAt, updatedAt: base.updatedAt)
        let quadrants = MatrixProjection.project(
            tasks: [parent, child], now: date(2026, 9, 22, hour: 10),
            listOrder: ["收集箱"], calendar: calendar,
            hasChildren: { $0 == parent.id })
        let rows = quadrants[MatrixQuadrant.delegate.rawValue].groups[0].tasks
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.first { $0.task.id == parent.id }?.hasSubtasks == true)
        XCTAssertFalse(rows.first { $0.task.id == child.id }?.hasSubtasks == true)
    }
}
