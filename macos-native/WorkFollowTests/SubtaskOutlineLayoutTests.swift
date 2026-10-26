import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class SubtaskOutlineLayoutTests: XCTestCase {
    private let children: [String: [String]] = [
        "根": ["甲", "乙", "丙"],
        "甲": ["甲一", "甲二"],
        "甲一": ["甲一一"],
        "乙": ["乙一"]
    ]

    func testNestedFoldsCountEveryHiddenDescendantOnce() {
        let open = layout(collapsed: [])
        XCTAssertEqual(open.visibleRowCount, 7)
        XCTAssertEqual(open.hiddenRowCount, 0)

        let nested = layout(collapsed: ["甲一"])
        XCTAssertEqual(nested.visibleRowCount, 6)
        XCTAssertEqual(nested.hiddenRowCount, 1)

        let ancestorAndNested = layout(collapsed: ["甲", "甲一"])
        XCTAssertEqual(ancestorAndNested.visibleRowCount, 4)
        XCTAssertEqual(ancestorAndNested.hiddenRowCount, 3,
                       "The nested folded node must not count its hidden child twice")
        XCTAssertEqual(ancestorAndNested.totalRowCount, open.totalRowCount)
        XCTAssertEqual(ancestorAndNested.height(rowHeight: 40), 160)

        XCTAssertEqual(layout(collapsed: ["甲一"]), nested,
                       "Reopening the ancestor preserves the inner fold")
    }

    func testIndependentBranchesCollapseWithoutRemovingTheirOwnRows() {
        let folded = layout(collapsed: ["甲", "乙"])
        XCTAssertEqual(folded.visibleRowCount, 3, "Direct children remain visible")
        XCTAssertEqual(folded.hiddenRowCount, 4)
        XCTAssertEqual(folded.height(rowHeight: 40), 120)
    }

    func testLeafOrRemovedFoldRecordsDoNotChangeTheCurrentTree() {
        XCTAssertEqual(layout(collapsed: ["丙", "已移除的子任务"]), layout(collapsed: []))
    }

    func testEmptyTreeHasNoReservedOutlineHeight() {
        let result = SubtaskOutlineLayout.measure(under: "空根", children: { _ in [String]() },
                                                  collapsed: Set<String>())
        XCTAssertEqual(result.visibleRowCount, 0)
        XCTAssertEqual(result.hiddenRowCount, 0)
        XCTAssertEqual(result.height(rowHeight: 40), 0)
    }

    /// Uses the production inspector, its following add-child row, and the
    /// production outline. Counting native rows alone missed the old blank gap.
    func testInspectorReclaimsSpaceOnCollapseAndRestoresNestedFoldHeight() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("subtask-layout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        let parent = try XCTUnwrap(workspace.createTask(title: "折叠布局父任务", in: .inbox).taskID)
        let alpha = try XCTUnwrap(workspace.createChild(parent, title: "甲").taskID)
        let beta = try XCTUnwrap(workspace.createChild(parent, title: "乙").taskID)
        _ = workspace.createChild(parent, title: "丙")
        let alphaOne = try XCTUnwrap(workspace.createChild(alpha, title: "甲一").taskID)
        _ = workspace.createChild(alpha, title: "甲二")
        _ = workspace.createChild(alphaOne, title: "甲一一")
        _ = workspace.createChild(beta, title: "乙一")
        workspace.select(parent)

        let foldStore = SubtaskFoldStore()
        defer {
            foldStore.setCollapsed(false, for: alpha)
            foldStore.setCollapsed(false, for: alphaOne)
        }
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace,
            width: 820, height: 900, environment: environment, onFrames: { frames = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 820, height: 900)
        defer { window.close() }
        let outline = try XCTUnwrap(findOutline(in: host))
        XCTAssertEqual(outline.numberOfRows, 7)
        let expandedAddRow = try XCTUnwrap(frames[.addChild])

        func item(_ id: UUID) throws -> Any {
            let index = try XCTUnwrap((0..<outline.numberOfRows).first {
                (outline.item(atRow: $0) as? Task)?.id == id
            })
            return try XCTUnwrap(outline.item(atRow: index))
        }
        func assertOutlineRows(_ expected: Int, file: StaticString = #filePath, line: UInt = #line) {
            InspectorPanelTestSupport.settle(window)
            XCTAssertEqual(outline.numberOfRows, expected, file: file, line: line)
            XCTAssertEqual(outline.frame.height,
                           CGFloat(expected) * TaskInspectorMetrics.childRowMinHeight,
                           accuracy: 1, "The SwiftUI host must shrink with the native outline",
                           file: file, line: line)
            XCTAssertEqual(outline.rect(ofRow: expected - 1).maxY, outline.frame.height,
                           accuracy: 1, "Native row spacing must not clip the last row or leave a trailing gutter",
                           file: file, line: line)
        }

        outline.collapseItem(try item(alphaOne))
        assertOutlineRows(6)
        outline.collapseItem(try item(alpha))
        assertOutlineRows(4)
        let collapsedAddRow = try XCTUnwrap(frames[.addChild])
        XCTAssertLessThan(collapsedAddRow.minY,
                          expandedAddRow.minY - 2 * TaskInspectorMetrics.childRowMinHeight,
                          "Following content must move up rather than leave expanded-height blank space")

        outline.expandItem(try item(alpha))
        assertOutlineRows(6)
        outline.expandItem(try item(alphaOne))
        assertOutlineRows(7)
    }

    private func layout(collapsed: Set<String>) -> SubtaskOutlineLayout {
        SubtaskOutlineLayout.measure(under: "根", children: { children[$0] ?? [] }, collapsed: collapsed)
    }

    private func findOutline(in view: NSView) -> SubtaskOutlineView? {
        if let outline = view as? SubtaskOutlineView { return outline }
        return view.subviews.lazy.compactMap { self.findOutline(in: $0) }.first
    }
}
