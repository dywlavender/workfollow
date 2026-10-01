import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskCompletedRowRenderTests: XCTestCase {
    func testCompletedRolesHaveIndependentNeutralTones() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                func level(_ color: Color) -> CGFloat {
                    let rgb = NSColor(color).usingColorSpace(.sRGB)!
                    XCTAssertEqual(rgb.redComponent, rgb.greenComponent, accuracy: 0.01)
                    XCTAssertEqual(rgb.greenComponent, rgb.blueComponent, accuracy: 0.01)
                    return rgb.redComponent
                }
                let title = level(WFColors.taskCompletedTitle)
                let preview = level(WFColors.taskCompletedPreview)
                let metadata = level(WFColors.taskCompletedMetadata)
                if name == .aqua {
                    XCTAssertLessThan(title, preview)
                    XCTAssertLessThan(preview, metadata)
                } else {
                    XCTAssertGreaterThan(title, preview)
                    XCTAssertGreaterThan(preview, metadata)
                }
            }
        }
        XCTAssertEqual(TaskListMetrics.dividerLeading(completed: true, depth: 0), 58)
        XCTAssertEqual(TaskListMetrics.dividerLeading(completed: true, depth: 1), 82)
        XCTAssertEqual(TaskListMetrics.dividerLeading(completed: false, depth: 0), TaskListMetrics.dividerLeading)
    }

    func testCompletedRowRendersGrayCheckboxAndRetainsRestoreAction() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "记录下次旅行的想法", in: .inbox).taskID)
        _ = workspace.setDocument(id, NativeDocument(plainText: "2026年9月27日"))
        _ = workspace.setPriority(id, .high)
        _ = workspace.complete(id)
        let task = try XCTUnwrap(workspace.task(for: id))
        for dark in [false, true] {
            var frames: [TaskTreeRenderAnchor: CGRect] = [:]
            var restored = false
            let root = VStack(spacing: 0) {
                TaskRowView(task: task, workspace: workspace, depth: 0, hasChildren: false,
                            expanded: false, selected: false, focused: false,
                            onSelect: {}, onComplete: { XCTFail("Completed checkbox must restore") },
                            onRestore: { restored = true }, onToggleExpanded: {})
                Rectangle().fill(WFColors.hover).frame(height: 1)
                    .padding(.leading, TaskListMetrics.dividerLeading(completed: true, depth: 0))
                Spacer()
            }
            .frame(width: 600, height: 130, alignment: .topLeading)
            .coordinateSpace(name: "task-tree-render")
            .onPreferenceChange(TaskTreeFramesKey.self) { frames = $0 }
            .environment(\.colorScheme, dark ? .dark : .light)
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 130),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.hasShadow = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.backgroundColor = dark ? .black : .white
            let host = NSHostingView(rootView: root)
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            let checkbox = try XCTUnwrap(frames[.init(taskID: id, part: .checkbox)])
            let preview = try XCTUnwrap(frames[.init(taskID: id, part: .preview)])
            XCTAssertEqual(preview.minX, TaskListMetrics.titleLeading, accuracy: 0.5)
            let image = try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow,
                CGWindowID(window.windowNumber), [.bestResolution]))
            let bitmap = NSBitmapImageRep(cgImage: image)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "/tmp/render_completed_row_\(dark ? "dark" : "light").png"))
            let point = host.convert(NSPoint(x: checkbox.midX,
                y: host.isFlipped ? checkbox.midY : host.bounds.height - checkbox.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                window.sendEvent(event)
            }
            XCTAssertTrue(restored)
        }
    }
}
