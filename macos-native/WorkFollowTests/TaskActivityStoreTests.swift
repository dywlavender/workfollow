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
            atPath: directory.appendingPathComponent("task-activity.json").path))
        let reloaded = TaskActivityStore(clock: { instant }, directory: directory)
        XCTAssertEqual(reloaded.events(for: taskID).map(\.detail), ["正计时"])
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
