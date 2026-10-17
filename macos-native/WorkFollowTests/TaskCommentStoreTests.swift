import XCTest
@testable import WorkFollow

@MainActor
final class TaskCommentStoreTests: XCTestCase {
    func testAddCommentsAppendInInsertionOrder() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = TaskCommentStore(clock: { now }, directory: temporaryDirectory())
        let taskID = UUID()
        store.add(taskID: taskID, text: "第一条")
        now = now.addingTimeInterval(10)
        store.add(taskID: taskID, text: "第二条")

        let comments = store.comments(for: taskID)
        XCTAssertEqual(comments.map(\.text), ["第一条", "第二条"])
        XCTAssertEqual(comments.count, 2)
    }

    func testCommentsAreScopedByTask() {
        let store = TaskCommentStore(directory: temporaryDirectory())
        let a = UUID(), b = UUID()
        store.add(taskID: a, text: "A 的评论")
        store.add(taskID: b, text: "B 的评论")

        XCTAssertEqual(store.comments(for: a).map(\.text), ["A 的评论"])
        XCTAssertEqual(store.comments(for: b).map(\.text), ["B 的评论"])
        XCTAssertEqual(store.count(for: a), 1)
        XCTAssertEqual(store.count(for: b), 1)
    }

    func testAddTrimsWhitespace() {
        let store = TaskCommentStore(directory: temporaryDirectory())
        let taskID = UUID()
        let comment = store.add(taskID: taskID, text: "  你好  ")
        XCTAssertEqual(comment.text, "你好")
    }

    func testDeleteRemovesComment() {
        let store = TaskCommentStore(directory: temporaryDirectory())
        let taskID = UUID()
        let comment = store.add(taskID: taskID, text: "要删除")
        XCTAssertEqual(store.count(for: taskID), 1)

        store.delete(comment.id)
        XCTAssertTrue(store.comments(for: taskID).isEmpty)
    }

    func testFlushAndReloadPersistsComments() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        let store = TaskCommentStore(clock: { instant }, directory: directory)
        let taskID = UUID()
        store.add(taskID: taskID, text: "持久化评论")

        let done = expectation(description: "flush comments")
        store.flush { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("task-comments.sqlite").path))
        let reloaded = TaskCommentStore(clock: { instant }, directory: directory)
        XCTAssertEqual(reloaded.comments(for: taskID).map(\.text), ["持久化评论"])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskCommentStoreTests-\(UUID().uuidString)", isDirectory: true)
    }
}
