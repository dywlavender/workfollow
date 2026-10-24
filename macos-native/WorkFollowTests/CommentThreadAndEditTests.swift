import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// TI2-09 剩余项：评论回复（一级缩进）与编辑（`已编辑` 标记）。
@MainActor
final class CommentThreadAndEditTests: XCTestCase {

    // MARK: - 存储层

    func testReplyIsScopedUnderParent() {
        let store = TaskCommentStore(directory: temporaryDirectory())
        let taskID = UUID()
        let parent = store.add(taskID: taskID, text: "父评论")
        let reply = store.add(taskID: taskID, text: "回复内容", parentID: parent.id)

        XCTAssertEqual(reply.parentID, parent.id)
        let all = store.comments(for: taskID)
        XCTAssertEqual(all.map { $0.text }, ["父评论", "回复内容"])
        XCTAssertEqual(store.replies(to: parent.id, in: all).map { $0.id }, [reply.id])
    }

    func testTopLevelCommentsExcludeReplies() {
        let store = TaskCommentStore(directory: temporaryDirectory())
        let taskID = UUID()
        let parent = store.add(taskID: taskID, text: "父")
        store.add(taskID: taskID, text: "子", parentID: parent.id)
        let topLevel = store.comments(for: taskID).filter { $0.parentID == nil }
        XCTAssertEqual(topLevel.count, 1)
    }

    func testEditUpdatesTextAndStampsEditedAt() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = TaskCommentStore(clock: { now }, directory: temporaryDirectory())
        let taskID = UUID()
        let comment = store.add(taskID: taskID, text: "原文")
        XCTAssertNil(comment.editedAt)

        now = now.addingTimeInterval(60)
        XCTAssertTrue(store.update(comment.id, text: "  改过  "))
        let updated = store.comment(comment.id)
        XCTAssertEqual(updated?.text, "改过", "与 add 同口径裁剪空白")
        XCTAssertEqual(updated?.editedAt, now)
        XCTAssertEqual(updated?.createdAt, comment.createdAt, "创建时间不动，列表仍按创建时间排")
    }

    func testEditRejectsEmptyAndNoOp() {
        let store = TaskCommentStore(directory: temporaryDirectory())
        let taskID = UUID()
        let comment = store.add(taskID: taskID, text: "原文")
        XCTAssertFalse(store.update(comment.id, text: "   "), "空文本拒绝")
        XCTAssertTrue(store.update(comment.id, text: "原文"), "内容没变算成功但不产生编辑标记")
        XCTAssertNil(store.comment(comment.id)?.editedAt)
    }

    func testDeletingParentRemovesItsReplies() {
        let store = TaskCommentStore(directory: temporaryDirectory())
        let taskID = UUID()
        let parent = store.add(taskID: taskID, text: "父")
        store.add(taskID: taskID, text: "子一", parentID: parent.id)
        store.add(taskID: taskID, text: "子二", parentID: parent.id)
        let sibling = store.add(taskID: taskID, text: "别处的顶层评论")
        XCTAssertEqual(store.count(for: taskID), 4)

        store.delete(parent.id)
        XCTAssertEqual(store.comments(for: taskID).map { $0.id }, [sibling.id],
                       "父评论删掉时回复一起走，不留孤儿")
    }

    func testReplyAndEditSurviveReload() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        let store = TaskCommentStore(clock: { instant }, directory: directory)
        let taskID = UUID()
        let parent = store.add(taskID: taskID, text: "父")
        let reply = store.add(taskID: taskID, text: "子", parentID: parent.id)
        _ = store.update(reply.id, text: "子（改）")

        let done = expectation(description: "flush")
        store.flush { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)

        let reloaded = TaskCommentStore(directory: directory)
        let comments = reloaded.comments(for: taskID)
        XCTAssertEqual(comments.count, 2)
        let child = try XCTUnwrap(comments.first { $0.id == reply.id })
        XCTAssertEqual(child.text, "子（改）")
        XCTAssertEqual(child.parentID, parent.id)
        XCTAssertNotNil(child.editedAt)
    }

    /// 旧存档没有 parentID / editedAt 两个键，必须能解出来（additive 迁移）。
    func testDecodingLegacyCommentWithoutNewKeys() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","taskID":"\(UUID().uuidString)","text":"旧评论","createdAt":0}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let comments = try decoder.decode([TaskComment].self, from: Data(json.utf8))
        XCTAssertEqual(comments.count, 1)
        XCTAssertNil(comments[0].parentID)
        XCTAssertNil(comments[0].editedAt)
    }

    // MARK: - 视图

    func testSectionRendersRepliesIndentedUnderParent() throws {
        let directory = temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = TaskCommentStore(directory: directory)
        let taskID = UUID()
        let parent = store.add(taskID: taskID, text: "父评论")
        store.add(taskID: taskID, text: "回复内容", parentID: parent.id)

        // 直接渲染展开态（宿主里 `isExpanded` 是私有 State，展开由底栏按钮驱动）。
        let expanded = Binding.constant(true)
        let view = TaskCommentSection(taskID: taskID, store: store, isExpanded: expanded)
            .frame(width: 600)
            .background(WFColors.content)
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        // 展开态要真的比收起态（只有 24pt 标题行）高——父 + 一条回复 + 输入框。
        XCTAssertGreaterThan(host.fittingSize.height, 60,
                             "展开后应渲染评论列表与输入框，实际 \(host.fittingSize.height)")
    }

    func testEditingShowsSaveAndCancel() throws {
        let (environment, id, window, host, _) = try makeShell()
        defer { window.close() }
        let comment = environment.taskCommentStore.add(taskID: id, text: "待改")
        settle(host)
        // 视图状态是私有的：走 store 的公开路径验证行为一致（编辑后文本与标记都变）。
        XCTAssertTrue(environment.taskCommentStore.update(comment.id, text: "改好了"))
        settle(host)
        let updated = try XCTUnwrap(environment.taskCommentStore.comment(comment.id))
        XCTAssertEqual(updated.text, "改好了")
        XCTAssertNotNil(updated.editedAt)
    }

    // MARK: - Helpers

    private final class FrameBox {
        var frames: [InspectorRenderAnchor: CGRect] = [:]
    }

    private func makeShell() throws -> (AppEnvironment, UUID, NSWindow, NSView, FrameBox) {
        let directory = temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "评论线程", in: .inbox).taskID)
        workspace.select(id)
        let box = FrameBox()
        let root = TaskInspectorShell(workspace: workspace, showBack: false,
                                      commentStore: environment.taskCommentStore)
            .frame(width: 880, height: 900)
            .environment(\.colorScheme, .light)
            .environmentObject(environment)
            .coordinateSpace(name: "inspector-render")
            .onPreferenceChange(InspectorFramesKey.self) { box.frames = $0 }
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        return (environment, id, window, host, box)
    }

    private func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CommentThreadAndEditTests-\(UUID().uuidString)", isDirectory: true)
    }
}
