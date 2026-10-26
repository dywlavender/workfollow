import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskRowInteractionTests: XCTestCase {
    func testDropFeedbackHasOnlyOneTargetAndIgnoresStaleExit() {
        let feedback = TaskDropFeedback()
        defer { feedback.clear() }
        let first = UUID(), second = UUID()
        feedback.update(rowID: first, placement: .before(first))
        feedback.update(rowID: second, placement: .childOf(second))
        XCTAssertEqual(feedback.target, .init(rowID: second, placement: .childOf(second)))
        feedback.exit(rowID: first)
        XCTAssertEqual(feedback.target?.rowID, second)
        feedback.exit(rowID: second)
        XCTAssertNil(feedback.target)
    }

    func testDropFeedbackClearsOnReleaseAndNeverRetainsInsertionAndParentHintsTogether() {
        let feedback = TaskDropFeedback()
        let id = UUID()
        feedback.update(rowID: id, placement: .before(id))
        feedback.update(rowID: id, placement: .childOf(id))
        XCTAssertEqual(feedback.target?.placement, .childOf(id))
        feedback.clearIfReleased(pressedButtons: 1)
        XCTAssertNotNil(feedback.target)
        feedback.clearIfReleased(pressedButtons: 0)
        XCTAssertNil(feedback.target)
        feedback.update(rowID: id, placement: .after(id))
        feedback.clear()
        XCTAssertNil(feedback.target)
        XCTAssertEqual(TaskListMetrics.dragMarkerHeight, 1)
    }

    func testReorderDropProposesMoveAndPreservesTaskIdentity() throws {
        XCTAssertEqual(TaskReorderDropDelegate.moveProposal.operation, .move)
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let first = try XCTUnwrap(workspace.createTask(title: "第一项", in: .inbox).taskID)
        let second = try XCTUnwrap(workspace.createTask(title: "第二项", in: .inbox).taskID)
        let original = workspace.groups(for: .inbox).flatMap(\.tasks).map(\.id)
        workspace.select(first)
        XCTAssertTrue(TaskReorderDropDelegate.apply(payload: second.uuidString, before: first, workspace: workspace))
        XCTAssertEqual(workspace.groups(for: .inbox).flatMap(\.tasks).map(\.id), [second, first])
        XCTAssertEqual(workspace.selectedTaskID, first)
        XCTAssertFalse(TaskReorderDropDelegate.apply(payload: first.uuidString, before: first, workspace: workspace))
        workspace.undo()
        XCTAssertEqual(workspace.groups(for: .inbox).flatMap(\.tasks).map(\.id), original)
    }

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
        let workspace: TaskWorkspaceModel
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

        func doubleClick(_ frame: CGRect) throws {
            try InspectorPanelTestSupport.doubleClick(frame, in: host, window: window)
        }
    }

    private func fixture(completed: Bool = false, modifierRouting: Bool = false,
                         allowsReordering: Bool = true) throws -> Fixture {
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
                        allowsReordering: allowsReordering,
                        onSelect: { probe.selections += 1 },
                        onBulkToggle: modifierRouting ? { _ in probe.bulkToggles += 1 } : nil,
                        onRangeSelect: modifierRouting ? { _ in probe.rangeSelections += 1 } : nil,
                        onComplete: { probe.completions += 1 },
                        onRestore: { probe.restores += 1 },
                        onToggleExpanded: { probe.expansions += 1 })
            Spacer(minLength: 0)
        }
        .frame(width: 600, height: 180, alignment: .topLeading)
        .environment(\.recordsTaskTreeFrames, true)
        .coordinateSpace(name: "task-tree-render")
        .onPreferenceChange(TaskTreeFramesKey.self) { probe.frames = $0 }
        .environmentObject(AppEnvironment())
        let host = NSHostingView(rootView: AnyView(root))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 600, height: 180)
        return Fixture(workspace: workspace, window: window, host: host, probe: probe, id: id)
    }

    func testSingleTitleClickSelectsAndStartsInlineEditing() throws {
        let fixture = try fixture()
        defer { fixture.window.close() }
        try fixture.click(try fixture.frame(.title))
        XCTAssertEqual(fixture.probe.selections, 1)
        XCTAssertNotNil(fixture.window.firstResponder as? NSTextView,
                        "单击标题应直接进入行内编辑")
    }

    func testDoubleClickTitleEditsAndReturnCommitsWhileEscapeCancels() throws {
        let fixture = try fixture()
        defer { fixture.window.close() }
        try fixture.doubleClick(try fixture.frame(.title))
        let editor = try XCTUnwrap(fixture.window.firstResponder as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("新的行内标题", replacementRange: editor.selectedRange())
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(fixture.workspace.task(for: fixture.id)?.title, "新的行内标题")
        try fixture.doubleClick(try fixture.frame(.title))
        let nextEditor = try XCTUnwrap(fixture.window.firstResponder as? NSTextView)
        nextEditor.selectAll(nil)
        nextEditor.insertText("放弃这次修改", replacementRange: nextEditor.selectedRange())
        try InspectorPanelTestSupport.sendEscape(to: fixture.window)
        XCTAssertEqual(fixture.workspace.task(for: fixture.id)?.title, "新的行内标题")
    }

    func testDropZonesDistinguishSiblingParentAndIndependentPlacement() {
        let root = UUID(), child = UUID()
        XCTAssertEqual(TaskReorderDropDelegate.destination(at: CGPoint(x: 100, y: 2), rowHeight: 50,
                         depth: 0, targetID: root, parentID: nil), .before(root))
        XCTAssertEqual(TaskReorderDropDelegate.destination(at: CGPoint(x: 100, y: 25), rowHeight: 50,
                         depth: 0, targetID: root, parentID: nil), .childOf(root))
        XCTAssertEqual(TaskReorderDropDelegate.destination(at: CGPoint(x: 100, y: 48), rowHeight: 50,
                         depth: 1, targetID: child, parentID: root), .after(child))
        XCTAssertEqual(TaskReorderDropDelegate.destination(at: CGPoint(x: 2, y: 25), rowHeight: 50,
                         depth: 1, targetID: child, parentID: root), .rootAfter(root))
    }

    func testHierarchyMoveExpandsDestinationAndKeepsSelectedChild() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let first = try XCTUnwrap(workspace.createTask(title: "旧父任务", in: .inbox).taskID)
        let second = try XCTUnwrap(workspace.createTask(title: "新父任务", in: .inbox).taskID)
        let child = try XCTUnwrap(workspace.createChild(first, title: "子任务").taskID)
        workspace.select(child)
        workspace.toggleExpanded(second)
        XCTAssertTrue(TaskReorderDropDelegate.apply(payload: child.uuidString,
                      placement: .childOf(second), workspace: workspace))
        XCTAssertEqual(workspace.task(for: child)?.parentID, second)
        XCTAssertEqual(workspace.selectedTaskID, child)
        XCTAssertFalse(workspace.collapsedTaskIDs.contains(second))
        workspace.undo()
        XCTAssertEqual(workspace.task(for: child)?.parentID, first)
        XCTAssertEqual(workspace.selectedTaskID, child)
    }

    func testFullListTitleSingleClickKeepsFieldEditorFocusAndCommits() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "完整列表标题", in: .inbox).taskID)
        let navigation = AppNavigation()
        navigation.destination = .inbox
        let probe = Probe()
        let root = TaskListView(workspace: workspace, navigation: navigation, navigationVisible: true)
            .frame(width: 600, height: 600)
            .environment(\.recordsTaskTreeFrames, true)
            .coordinateSpace(name: "task-tree-render")
            .onPreferenceChange(TaskTreeFramesKey.self) { probe.frames = $0 }
            .environmentObject(AppEnvironment())
        let host = NSHostingView(rootView: AnyView(root))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 600, height: 600)
        defer { window.close() }
        let title = try XCTUnwrap(probe.frames[.init(taskID: id, part: .title)])
        try InspectorPanelTestSupport.click(title, in: host, window: window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView,
                                  "List focus must not steal the title field editor")
        editor.selectAll(nil)
        func sendKey(_ characters: String, code: UInt16) throws {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
            NSApp.sendEvent(event)
            InspectorPanelTestSupport.settle(window)
        }
        try sendKey("t", code: 17)
        try sendKey(" ", code: 49)
        try sendKey("x", code: 7)
        XCTAssertFalse(try XCTUnwrap(workspace.task(for: id)).isClosed,
                       "Space in the title must not complete the selected task")
        try sendKey("\r", code: 36)
        XCTAssertEqual(workspace.task(for: id)?.title, "t x")
        XCTAssertEqual(workspace.selectedTaskID, id)
    }

    func testFullListRightClickReachesReferenceMenuAndItsChildPanels() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "列表右键入口验收", in: .inbox).taskID)
        let navigation = AppNavigation()
        navigation.destination = .inbox
        let environment = AppEnvironment()
        environment.focusStore.notifier = nil
        let probe = Probe()
        let root = TaskListView(workspace: workspace, navigation: navigation, navigationVisible: true)
            .frame(width: 1000, height: 700)
            .environment(\.recordsTaskTreeFrames, true)
            .coordinateSpace(name: "task-tree-render")
            .onPreferenceChange(TaskTreeFramesKey.self) { probe.frames = $0 }
            .environmentObject(environment)
        let host = NSHostingView(rootView: AnyView(root))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1000, height: 700)
        defer { TaskContextMenuPresenter.activeSession?.close(); window.close() }
        let title = try XCTUnwrap(probe.frames[.init(taskID: id, part: .title)])
        let local = NSPoint(x: title.midX, y: host.isFlipped ? title.midY : host.bounds.height - title.midY)
        let point = host.convert(local, to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: point,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        NSApp.postEvent(event, atStart: true)
        let down = try XCTUnwrap(NSApp.nextEvent(matching: .rightMouseDown, until: Date(),
                                                inMode: .default, dequeue: true))
        NSApp.sendEvent(down)
        InspectorPanelTestSupport.settle(window)
        let session = try XCTUnwrap(TaskContextMenuPresenter.activeSession,
                                    "真实列表行必须打开共享菜单，而不是文本系统菜单")
        let menu = try XCTUnwrap(session.coordinator.panel)
        XCTAssertEqual(menu.title, "任务右键菜单")
        XCTAssertNil(workspace.selectedTaskID, "右键不能变成左键选择或编辑")

        var actions: [TaskContextMenuAnchor: CGRect] = [:]
        var focus: [InspectorRenderAnchor: CGRect] = [:]
        var lists: [TaskContextSubmenuAnchor: CGRect] = [:]
        var tags: [TaskTagPickerAnchor: CGRect] = [:]
        let productionRoot = session.coordinator.root
        session.coordinator.root = AnyView(productionRoot
            .onPreferenceChange(TaskContextMenuFrames.self) { actions = $0 }
            .environment(\.popupContentObservation, { content in
                AnyView(content.coordinateSpace(name: "inspector-render")
                    .onPreferenceChange(InspectorFramesKey.self) { if !$0.isEmpty { focus = $0 } }
                    .onPreferenceChange(TaskContextSubmenuFrames.self) { if !$0.isEmpty { lists = $0 } }
                    .onPreferenceChange(TaskTagPickerFrames.self) { if !$0.isEmpty { tags = $0 } })
            }))
        session.coordinator.update()
        InspectorPanelTestSupport.settle(window)
        for title in ["添加子任务", "关联主任务", "置顶", "放弃", "移动到", "标签", "开始专注",
                      "创建副本", "复制链接", "打开便签", "转换为笔记", "删除"] {
            XCTAssertNotNil(actions[.action(title)], "缺少截图中的菜单项：" + title)
        }
        func open(_ title: String, panelTitle: String) throws -> NSPanel {
            let target = try XCTUnwrap(actions[.action(title)])
            XCTAssertTrue(try XCTUnwrap(menu.contentView).bounds.contains(target),
                          "重新挂载后主卡必须按完整内容收高，不能只剩首次测量高度")
            if let directory = ProcessInfo.processInfo.environment["WF_CONTEXT_MENU_ARTIFACTS"],
               let view = menu.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("actual-entry-" + title + ".png"))
            }
            try InspectorPanelTestSupport.click(target,
                in: try XCTUnwrap(menu.contentView), window: menu)
            return try InspectorPanelTestSupport.panel(title: panelTitle, below: window)
        }
        let move = try open("移动到", panelTitle: "移动到清单")
        XCTAssertNotNil(lists[.search])
        XCTAssertNotNil(lists[.list(TaskList.inbox.name)])
        try InspectorPanelTestSupport.sendEscape(to: window)
        XCTAssertFalse(move.isVisible)
        let tag = try open("标签", panelTitle: "任务标签")
        XCTAssertNotNil(tags[.confirm])
        XCTAssertNotNil(tags[.cancel])
        try InspectorPanelTestSupport.sendEscape(to: window)
        XCTAssertFalse(tag.isVisible)
        let timer = try open("开始专注", panelTitle: "任务专注")
        for action: InspectorRenderAnchor in [.focusPomodoro, .focusStopwatch, .focusEstimate] {
            XCTAssertNotNil(focus[action])
        }
        try InspectorPanelTestSupport.sendEscape(to: window)
        XCTAssertFalse(timer.isVisible)
        XCTAssertTrue(menu.isVisible)
        XCTAssertEqual(environment.focusStore.phase, .idle)
        XCTAssertEqual(workspace.task(for: id)?.title, "列表右键入口验收")
    }

    func testReorderHandleDoesNotShiftContentColumns() throws {
        let withoutHandle = try fixture(allowsReordering: false)
        defer { withoutHandle.window.close() }
        let withHandle = try fixture(allowsReordering: true)
        defer { withHandle.window.close() }
        for part: TaskTreeRenderPart in [.row, .disclosure, .checkbox, .title, .preview] {
            XCTAssertEqual(try withHandle.frame(part), try withoutHandle.frame(part))
        }
    }

    func testTitlePreviewAndPaddingEachEnterTitleEditingWithoutDuplicateSelection() throws {
        for part: TaskTreeRenderPart in [.title, .preview, .row] {
            let fixture = try fixture()
            defer { fixture.window.close() }
            let frame = try fixture.frame(part)
            let target = part == .row
                ? CGRect(x: frame.minX + 2, y: frame.minY + 2, width: 2, height: 2) : frame
            try fixture.click(target)
            XCTAssertEqual(fixture.probe.selections, 1)
            let editor = try XCTUnwrap(fixture.window.firstResponder as? NSTextView)
            XCTAssertEqual(editor.selectedRange().length, 0)
            if part != .title {
                XCTAssertEqual(editor.selectedRange().location, editor.string.utf16.count)
            }
            XCTAssertEqual(fixture.probe.completions, 0)
            XCTAssertEqual(fixture.probe.expansions, 0)
        }
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

    func testNonKeyWindowFirstClickDoesNotEnterBulkSelection() throws {
        let fixture = try fixture(modifierRouting: true)
        defer { fixture.window.close() }
        let other = InspectorPanelTestSupport.ownerWindow(for: NSView(), width: 200, height: 100)
        defer { other.close() }
        for part: TaskTreeRenderPart in [.title, .preview] {
            other.makeKeyAndOrderFront(nil)
            InspectorPanelTestSupport.settle(other)
            XCTAssertFalse(fixture.window.isKeyWindow)
            let previous = fixture.probe.selections
            try fixture.click(try fixture.frame(part))
            XCTAssertEqual(fixture.probe.selections, previous + 1,
                           "The activation click must also perform ordinary selection")
            XCTAssertEqual(fixture.probe.bulkToggles, 0)
            XCTAssertEqual(fixture.probe.rangeSelections, 0)
        }
    }
}
