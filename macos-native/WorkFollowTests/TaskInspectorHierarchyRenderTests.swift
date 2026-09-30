import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskInspectorHierarchyRenderTests: XCTestCase {
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
        XCTAssertEqual(list.minX, 20, accuracy: 0.5)
        XCTAssertEqual(more.maxX, 880 - 20, accuracy: 0.5)
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
