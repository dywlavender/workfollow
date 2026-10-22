import XCTest
import EventKit
@testable import WorkFollow

@MainActor
final class SystemCalendarIntegrationTests: XCTestCase {
    private var now: Date { Date(timeIntervalSince1970: 1_792_300_000) }
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 28800)!; return value }
    private var range: DateInterval { .init(start: now.addingTimeInterval(-86400), end: now.addingTimeInterval(7 * 86400)) }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("calendar-test-" + UUID().uuidString) }
    private func event(_ id: String = "meeting") -> SystemCalendarEvent {
        .init(id: id, calendarID: "calendar", fields: .init(title: "会议", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200), allDay: false),
            location: "", calendarTitle: "工作", colorARGB: 0xff0000ff, notes: "日程备注", timeZoneIdentifier: "Asia/Shanghai")
    }
    private func copy(_ id: String) -> (CalendarTaskBinding, SystemCalendarEvent) {
        let reference = CalendarTaskReference(taskID: UUID())
        var value = event(id); value.sourceURL = reference.url
        return (.init(reference: reference, eventID: value.id, calendarID: value.calendarID, lastSynced: value.fields, derivedDuration: false), value)
    }
    private func coordinator(_ folder: URL, _ client: FakeSystemCalendarClient) -> CalendarSyncCoordinator {
        let value = CalendarSyncCoordinator(directory: folder, client: client)
        value.store.configure { $0.enabled = true }
        return value
    }

    func testConnectionAndDateNavigationOnlyReadExistingEvents() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemCalendarClient(); let meeting = event(); client.values[meeting.id] = meeting
        let value = coordinator(folder, client)
        await value.connect(); value.showEvents(in: range); value.refreshAccess(); value.showEvents(in: range)
        XCTAssertEqual(value.externalEvents, [meeting])
        XCTAssertTrue(client.removedIDs.isEmpty); XCTAssertEqual(client.restores, 0)
        XCTAssertEqual(client.values[meeting.id], meeting)
    }

    func testOldExportConfigurationLoadsAsReadOnlyAndKeepsLegacyBindings() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (binding, original) = copy("legacy")
        var snapshot = CalendarIntegrationSnapshot(); snapshot.enabled = true; snapshot.bindings = [binding]
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        data["targetCalendarID"] = "calendar"; data["autoSyncLists"] = ["收集箱"]; data["bidirectional"] = true
        try JSONSerialization.data(withJSONObject: data).write(to: folder.appendingPathComponent("calendar-integration.json"))
        let client = FakeSystemCalendarClient(); client.values[original.id] = original
        let value = CalendarSyncCoordinator(directory: folder, client: client)
        value.showEvents(in: range); await value.connect(); value.refreshAccess()
        XCTAssertEqual(value.legacyCopyCount, 1)
        XCTAssertTrue(value.externalEvents.isEmpty)
        XCTAssertEqual(client.values[original.id], original)
        XCTAssertTrue(client.removedIDs.isEmpty); XCTAssertEqual(client.restores, 0)
    }

    func testAllCalendarsDisplayRealEventsWhileManagedTaskCopiesStayHidden() {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemCalendarClient(); let value = coordinator(folder, client)
        let (binding, original) = copy("legacy")
        let meeting = event(); var holiday = event("holiday"); holiday.calendarID = "readonly"
        client.values = [meeting.id: meeting, holiday.id: holiday, original.id: original]
        value.store.configure { $0.bindings = [binding] }
        value.showEvents(in: range)
        XCTAssertEqual(Set(value.externalEvents.map(\.id)), ["meeting", "holiday"])
    }

    func testDisabledDisplayAndRevokedAccessClearExternalEventsWithoutWrites() {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemCalendarClient(); client.values["meeting"] = event()
        let value = coordinator(folder, client); value.showEvents(in: range)
        XCTAssertEqual(value.externalEvents.count, 1)
        value.store.configure { $0.enabled = false }; XCTAssertTrue(value.externalEvents.isEmpty)
        value.store.configure { $0.enabled = true }; XCTAssertEqual(value.externalEvents.count, 1)
        client.authorization = .denied; value.refreshAccess(); XCTAssertTrue(value.externalEvents.isEmpty)
        XCTAssertTrue(client.removedIDs.isEmpty); XCTAssertEqual(client.restores, 0)
    }

    func testCleanupOnlyRemovesUnchangedManagedCopies() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemCalendarClient(); let value = coordinator(folder, client)
        let (binding, original) = copy("owned")
        let (editedBinding, source) = copy("edited"); var edited = source; edited.fields.title = "系统中修改的日程"
        let (sourceBinding, detached) = copy("detached"); var detachedBinding = sourceBinding; detachedBinding.detached = true
        let meeting = event()
        client.values = [original.id: original, edited.id: edited, detached.id: detached, meeting.id: meeting]
        value.store.configure { $0.bindings = [binding, editedBinding, detachedBinding] }
        value.showEvents(in: range); await value.cleanupLegacyCopies()
        XCTAssertEqual(client.removedIDs, [original.id])
        XCTAssertEqual(Set(client.values.keys), ["edited", "detached", "meeting"])
        XCTAssertEqual(value.removedCopyCount, 1); XCTAssertEqual(value.legacyCopyCount, 0)
        XCTAssertEqual(Set(value.externalEvents.map(\.id)), ["edited", "detached", "meeting"])
        XCTAssertNil(value.message)
    }

    func testCleanupBackupSurvivesRestartAndUndoRestoresOriginalDetailsOnce() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemCalendarClient(); let value = coordinator(folder, client)
        let (binding, original) = copy("owned"); client.values[original.id] = original
        value.store.configure { $0.bindings = [binding] }; await value.cleanupLegacyCopies()
        XCTAssertTrue(client.values.isEmpty)
        let restored = CalendarSyncCoordinator(directory: folder, client: client)
        XCTAssertEqual(restored.removedCopyCount, 1)
        await restored.undoLegacyCleanup(); await restored.undoLegacyCleanup()
        let result = try XCTUnwrap(client.values.values.first)
        XCTAssertEqual(result.fields, original.fields); XCTAssertEqual(result.notes, original.notes)
        XCTAssertEqual(result.timeZoneIdentifier, original.timeZoneIdentifier); XCTAssertEqual(result.sourceURL, original.sourceURL)
        XCTAssertEqual(client.values.count, 1); XCTAssertEqual(client.restores, 1)
        XCTAssertEqual(restored.removedCopyCount, 0); XCTAssertEqual(restored.legacyCopyCount, 0)
        restored.showEvents(in: range); XCTAssertEqual(restored.externalEvents.count, 1)
    }

    func testCleanupWithoutAccessKeepsCopiesAndAssociations() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemCalendarClient(); let value = coordinator(folder, client)
        let (binding, original) = copy("owned"); client.values[original.id] = original
        value.store.configure { $0.bindings = [binding] }; client.authorization = .denied
        await value.cleanupLegacyCopies()
        XCTAssertEqual(client.values.count, 1); XCTAssertEqual(value.legacyCopyCount, 1)
        XCTAssertEqual(value.removedCopyCount, 0); XCTAssertNotNil(value.message)
    }

    func testFailedCleanupCanRetryWithoutDuplicatingBackup() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemCalendarClient(); let value = coordinator(folder, client)
        let (binding, original) = copy("owned"); client.values[original.id] = original
        value.store.configure { $0.bindings = [binding] }; client.failNextRemoval = true
        await value.cleanupLegacyCopies()
        XCTAssertEqual(client.values.count, 1); XCTAssertEqual(value.legacyCopyCount, 1); XCTAssertEqual(value.removedCopyCount, 1)
        await value.cleanupLegacyCopies()
        XCTAssertTrue(client.values.isEmpty); XCTAssertEqual(value.removedCopyCount, 1); XCTAssertNil(value.message)
        await value.undoLegacyCleanup(); XCTAssertEqual(client.values.count, 1)
    }

    func testCleanupFindsChangedSystemIdentifierByTaskURL() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemCalendarClient(); let value = coordinator(folder, client)
        let (binding, original) = copy("old-id"); var current = original; current.id = "new-id"
        client.values[current.id] = current; value.store.configure { $0.bindings = [binding] }
        await value.cleanupLegacyCopies()
        XCTAssertEqual(client.removedIDs, ["new-id"]); XCTAssertEqual(value.legacyCopyCount, 0)
    }

    func testMacAllDayBoundaryAndTaskEventLayoutRemainUnchanged() {
        let day = calendar.startOfDay(for: now); let end = calendar.date(byAdding: .day, value: 1, to: day)!
        let systemEnd = EventKitDayBoundary.systemEnd(exclusiveEnd: end)
        XCTAssertTrue(calendar.isDate(systemEnd, inSameDayAs: day))
        XCTAssertEqual(EventKitDayBoundary.exclusiveEnd(systemEnd: systemEnd, calendar: calendar), end)
        let meeting = event()
        let source = Task(id: UUID(), title: "任务", list: .inbox, priority: .none,
            schedule: .init(dueAt: meeting.fields.start, hasTime: true), childOrder: 0, createdAt: now, updatedAt: now)
        let tasks = CalendarProjection.timed(on: day, tasks: [source], preferences: .init(), calendar: calendar)
        let layout = ExternalCalendarProjection.timed(on: day, tasks: tasks, events: [meeting], calendar: calendar)
        XCTAssertEqual(layout.tasks.first?.laneCount, 2); XCTAssertEqual(layout.events.first?.laneCount, 2)
        XCTAssertNotEqual(layout.tasks.first?.lane, layout.events.first?.lane)
        XCTAssertEqual(layout.tasks.first?.task.id, source.id); XCTAssertEqual(layout.events.first?.event.id, meeting.id)
    }
}

@MainActor
final class FakeSystemCalendarClient: SystemCalendarClient {
    var authorization: EKAuthorizationStatus = .fullAccess
    var onChange: (() -> Void)?
    var values: [String: SystemCalendarEvent] = [:]
    var removedIDs: [String] = []
    var restores = 0
    var failNextRemoval = false
    func requestAccess() async throws -> Bool { authorization == .fullAccess }
    func calendars() -> [SystemCalendarInfo] {
        [.init(id: "calendar", title: "工作", colorARGB: 0xff0000ff, writable: true),
         .init(id: "readonly", title: "订阅", colorARGB: 0xffff0000, writable: false)]
    }
    func events(in range: DateInterval, calendarIDs: [String]) -> [SystemCalendarEvent] {
        values.values.filter { calendarIDs.contains($0.calendarID) && $0.fields.start < range.end && $0.fields.end > range.start }
    }
    func event(id: String) -> SystemCalendarEvent? { values[id] }
    func removeLegacyCopy(id: String) throws {
        if failNextRemoval { failNextRemoval = false; throw CalendarIntegrationError.message("暂时无法移除日程") }
        values.removeValue(forKey: id); removedIDs.append(id)
    }
    func restoreLegacyCopy(_ original: SystemCalendarEvent) throws -> SystemCalendarEvent {
        var value = original; value.id = UUID().uuidString
        values[value.id] = value; restores += 1
        return value
    }
}
