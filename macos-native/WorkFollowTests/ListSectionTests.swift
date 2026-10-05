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

    private func makeTask(title: String, sectionID: String? = nil, dueAt: Date? = nil,
                          priority: TaskPriority = .none, createdAt: Date? = nil,
                          updatedAt: Date? = nil) -> Task {
        Task(id: UUID(), title: title, list: TaskList(name: "工作"), priority: priority,
             schedule: TaskSchedule(dueAt: dueAt, hasTime: false), parentID: nil, childOrder: 0,
             createdAt: createdAt ?? now, updatedAt: updatedAt ?? now, sectionID: sectionID)
    }

    // MARK: - 分组内排序（滴答「清单页 → … → 分组排序」）

    func testSectionSortRearrangesTasksInsideEachBucket() {
        let section = TaskListSection(id: "s1", listName: "工作", title: "进行中", sortOrder: 0)
        let base = now
        func task(_ title: String, _ sectionID: String?, due: TimeInterval?,
                  priority: TaskPriority, created: TimeInterval, updated: TimeInterval) -> Task {
            makeTask(title: title, sectionID: sectionID,
                     dueAt: due.map { base.addingTimeInterval($0) }, priority: priority,
                     createdAt: base.addingTimeInterval(created),
                     updatedAt: base.addingTimeInterval(updated))
        }
        let tasks = [task("晚", "s1", due: 300, priority: .none, created: 10, updated: 100),
                     task("早", "s1", due: 100, priority: .high, created: 20, updated: 10),
                     task("无日期", "s1", due: nil, priority: .low, created: 30, updated: 200),
                     task("未分组", nil, due: 50, priority: .medium, created: 5, updated: 5)]

        func order(_ sort: TaskSectionSort?) -> [String] {
            TaskListSectionProjection.groups(tasks, list: "工作", sections: [section], sort: sort)?
                .first { $0.label == section.title }?.tasks.map(\.title) ?? []
        }
        XCTAssertEqual(order(nil), ["晚", "早", "无日期"], "默认 = 跟随视图排序（保持传入顺序）")
        XCTAssertEqual(order(.dueDate), ["早", "晚", "无日期"], "按时间：无日期排最后")
        XCTAssertEqual(order(.priority), ["早", "无日期", "晚"], "按优先级：高 → 低 → 无")
        XCTAssertEqual(order(.createdNewest), ["无日期", "早", "晚"])
        XCTAssertEqual(order(.createdOldest), ["晚", "早", "无日期"])
        XCTAssertEqual(order(.modifiedNewest), ["无日期", "晚", "早"])
        XCTAssertEqual(order(.modifiedOldest), ["早", "晚", "无日期"])

        let unsectioned = TaskListSectionProjection
            .groups(tasks, list: "工作", sections: [section], sort: .priority)?
            .first { $0.label == "未分组" }?.tasks.map(\.title)
        XCTAssertEqual(unsectioned, ["未分组"], "未分组桶同样应用分组内排序")
    }

    func testSectionSortIsListLevelAndOneUndo() {
        let (store, actions) = makeActions()
        _ = actions.renameList(nil, to: "工作")
        XCTAssertFalse(actions.setListSectionSort("工作", nil), "本来就是默认 → 不算改动")
        XCTAssertTrue(actions.setListSectionSort("工作", .priority))
        XCTAssertEqual(store.listMeta(for: "工作")?.sectionTaskSort, .priority)
        XCTAssertFalse(actions.setListSectionSort("工作", .priority), "同值不重复提交")
        actions.undo()
        XCTAssertNil(store.listMeta(for: "工作")?.sectionTaskSort, "一步撤销回默认")
    }

    func testSectionSortIsAdditiveCodable() throws {
        let meta = TaskListMeta(name: "工作", sectionTaskSort: .modifiedNewest)
        let data = try JSONEncoder().encode(meta)
        XCTAssertEqual(try JSONDecoder().decode(TaskListMeta.self, from: data).sectionTaskSort,
                       .modifiedNewest)
        var raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        raw.removeValue(forKey: "sectionTaskSort")
        let legacy = try JSONDecoder().decode(TaskListMeta.self,
                                              from: try JSONSerialization.data(withJSONObject: raw))
        XCTAssertNil(legacy.sectionTaskSort, "旧快照缺键 → 默认（跟随视图排序）")
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

    func testSectionGroupsCarrySectionIDForKanbanDrops() {
        let first = TaskListSection(id: "s1", listName: "工作", title: "进行中", sortOrder: 0)
        let tasks = [makeTask(title: "无归属"), makeTask(title: "在 s1", sectionID: "s1")]
        let groups = TaskListSectionProjection.groups(tasks, list: "工作", sections: [first])
        XCTAssertEqual(groups?.first { $0.label == "进行中" }?.sectionID, "s1",
                       "列 = 分组时带出分组 id，看板才能把卡片落进来")
        XCTAssertNil(groups?.first { $0.label == "未分组" }?.sectionID, "未分组不是可落列")
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

    // MARK: - 滴答分组标题菜单的"上/下方添加分组"

    func testInsertListSectionAboveAndBelowKeepsOrder() {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.renameList(nil, to: "工作")
        XCTAssertTrue(actions.addListSection("工作", title: "乙"))
        let second = try? XCTUnwrap(store.listSections.first { $0.title == "乙" })
        guard let second else { return XCTFail("乙 未建出") }

        XCTAssertTrue(actions.insertListSection("工作", title: "甲", above: second.id),
                      "在上方添加")
        XCTAssertEqual(store.listSections.filter { $0.listName == "工作" }.sorted { $0.sortOrder < $1.sortOrder }.map(\.title), ["甲", "乙"])
        XCTAssertEqual(store.listSections.filter { $0.listName == "工作" }.sorted { $0.sortOrder < $1.sortOrder }.map(\.sortOrder), [0, 1],
                       "插入后序号要重排，否则位置会漂")

        XCTAssertTrue(actions.insertListSection("工作", title: "丙", above: nil), "追加到末尾")
        XCTAssertEqual(store.listSections.filter { $0.listName == "工作" }.sorted { $0.sortOrder < $1.sortOrder }.map(\.title), ["甲", "乙", "丙"])

        XCTAssertFalse(actions.insertListSection("工作", title: "甲", above: nil), "同清单重名被拒")
        actions.undo()
        XCTAssertEqual(store.listSections.filter { $0.listName == "工作" }.sorted { $0.sortOrder < $1.sortOrder }.map(\.title), ["甲", "乙"],
                       "一次插入 = 一步撤销")
    }

    func testMoveListSectionGuards() {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.renameList(nil, to: "工作")
        _ = actions.renameList(nil, to: "生活")
        XCTAssertTrue(actions.addListSection("工作", title: "阶段一"))
        guard let section = store.listSections.first(where: { $0.title == "阶段一" }) else {
            return XCTFail("分组未建出")
        }
        XCTAssertFalse(actions.moveListSection(section.id, to: "工作"), "移到自己所在的清单被拒")
        XCTAssertFalse(actions.moveListSection(section.id, to: "   "), "空清单名被拒")
        XCTAssertTrue(actions.moveListSection(section.id, to: "生活"))
        XCTAssertEqual(store.listSection(section.id)?.listName, "生活")
        XCTAssertEqual(store.listSections.filter { $0.listName == "工作" }.sorted { $0.sortOrder < $1.sortOrder }.count, 0, "原清单不再有该分组")
        actions.undo()
        XCTAssertEqual(store.listSection(section.id)?.listName, "工作", "一步撤销归位")
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
