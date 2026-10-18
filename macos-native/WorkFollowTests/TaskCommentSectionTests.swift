import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// TI2-09：详情内联评论区。
///
/// 滴答把评论放在详情底部（`showAddCommentView:` + 评论 cell）；本地改成正文流里的
/// 折叠区块：有评论显示"评论 n"标题行，底栏 💬 控制展开。
@MainActor
final class TaskCommentSectionTests: XCTestCase {

    private final class FrameBox {
        var frames: [InspectorRenderAnchor: CGRect] = [:]
    }

    func testSectionAppearsOnlyWhenCommentsExistOrExpanded() throws {
        let (environment, _, id, window, host, box) = try makeShell()
        _ = window
        settle(host)
        XCTAssertNil(box.frames[.commentSection], "没有评论时不占位")

        environment.taskCommentStore.add(taskID: id, text: "第一条评论")
        settle(host)
        let section = try XCTUnwrap(box.frames[.commentSection], "有评论时出现评论区")
        XCTAssertGreaterThan(section.height, 0)

        let comment = try XCTUnwrap(environment.taskCommentStore.comments(for: id).first)
        environment.taskCommentStore.delete(comment.id)
        settle(host)
        XCTAssertNil(box.frames[.commentSection], "删完最后一条评论后收起")
    }

    func testCommentCountReflectsStore() throws {
        let (environment, _, id, window, _, _) = try makeShell()
        _ = window
        XCTAssertEqual(environment.taskCommentStore.count(for: id), 0)
        environment.taskCommentStore.add(taskID: id, text: "甲")
        environment.taskCommentStore.add(taskID: id, text: "乙")
        XCTAssertEqual(environment.taskCommentStore.count(for: id), 2)
    }


    // MARK: - Helpers

    private func makeShell() throws -> (AppEnvironment, TaskWorkspaceModel, UUID, NSWindow, NSView, FrameBox) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("comment-section-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "评论用例", in: .inbox).taskID)
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
        window.contentView = host
        window.orderFront(nil)
        return (environment, workspace, id, window, host, box)
    }

    private func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
    }
}
