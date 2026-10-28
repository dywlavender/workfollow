import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class EditorPopupPresentationTests: XCTestCase {
    func testCaretAtWindowBottomFlipsAboveAndStaysInsideContent() {
        let bounds = CGRect(x: 100, y: 100, width: 400, height: 300)
        let caret = CGRect(x: 470, y: 116, width: 1, height: 18)
        let frame = EditorPopupGeometry.frame(anchor: caret,
            size: CGSize(width: 160, height: 176), bounds: bounds)
        XCTAssertGreaterThanOrEqual(frame.minY, caret.maxY + PopupMetrics.scheduleGap)
        XCTAssertEqual(frame.width, 160)
        XCTAssertEqual(frame.height, 176)
        XCTAssertTrue(bounds.insetBy(dx: PopupMetrics.screenInset,
                                    dy: PopupMetrics.screenInset).contains(frame))
    }

    func testShortDetailWindowConstrainsViewportInsteadOfImposingMinimumHeight() {
        let bounds = CGRect(x: 100, y: 100, width: 280, height: 180)
        let caret = CGRect(x: 130, y: 130, width: 1, height: 18)
        let frame = EditorPopupGeometry.frame(anchor: caret,
            size: CGSize(width: 160, height: 510), bounds: bounds)
        XCTAssertEqual(frame.height, bounds.maxY - PopupMetrics.screenInset
                       - caret.maxY - PopupMetrics.scheduleGap)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertTrue(bounds.insetBy(dx: PopupMetrics.screenInset,
                                    dy: PopupMetrics.screenInset).contains(frame))
    }

    func testTimePickerTrailingAlignmentAndTooltipClampingUseRealAnchor() {
        let bounds = CGRect(x: 100, y: 100, width: 600, height: 500)
        let anchor = CGRect(x: 450, y: 120, width: 26, height: 28)
        let frame = EditorPopupGeometry.frame(anchor: anchor,
            size: CGSize(width: 222, height: 156), bounds: bounds,
            preferredSide: .above, alignment: .trailing)
        XCTAssertEqual(frame.maxX, anchor.maxX)
        XCTAssertEqual(frame.minY, anchor.maxY + PopupMetrics.scheduleGap)
        XCTAssertEqual(EditorPopupGeometry.tooltipX(anchor: .init(x: 0, y: 0, width: 26, height: 28),
            width: 100, containerWidth: 444), 0)
        XCTAssertEqual(EditorPopupGeometry.tooltipX(anchor: .init(x: 418, y: 0, width: 26, height: 28),
            width: 100, containerWidth: 444), 344)
    }

    func testHeadingPickerUsesChildHostAndPreservesBodySelectionOnEscape() throws {
        let shell = makeShell()
        defer { shell.window.close() }
        let baseline = shell.window.frame
        let selection = shell.editor.selectedRange()
        try shell.clickPicker("heading")
        let panel = try InspectorPanelTestSupport.panel(title: "正文标题格式", below: shell.window)
        XCTAssertEqual(panel.frame.width, DocumentToolbarPicker.heading.width, accuracy: 0.5)
        XCTAssertEqual(panel.frame.height, DocumentToolbarPicker.heading.height, accuracy: 0.5)
        XCTAssertEqual(shell.window.frame, baseline, "Picker content must not resize the detail window")
        XCTAssertTrue(shell.window.firstResponder === shell.editor)
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertEqual(shell.editor.selectedRange(), selection)
        XCTAssertTrue(EditorPopupGeometry.bounds(in: shell.window).contains(panel.frame))
        XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: shell.window))
        InspectorPanelTestSupport.settle(shell.window)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(shell.editor.selectedRange(), selection)
        XCTAssertTrue(shell.window.firstResponder === shell.editor)
    }

    func testHeadingPickerFitsShortOwnerAndOutsideClickClosesIt() throws {
        let shell = makeShell(height: 210)
        defer { shell.window.close() }
        try shell.clickPicker("heading")
        let panel = try InspectorPanelTestSupport.panel(title: "正文标题格式", below: shell.window)
        XCTAssertLessThan(panel.frame.height, DocumentToolbarPicker.heading.height)
        XCTAssertGreaterThan(panel.frame.height, 0)
        XCTAssertTrue(EditorPopupGeometry.bounds(in: shell.window).contains(panel.frame))
        let selection = shell.editor.selectedRange()
        let outside = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: CGPoint(x: 420, y: 180), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: shell.window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        _ = PopupInteractionRegistry.shared.routeMouseDown(outside)
        InspectorPanelTestSupport.settle(shell.window)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(shell.editor.selectedRange(), selection)
    }

    func testTagPanelFollowsOwnerMovementWithoutTakingEditorFocus() throws {
        let shell = makeShell()
        defer { shell.editor.dismissTagCompletion(); shell.window.close() }
        shell.editor.profile = DocumentProfile(tagCandidates: { ["标签一", "标签二"] })
        shell.editor.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: "#")))
        shell.editor.setSelectedRange(NSRange(location: 1, length: 0))
        shell.editor.refreshTagCompletion()
        let panel = try XCTUnwrap(shell.editor.tagPanel)
        let before = panel.frame
        shell.window.setFrameOrigin(CGPoint(x: shell.window.frame.minX + 30,
                                            y: shell.window.frame.minY + 20))
        try InspectorPanelTestSupport.waitUntil("Tag panel did not follow its owner") {
            abs(panel.frame.minX - before.minX - 30) < 1 &&
            abs(panel.frame.minY - before.minY - 20) < 1
        }
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertTrue(shell.window.firstResponder === shell.editor)
    }

    func testTimePickerUsesItsOwnWidthAndKeepsEditorSelection() throws {
        let shell = makeShell()
        defer { shell.window.close() }
        let selection = shell.editor.selectedRange()
        try shell.clickPicker("time")
        let panel = try InspectorPanelTestSupport.panel(title: "正文插入时间", below: shell.window)
        XCTAssertEqual(panel.frame.width, DocumentToolbarPicker.time.width, accuracy: 0.5)
        XCTAssertEqual(panel.frame.height, DocumentToolbarPicker.time.height, accuracy: 0.5)
        XCTAssertTrue(EditorPopupGeometry.bounds(in: shell.window).contains(panel.frame))
        XCTAssertEqual(shell.editor.selectedRange(), selection)
        XCTAssertTrue(shell.window.firstResponder === shell.editor)
        XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: shell.window))
        InspectorPanelTestSupport.settle(shell.window)
        XCTAssertFalse(panel.isVisible)
    }

    func testHighlightPaletteOpensFromHighlightControlAndKeepsEditorSelection() throws {
        let shell = makeShell()
        defer { shell.window.close() }
        let selection = shell.editor.selectedRange()
        try shell.clickPicker("highlightColor")
        let panel = try InspectorPanelTestSupport.panel(title: "背景颜色", below: shell.window)
        XCTAssertEqual(panel.frame.width, DocumentToolbarPicker.textColorWidth, accuracy: 0.5)
        XCTAssertEqual(panel.frame.height, DocumentToolbarPicker.textColorHeight, accuracy: 0.5)
        XCTAssertEqual(shell.editor.selectedRange(), selection)
        XCTAssertTrue(shell.window.firstResponder === shell.editor)
        XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: shell.window))
        InspectorPanelTestSupport.settle(shell.window)
        XCTAssertFalse(panel.isVisible)
    }

    func testInsertRowOpensBelowToolbarAndKeepsSelection() throws {
        let shell = makeShell()
        defer { shell.window.close() }
        let selection = shell.editor.selectedRange()
        try shell.clickPicker("insert")
        let panel = try InspectorPanelTestSupport.panel(title: "插入", below: shell.window)
        XCTAssertEqual(panel.frame.width,
                       CGFloat(DocumentInsertCatalog.items.count)
                           * DocumentFormatToolbarMetrics.controlWidth + 12,
                       accuracy: 0.5)
        let toolbarScreenFrame = shell.window.convertToScreen(toolbarFrame())
        XCTAssertLessThan(panel.frame.maxY, toolbarScreenFrame.midY, "插入浮条应在工具条下方")
        XCTAssertEqual(shell.editor.selectedRange(), selection)
        XCTAssertTrue(shell.window.firstResponder === shell.editor)
        XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: shell.window))
        InspectorPanelTestSupport.settle(shell.window)
        XCTAssertFalse(panel.isVisible)
    }

    private func toolbarFrame(height: CGFloat = 460) -> NSRect {
        NSRect(x: 12, y: height - 50, width: 700, height: DocumentFormatToolbarMetrics.height)
    }

    private func makeShell(height: CGFloat = 460) -> (window: NSWindow, editor: NativeTextView,
                                                     clickPicker: (String) throws -> Void) {
        // 格式命令加插入入口一整排；测试宿主给足宽度，让每个触发按钮
        // 都在可视区里（产品里 444 宽时靠横向滚动到达后面的格式命令）。
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 760, height: height))
        // 工具条常驻在正文上方；正文宿主放在它下面。
        let scroll = NSScrollView(frame: CGRect(x: 12, y: 12, width: 736, height: height - 74))
        let editor = NativeTextView(frame: scroll.bounds, textContainer: nil)
        editor.isEditable = true
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: "选区正文")))
        scroll.documentView = editor
        root.addSubview(scroll)
        let handle = DocumentEditorHandle()
        handle.textView = editor
        var triggerFrames: [String: CGRect] = [:]
        let toolbar = NSHostingView(rootView: DocumentFormatToolbarView(handle: handle, maxWidth: 700)
            .onPreferenceChange(EditorPopupTriggerFramesKey.self) { triggerFrames = $0 })
        toolbar.frame = toolbarFrame(height: height)
        root.addSubview(toolbar)
        let window = InspectorPanelTestSupport.ownerWindow(for: root, width: 760, height: height)
        let screen = window.screen?.visibleFrame ?? window.frame
        window.setFrameOrigin(CGPoint(x: screen.minX + 80, y: screen.minY + 80))
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 1, length: 2))
        handle.refreshStyle()
        InspectorPanelTestSupport.settle(window)
        return (window, editor, { id in
            try InspectorPanelTestSupport.waitUntil("Picker trigger was not rendered") {
                triggerFrames[id] != nil
            }
            try InspectorPanelTestSupport.click(try XCTUnwrap(triggerFrames[id]),
                                                in: toolbar, window: window)
        })
    }
}
