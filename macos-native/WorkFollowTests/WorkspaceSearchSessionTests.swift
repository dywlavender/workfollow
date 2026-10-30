import XCTest
@testable import WorkFollow

@MainActor
final class WorkspaceSearchSessionTests: XCTestCase {
    func testAllResultsPassQuickLimitAndFiltersStillReturnCompleteSet() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        for index in 0..<18 {
            let id = try XCTUnwrap(workspace.createDraft(title: "周报 \(index)",
                list: index < 10 ? "工作" : "学习", schedule: .init(), priority: .none,
                tags: [], reminder: nil, repeatFrequency: .never).taskID)
            if index.isMultiple(of: 2) { _ = workspace.complete(id) }
        }
        let notes = NotesWorkspaceModel()
        for index in 0..<8 {
            notes.create()
            let id = try XCTUnwrap(notes.selectedID)
            notes.edit(id) { $0.title = "周报笔记 \(index)" }
        }
        let session = WorkspaceSearchSession()
        session.query = "周报"
        var entries = session.entries(workspace: workspace, notes: notes, destination: .today)
        XCTAssertEqual(entries.filter { $0.kind == .task }.count, 7)
        XCTAssertEqual(entries.filter { $0.kind == .note }.count, 5)
        session.showAll = true
        XCTAssertEqual(session.entries(workspace: workspace, notes: notes, destination: .today).count, 26)
        session.content = .tasks; session.status = .completed; session.list = "工作"
        entries = session.entries(workspace: workspace, notes: notes, destination: .today)
        XCTAssertEqual(entries.count, 5)
        XCTAssertTrue(entries.allSatisfy { $0.kind == .task && $0.subtitle.contains("工作") })
        session.content = .notes
        XCTAssertEqual(session.entries(workspace: workspace, notes: notes, destination: .today).count, 8)
    }

    func testSearchOpenAndReturnKeepQueryFiltersAndSelection() throws {
        let environment = AppEnvironment()
        let id = try XCTUnwrap(environment.taskWorkspace.createTask(title: "搜索返回验收", in: .today).taskID)
        let session = environment.searchSession
        session.query = "搜索返回验收"; session.showAll = true; session.content = .tasks
        let entry = try XCTUnwrap(session.entries(workspace: environment.taskWorkspace,
            notes: environment.notesWorkspace, destination: .today).first)
        environment.commandPalettePresented = true
        XCTAssertTrue(session.open(entry, environment: environment, navigation: environment.navigation))
        XCTAssertEqual(environment.taskWorkspace.selectedTaskID, id)
        XCTAssertFalse(environment.commandPalettePresented)
        environment.feedback.openDestination()
        XCTAssertTrue(environment.commandPalettePresented)
        XCTAssertEqual(session.query, "搜索返回验收")
        XCTAssertTrue(session.showAll)
        XCTAssertEqual(session.content, .tasks)
    }

    func testOpeningResultRequestsRevealAtTheMatchingQuery() throws {
        let environment = AppEnvironment()
        let taskID = try XCTUnwrap(environment.taskWorkspace.createTask(title: "搜索定位", in: .today).taskID)
        _ = environment.taskWorkspace.setDocument(taskID, NativeDocument(plainText: "会议纪要：季度预算复核"))
        let notes = environment.notesWorkspace
        notes.create()
        let noteID = try XCTUnwrap(notes.selectedID)
        notes.edit(noteID) { note in
            note.title = "预算笔记"
            note.document = NativeDocument(plainText: "正文里的预算结论")
        }

        let session = environment.searchSession
        session.query = "预算"; session.showAll = true; session.content = .all
        let entries = session.entries(workspace: environment.taskWorkspace, notes: notes,
                                      destination: .today)
        let taskEntry = try XCTUnwrap(entries.first { $0.action == .openTask(taskID) })
        let noteEntry = try XCTUnwrap(entries.first { $0.action == .openNote(noteID) })

        XCTAssertTrue(session.open(taskEntry, environment: environment,
                                   navigation: environment.navigation))
        XCTAssertEqual(environment.taskWorkspace.searchRevealRequest?.targetID, taskID)
        XCTAssertEqual(environment.taskWorkspace.consumeSearchReveal(for: taskID)?.query, "预算")
        XCTAssertNil(environment.taskWorkspace.searchRevealRequest)

        XCTAssertTrue(session.open(noteEntry, environment: environment,
                                   navigation: environment.navigation))
        XCTAssertEqual(notes.searchRevealRequest?.targetID, noteID)
        XCTAssertEqual(notes.consumeSearchReveal(for: noteID)?.query, "预算")
        XCTAssertNil(notes.searchRevealRequest)
    }

    func testSelectionReusesResultsAndActualEditsRefreshThem() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let notes = NotesWorkspaceModel()
        notes.create()
        let id = try XCTUnwrap(notes.selectedID)
        notes.edit(id) { $0.title = "项目回顾" }
        let session = WorkspaceSearchSession()
        session.query = "项目"; session.showAll = true
        XCTAssertEqual(session.entries(workspace: workspace, notes: notes, destination: .today).count, 1)
        let builds = session.projectionBuildCount
        session.selectedIndex = 1
        _ = session.entries(workspace: workspace, notes: notes, destination: .today)
        XCTAssertEqual(session.projectionBuildCount, builds)
        notes.edit(id) { $0.title = "个人回顾" }
        XCTAssertTrue(session.entries(workspace: workspace, notes: notes, destination: .today).isEmpty)
    }

    func testRecentResourcesPersistAndRemovedResourcesDisappear() throws {
        let suite = "WorkFollow.SearchRecent.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "最近任务", in: .inbox).taskID)
        WorkspaceSearchSession(defaults: defaults).recordTask(id)
        let reopened = WorkspaceSearchSession(defaults: defaults)
        XCTAssertEqual(reopened.recentEntries(tasks: workspace.allTasks, notes: []).first?.action, .openTask(id))
        _ = workspace.delete(id)
        XCTAssertTrue(reopened.recentEntries(tasks: workspace.allTasks, notes: []).isEmpty)
    }
}
