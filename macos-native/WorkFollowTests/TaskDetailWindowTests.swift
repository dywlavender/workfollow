import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// The task inspector's top entry uses the common floating editor in both layouts.
@MainActor
final class TaskDetailWindowTests: XCTestCase {

    override func tearDown() {
        FloatingEditorWindowController.shared.closeAll()
        super.tearDown()
    }

    func testFloatingEntryRemainsAvailableInWideAndCompactLayouts() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "独立窗口用例", in: .inbox).taskID)
        workspace.select(id)

        let wide = try render(TaskInspectorShell(workspace: workspace, showBack: false))
        let detach = try XCTUnwrap(wide[.detach], "宽布局顶栏应有独立窗口入口")
        let priority = try XCTUnwrap(wide[.priority])
        XCTAssertLessThan(detach.maxX, priority.minX + 0.5, "入口在优先级左侧")

        let narrow = try render(TaskInspectorShell(workspace: workspace, showBack: true))
        XCTAssertNotNil(narrow[.detach], "移除更多菜单入口后，窄布局也应能从顶部打开浮窗")
    }

    func testControllerReusesTheSameWindow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("detail-window-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "窗口用例", in: .inbox).taskID)
        workspace.select(id)

        TaskDetailWindowController.shared.show(workspace: workspace, environment: environment)
        let first = try XCTUnwrap(TaskDetailWindowController.shared.window)
        XCTAssertEqual(first.title, "任务浮窗")
        let panel = try XCTUnwrap(first as? FloatingEditorPanel)
        InspectorPanelTestSupport.settle(panel)
        XCTAssertEqual(panel.editorHandle.textView?.documentIdentity, id)

        TaskDetailWindowController.shared.show(workspace: workspace, environment: environment)
        XCTAssertTrue(TaskDetailWindowController.shared.window === first,
                      "重复点入口只前置，不再开第二个窗口")
        let other = try XCTUnwrap(workspace.createTask(title: "另一个任务", in: .inbox).taskID)
        workspace.select(other)
        InspectorPanelTestSupport.settle(panel)
        XCTAssertEqual(panel.editorHandle.textView?.documentIdentity, id,
                       "主页面切换任务不能改变已打开浮窗的内容")
    }

    // MARK: - Helpers

    private func render(_ root: some View) throws -> [InspectorRenderAnchor: CGRect] {
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let host = NSHostingView(rootView: root
            .frame(width: 880, height: 900)
            // TaskInspectorShell 声明了 @EnvironmentObject AppEnvironment，
            // 其他渲染测试（ScheduleContainerRenderTests 等）也都显式注入。
            .environmentObject(AppEnvironment())
            .environment(\.colorScheme, .light)
            .coordinateSpace(name: "inspector-render")
            .onPreferenceChange(InspectorFramesKey.self) { frames = $0 })
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        // 不关窗：AppEnvironment/NSHostingView 的"关窗释放"在 XCTest 内存检查里会过释放
        // （最简 Text + 空 AppEnvironment 可复现，与本功能无关）。
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        return frames
    }
}
