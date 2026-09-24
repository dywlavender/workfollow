import XCTest
@testable import WorkFollow

final class StageAInfrastructureTests: XCTestCase {
    func testTextEditsDoNotRecordOrGetRevertedByBusinessUndo() {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store)
        let id = actions.create(title: "before").taskID!
        store.clearUndo()
        actions.setDocument(id, NativeDocument(plainText: "first"))
        XCTAssertFalse(store.canUndo)
        actions.setPriority(id, .high)
        actions.setTitle(id, "after")
        actions.setDocument(id, NativeDocument(plainText: "latest"))
        actions.undo()
        XCTAssertEqual(store.task(id)?.priority, TaskPriority.none)
        XCTAssertEqual(store.task(id)?.title, "after")
        XCTAssertEqual(store.task(id)?.document.plainText, "latest")
        XCTAssertFalse(store.canUndo)
    }

    func testQueryFindsCollapsedChildAndPromotesItToRoot() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(seedDemoData: false)
            let parent = model.createTask(title: "parent", in: .inbox).taskID!
            let child = model.createChild(parent, title: "needle").taskID!
            model.setTags(child, ["work"])
            let query = TaskListQuery(search: "needle", list: TaskList.inbox.name, tag: "work")
            let nodes = model.visibleNodes(for: .inbox, query: query)
            XCTAssertEqual(nodes.map(\.task.id), [child])
            XCTAssertEqual(nodes.map(\.depth), [0])
            XCTAssertEqual(model.groups(for: .inbox, query: query).first?.tasks.count, 1)
            XCTAssertTrue(model.groups(for: .inbox, query: TaskListQuery(search: "absent")).isEmpty)
        }
    }

    func testQueryExpandsMatchingParentAndChildWithoutChangingStoredExpansion() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(seedDemoData: false)
            let parent = model.createTask(title: "match parent", in: .inbox).taskID!
            let child = model.createChild(parent, title: "match child").taskID!
            XCTAssertEqual(model.visibleNodes(for: .inbox, query: TaskListQuery(search: "match")).map(\.task.id), [parent, child])
            XCTAssertTrue(model.expandedTaskIDs.isEmpty)
        }
    }

    func testReminderSignatureIgnoresBodyButTracksNotificationContentAndEligibility() {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store)
        let id = actions.create(title: "Reminder").taskID!
        actions.setReminder(id, Date(timeIntervalSince1970: 2_000_000_000))
        let before = ReminderSignature.values(store.tasks)
        actions.setDocument(id, NativeDocument(plainText: "body"))
        XCTAssertEqual(ReminderSignature.values(store.tasks), before)
        actions.setTitle(id, "new title")
        XCTAssertNotEqual(ReminderSignature.values(store.tasks), before)
        actions.complete(id)
        XCTAssertTrue(ReminderSignature.values(store.tasks).isEmpty)
    }

    func testFlushWritesLatestSnapshotBeforeDebounceExpires() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repository = NativePreviewRepository(directory: directory)
        let coordinator = PersistenceCoordinator(repository: repository, delay: 60)
        let store = WorkspaceStore()
        let actions = TaskActions(store: store)
        actions.create(title: "first")
        coordinator.schedule(NativeWorkspaceSnapshot(tasks: store.tasks, notes: []))
        actions.create(title: "latest")
        coordinator.schedule(NativeWorkspaceSnapshot(tasks: store.tasks, notes: []))
        let done = expectation(description: "flush")
        coordinator.flush { error in XCTAssertNil(error); done.fulfill() }
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(try repository.load()?.tasks.map(\.title), ["first", "latest"])
    }

    func testDebounceCoalescesWritesOffMainThread() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let coordinator = PersistenceCoordinator(repository: NativePreviewRepository(directory: directory), delay: 0.05)
        let saved = expectation(description: "one background save")
        saved.assertForOverFulfill = true
        coordinator.onResult = { error in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertNil(error)
            saved.fulfill()
        }
        for _ in 0..<20 { coordinator.schedule(NativeWorkspaceSnapshot(tasks: [], notes: [])) }
        await fulfillment(of: [saved], timeout: 5)
        let flushed = expectation(description: "barrier")
        coordinator.flush { _ in flushed.fulfill() }
        await fulfillment(of: [flushed], timeout: 5)
    }

    func testNotesAndRecurrenceUseInjectedTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let notes = NoteStore(clock: { now })
        let note = notes.create()
        notes.delete(note)
        XCTAssertEqual(notes.notes.first?.deletedAt, now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { now }, calendar: calendar)
        let id = actions.create(title: "repeat", schedule: TaskSchedule(dueAt: now)).taskID!
        actions.setRepeat(id, .monthly)
        actions.complete(id)
        XCTAssertEqual(store.tasks.last?.schedule.dueAt, calendar.date(byAdding: .month, value: 1, to: now))
    }
}
