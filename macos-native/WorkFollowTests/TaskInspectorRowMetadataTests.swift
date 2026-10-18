import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// TI2-12：子任务行的迷你标记（重复 / 提醒 / 描述 / 附件）。
///
/// 滴答 `TTSubtasksCell` 的 `shouldShowMiniIcons` 一类开关；本地数据源与列表行
/// 同构（`TaskSecondaryMetadata`），这里只锁"取哪些 + 行里真的画出来"。
@MainActor
final class SubtaskRowMetadataTests: XCTestCase {

    func testPlainSubtaskHasNoIndicators() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parent = try XCTUnwrap(workspace.createTask(title: "父", in: .inbox).taskID)
        let child = try XCTUnwrap(workspace.createChild(parent, title: "干净子任务").taskID)
        let task = try XCTUnwrap(workspace.task(for: child))

        XCTAssertEqual(SubtaskRowMetadata.indicatorSymbols(for: task), [])

        let row = SubtaskRowView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        row.configure(task: task, completionSize: 19, dateText: nil)
        XCTAssertEqual(row.indicatorCount, 0)
    }

    func testIndicatorsFollowTaskSecondaryMetadataOrder() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parent = try XCTUnwrap(workspace.createTask(title: "父", in: .inbox).taskID)
        let child = try XCTUnwrap(workspace.createChild(parent, title: "带标记").taskID)
        var task = try XCTUnwrap(workspace.task(for: child))
        task.recurrence = .daily
        task.reminderOffsets = [-30]
        task.attachments = [NativeAttachment(id: UUID(), name: "图纸.pdf", storedName: "图纸.pdf")]

        XCTAssertEqual(SubtaskRowMetadata.indicatorSymbols(for: task),
                       ["repeat", "bell", "paperclip"],
                       "顺序跟列表行一致：重复 → 提醒 → 附件")

        let row = SubtaskRowView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        row.configure(task: task, completionSize: 19, dateText: "今天")
        XCTAssertEqual(row.indicatorCount, 3)

        // cell 复用：换成没有标记的任务时必须清空，不能留下上一行的图标。
        var plain = task
        plain.recurrence = .never
        plain.reminderOffsets = nil
        plain.attachments = []
        row.configure(task: plain, completionSize: 19, dateText: nil)
        XCTAssertEqual(row.indicatorCount, 0)
    }
}

/// TI2-09（部分）：底栏评论出口的条数角标。
@MainActor
final class TaskCommentBadgeTests: XCTestCase {

    func testBadgeAppearsOnlyWhenTheTaskHasComments() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("comment-badge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "评论角标", in: .inbox).taskID)
        workspace.select(id)

        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let root = TaskInspectorShell(workspace: workspace, showBack: false,
                                      commentStore: environment.taskCommentStore)
            .frame(width: 880, height: 900)
            .environment(\.colorScheme, .light)
            .environmentObject(environment)
            .coordinateSpace(name: "inspector-render")
            .onPreferenceChange(InspectorFramesKey.self) { frames = $0 }
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        XCTAssertNil(frames[.commentBadge], "没有评论时不占位")

        environment.taskCommentStore.add(taskID: id, text: "第一条评论")
        settle(host)
        let badge = try XCTUnwrap(frames[.commentBadge], "有评论时角标出现")
        XCTAssertGreaterThan(badge.width, 0)

        let comment = try XCTUnwrap(environment.taskCommentStore.comments(for: id).first)
        environment.taskCommentStore.delete(comment.id)
        settle(host)
        XCTAssertNil(frames[.commentBadge], "删完评论后角标消失")
    }

    private func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
    }
}
