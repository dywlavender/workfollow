import XCTest
@testable import WorkFollow

/// 分组搬家要**带着任务一起走**：只搬分组会把任务留在没有该分组的清单里。
/// 单独一个文件：夹具签名对不上时便于整文件撤掉，而不影响其它测试。
final class MoveListSectionCarriesTasksTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testMoveListSectionCarriesItsTasksAndIsOneUndoStep() {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.renameList(nil, to: "工作")
        _ = actions.renameList(nil, to: "生活")
        XCTAssertTrue(actions.addListSection("工作", title: "阶段一"))
        guard let section = store.listSections.first(where: { $0.title == "阶段一" }) else {
            return XCTFail("分组未建出")
        }
        let created = actions.createDraft(title: "任务 A", list: "工作", schedule: TaskSchedule(),
                                          priority: .none, tags: [], reminder: nil,
                                          frequency: TaskRepeat.never)
        guard let taskID = created.taskID else { return XCTFail("任务未建出") }
        _ = actions.setTaskSection(taskID, sectionID: section.id)

        XCTAssertTrue(actions.moveListSection(section.id, to: "生活"))
        XCTAssertEqual(store.listSection(section.id)?.listName, "生活")
        XCTAssertEqual(store.task(taskID)?.list.name, "生活", "分组里的任务跟着搬")
        actions.undo()
        XCTAssertEqual(store.listSection(section.id)?.listName, "工作", "一步撤销把分组带回来")
        XCTAssertEqual(store.task(taskID)?.list.name, "工作", "任务一起回滚")
    }
}
