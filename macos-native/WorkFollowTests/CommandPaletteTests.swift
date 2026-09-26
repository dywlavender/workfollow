import XCTest
@testable import WorkFollow

final class CommandPaletteTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testEmptyPaletteLeadsWithCreateEntryFollowedByAllCommands() {
        let entries = CommandPaletteProjection.entries(
            query: "  ", tasks: [], notes: [], creationList: "收集箱",
            schedulesForToday: false, now: now, calendar: calendar)

        // 首项恒为"新建任务"，其后是完整命令区（Flutter 命令全集）。
        XCTAssertEqual(entries.count, 10)
        XCTAssertEqual(entries.first?.kind, .createTask)
        XCTAssertEqual(entries.first?.title, "新建任务")
        XCTAssertEqual(entries.first?.subtitle, "保存到收集箱")
        XCTAssertEqual(entries.first?.action, .createTask(""))
        XCTAssertEqual(entries.dropFirst().map(\.title),
                       ["打开最近 7 天", "打开今天", "打开收集箱", "打开所有任务",
                        "打开日历", "打开笔记", "打开任务垃圾桶", "打开笔记垃圾桶", "切换外观"])
        XCTAssertFalse(entries.contains { $0.title == "已完成" || $0.title == "四象限" })
    }

    func testCreateEntryAnnouncesTodayScheduleInTodayContext() {
        let entries = CommandPaletteProjection.entries(
            query: "", tasks: [], notes: [], creationList: "收集箱",
            schedulesForToday: true, now: now, calendar: calendar)

        XCTAssertEqual(entries.first?.subtitle, "保存到收集箱 · 安排到今天")
    }

    func testSearchOffersCreateTaskThenMatchingTasksNotesAndCommands() async {
        await MainActor.run {
            let tasks = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar, seedDemoData: false)
            let matchingTask = tasks.createTask(title: "search title", in: .inbox).taskID!
            let bodyMatch = tasks.createTask(title: "different", in: .inbox).taskID!
            _ = tasks.setDocument(bodyMatch, NativeDocument(plainText: "search body"))
            tasks.setTags(bodyMatch, ["search-tag"])
            _ = tasks.delete(tasks.createTask(title: "search deleted", in: .inbox).taskID!)

            let notes = NotesWorkspaceModel(clock: { self.now })
            notes.create()
            let matchingNote = notes.selectedID!
            notes.edit(matchingNote) {
                $0.title = "search note"
                $0.folder = "学习"
            }
            notes.create()
            let deletedNote = notes.selectedID!
            notes.delete(deletedNote)

            let entries = CommandPaletteProjection.entries(
                query: " search ", tasks: tasks.allTasks, notes: notes.notes,
                creationList: "收集箱", schedulesForToday: false,
                now: self.now, calendar: self.calendar)

            XCTAssertEqual(entries.first?.title, "新建任务「search」")
            XCTAssertEqual(entries.first?.kind, .createTask)
            XCTAssertEqual(entries.first?.action, .createTask("search"))
            XCTAssertTrue(entries.contains { $0.id == "task-\(matchingTask.uuidString)" })
            XCTAssertTrue(entries.contains { $0.id == "task-\(bodyMatch.uuidString)" })
            XCTAssertTrue(entries.contains { $0.id == "note-\(matchingNote.uuidString)" })
            XCTAssertFalse(entries.contains { $0.title == "search deleted" || $0.id == "note-\(deletedNote.uuidString)" })
            let commands = CommandPaletteProjection.entries(
                query: "垃圾桶", tasks: tasks.allTasks, notes: notes.notes,
                creationList: "收集箱", schedulesForToday: false,
                now: self.now, calendar: self.calendar)
            XCTAssertTrue(commands.contains { $0.title == "打开任务垃圾桶" })
        }
    }

    func testSearchTaskResultsAreLimitedToSevenAndNotesToFive() async {
        await MainActor.run {
            let tasks = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar, seedDemoData: false)
            for index in 0..<9 { _ = tasks.createTask(title: "match task \(index)", in: .inbox) }

            let notes = NotesWorkspaceModel(clock: { self.now })
            for index in 0..<7 {
                notes.create()
                if let id = notes.selectedID { notes.edit(id) { $0.title = "match note \(index)" } }
            }

            let entries = CommandPaletteProjection.entries(
                query: "match", tasks: tasks.allTasks, notes: notes.notes,
                creationList: "收集箱", schedulesForToday: false,
                now: self.now, calendar: self.calendar)
            XCTAssertEqual(entries.filter { $0.id.hasPrefix("task-") }.count, 7)
            XCTAssertEqual(entries.filter { $0.id.hasPrefix("note-") }.count, 5)
        }
    }

    func testNextAppearanceCyclesThroughSystemLightAndDark() {
        XCTAssertEqual(CommandPaletteProjection.nextAppearance(after: .system), .light)
        XCTAssertEqual(CommandPaletteProjection.nextAppearance(after: .light), .dark)
        XCTAssertEqual(CommandPaletteProjection.nextAppearance(after: .dark), .system)
    }

    func testOpenTaskRoutesToItsListAndPreservesSelectionAcrossNavigation() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar, seedDemoData: false)
            let id = workspace.createTask(title: "work", in: .inbox).taskID!
            _ = workspace.moveToList(id, TaskList(name: "工作"))
            workspace.activeTag = "old-filter"
            let navigation = AppNavigation()
            navigation.destination = .today

            XCTAssertTrue(CommandPaletteProjection.openTask(id, workspace: workspace, navigation: navigation))
            XCTAssertEqual(navigation.destination, .allTasks)
            XCTAssertEqual(workspace.activeList, "工作")
            XCTAssertNil(workspace.activeTag)
            XCTAssertEqual(workspace.selectedTaskID, id)
            XCTAssertEqual(navigation.taskSelectionToPreserveOnNextNavigation, id)
        }
    }

    func testOpenNoteSelectsExactNoteAndLeavesTrashContext() async {
        await MainActor.run {
            let tasks = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar, seedDemoData: false)
            let taskID = tasks.createTask(title: "selected", in: .inbox).taskID!
            tasks.select(taskID)
            tasks.activeTag = "old-filter"

            let notes = NotesWorkspaceModel(clock: { self.now })
            notes.create()
            let id = notes.selectedID!
            notes.edit(id) { $0.title = "wanted note" }
            let navigation = AppNavigation()
            navigation.destination = .trash

            XCTAssertTrue(CommandPaletteProjection.openNote(id, workspace: notes,
                                                             taskWorkspace: tasks, navigation: navigation))
            XCTAssertEqual(navigation.destination, .notes)
            XCTAssertEqual(notes.selectedID, id)
            XCTAssertNil(tasks.selectedTaskID)
            XCTAssertNil(tasks.activeTag)
        }
    }

    func testCreateTaskUsesCurrentListAndOnlySchedulesTodayContext() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar, seedDemoData: false)
            let navigation = AppNavigation()
            navigation.destination = .today
            workspace.activeList = "工作"

            let todayID = CommandPaletteProjection.createTask(" today task ", workspace: workspace,
                                                               navigation: navigation).taskID!
            XCTAssertEqual(workspace.task(for: todayID)?.list.name, "工作")
            XCTAssertEqual(workspace.task(for: todayID)?.schedule.dueAt,
                           self.calendar.startOfDay(for: self.now))

            navigation.destination = .calendar
            let laterID = CommandPaletteProjection.createTask("unscheduled", workspace: workspace,
                                                               navigation: navigation).taskID!
            XCTAssertEqual(workspace.task(for: laterID)?.list.name, "工作")
            XCTAssertNil(workspace.task(for: laterID)?.schedule.dueAt)
        }
    }

    func testCreateTaskFromEmptyQueryFallsBackToUntitledInCurrentContext() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar, seedDemoData: false)
            let navigation = AppNavigation()

            let id = CommandPaletteProjection.createTask("   ", workspace: workspace,
                                                         navigation: navigation).taskID!
            XCTAssertEqual(workspace.task(for: id)?.title, "无标题")
            XCTAssertEqual(workspace.task(for: id)?.list.name, "收集箱")
            // 默认目的地是"今天"：当前上下文语义下应排今天。
            XCTAssertEqual(workspace.task(for: id)?.schedule.dueAt,
                           workspace.calendar.startOfDay(for: now))
        }
    }
}
