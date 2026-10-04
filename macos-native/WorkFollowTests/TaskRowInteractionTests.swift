import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskRowInteractionTests: XCTestCase {
    func testReorderProjectionAndUndoPreserveSelectedTaskAcrossBothDirections() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let ids = try (0..<3).map { index in
            try XCTUnwrap(workspace.createTask(title: "排序验收 \(index)", in: .inbox).taskID)
        }
        let original = workspace.groups(for: .inbox).flatMap(\.tasks).map(\.id)
        XCTAssertEqual(Set(original), Set(ids))
        workspace.select(ids[1])
        let first = try XCTUnwrap(original.first)
        let last = try XCTUnwrap(original.last)

        for _ in 0..<10 {
            workspace.reorder(last, before: first)
            XCTAssertEqual(workspace.groups(for: .inbox).flatMap(\.tasks).map(\.id),
                           [last] + original.filter { $0 != last })
            XCTAssertEqual(workspace.selectedTask?.id, ids[1])
            workspace.undo()
            XCTAssertEqual(workspace.groups(for: .inbox).flatMap(\.tasks).map(\.id), original)
            workspace.reorder(first, before: last)
            var downward = original.filter { $0 != first }
            downward.insert(first, at: try XCTUnwrap(downward.firstIndex(of: last)))
            XCTAssertEqual(workspace.groups(for: .inbox).flatMap(\.tasks).map(\.id), downward)
            XCTAssertEqual(workspace.selectedTask?.id, ids[1])
            workspace.undo()
            XCTAssertEqual(workspace.groups(for: .inbox).flatMap(\.tasks).map(\.id), original)
            XCTAssertEqual(workspace.selectedTask?.id, ids[1])
        }
    }

    private final class Probe {
        var frames: [TaskTreeRenderAnchor: CGRect] = [:]
        var selections = 0
        var completions = 0
        var restores = 0
        var expansions = 0
        var bulkToggles = 0
        var rangeSelections = 0
    }

    @MainActor
    private struct Fixture {
        let window: NSWindow
        let host: NSHostingView<AnyView>
        let probe: Probe
        let id: UUID

        func frame(_ part: TaskTreeRenderPart) throws -> CGRect {
            try XCTUnwrap(probe.frames[.init(taskID: id, part: part)])
        }

        func click(_ frame: CGRect) throws {
            try InspectorPanelTestSupport.click(frame, in: host, window: window)
        }
    }

    private func fixture(completed: Bool = false, modifierRouting: Bool = false) throws -> Fixture {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "点击归属验收", in: .inbox).taskID)
        _ = workspace.setDocument(id, NativeDocument(plainText: "第二行预览"))
        _ = workspace.setDueDate(id, Date())
        if completed { _ = workspace.complete(id) }
        let task = try XCTUnwrap(workspace.task(for: id))
        let probe = Probe()
        let root = VStack(spacing: 0) {
            TaskRowView(task: task, workspace: workspace, depth: 0, hasChildren: true,
                        expanded: true, selected: false,
                        onSelect: { probe.selections += 1 },
                        onBulkToggle: modifierRouting ? { _ in probe.bulkToggles += 1 } : nil,
                        onRangeSelect: modifierRouting ? { _ in probe.rangeSelections += 1 } : nil,
                        onComplete: { probe.completions += 1 },
                        onRestore: { probe.restores += 1 },
                        onToggleExpanded: { probe.expansions += 1 })
            Spacer(minLength: 0)
        }
        .frame(width: 600, height: 180, alignment: .topLeading)
        .coordinateSpace(name: "task-tree-render")
        .onPreferenceChange(TaskTreeFramesKey.self) { probe.frames = $0 }
        .environmentObject(AppEnvironment())
        let host = NSHostingView(rootView: AnyView(root))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 600, height: 180)
        return Fixture(window: window, host: host, probe: probe, id: id)
    }

    func testTitlePreviewAndPaddingEachSelectExactlyOnceAcrossThirtyClicks() throws {
        let fixture = try fixture()
        defer { fixture.window.close() }
        let row = try fixture.frame(.row)
        let targets = [try fixture.frame(.title), try fixture.frame(.preview),
                       CGRect(x: row.minX + 2, y: row.minY + 2, width: 2, height: 2)]
        for n in 0..<30 {
            try fixture.click(targets[n % targets.count])
            XCTAssertEqual(fixture.probe.selections, n + 1)
            if fixture.probe.selections != n + 1 { break }
        }
        XCTAssertEqual(fixture.probe.completions, 0)
        XCTAssertEqual(fixture.probe.expansions, 0)
    }

    func testCompletionAndDisclosureDoNotAlsoSelectRow() throws {
        let fixture = try fixture()
        defer { fixture.window.close() }
        for n in 0..<10 {
            try fixture.click(try fixture.frame(.checkbox))
            XCTAssertEqual(fixture.probe.completions, n + 1)
            try fixture.click(try fixture.frame(.disclosure))
            XCTAssertEqual(fixture.probe.expansions, n + 1)
            XCTAssertEqual(fixture.probe.selections, 0)
        }
        XCTAssertEqual(fixture.probe.restores, 0)
    }

    func testCompletedCheckboxRestoresWithoutSelecting() throws {
        let fixture = try fixture(completed: true)
        defer { fixture.window.close() }
        try fixture.click(try fixture.frame(.checkbox))
        XCTAssertEqual(fixture.probe.restores, 1)
        XCTAssertEqual(fixture.probe.completions, 0)
        XCTAssertEqual(fixture.probe.selections, 0)
    }

    func testDateOpensScheduleWithoutSelectingAndEscapeKeepsRowClickable() throws {
        let fixture = try fixture()
        defer { fixture.window.close() }
        try fixture.click(try fixture.frame(.date))
        _ = try InspectorPanelTestSupport.panel(title: "日期属性", below: fixture.window)
        XCTAssertEqual(fixture.probe.selections, 0)
        try InspectorPanelTestSupport.sendEscape(to: fixture.window)
        XCTAssertTrue(InspectorPanelTestSupport.visibleWindows(below: fixture.window).isEmpty)
        try fixture.click(try fixture.frame(.title))
        XCTAssertEqual(fixture.probe.selections, 1)
    }

    func testModifierClicksRouteOnlyTheirOwnActionAndPlainClickDoesNotInheritCommand() throws {
        let fixture = try fixture(modifierRouting: true)
        defer { fixture.window.close() }
        let title = try fixture.frame(.title)
        try InspectorPanelTestSupport.click(title, in: fixture.host, window: fixture.window,
                                            modifiers: .command)
        XCTAssertEqual(fixture.probe.bulkToggles, 1)
        XCTAssertEqual(fixture.probe.selections, 0)
        XCTAssertEqual(fixture.probe.rangeSelections, 0)
        try fixture.click(title)
        XCTAssertEqual(fixture.probe.selections, 1)
        XCTAssertEqual(fixture.probe.bulkToggles, 1)
        try InspectorPanelTestSupport.click(title, in: fixture.host, window: fixture.window,
                                            modifiers: .shift)
        XCTAssertEqual(fixture.probe.rangeSelections, 1)
        XCTAssertEqual(fixture.probe.selections, 1)
        XCTAssertEqual(fixture.probe.bulkToggles, 1)
    }
}
