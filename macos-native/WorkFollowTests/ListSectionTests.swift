import XCTest
@testable import WorkFollow

/// 清单内自定义分组（滴答层级第三级：文件夹 → 清单 → 分组 → 任务 → 子任务）。
/// 官方：仅普通清单支持自定义分组（智能清单不支持）；看板视图以分组为列。
final class ListSectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeActions() -> (WorkspaceStore, TaskActions) {
        let store = WorkspaceStore()
        return (store, TaskActions(store: store, clock: { self.now }))
    }

    private func addTask(_ actions: TaskActions, title: String, list: String) -> UUID {
        let result = actions.createDraft(title: title, list: list,
                                         schedule: TaskSchedule(), priority: .none, tags: [],
                                         reminder: nil, frequency: .never)
        return result.taskID!
    }

    private func makeTask(title: String, sectionID: String?) -> Task {
        Task(id: UUID(), title: title, list: TaskList(name: "工作"), priority: .none,
             schedule: TaskSchedule(), parentID: nil, childOrder: 0,
             createdAt: now, updatedAt: now, sectionID: sectionID)
    }

    func testSectionAddRenameRemoveAndAssignmentIsOneUndoStep() {
        let (store, actions) = makeActions()
        _ = actions.renameList(nil, to: "工作")
        XCTAssertTrue(actions.addListSection("工作", title: "进行中"))
        XCTAssertFalse(actions.addListSection("工作", title: "进行中"), "同清单重名被拒")
        XCTAssertFalse(actions.addListSection("工作", title: "   "), "空名被拒")
        XCTAssertFalse(actions.addListSection(TaskList.inbox.name, title: "进行中"), "收集箱不支持分组")

        let id = addTask(actions, title: "写周报", list: "工作")
        guard let section = store.listSections.first else { return XCTFail("分组没建出来") }
        XCTAssertNotNil(actions.setTaskSection(id, sectionID: section.id).taskID)
        XCTAssertEqual(store.task(id)?.sectionID, section.id)
        actions.undo()
        XCTAssertNil(store.task(id)?.sectionID, "改归属是一步撤销")
        XCTAssertEqual(store.listSections.count, 1, "撤销归属不会动分组本身")

        XCTAssertTrue(actions.renameListSection(section.id, title: "进行中 2"))
        XCTAssertEqual(store.listSection(section.id)?.title, "进行中 2")
        XCTAssertEqual(store.listSection(section.id)?.id, section.id, "重命名不换身份")

        _ = actions.setTaskSection(id, sectionID: section.id)
        XCTAssertTrue(actions.removeListSection(section.id))
        XCTAssertNil(store.task(id)?.sectionID, "删分组时任务保留并回到未分组")
        XCTAssertNotNil(store.task(id), "任务没被删掉")
        XCTAssertTrue(store.listSections.isEmpty)
    }

    func testSectionProjectionPutsUnsectionedFirstAndKeepsOrderAndEmptySections() {
        let first = TaskListSection(id: "s1", listName: "工作", title: "进行中", sortOrder: 0)
        let second = TaskListSection(id: "s2", listName: "工作", title: "待办", sortOrder: 1)
        let other = TaskListSection(id: "s3", listName: "生活", title: "别的清单", sortOrder: 0)
        let tasks = [makeTask(title: "无归属", sectionID: nil),
                     makeTask(title: "在 s1", sectionID: "s1"),
                     makeTask(title: "也在 s1", sectionID: "s1"),
                     makeTask(title: "别的清单的分组", sectionID: "s3")]
        let groups = TaskListSectionProjection.groups(tasks, list: "工作",
                                                      sections: [first, second, other])
        XCTAssertEqual(groups?.map(\.label), ["未分组", "进行中", "待办"],
                       "未分组在最前；只画本清单的分组；空分组也保留")
        XCTAssertEqual(groups?.map { $0.tasks.count }, [2, 2, 0])
        XCTAssertEqual(groups?.map(\.id), ["plain:未分组", "plain:进行中", "plain:待办"],
                       "组身份按标签互不串（折叠状态不串）")
    }

    func testSectionProjectionIsInertWithoutSections() {
        let tasks = [makeTask(title: "普通任务", sectionID: nil)]
        XCTAssertNil(TaskListSectionProjection.groups(tasks, list: "工作", sections: []),
                     "没有分组时返回 nil：调用方沿用用户选的分组方式")
    }

    func testTaskSectionIDIsAdditiveCodable() throws {
        let task = makeTask(title: "带分组", sectionID: "s1")
        let data = try JSONEncoder().encode(task)
        XCTAssertEqual(try JSONDecoder().decode(Task.self, from: data).sectionID, "s1")
        var raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        raw.removeValue(forKey: "sectionID")
        let legacy = try JSONDecoder().decode(Task.self,
                                              from: try JSONSerialization.data(withJSONObject: raw))
        XCTAssertNil(legacy.sectionID, "旧快照缺 sectionID → 未分组")
    }

    @MainActor
    func testWorkspaceHydratesSections() {
        let (store, actions) = makeActions()
        _ = actions.renameList(nil, to: "工作")
        XCTAssertTrue(actions.addListSection("工作", title: "进行中"))
        let model = TaskWorkspaceModel(seedDemoData: false, initialTasks: [], initialLists: ["工作"],
                                       initialListMeta: nil, initialListFolders: [],
                                       initialListSections: store.listSections)
        XCTAssertEqual(model.listSections(forList: "工作").map(\.title), ["进行中"])
        XCTAssertTrue(model.listSections(forList: "生活").isEmpty)
    }
}
