import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// TI2-07：顶栏子任务进度条（只读形态）。
@MainActor
final class TaskInspectorProgressBarTests: XCTestCase {

    func testParseAcceptsOnlyTheSubtaskProgressShape() {
        XCTAssertEqual(TaskInspectorSubtaskProgress.parse("2/5"),
                       TaskInspectorSubtaskProgress(done: 2, total: 5))
        XCTAssertEqual(TaskInspectorSubtaskProgress.parse("0/3"),
                       TaskInspectorSubtaskProgress(done: 0, total: 3))
        XCTAssertNil(TaskInspectorSubtaskProgress.parse(nil))
        XCTAssertNil(TaskInspectorSubtaskProgress.parse(""))
        XCTAssertNil(TaskInspectorSubtaskProgress.parse("2"))
        XCTAssertNil(TaskInspectorSubtaskProgress.parse("6/5"))
        XCTAssertNil(TaskInspectorSubtaskProgress.parse("a/b"))
        XCTAssertNil(TaskInspectorSubtaskProgress.parse("1/0"))
    }

    func testFraction() {
        XCTAssertEqual(TaskInspectorSubtaskProgress(done: 1, total: 4).fraction, 0.25, accuracy: 0.001)
        XCTAssertEqual(TaskInspectorSubtaskProgress(done: 0, total: 0).fraction, 0)
    }

    func testProgressBarAppearsOnlyWhenTheTaskHasSubtasks() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parent = try XCTUnwrap(workspace.createTask(title: "父任务", in: .inbox).taskID)
        workspace.select(parent)

        var frames = try renderShell(workspace)
        XCTAssertNil(frames[.progressBar], "没有子任务时不占位")

        let child = try XCTUnwrap(workspace.createChild(parent, title: "子任务").taskID)
        frames = try renderShell(workspace)
        let bar = try XCTUnwrap(frames[.progressBar], "有子任务时顶栏下沿出现进度条")
        XCTAssertEqual(bar.height, 2, accuracy: 0.5)

        let task = try XCTUnwrap(workspace.task(for: child))
        _ = workspace.changeStatus(task)
        frames = try renderShell(workspace)
        XCTAssertNotNil(frames[.progressBar], "完成后仍显示（进度推进）")
    }

    private func renderShell(_ workspace: TaskWorkspaceModel) throws -> [InspectorRenderAnchor: CGRect] {
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let root = TaskInspectorShell(workspace: workspace, showBack: false)
            .frame(width: 880, height: 900)
            .environment(\.colorScheme, .light)
            .coordinateSpace(name: "inspector-render")
            .onPreferenceChange(InspectorFramesKey.self) { frames = $0 }
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        return frames
    }
}
