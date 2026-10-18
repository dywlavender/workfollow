import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// TI2-15：笔记信息（字数 / 创建 / 修改）。
///
/// 滴答证据：`TTTaskDetailNoteInfoViewController` 的 count / create / modify 三行，
/// 顶栏 `noteInfoButton`。本地只在任务有正文时给入口。
@MainActor
final class TaskNoteInfoTests: XCTestCase {

    func testCharacterCountIgnoresWhitespace() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "字数", in: .inbox).taskID)
        workspace.setDocument(id, NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "你好 世界")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: " 第二行\n")])
        ]))
        let task = try XCTUnwrap(workspace.task(for: id))
        let info = TaskNoteInfo(task: task)
        XCTAssertEqual(info.characterCount, 7, "空格与换行不计入：你好世界第二行")
        XCTAssertEqual(info.characterCountText, "7")
    }

    func testDateTextUsesCompactPattern() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let text = TaskNoteInfoPanel.dateText(date, calendar: calendar)
        // 走查发现中文长格式在 220pt 面板里会被截断，改为紧凑的 yyyy/M/d HH:mm。
        XCTAssertNotNil(text.range(of: #"^\d{4}/\d{1,2}/\d{1,2} \d{2}:\d{2}$"#, options: .regularExpression),
                        "实际：\(text)")
    }

    func testHeaderOffersInfoOnlyWhenTheTaskHasBody() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "信息入口", in: .inbox).taskID)
        workspace.select(id)

        var frames = try render(TaskInspectorShell(workspace: workspace, showBack: false))
        XCTAssertNil(frames[.noteInfo], "空正文不显示笔记信息入口")

        workspace.setDocument(id, NativeDocument(plainText: "正文内容"))
        frames = try render(TaskInspectorShell(workspace: workspace, showBack: false))
        let info = try XCTUnwrap(frames[.noteInfo])
        let priority = try XCTUnwrap(frames[.priority])
        XCTAssertLessThan(info.maxX, priority.minX + 0.5, "入口在优先级左侧")
    }

    // MARK: - Helpers

    private func render(_ root: some View) throws -> [InspectorRenderAnchor: CGRect] {
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let host = NSHostingView(rootView: root
            .frame(width: 880, height: 900)
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
