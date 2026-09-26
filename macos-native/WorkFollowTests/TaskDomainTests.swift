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

    func testTodayGroupsOverdueBeforeTodayAndKeepsCompletedInItsOwnGroup() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.today }, calendar: calendar)
        let start = calendar.startOfDay(for: today)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: start)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start)!
        let overdueID = try XCTUnwrap(actions.create(
            title: "overdue", schedule: TaskSchedule(dueAt: yesterday)).taskID)
        let todayID = try XCTUnwrap(actions.create(
            title: "today", schedule: TaskSchedule(dueAt: start)).taskID)
        let completedID = try XCTUnwrap(actions.create(
            title: "completed", schedule: TaskSchedule(dueAt: start)).taskID)
        _ = actions.complete(completedID)
        _ = actions.create(title: "tomorrow", schedule: TaskSchedule(dueAt: tomorrow))

        let groups = TaskListProjection.groups(in: .today, store: store,
                                               now: today, calendar: calendar)
        XCTAssertEqual(groups.map(\.kind), [.overdue, .today, .completed])
        XCTAssertEqual(groups[0].tasks.map(\.id), [overdueID])
        XCTAssertEqual(groups[1].day, start)
        XCTAssertEqual(groups[1].tasks.map(\.id), [todayID])
        XCTAssertEqual(groups[2].tasks.map(\.id), [completedID])
        XCTAssertEqual(TaskListProjection.count(in: .today, store: store,
                                                now: today, calendar: calendar), 2)
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

    func testRecentIncludesOverdueAndGroupsDueDaysInAscendingOrder() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.today }, calendar: calendar)
        let start = calendar.startOfDay(for: today)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: start)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start)!
        let outsideWindow = calendar.date(byAdding: .day, value: 7, to: start)!

        let tomorrowID = try XCTUnwrap(actions.create(
            title: "tomorrow", schedule: TaskSchedule(dueAt: tomorrow)).taskID)
        let overdueID = try XCTUnwrap(actions.create(
            title: "overdue", schedule: TaskSchedule(dueAt: yesterday)).taskID)
        let todayID = try XCTUnwrap(actions.create(
            title: "today", schedule: TaskSchedule(dueAt: start)).taskID)
        _ = actions.create(title: "outside", schedule: TaskSchedule(dueAt: outsideWindow))
        _ = actions.create(title: "deadline only", schedule: TaskSchedule(deadlineAt: start))
        let completedID = try XCTUnwrap(actions.create(
            title: "completed tomorrow", schedule: TaskSchedule(dueAt: tomorrow)).taskID)
        _ = actions.complete(completedID)

        let groups = TaskListProjection.groups(in: .nextSevenDays, store: store,
                                               now: today, calendar: calendar)
        XCTAssertEqual(groups.map(\.kind), [.overdue, .today, .day, .completed])
        XCTAssertEqual(groups[0].tasks.map(\.id), [overdueID])
        XCTAssertEqual(groups[1].day, start)
        XCTAssertEqual(groups[1].tasks.map(\.id), [todayID])
        XCTAssertEqual(groups[2].day, tomorrow)
        XCTAssertEqual(groups[2].tasks.map(\.id), [tomorrowID])
        XCTAssertEqual(groups[3].tasks.map(\.id), [completedID])
        XCTAssertEqual(TaskListProjection.count(in: .nextSevenDays, store: store,
                                                now: today, calendar: calendar), 3)
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

    func testChildCannotMoveToAnotherListIndependently() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store)
        let parentID = try XCTUnwrap(actions.create(title: "parent", list: TaskList(name: "工作")).taskID)
        let childID = try XCTUnwrap(actions.createChild(parentID).taskID)
        let before = store.tasks

        XCTAssertEqual(actions.moveToList(childID, TaskList(name: "个人")),
                       .failure(.childListMoveNotSupported))
        XCTAssertEqual(store.task(parentID)?.list, TaskList(name: "工作"))
        XCTAssertEqual(store.task(childID)?.list, TaskList(name: "工作"))
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

    func testAbandonedTaskIsClosedOutsideTodayAndRestoresToItsActiveScope() throws {
        let store = WorkspaceStore()
        let now = calendar.startOfDay(for: today)
        let actions = TaskActions(store: store, clock: { now }, calendar: calendar)
        let id = try XCTUnwrap(actions.create(
            title: "give up", schedule: TaskSchedule(dueAt: now)).taskID)

        XCTAssertEqual(actions.abandon(id), .success(id))
        let abandoned = try XCTUnwrap(store.task(id))
        XCTAssertTrue(abandoned.isAbandoned)
        XCTAssertTrue(abandoned.isClosed)
        XCTAssertEqual(TaskListProjection.count(in: .today, store: store, now: now, calendar: calendar), 0)
        XCTAssertTrue(TaskListProjection.groups(in: .today, store: store, now: now, calendar: calendar).isEmpty)
        XCTAssertEqual(TaskListProjection.count(in: .completed, store: store, now: now, calendar: calendar), 1)

        let completedGroups = TaskListProjection.groups(in: .completed, store: store,
                                                        now: now, calendar: calendar)
        XCTAssertEqual(completedGroups.compactMap(\.day), [now])
        XCTAssertEqual(completedGroups.flatMap(\.tasks).map(\.id), [id])
        let allClosed = try XCTUnwrap(TaskListProjection.groups(
            in: .allTasks, store: store, now: now, calendar: calendar)
            .first { $0.kind == .completed })
        XCTAssertEqual(allClosed.label, "已放弃")

        XCTAssertEqual(actions.complete(id), .failure(.alreadyCompleted))
        XCTAssertEqual(actions.restore(id), .success(id))
        XCTAssertFalse(try XCTUnwrap(store.task(id)).isClosed)
        XCTAssertNil(store.task(id)?.abandonedAt)
        XCTAssertEqual(TaskListProjection.count(in: .today, store: store, now: now, calendar: calendar), 1)
        XCTAssertEqual(TaskListProjection.count(in: .completed, store: store, now: now, calendar: calendar), 0)
    }

    func testCompletedAndAbandonedGroupsUseTheirCloseTimesAndMixedLabel() throws {
        let store = WorkspaceStore()
        let dayOne = calendar.startOfDay(for: today)
        var now = calendar.date(byAdding: .hour, value: 8, to: dayOne)!
        let actions = TaskActions(store: store, clock: { now }, calendar: calendar)
        let completedID = try XCTUnwrap(actions.create(title: "completed").taskID)
        _ = actions.complete(completedID)

        now = calendar.date(byAdding: .hour, value: 11, to: dayOne)!
        let abandonedID = try XCTUnwrap(actions.create(title: "abandoned").taskID)
        _ = actions.abandon(abandonedID)

        let dayTwo = calendar.date(byAdding: .day, value: 1, to: dayOne)!
        now = calendar.date(byAdding: .hour, value: 9, to: dayTwo)!
        let nextDayID = try XCTUnwrap(actions.create(title: "next day").taskID)
        _ = actions.complete(nextDayID)

        let completedGroups = TaskListProjection.groups(in: .completed, store: store,
                                                        now: now, calendar: calendar)
        XCTAssertEqual(completedGroups.compactMap(\.day), [dayTwo, dayOne])
        XCTAssertEqual(completedGroups[1].tasks.map(\.id), [abandonedID, completedID])

        let allClosed = try XCTUnwrap(TaskListProjection.groups(
            in: .allTasks, store: store, now: now, calendar: calendar)
            .first { $0.kind == .completed })
        XCTAssertEqual(allClosed.label, "已完成&已放弃")
        XCTAssertEqual(allClosed.tasks.map(\.id), [nextDayID, abandonedID, completedID])
    }

    func testTaskGroupFoldingIsStableAndClosedGroupsCanBeToggledTogether() throws {
        let store = WorkspaceStore()
        var now = calendar.startOfDay(for: today).addingTimeInterval(8 * 60 * 60)
        let actions = TaskActions(store: store, clock: { now }, calendar: calendar)
        let firstID = try XCTUnwrap(actions.create(title: "first closed").taskID)
        _ = actions.complete(firstID)
        now = now.addingTimeInterval(24 * 60 * 60)
        let secondID = try XCTUnwrap(actions.create(title: "second closed").taskID)
        _ = actions.complete(secondID)

        let groups = TaskListProjection.groups(in: .completed, store: store,
                                               now: now, calendar: calendar)
        XCTAssertEqual(groups.count, 2)
        XCTAssertNotEqual(groups[0].id, groups[1].id)
        XCTAssertTrue(groups.allSatisfy { !$0.id.isEmpty })
        let relabeledGroup = TaskListGroup(kind: groups[0].kind, day: groups[0].day,
                                           tasks: groups[0].tasks, label: "改过的日期标题")
        XCTAssertEqual(groups[0].id, relabeledGroup.id)

        var state = TaskGroupExpansionState()
        XCTAssertTrue(groups.allSatisfy { !state.isCollapsed($0) })
        state.toggle(groups[0])
        XCTAssertTrue(state.isCollapsed(groups[0]))
        XCTAssertFalse(state.isCollapsed(groups[1]))

        state.toggleClosedGroups(in: groups)
        XCTAssertTrue(groups.allSatisfy(state.isCollapsed))
        state.toggleClosedGroups(in: groups)
        XCTAssertTrue(groups.allSatisfy { !state.isCollapsed($0) })

        state.toggle(groups[0])
        state.reveal(try XCTUnwrap(groups[0].tasks.first), in: .completed, calendar: calendar)
        XCTAssertFalse(state.isCollapsed(groups[0]))
    }

    func testAllTasksGroupsPinnedThenDateBucketsWithStableOrder() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.today }, calendar: calendar)
        let start = calendar.startOfDay(for: today)
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: start)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start)!
        let threeDaysOut = calendar.date(byAdding: .day, value: 3, to: start)!
        let recentEnd = calendar.date(byAdding: .day, value: 7, to: start)!
        let overdueID = try XCTUnwrap(actions.create(
            title: "overdue", schedule: TaskSchedule(dueAt: dayBefore)).taskID)
        let laterSoonID = try XCTUnwrap(actions.create(
            title: "three days", schedule: TaskSchedule(dueAt: threeDaysOut)).taskID)
        let todayID = try XCTUnwrap(actions.create(
            title: "today", schedule: TaskSchedule(dueAt: start)).taskID)
        let firstTomorrowID = try XCTUnwrap(actions.create(
            title: "tomorrow first", schedule: TaskSchedule(dueAt: tomorrow)).taskID)
        let secondTomorrowID = try XCTUnwrap(actions.create(
            title: "tomorrow second", schedule: TaskSchedule(dueAt: tomorrow.addingTimeInterval(3600))).taskID)
        let laterID = try XCTUnwrap(actions.create(
            title: "seven days", schedule: TaskSchedule(dueAt: recentEnd)).taskID)
        let undatedID = try XCTUnwrap(actions.create(title: "undated").taskID)
        let deadlineOnlyID = try XCTUnwrap(actions.create(
            title: "deadline only", schedule: TaskSchedule(deadlineAt: dayBefore)).taskID)
        let pinnedID = try XCTUnwrap(actions.create(
            title: "pinned overdue", schedule: TaskSchedule(dueAt: dayBefore)).taskID)
        let completedID = try XCTUnwrap(actions.create(
            title: "completed", schedule: TaskSchedule(dueAt: start)).taskID)
        _ = actions.setPinned(pinnedID, true)
        _ = actions.complete(completedID)

        let groups = TaskListProjection.groups(in: .allTasks, store: store,
                                               now: today, calendar: calendar)
        XCTAssertEqual(groups.map(\.kind), [.pinned, .overdue, .today, .upcoming, .later, .undated, .completed])
        XCTAssertEqual(groups[0].tasks.map(\.id), [pinnedID])
        XCTAssertEqual(groups[1].tasks.map(\.id), [overdueID])
        XCTAssertEqual(groups[2].tasks.map(\.id), [todayID])
        XCTAssertEqual(groups[3].tasks.map(\.id), [firstTomorrowID, secondTomorrowID, laterSoonID])
        XCTAssertEqual(groups[4].tasks.map(\.id), [laterID])
        XCTAssertEqual(groups[5].tasks.map(\.id), [undatedID, deadlineOnlyID])
        XCTAssertEqual(groups[6].tasks.map(\.id), [completedID])
    }

    func testAllTasksListAndTagFiltersKeepManualPlainGroupingAfterPinned() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.today }, calendar: calendar)
        let overdue = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today))!
        let pinnedID = try XCTUnwrap(actions.create(
            title: "pinned", list: TaskList(name: "工作"), schedule: TaskSchedule(dueAt: overdue)).taskID)
        let ordinaryID = try XCTUnwrap(actions.create(
            title: "ordinary", list: TaskList(name: "工作"), schedule: TaskSchedule(dueAt: today)).taskID)
        _ = actions.setPinned(pinnedID, true)
        _ = actions.setTags(ordinaryID, ["focus"])

        let listGroups = TaskListProjection.groups(in: .allTasks, store: store, now: today,
                                                   calendar: calendar, query: TaskListQuery(list: "工作"))
        XCTAssertEqual(listGroups.map(\.kind), [.pinned, .plain])
        XCTAssertEqual(listGroups.flatMap(\.tasks).map(\.id), [pinnedID, ordinaryID])

        let tagGroups = TaskListProjection.groups(in: .allTasks, store: store, now: today,
                                                  calendar: calendar, query: TaskListQuery(tag: "focus"))
        XCTAssertEqual(tagGroups.map(\.kind), [.plain])
        XCTAssertEqual(tagGroups.flatMap(\.tasks).map(\.id), [ordinaryID])
    }

    func testPinnedTasksLeadTodayAndInboxBeforeTheirOrdinaryGroups() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.today }, calendar: calendar)
        let todayID = try XCTUnwrap(actions.create(
            title: "today", list: TaskList(name: "工作"),
            schedule: TaskSchedule(dueAt: today)).taskID)
        let pinnedTodayID = try XCTUnwrap(actions.create(
            title: "pinned today", list: TaskList(name: "工作"),
            schedule: TaskSchedule(dueAt: today)).taskID)
        let inboxID = try XCTUnwrap(actions.create(title: "inbox").taskID)
        let pinnedInboxID = try XCTUnwrap(actions.create(title: "pinned inbox").taskID)
        _ = actions.setPinned(pinnedTodayID, true)
        _ = actions.setPinned(pinnedInboxID, true)

        let todayGroups = TaskListProjection.groups(in: .today, store: store,
                                                    now: today, calendar: calendar)
        XCTAssertEqual(todayGroups.map(\.kind), [.pinned, .today])
        XCTAssertEqual(todayGroups.flatMap(\.tasks).map(\.id), [pinnedTodayID, todayID])

        let inboxGroups = TaskListProjection.groups(in: .inbox, store: store,
                                                    now: today, calendar: calendar)
        XCTAssertEqual(inboxGroups.map(\.kind), [.pinned, .plain])
        XCTAssertEqual(inboxGroups.flatMap(\.tasks).map(\.id), [pinnedInboxID, inboxID])
    }

    func testTaskGroupSortsByDateOrPriorityButLeavesCompletedOrderUntouched() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.today }, calendar: calendar)
        let start = calendar.startOfDay(for: today)
        let lowMorning = try XCTUnwrap(actions.create(
            title: "low morning", schedule: TaskSchedule(dueAt: start.addingTimeInterval(8 * 3600), hasTime: true),
            priority: .low).taskID)
        let highNoon = try XCTUnwrap(actions.create(
            title: "high noon", schedule: TaskSchedule(dueAt: start.addingTimeInterval(12 * 3600), hasTime: true),
            priority: .high).taskID)
        let highMorning = try XCTUnwrap(actions.create(
            title: "high morning", schedule: TaskSchedule(dueAt: start.addingTimeInterval(9 * 3600), hasTime: true),
            priority: .high).taskID)
        let undated = try XCTUnwrap(actions.create(title: "undated", priority: .medium).taskID)
        let group = TaskListGroup(kind: .plain, day: nil,
                                  tasks: [lowMorning, highNoon, highMorning, undated].compactMap(store.task))

        XCTAssertEqual(group.orderedTasks(using: .manual, calendar: calendar).map(\.id),
                       [lowMorning, highNoon, highMorning, undated])
        XCTAssertEqual(group.orderedTasks(using: .due, calendar: calendar).map(\.id),
                       [lowMorning, highMorning, highNoon, undated])
        XCTAssertEqual(group.orderedTasks(using: .priority, calendar: calendar).map(\.id),
                       [highMorning, highNoon, undated, lowMorning])

        let completed = TaskListGroup(kind: .completed, day: nil,
                                      tasks: [highNoon, lowMorning].compactMap(store.task))
        XCTAssertEqual(completed.orderedTasks(using: .priority, calendar: calendar).map(\.id),
                       [highNoon, lowMorning])
    }

    func testPostponeOverdueGroupPreservesTimeAndIsOneUndoableOperation() throws {
        let store = WorkspaceStore()
        var local = calendar
        local.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = local.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 16))!
        let yesterday = local.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        let timedDue = local.date(bySettingHour: 9, minute: 30, second: 0, of: yesterday)!
        let deadline = local.date(from: DateComponents(year: 2026, month: 9, day: 30))!
        let actions = TaskActions(store: store, clock: { now }, calendar: local)
        let timedID = try XCTUnwrap(actions.create(
            title: "timed", schedule: TaskSchedule(dueAt: timedDue, hasTime: true, deadlineAt: deadline)).taskID)
        let allDayID = try XCTUnwrap(actions.create(
            title: "all day", schedule: TaskSchedule(dueAt: yesterday)).taskID)
        store.clearUndo()

        actions.postponeOverdue([timedID, allDayID], to: now)

        let today = local.startOfDay(for: now)
        XCTAssertEqual(store.task(timedID)?.schedule.dueAt,
                       local.date(bySettingHour: 9, minute: 30, second: 0, of: today))
        XCTAssertEqual(store.task(timedID)?.schedule.hasTime, true)
        XCTAssertEqual(store.task(timedID)?.schedule.deadlineAt, deadline)
        XCTAssertEqual(store.task(allDayID)?.schedule.dueAt, today)
        XCTAssertEqual(store.task(allDayID)?.schedule.hasTime, false)
        XCTAssertTrue(store.canUndo)

        actions.undo()
        XCTAssertEqual(store.task(timedID)?.schedule.dueAt, timedDue)
        XCTAssertEqual(store.task(allDayID)?.schedule.dueAt, yesterday)
        XCTAssertFalse(store.canUndo)
    }

    func testPinnedStateRoundTripsAndOlderTaskSnapshotsDefaultToUnpinned() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.today })
        let id = try XCTUnwrap(actions.create(title: "pinned").taskID)
        _ = actions.setPinned(id, true)
        let task = try XCTUnwrap(store.task(id))
        let encoded = try JSONEncoder().encode(task)
        XCTAssertTrue(try JSONDecoder().decode(Task.self, from: encoded).isPinned)

        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject.removeValue(forKey: "isPinned")
        legacyObject.removeValue(forKey: "abandonedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacy = try JSONDecoder().decode(Task.self, from: legacyData)
        XCTAssertFalse(legacy.isPinned)
        XCTAssertFalse(legacy.isAbandoned)
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
