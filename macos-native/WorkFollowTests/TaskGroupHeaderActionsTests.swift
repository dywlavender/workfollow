import XCTest
@testable import WorkFollow

/// 任务栏优化第一批：分组头动作位（对齐滴答 `TTTaskListSectionCell` 的三枚固定 outlet）。
///
/// 滴答证据：`addButton`(24×24) / `moreButton`(24×24) / `actionButton`(58×18 文字)，
/// 动作池是 `addButtonClicked:` / `moreButtonClicked:` / `postponeButtonClicked` /
/// `selectAllButtonClicked`。旧实现把 `+` 与 `…` 都挂在 `if let sectionID` 里，
/// 系统分组（今天 / 已过期）因此永远没有按钮。
@MainActor
final class TaskGroupHeaderActionsTests: XCTestCase {

    private var today: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 24))!
    }

    // MARK: - + 覆盖所有分组

    func testEveryNonCompletedGroupOffersAdd() {
        for kind in [TaskGroupKind.pinned, .overdue, .today, .upcoming, .later, .undated, .day, .plain] {
            let actions = TaskGroupHeaderActions.resolve(kind: kind, sectionID: nil, day: today,
                                                         taskCount: 3, today: today)
            XCTAssertTrue(actions.showsAdd, "\(kind) 分组也要有「+」（滴答是固定 outlet）")
        }
    }

    func testCompletedGroupHasNoActions() {
        let actions = TaskGroupHeaderActions.resolve(kind: .completed, sectionID: nil, day: today,
                                                     taskCount: 5, today: today)
        XCTAssertFalse(actions.showsAdd, "已完成组不该能再建一条已完成任务")
        XCTAssertFalse(actions.showsMenu)
        XCTAssertNil(actions.primary)
        XCTAssertEqual(actions.prefill, .none)
    }

    // MARK: - 文字动作

    func testOverdueGroupOffersPostpone() {
        let actions = TaskGroupHeaderActions.resolve(kind: .overdue, sectionID: nil, day: nil,
                                                     taskCount: 4, today: today)
        XCTAssertEqual(actions.primary, .postpone)
        XCTAssertEqual(actions.primary?.title, "顺延")
    }

    func testOtherGroupsOfferSelectAll() {
        for kind in [TaskGroupKind.today, .upcoming, .undated, .plain, .day] {
            let actions = TaskGroupHeaderActions.resolve(kind: kind, sectionID: nil, day: today,
                                                         taskCount: 2, today: today)
            XCTAssertEqual(actions.primary, .selectAll, "\(kind) 应给「全选」")
            XCTAssertEqual(actions.primary?.title, "全选")
        }
    }

    func testEmptyGroupHasNoPrimaryAction() {
        let overdue = TaskGroupHeaderActions.resolve(kind: .overdue, sectionID: nil, day: nil,
                                                     taskCount: 0, today: today)
        XCTAssertNil(overdue.primary, "0 条时「顺延」是死按钮")
        let todayEmpty = TaskGroupHeaderActions.resolve(kind: .today, sectionID: nil, day: today,
                                                        taskCount: 0, today: today)
        XCTAssertNil(todayEmpty.primary, "0 条时「全选」是死按钮")
        XCTAssertTrue(todayEmpty.showsAdd, "空组仍然可以新建")
    }

    // MARK: - 菜单归属

    func testMenuOnlyForSections() {
        let system = TaskGroupHeaderActions.resolve(kind: .today, sectionID: nil, day: today,
                                                    taskCount: 1, today: today)
        XCTAssertFalse(system.showsMenu, "系统分组没有归属可改，不给「…」")

        let section = TaskGroupHeaderActions.resolve(kind: .plain, sectionID: "sec-1", day: nil,
                                                     taskCount: 1, today: today)
        XCTAssertTrue(section.showsMenu)
        XCTAssertEqual(section.prefill, .section("sec-1"))
    }

    func testUnsectionedBucketGetsMenuButNoSectionPrefill() {
        let bucket = TaskGroupHeaderActions.resolve(kind: .plain, sectionID: nil, day: nil,
                                                    taskCount: 2, isUnsectionedBucket: true, today: today)
        XCTAssertTrue(bucket.showsMenu, "「未分组」桶能改名/搬移")
        XCTAssertEqual(bucket.prefill, .none, "它没有 sectionID 可预填")
    }

    // MARK: - + 的预填落点

    func testDayGroupsPrefillTheirOwnDate() {
        let day = TaskGroupHeaderActions.resolve(kind: .day, sectionID: nil, day: today,
                                                 taskCount: 1, today: today)
        XCTAssertEqual(day.prefill, .due(today))
    }

    func testTodayGroupPrefillsToday() {
        let actions = TaskGroupHeaderActions.resolve(kind: .today, sectionID: nil, day: today,
                                                     taskCount: 1, today: today)
        XCTAssertEqual(actions.prefill, .due(today))
    }

    func testOverdueGroupPrefillsTodayNotTheOverdueDay() {
        let actions = TaskGroupHeaderActions.resolve(kind: .overdue, sectionID: nil, day: today,
                                                     taskCount: 1, today: today)
        XCTAssertEqual(actions.prefill, .due(today),
                       "在逾期组新建的任务不该一出生就逾期")
    }

    func testUndatedGroupHasNoDatePrefill() {
        let actions = TaskGroupHeaderActions.resolve(kind: .undated, sectionID: nil, day: nil,
                                                     taskCount: 1, today: today)
        XCTAssertEqual(actions.prefill, .none)
    }

}
