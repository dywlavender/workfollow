import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskTagEditorInteractionTests: XCTestCase {
    func testColorDraftCancelsWithoutLeakingAndConfirmationIsUndoable() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let tagID = try XCTUnwrap(workspace.createTag("编辑验收"))
        let original = try XCTUnwrap(workspace.tag(for: tagID))
        var dismissals = 0
        final class Frames { var values: [TaskTagEditorAnchor: CGRect] = [:] }
        let frames = Frames()

        func editorWindow() -> NSWindow {
            frames.values = [:]
            let host = NSHostingView(rootView: TaskTagEditorView(workspace: workspace,
                tag: workspace.tag(for: tagID), parentID: nil,
                onDismiss: { dismissals += 1 })
                .frame(width: 420, height: 330, alignment: .topLeading)
                .onPreferenceChange(TaskTagEditorFrames.self) { frames.values = $0 })
            return InspectorPanelTestSupport.ownerWindow(for: host, width: 420, height: 330)
        }
        func click(_ anchor: TaskTagEditorAnchor, in window: NSWindow) throws {
            let frame = try XCTUnwrap(frames.values[anchor])
            let host = try XCTUnwrap(window.contentView)
            XCTAssertTrue(host.bounds.contains(CGPoint(x: frame.midX, y: frame.midY)))
            try InspectorPanelTestSupport.click(frame, in: host, window: window)
        }

        let cancelled = editorWindow()
        try click(.color(WFListPalette.argb[1]), in: cancelled)
        XCTAssertEqual(workspace.tag(for: tagID), original, "色板只修改编辑草稿")
        try click(.cancel, in: cancelled)
        cancelled.close()
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(workspace.tag(for: tagID), original)

        let reopened = editorWindow()
        try click(.save, in: reopened)
        XCTAssertEqual(workspace.tag(for: tagID), original, "取消的颜色不能在重开后保存")
        reopened.close()

        let saved = editorWindow()
        defer { saved.close() }
        try click(.color(WFListPalette.argb[1]), in: saved)
        try click(.save, in: saved)
        XCTAssertEqual(workspace.tag(for: tagID)?.colorARGB, WFListPalette.argb[1])
        workspace.undo()
        XCTAssertEqual(workspace.tag(for: tagID), original)
    }
}
