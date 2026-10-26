import XCTest
@testable import WorkFollow

/// 分组头动作位（滴答实机 2026-10-24）：
/// - 日期/优先级分组头没有 + / …；
/// - 只有已过期且非空才有「顺延」；
/// - 自定义小节（含未分组桶）才有 +，小节还有 …。
@MainActor
final class TaskGroupHeaderActionsTests: XCTestCase {

    func testSystemGroupsHaveNoHeaderActions() {
        for kind in [TaskGroupKind.pinned, .today, .upcoming, .later, .undated, .day, .plain] {
            let actions = TaskGroupHeaderActions.resolve(kind: kind, sectionID: nil, taskCount: 3)
            XCTAssertFalse(actions.showsAdd, "\(kind) 是系统分组，不应该有 +")
            XCTAssertFalse(actions.showsMenu, "\(kind) 没有归属可改，不应该有 …")
            XCTAssertFalse(actions.showsPostpone, "\(kind) 只有已过期才有顺延")
            XCTAssertEqual(actions.prefill, .none)
        }
    }

    func testOverdueOffersPostponeOnlyWhenNonEmpty() {
        let overdue = TaskGroupHeaderActions.resolve(kind: .overdue, sectionID: nil, taskCount: 4)
        XCTAssertTrue(overdue.showsPostpone)
        let empty = TaskGroupHeaderActions.resolve(kind: .overdue, sectionID: nil, taskCount: 0)
        XCTAssertFalse(empty.showsPostpone, "0 条时「顺延」是死按钮")
    }

    func testCompletedGroupHasNoActions() {
        let actions = TaskGroupHeaderActions.resolve(kind: .completed, sectionID: nil, taskCount: 5)
        XCTAssertFalse(actions.showsAdd)
        XCTAssertFalse(actions.showsMenu)
        XCTAssertFalse(actions.showsPostpone)
        XCTAssertEqual(actions.prefill, .none)
    }

    func testSectionOffersAddAndMenuWithSectionPrefill() {
        let section = TaskGroupHeaderActions.resolve(kind: .plain, sectionID: "sec-1", taskCount: 1)
        XCTAssertTrue(section.showsAdd)
        XCTAssertTrue(section.showsMenu)
        XCTAssertEqual(section.prefill, .section("sec-1"))
    }

    func testUnsectionedBucketGetsAddButNoMenuOrSectionPrefill() {
        let bucket = TaskGroupHeaderActions.resolve(kind: .plain, sectionID: nil, taskCount: 2,
                                                    isUnsectionedBucket: true)
        XCTAssertTrue(bucket.showsAdd)
        XCTAssertFalse(bucket.showsMenu, "桶没有 sectionID，不能改名/搬移")
        XCTAssertEqual(bucket.prefill, .none)
    }
}
