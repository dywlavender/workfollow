import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// TI2-22 焦点接力：标题 Return → 正文；新建空任务自动聚焦标题。
@MainActor
final class FocusRelayTests: XCTestCase {
    @MainActor private final class TitleModel: ObservableObject {
        @Published var title = "工作计划"
        @Published var editing = false
        @Published var placeholder = "标题"
    }

    private struct TitleHost: View {
        @ObservedObject var model: TitleModel

        var body: some View {
            AppKitTaskTitleField(text: $model.title, isEditing: $model.editing,
                                 placeholder: model.placeholder)
                .frame(width: 400)
        }
    }

    func testTitleKeepsCompositionAndCaretDuringViewRefresh() throws {
        let model = TitleModel()
        let host = NSHostingView(rootView: TitleHost(model: model))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 420, height: 150)
        defer { window.contentView = nil; window.close() }
        let title = try XCTUnwrap(firstResponderField(in: host))
        XCTAssertTrue(window.makeFirstResponder(title))
        InspectorPanelTestSupport.settle(window)
        let editor = try XCTUnwrap(title.currentEditor() as? NSTextView)
        let end = NSRange(location: (model.title as NSString).length, length: 0)
        editor.setSelectedRange(end)
        editor.setMarkedText("gengxin", selectedRange: NSRange(location: 7, length: 0), replacementRange: end)
        XCTAssertTrue(editor.hasMarkedText())
        let selection = editor.selectedRange()

        model.placeholder = "任务标题"
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(title.placeholderAttributedString?.string, "任务标题")
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertTrue(editor.hasMarkedText(), "外层刷新期间要保留正在选词的组合串")
        XCTAssertEqual(editor.string, "工作计划gengxin")
        XCTAssertEqual(editor.selectedRange(), selection)
        XCTAssertEqual(model.title, "工作计划")

        editor.insertText("更新", replacementRange: editor.markedRange())
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(model.title, "工作计划更新")
        XCTAssertTrue(window.firstResponder === editor)

        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.insertText("v2", replacementRange: editor.selectedRange())
        let caretAfterInsertion = editor.selectedRange()
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(model.title, "工作v2计划更新")
        XCTAssertEqual(editor.selectedRange(), caretAfterInsertion)
        XCTAssertTrue(window.firstResponder === editor)
    }

    func testTitleFocusFollowsTheLatestHandoff() throws {
        let (_, _, window, host) = try makeShell()
        defer { window.contentView = nil; window.close() }
        let title = try XCTUnwrap(firstResponderField(in: host))
        let body = try MilkdownTestSupport.editor(in: host)

        XCTAssertTrue(window.makeFirstResponder(title))
        XCTAssertNotNil(title.currentEditor())
        body.focus()
        InspectorPanelTestSupport.settle(window)

        XCTAssertTrue(MilkdownTestSupport.isFocused(body), "过期的标题编辑通知不能从正文抢回焦点")
        XCTAssertNil(title.currentEditor())

        XCTAssertTrue(window.makeFirstResponder(title))
        InspectorPanelTestSupport.settle(window)
        body.focus()
        XCTAssertTrue(window.makeFirstResponder(title))
        InspectorPanelTestSupport.settle(window)

        XCTAssertNotNil(title.currentEditor(), "重新点进标题后，上一轮离开标题的通知不能清掉当前焦点")
    }

    func testTitleReturnRelaysFocusToBody() throws {
        let (environment, id, window, host) = try makeShell()
        defer { window.close() }
        let title = try XCTUnwrap(firstResponderField(in: host), "标题字段应已建出来")
        let body = try MilkdownTestSupport.editor(in: host)

        window.makeFirstResponder(title)
        // Return 走字段的 doCommandBy：与真实按键同一条路径。
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        _ = title.delegate?.control?(title, textView: editor,
                                     doCommandBy: #selector(NSResponder.insertNewline(_:)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

        XCTAssertTrue(MilkdownTestSupport.isFocused(body),
                      "标题 Return 后焦点应落在正文，实际 \(String(describing: window.firstResponder))")
        XCTAssertNotNil(environment.taskWorkspace.task(for: id))
    }

    func testTitleEscapeEndsEditingWithoutRelay() throws {
        let (_, _, window, host) = try makeShell()
        defer { window.close() }
        let title = try XCTUnwrap(firstResponderField(in: host))
        let body = try MilkdownTestSupport.editor(in: host)
        window.makeFirstResponder(title)
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        _ = title.delegate?.control?(title, textView: editor,
                                     doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertFalse(MilkdownTestSupport.isFocused(body), "Esc 只结束编辑，不接力到正文")
    }

    func testPaletteBlankCreateRequestsTitleFocus() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-relay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        let navigation = AppNavigation()

        let result = CommandPaletteProjection.createTask("", workspace: workspace, navigation: navigation)
        let id = try XCTUnwrap(result.taskID)
        XCTAssertEqual(workspace.task(for: id)?.title, "无标题")
        XCTAssertEqual(workspace.pendingTitleEditorID, id, "空查询创建要请求标题焦点")
        XCTAssertEqual(workspace.consumePendingTitleEditor(), id)
        XCTAssertNil(workspace.pendingTitleEditorID, "取一次就消费掉，不能反复抢焦点")
    }

    func testPaletteTitledCreateDoesNotStealFocus() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-relay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        _ = CommandPaletteProjection.createTask("写好的标题", workspace: workspace, navigation: AppNavigation())
        XCTAssertNil(workspace.pendingTitleEditorID, "已有标题的创建不抢焦点")
    }

    // MARK: - Helpers

    private func makeShell() throws -> (AppEnvironment, UUID, NSWindow, NSView) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-relay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "焦点接力", in: .inbox).taskID)
        workspace.select(id)
        let root = TaskInspectorShell(workspace: workspace, showBack: false)
            .frame(width: 880, height: 900)
            .environmentObject(environment)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        host.layoutSubtreeIfNeeded()
        return (environment, id, window, host)
    }

    private func firstResponderField(in view: NSView) -> NSTextField? {
        if let field = view as? HeightTrackingTextField { return field }
        return view.subviews.lazy.compactMap { self.firstResponderField(in: $0) }.first
    }

}
