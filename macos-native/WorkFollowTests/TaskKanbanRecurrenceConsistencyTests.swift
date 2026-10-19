import XCTest
@testable import WorkFollow

@MainActor
final class TaskKanbanRecurrenceConsistencyTests: XCTestCase {
    private enum SectionEdit: CaseIterable { case kanbanSection, sectionMenu, kanbanList }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }

    private func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func repeatedTask() -> Task {
        var task = Task(id: UUID(), title: "每日评审", recurrence: .daily,
            list: TaskList(name: "工作"), priority: .low,
            schedule: TaskSchedule(dueAt: date(19, 9), hasTime: true),
            childOrder: 0, createdAt: date(19), updatedAt: date(19))
        task.sectionID = "planned"
        return task
    }

    private func workspace(_ task: Task) -> TaskWorkspaceModel {
        TaskWorkspaceModel(clock: { self.date(19, 12) }, calendar: calendar,
            seedDemoData: false, initialTasks: [task], initialLists: ["工作", "个人"],
            initialListSections: [
                TaskListSection(id: "planned", listName: "工作", title: "计划"),
                TaskListSection(id: "review", listName: "工作", title: "评审", sortOrder: 1)
            ])
    }

    private func tomorrowOccurrence(in workspace: TaskWorkspaceModel) throws -> TaskOccurrence {
        let occurrences = TaskOccurrenceProjection.occurrences(tasks: workspace.allTasks,
            in: DateInterval(start: date(20), end: date(21)), calendar: calendar)
        let occurrence = try XCTUnwrap(occurrences.first { $0.key.ordinal == 1 })
        XCTAssertTrue(occurrence.isVirtual)
        XCTAssertEqual(occurrence.task.schedule.dueAt, date(20, 9))
        return occurrence
    }

    func testPriorityDropKeepsProjectedAndCompletedNextOccurrenceConsistent() throws {
        for usesAttributeEditor in [false, true] {
            let source = repeatedTask()
            let workspace = workspace(source)
            let original = try XCTUnwrap(workspace.task(for: source.id))

            if usesAttributeEditor {
                XCTAssertNotNil(workspace.updateAttributes(source.id, priority: .high).taskID)
            } else {
                XCTAssertTrue(workspace.applyKanbanDrop(source.id, to: .priority(.high),
                    insertion: nil, columnTaskIDs: []))
            }
            XCTAssertEqual(workspace.task(for: source.id)?.priority, .high)
            let projected = try tomorrowOccurrence(in: workspace)
            XCTAssertEqual(projected.task.priority, .high)

            workspace.undo()
            XCTAssertEqual(workspace.task(for: source.id), original)
            XCTAssertEqual(try tomorrowOccurrence(in: workspace).task.priority, .low)
            XCTAssertFalse(workspace.canUndo)
            workspace.redo()
            XCTAssertEqual(try tomorrowOccurrence(in: workspace).task.priority, .high)

            let nextID = try XCTUnwrap(workspace.complete(source.id).taskID)
            let next = try XCTUnwrap(workspace.task(for: nextID))
            XCTAssertEqual(next.occurrenceKey, projected.key)
            XCTAssertEqual(next.priority, .high)
            XCTAssertEqual(projected.task.priority, next.priority,
                "完成今天不应改变同一明日实例原先预览的优先级")
        }
    }

    func testSectionDropKeepsProjectedAndCompletedNextOccurrenceConsistent() throws {
        for operation in SectionEdit.allCases {
            let source = repeatedTask()
            let workspace = workspace(source)
            let original = try XCTUnwrap(workspace.task(for: source.id))
            let expectedSection: String? = operation == .kanbanList ? nil : "review"
            let expectedList = operation == .kanbanList ? "个人" : "工作"

            if operation == .sectionMenu {
                XCTAssertNotNil(workspace.setTaskSection(source.id, sectionID: "review").taskID)
            } else {
                let target: TaskKanbanCreationTarget = operation == .kanbanList ? .list("个人")
                    : .section(list: "工作", sectionID: "review")
                XCTAssertTrue(workspace.applyKanbanDrop(source.id, to: target,
                    insertion: nil, columnTaskIDs: []))
            }
            XCTAssertEqual(workspace.task(for: source.id)?.sectionID, expectedSection)
            let projected = try tomorrowOccurrence(in: workspace)
            XCTAssertEqual(projected.task.sectionID, expectedSection)
            XCTAssertEqual(projected.task.list.name, expectedList)

            workspace.undo()
            XCTAssertEqual(workspace.task(for: source.id), original)
            XCTAssertEqual(try tomorrowOccurrence(in: workspace).task.sectionID, "planned")
            XCTAssertFalse(workspace.canUndo)
            workspace.redo()
            XCTAssertEqual(try tomorrowOccurrence(in: workspace).task.sectionID, expectedSection)

            let nextID = try XCTUnwrap(workspace.complete(source.id).taskID)
            let next = try XCTUnwrap(workspace.task(for: nextID))
            XCTAssertEqual(next.occurrenceKey, projected.key)
            XCTAssertEqual(next.sectionID, expectedSection)
            XCTAssertEqual(next.list.name, expectedList)
            XCTAssertEqual(projected.task.sectionID, next.sectionID,
                "完成今天不应改变同一明日实例原先预览的分组")
        }
    }
}
