import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// TI2-05b：任务形态（文本 / 笔记 / 清单）。
///
/// 滴答证据：`kind` / `updateKind:` / `isTextKind` / `isNoteKind` / `isChecklistKind`
/// 与标题 cell 的 `kindButton`。本地把形态存在 `Task.kind`（旧快照缺键 → `.text`），
/// 切换时做内容映射：清单形态把普通/列表段落变成检查项，切回文本/笔记再还原。
@MainActor
final class TaskKindTests: XCTestCase {

    // MARK: - 迁移

    func testLegacySnapshotWithoutKindDecodesAsText() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "旧快照", in: .inbox).taskID)
        let task = try XCTUnwrap(workspace.task(for: id))
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any])
        json.removeValue(forKey: "kind")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Task.self, from: data)
        XCTAssertEqual(decoded.kind, .text, "缺 kind 的旧快照按文本处理")
    }

    // MARK: - 内容映射

    func testSwitchingToChecklistConvertsParagraphsAndLists() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "形态", in: .inbox).taskID)
        workspace.setDocument(id, NativeDocument(blocks: [
            DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: "标题")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "甲")]),
            DocumentBlock(kind: .bullet, runs: [DocumentRun(text: "乙")]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "丙")]),
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "丁")])
        ]))

        workspace.setKind(id, .checklist)

        let task = try XCTUnwrap(workspace.task(for: id))
        XCTAssertEqual(task.kind, .checklist)
        XCTAssertEqual(task.document.blocks.map(\.kind), [
            .heading(1), .checklist(false), .checklist(false), .checklist(false), .checklist(true)
        ])
        XCTAssertEqual(task.document.blocks.map { $0.runs.map(\.text).joined() },
                       ["标题", "甲", "乙", "丙", "丁"], "文字内容不丢")
    }

    func testSwitchingBackToTextRestoresParagraphsAndKeepsCheckedAsStrike() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "回退", in: .inbox).taskID)
        workspace.setDocument(id, NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "未完成")]),
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "已完成")])
        ]))
        workspace.setKind(id, .checklist)
        workspace.setKind(id, .text)

        let task = try XCTUnwrap(workspace.task(for: id))
        XCTAssertEqual(task.kind, .text)
        XCTAssertEqual(task.document.blocks.map(\.kind), [.paragraph, .paragraph])
        XCTAssertFalse(task.document.blocks[0].runs[0].marks.contains(.strikethrough))
        XCTAssertTrue(task.document.blocks[1].runs[0].marks.contains(.strikethrough),
                      "已完成项切回文本后保留删除线，状态不静默丢失")
    }

    func testSetKindIsOneUndoStep() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "撤销", in: .inbox).taskID)
        workspace.setDocument(id, NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")])
        ]))
        workspace.setKind(id, .checklist)
        XCTAssertEqual(workspace.task(for: id)?.kind, .checklist)

        workspace.undo()
        let task = try XCTUnwrap(workspace.task(for: id))
        XCTAssertEqual(task.kind, .text)
        XCTAssertEqual(task.document.blocks.map(\.kind), [.paragraph])
    }

    // MARK: - UI

    func testHeaderShowsKindButton() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "类型入口", in: .inbox).taskID)
        workspace.select(id)
        let frames = try render(TaskInspectorShell(workspace: workspace, showBack: false))
        XCTAssertNotNil(frames[.kind], "顶栏有任务类型入口")
    }

    func testChecklistKindShowsDocumentProgressWithoutSubtasks() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "清单进度", in: .inbox).taskID)
        workspace.setDocument(id, NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "一")]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "二")])
        ]))
        workspace.select(id)

        var frames = try render(TaskInspectorShell(workspace: workspace, showBack: false))
        XCTAssertNil(frames[.progressBar], "文本形态不显示检查项进度")

        workspace.setKind(id, .checklist)
        frames = try render(TaskInspectorShell(workspace: workspace, showBack: false))
        XCTAssertNotNil(frames[.progressBar], "清单形态用检查项完成度填顶栏进度条")
    }

    // MARK: - Helpers

    private func render(_ root: some View) throws -> [InspectorRenderAnchor: CGRect] {
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let host = NSHostingView(rootView: root
            .frame(width: 880, height: 900)
            .environmentObject(AppEnvironment())
            .environment(\.colorScheme, .light)
            .coordinateSpace(name: "inspector-render")
            .onPreferenceChange(InspectorFramesKey.self) { frames = $0 })
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        return frames
    }
}
