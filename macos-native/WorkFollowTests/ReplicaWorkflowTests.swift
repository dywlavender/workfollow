import XCTest
@testable import WorkFollow

@MainActor
final class ReplicaWorkflowTests: XCTestCase {
    func testAcceptanceClockKeepsTimeAdvancingFromFixtureDate() throws {
        var wall = Date(timeIntervalSince1970: 100)
        let clock = NativeAcceptanceConfiguration.clock(
            reference: "2026-10-13T12:00:00+08:00", wallClock: { wall })
        let anchor = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-13T12:00:00+08:00"))
        XCTAssertEqual(clock(), anchor)
        wall += 90
        XCTAssertEqual(clock(), anchor.addingTimeInterval(90))
    }

    func testRecordTaskLinkLeavesOldScopeAndRetainsEditorSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("replica-link-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let id = try XCTUnwrap(environment.taskWorkspace.createTask(title: "复盘关联任务", in: .inbox).taskID)
        environment.taskWorkspace.activeList = "旧清单"
        environment.taskWorkspace.activeTag = "旧标签"
        environment.navigation.destination = .focus

        environment.openTask(id)

        XCTAssertEqual(environment.navigation.destination, .allTasks)
        XCTAssertEqual(environment.taskWorkspace.selectedTaskID, id)
        XCTAssertEqual(environment.navigation.taskSelectionToPreserveOnNextNavigation, id)
        XCTAssertNil(environment.taskWorkspace.activeList)
        XCTAssertNil(environment.taskWorkspace.activeTag)
        XCTAssertNil(environment.taskWorkspace.activeFilterID)
    }

    func testTaskFocusEntryPreservesTheSameTaskAcrossNavigation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("replica-focus-link-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let id = try XCTUnwrap(environment.taskWorkspace.createTask(title: "任务投入", in: .inbox).taskID)

        environment.startFocus(for: id)

        XCTAssertEqual(environment.navigation.destination, .focus)
        XCTAssertEqual(environment.navigation.taskSelectionToPreserveOnNextNavigation, id)
        XCTAssertEqual(environment.focusStore.currentTaskID, id)
        _ = environment.focusStore.giveUp()
    }

    func testProjectedPeriodFocusUsesADurableTaskRelation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("replica-period-focus-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-13T12:00:00+08:00"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let environment = AppEnvironment(clock: { now }, calendar: calendar, directory: directory)
        let workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createDraft(title: "周期任务投入", list: "工作",
            schedule: TaskSchedule(dueAt: calendar.startOfDay(for: now)), priority: .medium,
            tags: [], reminder: nil, repeatFrequency: .daily).taskID)
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let window = try XCTUnwrap(calendar.dateInterval(of: .day, for: nextDay))
        let occurrence = try XCTUnwrap(TaskOccurrenceProjection.occurrences(
            tasks: workspace.allTasks, in: window, calendar: calendar).first { $0.isVirtual && $0.sourceTaskID == id })
        let count = workspace.allTasks.count
        workspace.selectOccurrence(occurrence)
        XCTAssertEqual(workspace.allTasks.count, count)

        environment.startFocus(for: occurrence.task.id)

        let resolvedID = try XCTUnwrap(environment.focusStore.currentTaskID)
        XCTAssertNotEqual(resolvedID, id)
        XCTAssertEqual(workspace.allTasks.count, count + 1)
        XCTAssertEqual(workspace.task(for: resolvedID)?.occurrenceKey, occurrence.key)
        XCTAssertEqual(environment.navigation.taskSelectionToPreserveOnNextNavigation, resolvedID)
        XCTAssertEqual(environment.navigation.destination, .focus)
        _ = environment.focusStore.giveUp()
    }

    func testTaskConversionRedoRestoresTheSameNoteAndChecklist() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("replica-conversion-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "交付复盘", in: .inbox).taskID)
        _ = workspace.createChild(id, title: "记录验收结果")
        let before = workspace.allTasks
        let noteID = try XCTUnwrap(environment.convertTaskToNote(id))
        let after = workspace.allTasks
        let note = try XCTUnwrap(environment.notesWorkspace.notes.first { $0.id == noteID })

        workspace.undo()
        XCTAssertEqual(workspace.allTasks, before)
        XCTAssertFalse(environment.notesWorkspace.notes.contains { $0.id == noteID })
        XCTAssertTrue(workspace.canRedo)
        workspace.redo()
        XCTAssertEqual(workspace.allTasks, after)
        XCTAssertEqual(environment.notesWorkspace.notes.first { $0.id == noteID }, note)
    }
}
