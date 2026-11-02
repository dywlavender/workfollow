import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskListEditorInteractionTests: XCTestCase {
    private final class State: ObservableObject { @Published var visible = false }
    private final class Probe { var frames: [ListManagementAnchor: CGRect] = [:] }
    private struct Host: View {
        @ObservedObject var state: State
        let workspace: TaskWorkspaceModel
        let preferences: TaskViewPreferenceStore
        let probe: Probe
        var copies = false
        var body: some View {
            Color.clear.frame(width: 720, height: 720)
                .sheet(isPresented: $state.visible) {
                    Group {
                        if copies { TaskListCopyView(workspace: workspace, source: "工作") }
                        else { TaskListEditorView(workspace: workspace, preferences: preferences, name: "工作") }
                    }.onPreferenceChange(ListManagementFrames.self) { probe.frames = $0 }
                }
        }
    }

    func testSaveWritesEditedTitleAndSelectedViewThenClosesSheet() throws {
        try exercise(save: true)
    }

    func testCancelLeavesTitleAndViewUnchanged() throws {
        try exercise(save: false)
    }

    func testCopyDialogUsesTheSelectedScope() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("list-copy-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let active = Task(id: UUID(), title: "待办", list: TaskList(name: "工作"), priority: .none,
                          schedule: TaskSchedule(), childOrder: 0, createdAt: now, updatedAt: now)
        let closed = Task(id: UUID(), title: "已完成", list: TaskList(name: "工作"), priority: .none,
                          schedule: TaskSchedule(), status: .completed, childOrder: 0,
                          createdAt: now, updatedAt: now, completedAt: now)
        let workspace = TaskWorkspaceModel(seedDemoData: false, initialTasks: [active, closed], initialLists: ["工作"])
        let preferences = TaskViewPreferenceStore(directory: directory), state = State(), probe = Probe()
        let host = NSHostingView(rootView: Host(state: state, workspace: workspace, preferences: preferences, probe: probe, copies: true))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 720, height: 720)
        defer { window.close() }
        state.visible = true
        try InspectorPanelTestSupport.waitUntil { probe.frames[.copyScope(.incomplete)] != nil }
        let sheet = try XCTUnwrap(window.attachedSheet), content = try XCTUnwrap(sheet.contentView)
        try InspectorPanelTestSupport.click(try XCTUnwrap(probe.frames[.copyScope(.incomplete)]), in: content, window: sheet)
        try capture(sheet, name: "copy")
        try InspectorPanelTestSupport.click(try XCTUnwrap(probe.frames[.save]), in: content, window: sheet)
        try InspectorPanelTestSupport.waitUntil { window.attachedSheet == nil }
        let copies = workspace.allTasks.filter { $0.list.name == "工作 副本" }
        XCTAssertEqual(copies.map(\.title), ["待办"])
    }

    private func exercise(save: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("list-editor-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = TaskWorkspaceModel(seedDemoData: false, initialTasks: [], initialLists: ["工作"])
        let preferences = TaskViewPreferenceStore(directory: directory)
        let state = State(), probe = Probe()
        let host = NSHostingView(rootView: Host(state: state, workspace: workspace, preferences: preferences, probe: probe)
            .preferredColorScheme(save ? .light : .dark))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 720, height: 720)
        defer { window.close() }
        window.appearance = NSAppearance(named: save ? .aqua : .darkAqua)
        state.visible = true
        try InspectorPanelTestSupport.waitUntil { window.attachedSheet?.contentView != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        InspectorPanelTestSupport.settle(sheet)
        let field = try XCTUnwrap(findField(in: try XCTUnwrap(sheet.contentView)))
        sheet.makeFirstResponder(field)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.selectAll(nil); editor.insertText("项目")
        sheet.makeFirstResponder(nil)
        InspectorPanelTestSupport.settle(sheet)
        try InspectorPanelTestSupport.waitUntil { probe.frames[.mode(.kanban)] != nil }
        let content = try XCTUnwrap(sheet.contentView)
        try InspectorPanelTestSupport.click(try XCTUnwrap(probe.frames[.mode(.kanban)]), in: content, window: sheet)
        try capture(sheet, name: save ? "editor-light" : "editor-dark")
        if let rect = probe.frames[.more] {
            try InspectorPanelTestSupport.click(CGRect(x: rect.minX, y: rect.minY, width: 14, height: 20), in: content, window: sheet)
            try capture(sheet, name: save ? "editor-expanded-light" : "editor-expanded-dark")
        }
        try InspectorPanelTestSupport.click(try XCTUnwrap(probe.frames[save ? .save : .cancel]), in: content, window: sheet)
        try InspectorPanelTestSupport.waitUntil { window.attachedSheet == nil }
        XCTAssertEqual(workspace.listNames, [save ? "项目" : "工作"])
        let key = TaskViewScopeKey.key(destination: .allTasks, activeList: save ? "项目" : "工作", activeTag: nil)
        XCTAssertEqual(preferences.viewMode(for: key, availableModes: TaskListViewMode.allCases), save ? .kanban : .list)
    }

    private func capture(_ window: NSWindow, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["WORKFOLLOW_LISTS_CAPTURE_DIRECTORY"], let content = window.contentView else { return }
        InspectorPanelTestSupport.settle(window)
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let image = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: image)
        try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
    }

    private func findField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { self.findField(in: $0) }.first
    }
}

@MainActor
final class TaskListColorPaletteTests: XCTestCase {
    private final class Storage: ObservableObject, @unchecked Sendable {
        @Published var colorIndex: Int? = 3
        @Published var colorARGB: UInt32?
    }
    private struct Host: View {
        @ObservedObject var storage: Storage
        var body: some View {
            ListColorPalette(colorIndex: $storage.colorIndex, colorARGB: $storage.colorARGB,
                             autoARGB: 0xFF27C264)
                .frame(width: 256)
                .padding(20)
        }
    }

    /// 16 格必须一行排完且不溢出：色板本来就是为「不再横向滚动」重做的。
    func testPaletteFitsSixteenSlotsInOneRow() throws {
        let storage = Storage()
        let host = NSHostingView(rootView: Host(storage: storage))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 296, height: 80)
        defer { window.close() }
        InspectorPanelTestSupport.settle(window)
        host.layoutSubtreeIfNeeded()
        var swatches = 0
        func walk(_ view: NSView) {
            // 每颗色点的悬停区就是它的点击热区（含「自动」与取色盘）。
            if String(describing: type(of: view)).contains("HoverTipTrackingView") {
                swatches += 1
            }
            for s in view.subviews { walk(s) }
        }
        walk(host)
        XCTAssertEqual(swatches, 16, "自动 + 14 色 + 取色盘应一行铺满")
        // fittingSize 含外层 padding 20×2，扣掉后应正好是单档位 16pt。
        XCTAssertEqual(host.fittingSize.height - 40, 16, accuracy: 1, "色板行高应为单档位 16pt")
    }
}
