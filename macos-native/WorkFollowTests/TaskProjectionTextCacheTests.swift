import XCTest
@testable import WorkFollow

@MainActor
final class TaskProjectionTextCacheTests: XCTestCase {
    func testTextEditsReuseMembershipAndRefreshCachedParentAndChildValues() throws {
        let now = Date(timeIntervalSince1970: 1_793_548_800)
        var tasks = (0..<500).map { index in
            Task(id: UUID(), title: "虚构任务 \(index)", list: .inbox, priority: .none,
                 schedule: TaskSchedule(dueAt: now), childOrder: index, createdAt: now, updatedAt: now)
        }
        tasks[1].parentID = tasks[0].id
        let parent = tasks[0].id
        let child = tasks[1].id
        let workspace = TaskWorkspaceModel(clock: { now }, seedDemoData: false, initialTasks: tasks)
        let scopes: [TaskListScope] = [.inbox, .today, .allTasks]
        func nodes(_ scope: TaskListScope) -> [TaskTreeNode] {
            workspace.groups(for: scope).flatMap { workspace.nodes(for: $0, scope: scope) }
        }
        for scope in scopes { XCTAssertEqual(nodes(scope).count, 500) }
        let badge = workspace.count(for: NativeDestination.today)
        XCTAssertEqual(workspace.subtaskProgress(for: parent), "0/1")
        let builds = workspace.projectionBuildCount
        for edit in 0..<20 {
            workspace.setDocument(parent, NativeDocument(plainText: "更新正文 \(edit)"))
            workspace.setTitle(child, "更新子任务 \(edit)")
            for scope in scopes {
                let current = nodes(scope)
                XCTAssertEqual(current.first { $0.task.id == parent }?.task.document.plainText, "更新正文 \(edit)")
                XCTAssertEqual(current.first { $0.task.id == child }?.task.title, "更新子任务 \(edit)")
            }
            XCTAssertEqual(workspace.count(for: NativeDestination.today), badge)
            XCTAssertEqual(workspace.subtaskProgress(for: parent), "0/1")
        }
        let rebuilds = workspace.projectionBuildCount - builds
        print("TEXT_PROJECTION tasks=500 edits=40 rebuilds=\(rebuilds)")
        XCTAssertEqual(rebuilds, 0, "Plain text edits must refresh cached values without rebuilding membership or sidebar counts")
    }
}
