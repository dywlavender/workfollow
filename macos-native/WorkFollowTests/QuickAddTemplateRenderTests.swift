import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class QuickAddTemplateRenderTests: XCTestCase {
    func testPropertiesOnlyExposeFourPrioritiesAndListTagsTemplateAndDispatchOnce() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        var frames: [QuickAddRenderAnchor: CGRect] = [:]
        var applies = 0
        let root = QuickAddPropertiesPopover(workspace: workspace, selectedPriority: .none,
            selectedList: TaskList.inbox.name, selectedTags: [],
            onPriority: { _ in }, onList: { _ in }, onTags: { _ in },
            onTemplate: { applies += 1 }, onDismiss: {})
            .background(WFColors.content)
            .environment(\.colorScheme, .light)
            .coordinateSpace(name: "quick-add-render")
            .onPreferenceChange(QuickAddFramesKey.self) { frames = $0 }
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 270, height: 235),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        XCTAssertEqual(frames.count, 8)
        XCTAssertEqual(try XCTUnwrap(frames[.properties]).width, 270, accuracy: 0.5)
        let list = try XCTUnwrap(frames[.list])
        let tags = try XCTUnwrap(frames[.tags])
        let template = try XCTUnwrap(frames[.template])
        XCTAssertLessThan(list.maxY, tags.maxY)
        XCTAssertLessThan(tags.maxY, template.maxY)
        XCTAssertEqual(list.minX, tags.minX, accuracy: 0.1)
        XCTAssertEqual(tags.minX, template.minX, accuracy: 0.1)
        try export(host, name: "quick-add-properties")
        let point = host.convert(CGPoint(x: template.midX,
            y: host.isFlipped ? template.midY : host.bounds.height - template.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1)))
        }
        settle(host)
        XCTAssertEqual(applies, 1)
        XCTAssertTrue(workspace.allTasks.isEmpty, "Opening Gallery must not create a task")
    }

    func testBuiltInApplicationRendersActualInspectorChecklistAndToday() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(TemplateApplier.apply(BuiltInTaskTemplates.all[0], to: workspace))
        XCTAssertEqual(workspace.selectedTaskID, id)
        let root = TaskInspectorShell(workspace: workspace, showBack: false)
            .frame(width: 880, height: 900)
            .environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 900),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        try export(host, name: "template-created-task-inspector")
        XCTAssertEqual(workspace.selectedTask?.document.blocks.count, 7)
        XCTAssertEqual(workspace.selectedTask?.schedule.dueAt, workspace.calendar.startOfDay(for: workspace.clock()))
    }

    private func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
    }

    private func export(_ host: NSView, name: String) throws {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: "/tmp/workfollow-template-renders", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name + ".png"))
    }
}
