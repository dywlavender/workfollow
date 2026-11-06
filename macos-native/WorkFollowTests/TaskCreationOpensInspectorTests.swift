import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 端到端验收：在真实 `RootShellView` 里通过列表快速添加条（真实键盘事件路径）
/// 建一条待办，断言**详情栏跟到新任务**，而不是停在上一条。
///
/// 这条用例走的是用户实际用的那条路：`QuickAddFocusReportingField` 的
/// `doCommandBy(insertNewline:)` → `TaskListView.addTask` → `openCreatedTask`。
@MainActor
final class TaskCreationOpensInspectorTests: XCTestCase {
    @MainActor private final class Fixture {
        let environment = AppEnvironment()
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let navigation = AppNavigation(destination: .today)
        let host: NSHostingView<AnyView>
        let window: NSWindow

        init() throws {
            workspace.feedbackSink = environment.feedback
            workspace.placementFeedback = { [weak workspace, weak environment, weak navigation] before, after, count in
                guard let workspace, let environment, let navigation else { return false }
                return TaskPlacementFeedback.present(before: before, after: after, count: count,
                    destination: navigation.destination, workspace: workspace, center: environment.feedback,
                    open: { CommandPaletteProjection.openTask($0, workspace: workspace, navigation: navigation) })
            }
            host = NSHostingView(rootView: AnyView(
                RootShellView(workspace: workspace, navigation: navigation)
                    .environmentObject(environment).frame(width: 1280, height: 800)))
            window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        }

        /// 真实输入路径：点进快速添加框、打字、按回车。
        @discardableResult
        func add(_ title: String) throws -> UUID {
            let previousIDs = Set(workspace.allTasks.map(\.id))
            let field = try XCTUnwrap(find(QuickAddFocusReportingField.self, in: host))
            field.onMouseDown?()
            window.makeFirstResponder(field)
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            field.stringValue = title
            field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification,
                                                               object: field))
            InspectorPanelTestSupport.settle(window)
            XCTAssertEqual(field.delegate?.control?(field, textView: editor,
                doCommandBy: #selector(NSResponder.insertNewline(_:))), true)
            InspectorPanelTestSupport.settle(window)
            return try XCTUnwrap(workspace.allTasks.first { !previousIDs.contains($0.id) },
                "回车后应建出任务，现有：\(workspace.allTasks.map(\.title))").id
        }

        func close() { window.contentView = nil; window.close() }

        private func find<V: NSView>(_ type: V.Type, in view: NSView) -> V? {
            if let match = view as? V { return match }
            return view.subviews.lazy.compactMap { self.find(type, in: $0) }.first
        }
    }

    /// 用户报告的原症状：先打开一条旧待办，再新建一条 —— 编辑栏必须换成新任务。
    func testCreatingTaskWhileAnotherIsOpenSwitchesInspectorToTheNewTask() throws {
        let fixture = try Fixture()
        defer { fixture.close() }

        let existing = try XCTUnwrap(fixture.workspace.createTask(title: "先打开的那条", in: .today).taskID)
        fixture.workspace.select(existing)
        InspectorPanelTestSupport.settle(fixture.window)
        XCTAssertEqual(fixture.workspace.selectedTaskID, existing)

        let created = try fixture.add("新建的这条")

        XCTAssertEqual(fixture.workspace.selectedTaskID, created,
                       "创建完成后应自动打开新任务，而不是继续显示上一条")
        XCTAssertEqual(fixture.workspace.selectedTask?.title, "新建的这条",
                       "编辑栏标题必须是新任务")
    }

    /// 没有任何选中时新建，也要把新任务打开（不能停在空详情）。
    func testCreatingTaskWithEmptyInspectorOpensTheNewTask() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        XCTAssertNil(fixture.workspace.selectedTaskID)

        let created = try fixture.add("空态下新建")

        XCTAssertEqual(fixture.workspace.selectedTaskID, created)
        XCTAssertEqual(fixture.workspace.selectedTask?.title, "空态下新建")
    }

    /// 范围外新建（今天视图里建一条没有日期的）不能抢走详情：
    /// 那条任务根本不在当前列表里，打开它只会得到一份空详情。
    func testCreatingTaskOutsideTheViewKeepsInspectorAndOffersDestination() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let existing = try XCTUnwrap(fixture.workspace.createTask(title: "正在看的这条", in: .today).taskID)
        fixture.workspace.select(existing)
        InspectorPanelTestSupport.settle(fixture.window)

        // 「明天 …」把落点推到明天 → 不在今天的投影里。
        let created = try fixture.add("明天 范围外新建")
        XCTAssertFalse(fixture.workspace.groups(for: .today).flatMap(\.tasks).contains { $0.id == created },
                       "这条确实不在今天视图里")
        XCTAssertEqual(fixture.workspace.selectedTaskID, existing,
                       "范围外新建不应抢走当前详情")
        XCTAssertTrue(fixture.environment.feedback.presentation?.event.message.contains("明天") == true,
                      "应给出落点提示")
        XCTAssertEqual(fixture.environment.feedback.presentation?.event.destinationTitle, "查看")
    }
}
