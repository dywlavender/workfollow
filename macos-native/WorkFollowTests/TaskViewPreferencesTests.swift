import XCTest
@testable import WorkFollow

/// 阶段0/1：排序维度、分组策略与视图偏好持久化的纯逻辑测试。
/// 规则本体在 TaskListProjection（分组/比较器）与 TaskViewPreferenceStore（存取）。
@MainActor
final class TaskViewPreferencesTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 10))!
    }

    private func makeTask(_ title: String, createdAt: Date, updatedAt: Date? = nil,
                          priority: TaskPriority = .none,
                          dueAt: Date? = nil, list: TaskList = .inbox,
                          tags: [String] = [], isPinned: Bool = false) -> Task {
        var task = Task(id: UUID(), title: title, list: list, priority: priority,
                        schedule: TaskSchedule(dueAt: dueAt), parentID: nil, childOrder: 0,
                        createdAt: createdAt, updatedAt: updatedAt ?? createdAt)
        task.tags = tags
        task.isPinned = isPinned
        return task
    }

    private func group(_ tasks: [Task], kind: TaskGroupKind = .plain,
                       label: String? = nil) -> TaskListGroup {
        TaskListGroup(kind: kind, day: nil, tasks: tasks, label: label)
    }

    // MARK: - 排序比较器

    func testTitleSortIsCaseInsensitiveWithStableFallback() {
        let base = now
        let tasks = [
            makeTask("banana", createdAt: base),
            makeTask("Apple", createdAt: base),
            makeTask("apple pie", createdAt: base),
            makeTask("Banana", createdAt: base),
        ]
        XCTAssertEqual(group(tasks).orderedTasks(using: .title, calendar: calendar).map(\.title),
                       ["Apple", "apple pie", "banana", "Banana"],
                       "同名字段内按原始顺序稳定收尾")
    }

    func testCreatedAtSortIsOldestFirst() {
        let tasks = [
            makeTask("newest", createdAt: now.addingTimeInterval(200)),
            makeTask("oldest", createdAt: now),
            makeTask("middle", createdAt: now.addingTimeInterval(100)),
        ]
        XCTAssertEqual(group(tasks).orderedTasks(using: .createdAt, calendar: calendar).map(\.title),
                       ["oldest", "middle", "newest"])
    }

    func testPrioritySortStillFallsBackToDueThenManualOrder() {
        let start = calendar.startOfDay(for: now)
        let tasks = [
            makeTask("low morning", createdAt: now, priority: .low,
                     dueAt: start.addingTimeInterval(8 * 3600)),
            makeTask("high noon", createdAt: now, priority: .high,
                     dueAt: start.addingTimeInterval(12 * 3600)),
            makeTask("high morning", createdAt: now, priority: .high,
                     dueAt: start.addingTimeInterval(9 * 3600)),
        ]
        XCTAssertEqual(group(tasks).orderedTasks(using: .priority, calendar: calendar).map(\.title),
                       ["high morning", "high noon", "low morning"],
                       "新枚举值加入后，priority→日期→原始顺序的历史语义不变")
    }

    func testCompletedGroupIsNeverResorted() {
        let tasks = [
            makeTask("b", createdAt: now),
            makeTask("a", createdAt: now),
        ]
        XCTAssertEqual(group(tasks, kind: .completed).orderedTasks(using: .title, calendar: calendar).map(\.title),
                       ["b", "a"])
    }

    // MARK: - 分组策略

    private func makeFixture() -> (WorkspaceStore, TaskActions) {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.now }, calendar: calendar)
        return (store, actions)
    }

    func testModifiedSortOrdersByUpdatedAtBothWays() {
        let base = now
        let early = makeTask("a", createdAt: base, updatedAt: base)
        let late = makeTask("b", createdAt: base, updatedAt: base.addingTimeInterval(3_600))
        let group = group([late, early])
        XCTAssertEqual(group.orderedTasks(using: .modified, calendar: calendar).map(\.id),
                       [early.id, late.id])
        XCTAssertEqual(group.orderedTasks(using: .modified, descending: true, calendar: calendar).map(\.id),
                       [late.id, early.id])
    }

    func testPrioritySortDefaultIsHighFirstAndDescendingFlips() {
        let base = now
        let high = makeTask("h", createdAt: base, priority: .high)
        let low = makeTask("l", createdAt: base, priority: .low)
        let group = group([low, high])
        XCTAssertEqual(group.orderedTasks(using: .priority, calendar: calendar).map(\.id),
                       [high.id, low.id], "默认高优先在前（历史行为，不是字面升序）")
        XCTAssertEqual(group.orderedTasks(using: .priority, descending: true, calendar: calendar).map(\.id),
                       [low.id, high.id], "降序整体翻转")
    }

    func testDescendingKeepsUndatedLastAndManualIgnoresDirection() {
        let base = now
        let day1 = makeTask("d1", createdAt: base, dueAt: base.addingTimeInterval(86_400))
        let day3 = makeTask("d3", createdAt: base, dueAt: base.addingTimeInterval(86_400 * 3))
        let undated = makeTask("u", createdAt: base)
        let group = group([day1, day3, undated])
        XCTAssertEqual(group.orderedTasks(using: .due, descending: true, calendar: calendar).map(\.id),
                       [day3.id, day1.id, undated.id], "降序时无日期仍垫底")
        XCTAssertEqual(group.orderedTasks(using: .manual, descending: true, calendar: calendar).map(\.id),
                       [day1.id, day3.id, undated.id], "手动排序不受方向影响")
    }

    func testCreatedAtGroupingBucketsNewestDayFirst() throws {
        let (store, _) = makeFixture()
        let recent = makeTask("今天建的", createdAt: now)
        let older = makeTask("三天前建的", createdAt: calendar.date(byAdding: .day, value: -3, to: now)!)
        store.commit([older, recent], undoPolicy: .skip, lists: [TaskList.inbox.name])

        let groups = TaskListProjection.groups(in: .allTasks, store: store, now: now,
                                               calendar: calendar, grouping: .byCreatedAt)
        XCTAssertEqual(groups.filter { $0.kind != .pinned }.flatMap(\.tasks).map(\.id),
                       [recent.id, older.id], "按创建日倒序：今天在前，三天前在后")
    }

    func testResetSortClearsModeAndDirectionButKeepsGrouping() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskViewPreferencesTests-\(UUID().uuidString)", isDirectory: true)
        let store = TaskViewPreferenceStore(directory: directory)
        store.setSortMode(.due, for: "scope:allTasks")
        store.setSortDescending(true, for: "scope:allTasks")
        store.setGrouping(.byPriority, for: "scope:allTasks")

        store.resetSort(for: "scope:allTasks")

        XCTAssertEqual(store.sortMode(for: "scope:allTasks"), .manual, "恢复默认 = 手动排序")
        XCTAssertFalse(store.sortDescending(for: "scope:allTasks"))
        XCTAssertEqual(store.grouping(for: "scope:allTasks", allTasksRoot: true), .byPriority,
                       "分组不受影响")
    }

    func testSortDescendingDefaultsToFalseForOldArchives() throws {
        let json = #"{"preferences":{"scope:allTasks":{"sortMode":"due"}}}"#
        let archive = try JSONDecoder().decode(TaskViewPreferenceStore.Archive.self,
                                               from: Data(json.utf8))
        XCTAssertNil(archive.preferences["scope:allTasks"]?.sortDescending)
        XCTAssertEqual(archive.preferences["scope:allTasks"]?.sortMode, .due, "旧档案其余字段照旧")
    }

    func testPriorityGroupingBucketsInFixedOrderWithoutEmptyBuckets() throws {
        let (store, actions) = makeFixture()
        let high = try XCTUnwrap(actions.create(title: "h", priority: .high).taskID)
        let low = try XCTUnwrap(actions.create(title: "l", priority: .low).taskID)
        let plain = try XCTUnwrap(actions.create(title: "p").taskID)
        _ = actions.setPriority(plain, .none)

        let groups = TaskListProjection.groups(in: .allTasks, store: store, now: now,
                                               calendar: calendar, grouping: .byPriority)
        XCTAssertEqual(groups.filter { $0.kind != .pinned }.map(\.label),
                       ["高优先级", "低优先级", "无优先级"],
                       "没有中优先级任务，中优先级空桶不出现")
        XCTAssertEqual(groups.filter { $0.kind != .pinned }.flatMap(\.tasks).map(\.id),
                       [high, low, plain])
    }

    func testListGroupingFollowsSavedOrderWithInboxFirst() throws {
        let (store, actions) = makeFixture()
        let inbox = try XCTUnwrap(actions.create(title: "inbox").taskID)
        let work = try XCTUnwrap(actions.create(title: "work", list: TaskList(name: "工作")).taskID)
        let study = try XCTUnwrap(actions.create(title: "study", list: TaskList(name: "学习")).taskID)
        let extra = try XCTUnwrap(actions.create(title: "extra", list: TaskList(name: "临时")).taskID)
        // store.lists 保存顺序是"学习"在前（用户手动排的），分组必须尊重它。
        store.commit(store.tasks, undoPolicy: .skip, lists: ["学习", "工作"])

        let groups = TaskListProjection.groups(in: .allTasks, store: store, now: now,
                                               calendar: calendar, grouping: .byList)
        XCTAssertEqual(groups.filter { $0.kind != .pinned }.map(\.label),
                       ["收集箱", "学习", "工作", "临时"])
        XCTAssertEqual(groups.filter { $0.kind != .pinned }.flatMap(\.tasks).map(\.id),
                       [inbox, study, work, extra])
    }

    func testTagGroupingUsesFirstTagOnlyAndUntaggedLast() throws {
        let (store, actions) = makeFixture()
        let both = try XCTUnwrap(actions.create(title: "both").taskID)
        _ = actions.setTags(both, ["验收", "日期"])
        let dated = try XCTUnwrap(actions.create(title: "dated").taskID)
        _ = actions.setTags(dated, ["日期"])
        let untagged = try XCTUnwrap(actions.create(title: "none").taskID)

        let groups = TaskListProjection.groups(in: .allTasks, store: store, now: now,
                                               calendar: calendar, grouping: .byTag)
        // "both" 只出现在"验收"组：列表以 task.id 为身份，跨组重复会撞 ForEach ID。
        // 组顺序按标签名字典序，"日"(U+65E5) < "验"(U+9A8C)。
        XCTAssertEqual(groups.filter { $0.kind != .pinned }.map(\.label),
                       ["日期", "验收", "无标签"])
        XCTAssertEqual(groups.first { $0.label == "验收" }?.tasks.map(\.id), [both])
        XCTAssertEqual(groups.first { $0.label == "日期" }?.tasks.map(\.id), [dated])
        XCTAssertEqual(groups.first { $0.label == "无标签" }?.tasks.map(\.id), [untagged])
    }

    func testNoneGroupingFlattensAllTasksRoot() throws {
        let (store, actions) = makeFixture()
        _ = try XCTUnwrap(actions.create(title: "past",
                                         schedule: TaskSchedule(dueAt: calendar.date(byAdding: .day, value: -3, to: now))).taskID)
        _ = try XCTUnwrap(actions.create(title: "today",
                                         schedule: TaskSchedule(dueAt: now)).taskID)

        let groups = TaskListProjection.groups(in: .allTasks, store: store, now: now,
                                               calendar: calendar, grouping: .none)
        XCTAssertEqual(groups.filter { $0.kind != .pinned }.count, 1)
        XCTAssertEqual(groups.filter { $0.kind != .pinned }.first?.label, nil)
        XCTAssertEqual(groups.filter { $0.kind != .pinned }.first?.tasks.count, 2)
    }

    func testDateGroupingKeepsHistoricalBucketsForAllTasksRoot() throws {
        let (store, actions) = makeFixture()
        _ = try XCTUnwrap(actions.create(title: "past",
                                         schedule: TaskSchedule(dueAt: calendar.date(byAdding: .day, value: -3, to: now))).taskID)
        _ = try XCTUnwrap(actions.create(title: "today",
                                         schedule: TaskSchedule(dueAt: now)).taskID)
        _ = try XCTUnwrap(actions.create(title: "far",
                                         schedule: TaskSchedule(dueAt: calendar.date(byAdding: .day, value: 20, to: now))).taskID)

        let groups = TaskListProjection.groups(in: .allTasks, store: store, now: now,
                                               calendar: calendar, grouping: .byDate)
        XCTAssertEqual(groups.filter { $0.kind != .pinned }.map(\.kind),
                       [.overdue, .today, .later])
    }

    func testGroupingIsIgnoredForTimeBasedScopes() throws {
        let (store, actions) = makeFixture()
        let overdue = try XCTUnwrap(actions.create(
            title: "overdue", schedule: TaskSchedule(dueAt: calendar.date(byAdding: .day, value: -2, to: now)),
            priority: .low).taskID)
        let onToday = try XCTUnwrap(actions.create(
            title: "today", schedule: TaskSchedule(dueAt: now), priority: .high).taskID)

        let groups = TaskListProjection.groups(in: .today, store: store, now: now,
                                               calendar: calendar, grouping: .byPriority)
        XCTAssertEqual(groups.map(\.kind), [.overdue, .today],
                       "今天视图的日期分组是视图本体，分组偏好不得改写")
        XCTAssertEqual(groups.last?.tasks.map(\.id), [onToday])
        XCTAssertEqual(groups.first?.tasks.map(\.id), [overdue])
    }

    func testLabeledPlainGroupsHaveDistinctFoldIdentity() {
        let work = makeTask("w", createdAt: now, list: TaskList(name: "工作"))
        let study = makeTask("s", createdAt: now, list: TaskList(name: "学习"))
        XCTAssertEqual(group([work], label: "工作").id, "plain:工作")
        XCTAssertEqual(group([study], label: "学习").id, "plain:学习")
        XCTAssertNotEqual(group([work], label: "工作").id, group([study], label: "学习").id)
        XCTAssertEqual(group([work]).id, "plain", "无标签平铺组保持历史身份")
    }

    // MARK: - 分组菜单可用性矩阵

    // MARK: - 智能清单显示状态（显示 / 隐藏 / 有内容时显示）

    func testVisibilityShowsMatrix() {
        XCTAssertTrue(SmartListVisibility.visible.shows(hasContent: false))
        XCTAssertFalse(SmartListVisibility.hidden.shows(hasContent: true))
        XCTAssertTrue(SmartListVisibility.automatic.shows(hasContent: true))
        XCTAssertFalse(SmartListVisibility.automatic.shows(hasContent: false),
                       "有内容时显示 = 没内容就不出现")
    }

    func testVisibilityDefaultsToVisibleAndInboxIsNotConfigurable() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskViewPreferencesTests-\(UUID().uuidString)", isDirectory: true)
        let store = TaskViewPreferenceStore(directory: directory)
        XCTAssertEqual(store.visibility(for: .today), .visible, "未设过 = 显示")

        store.setVisibility(.automatic, for: .today)
        XCTAssertEqual(store.visibility(for: .today), .automatic)
        store.setVisibility(.visible, for: .today)
        XCTAssertEqual(store.visibility(for: .today), .visible, "回到显示会删键")
        XCTAssertTrue(store.smartListVisibility.isEmpty)

        store.setVisibility(.hidden, for: .inbox)
        XCTAssertEqual(store.visibility(for: .inbox), .visible, "收集箱不可隐藏（滴答规则）")
        XCTAssertFalse(SmartListVisibility.isConfigurable(.inbox))
        XCTAssertTrue(SmartListVisibility.isConfigurable(.tomorrow))
    }

    func testVisibilityArchiveIsAdditiveAndRoundTrips() throws {
        let old = #"{"preferences":{"scope:allTasks":{"sortMode":"due"}}}"#
        let decoded = try JSONDecoder().decode(TaskViewPreferenceStore.Archive.self,
                                               from: Data(old.utf8))
        XCTAssertTrue(decoded.smartListVisibility.isEmpty, "旧档案缺键 → 空字典（= 全部显示）")
        XCTAssertEqual(decoded.preferences["scope:allTasks"]?.sortMode, .due, "其余字段照旧")

        let archive = TaskViewPreferenceStore.Archive(smartListVisibility: ["today": .automatic])
        let data = try JSONEncoder().encode(archive)
        let roundTrip = try JSONDecoder().decode(TaskViewPreferenceStore.Archive.self, from: data)
        XCTAssertEqual(roundTrip.smartListVisibility["today"], .automatic)
    }

    // MARK: - 显示设置（隐藏已完成 / 隐藏详细 / 详细行字段开关）

    func testDisplayTogglesDefaultOffAndPruneBackToDefault() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskViewPreferencesTests-\(UUID().uuidString)", isDirectory: true)
        let store = TaskViewPreferenceStore(directory: directory)
        let key = "list:工作"
        XCTAssertFalse(store.hidesCompleted(for: key), "未设过 = 显示已完成")
        XCTAssertFalse(store.hidesDetails(for: key), "未设过 = 显示详细")
        XCTAssertTrue(store.hiddenDetailFields(for: key).isEmpty)

        store.setHidesCompleted(true, for: key)
        store.setHidesDetails(true, for: key)
        store.setDetailField(.date, hidden: true, for: key)
        store.setDetailField(.tags, hidden: true, for: key)
        XCTAssertTrue(store.hidesCompleted(for: key))
        XCTAssertTrue(store.hidesDetails(for: key))
        XCTAssertEqual(store.hiddenDetailFields(for: key).sorted { $0.rawValue < $1.rawValue },
                       [.date, .tags])

        store.setDetailField(.date, hidden: true, for: key)
        XCTAssertEqual(store.hiddenDetailFields(for: key).count, 2, "重复勾选不叠加")

        store.setHidesCompleted(false, for: key)
        store.setHidesDetails(false, for: key)
        store.setDetailField(.date, hidden: false, for: key)
        store.setDetailField(.tags, hidden: false, for: key)
        XCTAssertNil(store.preferences[key], "全部回默认 → 档案清掉，不留垃圾")
    }

    func testDisplayTogglesArchiveIsAdditiveAndRoundTrips() throws {
        let key = "scope:allTasks"
        let archive = TaskViewPreferenceStore.Archive(
            preferences: [key: TaskViewPreference(hidesCompleted: true, hidesDetails: true,
                                                  hiddenFields: [.priority])])
        let data = try JSONEncoder().encode(archive)
        let roundTrip = try JSONDecoder().decode(TaskViewPreferenceStore.Archive.self, from: data)
        let entry = try XCTUnwrap(roundTrip.preferences[key])
        XCTAssertTrue(entry.hidesCompleted ?? false, "隐藏已完成随档案往返")
        XCTAssertTrue(entry.hidesDetails ?? false)
        XCTAssertEqual(entry.hiddenFields, [.priority], "字段开关随档案往返")

        let old = #"{"preferences":{"scope:allTasks":{"sortMode":"due"}}}"#
        let decoded = try JSONDecoder().decode(TaskViewPreferenceStore.Archive.self,
                                               from: Data(old.utf8))
        let oldEntry = try XCTUnwrap(decoded.preferences["scope:allTasks"])
        XCTAssertNil(oldEntry.hidesCompleted, "旧档案缺键 → 显示已完成")
        XCTAssertNil(oldEntry.hiddenFields, "旧档案缺键 → 字段全显示")
    }

    func testHidesCompletedDropsClosedGroupButCompletedScopeKeepsIt() throws {
        let (store, actions) = makeFixture()
        let open = try XCTUnwrap(actions.create(title: "进行中").taskID)
        let done = try XCTUnwrap(actions.create(title: "已完成").taskID)
        _ = actions.complete(done)

        let shown = TaskListProjection.groups(in: .allTasks, store: store, now: now,
                                              calendar: calendar)
        XCTAssertEqual(shown.last?.kind, .completed, "默认显示已完成组")
        let hidden = TaskListProjection.groups(in: .allTasks, store: store, now: now,
                                               calendar: calendar, hidesCompleted: true)
        XCTAssertFalse(hidden.contains { $0.kind == .completed }, "隐藏已完成")
        XCTAssertTrue(hidden.flatMap(\.tasks).contains { $0.id == open }, "未完成任务不受影响")

        let completedScope = TaskListProjection.groups(in: .completed, store: store, now: now,
                                                       calendar: calendar, hidesCompleted: true)
        XCTAssertTrue(completedScope.flatMap(\.tasks).contains { $0.id == done },
                      "已完成视图是视图本体，不受「隐藏已完成」影响")
    }

    // MARK: - 视图形态（列表 / 看板）

    func testViewModeDefaultsToListAndPrunesWhenReset() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskViewPreferencesTests-\(UUID().uuidString)", isDirectory: true)
        let store = TaskViewPreferenceStore(directory: directory)
        let key = "list:工作"
        XCTAssertEqual(store.viewMode(for: key), .list, "未设过 = 列表（滴答默认）")
        store.setViewMode(.kanban, for: key)
        XCTAssertEqual(store.viewMode(for: key), .kanban)
        store.setViewMode(.list, for: key)
        XCTAssertEqual(store.viewMode(for: key), .list)
        XCTAssertNil(store.preferences[key], "回到列表 = 删键，不留垃圾")
    }

    func testViewModeArchiveIsAdditive() throws {
        let archive = TaskViewPreferenceStore.Archive(
            preferences: ["list:工作": TaskViewPreference(viewMode: .kanban)])
        let data = try JSONEncoder().encode(archive)
        let roundTrip = try JSONDecoder().decode(TaskViewPreferenceStore.Archive.self, from: data)
        XCTAssertEqual(roundTrip.preferences["list:工作"]?.viewMode, .kanban, "视图形态随档案往返")

        let old = #"{"preferences":{"scope:allTasks":{"sortMode":"due"}}}"#
        let decoded = try JSONDecoder().decode(TaskViewPreferenceStore.Archive.self,
                                               from: Data(old.utf8))
        XCTAssertNil(decoded.preferences["scope:allTasks"]?.viewMode, "旧档案缺键 → 列表")
    }

    func testGroupTitleIsSingleSourceForListAndKanban() {
        XCTAssertEqual(TaskGroupDisplay.title(group([], kind: .pinned), now: now), "置顶")
        XCTAssertEqual(TaskGroupDisplay.title(group([], kind: .overdue), now: now), "已过期")
        XCTAssertEqual(TaskGroupDisplay.title(group([], kind: .upcoming), now: now), "最近 7 天")
        XCTAssertEqual(TaskGroupDisplay.title(group([], kind: .later), now: now), "更远")
        XCTAssertEqual(TaskGroupDisplay.title(group([], kind: .undated), now: now), "无日期")
        XCTAssertEqual(TaskGroupDisplay.title(group([], kind: .plain, label: "进行中"), now: now),
                       "进行中", "自定义分组 = plain 组标签（看板列头与列表组头同一份）")
        XCTAssertEqual(TaskGroupDisplay.title(group([], kind: .completed, label: "已完成"), now: now),
                       "已完成")
        XCTAssertTrue(TaskGroupDisplay.title(group([], kind: .today), now: now).hasPrefix("今天,"),
                      "今天组带星期上下文")
    }

    func testTomorrowDestinationMapsToTomorrowScope() {
        XCTAssertEqual(TaskWorkspaceModel.scope(for: .tomorrow), .tomorrow)
        XCTAssertEqual(NativeDestination.tomorrow.title, "明天")
        XCTAssertTrue(NativeDestination.taskDestinations.contains(.tomorrow))
        XCTAssertNil(TaskWorkspaceModel.scope(for: .calendar), "非任务视图不映射 scope")
    }

    func testAvailableGroupingOptionsMatrix() {
        XCTAssertEqual(TaskListGrouping.availableOptions(destination: .allTasks, activeList: nil, activeTag: nil),
                       [.byDate, .none, .byPriority, .byList, .byTag, .byCreatedAt])
        XCTAssertEqual(TaskListGrouping.availableOptions(destination: .allTasks, activeList: "工作", activeTag: nil),
                       [.none, .byDate, .byPriority, .byTag, .byCreatedAt],
                       "清单视图内按清单分组无意义，不出现")
        XCTAssertEqual(TaskListGrouping.availableOptions(destination: .allTasks, activeList: nil, activeTag: "验收"),
                       [.none, .byDate, .byPriority, .byList, .byCreatedAt])
        XCTAssertTrue(TaskListGrouping.availableOptions(destination: .today, activeList: nil, activeTag: nil).isEmpty,
                      "时间型视图不提供分组菜单")
        XCTAssertTrue(TaskListGrouping.availableOptions(destination: .inbox, activeList: nil, activeTag: nil).isEmpty)
    }

    // MARK: - 偏好存取与持久化

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wf-viewprefs-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testScopeKeyPrefersListThenTagThenDestination() {
        XCTAssertEqual(TaskViewScopeKey.key(destination: .allTasks, activeList: "工作", activeTag: nil),
                       "list:工作")
        XCTAssertEqual(TaskViewScopeKey.key(destination: .allTasks, activeList: nil, activeTag: "验收"),
                       "tag:验收")
        XCTAssertEqual(TaskViewScopeKey.key(destination: .today, activeList: nil, activeTag: nil),
                       "scope:today")
    }

    func testPreferenceStoreFallsBackToDefaultsWhenKeyMissing() {
        let store = TaskViewPreferenceStore(directory: temporaryDirectory())
        let key = TaskViewScopeKey.key(destination: .today, activeList: nil, activeTag: nil)
        XCTAssertEqual(store.sortMode(for: key), .manual)
        XCTAssertEqual(store.grouping(for: key, allTasksRoot: true), .byDate,
                       "智能根视图缺省保持历史日期分组")
        XCTAssertEqual(store.grouping(for: key, allTasksRoot: false), .none,
                       "清单/标签视图缺省保持平铺")
    }

    func testPreferenceStoreWritesAreIsolatedPerKeyAndPersistAcrossInstances() async throws {
        let directory = temporaryDirectory()
        let keyToday = TaskViewScopeKey.key(destination: .today, activeList: nil, activeTag: nil)
        let keyList = TaskViewScopeKey.key(destination: .allTasks, activeList: "工作", activeTag: nil)

        let store = TaskViewPreferenceStore(directory: directory)
        store.setSortMode(.priority, for: keyToday)
        store.setGrouping(.byPriority, for: keyToday)
        store.setSortMode(.title, for: keyList)

        XCTAssertEqual(store.sortMode(for: keyToday), .priority)
        XCTAssertEqual(store.sortMode(for: keyList), .title, "两个视图的偏好互不串")

        // 防抖写盘：flush 后重新实例化，值必须从文件里回来。
        let reloaded = try await awaitFlush(store, directory: directory)
        XCTAssertEqual(reloaded.sortMode(for: keyToday), .priority)
        XCTAssertEqual(reloaded.grouping(for: keyToday, allTasksRoot: true), .byPriority)
        XCTAssertEqual(reloaded.sortMode(for: keyList), .title)
        XCTAssertEqual(reloaded.sortMode(for: TaskViewScopeKey.key(destination: .inbox, activeList: nil, activeTag: nil)),
                       .manual, "没写过的键回落默认")
    }

    /// flush 是异步队列语义：轮询重载直到读到写入值或超时。
    private func awaitFlush(_ store: TaskViewPreferenceStore,
                            directory: URL) async throws -> TaskViewPreferenceStore {
        let expectation = expectation(description: "preferences flushed")
        store.flush { _ in expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 5)
        return TaskViewPreferenceStore(directory: directory)
    }

    func testPreferenceArchiveDecodesMissingKeysAsNil() throws {
        let data = Data(#"{"preferences":{"scope:today":{"sortMode":"due"}}}"#.utf8)
        let archive = try JSONDecoder().decode(TaskViewPreferenceStore.Archive.self, from: data)
        let preference = try XCTUnwrap(archive.preferences["scope:today"])
        XCTAssertEqual(preference.sortMode, .due)
        XCTAssertEqual(preference.grouping, nil, "旧档案缺 grouping 键必须解码为 nil")
    }
}
