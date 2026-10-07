import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class NativeTaskOutlineTests: XCTestCase {
    func testUnchangedRowsLayoutCostProbe() {
        let coordinator = NativeTaskOutline.Coordinator()
        let scroll = NativeTaskOutline.makeScrollView(coordinator: coordinator)
        let window = InspectorPanelTestSupport.ownerWindow(for: scroll, width: 400, height: 800)
        defer { window.close() }
        let rows = (0..<100).map { index in
            NativeTaskOutline.Row(id: "probe-\(index)", state: index, layout: 65) {
                VStack(alignment: .leading) {
                    TaskRowTitleField(title: "Task \(index)", color: .primary,
                                      onSelect: {}, onEditingEnded: {}, onCommit: { _ in })
                    Text("Preview").lineLimit(1)
                }.frame(height: 65)
            }
        }
        coordinator.update(rows, in: scroll)
        settle(scroll)
        for (name, content, heights) in [("both", true, true), ("content", true, false),
                                         ("heights", false, true), ("neither", false, false)] {
            coordinator.refreshContent = content
            coordinator.refreshHeights = heights
            let cells = coordinator.configuredCellCount
            let invalidations = coordinator.heightInvalidationCount
            let start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<10 {
                coordinator.update(rows, in: scroll)
                scroll.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
                scroll.layoutSubtreeIfNeeded()
            }
            print("ROW_UPDATE_PROBE mode=\(name) total_ms=\((ProcessInfo.processInfo.systemUptime-start)*1000) cells=\(coordinator.configuredCellCount-cells) heights=\(coordinator.heightInvalidationCount-invalidations)")
        }
    }

    func testUnchangedPresentationSkipsBuildersAndSelectionDoesNotMeasureHeight() throws {
        let coordinator = NativeTaskOutline.Coordinator()
        let scroll = NativeTaskOutline.makeScrollView(coordinator: coordinator)
        let window = InspectorPanelTestSupport.ownerWindow(for: scroll, width: 400, height: 300)
        defer { window.close() }
        var builds = 0
        func rows(selected: Int?) -> [NativeTaskOutline.Row] {
            (0..<3).map { index in
                NativeTaskOutline.Row(id: "row-\(index)", state: selected == index, layout: 50) {
                    builds += 1
                    return Text("Task \(index)").background(selected == index ? Color.gray : .clear).frame(height: 50)
                }
            }
        }
        coordinator.update(rows(selected: nil), in: scroll)
        settle(scroll)
        let before = builds
        coordinator.update(rows(selected: nil), in: scroll)
        settle(scroll)
        XCTAssertEqual(builds, before)
        XCTAssertEqual(coordinator.configuredCellCount, 0)
        XCTAssertEqual(coordinator.heightInvalidationCount, 0)
        coordinator.update(rows(selected: 1), in: scroll)
        settle(scroll)
        XCTAssertEqual(builds, before + 1)
        XCTAssertEqual(coordinator.configuredCellCount, 1)
        XCTAssertEqual(coordinator.heightInvalidationCount, 0)
    }

    func testDocumentPreviewPreservesFirstNonemptyLineAcrossBlocksAndRuns() {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: " \n ")]),
            DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: " First"), DocumentRun(text: " line \nsecond")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "Later")])
        ])
        XCTAssertEqual(TaskListViewDefaults.bodyPreview(of: document), "First line")
        XCTAssertEqual(TaskListViewDefaults.bodyPreview(of: document),
                       TaskListViewDefaults.bodyPreview(of: document.plainText))
        XCTAssertNil(TaskListViewDefaults.bodyPreview(of: .empty))
    }

    func testLayoutChangeUpdatesOnlyAffectedHeightIncludingOffscreenRows() throws {
        let coordinator = NativeTaskOutline.Coordinator()
        let scroll = NativeTaskOutline.makeScrollView(coordinator: coordinator)
        let window = InspectorPanelTestSupport.ownerWindow(for: scroll, width: 400, height: 150)
        defer { window.close() }
        func rows(tall: Bool) -> [NativeTaskOutline.Row] {
            (0..<30).map { index in
                let height = tall && index == 20 ? 82 : 50
                return NativeTaskOutline.Row(id: "row-\(index)", state: height, layout: height) {
                    Text("Task \(index)").frame(height: CGFloat(height))
                }
            }
        }
        coordinator.update(rows(tall: false), in: scroll)
        settle(scroll)
        coordinator.update(rows(tall: true), in: scroll)
        settle(scroll)
        let outline = try XCTUnwrap(coordinator.outline)
        XCTAssertEqual(coordinator.heightInvalidationCount, 1)
        outline.scrollRowToVisible(20)
        settle(scroll)
        XCTAssertEqual(outline.rect(ofRow: 20).height, 82, accuracy: 1)
    }

    private func settle(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        view.layoutSubtreeIfNeeded()
    }

    private func titleField(in view: NSView) -> TaskRowTitleField.Field? {
        if let field = view as? TaskRowTitleField.Field { return field }
        return view.subviews.lazy.compactMap { self.titleField(in: $0) }.first
    }

    func testSelectionRefreshKeepsActiveTitleEditorAndDraft() throws {
        let coordinator = NativeTaskOutline.Coordinator()
        let scroll = NativeTaskOutline.makeScrollView(coordinator: coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer { window.close() }
        func row(_ color: Color) -> NativeTaskOutline.Row {
            .init(id: "task", state: color, layout: 50) {
                TaskRowTitleField(title: "Saved title", color: color, onSelect: {},
                                  onEditingEnded: {}, onCommit: { _ in })
                    .frame(height: 50)
            }
        }
        coordinator.update([row(.primary)], in: scroll)
        settle(scroll)
        let field = try XCTUnwrap(titleField(in: scroll))
        field.editingSession = true
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor())
        editor.string = "Uncommitted draft"
        coordinator.update([row(.secondary)], in: scroll)
        settle(scroll)
        XCTAssertTrue(titleField(in: scroll) === field)
        XCTAssertTrue(field.currentEditor() === editor)
        XCTAssertEqual(editor.string, "Uncommitted draft")
        field.editingSession = false
    }

    func testContentUpdatePreservesVisibleCellAndVariableRowHeights() throws {
        let coordinator = NativeTaskOutline.Coordinator()
        let scroll = NativeTaskOutline.makeScrollView(coordinator: coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer { window.close() }
        let rows = [NativeTaskOutline.Row(id: "short") { Text("Task").frame(height: 50) },
                    NativeTaskOutline.Row(id: "tall") { Text("Preview").frame(height: 82) }]
        coordinator.update(rows, in: scroll)
        settle(scroll)
        let outline = try XCTUnwrap(coordinator.outline)
        let cell = try XCTUnwrap(outline.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NativeTaskOutline.Cell)
        let item = coordinator.items[0]
        XCTAssertEqual(outline.rect(ofRow: 0).height, 50, accuracy: 1)
        XCTAssertEqual(outline.rect(ofRow: 1).height, 82, accuracy: 1)
        XCTAssertEqual(cell.host.frame.minX, WFSpace.md, accuracy: 1)

        coordinator.update([.init(id: "short") { Text("Selected task").frame(height: 50) }, rows[1]], in: scroll)
        settle(scroll)
        XCTAssertTrue(coordinator.items[0] === item)
        XCTAssertTrue(outline.view(atColumn: 0, row: 0, makeIfNecessary: false) === cell)
    }

    func testInsertionAboveViewportKeepsReadingPosition() throws {
        let coordinator = NativeTaskOutline.Coordinator()
        let scroll = NativeTaskOutline.makeScrollView(coordinator: coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer { window.close() }
        let rows = (0..<30).map { index in
            NativeTaskOutline.Row(id: "task-\(index)") { Text("Task \(index)").frame(height: 50) }
        }
        coordinator.update(rows, in: scroll)
        settle(scroll)
        let outline = try XCTUnwrap(coordinator.outline)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 507))
        scroll.reflectScrolledClipView(scroll.contentView)
        settle(scroll)
        let first = outline.rows(in: outline.visibleRect).location
        let id = coordinator.items[first].id
        let offset = scroll.contentView.bounds.minY - outline.rect(ofRow: first).minY
        coordinator.update([.init(id: "inserted") { Text("New task").frame(height: 50) }] + rows, in: scroll)
        settle(scroll)
        let after = outline.rows(in: outline.visibleRect).location
        XCTAssertEqual(coordinator.items[after].id, id)
        XCTAssertEqual(scroll.contentView.bounds.minY - outline.rect(ofRow: after).minY, offset, accuracy: 1)
    }
}
