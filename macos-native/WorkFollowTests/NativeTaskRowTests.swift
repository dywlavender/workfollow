import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class NativeTaskRowTests: XCTestCase {
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    func testVisibleTaskRowsDoNotCreateSwiftUIHosts() throws {
        let environment = AppEnvironment(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let workspace = environment.taskWorkspace
        for i in 0..<40 { _ = workspace.createTask(title: "虚构原生任务 \(i)", in: .inbox) }
        workspace.select(nil)
        environment.navigation.destination = .inbox
        NativeTaskOutline.Diagnostics.reset()
        let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: environment.navigation)
            .environmentObject(environment).frame(width: 1280, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { window.contentView = nil; window.close() }
        let rows = descendants(host).compactMap { $0 as? NativeTaskRowView }
        XCTAssertGreaterThan(rows.count, 0)
        XCTAssertLessThan(rows.count, 40)
        XCTAssertEqual(NativeTaskOutline.Diagnostics.createdNativeRows, rows.count)
        for row in rows {
            XCTAssertFalse(descendants(row).contains { $0 is NSHostingView<AnyView> })
            XCTAssertEqual(row.titleField.font?.pointSize, 14)
            XCTAssertTrue(descendants(row).compactMap { $0 as? HoverTipTrackingView }.contains { $0.title == "完成任务" })
        }
        XCTAssertLessThanOrEqual(NativeTaskOutline.Diagnostics.createdHostingViews, 2)
    }

    func testReferenceAndNativeRowsExportAppearanceFixtures() throws {
        let now = Date(timeIntervalSince1970: 1_793_410_000)
        let tasks = (0..<5).map { index in
            Task(id: UUID(), title: ["普通任务", "带正文、日期与标签", "已经完成的任务", "带子任务的父任务", "子任务"][index],
                 document: index == 1 ? NativeDocument(plainText: "这里是第一行正文预览") : .empty,
                 tags: index == 1 ? ["工作", "重要"] : [],
                 list: .inbox, priority: index == 1 ? .high : .none,
                 schedule: index == 1 ? TaskSchedule(dueAt: now) : TaskSchedule(),
                 childOrder: index,
                 createdAt: now, updatedAt: now)
        }
        let workspace = TaskWorkspaceModel(clock: { now }, seedDemoData: false, initialTasks: tasks)
        _ = workspace.complete(tasks[2].id, in: .inbox)
        let environment = AppEnvironment(clock: { now }, directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let output = URL(fileURLWithPath: "/private/tmp/workfollow-native-row-appearance-20261101", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (appearanceName, scheme): (String, ColorScheme) in [("light", .light), ("dark", .dark)] {
            for native in [false, true] {
                NativeTaskOutline.Diagnostics.usesNativeRows = native
                defer { NativeTaskOutline.Diagnostics.usesNativeRows = true }
                let rows = tasks.enumerated().map { index, original -> NativeTaskOutline.Row in
                    let task = workspace.task(for: original.id)!
                    let depth = index == 4 ? 1 : 0
                    let hasTags = !task.tags.isEmpty
                    let height = TaskListMetrics.taskRowHeight(hasPreview: !task.document.isEmpty, hasTags: hasTags)
                    let makeNative = {
                        NativeTaskRowConfiguration(task: task, workspace: workspace, environment: environment,
                            depth: depth, hasChildren: index == 3, expanded: false,
                            bulkSelected: index == 1, recentlyCreated: false,
                            showsListBadge: false, hidesDetails: false, hiddenFields: [], allowsReordering: false,
                            dateDisplay: .taskTime, feedback: TaskDropFeedback(), onEditingRequested: {},
                            onEditingBegan: {}, onEditingEnded: {}, onSelect: {}, onBulkToggle: {}, onRangeSelect: {},
                            onComplete: {}, onRestore: {}, onToggleExpanded: {})
                    }
                    return .init(id: task.id.uuidString, taskID: task.id, state: task, layout: height,
                        height: height, native: makeNative) {
                        TaskRowView(task: task, workspace: workspace, depth: depth, hasChildren: index == 3,
                            expanded: false, selected: index == 1, showsListBadge: false,
                            onSelect: {}, onComplete: {}, onRestore: {}, onToggleExpanded: {})
                            .overlay(alignment: .bottom) {
                                if index != 1 { ListRowDivider(leading: TaskListMetrics.dividerLeading(completed: task.isClosed, depth: depth), trailing: WFSpace.lg) }
                            }
                            .environmentObject(environment)
                    }
                }
                let host = NSHostingView(rootView: NativeTaskOutline(rows: rows, selectionSource: workspace)
                    .environment(\.colorScheme, scheme).frame(width: 470, height: 310)
                    .background(WFColors.content))
                let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 470, height: 310)
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                InspectorPanelTestSupport.settle(window)
                if native {
                    let taskRows = descendants(host).compactMap { $0 as? NativeTaskRowView }
                    XCTAssertEqual(taskRows.count, 5)
                    let field = try XCTUnwrap(taskRows.first?.titleField)
                    XCTAssertEqual(field.alignmentRect(forFrame: field.frame).minX, TaskListMetrics.titleLeading)
                }
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: output.appendingPathComponent("\(appearanceName)-\(native ? "native" : "reference").png"))
                window.contentView = nil; window.close()
            }
        }
    }

    func testDateButtonUsesSharedPanelWithoutSelectingTask() throws {
        let environment = AppEnvironment(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "虚构日期任务", in: .today).taskID)
        workspace.select(nil)
        environment.navigation.destination = .inbox
        let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: environment.navigation)
            .environmentObject(environment).frame(width: 1280, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { NativeTaskDatePresenter.activeSession?.close(); window.contentView = nil; window.close() }
        let row = try XCTUnwrap(descendants(host).compactMap { $0 as? NativeTaskRowView }.first { $0.configuration?.task.id == id })
        let date = try XCTUnwrap(row.renderFrames[.init(taskID: id, part: .date)])
        try InspectorPanelTestSupport.click(date, in: row, window: window)
        let panel = try InspectorPanelTestSupport.panel(title: "日期属性", below: window)
        XCTAssertNil(workspace.selectedTaskID)
        XCTAssertFalse(row.titleField.editingSession)
        try InspectorPanelTestSupport.sendEscape(to: panel)
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(NativeTaskDatePresenter.activeSession)
    }

    func testSwitchingListCommitsOutgoingChineseTitleComposition() throws {
        let environment = AppEnvironment(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "虚构旧标题", in: .inbox).taskID)
        workspace.select(nil)
        environment.navigation.destination = .inbox
        let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: environment.navigation)
            .environmentObject(environment).frame(width: 1280, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { window.contentView = nil; window.close() }
        let row = try XCTUnwrap(descendants(host).compactMap { $0 as? NativeTaskRowView }.first { $0.configuration?.task.id == id })
        row.titleField.beginEditing()
        let editor = try XCTUnwrap(row.titleField.currentEditor() as? NSTextView)
        editor.setMarkedText("中文标题", selectedRange: NSRange(location: 4, length: 0),
                             replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        environment.navigate(to: .today)
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(workspace.task(for: id)?.title, "中文标题")
    }
}
