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
        XCTAssertNil(meta.icon, "旧快照缺 icon 键 → nil（回落色点）")
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

    // MARK: - 清单文件夹（滴答层级：文件夹 → 清单）

    func testSidebarTreePutsFolderAtFirstMemberPosition() {
        let metas = [
            TaskListMeta(name: "工作", sortOrder: 0, folderName: "公司"),
            TaskListMeta(name: "生活", sortOrder: 1),
            TaskListMeta(name: "项目 A", sortOrder: 2, folderName: "公司"),
            TaskListMeta(name: "读书", sortOrder: 3),
        ]
        XCTAssertEqual(TaskListOrdering.sidebarTree(metas.map(\.name), metas: metas),
                       [.folder(name: "公司", lists: ["工作", "项目 A"]),
                        .list("生活"),
                        .list("读书")],
                       "文件夹出现在它第一个成员的位置，成员保持既有顺序")
    }

    func testSidebarTreeKeepsPinnedListsOutsideFolders() {
        let metas = [
            TaskListMeta(name: "收件", isPinned: true, sortOrder: 5, folderName: "公司"),
            TaskListMeta(name: "工作", sortOrder: 0, folderName: "公司"),
        ]
        XCTAssertEqual(TaskListOrdering.sidebarTree(metas.map(\.name), metas: metas),
                       [.list("收件"), .folder(name: "公司", lists: ["工作"])],
                       "置顶清单仍单独在前，不参与文件夹折叠")
    }

    func testListFolderActionsRenameAndDissolveKeepLists() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.renameList(nil, to: "工作")
        _ = actions.renameList(nil, to: "项目 A")
        XCTAssertTrue(actions.setListFolder("工作", "公司"))
        XCTAssertTrue(actions.setListFolder("项目 A", "公司"))
        XCTAssertEqual(store.listMeta(for: "项目 A")?.folderName, "公司")

        XCTAssertTrue(actions.renameListFolder(from: "公司", to: "公司 A"))
        XCTAssertEqual(store.listMeta(for: "工作")?.folderName, "公司 A")
        XCTAssertEqual(store.listMeta(for: "项目 A")?.folderName, "公司 A")

        XCTAssertTrue(actions.dissolveListFolder("公司 A"))
        XCTAssertNil(store.listMeta(for: "工作")?.folderName, "删除文件夹后清单回到顶层")
        XCTAssertTrue(store.lists.contains("工作"), "删文件夹不删清单")
        XCTAssertTrue(store.lists.contains("项目 A"))
        actions.undo()
        XCTAssertEqual(store.listMeta(for: "工作")?.folderName, "公司 A",
                       "解散是一步撤销（回到改名后的状态）")
    }

    func testListFolderRejectsInboxAndBlankClears() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.renameList(nil, to: "工作")
        XCTAssertFalse(actions.setListFolder(TaskList.inbox.name, "公司"), "收集箱不可归类")
        XCTAssertTrue(actions.setListFolder("工作", "公司"))
        XCTAssertTrue(actions.setListFolder("工作", "   "))
        XCTAssertNil(store.listMeta(for: "工作")?.folderName, "空白等于移出文件夹")
    }

    func testListFolderDecodesMissingKeyAsNil() throws {
        let json = #"{"name":"工作","sortOrder":0}"#
        let meta = try JSONDecoder().decode(TaskListMeta.self, from: Data(json.utf8))
        XCTAssertNil(meta.folderName, "旧快照缺 folderName 键 → 顶层")
    }

    func testListFolderPersistsThroughRepositoryRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wf-listfolder-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = NativePreviewRepository(directory: directory)
        let metas = [TaskListMeta(name: "工作", sortOrder: 0, folderName: "公司"),
                     TaskListMeta(name: "读书", sortOrder: 1)]
        try repository.save(NativeWorkspaceSnapshot(tasks: [], notes: [],
                                                    taskLists: ["工作", "读书"], taskListMeta: metas))
        let loaded = try XCTUnwrap(repository.load())
        XCTAssertEqual(loaded.taskListMeta, metas, "文件夹随快照往返")
        XCTAssertNil(loaded.taskListMeta?[1].folderName)
    }

    // MARK: - 清单拖动排序（侧栏行间拖放带）

    func testMoveListReordersAndIsOneUndoStep() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.renameList(nil, to: "A")
        _ = actions.renameList(nil, to: "B")
        _ = actions.renameList(nil, to: "C")
        XCTAssertEqual(store.lists, ["A", "B", "C"])

        XCTAssertTrue(actions.moveList("C", before: "A"))
        XCTAssertEqual(store.lists, ["C", "A", "B"], "移到目标之前")
        actions.undo()
        XCTAssertEqual(store.lists, ["A", "B", "C"], "排序是一步撤销")

        XCTAssertFalse(actions.moveList("A", before: "A"), "自己到自己不算改动")
        XCTAssertFalse(actions.moveList(TaskList.inbox.name, before: "B"), "收集箱不参与排序")
        XCTAssertFalse(actions.moveList("A", before: "不存在"), "目标不存在则拒绝")
    }

    func testMoveListToEndKeepsMetaAndFolder() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.renameList(nil, to: "A")
        _ = actions.renameList(nil, to: "B")
        XCTAssertTrue(actions.setListColor("A", 3))
        XCTAssertTrue(actions.setListFolder("A", "公司"))

        XCTAssertTrue(actions.moveList("A", before: nil))
        XCTAssertEqual(store.lists, ["B", "A"], "nil = 移到末尾")
        XCTAssertEqual(store.listMeta(for: "A")?.colorIndex, 3, "颜色随名字继承")
        XCTAssertEqual(store.listMeta(for: "A")?.folderName, "公司", "文件夹归属不受排序影响")
        XCTAssertEqual(TaskListOrdering.sidebarTree(store.lists, metas: store.listMetas,
                                                    folders: store.listFolders),
                       [.list("B"), .folder(name: "公司", lists: ["A"])],
                       "侧栏树按新顺序渲染")
    }

    // MARK: - 空文件夹 / 位置 / 拖拽建夹

    func testEmptyFolderKeepsItsOwnPosition() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.renameList(nil, to: "工作")
        XCTAssertTrue(actions.saveListFolder("公司"), "可以先建空文件夹（滴答「添加文件夹」路径）")
        XCTAssertFalse(actions.saveListFolder("公司"), "重名被拒")
        XCTAssertFalse(actions.saveListFolder("   "), "空名被拒")
        XCTAssertEqual(TaskListOrdering.sidebarTree(store.lists, metas: store.listMetas,
                                                    folders: store.listFolders),
                       [.list("工作"), .folder(name: "公司", lists: [])],
                       "空文件夹也出现在侧栏")
        XCTAssertTrue(actions.setListFolder("工作", "公司"))
        XCTAssertEqual(TaskListOrdering.sidebarTree(store.lists, metas: store.listMetas,
                                                    folders: store.listFolders),
                       [.folder(name: "公司", lists: ["工作"])],
                       "放清单后位置不变（文件夹位置由自己决定，不再靠成员派生）")
    }

    func testCombineListsIntoFolderIsOneUndoStep() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.renameList(nil, to: "工作")
        _ = actions.renameList(nil, to: "项目 A")
        XCTAssertTrue(actions.combineListsIntoFolder("工作", "项目 A", folder: "公司"))
        XCTAssertEqual(store.listMeta(for: "工作")?.folderName, "公司")
        XCTAssertEqual(store.listMeta(for: "项目 A")?.folderName, "公司")
        XCTAssertNotNil(store.listFolder(named: "公司"))
        actions.undo()
        XCTAssertNil(store.listMeta(for: "工作")?.folderName, "拖拽是一个动作：一步撤销")
        XCTAssertNil(store.listMeta(for: "项目 A")?.folderName)
        XCTAssertNil(store.listFolder(named: "公司"), "文件夹实体一起回滚")
    }

    func testCombineRejectsInboxAndSelf() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.renameList(nil, to: "工作")
        XCTAssertFalse(actions.combineListsIntoFolder(TaskList.inbox.name, "工作", folder: "公司"))
        XCTAssertFalse(actions.combineListsIntoFolder("工作", "工作", folder: "公司"))
        XCTAssertNil(store.listFolder(named: "公司"), "被拒时不留下空文件夹")
    }

    func testSidebarDragPayloadRoundTrip() {
        let id = UUID()
        XCTAssertEqual(SidebarDragPayload.decode(SidebarDragPayload.encode(.task(id))), .task(id))
        XCTAssertEqual(SidebarDragPayload.decode(SidebarDragPayload.encode(.list("工作 2"))),
                       .list("工作 2"))
        XCTAssertNil(SidebarDragPayload.decode("随便一段文字"))
        XCTAssertNil(SidebarDragPayload.decode(SidebarDragPayload.listPrefix), "空前缀不是有效清单名")
    }

    // MARK: - 清单图标（Emoji）

    func testListIconPersistsClearsAndRejectsInbox() {
        let store = WorkspaceStore(); let actions = TaskActions(store: store, clock: { self.now })
        _ = actions.renameList(nil, to: "读书")
        XCTAssertTrue(actions.setListIcon("读书", "📚"))
        XCTAssertEqual(store.listMeta(for: "读书")?.icon, "📚")
        XCTAssertTrue(actions.setListIcon("读书", "  "))
        XCTAssertNil(store.listMeta(for: "读书")?.icon, "空白等于清除图标")
        XCTAssertTrue(actions.setListIcon("读书", "🚀"))
        actions.undo()
        XCTAssertNil(store.listMeta(for: "读书")?.icon, "图标写入可撤销")
        XCTAssertFalse(actions.setListIcon(TaskList.inbox.name, "📥"), "收集箱不可设置图标")
        XCTAssertFalse(actions.setListIcon("", "📚"))
    }

    func testListIconPersistsThroughRepositoryRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wf-listmeta-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = NativePreviewRepository(directory: directory)
        let metas = [TaskListMeta(name: "读书", colorIndex: 4, sortOrder: 0, icon: "📚"),
                     TaskListMeta(name: "工作", sortOrder: 1)]
        try repository.save(NativeWorkspaceSnapshot(tasks: [], notes: [],
                                                    taskLists: ["读书", "工作"], taskListMeta: metas))
        let loaded = try XCTUnwrap(repository.load())
        XCTAssertEqual(loaded.taskListMeta, metas, "图标随快照往返")
        XCTAssertNil(loaded.taskListMeta?[1].icon, "没设图标的清单仍是 nil")
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
