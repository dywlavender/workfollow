import XCTest
@testable import WorkFollow

@MainActor
final class WorkspaceSnapshotDebouncerTests: XCTestCase {
    private func repository() -> NativePreviewRepository {
        NativePreviewRepository(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("workfollow-snapshot-test-\(UUID().uuidString)", isDirectory: true))
    }

    private func flush(_ persistence: PersistenceCoordinator) {
        let saved = expectation(description: "latest snapshot persisted")
        persistence.flush { error in
            XCTAssertNil(error)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 3)
    }

    func testBurstBuildsOnlyOneSnapshotFromLatestState() throws {
        let repository = repository()
        let persistence = PersistenceCoordinator(repository: repository, delay: 0)
        let debouncer = WorkspaceSnapshotDebouncer(persistence: persistence, delay: 0.01)
        var builds = 0
        var latest = ""
        for index in 0..<100 {
            latest = "清单\(index)"
            debouncer.schedule {
                builds += 1
                return NativeWorkspaceSnapshot(tasks: [], notes: [], taskLists: [latest])
            }
        }
        XCTAssertEqual(builds, 0)
        latest = "最后一次状态"
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        flush(persistence)
        XCTAssertEqual(builds, 1)
        XCTAssertEqual(try repository.load()?.taskLists, ["最后一次状态"])
    }

    func testTerminationFlushBuildsLatestSnapshotAndCancelsTimer() throws {
        let repository = repository()
        let persistence = PersistenceCoordinator(repository: repository, delay: 0)
        let debouncer = WorkspaceSnapshotDebouncer(persistence: persistence, delay: 0.03)
        var builds = 0
        debouncer.schedule {
            builds += 1
            return NativeWorkspaceSnapshot(tasks: [], notes: [], taskLists: ["退出前输入"])
        }
        debouncer.flushPendingSnapshot()
        flush(persistence)
        XCTAssertEqual(try repository.load()?.taskLists, ["退出前输入"])
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        flush(persistence)
        XCTAssertEqual(builds, 1, "A cancelled timer must not reconstruct or overwrite after flush")
    }

    func testFlushOrdersLatestSnapshotAfterPreviousWrite() throws {
        let repository = repository()
        let persistence = PersistenceCoordinator(repository: repository, delay: 0)
        let debouncer = WorkspaceSnapshotDebouncer(persistence: persistence)
        debouncer.schedule { NativeWorkspaceSnapshot(tasks: [], notes: [], taskLists: ["旧值"]) }
        debouncer.flushPendingSnapshot()
        debouncer.schedule { NativeWorkspaceSnapshot(tasks: [], notes: [], taskLists: ["新值"]) }
        debouncer.flushPendingSnapshot()
        flush(persistence)
        XCTAssertEqual(try repository.load()?.taskLists, ["新值"])
    }

    func testApplicationFlushPersistsLastEditBeforeDebounceDeadline() throws {
        guard let root = Bundle.main.object(forInfoDictionaryKey: "WorkFollowAcceptanceStorageRoot") as? String,
              !root.isEmpty else { throw XCTSkip("Requires isolated acceptance storage") }
        let environment = AppEnvironment()
        let workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "保存链路验收", in: .inbox).taskID)
        for index in 0..<20 {
            _ = workspace.setDocument(id, NativeDocument(plainText: "连续编辑\(index)"))
        }
        func flushApplication() {
            let done = expectation(description: "application flush")
            environment.flush { error in
                XCTAssertNil(error)
                done.fulfill()
            }
            wait(for: [done], timeout: 3)
        }
        flushApplication()
        let repository = NativePreviewRepository(directory: URL(fileURLWithPath: root, isDirectory: true))
        XCTAssertEqual(try repository.load()?.tasks.first(where: { $0.id == id })?.document.plainText,
                       "连续编辑19")
        // Remove only this disposable task from the isolated acceptance copy.
        _ = workspace.delete(id)
        workspace.permanentlyDelete(id)
        flushApplication()
    }
}
