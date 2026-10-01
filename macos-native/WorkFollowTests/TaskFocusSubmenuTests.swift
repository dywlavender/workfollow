import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskFocusSubmenuTests: XCTestCase {
    func testPlacementPrefersRightFlipsLeftAndClampsVertically() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let size = CGSize(width: 176, height: 82)
        let right = AnchoredPropertyPanelGeometry.submenuFrame(row: CGRect(x: 100, y: 200, width: 208, height: 32), size: size, bounds: bounds)
        XCTAssertEqual(right.minX, 314)
        let left = AnchoredPropertyPanelGeometry.submenuFrame(row: CGRect(x: 560, y: 200, width: 208, height: 32), size: size, bounds: bounds)
        XCTAssertEqual(left.maxX, 554)
        let low = AnchoredPropertyPanelGeometry.submenuFrame(row: CGRect(x: 560, y: 0, width: 208, height: 32), size: size, bounds: bounds)
        XCTAssertEqual(low.minY, 8)
        XCTAssertTrue(bounds.insetBy(dx: 8, dy: 8).contains(low))
    }

    func testBothActionsStartRealSessionAndBusySessionIsNotReplaced() throws {
        for stopwatch in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("task-focus-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = FocusStore(clock: Date.init, directory: directory)
            let taskID = UUID()
            var presentation = TaskInspectorActionPresentationState()
            presentation.open(.more)
            presentation.openSubmenu(.focus)
            XCTAssertTrue(TaskInspectorFocusAction.start(taskID: taskID, stopwatch: stopwatch, store: store, presentation: &presentation))
            XCTAssertEqual(store.currentTaskID, taskID)
            XCTAssertEqual(store.phase, .focusing)
            XCTAssertEqual(store.sessionTiming?.projectedEndAt == nil, stopwatch)
            XCTAssertEqual(store.preferences.lastTaskID, taskID)
            XCTAssertNil(presentation.panel)
            XCTAssertNil(presentation.submenu)
            presentation.open(.more)
            presentation.openSubmenu(.focus)
            XCTAssertFalse(TaskInspectorFocusAction.start(taskID: UUID(), stopwatch: !stopwatch, store: store, presentation: &presentation))
            XCTAssertEqual(store.currentTaskID, taskID)
            XCTAssertEqual(presentation.panel, .more)
            _ = store.giveUp()
        }
    }

    func testActualInspectorFocusChildDoesNotResizeMoreAndEscapeClosesChildFirst() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "任务操作验收", in: .inbox).taskID)
        workspace.select(id)
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let root = TaskInspectorShell(workspace: workspace, showBack: false)
            .frame(width: 760, height: 700)
            .coordinateSpace(name: "inspector-render")
            .onPreferenceChange(InspectorFramesKey.self) { frames = $0 }
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 760, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        func settle() {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        func click(_ rect: CGRect) throws {
            let point = host.convert(NSPoint(x: rect.midX, y: host.isFlipped ? rect.midY : host.bounds.height - rect.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                NSApp.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
            }
            settle()
        }
        settle()
        try click(try XCTUnwrap(frames[.footerMore]))
        let original = try XCTUnwrap(frames[.moreMenu])
        try click(try XCTUnwrap(frames[.focusMenuRow]))
        let panel = try XCTUnwrap(window.childWindows?.first { $0.title == "任务操作子菜单" })
        XCTAssertEqual(panel.frame.width, 176, accuracy: 0.5)
        XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        XCTAssertEqual(frames[.moreMenu], original)
        let row = try XCTUnwrap(frames[.focusMenuRow])
        let rowWindow = host.convert(NSRect(x: row.minX, y: host.isFlipped ? row.minY : host.bounds.height - row.maxY,
                                          width: row.width, height: row.height), to: nil)
        XCTAssertLessThan(panel.frame.maxX, window.convertToScreen(rowWindow).minX)
        let image = try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow,
            CGWindowID(window.windowNumber), [.bestResolution]))
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/render_task_more_menu.png"))
        let childImage = try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow,
            CGWindowID(panel.windowNumber), [.bestResolution]))
        try XCTUnwrap(NSBitmapImageRep(cgImage: childImage).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/render_task_focus_submenu.png"))
        XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: window))
        settle()
        XCTAssertFalse(panel.isVisible)
        XCTAssertNotNil(frames[.moreMenu])
        XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: window))
        settle()
        XCTAssertNil(frames[.moreMenu])
        try click(try XCTUnwrap(frames[.footerMore]))
        try click(try XCTUnwrap(frames[.focusMenuRow]))
        XCTAssertTrue(window.childWindows?.contains { $0.title == "任务操作子菜单" && $0.isVisible } == true)
        try click(CGRect(x: 40, y: 350, width: 20, height: 20))
        XCTAssertNil(frames[.moreMenu])
        XCTAssertFalse(window.childWindows?.contains { $0.title == "任务操作子菜单" && $0.isVisible } == true)
    }
}
