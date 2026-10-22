import Combine
import XCTest
@testable import WorkFollow

/// Real capture/actions/persistence and integration coordinators; only OS transports are fake.
@MainActor
final class TaskDailyWorkflowTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!; return value
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 8))! }

    func testCaptureRescheduleCompleteUndoAndRestartUseRemindersWithoutCalendarCopies() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("daily-flow-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let notifications = FakeTaskNotificationClient(); let systemCalendar = FakeSystemCalendarClient()
        let systemReminders = FakeSystemRemindersClient()
        let flow = try Flow(directory: directory, now: now, calendar: calendar,
            notifications: notifications, systemCalendar: systemCalendar, systemReminders: systemReminders)
        let due = now.addingTimeInterval(3600)
        var capture = QuickCaptureSession(text: "交付检查"); capture.description = "确认任务与手机提醒一致"
        capture.scheduleOverride = .init(dueAt: due, hasTime: true, reminderOffsets: [-5, 0])
        let id = try XCTUnwrap(flow.workspace.submitCapture(capture).first)
        await flow.sync()
        let reminderID = try XCTUnwrap(systemReminders.values.keys.first)
        XCTAssertEqual(systemReminders.values.count, 1)
        XCTAssertEqual(systemReminders.values[reminderID]?.fields.due, due)
        XCTAssertEqual(systemReminders.values[reminderID]?.fields.alarms, [due.addingTimeInterval(-300), due])
        XCTAssertTrue(notifications.values.isEmpty, "已同步任务由提醒事项通知，本机不重复投递")
        XCTAssertTrue(systemCalendar.values.isEmpty, "任务不能再另建日历副本")

        let moved = due.addingTimeInterval(7200)
        XCTAssertNotNil(flow.workspace.moveSchedule(id, to: moved).taskID); await flow.sync()
        XCTAssertEqual(Set(systemReminders.values.keys), [reminderID])
        XCTAssertEqual(systemReminders.values[reminderID]?.fields.due, moved)
        XCTAssertEqual(systemReminders.values[reminderID]?.fields.alarms, [moved.addingTimeInterval(-300), moved])
        flow.workspace.complete(id); await flow.sync()
        XCTAssertEqual(systemReminders.values[reminderID]?.fields.completed, true)
        flow.workspace.undo(); await flow.sync()
        XCTAssertEqual(systemReminders.values[reminderID]?.fields.completed, false)
        await flow.flush()

        let restarted = try Flow(directory: directory, now: now, calendar: calendar,
            notifications: notifications, systemCalendar: systemCalendar, systemReminders: systemReminders)
        await restarted.sync()
        let restored = try XCTUnwrap(restarted.workspace.task(for: id))
        XCTAssertEqual(restored.schedule.dueAt, moved); XCTAssertEqual(restored.reminderOffsets, [-5, 0])
        XCTAssertEqual(restored.document.plainText, capture.description); XCTAssertFalse(restored.isClosed)
        XCTAssertEqual(Set(systemReminders.values.keys), [reminderID], "重启不能创建重复提醒事项")
        XCTAssertTrue(systemCalendar.values.isEmpty); XCTAssertTrue(notifications.values.isEmpty)
        await restarted.flush()
    }

    func testRecurringCompletionReusesReminderPeriodAndNeverCreatesCalendarEvents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("daily-repeat-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let notifications = FakeTaskNotificationClient(); let systemCalendar = FakeSystemCalendarClient()
        let systemReminders = FakeSystemRemindersClient()
        let flow = try Flow(directory: directory, now: now, calendar: calendar,
            notifications: notifications, systemCalendar: systemCalendar, systemReminders: systemReminders)
        let due = now.addingTimeInterval(3600)
        var capture = QuickCaptureSession(text: "每日复盘")
        capture.scheduleOverride = .init(dueAt: due, hasTime: true, reminderOffsets: [0],
            repeatFrequency: .daily, recurrenceRule: .init(remainingCount: 3))
        let firstID = try XCTUnwrap(flow.workspace.submitCapture(capture).first); await flow.sync()
        let reminderIDs = Set(systemReminders.values.keys)
        XCTAssertEqual(reminderIDs.count, 3)
        let nextID = try XCTUnwrap(flow.workspace.complete(firstID).taskID)
        let nextDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: due))
        XCTAssertNotEqual(nextID, firstID); XCTAssertEqual(flow.workspace.task(for: nextID)?.schedule.dueAt, nextDate)
        await flow.sync()
        XCTAssertEqual(Set(systemReminders.values.keys), reminderIDs, "虚拟周期转为真实任务，应复用同一提醒事项")
        XCTAssertEqual(systemReminders.values.values.filter { $0.fields.completed }.count, 1)
        XCTAssertTrue(systemReminders.values.values.contains { $0.fields.due == nextDate && $0.fields.alarms == [nextDate] })
        await flow.flush()

        let restarted = try Flow(directory: directory, now: now, calendar: calendar,
            notifications: notifications, systemCalendar: systemCalendar, systemReminders: systemReminders)
        await restarted.sync()
        XCTAssertEqual(restarted.workspace.allTasks.count, 2)
        XCTAssertEqual(restarted.workspace.task(for: firstID)?.status, .completed)
        XCTAssertEqual(restarted.workspace.task(for: nextID)?.schedule.dueAt, nextDate)
        XCTAssertEqual(Set(systemReminders.values.keys), reminderIDs)
        XCTAssertTrue(systemCalendar.values.isEmpty); XCTAssertTrue(notifications.values.isEmpty)
        await restarted.flush()
    }

    @MainActor
    private final class Flow {
        let workspace: TaskWorkspaceModel
        let reminders: NativeReminderService
        let calendarReader: CalendarSyncCoordinator
        let remindersSync: RemindersSyncCoordinator
        let persistence: PersistenceCoordinator
        private var persistenceConnection: AnyCancellable?

        init(directory: URL, now: Date, calendar: Calendar, notifications: FakeTaskNotificationClient,
             systemCalendar: FakeSystemCalendarClient, systemReminders: FakeSystemRemindersClient) throws {
            let repository = NativePreviewRepository(directory: directory)
            let snapshot = try repository.load() ?? NativeWorkspaceSnapshot(tasks: [], notes: [])
            try repository.save(snapshot)
            workspace = TaskWorkspaceModel(clock: { now }, calendar: calendar,
                initialTasks: snapshot.tasks, initialTags: snapshot.taskTags)
            persistence = PersistenceCoordinator(repository: repository, delay: 60)
            let modules = directory.appendingPathComponent("modules")
            reminders = NativeReminderService(clock: { now }, calendar: calendar, directory: modules, client: notifications)
            calendarReader = CalendarSyncCoordinator(directory: modules, client: systemCalendar)
            calendarReader.store.configure { $0.enabled = true }
            remindersSync = RemindersSyncCoordinator(directory: modules, client: systemReminders, clock: { now }, calendar: calendar)
            remindersSync.store.configure {
                $0.enabled = true; $0.targetListID = "icloud-workfollow"
                $0.autoSyncLists = [RemindersIntegrationSnapshot.allTasksScope]
            }
            persistenceConnection = workspace.taskChanges.sink { [persistence] changes in persistence.schedule(changes: changes) }
        }
        func sync() async {
            await flushWorkspace()
            remindersSync.requestSync(tasks: workspace.allTasks, activeLists: workspace.availableListNames)
            await remindersSync.waitForSync()
            reminders.setExternallyRemindedTasks(Set(workspace.tasksInActiveLists.filter { remindersSync.handlesAlerts(for: $0) }.map(\.id)))
            reminders.reconcile(workspace.tasksInActiveLists); await reminders.waitForReconciliation()
            calendarReader.refreshAccess()
            XCTAssertNil(reminders.message); XCTAssertNil(remindersSync.message); XCTAssertNil(calendarReader.message)
        }
        private func flushWorkspace() async {
            await withCheckedContinuation { continuation in persistence.flush { error in XCTAssertNil(error); continuation.resume() } }
        }
        func flush() async {
            await flushWorkspace()
            await withCheckedContinuation { continuation in reminders.flush { error in XCTAssertNil(error); continuation.resume() } }
            await withCheckedContinuation { continuation in remindersSync.flush { error in XCTAssertNil(error); continuation.resume() } }
            await withCheckedContinuation { continuation in calendarReader.flush { error in XCTAssertNil(error); continuation.resume() } }
        }
    }
}
