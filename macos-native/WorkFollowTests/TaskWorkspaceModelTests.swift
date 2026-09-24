import XCTest
@testable import WorkFollow

final class TaskWorkspaceModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testCreateTodayAndInboxUseDistinctRealSchedulesAndCounts() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar, seedDemoData: false)
            let initial = model.count(for: TaskListScope.today)
            let today = model.createTask(title: "Today task", in: .today).taskID!
            XCTAssertEqual(model.count(for: TaskListScope.today), initial + 1)
            XCTAssertEqual(model.selectedTask?.id, nil)
            XCTAssertEqual(model.task(for: today)?.schedule.dueAt, self.calendar.startOfDay(for: self.now))
            XCTAssertEqual(model.task(for: today)?.list, .inbox)

            let inbox = model.createTask(title: "Inbox task", in: .inbox).taskID!
            XCTAssertNil(model.task(for: inbox)?.schedule.dueAt)
            XCTAssertEqual(model.count(for: TaskListScope.inbox), 2)
        }
    }

    func testCompleteAndRestoreUpdateOpenCountAndKeepTodayCompletedGroup() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar, seedDemoData: false)
            let id = model.createTask(title: "task", in: .today).taskID!
            XCTAssertEqual(model.count(for: TaskListScope.today), 1)
            _ = model.complete(id, in: .today)
            XCTAssertEqual(model.task(for: id)?.status, .completed)
            XCTAssertEqual(model.count(for: TaskListScope.today), 0)
            XCTAssertTrue(model.groups(for: .today).contains {
                $0.kind == .completed && $0.tasks.contains { $0.id == id }
            })
            XCTAssertEqual(model.count(for: TaskListScope.completed), 1)
            _ = model.restore(id, in: .today)
            XCTAssertEqual(model.task(for: id)?.status, .active)
            XCTAssertEqual(model.count(for: TaskListScope.today), 1)
            XCTAssertFalse(model.groups(for: .today).contains { $0.kind == .completed })
        }
    }

    func testCompletedInboxTaskStaysOnInboxAndInClosedGroup() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar, seedDemoData: false)
            let id = model.createTask(title: "inbox", in: .inbox).taskID!
            _ = model.complete(id, in: .inbox)
            XCTAssertEqual(model.count(for: TaskListScope.inbox), 0)
            XCTAssertTrue(model.groups(for: .inbox).contains {
                $0.kind == .completed && $0.tasks.contains { $0.id == id }
            })
        }
    }

    func testParentAndMatchingChildrenFlattenOnceAndExpandFromProjection() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar, seedDemoData: false)
            let parent = model.createTask(title: "parent", in: .today).taskID!
            let child = model.createChild(parent, title: "child").taskID!
            // Parent's schedule is today; add today's schedule to the child through the model action path.
            _ = model.setSchedule(child, TaskSchedule(dueAt: self.calendar.startOfDay(for: self.now)))
            let group = model.groups(for: .today).first!
            model.toggleExpanded(parent)
            let nodes = model.nodes(for: group, scope: .today)
            XCTAssertEqual(nodes.map(\.task.id), [parent, child])
            XCTAssertEqual(nodes.map(\.depth), [0, 1])
        }
    }

    func testOnlyMatchingChildIsPromotedToRoot() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar, seedDemoData: false)
            let parent = model.createTask(title: "undated parent", in: .inbox).taskID!
            let child = model.createChild(parent, title: "today child").taskID!
            _ = model.setSchedule(child, TaskSchedule(dueAt: self.calendar.startOfDay(for: self.now)))
            let nodes = model.visibleNodes(for: .today)
            XCTAssertEqual(nodes.map(\.task.id), [child])
            XCTAssertEqual(nodes.first?.depth, 0)
        }
    }

    func testParentMoveCarriesChildAndIndependentChildMoveFailsWithoutMutation() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar, seedDemoData: false)
            let parent = model.createTask(title: "parent", in: .inbox).taskID!
            let child = model.createChild(parent, title: "child").taskID!
            let before = [model.task(for: parent)!, model.task(for: child)!]
            XCTAssertEqual(model.moveToList(child, TaskList(name: "个人")), .failure(.childListMoveNotSupported))
            XCTAssertEqual([model.task(for: parent)!, model.task(for: child)!], before)
            _ = model.moveToList(parent, TaskList(name: "工作"))
            XCTAssertEqual(model.task(for: child)?.list, TaskList(name: "工作"))
        }
    }

    func testSelectionAndExpandedStateStayInPresentationModel() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar)
            let rows = model.visibleNodes(for: .today)
            XCTAssertFalse(rows.isEmpty)
            model.selectAdjacent(1, in: .today)
            XCTAssertEqual(model.selectedTaskID, rows[0].task.id)
            model.selectAdjacent(1, in: .today)
            XCTAssertEqual(model.selectedTaskID, rows[1].task.id)
            model.toggleExpanded(rows[0].task.id)
            XCTAssertFalse(model.expandedTaskIDs.contains(rows[0].task.id))
        }
    }

    func testInspectorTitleAndPriorityActionsUpdateSelectedDomainTask() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                           seedDemoData: false)
            let id = model.createTask(title: "Before", in: .inbox).taskID!
            model.select(id)

            _ = model.setTitle(id, "Edited title")
            _ = model.setPriority(id, .high)

            XCTAssertEqual(model.selectedTask?.title, "Edited title")
            XCTAssertEqual(model.selectedTask?.priority, .high)
        }
    }

    func testInspectorDocumentActionUpdatesTheSelectedDomainTask() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                           seedDemoData: false)
            let id = model.createTask(title: "Document task", in: .inbox).taskID!
            model.select(id)
            let document = NativeDocument(plainText: "First paragraph\nSecond paragraph")

            _ = model.setDocument(id, document)

            XCTAssertEqual(model.selectedTask?.document, document)
            XCTAssertEqual(model.selectedTask?.document.plainText,
                           "First paragraph\nSecond paragraph")
        }
    }

    func testTaskDocumentsRemainIsolatedWhenSelectionSwitchesBetweenTasks() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                           seedDemoData: false)
            let firstID = model.createTask(title: "First", in: .inbox).taskID!
            let secondID = model.createTask(title: "Second", in: .inbox).taskID!
            let firstDocument = NativeDocument(plainText: "First task details")
            let secondDocument = NativeDocument(plainText: "Second task details")

            _ = model.setDocument(firstID, firstDocument)
            model.select(firstID)
            _ = model.setDocument(secondID, secondDocument)
            model.select(secondID)
            XCTAssertEqual(model.selectedTask?.document, secondDocument)
            model.select(firstID)
            XCTAssertEqual(model.selectedTask?.document, firstDocument)
            XCTAssertEqual(model.task(for: secondID)?.document, secondDocument)
        }
    }

    func testDueDateAndDeadlineActionsPreserveIndependentScheduleFields() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                           seedDemoData: false)
            let id = model.createTask(title: "Scheduled", in: .inbox).taskID!
            let due = model.dateFromToday(1)
            let deadline = model.dateFromToday(7)
            _ = model.setSchedule(id, TaskSchedule(dueAt: self.now, hasTime: true,
                                                   deadlineAt: deadline))

            _ = model.setDueDate(id, due)
            XCTAssertEqual(model.task(for: id)?.schedule.dueAt, due)
            XCTAssertFalse(model.task(for: id)?.schedule.hasTime ?? true)
            XCTAssertEqual(model.task(for: id)?.schedule.deadlineAt, deadline)

            _ = model.setDeadline(id, nil)
            XCTAssertEqual(model.task(for: id)?.schedule.dueAt, due)
            XCTAssertNil(model.task(for: id)?.schedule.deadlineAt)
        }
    }

    func testSelectedInspectorTaskReflectsCompleteAndRestoreActions() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                           seedDemoData: false)
            let id = model.createTask(title: "Selected", in: .today).taskID!
            model.select(id)

            _ = model.changeStatus(model.selectedTask!)
            XCTAssertEqual(model.selectedTaskID, id)
            XCTAssertEqual(model.selectedTask?.status, .completed)
            _ = model.changeStatus(model.selectedTask!)
            XCTAssertEqual(model.selectedTask?.status, .active)
        }
    }

    func testOnlyParentTasksCanChangeListAndDeleteClearsSelectedInspector() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                           seedDemoData: false)
            let parent = model.createTask(title: "Parent", in: .inbox).taskID!
            let child = model.createChild(parent, title: "Child").taskID!
            XCTAssertTrue(model.canMoveToList(parent))
            XCTAssertFalse(model.canMoveToList(child))

            model.select(parent)
            _ = model.delete(parent)
            XCTAssertNil(model.selectedTaskID)
            XCTAssertEqual(model.task(for: parent)?.deletedAt, self.now)
            XCTAssertEqual(model.task(for: child)?.deletedAt, self.now)
        }
    }
}
