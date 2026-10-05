import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskSwitchingTests: XCTestCase {
    private func editor(in view: NSView) -> NativeTextView? {
        if let text = view as? NativeTextView { return text }
        return view.subviews.lazy.compactMap { self.editor(in: $0) }.first
    }

    func testInspectorSwitchLatencyAndDocumentBinding() throws {
        let environment = AppEnvironment()
        for lines in [0, 20, 200] {
            let workspace = TaskWorkspaceModel(seedDemoData: false)
            let ids = try (0..<2).map { index -> UUID in
                let id = try XCTUnwrap(workspace.createTask(title: "任务\(index)", in: .inbox).taskID)
                let text = (0..<lines).map { "任务\(index) 第\($0)行：切换性能验收正文" }.joined(separator: "\n")
                _ = workspace.setDocument(id, NativeDocument(plainText: text))
                return id
            }
            workspace.select(ids[0])
            let host = NSHostingView(rootView: TaskInspectorShell(workspace: workspace, showBack: false)
                .environmentObject(environment).frame(width: 520, height: 650))
            let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 520, height: 650)
            defer { window.close() }
            var previous = try XCTUnwrap(editor(in: host))
            var rebuilds = 0
            var samples: [Double] = []
            for iteration in 0..<20 {
                let id = ids[(iteration + 1) % 2]
                let start = ProcessInfo.processInfo.systemUptime
                workspace.select(id)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.001))
                host.layoutSubtreeIfNeeded()
                let current = try XCTUnwrap(editor(in: host))
                samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                if current !== previous { rebuilds += 1 }
                XCTAssertTrue(current === previous, "Task switches must rebind, not recreate the editor")
                previous = current
                XCTAssertEqual(current.documentIdentity, id)
                XCTAssertEqual(current.string, workspace.task(for: id)?.document.plainText)
            }
            samples.sort()
            print("TASK_SWITCH lines=\(lines) p50_ms=\(samples[10]) p95_ms=\(samples[18]) rebuilds=\(rebuilds)/20")
        }
    }

    func testReusedInspectorCommitsCompositionToOldTaskAndClearsFocusAndUndo() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let first = try XCTUnwrap(workspace.createTask(title: "第一任务", in: .inbox).taskID)
        let second = try XCTUnwrap(workspace.createTask(title: "第二任务", in: .inbox).taskID)
        _ = workspace.setDocument(second, NativeDocument(plainText: "第二正文"))
        workspace.select(first)
        let host = NSHostingView(rootView: TaskInspectorShell(workspace: workspace, showBack: false)
            .environmentObject(AppEnvironment()).frame(width: 520, height: 650))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 520, height: 650)
        defer { window.close() }
        let original = try XCTUnwrap(editor(in: host))
        window.makeFirstResponder(original)
        original.insertText("第一正文", replacementRange: NSRange(location: 0, length: 0))
        original.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0),
                               replacementRange: NSRange(location: NSNotFound, length: 0))
        workspace.select(second)
        InspectorPanelTestSupport.settle(window)
        let rebound = try XCTUnwrap(editor(in: host))
        XCTAssertTrue(rebound === original)
        XCTAssertEqual(workspace.task(for: first)?.document.plainText, "第一正文中文")
        XCTAssertEqual(workspace.task(for: second)?.document.plainText, "第二正文")
        XCTAssertEqual(rebound.string, "第二正文")
        XCTAssertFalse(rebound.hasMarkedText())
        XCTAssertEqual(rebound.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertFalse(rebound.undoManager?.canUndo ?? true)
        XCTAssertFalse(window.firstResponder === rebound)
        XCTAssertNil(rebound.slashPanel)
        XCTAssertNil(rebound.selectionPanel)
        window.makeFirstResponder(rebound)
        rebound.insertText("新", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(workspace.task(for: second)?.document.plainText, "新第二正文")
        XCTAssertEqual(workspace.task(for: first)?.document.plainText, "第一正文中文")
    }

    func testSplitViewSwitchLatencyUnderTaskVolume() throws {
        let environment = AppEnvironment()
        for count in [100, 500] {
            let workspace = TaskWorkspaceModel(seedDemoData: false)
            var ids: [UUID] = []
            for index in 0..<count {
                ids.append(try XCTUnwrap(workspace.createTask(title: "任务\(index)", in: .inbox).taskID))
            }
            for id in ids.prefix(2) { _ = workspace.setDocument(id, NativeDocument(plainText: "切换正文")) }
            workspace.select(ids[0])
            let navigation = AppNavigation()
            navigation.destination = .inbox
            let host = NSHostingView(rootView: TaskSwitchSplitFixture(workspace: workspace, navigation: navigation)
                .environmentObject(environment).frame(width: 1050, height: 650))
            let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1050, height: 650)
            defer { window.close() }
            let original = try XCTUnwrap(editor(in: host))
            var samples: [Double] = []
            for iteration in 0..<20 {
                let id = ids[(iteration + 1) % 2]
                let start = ProcessInfo.processInfo.systemUptime
                workspace.select(id)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.001))
                host.layoutSubtreeIfNeeded()
                samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                XCTAssertEqual(try XCTUnwrap(editor(in: host)).documentIdentity, id)
                XCTAssertTrue(editor(in: host) === original)
            }
            samples.sort()
            print("TASK_SPLIT_SWITCH tasks=\(count) p50_ms=\(samples[10]) p95_ms=\(samples[18])")
        }
    }

    func testSplitViewNativeTitleClicksSwitchInspectorOnFirstClick() throws {
        final class Probe { var frames: [TaskTreeRenderAnchor: CGRect] = [:] }
        let probe = Probe()
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let first = try XCTUnwrap(workspace.createTask(title: "第一任务", in: .inbox).taskID)
        let second = try XCTUnwrap(workspace.createTask(title: "第二任务", in: .inbox).taskID)
        let navigation = AppNavigation()
        navigation.destination = .inbox
        workspace.select(first)
        let host = NSHostingView(rootView: TaskSwitchSplitFixture(workspace: workspace, navigation: navigation)
            .environmentObject(AppEnvironment()).frame(width: 1050, height: 650)
            .coordinateSpace(name: "task-tree-render")
            .onPreferenceChange(TaskTreeFramesKey.self) { probe.frames = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1050, height: 650)
        defer { window.close() }
        for index in 0..<10 {
            let id = index.isMultiple(of: 2) ? second : first
            let frame = try XCTUnwrap(probe.frames[.init(taskID: id, part: .title)])
            try InspectorPanelTestSupport.click(frame, in: host, window: window)
            XCTAssertEqual(workspace.selectedTaskID, id)
            XCTAssertEqual(try XCTUnwrap(editor(in: host)).documentIdentity, id)
            XCTAssertTrue(workspace.bulkSelection.isEmpty)
        }
    }
}

private struct TaskSwitchSplitFixture: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let navigation: AppNavigation
    var body: some View {
        HStack(spacing: 0) {
            VStack {
                Text("今天 \(workspace.count(for: NativeDestination.today))")
                Text("明天 \(workspace.count(for: NativeDestination.tomorrow))")
                Text("收集箱 \(workspace.count(for: NativeDestination.inbox))")
                Text("所有 \(workspace.count(for: NativeDestination.allTasks))")
            }.frame(width: 110)
            TaskListView(workspace: workspace, navigation: navigation, navigationVisible: true).frame(width: 420)
            TaskInspectorShell(workspace: workspace, showBack: false).frame(width: 520)
        }
    }
}
