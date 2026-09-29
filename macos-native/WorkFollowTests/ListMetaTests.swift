import XCTest
@testable import WorkFollow

/// Round B1 清单元数据：TaskListMeta Codable 向后兼容、颜色/置顶/排序持久化往返、
/// 删除清单任务回收集箱、范围多选顺序、reorder 边界、色板与侧栏排序规则。
@MainActor
final class ListMetaTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Codable 向后兼容

    func testLegacySnapshotWithoutMetaDecodesWithTaskLists() throws {
        let json = #"{"version":1,"tasks":[],"notes":[],"taskLists":["收集箱","读书"]}"#
        let snapshot = try JSONDecoder().decode(NativeWorkspaceSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.taskLists, ["收集箱", "读书"])
        XCTAssertNil(snapshot.taskListMeta)
    }

    func testLegacySnapshotWithTasksAndMetaDecodesTogether() throws {
        let json = """
        {"version":1,
         "tasks":[{"id":"00000000-0000-0000-0000-000000000001","title":"旧任务",
                   "list":{"name":"读书"},"priority":0,"schedule":{"hasTime":false},
                   "childOrder":0,"createdAt":0,"updatedAt":0}],
         "notes":[],
         "taskLists":["收集箱","读书"],
         "taskListMeta":[{"name":"读书","colorIndex":4,"isPinned":true,"sortOrder":1}]}
        """
        let snapshot = try JSONDecoder().decode(NativeWorkspaceSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.tasks.first?.title, "旧任务")
        XCTAssertEqual(snapshot.taskListMeta,
                       [TaskListMeta(name: "读书", colorIndex: 4, isPinned: true, sortOrder: 1)])
    }

    func testTaskListMetaDecodesMissingOptionalKeys() throws {
        let json = #"{"name":"读书","colorIndex":2}"#
        let meta = try JSONDecoder().decode(TaskListMeta.self, from: Data(json.utf8))
        XCTAssertEqual(meta, TaskListMeta(name: "读书", colorIndex: 2, isPinned: false, sortOrder: 0))
    }

    // MARK: - 持久化往返（颜色/置顶/排序）

    func testListMetaPersistsThroughRepositoryRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wf-listmeta-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = NativePreviewRepository(directory: directory)
        let metas = [
            TaskListMeta(name: "读书", colorIndex: 4, isPinned: true, sortOrder: 0),
            TaskListMeta(name: "工作", colorIndex: nil, isPinned: false, sortOrder: 1),
            TaskListMeta(name: "旅行", sortOrder: 2, colorARGB: 0x80123456),
        ]
        try repository.save(NativeWorkspaceSnapshot(tasks: [], notes: [],
                                                    taskLists: ["读书", "工作", "旅行"], taskListMeta: metas))
        let loaded = try XCTUnwrap(repository.load())
        XCTAssertEqual(loaded.taskListMeta, metas)
        XCTAssertEqual(loaded.taskLists, ["读书", "工作", "旅行"])
    }

    func testWorkspaceAcceptsInitialMetaAndKeepsListNamesCompatible() {
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, seedDemoData: false,
                                           initialTasks: [], initialLists: ["收集箱", "读书", "工作"],
                                           initialListMeta: [
                                            TaskListMeta(name: "读书", colorIndex: 4, isPinned: true, sortOrder: 1),
                                            TaskListMeta(name: "工作", sortOrder: 2)])
        // listNames 对外契约不变：排除收集箱、字典序。
        XCTAssertEqual(workspace.listNames, ["工作", "读书"])
        XCTAssertEqual(workspace.allListNames, ["收集箱", "工作", "读书"])
        // 侧栏顺序：置顶在前，其余按 sortOrder。
        XCTAssertEqual(workspace.orderedListNames, ["读书", "工作"])
        XCTAssertEqual(workspace.listMeta(for: "读书")?.colorIndex, 4)
    }

    // MARK: - 颜色/置顶动作

    func testListColorAndPinnedPersistAndUndo() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.renameList(nil, to: "读书")
        _ = actions.setListColor("读书", 3)
        _ = actions.setListPinned("读书", true)
        XCTAssertEqual(store.listMeta(for: "读书"),
                       TaskListMeta(name: "读书", colorIndex: 3, isPinned: true, sortOrder: 0))
        _ = actions.setListColor("读书", 7)
        XCTAssertEqual(store.listMeta(for: "读书")?.colorIndex, 7)
        actions.undo()
        XCTAssertEqual(store.listMeta(for: "读书")?.colorIndex, 3)
        XCTAssertEqual(store.listMeta(for: "读书")?.isPinned, true)
        actions.undo()
        XCTAssertFalse(store.listMeta(for: "读书")?.isPinned ?? true)
    }

    func testSetListColorClampsToPaletteAndRejectsInbox() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.renameList(nil, to: "旅行")
        XCTAssertTrue(actions.setListColor("旅行", 99))
        XCTAssertEqual(store.listMeta(for: "旅行")?.colorIndex, WFListPalette.argb.count - 1)
        XCTAssertTrue(actions.setListColor("旅行", nil))
        XCTAssertNil(store.listMeta(for: "旅行")?.colorIndex)
        XCTAssertFalse(actions.setListColor(TaskList.inbox.name, 3))
        XCTAssertFalse(actions.setListPinned(TaskList.inbox.name, true))
        XCTAssertFalse(actions.setListColor("", 3))
        XCTAssertNil(store.listMeta(for: TaskList.inbox.name))
    }

    func testMetaOnImplicitListRegistersTheList() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.create(title: "想法", list: TaskList(name: "旅行"))
        XCTAssertFalse(store.lists.contains("旅行"))
        XCTAssertTrue(actions.setListPinned("旅行", true))
        XCTAssertEqual(store.lists, ["旅行"])
        XCTAssertEqual(store.listMeta(for: "旅行")?.isPinned, true)
    }

    func testRenameCarriesColorAndPinnedLikeFlutter() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.renameList(nil, to: "工作")
        _ = actions.setListColor("工作", 7)
        _ = actions.setListPinned("工作", true)
        actions.renameList("工作", to: "职场")
        XCTAssertEqual(store.lists, ["职场"])
        XCTAssertEqual(store.listMeta(for: "职场")?.colorIndex, 7)
        XCTAssertEqual(store.listMeta(for: "职场")?.isPinned, true)
        actions.undo()
        XCTAssertEqual(store.lists, ["工作"])
        XCTAssertEqual(store.listMeta(for: "工作")?.colorIndex, 7)
    }

    // MARK: - 删除清单：任务回收集箱 + 可撤销

    func testDeleteListMovesTasksToInboxAndUndoRestoresMeta() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.renameList(nil, to: "读书")
        let taskID = actions.create(title: "章节笔记", list: TaskList(name: "读书")).taskID!
        _ = actions.setListColor("读书", 4)
        actions.removeList("读书")
        XCTAssertEqual(store.task(taskID)?.list, .inbox)
        XCTAssertNil(store.task(taskID)?.deletedAt)
        XCTAssertFalse(store.lists.contains("读书"))
        XCTAssertNil(store.listMeta(for: "读书"))
        actions.undo()
        XCTAssertEqual(store.task(taskID)?.list.name, "读书")
        XCTAssertEqual(store.listMeta(for: "读书")?.colorIndex, 4)
        XCTAssertEqual(store.lists, ["读书"])
    }

    func testInboxCannotBeDeletedOrStyled() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.renameList(nil, to: "读书")
        actions.removeList(TaskList.inbox.name)
        XCTAssertFalse(actions.setListColor(TaskList.inbox.name, 3))
        XCTAssertFalse(actions.setListPinned(TaskList.inbox.name, true))
        XCTAssertEqual(store.lists, ["读书"])
        XCTAssertFalse(store.listMetas.contains { $0.name == TaskList.inbox.name })
    }

    // MARK: - 侧栏排序规则（Flutter orderedLists 语义）

    func testOrderingPutsPinnedFirstThenSortOrderThenName() {
        let names = ["乙", "甲", "丙", "Alpha"]
        let metas = [
            TaskListMeta(name: "乙", sortOrder: 0),
            TaskListMeta(name: "甲", sortOrder: 1),
            TaskListMeta(name: "丙", isPinned: true, sortOrder: 2),
        ]
        XCTAssertEqual(TaskListOrdering.ordered(names, metas: metas), ["丙", "乙", "甲", "Alpha"])
        // 无 meta 的名字排在有 meta 之后，按字典序。
        XCTAssertEqual(TaskListOrdering.ordered(["Beta", "Alpha"], metas: []), ["Alpha", "Beta"])
    }

    // MARK: - 色板

    func testPaletteHasStableFourteenColorsWithDeterministicFallback() {
        XCTAssertEqual(WFListPalette.argb.count, 14)
        XCTAssertEqual(Set(WFListPalette.argb).count, 14)
        XCTAssertEqual(WFListPalette.argb.first, 0xFFE35D6A)
        // 显式色优先；越界回退到按名推导；同名永远同色。
        XCTAssertEqual(WFListPalette.colorIndex(for: "工作", explicit: 5), 5)
        XCTAssertEqual(WFListPalette.colorIndex(for: "工作", explicit: 99),
                       WFListPalette.colorIndex(for: "工作", explicit: nil))
        let derived = WFListPalette.colorIndex(for: "工作", explicit: nil)
        XCTAssertTrue((0..<14).contains(derived))
        // 字符折叠的独立计算："A" 的 Unicode 标量 65 → 65 % 14 = 9。
        XCTAssertEqual(WFListPalette.colorIndex(for: "A", explicit: nil), 9)
        XCTAssertEqual(WFListPalette.colorIndex(for: "  ", explicit: nil), 0)
    }

    // MARK: - 范围多选（anchor → 投影顺序）

    func testRangeSelectionFollowsProjectionOrderFromAnchor() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, seedDemoData: false)
            let a = workspace.createTask(title: "甲", in: .inbox).taskID!
            let b = workspace.createTask(title: "乙", in: .inbox).taskID!
            let c = workspace.createTask(title: "丙", in: .inbox).taskID!
            let order = workspace.visibleNodes(for: .inbox).map(\.task.id)
            XCTAssertEqual(order, [a, b, c])
            // anchor → 目标（向后）。
            workspace.setBulkSelected(b, true)
            workspace.extendBulkSelection(to: c, in: order)
            XCTAssertEqual(workspace.bulkSelection, [b, c])
            // anchor → 目标（向前）。
            workspace.clearBulkSelection()
            workspace.toggleBulkSelection(b)
            workspace.extendBulkSelection(to: a, in: order)
            XCTAssertEqual(workspace.bulkSelection, [a, b])
            // 无 anchor：退化为只加目标（对齐 Flutter extendTo）。
            workspace.clearBulkSelection()
            workspace.extendBulkSelection(to: a, in: order)
            XCTAssertEqual(workspace.bulkSelection, [a])
        }
    }

    // MARK: - reorder 边界

    func testReorderBoundariesFirstLastAndChildren() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store, clock: { self.now })
        let a = actions.create(title: "A").taskID!
        let b = actions.create(title: "B").taskID!
        let c = actions.create(title: "C").taskID!
        let childA = actions.createChild(a).taskID!
        let childB = actions.createChild(b).taskID!

        // 自身：无操作。
        actions.reorder(a, before: a)
        XCTAssertEqual(store.tasks.map(\.id), [a, b, c, childA, childB])
        // 尾行拖到首行前。
        actions.reorder(c, before: a)
        XCTAssertEqual(store.tasks.filter { $0.parentID == nil }.map(\.id), [c, a, b])
        // 首行拖到末行前。
        actions.reorder(c, before: b)
        XCTAssertEqual(store.tasks.filter { $0.parentID == nil }.map(\.id), [a, c, b])
        // 父任务不可落到子任务前（不同父级拒绝）。
        actions.reorder(b, before: childA)
        XCTAssertEqual(store.tasks.filter { $0.parentID == nil }.map(\.id), [a, c, b])
        // 子任务间跨父拒绝。
        actions.reorder(childA, before: childB)
        XCTAssertEqual(store.children(of: a).map(\.id), [childA])
        XCTAssertEqual(store.children(of: b).map(\.id), [childB])
        // 目标不存在：无操作。
        actions.reorder(a, before: UUID())
        XCTAssertEqual(store.tasks.filter { $0.parentID == nil }.map(\.id), [a, c, b])
    }

    // MARK: - 顺延（一次撤销 + HUD 报告）

    func testPostponeOverdueIsOneUndoableGroup() async {
        await MainActor.run {
            let calendar = self.calendar
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, seedDemoData: false)
            let start = calendar.startOfDay(for: self.now)
            var yesterday = calendar.date(byAdding: .day, value: -1, to: start)!
            yesterday = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: yesterday)!
            let overdueTimed = workspace.createTask(title: "过期定时", in: .today).taskID!
            _ = workspace.setSchedule(overdueTimed, TaskSchedule(dueAt: yesterday, hasTime: true))
            let overdueAllDay = workspace.createTask(title: "过期全天", in: .today).taskID!
            _ = workspace.setSchedule(overdueAllDay, TaskSchedule(dueAt: yesterday))
            let before = workspace.task(for: overdueTimed)?.schedule.dueAt

            workspace.postponeOverdue([overdueTimed, overdueAllDay])

            let movedTimed = workspace.task(for: overdueTimed)!.schedule.dueAt!
            let movedAllDay = workspace.task(for: overdueAllDay)!.schedule.dueAt!
            // 逐任务保留时钟：定时任务带着 09:30 顺延，全天任务仍是全天。
            XCTAssertEqual(calendar.startOfDay(for: movedTimed), start)
            XCTAssertEqual(calendar.component(.hour, from: movedTimed), 9)
            XCTAssertTrue(workspace.task(for: overdueTimed)!.schedule.hasTime)
            XCTAssertEqual(movedAllDay, start)
            // 一次撤销整组生效。
            workspace.undo()
            XCTAssertEqual(workspace.task(for: overdueTimed)?.schedule.dueAt, before)
            XCTAssertEqual(workspace.task(for: overdueAllDay)?.schedule.dueAt, yesterday)
        }
    }

    // MARK: - 复制任务

    func testDuplicateCopiesTaskWithChildren() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, seedDemoData: false)
            let parent = workspace.createTask(title: "原始", in: .inbox).taskID!
            _ = workspace.createChild(parent, title: "子项")
            let before = workspace.allTasks.count
            workspace.duplicate(parent)
            let copies = workspace.allTasks.filter { $0.title == "原始" }
            XCTAssertEqual(copies.count, 2)
            XCTAssertEqual(workspace.allTasks.count, before + 2)
            XCTAssertNotEqual(copies.first?.id, copies.last?.id)
        }
    }
}
