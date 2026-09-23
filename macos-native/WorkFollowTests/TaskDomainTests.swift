import XCTest
@testable import WorkFollow

final class TaskDomainTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testCreationTitlePriorityAndInboxMovement() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.today })
        let id = try XCTUnwrap(actions.create(title: "  Draft  ").taskID)
        XCTAssertEqual(store.task(id)?.title, "Draft")
        XCTAssertEqual(TaskListProjection.rows(in: .inbox, store: store, now: today, calendar: calendar).map(\.id), [id])
        _ = actions.setTitle(id, "Renamed")
        _ = actions.setPriority(id, .high)
        _ = actions.moveToList(id, TaskList(name: "工作"))
        XCTAssertEqual(store.task(id)?.title, "Renamed")
        XCTAssertEqual(store.task(id)?.priority, .high)
        XCTAssertTrue(TaskListProjection.rows(in: .inbox, store: store, now: today, calendar: calendar).isEmpty)
    }

    func testCompletionLeavesTodayOpenTasksButRemainsInClosedGroup() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.today })
        let id = try XCTUnwrap(actions.create(title: "Today", schedule: TaskSchedule(dueAt: today)).taskID)
        _ = actions.complete(id)
        let groups = TaskListProjection.groups(in: .today, store: store, now: today, calendar: calendar)
        XCTAssertEqual(groups.flatMap(\.tasks).map(\.id), [id])
        XCTAssertEqual(groups.first?.kind, .completed)
        XCTAssertEqual(TaskListProjection.count(in: .today, store: store, now: today, calendar: calendar), 0)
        XCTAssertEqual(TaskListProjection.rows(in: .completed, store: store, now: today, calendar: calendar).map(\.id), [id])
        _ = actions.restore(id)
        XCTAssertEqual(store.task(id)?.status, .active)
        XCTAssertNil(store.task(id)?.completedAt)
        XCTAssertEqual(TaskListProjection.count(in: .today, store: store, now: today, calendar: calendar), 1)
    }

    func testScheduleUsesCalendarDayAndDoesNotTreatUndatedAsToday() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let overdue = try XCTUnwrap(actions.create(title: "overdue", schedule: TaskSchedule(dueAt: yesterday)).taskID)
        _ = actions.create(title: "undated")
        _ = actions.create(title: "future", schedule: TaskSchedule(dueAt: tomorrow))
        let deadline = try XCTUnwrap(actions.create(title: "deadline", schedule: TaskSchedule(deadlineAt: calendar.startOfDay(for: today))).taskID)
        XCTAssertEqual(Set(TaskListProjection.rows(in: .today, store: store, now: today, calendar: calendar).map(\.id)), Set([overdue, deadline]))
    }

    func testChildCannotCreateGrandchildAndHasIndependentFields() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store)
        let parent = try XCTUnwrap(actions.create(title: "parent", schedule: TaskSchedule(dueAt: today), priority: .high).taskID)
        let child = try XCTUnwrap(actions.createChild(parent, title: "child").taskID)
        XCTAssertEqual(actions.createChild(child), .failure(.childCannotHaveChildren))
        XCTAssertNil(store.task(child)?.schedule.dueAt)
        XCTAssertEqual(store.task(child)?.priority, TaskPriority.none)
        _ = actions.setTitle(child, "independent")
        XCTAssertEqual(store.task(parent)?.title, "parent")
    }

    func testCompletingChildDoesNotCompleteParent() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store)
        let parent = try XCTUnwrap(actions.create(title: "parent").taskID)
        let child = try XCTUnwrap(actions.createChild(parent).taskID)
        _ = actions.complete(child)
        XCTAssertEqual(store.task(parent)?.status, .active)
    }

    func testCompletingParentCompletesChildrenAndRestoreDoesNotRestoreChildren() throws {
        let store = WorkspaceStore()
        var now = today
        let actions = TaskActions(store: store, clock: { now })
        let parent = try XCTUnwrap(actions.create(title: "parent").taskID)
        let first = try XCTUnwrap(actions.createChild(parent).taskID)
        let second = try XCTUnwrap(actions.createChild(parent).taskID)
        _ = actions.complete(first)
        now = now.addingTimeInterval(60)
        _ = actions.complete(parent)
        XCTAssertEqual(store.task(first)?.completedAt, today)
        XCTAssertEqual(store.task(second)?.status, .completed)
        _ = actions.restore(parent)
        XCTAssertEqual(store.task(parent)?.status, .active)
        XCTAssertEqual(store.task(first)?.status, .completed)
        XCTAssertEqual(store.task(second)?.status, .completed)
    }

    func testDeleteAndUndeleteOnlyRestoreChildrenDeletedWithParent() throws {
        let store = WorkspaceStore()
        var now = today
        let actions = TaskActions(store: store, clock: { now })
        let parent = try XCTUnwrap(actions.create(title: "parent").taskID)
        let earlier = try XCTUnwrap(actions.createChild(parent).taskID)
        let together = try XCTUnwrap(actions.createChild(parent).taskID)
        _ = actions.delete(earlier)
        now = now.addingTimeInterval(60)
        _ = actions.delete(parent)
        XCTAssertTrue(TaskListProjection.rows(in: .inbox, store: store, now: now, calendar: calendar).isEmpty)
        _ = actions.restoreDeleted(parent)
        XCTAssertNotNil(store.task(earlier)?.deletedAt)
        XCTAssertNil(store.task(together)?.deletedAt)
        XCTAssertNil(store.task(parent)?.deletedAt)
    }

    func testMovingParentCarriesActiveChildrenAndTreeDoesNotDuplicateThem() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store)
        let parent = try XCTUnwrap(actions.create(title: "parent").taskID)
        let child = try XCTUnwrap(actions.createChild(parent).taskID)
        let roots = TaskListProjection.rows(in: .inbox, store: store, now: today, calendar: calendar)
        XCTAssertEqual(roots.map(\.id), [parent])
        XCTAssertEqual(TaskTreeProjection.nodes(roots: roots, store: store, expanded: [parent]).map(\.depth), [0, 1])
        XCTAssertEqual(TaskTreeProjection.nodes(roots: roots, store: store, expanded: []).map(\.task.id), [parent])
        _ = actions.moveToList(parent, TaskList(name: "工作"))
        XCTAssertEqual(store.task(child)?.list.name, "工作")
    }

    func testMatchingChildIsPromotedWhenParentDoesNotMatchToday() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store)
        let parent = try XCTUnwrap(actions.create(title: "parent").taskID)
        let child = try XCTUnwrap(actions.createChild(parent).taskID)
        _ = actions.setSchedule(child, TaskSchedule(dueAt: today))
        XCTAssertEqual(TaskListProjection.rows(in: .today, store: store, now: today, calendar: calendar).map(\.id), [child])
    }

    func testMissingTaskAndInvalidListDoNotMutateStore() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store)
        XCTAssertEqual(actions.complete(UUID()), .failure(.missingTask))
        let id = try XCTUnwrap(actions.create(title: "task").taskID)
        let before = store.tasks
        XCTAssertEqual(actions.moveToList(id, TaskList(name: "  ")), .failure(.invalidList))
        XCTAssertEqual(store.tasks, before)
    }

    func testCompletedGroupsSortNewestFirst() throws {
        let store = WorkspaceStore()
        var now = today
        let actions = TaskActions(store: store, clock: { now })
        let first = try XCTUnwrap(actions.create(title: "first").taskID)
        let second = try XCTUnwrap(actions.create(title: "second").taskID)
        _ = actions.complete(first)
        now = calendar.date(byAdding: .day, value: 1, to: now)!
        _ = actions.complete(second)
        let groups = TaskListProjection.groups(in: .completed, store: store, now: now, calendar: calendar)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.flatMap(\.tasks).map(\.id), [second, first])
    }

    func testTodayUsesInjectedTimezoneAndCompletionIsIdempotent() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.today })
        var local = calendar
        local.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let now = Date(timeIntervalSince1970: 0)
        let laterSameDay = now.addingTimeInterval(15 * 3600)
        let id = try XCTUnwrap(actions.create(title: "same local day", schedule: TaskSchedule(dueAt: laterSameDay, hasTime: true)).taskID)
        XCTAssertEqual(TaskListProjection.count(in: .today, store: store, now: now, calendar: local), 1)
        _ = actions.complete(id)
        let before = store.tasks
        XCTAssertEqual(actions.complete(id), .failure(.alreadyCompleted))
        XCTAssertEqual(store.tasks, before)
    }
}
