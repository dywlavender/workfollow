import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskKanbanCardTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_137_600)

    private func richTask() -> Task {
        var task = Task(id: UUID(), title: "看板任务", list: TaskList(name: "工作"),
                        priority: .high, schedule: TaskSchedule(dueAt: now, deadlineAt: now),
                        parentID: nil, childOrder: 0, createdAt: now, updatedAt: now)
        task.document = NativeDocument(plainText: "任务正文")
        task.tags = ["设计", "macOS"]
        task.recurrence = .weekly
        task.reminderOffsets = [-10]
        task.attachments = [.init(id: UUID(), name: "需求.pdf", storedName: "fixture.pdf")]
        task.isPinned = true
        return task
    }

    func testCardDetailsUseActualTagsAndSameSecondaryMetadataAsList() {
        let task = richTask()
        let details = TaskKanbanCardDetails(task: task, subtaskProgress: "1/3",
            showsListBadge: true, hidesDetails: false, hiddenFields: [])
        XCTAssertEqual(details.preview, "任务正文")
        XCTAssertEqual(details.tags, ["设计", "macOS"])
        XCTAssertEqual(details.listName, "工作")
        XCTAssertTrue(details.showsDate)
        XCTAssertTrue(details.showsPriority)
        XCTAssertTrue(details.showsPinned)
        XCTAssertEqual(details.indicators.map(\.id), ["subtasks", "repeat", "reminder", "description", "attachments"])
        XCTAssertEqual(details.indicators.first?.value, "1/3")
        XCTAssertEqual(details.indicators, TaskSecondaryMetadata.items(for: task, subtaskProgress: "1/3")
            .filter { $0.id != "tags" })
    }

    func testSharedDisplaySettingsHideMetadataWithoutRemovingBodyPreview() {
        let task = richTask()
        let hidden = TaskKanbanCardDetails(task: task, subtaskProgress: "1/3",
            showsListBadge: true, hidesDetails: true, hiddenFields: [])
        XCTAssertEqual(hidden.preview, "任务正文")
        XCTAssertNil(hidden.listName)
        XCTAssertTrue(hidden.tags.isEmpty)
        XCTAssertTrue(hidden.indicators.isEmpty)
        XCTAssertFalse(hidden.showsDate)
        XCTAssertFalse(hidden.showsPriority)
        XCTAssertFalse(hidden.showsPinned)

        let fields = TaskKanbanCardDetails(task: task, subtaskProgress: "1/3",
            showsListBadge: true, hidesDetails: false, hiddenFields: [.date, .tags, .indicators])
        XCTAssertFalse(fields.showsDate)
        XCTAssertTrue(fields.tags.isEmpty)
        XCTAssertTrue(fields.indicators.isEmpty)
        XCTAssertTrue(fields.showsPriority)
        XCTAssertTrue(fields.showsPinned)
        XCTAssertEqual(fields.listName, "工作")

        let inList = TaskKanbanCardDetails(task: task, subtaskProgress: nil,
            showsListBadge: false, hidesDetails: false, hiddenFields: [])
        XCTAssertNil(inList.listName)
        XCTAssertEqual(inList.tags, task.tags)
    }

    private final class Probe {
        var frames: [TaskTreeRenderAnchor: CGRect] = [:]
        var selections = 0
    }

    @MainActor
    private struct Fixture {
        let workspace: TaskWorkspaceModel
        let id: UUID
        let host: NSHostingView<AnyView>
        let window: NSWindow
        let probe: Probe

        func frame(_ part: TaskTreeRenderPart) throws -> CGRect {
            try XCTUnwrap(probe.frames[.init(taskID: id, part: part)])
        }

        func click(_ part: TaskTreeRenderPart) throws {
            try InspectorPanelTestSupport.click(frame(part), in: host, window: window)
        }
    }

    private func fixture() throws -> Fixture {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "看板卡片验收", in: .inbox).taskID)
        _ = workspace.setDocument(id, NativeDocument(plainText: "卡片正文预览"))
        _ = workspace.setDueDate(id, now)
        let task = try XCTUnwrap(workspace.task(for: id))
        let probe = Probe()
        let root = TaskKanbanColumnDropHost(workspace: workspace, target: .priority(.high),
                                            allowsMove: true, onTargeted: { _ in }) {
            VStack(alignment: .leading, spacing: 0) {
                TaskKanbanCardView(task: task, workspace: workspace,
                                   onSelect: { _ in probe.selections += 1 })
                    .frame(width: 256)
                Spacer(minLength: 0)
            }
            .frame(width: 600, height: 700, alignment: .topLeading)
            .coordinateSpace(name: "task-tree-render")
            .environment(\.recordsTaskTreeFrames, true)
            .onPreferenceChange(TaskTreeFramesKey.self) { probe.frames = $0 }
        }
        .frame(width: 600, height: 700, alignment: .topLeading)
        .environmentObject(AppEnvironment())
        let host = NSHostingView(rootView: AnyView(root))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 600, height: 700)
        return .init(workspace: workspace, id: id, host: host, window: window, probe: probe)
    }

    func testTitlePreviewAndPaddingSelectButCheckboxOnlyCompletes() throws {
        let fixture = try fixture()
        defer { fixture.window.close() }
        try fixture.click(.title)
        try fixture.click(.preview)
        let row = try fixture.frame(.row)
        try InspectorPanelTestSupport.click(CGRect(x: row.maxX - 2, y: row.minY + 2,
                                                   width: 1, height: 1),
                                            in: fixture.host, window: fixture.window)
        XCTAssertEqual(fixture.probe.selections, 3)
        XCTAssertFalse(try XCTUnwrap(fixture.workspace.task(for: fixture.id)).isClosed)
        try fixture.click(.checkbox)
        XCTAssertTrue(try XCTUnwrap(fixture.workspace.task(for: fixture.id)).isClosed)
        XCTAssertEqual(fixture.probe.selections, 3)
    }

    func testCardDateUsesSharedSchedulePanelWithoutSelecting() throws {
        let fixture = try fixture()
        defer { fixture.window.close() }
        try fixture.click(.date)
        _ = try InspectorPanelTestSupport.panel(title: "日期属性", below: fixture.window)
        XCTAssertEqual(fixture.probe.selections, 0)
        try InspectorPanelTestSupport.sendEscape(to: fixture.window)
        XCTAssertTrue(InspectorPanelTestSupport.visibleWindows(below: fixture.window).isEmpty)
        try fixture.click(.title)
        XCTAssertEqual(fixture.probe.selections, 1)
    }

    func testCardRightClickPresentsSharedMenuAndEscapeDismisses() throws {
        let fixture = try fixture()
        defer {
            TaskContextMenuPresenter.activeSession?.close()
            fixture.window.close()
        }
        let title = try fixture.frame(.title)
        let local = NSPoint(x: title.midX,
            y: fixture.host.isFlipped ? title.midY : fixture.host.bounds.height - title.midY)
        let point = fixture.host.convert(local, to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown,
            location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: fixture.window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        // Fetch through the application queue so NSApp.currentEvent reflects
        // the secondary click used by the production hit-test policy.
        NSApp.postEvent(event, atStart: true)
        let down = try XCTUnwrap(NSApp.nextEvent(matching: .rightMouseDown, until: Date(),
                                                inMode: .default, dequeue: true))
        NSApp.sendEvent(down)
        InspectorPanelTestSupport.settle(fixture.window)
        let session = try XCTUnwrap(TaskContextMenuPresenter.activeSession)
        let panel = try XCTUnwrap(session.coordinator.panel)
        XCTAssertEqual(panel.title, "任务右键菜单")
        XCTAssertEqual(fixture.probe.selections, 0)
        try InspectorPanelTestSupport.sendEscape(to: fixture.window)
        XCTAssertNil(TaskContextMenuPresenter.activeSession)
        XCTAssertNil(session.coordinator.panel)
    }
}
