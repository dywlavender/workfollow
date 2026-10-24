import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// TI2-22 焦点接力：标题 Return → 正文；新建空任务自动聚焦标题。
@MainActor
final class FocusRelayTests: XCTestCase {

    func testTitleReturnRelaysFocusToBody() throws {
        let (environment, id, window, host) = try makeShell()
        defer { window.close() }
        let title = try XCTUnwrap(firstResponderField(in: host), "标题字段应已建出来")
        let body = try XCTUnwrap(firstTextView(in: host))

        window.makeFirstResponder(title)
        // Return 走字段的 doCommandBy：与真实按键同一条路径。
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        _ = title.delegate?.control?(title, textView: editor,
                                     doCommandBy: #selector(NSResponder.insertNewline(_:)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

        XCTAssertTrue(window.firstResponder === body,
                      "标题 Return 后焦点应落在正文，实际 \(String(describing: window.firstResponder))")
        XCTAssertNotNil(environment.taskWorkspace.task(for: id))
    }

    func testTitleEscapeEndsEditingWithoutRelay() throws {
        let (_, _, window, host) = try makeShell()
        defer { window.close() }
        let title = try XCTUnwrap(firstResponderField(in: host))
        let body = try XCTUnwrap(firstTextView(in: host))
        window.makeFirstResponder(title)
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        _ = title.delegate?.control?(title, textView: editor,
                                     doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertFalse(window.firstResponder === body, "Esc 只结束编辑，不接力到正文")
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

    private func firstTextView(in view: NSView) -> NativeTextView? {
        if let text = view as? NativeTextView { return text }
        return view.subviews.lazy.compactMap { self.firstTextView(in: $0) }.first
    }
}
