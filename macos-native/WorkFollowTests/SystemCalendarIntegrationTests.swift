import XCTest
import EventKit
@testable import WorkFollow

@MainActor
final class SystemCalendarIntegrationTests: XCTestCase {
    private var now: Date { Date(timeIntervalSince1970: 1_792_300_000) }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 28800)!; return c }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("calendar-test-" + UUID().uuidString) }
    private func task() -> Task { Task(id: UUID(), title: "联调", list: .inbox, priority: .none,
        schedule: .init(dueAt: now.addingTimeInterval(3600), hasTime: true, deadlineAt: now.addingTimeInterval(86400)),
        childOrder: 0, createdAt: now, updatedAt: now) }
    private func coordinator(_ folder: URL, _ client: FakeSystemCalendarClient) -> CalendarSyncCoordinator {
        let value = CalendarSyncCoordinator(directory: folder, client: client, clock: { self.now }, calendar: calendar)
        value.store.configure { $0.enabled = true; $0.targetCalendarID = "test-calendar"; $0.autoSyncLists = [TaskList.inbox.name] }
        return value
    }
    private func sync(_ value: CalendarSyncCoordinator, _ tasks: [Task]) async {
        value.requestSync(tasks: tasks, activeLists: [TaskList.inbox.name]); await value.waitForSync()
    }

    func testMappingPreservesPointAndIndependentDeadlineAcrossCalendarMove() throws {
        let source = task()
        let exported = try XCTUnwrap(CalendarTaskMapping.export(source, reference: .init(taskID: source.id), duration: 30, calendar: calendar))
        XCTAssertEqual(exported.fields.end.timeIntervalSince(exported.fields.start), 1800)
        var moved = exported.fields; moved.start.addTimeInterval(3600); moved.end.addTimeInterval(3600)
        let restored = CalendarTaskMapping.schedule(from: moved, original: source.schedule, baseline: exported.fields,
            derivedDuration: true, calendar: calendar)
        XCTAssertNil(restored.dueEndAt)
        XCTAssertEqual(restored.deadlineAt, source.schedule.deadlineAt)
        var allDay = source; allDay.schedule.hasTime = false
        allDay.schedule.dueEndAt = calendar.date(byAdding: .day, value: 2, to: source.schedule.dueAt!)
        let span = try XCTUnwrap(CalendarTaskMapping.export(allDay, reference: .init(taskID: source.id), duration: 30, calendar: calendar))
        XCTAssertEqual(calendar.dateComponents([.day], from: span.fields.start, to: span.fields.end).day, 3)
    }

    func testMacAllDayEndBoundaryRoundTripsWithoutAddingAnotherDay() throws {
        let start = calendar.startOfDay(for: now)
        let exclusive = calendar.date(byAdding: .day, value: 1, to: start)!
        let systemEnd = EventKitDayBoundary.systemEnd(exclusiveEnd: exclusive)
        XCTAssertTrue(calendar.isDate(systemEnd, inSameDayAs: start))
        XCTAssertEqual(EventKitDayBoundary.exclusiveEnd(systemEnd: systemEnd, calendar: calendar), exclusive)
        var source = task(); source.schedule = .init(dueAt: start)
        let exported = try XCTUnwrap(CalendarTaskMapping.export(source, reference: .init(taskID: source.id), duration: 30, calendar: calendar))
        let normalized = EventKitDayBoundary.exclusiveEnd(systemEnd: EventKitDayBoundary.systemEnd(exclusiveEnd: exported.fields.end), calendar: calendar)
        XCTAssertEqual(normalized, exported.fields.end)
        XCTAssertEqual(CalendarTaskMapping.schedule(from: exported.fields, original: source.schedule,
            baseline: exported.fields, derivedDuration: true, calendar: calendar), source.schedule)
    }

    func testAllDaySeriesRetainsItsDateWhenCalendarUsesAnotherTimeZone() throws {
        var seriesCalendar = calendar; seriesCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var source = task(); source.schedule = .init(dueAt: seriesCalendar.startOfDay(for: now))
        source.recurrence = .daily; source.series = TaskSeries(task: source, calendar: seriesCalendar, now: now)
        let exported = try XCTUnwrap(CalendarTaskMapping.export(source, reference: .init(taskID: source.id), duration: 30, calendar: calendar))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: exported.fields.start),
                       seriesCalendar.dateComponents([.year, .month, .day], from: source.schedule.dueAt!))
        let restored = CalendarTaskMapping.schedule(from: exported.fields, original: source.schedule, baseline: exported.fields,
            derivedDuration: true, calendar: seriesCalendar, eventCalendar: calendar)
        XCTAssertEqual(restored, source.schedule)
    }

    func testCreateMoveCompleteDeleteAndUndoKeepOneEvent() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemCalendarClient(); let value = coordinator(folder, client); var source = task()
        await sync(value, [source]); XCTAssertEqual(client.values.count, 1)
        let eventID = try XCTUnwrap(client.values.first?.key)
        source.schedule.dueAt!.addTimeInterval(3600)
        await sync(value, [source]); XCTAssertEqual(client.values.count, 1)
        XCTAssertEqual(client.values[eventID]?.fields.start, source.schedule.dueAt)
        source.status = .completed; await sync(value, [source])
        XCTAssertTrue(client.values[eventID]!.fields.title.hasPrefix("[已完成]"))
        source.deletedAt = now; await sync(value, [source]); XCTAssertTrue(client.values.isEmpty)
        source.deletedAt = nil; source.status = .active; await sync(value, [source])
        XCTAssertEqual(client.values.count, 1)
    }

    func testBindingPersistsAcrossRestartAndRepairsChangedEventIdentifier() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemCalendarClient(); let value = coordinator(folder, client); let source = task()
        await sync(value, [source])
        await withCheckedContinuation { continuation in value.flush { _ in continuation.resume() } }
        var event = try XCTUnwrap(client.values.values.first); client.values.removeAll()
        event.id = "refreshed-event"; client.values[event.id] = event
        let restored = CalendarSyncCoordinator(directory: folder, client: client, clock: { self.now }, calendar: calendar)
        await sync(restored, [source])
        XCTAssertEqual(client.values.count, 1)
        XCTAssertEqual(restored.store.snapshot.bindings.first?.eventID, event.id)
    }

    func testExternalDeleteDetachesWithoutDeletingTaskOrRecreatingEvent() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemCalendarClient(); let value = coordinator(folder, client); let source = task()
        await sync(value, [source]); client.values.removeAll()
        await sync(value, [source]); await sync(value, [source])
        XCTAssertTrue(client.values.isEmpty)
        XCTAssertEqual(value.store.snapshot.bindings.first?.detached, true)
        XCTAssertNil(source.deletedAt)
        value.reconnect(source); await sync(value, [source]); XCTAssertEqual(client.values.count, 1)
    }

    func testBidirectionalMoveUsesSharedTaskActionAndOneUndo() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemCalendarClient(); let value = coordinator(folder, client); let source = task()
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, initialTasks: [source])
        value.store.configure { $0.bidirectional = true }
        value.applyExternal = { reference, fields, base, derived in
            guard let occurrence = CalendarTaskReference.resolve(reference, tasks: workspace.allTasks, calendar: self.calendar) else { return false }
            let schedule = CalendarTaskMapping.schedule(from: fields, original: occurrence.task.schedule,
                baseline: base, derivedDuration: derived, calendar: self.calendar)
            return workspace.applyCalendarEdit(occurrence, title: fields.title, schedule: schedule).taskID != nil
        }
        await sync(value, workspace.allTasks)
        let id = try XCTUnwrap(client.values.keys.first)
        client.values[id]!.fields.title = "日历改名"
        client.values[id]!.fields.start.addTimeInterval(3600); client.values[id]!.fields.end.addTimeInterval(3600)
        await sync(value, workspace.allTasks)
        XCTAssertEqual(workspace.task(for: source.id)?.title, "日历改名")
        XCTAssertEqual(workspace.task(for: source.id)?.schedule.dueAt, source.schedule.dueAt?.addingTimeInterval(3600))
        workspace.undo()
        XCTAssertEqual(workspace.task(for: source.id)?.title, source.title)
        XCTAssertEqual(workspace.task(for: source.id)?.schedule, source.schedule)
        await sync(value, workspace.allTasks)
        XCTAssertEqual(client.values[id]?.fields.title, source.title)
    }

    func testConcurrentEditsPresentConflictAndExplicitChoiceResolvesIt() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemCalendarClient(); let value = coordinator(folder, client); var source = task()
        value.store.configure { $0.bidirectional = true }
        await sync(value, [source]); let id = try XCTUnwrap(client.values.keys.first)
        source.title = "任务改名"; client.values[id]!.fields.title = "日历改名"
        await sync(value, [source])
        XCTAssertEqual(value.conflicts.count, 1)
        XCTAssertEqual(client.values[id]?.fields.title, "日历改名")
        value.resolve(try XCTUnwrap(value.conflicts.first), useCalendar: false)
        await sync(value, [source])
        XCTAssertTrue(value.conflicts.isEmpty)
        XCTAssertEqual(client.values[id]?.fields.title, "任务改名")
    }

    func testExternalEventAndTaskShareLayoutWithoutLosingTheirIdentities() throws {
        let source = task(); let day = calendar.startOfDay(for: source.schedule.dueAt!)
        let tasks = CalendarProjection.timed(on: day, tasks: [source], preferences: .init(), calendar: calendar)
        let event = SystemCalendarEvent(id: "meeting", calendarID: "calendar", fields: .init(title: "会议", start: source.schedule.dueAt!,
            end: source.schedule.dueAt!.addingTimeInterval(3600), allDay: false), location: "", calendarTitle: "工作", colorARGB: 0xff0000ff)
        let layout = ExternalCalendarProjection.timed(on: day, tasks: tasks, events: [event], calendar: calendar)
        XCTAssertEqual(layout.tasks.first?.laneCount, 2)
        XCTAssertEqual(layout.events.first?.laneCount, 2)
        XCTAssertNotEqual(layout.tasks.first?.lane, layout.events.first?.lane)
        XCTAssertEqual(layout.tasks.first?.task.id, source.id)
        XCTAssertEqual(layout.events.first?.event.id, event.id)
    }

    func testCalendarOccurrenceLinkAndEditAffectOnlyThatPeriodAndUndoMaterialization() throws {
        var source = task(); source.recurrence = .daily
        source.series = TaskSeries(task: source, calendar: calendar, now: now)
        source.occurrenceKey = source.series!.initialKey
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, initialTasks: [source])
        let range = DateInterval(start: now, end: now.addingTimeInterval(4 * 86400))
        let ghost = try XCTUnwrap(TaskOccurrenceProjection.occurrences(tasks: workspace.allTasks, in: range, calendar: calendar)
            .first { $0.isVirtual })
        let reference = CalendarTaskReference(taskID: ghost.sourceTaskID, occurrence: ghost.key)
        XCTAssertEqual(CalendarTaskReference(url: reference.url), reference)
        let resolved = try XCTUnwrap(CalendarTaskReference.resolve(reference, tasks: workspace.allTasks, calendar: calendar))
        XCTAssertEqual(resolved.key, ghost.key)
        XCTAssertNotNil(workspace.applyCalendarEdit(resolved, title: "仅修改这一周期", schedule: resolved.task.schedule).taskID)
        let following = TaskOccurrenceProjection.occurrences(tasks: workspace.allTasks, in: range, calendar: calendar)
        XCTAssertEqual(following.first { $0.key == ghost.key }?.task.title, "仅修改这一周期")
        XCTAssertTrue(following.filter { $0.key != ghost.key }.allSatisfy { $0.task.title == source.title })
        workspace.undo()
        XCTAssertEqual(workspace.allTasks.count, 1)
        XCTAssertEqual(workspace.task(for: source.id)?.title, source.title)
    }
}

@MainActor
final class FakeSystemCalendarClient: SystemCalendarClient {
    var authorization: EKAuthorizationStatus = .fullAccess
    var values: [String: SystemCalendarEvent] = [:]
    var onChange: (() -> Void)?
    func requestAccess() async throws -> Bool { true }
    func calendars() -> [SystemCalendarInfo] { [.init(id: "test-calendar", title: "验收", colorARGB: 0xff0000ff, writable: true)] }
    func createCalendar(title: String) throws -> SystemCalendarInfo { calendars()[0] }
    func events(in range: DateInterval, calendarIDs: [String]) -> [SystemCalendarEvent] {
        values.values.filter { calendarIDs.contains($0.calendarID) && $0.fields.start < range.end && $0.fields.end > range.start }
    }
    func event(id: String) -> SystemCalendarEvent? { values[id] }
    func save(_ fields: CalendarEventFields, calendarID: String, sourceURL: URL, notes: String, timeZone: TimeZone,
              existingID: String?) throws -> SystemCalendarEvent {
        let id = existingID ?? UUID().uuidString
        let value = SystemCalendarEvent(id: id, calendarID: calendarID, fields: fields, sourceURL: sourceURL,
            location: "", calendarTitle: "验收", colorARGB: 0xff0000ff)
        values[id] = value; return value
    }
    func remove(id: String) throws { values.removeValue(forKey: id) }
}
