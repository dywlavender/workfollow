import XCTest
@testable import WorkFollow

@MainActor
final class TaskKanbanCreationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 28_800)!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 12))!
    }

    private func task(_ title: String, due: Date?, priority: TaskPriority = .none,
                      list: String = "工作", tags: [String] = []) -> Task {
        var task = Task(id: UUID(), title: title, list: TaskList(name: list), priority: priority,
                        schedule: TaskSchedule(dueAt: due), parentID: nil, childOrder: 0,
                        createdAt: now, updatedAt: now)
        task.tags = tags
        return task
    }

    func testProjectionSuppliesTypedCreationTargetsWithoutUsingHeadingText() throws {
        let today = calendar.startOfDay(for: now)
        let store = WorkspaceStore()
        let scheduled = task("今天任务", due: today, priority: .high, tags: ["设计"])
        let undated = task("无日期任务", due: nil, priority: .low, list: "产品")
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let later = calendar.date(byAdding: .day, value: 10, to: today)!
        store.commit([scheduled, undated, task("过期任务", due: yesterday), task("稍后任务", due: later)])

        func groups(_ grouping: TaskListGrouping) -> [TaskListGroup] {
            TaskListProjection.groups(in: .allTasks, store: store, now: now,
                                      calendar: calendar, grouping: grouping)
        }
        let dated = groups(.byDate)
        XCTAssertEqual(dated.first { $0.kind == .today }?.creationTarget, .schedule(today))
        XCTAssertEqual(dated.first { $0.kind == .undated }?.creationTarget, .schedule(nil))
        XCTAssertNil(dated.first { $0.kind == .overdue }?.creationTarget)
        XCTAssertNil(dated.first { $0.kind == .later }?.creationTarget)
        XCTAssertEqual(groups(.byPriority).first { $0.tasks.contains { $0.id == scheduled.id } }?.creationTarget,
                       .priority(.high))
        XCTAssertEqual(groups(.byList).first { $0.tasks.contains { $0.id == undated.id } }?.creationTarget,
                       .list("产品"))
        XCTAssertEqual(groups(.byTag).first { $0.tasks.contains { $0.id == scheduled.id } }?.creationTarget,
                       .tag("设计"))
        XCTAssertEqual(groups(.byTag).first { $0.tasks.contains { $0.id == undated.id } }?.creationTarget,
                       .tag(nil))
        XCTAssertFalse(groups(.byCreatedAt).isEmpty)
        XCTAssertTrue(groups(.byCreatedAt).allSatisfy { $0.creationTarget == nil },
                      "按创建日分组的今天标题不能被误认为安排日期")
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        store.commit(store.tasks + [task("明天任务", due: tomorrow)])
        let days = TaskListProjection.groups(in: .nextSevenDays, store: store, now: now,
                                             calendar: calendar)
        XCTAssertEqual(days.first { $0.day == tomorrow }?.creationTarget, .schedule(tomorrow))
    }

    func testEmptyCustomColumnCreationAndAttributesHaveOneUndoAndRedo() throws {
        let section = TaskListSection(id: "review", listName: "工作", title: "高优先级")
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar,
            seedDemoData: false, initialTasks: [], initialLists: ["工作"], initialListSections: [section])
        workspace.activeList = "工作"
        let groups = workspace.groups(for: .allTasks, query: TaskListQuery(list: "工作"))
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].tasks.isEmpty)
        XCTAssertEqual(groups[0].creationTarget, .section(list: "工作", sectionID: "review"))
        let target = try XCTUnwrap(groups[0].creationTarget)
        let id = try XCTUnwrap(workspace.createKanbanTask(title: "列内添加验收", target: target))
        let created = try XCTUnwrap(workspace.task(for: id))
        XCTAssertEqual(created.list.name, "工作")
        XCTAssertEqual(created.sectionID, "review")
        XCTAssertEqual(created.priority, .none, "分组标题恰好是优先级文案，不改变其类型")
        XCTAssertEqual(workspace.selectedTaskID, id)
        workspace.undo()
        XCTAssertTrue(workspace.allTasks.isEmpty)
        XCTAssertFalse(workspace.canUndo, "创建和属性归属必须只有一步撤销")
        workspace.redo()
        XCTAssertEqual(workspace.task(for: id), created)
    }

    func testDateColumnDefaultsPreserveExplicitCaptureFields() throws {
        let today = calendar.startOfDay(for: now)
        let existing = task("已有的今天任务", due: today)
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar,
                                           seedDemoData: false, initialTasks: [existing])
        let todayGroup = try XCTUnwrap(workspace.groups(for: .allTasks).first { $0.kind == .today })
        let target = try XCTUnwrap(todayGroup.creationTarget)
        let defaultID = try XCTUnwrap(workspace.createKanbanTask(
            title: "上午9点 列内默认日期", target: target))
        let defaultDue = try XCTUnwrap(workspace.task(for: defaultID)?.schedule.dueAt)
        XCTAssertEqual(calendar.startOfDay(for: defaultDue), today)
        XCTAssertEqual(calendar.component(.hour, from: defaultDue), 9)
        workspace.undo()
        XCTAssertEqual(workspace.allTasks.map(\.id), [existing.id])

        let id = try XCTUnwrap(workspace.createKanbanTask(
            title: "明天上午9点 看板验收", target: target))
        let task = try XCTUnwrap(workspace.task(for: id))
        let due = try XCTUnwrap(task.schedule.dueAt)
        XCTAssertEqual(calendar.startOfDay(for: due), calendar.date(byAdding: .day, value: 1, to: today))
        XCTAssertEqual(calendar.component(.hour, from: due), 9)
        XCTAssertTrue(task.schedule.hasTime)
        workspace.undo()
        XCTAssertEqual(workspace.allTasks.map(\.id), [existing.id])
        XCTAssertFalse(workspace.canUndo)
    }
}
