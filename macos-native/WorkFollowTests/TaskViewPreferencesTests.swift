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

    private func makeTask(_ title: String, createdAt: Date, priority: TaskPriority = .none,
                          dueAt: Date? = nil, list: TaskList = .inbox,
                          tags: [String] = [], isPinned: Bool = false) -> Task {
        var task = Task(id: UUID(), title: title, list: list, priority: priority,
                        schedule: TaskSchedule(dueAt: dueAt), parentID: nil, childOrder: 0,
                        createdAt: createdAt, updatedAt: createdAt)
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

    func testAvailableGroupingOptionsMatrix() {
        XCTAssertEqual(TaskListGrouping.availableOptions(destination: .allTasks, activeList: nil, activeTag: nil),
                       [.byDate, .none, .byPriority, .byList, .byTag])
        XCTAssertEqual(TaskListGrouping.availableOptions(destination: .allTasks, activeList: "工作", activeTag: nil),
                       [.none, .byDate, .byPriority, .byTag],
                       "清单视图内按清单分组无意义，不出现")
        XCTAssertEqual(TaskListGrouping.availableOptions(destination: .allTasks, activeList: nil, activeTag: "验收"),
                       [.none, .byDate, .byPriority, .byList])
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
