import XCTest
@testable import WorkFollow

/// Weekly review generation for the summary module: week boundaries pinned to
/// Monday, the 已完成 / 已放弃 / 未完成 split, exclusions, date prefixes and
/// the picker-week list. Clock and calendar are fixed for determinism.
final class SummaryReviewBuilderTests: XCTestCase {
    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }()

    // MARK: Helpers

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeBuilder(now: Date) -> SummaryReviewBuilder {
        SummaryReviewBuilder(clock: { now }, calendar: calendar)
    }

    private func makeTask(_ title: String, list: String = "工作",
                          priority: TaskPriority = .none, tags: [String] = [],
                          dueAt: Date? = nil, completedAt: Date? = nil,
                          abandonedAt: Date? = nil, skippedAt: Date? = nil,
                          deletedAt: Date? = nil,
                          status: TaskStatus = .active) -> Task {
        let stamp = Date(timeIntervalSince1970: 0)
        var task = Task(id: UUID(), title: title, list: TaskList(name: list), priority: priority,
                        schedule: TaskSchedule(dueAt: dueAt), status: status, parentID: nil,
                        childOrder: 0, createdAt: stamp, updatedAt: stamp)
        task.tags = tags
        task.completedAt = completedAt
        task.abandonedAt = abandonedAt
        task.skippedAt = skippedAt
        task.deletedAt = deletedAt
        return task
    }

    /// 2026-09-26 is a Saturday; its week is Monday 09-21 … Sunday 09-27.
    private var weekOfSaturday: Date { day(2026, 9, 26, hour: 17) }

    // MARK: Week boundaries (Monday-pinned)

    func testWeekStartPinsMondayRegardlessOfFirstWeekday() {
        // Default Gregorian in GMT starts weeks on Sunday; Monday stays the anchor.
        XCTAssertEqual(SummaryReviewBuilder.weekStart(of: weekOfSaturday, calendar: calendar),
                       day(2026, 9, 21))
        // A Sunday rolls back to the previous Monday.
        XCTAssertEqual(SummaryReviewBuilder.weekStart(of: day(2026, 9, 20, hour: 23), calendar: calendar),
                       day(2026, 9, 14))
        // Same result even when the calendar claims Monday is the first weekday.
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        XCTAssertEqual(SummaryReviewBuilder.weekStart(of: weekOfSaturday, calendar: mondayFirst),
                       day(2026, 9, 21))
    }

    func testWeekEndIsNextMondayMidnight() {
        let start = SummaryReviewBuilder.weekStart(of: weekOfSaturday, calendar: calendar)
        XCTAssertEqual(SummaryReviewBuilder.weekEnd(of: start, calendar: calendar), day(2026, 9, 28))
    }

    func testWeekTitleFormatsRangeIncludingMonthSpans() {
        XCTAssertEqual(SummaryReviewBuilder.weekTitle(for: day(2026, 9, 21), calendar: calendar),
                       "9月21日-9月27日")
        XCTAssertEqual(SummaryReviewBuilder.weekTitle(for: day(2026, 9, 28), calendar: calendar),
                       "9月28日-10月4日")
    }

    // MARK: Section grouping

    func testGroupsSplitCompletedAbandonedAndUncompleted() {
        let builder = makeBuilder(now: weekOfSaturday)
        let tasks = [
            makeTask("写周报", list: "工作", dueAt: day(2026, 9, 22),
                     completedAt: day(2026, 9, 22, hour: 10), status: .completed),
            makeTask("换方案", list: "个人", abandonedAt: day(2026, 9, 23, hour: 9)),
            makeTask("准备评审", list: "学习", dueAt: day(2026, 9, 24)),
            makeTask("上周完成", completedAt: day(2026, 9, 18, hour: 10), status: .completed),
            makeTask("下周到期", dueAt: day(2026, 9, 30)),
            makeTask("无日期且未完成"),
        ]
        let review = builder.review(for: tasks, weekOf: weekOfSaturday)

        XCTAssertEqual(review.weekStart, day(2026, 9, 21))
        XCTAssertEqual(review.completed.map(\.title), ["写周报"])
        XCTAssertEqual(review.completed.first?.datePrefix, "[9月22日]")
        XCTAssertEqual(review.completed.first?.listName, "工作")
        XCTAssertEqual(review.abandoned.map(\.title), ["换方案"])
        XCTAssertEqual(review.abandoned.first?.datePrefix, "[9月23日]")
        XCTAssertEqual(review.uncompleted.map(\.title), ["准备评审"])
        XCTAssertEqual(review.uncompleted.first?.datePrefix, "")  // 未完成无日期前缀
        XCTAssertEqual(review.uncompleted.first?.listName, "学习")
    }

    func testDeletedAndSkippedTasksNeverAppear() {
        let builder = makeBuilder(now: weekOfSaturday)
        let tasks = [
            makeTask("删除的已完成", completedAt: day(2026, 9, 22),
                     deletedAt: day(2026, 9, 23), status: .completed),
            makeTask("删除的未完成", dueAt: day(2026, 9, 24), deletedAt: day(2026, 9, 23)),
            makeTask("跳过的未完成", dueAt: day(2026, 9, 24), skippedAt: day(2026, 9, 23)),
            makeTask("跳过的已放弃", abandonedAt: day(2026, 9, 22), skippedAt: day(2026, 9, 23)),
        ]
        let review = builder.review(for: tasks, weekOf: weekOfSaturday)
        XCTAssertTrue(review.isEmpty)
        XCTAssertTrue(review.completed.isEmpty)
        XCTAssertTrue(review.abandoned.isEmpty)
        XCTAssertTrue(review.uncompleted.isEmpty)
    }

    func testItemsSortByReferenceDateDescendingThenTitle() {
        let builder = makeBuilder(now: weekOfSaturday)
        let tasks = [
            makeTask("周一完成", completedAt: day(2026, 9, 21, hour: 9), status: .completed),
            makeTask("周五完成", completedAt: day(2026, 9, 25, hour: 9), status: .completed),
            makeTask("周三完成", completedAt: day(2026, 9, 23, hour: 9), status: .completed),
            makeTask("同日B", completedAt: day(2026, 9, 23, hour: 10), status: .completed),
            makeTask("同日A", completedAt: day(2026, 9, 23, hour: 10), status: .completed),
        ]
        let review = builder.review(for: tasks, weekOf: weekOfSaturday)
        XCTAssertEqual(review.completed.map(\.title),
                       ["周五完成", "同日A", "同日B", "周三完成", "周一完成"])
    }

    // MARK: Empty week

    func testEmptyWeekReturnsEmptyGroupsWithTitle() {
        let builder = makeBuilder(now: weekOfSaturday)
        let review = builder.review(for: [], weekOf: weekOfSaturday)
        XCTAssertEqual(review.weekTitle, "9月21日-9月27日")
        XCTAssertTrue(review.isEmpty)
    }

    // MARK: Picker weeks

    func testAvailableWeeksListsCurrentWeekFirstThenPastContentWeeks() {
        let builder = makeBuilder(now: day(2026, 9, 26, hour: 12))
        let tasks = [
            makeTask("本周完成", completedAt: day(2026, 9, 22), status: .completed),
            makeTask("本周未完成", dueAt: day(2026, 9, 24)),
            makeTask("上周完成", completedAt: day(2026, 9, 15), status: .completed),
            makeTask("两周前放弃", abandonedAt: day(2026, 9, 8)),
            makeTask("三周前完成", completedAt: day(2026, 9, 1), status: .completed),
            makeTask("一个月前完成", completedAt: day(2026, 8, 20), status: .completed),
        ]
        let weeks = builder.availableWeeks(for: tasks)

        XCTAssertEqual(weeks.first?.weekStart, day(2026, 9, 21))
        XCTAssertEqual(weeks.first?.completedCount, 1)
        XCTAssertEqual(weeks.first?.isCurrent, true)
        XCTAssertEqual(weeks.dropFirst().map(\.weekStart),
                       [day(2026, 9, 14), day(2026, 9, 7), day(2026, 8, 31), day(2026, 8, 17)])
        XCTAssertEqual(weeks.dropFirst().map(\.isCurrent), [false, false, false, false])
    }

    func testAvailableWeeksRespectsMaximumAndAlwaysKeepsCurrentWeek() {
        let builder = makeBuilder(now: day(2026, 9, 26, hour: 12))
        let tasks = [
            makeTask("本周完成", completedAt: day(2026, 9, 22), status: .completed),
            makeTask("上周完成", completedAt: day(2026, 9, 15), status: .completed),
            makeTask("两周前完成", completedAt: day(2026, 9, 8), status: .completed),
        ]
        let weeks = builder.availableWeeks(for: tasks, maximum: 2)
        XCTAssertEqual(weeks.map(\.weekStart), [day(2026, 9, 21), day(2026, 9, 14)])
        XCTAssertEqual(weeks.first?.isCurrent, true)
    }

    func testAvailableWeeksWithoutTasksReturnsOnlyCurrentWeek() {
        let builder = makeBuilder(now: day(2026, 9, 26, hour: 12))
        let weeks = builder.availableWeeks(for: [])
        XCTAssertEqual(weeks.count, 1)
        XCTAssertEqual(weeks.first?.weekStart, day(2026, 9, 21))
        XCTAssertEqual(weeks.first?.completedCount, 0)
        XCTAssertEqual(weeks.first?.isCurrent, true)
    }

    // MARK: Copy text

    func testPlainTextContainsTitleSectionsAndPrefixedRows() {
        let builder = makeBuilder(now: weekOfSaturday)
        let tasks = [
            makeTask("写周报", list: "工作", completedAt: day(2026, 9, 22, hour: 10), status: .completed),
            makeTask("换方案", list: "个人", abandonedAt: day(2026, 9, 23, hour: 9)),
            makeTask("准备评审", list: "学习", dueAt: day(2026, 9, 24)),
        ]
        let text = builder.plainText(for: builder.review(for: tasks, weekOf: weekOfSaturday))
        XCTAssertTrue(text.hasPrefix("9月21日-9月27日"))
        XCTAssertTrue(text.contains("已完成\n[9月22日] 写周报（工作）"))
        XCTAssertTrue(text.contains("已放弃\n[9月23日] 换方案（个人）"))
        XCTAssertTrue(text.contains("未完成\n准备评审（学习）"))
    }

    // MARK: - Filter (清单 / 状态)

    func testFilterByStatusKeepsOnlyCompletedSection() {
        let builder = makeBuilder(now: day(2026, 9, 26))
        let tasks = [
            makeTask("完成A", completedAt: day(2026, 9, 22), status: .completed),
            makeTask("未完成B", dueAt: day(2026, 9, 23)),
        ]
        var filter = SummaryFilter.all
        filter.status = .completed
        let review = builder.review(for: tasks, weekOf: weekOfSaturday, filter: filter)
        XCTAssertEqual(review.completed.map(\.title), ["完成A"])
        XCTAssertTrue(review.abandoned.isEmpty)
        XCTAssertTrue(review.uncompleted.isEmpty)
    }

    func testFilterByUncompletedDropsCompletedSection() {
        let builder = makeBuilder(now: day(2026, 9, 26))
        let tasks = [
            makeTask("完成A", completedAt: day(2026, 9, 22), status: .completed),
            makeTask("未完成B", dueAt: day(2026, 9, 23)),
        ]
        var filter = SummaryFilter.all
        filter.status = .uncompleted
        let review = builder.review(for: tasks, weekOf: weekOfSaturday, filter: filter)
        XCTAssertTrue(review.completed.isEmpty)
        XCTAssertEqual(review.uncompleted.map(\.title), ["未完成B"])
    }

    func testFilterByListExcludesOtherLists() {
        let builder = makeBuilder(now: day(2026, 9, 26))
        let tasks = [
            makeTask("工作A", list: "工作", completedAt: day(2026, 9, 22), status: .completed),
            makeTask("学习B", list: "学习", completedAt: day(2026, 9, 23), status: .completed),
        ]
        var filter = SummaryFilter.all
        filter.listName = "工作"
        let review = builder.review(for: tasks, weekOf: weekOfSaturday, filter: filter)
        XCTAssertEqual(review.completed.map(\.title), ["工作A"])
    }

    // MARK: - Grouping (完成状态 / 清单 / 优先级 / 标签)

    func testGroupingByListBucketsTasks() {
        let builder = makeBuilder(now: day(2026, 9, 26))
        let tasks = [
            makeTask("工作A", list: "工作", completedAt: day(2026, 9, 22), status: .completed),
            makeTask("学习B", list: "学习", completedAt: day(2026, 9, 23), status: .completed),
        ]
        let review = builder.review(for: tasks, weekOf: weekOfSaturday)
        let sections = SummaryReviewBuilder.sections(from: review, grouping: .list)
        // localizedStandardCompare：拼音序「工作(gongzuo)」在「学习(xuexi)」前。
        XCTAssertEqual(sections.map(\.title), ["工作", "学习"])
        XCTAssertEqual(sections.first(where: { $0.title == "工作" })?.items.map(\.title), ["工作A"])
    }

    func testGroupingByPriorityOrdersHighFirst() {
        let builder = makeBuilder(now: day(2026, 9, 26))
        let tasks = [
            makeTask("低", priority: .low, completedAt: day(2026, 9, 22), status: .completed),
            makeTask("高", priority: .high, completedAt: day(2026, 9, 23), status: .completed),
        ]
        let review = builder.review(for: tasks, weekOf: weekOfSaturday)
        let sections = SummaryReviewBuilder.sections(from: review, grouping: .priority)
        XCTAssertEqual(sections.map(\.title), ["高优先级", "低优先级"])
    }

    func testGroupingByTagIncludesUntaggedBucket() {
        let builder = makeBuilder(now: day(2026, 9, 26))
        let tasks = [
            makeTask("带标签", tags: ["紧急"], completedAt: day(2026, 9, 22), status: .completed),
            makeTask("没标签", completedAt: day(2026, 9, 23), status: .completed),
        ]
        let review = builder.review(for: tasks, weekOf: weekOfSaturday)
        let sections = SummaryReviewBuilder.sections(from: review, grouping: .tag)
        XCTAssertEqual(Set(sections.map(\.title)), ["紧急", "无标签"])
    }

    // MARK: - Filter by tag (右栏「更多」)

    func testFilterByTagExcludesTasksWithoutThatTag() {
        let builder = makeBuilder(now: day(2026, 9, 26))
        let tasks = [
            makeTask("带标签", tags: ["紧急"], completedAt: day(2026, 9, 22), status: .completed),
            makeTask("另一个标签", tags: ["稍后"], completedAt: day(2026, 9, 23), status: .completed),
            makeTask("没标签", completedAt: day(2026, 9, 24), status: .completed),
        ]
        var filter = SummaryFilter.all
        filter.tagName = "紧急"
        let review = builder.review(for: tasks, weekOf: weekOfSaturday, filter: filter)
        XCTAssertEqual(review.completed.map(\.title), ["带标签"])
    }

    // MARK: - 显示内容（日期 / 清单 / 标签）

    func testItemTextFollowsContentSwitches() {
        let item = ReviewItem(datePrefix: "10月20日", title: "写周报",
                              listName: "工作", tagNames: ["紧急"])

        var filter = SummaryFilter.all
        filter.showsDate = false
        XCTAssertEqual(SummaryReviewBuilder.itemText(item, filter: filter), "写周报")

        filter.showsDate = true
        XCTAssertEqual(SummaryReviewBuilder.itemText(item, filter: filter), "10月20日  写周报")

        filter.showsList = true
        XCTAssertEqual(SummaryReviewBuilder.itemText(item, filter: filter),
                       "10月20日  写周报  （工作）")

        filter.showsTags = true
        XCTAssertEqual(SummaryReviewBuilder.itemText(item, filter: filter),
                       "10月20日  写周报  （工作）  #紧急")
    }

    func testDocumentBulletsRespectFilterSwitches() {
        let builder = makeBuilder(now: day(2026, 9, 26))
        let tasks = [
            makeTask("写周报", list: "工作", tags: ["紧急"],
                     completedAt: day(2026, 9, 22), status: .completed),
        ]
        let review = builder.review(for: tasks, weekOf: weekOfSaturday)

        var filter = SummaryFilter.all   // 默认只带日期
        let withDate = builder.document(for: review, grouping: .completion, filter: filter)
            .plainText
        XCTAssertTrue(withDate.contains("[9月22日]  写周报"))

        filter.showsDate = false
        filter.showsList = true
        filter.showsTags = true
        let bare = builder.document(for: review, grouping: .completion, filter: filter)
            .plainText
        XCTAssertTrue(bare.contains("写周报  （工作）  #紧急"))
        // 关掉日期后，条目行不应再出现日期前缀（标题行 h1 仍带日期，不算）。
        XCTAssertFalse(bare.contains("[9月22日]"))
    }
}
