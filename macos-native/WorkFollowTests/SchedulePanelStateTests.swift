import XCTest
@testable import WorkFollow

/// 面板导航状态（`SchedulePanelPresentationState`）的纯逻辑回归。
///
/// 这层状态以前是五个并行 `@State`（`expandedProperty` / `recurrencePage` /
/// `reminderCustomOpen` / `repeatCustomOpen` / `repeatEndEdit`），
/// 开合与"返回 / Esc / ×"各写一份判断。现在收敛成一个 reducer，这里锁住它的口径：
/// **先弹最深子页，再收二级页，最后收属性子卡；到底交给宿主**。
final class SchedulePanelStateTests: XCTestCase {

    func testBackPopsSubPageThenRecurrencePageThenProperty() {
        var state = SchedulePanelPresentationState()
        state.expandedProperty = .repeat
        state.recurrencePage = .work
        state.open(.repeatCustom)

        XCTAssertTrue(state.back(), "先弹最深子页")
        XCTAssertNil(state.subPage)
        XCTAssertEqual(state.recurrencePage, .work, "二级页还在")
        XCTAssertEqual(state.expandedProperty, .repeat, "属性子卡还在")

        XCTAssertTrue(state.back())
        XCTAssertNil(state.recurrencePage)
        XCTAssertEqual(state.expandedProperty, .repeat)

        XCTAssertTrue(state.back())
        XCTAssertNil(state.expandedProperty)
        XCTAssertFalse(state.back(), "已经到底，Esc 该交给宿主关面板")
    }

    func testOpeningTheSameSubPageTwiceDoesNotStack() {
        var state = SchedulePanelPresentationState()
        state.open(.reminderCustom)
        state.open(.reminderCustom)
        XCTAssertEqual(state.subPages.count, 1)
        XCTAssertTrue(state.back())
        XCTAssertNil(state.subPage)
    }

    func testCloseDropsThatPageAndEverythingDeeper() {
        var state = SchedulePanelPresentationState()
        state.open(.reminderCustom)
        state.open(.repeatCustom)
        state.close(.repeatCustom)
        XCTAssertFalse(state.shows(.repeatCustom))
        XCTAssertTrue(state.shows(.reminderCustom), "收深层不影响更浅的层")
    }

    func testPropertyClearedClosesItsBoundSubPages() {
        var state = SchedulePanelPresentationState()
        state.expandedProperty = .reminder
        state.open(.reminderCustom)
        state.propertyCleared(.reminder)
        XCTAssertFalse(state.shows(.reminderCustom), "清提醒要收掉自定义提前量")

        state.open(.repeatCustom)
        state.open(.repeatEnd(.date))
        state.propertyCleared(.repeat)
        XCTAssertFalse(state.shows(.repeatCustom))
        XCTAssertFalse(state.shows(.repeatEnd(.date)), "清重复要收掉重复结束页")
    }

    func testRepeatEndVariantsReplaceEachOther() {
        var state = SchedulePanelPresentationState()
        state.expandedProperty = .repeatEnd
        state.open(.repeatEnd(.date))
        XCTAssertEqual(state.repeatEndEdit, .date)
        state.open(.repeatEnd(.count))
        XCTAssertEqual(state.repeatEndEdit, .count)
        XCTAssertEqual(state.subPages.count, 1, "两种编辑互斥，切换而不是叠加")
        state.closeRepeatEnd()
        XCTAssertFalse(state.shows(.repeatEnd(.count)))
        XCTAssertNil(state.repeatEndEdit)
    }

    func testCollapsePropertyDropsEveryDeeperLayer() {
        var state = SchedulePanelPresentationState()
        state.expandedProperty = .reminder
        state.open(.reminderCustom)
        state.recurrencePage = .lunar
        state.collapseProperty()
        XCTAssertNil(state.expandedProperty)
        XCTAssertNil(state.recurrencePage)
        XCTAssertTrue(state.subPages.isEmpty)
    }

    @MainActor
    func testClearingAnOptionAlsoDropsItsSubPage() {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try! XCTUnwrap(workspace.createTask(title: "清除语义", in: .inbox).taskID)
        let task = try! XCTUnwrap(workspace.task(for: id))
        let model = TaskDateDraftModel(task: task, calendar: workspace.calendar,
                                       now: workspace.clock, deadline: false)
        var state = SchedulePanelPresentationState()
        state.expandedProperty = .reminder
        state.open(.reminderCustom)

        SchedulePanelInteraction.clear(.reminder, state: &state, model: model)

        XCTAssertTrue(state.subPages.isEmpty, "× 清提醒时自定义提前量页必须一起收掉")
        XCTAssertNil(state.expandedProperty)
    }
}
