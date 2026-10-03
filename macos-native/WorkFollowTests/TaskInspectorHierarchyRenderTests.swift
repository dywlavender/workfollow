import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskInspectorHierarchyRenderTests: XCTestCase {
    func testFocusedChildInspectorKeepsPlusAndHeadingInsidePane() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parent = workspace.createTask(title: "父任务", in: .inbox).taskID!
        let child = workspace.createChild(parent, title: "归纳高频问题").taskID!
        workspace.select(child)
        let host = NSHostingView(rootView: TaskInspectorShell(workspace: workspace, showBack: false)
            .frame(width: 320, height: 600))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 320, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        func editor(_ view: NSView) -> NativeTextView? {
            if let text = view as? NativeTextView { return text }
            return view.subviews.lazy.compactMap { editor($0) }.first
        }
        let text = try XCTUnwrap(editor(host))
        window.makeFirstResponder(text)
        func caretX() -> CGFloat {
            host.convert(window.convertFromScreen(text.firstRect(forCharacterRange:
                NSRange(location: 0, length: 0), actualRange: nil)), from: nil).minX
        }
        let initialX = caretX()
        XCTAssertEqual(initialX, TaskInspectorMetrics.horizontalPadding, accuracy: 1)
        let origin = host.convert(.zero, from: text).x
        // 标记（空行 + / 标题角标）距 pane 左缘的**几何**位置：滴答实测墨迹起点 5.5pt（2x 截图里 11px），
        // 扣掉抗锯齿的约 0.5pt → 几何值 5.0pt。替代原先"≥4"的弱断言，锁住宿主缩进 / 槽宽变化时的实际位置。
        let expectedMarkerGeometryFromPaneEdge: CGFloat = 5.0
        let markerX = origin + DocumentEditorGeometry.decorationMarkerX(visibleMinX: text.decorationVisibleMinX)
        XCTAssertEqual(markerX, expectedMarkerGeometryFromPaneEdge, accuracy: 0.5,
                       "装饰标记距 pane 左缘应为滴答实测值，当前 \(markerX)")
        let caret = text.convert(window.convertFromScreen(text.firstRect(forCharacterRange:
            NSRange(location: 0, length: 0), actualRange: nil)), from: nil)
        let before = text.string
        XCTAssertTrue(text.openEmptyBlockMenu(at: NSPoint(x: DocumentEditorGeometry.decorationMarkerX(visibleMinX: text.decorationVisibleMinX) + 2,
                                                        y: caret.midY)))
        XCTAssertNotNil(text.slashPanel)
        XCTAssertEqual(text.slashSession?.range.length, 0)
        XCTAssertEqual(text.string, before)
        text.dismissSlash()
        XCTAssertEqual(text.string, before)
        for level in 0...3 {
            if level > 0 {
                text.applyFormat(try XCTUnwrap(EditorCommandCatalog.format("format.heading\(level)")))
            }
            text.setSelectedRange(NSRange(location: 0, length: 0))
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            text.displayIfNeeded()
            XCTAssertEqual(caretX(), initialX, accuracy: 1)
            let image = try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow,
                CGWindowID(window.windowNumber), [.bestResolution]))
            try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "/tmp/render_child_inspector_marker_\(level).png"))
        }
    }

    func testParentWithoutChildrenHasNoChildSectionAndKeepsFooterEdges() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parent = workspace.createTask(title: "父任务", in: .inbox).taskID!
        _ = workspace.setDocument(parent, NativeDocument(plainText: "正文"))
        workspace.select(parent)
        let frames = try render(workspace, name: "parent-no-child")
        XCTAssertNil(frames[.childSection])
        XCTAssertNil(frames[.addChild])
        XCTAssertNil(frames[.breadcrumb])
        try assertFooter(frames)
    }

    func testChildrenFollowNaturalDocumentHeightForEmptySingleAndMultilineBody() throws {
        var heights: [CGFloat] = []
        for (name, text) in [("empty", ""), ("single", "单行正文"),
                              ("multiline", "第一行\n第二行\n第三行\n第四行\n第五行\n第六行")] {
            let workspace = TaskWorkspaceModel(seedDemoData: false)
            let parent = workspace.createTask(title: "父任务", in: .inbox).taskID!
            _ = workspace.setDocument(parent, NativeDocument(plainText: text))
            let child = workspace.createChild(parent, title: "1231 2").taskID!
            workspace.select(parent)
            let frames = try render(workspace, name: "parent-with-child-\(name)")
            let document = try XCTUnwrap(frames[.document])
            let section = try XCTUnwrap(frames[.childSection])
            let row = try XCTUnwrap(frames[.childRow(child)])
            let add = try XCTUnwrap(frames[.addChild])
            XCTAssertEqual(section.minY - document.maxY, TaskInspectorMetrics.childSectionTopGap, accuracy: 0.5)
            XCTAssertEqual(row.height, 42, accuracy: 0.5)
            XCTAssertEqual(add.minY - row.maxY, TaskInspectorMetrics.childAddGap, accuracy: 0.5)
            XCTAssertLessThan(document.height, 400, "Body must not fill the inspector viewport")
            XCTAssertLessThan(row.maxY, 600, "Children stay near the body, not the footer")
            heights.append(document.height)
            try assertFooter(frames)
        }
        XCTAssertGreaterThan(heights[2], heights[1], "Multiline content must grow naturally")
    }

    func testSelectedChildRendersBreadcrumbBeforeTitleAndNormalReadonlyList() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parent = workspace.createTask(title: "1", in: .inbox).taskID!
        let child = workspace.createChild(parent, title: "1231 2").taskID!
        _ = workspace.setDocument(child, NativeDocument(plainText: "asd as da"))
        workspace.select(child)
        let frames = try render(workspace, name: "selected-child")
        let breadcrumb = try XCTUnwrap(frames[.breadcrumb])
        let title = try XCTUnwrap(frames[.title])
        XCTAssertLessThan(breadcrumb.maxY, title.minY)
        XCTAssertNil(frames[.childSection])
        XCTAssertFalse(workspace.canMoveToList(child), "Read-only display must not change Domain rules")
        try assertFooter(frames)
    }

    func testMultipleChildSurfacesUseSmallGapsWithoutDividers() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parent = workspace.createTask(title: "父任务", in: .inbox).taskID!
        let first = workspace.createChild(parent, title: "子任务 A").taskID!
        let second = workspace.createChild(parent, title: "子任务 B").taskID!
        workspace.select(parent)
        let frames = try render(workspace, name: "parent-multiple-children")
        let firstRow = try XCTUnwrap(frames[.childRow(first)])
        let secondRow = try XCTUnwrap(frames[.childRow(second)])
        XCTAssertEqual(secondRow.minY - firstRow.maxY, TaskInspectorMetrics.childRowGap, accuracy: 0.5)
    }

    private func assertFooter(_ frames: [InspectorRenderAnchor: CGRect]) throws {
        let list = try XCTUnwrap(frames[.footerList])
        let formatting = try XCTUnwrap(frames[.footerFormatting])
        let more = try XCTUnwrap(frames[.footerMore])
        XCTAssertEqual(list.minX, TaskInspectorMetrics.horizontalPadding, accuracy: 0.5)
        XCTAssertEqual(more.maxX, 880 - TaskInspectorMetrics.horizontalPadding, accuracy: 0.5)
        XCTAssertLessThan(list.maxX, formatting.minX)
        XCTAssertLessThan(formatting.maxX, more.minX)
        XCTAssertEqual(list.midY, more.midY, accuracy: 0.5)
    }

    private func render(_ workspace: TaskWorkspaceModel, name: String) throws -> [InspectorRenderAnchor: CGRect] {
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let root = TaskInspectorShell(workspace: workspace, showBack: false)
            .frame(width: 880, height: 900)
            .environment(\.colorScheme, .light)
            .coordinateSpace(name: "inspector-render")
            .onPreferenceChange(InspectorFramesKey.self) { frames = $0 }
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: "/tmp/workfollow-inspector-hierarchy-renders", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(name).png"))
        return frames
    }
}
