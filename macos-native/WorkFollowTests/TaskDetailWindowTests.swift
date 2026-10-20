import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// TI2-17：详情独立窗口。
///
/// 滴答的容器切换（`detail_side_peek` / `detail_popup`）；本地做成真正的独立窗口：
/// 顶栏入口只在宽布局出现，重复点击复用同一个窗口。
@MainActor
final class TaskDetailWindowTests: XCTestCase {

    func testDetachEntryOnlyAppearsInWideLayout() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "独立窗口用例", in: .inbox).taskID)
        workspace.select(id)

        let wide = try render(TaskInspectorShell(workspace: workspace, showBack: false))
        let detach = try XCTUnwrap(wide[.detach], "宽布局顶栏应有独立窗口入口")
        let priority = try XCTUnwrap(wide[.priority])
        XCTAssertLessThan(detach.maxX, priority.minX + 0.5, "入口在优先级左侧")

        let narrow = try render(TaskInspectorShell(workspace: workspace, showBack: true))
        XCTAssertNil(narrow[.detach], "窄列（已分离视图）不再重复给入口")
    }

    func testControllerReusesTheSameWindow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("detail-window-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        _ = try XCTUnwrap(workspace.createTask(title: "窗口用例", in: .inbox).taskID)

        TaskDetailWindowController.shared.show(workspace: workspace, environment: environment)
        let first = try XCTUnwrap(TaskDetailWindowController.shared.window)
        XCTAssertEqual(first.title, "任务详情")

        TaskDetailWindowController.shared.show(workspace: workspace, environment: environment)
        XCTAssertTrue(TaskDetailWindowController.shared.window === first,
                      "重复点入口只前置，不再开第二个窗口")
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
