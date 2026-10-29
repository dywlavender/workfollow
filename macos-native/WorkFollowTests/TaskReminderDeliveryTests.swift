import XCTest
import UserNotifications
@testable import WorkFollow

@MainActor
final class TaskReminderDeliveryTests: XCTestCase {
    private var now: Date { Date(timeIntervalSince1970: 1_792_300_000) }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 28800)!; return c }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("reminder-test-" + UUID().uuidString) }
    private func task() -> Task {
        var value = Task(id: UUID(), title: "交付报告", list: .inbox, priority: .none,
            schedule: .init(dueAt: now.addingTimeInterval(600), hasTime: true), childOrder: 0, createdAt: now, updatedAt: now)
        value.reminderOffsets = [0, -5]; return value
    }

    func testFocusNotifierKeepsTheSharedTaskNotificationDelegate() {
        let coordinator = NotificationCoordinator(); coordinator.install()
        let focus = FocusNotifier()
        XCTAssertTrue(UNUserNotificationCenter.current().delegate === coordinator)
        withExtendedLifetime(focus) {}
    }

    func testLegacyReminderBellFallsBackToJingle() throws {
        let legacy = try JSONDecoder().decode(TaskReminderPreferences.self,
            from: Data("{\"soundEnabled\":true,\"bell\":\"Glass\",\"snoozeMinutes\":10}".utf8))
        XCTAssertEqual(legacy.bell, "Jingle")
        let chosen = try JSONDecoder().decode(TaskReminderPreferences.self,
            from: Data("{\"soundEnabled\":true,\"bell\":\"Knock\",\"snoozeMinutes\":10}".utf8))
        XCTAssertEqual(chosen.bell, "Knock")
    }

    func testSnoozeSurvivesRestartWithoutChangingTaskSchedule() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = task(); let client = FakeTaskNotificationClient()
        let service = NativeReminderService(clock: { self.now }, calendar: calendar, directory: folder, client: client)
        service.reconcile([source]); await service.waitForReconciliation()
        let first = try XCTUnwrap(service.deliveries.first)
        await service.handle(first, snoozeMinutes: 10)
        XCTAssertEqual(client.values[first.id]?.delivery.fireDate, now.addingTimeInterval(600))
        let restored = NativeReminderService(clock: { self.now }, calendar: calendar, directory: folder, client: client)
        restored.reconcile([source]); await restored.waitForReconciliation()
        XCTAssertEqual(restored.deliveries.first(where: { $0.id == first.id })?.fireDate, now.addingTimeInterval(600))
        XCTAssertEqual(source.schedule.dueAt, now.addingTimeInterval(600))
        XCTAssertEqual(client.values.count, 2, "另一个独立提醒应保留")
    }

    func testStopAcknowledgesOneReminderAndCompletionCancelsTheRest() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        var source = task(); let client = FakeTaskNotificationClient()
        let service = NativeReminderService(clock: { self.now }, calendar: calendar, directory: folder, client: client)
        service.reconcile([source]); await service.waitForReconciliation()
        await service.handle(try XCTUnwrap(service.deliveries.first), snoozeMinutes: nil)
        XCTAssertEqual(client.values.count, 1)
        XCTAssertFalse(source.isClosed)
        source.status = .completed
        service.reconcile([source]); await service.waitForReconciliation()
        XCTAssertTrue(client.values.isEmpty)
    }

    func testRescheduleInvalidatesSnoozeAndUndoRestoresOriginalReminder() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let original = task(); var moved = original; let client = FakeTaskNotificationClient()
        let service = NativeReminderService(clock: { self.now }, calendar: calendar, directory: folder, client: client)
        service.reconcile([original]); await service.waitForReconciliation()
        let old = try XCTUnwrap(service.deliveries.first)
        await service.handle(old, snoozeMinutes: 30)
        moved.schedule.dueAt = now.addingTimeInterval(3600)
        service.reconcile([moved]); await service.waitForReconciliation()
        XCTAssertNil(client.values[old.id])
        await service.handle(old, snoozeMinutes: 5)
        XCTAssertNil(client.values[old.id], "旧通知操作不能重新激活失效提醒")
        service.reconcile([original]); await service.waitForReconciliation()
        XCTAssertEqual(client.values[old.id]?.delivery.fireDate, now.addingTimeInterval(1800))
    }

    func testFailedSystemRegistrationRetriesIdenticalInputAndDoesNotRebuildUnchangedRequests() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = task(); let client = FakeTaskNotificationClient(); client.failNext = true
        let service = NativeReminderService(clock: { self.now }, calendar: calendar, directory: folder, client: client)
        service.reconcile([source]); await service.waitForReconciliation()
        XCTAssertNotNil(service.message)
        service.reconcile([source]); await service.waitForReconciliation()
        XCTAssertEqual(client.values.count, 2)
        let adds = client.addCount
        service.reconcile([source]); await service.waitForReconciliation()
        XCTAssertEqual(client.addCount, adds)
        XCTAssertTrue(client.removed.isEmpty)
    }
}

@MainActor
final class FakeTaskNotificationClient: TaskNotificationClient {
    var values: [String: ScheduledTaskNotification] = [:]
    var removed: [String] = []
    var addCount = 0
    var failNext = false
    func authorization() async -> UNAuthorizationStatus { .authorized }
    func authorize() async throws -> Bool { true }
    func pending() async -> [ScheduledTaskNotification] { Array(values.values) }
    func pendingManagedIDs() async -> [String] { Array(values.keys) }
    func delivered() async -> [ReminderDelivery] { [] }
    func add(_ value: ScheduledTaskNotification, calendar: Calendar) async throws {
        if failNext { failNext = false; throw NSError(domain: "test.registration", code: 1) }
        addCount += 1; values[value.delivery.id] = value
    }
    func removePending(_ ids: [String]) { removed += ids; for id in ids { values.removeValue(forKey: id) } }
    func removeDelivered(_ ids: [String]) {}
}
