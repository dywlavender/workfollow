import XCTest
@testable import WorkFollow

@MainActor
final class TaskActivityStoreTests: XCTestCase {
    func testRecordsCreationAndImportantFieldChanges() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = TaskActivityStore(clock: { now }, directory: temporaryDirectory())
        let original = makeTask(title: "原任务", tags: ["甲", "乙"])
        store.recordChanges(from: [], to: [original])

        var changed = original
        changed.title = "新标题"
        changed.schedule = TaskSchedule(
            dueAt: now, hasTime: true,
            dueEndAt: now.addingTimeInterval(3_600),
            deadlineAt: now.addingTimeInterval(7_200))
        changed.recurrence = .weekly
        changed.recurrenceRule = RecurrenceRule(interval: 2, endDate: now.addingTimeInterval(86_400),
                                                remainingCount: 4, weekday: 3)
        changed.reminderAt = now.addingTimeInterval(-600)
        changed.reminderOffsets = [-30, 0]
        changed.list = TaskList(name: "工作")
        changed.priority = .high
        changed.tags = ["乙", "丙"]
        now = now.addingTimeInterval(10)
        store.recordChanges(from: [original], to: [changed])

        let recorded = store.events(for: original.id).reversed()
        XCTAssertEqual(recorded.map(\.kind), [
            .created, .titleChanged, .dateChanged, .listChanged, .priorityChanged, .tagsChanged
        ])
        XCTAssertEqual(recorded.first?.afterValue, "原任务")
        let dateEvent = try! XCTUnwrap(recorded.first { $0.kind == .dateChanged })
        XCTAssertTrue(dateEvent.afterValue?.contains("每周") == true)
        XCTAssertTrue(dateEvent.afterValue?.contains("提醒偏移 -30, 0 分钟") == true)
        XCTAssertEqual(recorded.first { $0.kind == .listChanged }?.afterValue, "工作")
        XCTAssertEqual(recorded.first { $0.kind == .priorityChanged }?.afterValue, "高")
        XCTAssertEqual(recorded.first { $0.kind == .tagsChanged }?.afterValue, "丙, 乙")
    }

    func testNoOpBodyOnlyAndTagReorderingDoNotRecordActivity() {
        let store = TaskActivityStore(directory: temporaryDirectory())
        let original = makeTask(title: "正文不入历史", tags: ["甲", "乙"])
        var edited = original
        edited.document = NativeDocument(plainText: "新增正文")
        edited.updatedAt = edited.updatedAt.addingTimeInterval(60)
        edited.tags = ["乙", "甲"]

        store.recordChanges(from: [original], to: [edited])
        XCTAssertTrue(store.events.isEmpty)
    }

    func testNewChildCreatesChildAndParentEvents() {
        let store = TaskActivityStore(directory: temporaryDirectory())
        let parent = makeTask(title: "父任务")
        let child = makeTask(title: "子任务", parentID: parent.id)

        store.recordChanges(from: [parent], to: [parent, child])

        XCTAssertEqual(store.events(for: child.id).map(\.kind), [.created])
        XCTAssertEqual(store.events(for: child.id).first?.detail, "子任务")
        XCTAssertEqual(store.events(for: parent.id).map(\.kind), [.childCreated])
        XCTAssertEqual(store.events(for: parent.id).first?.detail, "子任务")
    }

    func testEventsAreNewestFirstIncludingEqualTimestamps() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = TaskActivityStore(clock: { now }, directory: temporaryDirectory())
        let task = makeTask(title: "任务")
        store.recordChanges(from: [], to: [task])

        now = now.addingTimeInterval(10)
        store.recordFocusStart(taskID: task.id, stopwatch: false)
        store.recordFocusStart(taskID: task.id, stopwatch: true)
        now = now.addingTimeInterval(10)
        store.recordChanges(from: [task], to: [makeTask(id: task.id, title: "修改后")])

        XCTAssertEqual(store.events(for: task.id).map(\.kind), [
            .titleChanged, .focusStarted, .focusStarted, .created
        ])
        XCTAssertEqual(store.events(for: task.id).map(\.afterValue), ["修改后", "正计时", "番茄计时", "任务"])
    }

    func testTitleChangesMergeAndReturningToOriginalRemovesMergedEvent() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = TaskActivityStore(clock: { now }, directory: temporaryDirectory())
        let original = makeTask(title: "初始")
        store.recordChanges(from: [], to: [original])

        var updated = original
        updated.title = "中间"
        now = now.addingTimeInterval(1)
        store.recordChanges(from: [original], to: [updated])
        let mergedID = store.events.last?.id

        let intermediate = updated
        updated.title = "最终"
        now = now.addingTimeInterval(1)
        store.recordChanges(from: [intermediate], to: [updated])
        XCTAssertEqual(store.events(for: original.id).first?.beforeValue, "初始")
        XCTAssertEqual(store.events(for: original.id).first?.afterValue, "最终")
        XCTAssertEqual(store.events.last?.id, mergedID)

        let beforeRevert = updated
        updated.title = "初始"
        now = now.addingTimeInterval(1)
        store.recordChanges(from: [beforeRevert], to: [updated])
        XCTAssertEqual(store.events(for: original.id).map(\.kind), [.created])
    }

    func testLifecycleChangesRecordOneCorrectStatusEvent() {
        let store = TaskActivityStore(directory: temporaryDirectory())
        let active = makeTask(title: "状态")
        var completed = active
        completed.status = .completed
        completed.completedAt = Date(timeIntervalSince1970: 1_800_000_001)
        completed.abandonedAt = Date(timeIntervalSince1970: 1_800_000_002)
        store.recordChanges(from: [active], to: [completed])
        XCTAssertEqual(store.events(for: active.id).map(\.kind), [.completed])

        var restored = completed
        restored.status = .active
        restored.completedAt = nil
        restored.abandonedAt = nil
        store.recordChanges(from: [completed], to: [restored])
        XCTAssertEqual(store.events(for: active.id).filter { $0.kind == .restored }.count, 1)

        var abandoned = restored
        abandoned.abandonedAt = Date(timeIntervalSince1970: 1_800_000_003)
        store.recordChanges(from: [restored], to: [abandoned])
        XCTAssertEqual(store.events(for: active.id).filter { $0.kind == .abandoned }.count, 1)
    }

    func testFocusStartRecordsBothTimerModes() {
        let store = TaskActivityStore(directory: temporaryDirectory())
        let id = UUID()

        store.recordFocusStart(taskID: id, stopwatch: false)
        store.recordFocusStart(taskID: id, stopwatch: true)

        let events = store.events(for: id)
        XCTAssertEqual(events.map(\.kind), [.focusStarted, .focusStarted])
        XCTAssertEqual(events.map(\.detail), ["正计时", "番茄计时"])
    }

    func testFlushAndReloadUseTaskActivityFile() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        let store = TaskActivityStore(clock: { instant }, directory: directory)
        let taskID = UUID()
        store.recordFocusStart(taskID: taskID, stopwatch: true)

        let done = expectation(description: "flush task activity")
        store.flush { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("task-activity.sqlite").path))
        let reloaded = TaskActivityStore(clock: { instant }, directory: directory)
        XCTAssertEqual(reloaded.events(for: taskID).map(\.detail), ["正计时"])
    }

    func testLargeHistoryStartupAndPanelsOnlyHydrateRequestedPages() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID(), other = UUID()
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        let records = (0..<10_000).map { index in
            TaskActivityEvent(taskID: index % 2 == 0 ? id : other,
                              occurredAt: instant, kind: .focusStarted,
                              afterValue: String(index))
        }
        try JSONEncoder().encode(records).write(to: directory.appendingPathComponent("task-activity.json"))
        // First launch performs the one-time legacy import; subsequent launches
        // must not decode the imported history again.
        _ = TaskActivityStore(directory: directory)
        let store = TaskActivityStore(clock: { instant }, directory: directory)
        XCTAssertEqual(store.hydratedEventCount, 1)
        let history = TaskActivityPageModel()
        await history.reset(store: store, taskIDs: [id])
        XCTAssertEqual(history.events.count, 50)
        XCTAssertEqual(history.events.first?.afterValue, "9998")
        XCTAssertTrue(history.hasMore)
        XCTAssertEqual(store.hydratedEventCount, 52)
        await history.loadMore(store: store, taskIDs: [id])
        XCTAssertEqual(history.events.count, 100)
        XCTAssertEqual(Set(history.events.map(\.id)).count, 100)
        XCTAssertEqual(history.events.last?.afterValue, "9800")

        // New events reset pagination, avoiding shifted offsets and duplicates.
        store.recordFocusStart(taskID: id, stopwatch: true)
        await history.reset(store: store, taskIDs: [id])
        XCTAssertEqual(history.events.first?.detail, "正计时")
        XCTAssertEqual(history.events.count, 50)
        let reloaded = TaskActivityStore(directory: directory)
        let newestPage = try await reloaded.page(taskIDs: [id], limit: 1)
        XCTAssertEqual(newestPage.first?.detail, "正计时")
        XCTAssertEqual(store.events.count, 10_001, "A delta append must preserve history outside loaded pages")
    }

    func testTitleMergeSurvivesReloadWithoutLoadingWholeHistory() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let original = makeTask(title: "初始")
        var edited = original; edited.title = "中间"
        let first = TaskActivityStore(clock: { now }, directory: directory)
        first.recordChanges(from: [original], to: [edited])
        let initialPage = try await first.page(taskIDs: [original.id])
        let originalEvent = try XCTUnwrap(initialPage.first)
        now = now.addingTimeInterval(1)
        let reloaded = TaskActivityStore(clock: { now }, directory: directory)
        var final = edited; final.title = "最终"
        reloaded.recordChanges(from: [edited], to: [final])
        let merged = try await reloaded.page(taskIDs: [original.id])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.id, originalEvent.id)
        XCTAssertEqual(merged.first?.beforeValue, "初始")
        XCTAssertEqual(merged.first?.afterValue, "最终")
        now = now.addingTimeInterval(1)
        reloaded.recordChanges(from: [final], to: [original])
        let empty = try await reloaded.page(taskIDs: [original.id])
        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(TaskActivityStore(directory: directory).events.isEmpty)
    }

    func testPageExhaustionAndEmptyListDoNotRepeatOrReadOtherTasks() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TaskActivityStore(directory: directory)
        let taskID = UUID()
        for _ in 0..<103 { store.recordFocusStart(taskID: taskID, stopwatch: false) }
        store.recordFocusStart(taskID: UUID(), stopwatch: true)
        let history = TaskActivityPageModel()
        await history.reset(store: store, taskIDs: [taskID])
        await history.loadMore(store: store, taskIDs: [taskID])
        await history.loadMore(store: store, taskIDs: [taskID])
        XCTAssertEqual(history.events.count, 103)
        XCTAssertEqual(Set(history.events.map(\.id)).count, 103)
        XCTAssertFalse(history.hasMore)
        let readCount = store.hydratedEventCount
        await history.loadMore(store: store, taskIDs: [taskID])
        XCTAssertEqual(store.hydratedEventCount, readCount)
        await history.reset(store: store, taskIDs: [])
        XCTAssertTrue(history.events.isEmpty)
        XCTAssertFalse(history.hasMore)
        XCTAssertEqual(store.hydratedEventCount, readCount)
    }

    private func makeTask(id: UUID = UUID(), title: String, tags: [String] = [],
                          parentID: UUID? = nil) -> Task {
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        return Task(id: id, title: title, tags: tags, list: .inbox, priority: .none,
                    schedule: TaskSchedule(), parentID: parentID, childOrder: 0,
                    createdAt: stamp, updatedAt: stamp)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskActivityStoreTests-\(UUID().uuidString)", isDirectory: true)
    }
}
