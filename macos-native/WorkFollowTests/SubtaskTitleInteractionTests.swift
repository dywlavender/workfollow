import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class SubtaskTitleInteractionTests: XCTestCase {
    @MainActor private final class FrameProbe {
        var frames: [InspectorRenderAnchor: CGRect] = [:]
    }

    @MainActor private final class Fixture {
        let directory: URL
        let environment: AppEnvironment
        let parent: UUID
        let first: UUID
        let second: UUID
        let probe: FrameProbe
        let host: NSHostingView<AnyView>
        let window: NSWindow
        var workspace: TaskWorkspaceModel { environment.taskWorkspace }

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("subtask-title-click-" + UUID().uuidString)
            let seed = TaskWorkspaceModel(seedDemoData: false)
            parent = try XCTUnwrap(seed.createTask(title: "保持在父任务详情", in: .inbox).taskID)
            first = try XCTUnwrap(seed.createChild(parent, title: "点击修改第一条").taskID)
            second = try XCTUnwrap(seed.createChild(parent, title: "点击修改第二条").taskID)
            try NativePreviewRepository(directory: directory)
                .save(NativeWorkspaceSnapshot(tasks: seed.allTasks, notes: []))
            environment = AppEnvironment(directory: directory)
            environment.focusStore.notifier = nil
            environment.taskWorkspace.select(parent)
            let probe = FrameProbe()
            self.probe = probe
            let root = TaskInspectorShell(workspace: environment.taskWorkspace, showBack: false)
                .environmentObject(environment).frame(width: 760, height: 700)
                .coordinateSpace(name: "inspector-render")
                .onPreferenceChange(InspectorFramesKey.self) { probe.frames = $0 }
            host = NSHostingView(rootView: AnyView(root))
            window = InspectorPanelTestSupport.ownerWindow(for: host, width: 760, height: 700)
        }

        func close() {
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }

        func row(_ id: UUID) throws -> SubtaskRowView {
            try XCTUnwrap(descendants(host).compactMap { $0 as? SubtaskRowView }.first { $0.taskID == id })
        }

        func title(_ id: UUID) throws -> SubtaskTitleField {
            try XCTUnwrap(descendants(try row(id)).compactMap { $0 as? SubtaskTitleField }.first)
        }

        func parentTitle() throws -> HeightTrackingTextField {
            try XCTUnwrap(descendants(host).compactMap { $0 as? HeightTrackingTextField }.first)
        }

        func activeChildEditor() throws -> NSTextView {
            try XCTUnwrap(descendants(host).compactMap { $0 as? SubtaskTitleField }
                .compactMap { $0.currentEditor() as? NSTextView }
                .first { window.firstResponder === $0 })
        }

        func clickTitle(_ id: UUID) throws -> NSTextView {
            let field = try title(id)
            try InspectorPanelTestSupport.click(field.bounds, in: field, window: window)
            XCTAssertEqual(workspace.selectedTaskID, parent, "单击子任务标题应留在父任务详情")
            // 点击会触发失焦保存引起的行重建，field editor 就位晚一拍：
            // 轮询等 firstResponder 落到标题编辑器，而不是立刻解包。
            try InspectorPanelTestSupport.waitUntil(
                "必须从实际标题点击进入编辑，包含失焦保存引起的行重建") {
                descendants(host).compactMap { $0 as? SubtaskTitleField }
                    .contains { window.firstResponder === $0.currentEditor() as? NSTextView }
            }
            let current = try title(id)
            let editor = try XCTUnwrap(current.currentEditor() as? NSTextView,
                                        "必须从实际标题点击进入编辑，包含失焦保存引起的行重建")
            XCTAssertTrue(window.firstResponder === editor)
            return editor
        }

        private func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
    }

    func testSingleTitleClickEditsInParentInspectorAndReturnSaves() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let editor = try fixture.clickTitle(fixture.first)
        editor.selectAll(nil)
        editor.insertText("就地修改成功", replacementRange: editor.selectedRange())
        try InspectorPanelTestSupport.sendReturn(to: fixture.window)
        XCTAssertEqual(fixture.workspace.task(for: fixture.first)?.title, "就地修改成功")
        XCTAssertEqual(fixture.workspace.selectedTaskID, fixture.parent)
        XCTAssertEqual(fixture.workspace.allTasks.count, 3, "修改现有标题不能续建新子任务")
        XCTAssertEqual(try fixture.title(fixture.first).focusRingType, .none)
    }

    func testClickingAnotherTitleCommitsPreviousAndKeepsParentSelected() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let firstEditor = try fixture.clickTitle(fixture.first)
        firstEditor.selectAll(nil)
        firstEditor.insertText("第一条失焦保存", replacementRange: firstEditor.selectedRange())
        let secondEditor = try fixture.clickTitle(fixture.second)
        XCTAssertEqual(fixture.workspace.task(for: fixture.first)?.title, "第一条失焦保存")
        secondEditor.selectAll(nil)
        secondEditor.insertText("第二条回车保存", replacementRange: secondEditor.selectedRange())
        try InspectorPanelTestSupport.sendReturn(to: fixture.window)
        XCTAssertEqual(fixture.workspace.task(for: fixture.second)?.title, "第二条回车保存")
        XCTAssertEqual(fixture.workspace.selectedTaskID, fixture.parent)
    }

    func testCompletionKeepsParentAndRowPaddingStillOpensChild() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let first = try fixture.row(fixture.first)
        let checkbox = try XCTUnwrap(first.subviews.compactMap { $0 as? NSButton }.first)
        try InspectorPanelTestSupport.click(checkbox.bounds, in: checkbox, window: fixture.window)
        XCTAssertTrue(try XCTUnwrap(fixture.workspace.task(for: fixture.first)).isClosed)
        XCTAssertEqual(fixture.workspace.selectedTaskID, fixture.parent)

        let second = try fixture.row(fixture.second)
        let padding = CGRect(x: second.bounds.maxX - 6, y: second.bounds.midY - 1, width: 2, height: 2)
        try InspectorPanelTestSupport.click(padding, in: second, window: fixture.window)
        XCTAssertEqual(fixture.workspace.selectedTaskID, fixture.second, "标题编辑之外保留原有详情入口")
    }

    func testSavingChildOnBlurDoesNotTakeFocusBackFromParentTitle() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let editor = try fixture.clickTitle(fixture.first)
        editor.selectAll(nil)
        editor.insertText("离开子任务时保存", replacementRange: editor.selectedRange())
        let parentTitle = try fixture.parentTitle()
        try InspectorPanelTestSupport.click(parentTitle.bounds, in: parentTitle, window: fixture.window)
        XCTAssertEqual(fixture.workspace.task(for: fixture.first)?.title, "离开子任务时保存")
        XCTAssertEqual(fixture.workspace.selectedTaskID, fixture.parent)
        let parentEditor = try XCTUnwrap(try fixture.parentTitle().currentEditor())
        XCTAssertTrue(fixture.window.firstResponder === parentEditor, "树刷新不能把焦点从其它输入框抢回")
    }

    func testAddChildButtonStillFocusesTheNewTitleAndReturnContinuesAdding() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let add = try XCTUnwrap(fixture.probe.frames[.addChild])
        try InspectorPanelTestSupport.click(add, in: fixture.host, window: fixture.window)
        XCTAssertEqual(fixture.workspace.allTasks.count, 4)
        let editor = try fixture.activeChildEditor()
        editor.insertText("新增子任务回车保存", replacementRange: editor.selectedRange())
        try InspectorPanelTestSupport.sendReturn(to: fixture.window)
        XCTAssertTrue(fixture.workspace.allTasks.contains { $0.title == "新增子任务回车保存" })
        XCTAssertEqual(fixture.workspace.allTasks.count, 5, "新增行回车后仍应续加下一条")
        XCTAssertEqual(fixture.workspace.selectedTaskID, fixture.parent)
        XCTAssertEqual(try fixture.activeChildEditor().string, "")
    }
}
