import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskRowTitleFocusTests: XCTestCase {
    func testDeferredFocusRestoreDoesNotTakeFocusBackFromTheNextTask() throws {
        var committed: String?
        let host = NSHostingView(rootView: VStack {
            TaskRowTitleField(title: "第一条任务", color: .primary, onSelect: {},
                onEditingEnded: {}, onCommit: { committed = $0 }).frame(height: 30)
            TaskRowTitleField(title: "第二条任务", color: .primary, onSelect: {},
                onEditingEnded: {}, onCommit: { _ in }).frame(height: 30)
        })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 390, height: 90)
        defer { window.close() }
        let fields = titleFields(in: host)
        let first = try XCTUnwrap(fields.first { $0.stringValue == "第一条任务" })
        let second = try XCTUnwrap(fields.first { $0.stringValue == "第二条任务" })
        defer { first.editingSession = false; second.editingSession = false }
        first.editingSession = true
        first.selectText(nil)
        try XCTUnwrap(first.currentEditor()).string = "第一条的修改"
        second.editingSession = true
        second.selectText(nil)
        // A selection refresh can have queued this callback before focus moved.
        first.restoreEditingFocus()
        XCTAssertTrue(window.firstResponder === second.currentEditor())
        XCTAssertNotNil(second.currentEditor())
        XCTAssertFalse(first.editingSession)
        XCTAssertEqual(committed, "第一条的修改")
    }

    func testDeferredFocusRestoreDoesNotTakeFocusFromTheDetailBody() throws {
        let titleHost = NSHostingView(rootView: TaskRowTitleField(title: "任务", color: .primary,
            onSelect: {}, onEditingEnded: {}, onCommit: { _ in }).frame(height: 30))
        let body = NativeTextView(frame: CGRect(x: 0, y: 40, width: 390, height: 60), textContainer: nil)
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 390, height: 100))
        titleHost.frame = CGRect(x: 0, y: 0, width: 390, height: 30)
        host.addSubview(titleHost); host.addSubview(body)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 390, height: 100)
        defer { window.close() }
        let field = try XCTUnwrap(titleFields(in: host).first)
        defer { field.editingSession = false }
        field.editingSession = true
        field.selectText(nil)
        XCTAssertTrue(window.makeFirstResponder(body))
        field.restoreEditingFocus()
        XCTAssertTrue(window.firstResponder === body)
        XCTAssertFalse(field.editingSession)
    }

    private func titleFields(in view: NSView) -> [TaskRowTitleField.Field] {
        if let field = view as? TaskRowTitleField.Field { return [field] }
        return view.subviews.flatMap { titleFields(in: $0) }
    }
}
