import Combine
import XCTest
@testable import WorkFollow

/// Real capture/actions/persistence and integration coordinators; only the OS transports are fake.
@MainActor
final class TaskDailyWorkflowTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 8))!
    }

    func testCaptureRescheduleCompleteUndoAndRestartKeepCalendarAndRemindersConsistent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("daily-flow-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let notifications = FakeTaskNotificationClient()
        let systemCalendar = FakeSystemCalendarClient()
        let flow = try Flow(directory: directory, now: now, calendar: calendar,
                            notifications: notifications, systemCalendar: systemCalendar)
        let due = now.addingTimeInterval(3600)
        var capture = QuickCaptureSession(text: "交付检查")
        capture.description = "确认任务、提醒和日历一致"
        capture.scheduleOverride = .init(dueAt: due, hasTime: true, reminderOffsets: [-5, 0])
        let id = try XCTUnwrap(flow.workspace.submitCapture(capture).first)
        await flow.sync()
        XCTAssertEqual(notifications.values.count, 2)
        let eventID = try XCTUnwrap(systemCalendar.values.keys.first)
        XCTAssertEqual(systemCalendar.values[eventID]?.fields.start, due)
        let originalReminderIDs = Set(notifications.values.keys)

        let moved = due.addingTimeInterval(7200)
        XCTAssertNotNil(flow.workspace.moveSchedule(id, to: moved).taskID)
        await flow.sync()
        XCTAssertEqual(Set(systemCalendar.values.keys), [eventID])
        XCTAssertEqual(systemCalendar.values[eventID]?.fields.start, moved)
        XCTAssertTrue(originalReminderIDs.isDisjoint(with: notifications.values.keys))
        XCTAssertEqual(Set(notifications.values.values.map(\.delivery.fireDate)),
                       [moved.addingTimeInterval(-300), moved])

        flow.workspace.complete(id)
        await flow.sync()
        XCTAssertTrue(notifications.values.isEmpty)
        XCTAssertEqual(systemCalendar.values[eventID]?.fields.title, "[已完成] 交付检查")
        flow.workspace.undo()
        await flow.sync()
        let remindersBeforeRestart = notifications.values.mapValues(\.delivery)
        XCTAssertEqual(remindersBeforeRestart.count, 2)
        XCTAssertEqual(systemCalendar.values[eventID]?.fields.title, "交付检查")
        await flow.flush()

        let restarted = try Flow(directory: directory, now: now, calendar: calendar,
                                 notifications: notifications, systemCalendar: systemCalendar)
        await restarted.sync()
        let restored = try XCTUnwrap(restarted.workspace.task(for: id))
        XCTAssertEqual(restored.schedule.dueAt, moved)
        XCTAssertEqual(restored.reminderOffsets, [-5, 0])
        XCTAssertEqual(restored.document.plainText, capture.description)
        XCTAssertFalse(restored.isClosed)
        XCTAssertEqual(notifications.values.mapValues(\.delivery), remindersBeforeRestart)
        XCTAssertEqual(Set(systemCalendar.values.keys), [eventID], "重启不能创建重复日程")
        XCTAssertEqual(systemCalendar.values[eventID]?.fields.start, moved)
        await restarted.flush()
    }

    func testRecurringCompletionMaterializesNextDayWithoutDuplicatingProjectedIntegrations() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("daily-repeat-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let notifications = FakeTaskNotificationClient()
        let systemCalendar = FakeSystemCalendarClient()
        let flow = try Flow(directory: directory, now: now, calendar: calendar,
                            notifications: notifications, systemCalendar: systemCalendar)
        let due = now.addingTimeInterval(3600)
        var capture = QuickCaptureSession(text: "每日复盘")
        capture.scheduleOverride = .init(dueAt: due, hasTime: true, reminderOffsets: [0],
            repeatFrequency: .daily, recurrenceRule: .init(remainingCount: 3))
        let firstID = try XCTUnwrap(flow.workspace.submitCapture(capture).first)
        await flow.sync()
        let eventIDs = Set(systemCalendar.values.keys)
        let nextID = try XCTUnwrap(flow.workspace.complete(firstID).taskID)
        XCTAssertNotEqual(nextID, firstID)
        let next = try XCTUnwrap(flow.workspace.task(for: nextID))
        let nextDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: due))
        XCTAssertEqual(next.schedule.dueAt, nextDate)
        XCTAssertEqual(next.reminderOffsets, [0])
        await flow.sync()
        XCTAssertEqual(Set(systemCalendar.values.keys), eventIDs,
                       "虚拟周期转为真实任务，应复用同一周期日程")
        XCTAssertFalse(notifications.values.values.contains { $0.delivery.sourceID == firstID })
        XCTAssertTrue(notifications.values.values.contains {
            $0.delivery.sourceID == nextID && $0.delivery.fireDate == nextDate
        })
        let pending = notifications.values.mapValues(\.delivery)
        await flow.flush()

        let restarted = try Flow(directory: directory, now: now, calendar: calendar,
                                 notifications: notifications, systemCalendar: systemCalendar)
        await restarted.sync()
        XCTAssertEqual(restarted.workspace.allTasks.count, 2)
        XCTAssertEqual(restarted.workspace.task(for: firstID)?.status, .completed)
        XCTAssertEqual(restarted.workspace.task(for: nextID)?.schedule.dueAt, nextDate)
        XCTAssertEqual(notifications.values.mapValues(\.delivery), pending)
        XCTAssertEqual(Set(systemCalendar.values.keys), eventIDs)
        await restarted.flush()
    }

    @MainActor
    private final class Flow {
        let workspace: TaskWorkspaceModel
        let reminders: NativeReminderService
        let calendarSync: CalendarSyncCoordinator
        let persistence: PersistenceCoordinator
        private var persistenceConnection: AnyCancellable?

        init(directory: URL, now: Date, calendar: Calendar,
             notifications: FakeTaskNotificationClient, systemCalendar: FakeSystemCalendarClient) throws {
            let repository = NativePreviewRepository(directory: directory)
            let snapshot = try repository.load() ?? NativeWorkspaceSnapshot(tasks: [], notes: [])
            try repository.save(snapshot)
            workspace = TaskWorkspaceModel(clock: { now }, calendar: calendar,
                initialTasks: snapshot.tasks, initialTags: snapshot.taskTags)
            persistence = PersistenceCoordinator(repository: repository, delay: 60)
            let modules = directory.appendingPathComponent("modules")
            reminders = NativeReminderService(clock: { now }, calendar: calendar,
                directory: modules, client: notifications)
            calendarSync = CalendarSyncCoordinator(directory: modules, client: systemCalendar,
                clock: { now }, calendar: calendar)
            if !calendarSync.store.snapshot.enabled {
                calendarSync.store.configure {
                    $0.enabled = true
                    $0.targetCalendarID = "test-calendar"
                    $0.autoSyncLists = [TaskList.inbox.name]
                }
            }
            persistenceConnection = workspace.taskChanges.sink { [persistence] changes in
                persistence.schedule(changes: changes)
            }
        }

        func sync() async {
            reminders.reconcile(workspace.tasksInActiveLists)
            await reminders.waitForReconciliation()
            calendarSync.requestSync(tasks: workspace.tasksInActiveLists, activeLists: [TaskList.inbox.name])
            await calendarSync.waitForSync()
            XCTAssertNil(reminders.message)
            XCTAssertNil(calendarSync.message)
        }

        func flush() async {
            await withCheckedContinuation { continuation in
                persistence.flush { error in XCTAssertNil(error); continuation.resume() }
            }
            await withCheckedContinuation { continuation in
                reminders.flush { error in XCTAssertNil(error); continuation.resume() }
            }
            await withCheckedContinuation { continuation in
                calendarSync.flush { error in XCTAssertNil(error); continuation.resume() }
            }
        }
    }
}
