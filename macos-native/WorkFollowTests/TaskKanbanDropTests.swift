import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskKanbanDropTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 28_800)!
        return value
    }
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 12))!
    }
    private func task(_ title: String, parent: UUID? = nil) -> Task {
        Task(id: UUID(), title: title, list: TaskList(name: "工作"), priority: .none,
             schedule: TaskSchedule(), parentID: parent, childOrder: 0,
             createdAt: now, updatedAt: now)
    }
    private func workspace(_ tasks: [Task], sections: [TaskListSection] = [],
                           metadata: [TaskListMeta]? = nil) -> TaskWorkspaceModel {
        TaskWorkspaceModel(clock: { self.now }, calendar: calendar, seedDemoData: false,
            initialTasks: tasks, initialLists: ["工作", "个人"], initialListMeta: metadata,
            initialListSections: sections)
    }

    func testDateMoveKeepsClockIntervalReminderAndDeadlineWithOneUndo() throws {
        var source = task("排期调整")
        source.schedule = TaskSchedule(dueAt: now, hasTime: true,
                                      dueEndAt: now.addingTimeInterval(5400),
                                      deadlineAt: now.addingTimeInterval(604800))
        source.reminderAt = now.addingTimeInterval(-600)
        source.reminderOffsets = [-10]
        source.tags = ["设计", "本周"]
        let workspace = workspace([source])
        let original = workspace.allTasks
        workspace.select(source.id)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertTrue(workspace.moveKanbanTask(source.id, to: .schedule(tomorrow)))
        let moved = try XCTUnwrap(workspace.task(for: source.id))
        XCTAssertEqual(moved.schedule.dueAt, tomorrow)
        XCTAssertEqual(moved.schedule.dueEndAt, tomorrow.addingTimeInterval(5400))
        XCTAssertEqual(moved.reminderAt, tomorrow.addingTimeInterval(-600))
        XCTAssertEqual(moved.reminderOffsets, [-10])
        XCTAssertEqual(moved.schedule.deadlineAt, source.schedule.deadlineAt)
        XCTAssertEqual(moved.tags, source.tags)
        XCTAssertEqual(workspace.selectedTaskID, source.id)
        workspace.undo()
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertFalse(workspace.canUndo)
        workspace.redo()
        XCTAssertEqual(workspace.task(for: source.id), moved)
    }

    func testUndatedMoveClearsDateDependenciesAndPreservesDeadline() throws {
        var source = task("每天复盘")
        source.schedule = TaskSchedule(dueAt: now, hasTime: true,
                                      dueEndAt: now.addingTimeInterval(1800),
                                      deadlineAt: now.addingTimeInterval(604800))
        source.recurrence = .daily
        source.reminderAt = now.addingTimeInterval(-300)
        source.reminderOffsets = [-5]
        let workspace = workspace([source])
        let original = workspace.allTasks
        XCTAssertTrue(workspace.moveKanbanTask(source.id, to: .schedule(nil)))
        let moved = try XCTUnwrap(workspace.task(for: source.id))
        XCTAssertNil(moved.schedule.dueAt)
        XCTAssertNil(moved.schedule.dueEndAt)
        XCTAssertFalse(moved.schedule.hasTime)
        XCTAssertNil(moved.reminderAt)
        XCTAssertNil(moved.reminderOffsets)
        XCTAssertEqual(moved.recurrence, .never)
        XCTAssertEqual(moved.schedule.deadlineAt, source.schedule.deadlineAt)
        workspace.undo()
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertFalse(workspace.canUndo)
    }

    func testPriorityMoveOnChildKeepsParentAndCompletionAndSameColumnIsNoOp() throws {
        let parent = task("需求评审")
        var child = task("检查材料", parent: parent.id)
        child.status = .completed
        child.completedAt = now
        let workspace = workspace([parent, child])
        XCTAssertFalse(workspace.moveKanbanTask(child.id, to: .priority(.none)))
        XCTAssertFalse(workspace.canUndo)
        XCTAssertTrue(workspace.moveKanbanTask(child.id, to: .priority(.high)))
        let moved = try XCTUnwrap(workspace.task(for: child.id))
        XCTAssertEqual(moved.priority, .high)
        XCTAssertEqual(moved.parentID, parent.id)
        XCTAssertEqual(moved.status, .completed)
        XCTAssertEqual(moved.completedAt, now)
        XCTAssertEqual(workspace.task(for: parent.id)?.priority, TaskPriority.none)
        workspace.undo()
        XCTAssertEqual(workspace.task(for: child.id)?.priority, TaskPriority.none)
        XCTAssertFalse(workspace.canUndo)
    }

    func testListMoveCarriesChildrenAndClearsOldSectionsInOneStep() throws {
        let section = TaskListSection(id: "review", listName: "工作", title: "评审")
        var parent = task("方案评审")
        parent.sectionID = section.id
        var child = task("补充材料", parent: parent.id)
        child.sectionID = section.id
        let workspace = workspace([parent, child], sections: [section])
        let original = workspace.allTasks
        XCTAssertFalse(workspace.moveKanbanTask(child.id, to: .list("个人")))
        XCTAssertFalse(workspace.canUndo)
        XCTAssertTrue(workspace.moveKanbanTask(parent.id, to: .list("个人")))
        XCTAssertTrue(workspace.allTasks.allSatisfy { $0.list.name == "个人" && $0.sectionID == nil })
        XCTAssertEqual(workspace.task(for: child.id)?.parentID, parent.id)
        workspace.undo()
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertFalse(workspace.canUndo)
    }

    func testSectionMoveValidatesOwnershipAndCanReturnToUnsectioned() throws {
        let section = TaskListSection(id: "review", listName: "工作", title: "高优先级")
        let source = task("待归组")
        let workspace = workspace([source], sections: [section])
        XCTAssertFalse(workspace.moveKanbanTask(source.id, to: .section(list: "个人", sectionID: section.id)))
        XCTAssertFalse(workspace.canUndo)
        XCTAssertTrue(workspace.moveKanbanTask(source.id, to: .section(list: "工作", sectionID: section.id)))
        XCTAssertEqual(workspace.task(for: source.id)?.sectionID, section.id)
        XCTAssertEqual(workspace.task(for: source.id)?.priority, TaskPriority.none)
        workspace.undo()
        XCTAssertFalse(workspace.canUndo)
        workspace.redo()
        XCTAssertTrue(workspace.moveKanbanTask(source.id, to: .section(list: "工作", sectionID: nil)))
        XCTAssertNil(workspace.task(for: source.id)?.sectionID)
        workspace.undo()
        XCTAssertEqual(workspace.task(for: source.id)?.sectionID, section.id)
    }

    func testTagMoveReplacesPrimaryTagAndKeepsOtherRelationsInOneColumn() throws {
        var source = task("多标签任务")
        source.tags = ["设计", "本周", "发布"]
        let workspace = workspace([source])
        let original = try XCTUnwrap(workspace.task(for: source.id))
        XCTAssertTrue(workspace.moveKanbanTask(source.id, to: .tag("本周")))
        let moved = try XCTUnwrap(workspace.task(for: source.id))
        XCTAssertEqual(moved.tags, ["本周", "发布"])
        let movedReferences = try XCTUnwrap(moved.tagReferences)
        let originalReferences = try XCTUnwrap(original.tagReferences)
        XCTAssertEqual(movedReferences.map(\.id), originalReferences.dropFirst().map(\.id))
        let columns = workspace.groups(for: .allTasks, grouping: .byTag, viewMode: .kanban)
        XCTAssertEqual(columns.map(\.label), ["本周"])
        XCTAssertEqual(columns.flatMap(\.tasks).map(\.id), [source.id])
        workspace.undo()
        XCTAssertEqual(workspace.task(for: source.id), original)
        XCTAssertFalse(workspace.canUndo)
        workspace.redo()
        XCTAssertEqual(workspace.task(for: source.id), moved)
    }

    func testUntaggedMoveClearsAllTagsAndUndoRestoresThem() throws {
        var source = task("去除标签")
        source.tags = ["设计", "本周"]
        let workspace = workspace([source])
        let original = workspace.allTasks
        XCTAssertTrue(workspace.moveKanbanTask(source.id, to: .tag(nil)))
        XCTAssertEqual(workspace.task(for: source.id)?.tags, [])
        XCTAssertEqual(workspace.task(for: source.id)?.tagReferences, [])
        XCTAssertEqual(workspace.groups(for: .allTasks, grouping: .byTag, viewMode: .kanban).map(\.label), ["无标签"])
        workspace.undo()
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertFalse(workspace.canUndo)
    }

    func testArchivedListsDoNotAcceptOrExportColumnMoves() throws {
        let source = task("保留归档")
        let metadata = [TaskListMeta(name: "个人", archivedAt: now)]
        let workspace = workspace([source], metadata: metadata)
        XCTAssertFalse(workspace.moveKanbanTask(source.id, to: .list("个人")))
        XCTAssertFalse(workspace.canUndo)
        XCTAssertTrue(workspace.setListArchived("工作", true))
        let original = workspace.allTasks
        XCTAssertFalse(workspace.moveKanbanTask(source.id, to: .priority(.high)))
        XCTAssertEqual(workspace.allTasks, original)
    }

    func testDropTargetsComeFromWritableAttributesRatherThanHeadingText() {
        let source = task("今天创建")
        let workspace = workspace([source])
        XCTAssertTrue(workspace.groups(for: .allTasks, grouping: .byCreatedAt, viewMode: .kanban)
            .allSatisfy { $0.kanbanDropTarget == nil })
        XCTAssertEqual(workspace.groups(for: .allTasks, grouping: .byDate, viewMode: .kanban)
            .first?.kanbanDropTarget, .schedule(nil))
        XCTAssertNil(TaskListGroup(kind: .plain, day: nil, tasks: [],
                                  creationTarget: .currentContext).kanbanDropTarget)
    }

    func testNativeReleaseRemovesPreviewBeforeSynchronouslyMovingOriginalTask() throws {
        let source = task("原生拖放")
        let workspace = workspace([source])
        let original = try XCTUnwrap(workspace.task(for: source.id))
        let view = destination(workspace, target: .priority(.high))
        let drag = DragInfo(taskID: source.id)
        defer { drag.draggingPasteboard.releaseGlobally() }
        var highlights: [Bool] = []
        view.onTargeted = { highlights.append($0) }

        XCTAssertEqual(view.draggingEntered(drag), .move)
        XCTAssertTrue(drag.animatesToDestination, "移动过程中保留系统拖动预览")
        XCTAssertEqual(highlights, [true])
        XCTAssertTrue(view.prepareForDragOperation(drag))
        XCTAssertFalse(drag.animatesToDestination, "松手后、更新卡片前关闭系统滑入动画")
        XCTAssertEqual(highlights.last, false)
        XCTAssertEqual(workspace.task(for: source.id), original)
        XCTAssertFalse(workspace.canUndo)

        XCTAssertTrue(view.performDragOperation(drag))
        XCTAssertEqual(workspace.allTasks.count, 1)
        XCTAssertEqual(workspace.task(for: source.id)?.priority, .high, "无需等待异步回调即可完成移列")
        view.concludeDragOperation(drag)
        XCTAssertEqual(highlights.last, false)
        workspace.undo()
        XCTAssertEqual(workspace.task(for: source.id), original)
        XCTAssertFalse(workspace.canUndo)
        workspace.redo()
        XCTAssertEqual(workspace.task(for: source.id)?.priority, .high)
    }

    func testSameColumnReleaseIsAcceptedWithoutReturnAnimationOrUndoEntry() {
        let source = task("原列释放")
        let workspace = workspace([source])
        let original = workspace.allTasks
        let view = destination(workspace, target: .priority(.none))
        let drag = DragInfo(taskID: source.id)
        drag.draggingSourceOperationMask = .copy
        defer { drag.draggingPasteboard.releaseGlobally() }
        XCTAssertEqual(view.draggingEntered(drag), .copy)
        XCTAssertTrue(view.prepareForDragOperation(drag))
        XCTAssertFalse(drag.animatesToDestination)
        XCTAssertTrue(view.performDragOperation(drag))
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertFalse(workspace.canUndo)
    }

    func testLeavingColumnKeepsPreviewAndClearsOnlyDropHighlight() {
        let source = task("继续拖动")
        let workspace = workspace([source])
        let original = workspace.allTasks
        let view = destination(workspace, target: .priority(.high))
        let drag = DragInfo(taskID: source.id)
        defer { drag.draggingPasteboard.releaseGlobally() }
        var targeted = false
        view.onTargeted = { targeted = $0 }
        XCTAssertEqual(view.draggingEntered(drag), .move)
        XCTAssertTrue(targeted)
        view.draggingExited(drag)
        XCTAssertFalse(targeted)
        XCTAssertTrue(drag.animatesToDestination)
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertFalse(workspace.canUndo)
    }

    func testNativePointerPreparesInsertionThenMovesWithoutPreviewAnimation() {
        let first = task("第一张"), second = task("第二张"), source = task("移动卡片")
        let workspace = workspace([first, second, source])
        let original = workspace.allTasks
        let view = destination(workspace, target: .priority(.none))
        view.frame = CGRect(x: 0, y: 0, width: 264, height: 400)
        view.allowsReorder = true
        view.columnTaskIDs = [first.id, second.id, source.id]
        view.dropLayout = TaskKanbanColumnLayout(cards: [
            first.id: CGRect(x: 4, y: 40, width: 256, height: 60),
            second.id: CGRect(x: 4, y: 110, width: 256, height: 90),
            source.id: CGRect(x: 4, y: 220, width: 256, height: 60)
        ], viewport: CGRect(x: 0, y: 32, width: 264, height: 368))
        let drag = DragInfo(taskID: source.id)
        defer { drag.draggingPasteboard.releaseGlobally() }
        drag.draggingLocation = view.convert(
            CGPoint(x: 100, y: view.isFlipped ? 50 : view.bounds.height - 50), to: nil)
        XCTAssertEqual(view.draggingEntered(drag), .move)
        XCTAssertEqual(view.insertion?.placement, .before(first.id))
        XCTAssertEqual(workspace.allTasks, original, "悬停只显示落点，不提前改任务顺序")
        XCTAssertTrue(view.prepareForDragOperation(drag))
        XCTAssertNil(view.insertion)
        XCTAssertFalse(drag.animatesToDestination)
        XCTAssertTrue(view.performDragOperation(drag))
        XCTAssertEqual(workspace.allTasks.map(\.id), [source.id, first.id, second.id])
        workspace.undo()
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertFalse(workspace.canUndo)
    }

    func testFixedFieldSortDoesNotOfferAnInsertionOrRewriteManualOrder() {
        let first = task("第一张"), source = task("移动卡片")
        let workspace = workspace([first, source])
        let original = workspace.allTasks
        let view = destination(workspace, target: .priority(.none))
        view.columnTaskIDs = [first.id, source.id]
        view.allowsReorder = false
        let drag = DragInfo(taskID: source.id)
        defer { drag.draggingPasteboard.releaseGlobally() }
        XCTAssertEqual(view.draggingEntered(drag), .move)
        XCTAssertNil(view.insertion)
        XCTAssertTrue(view.prepareForDragOperation(drag))
        XCTAssertTrue(view.performDragOperation(drag))
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertFalse(workspace.canUndo)
    }

    func testInsertionLineRemainsVisibleAfterTheBoardRedrawsItsTargetHighlight() throws {
        let first = task("第一张"), source = task("移动卡片")
        let workspace = workspace([first, source])
        let root = TaskKanbanView(groups: workspace.groups(for: .allTasks, grouping: .byPriority,
                                                           viewMode: .kanban),
                                  workspace: workspace, onSelect: { _ in })
            .frame(width: 900, height: 650)
            .environmentObject(AppEnvironment())
        let host = NSHostingView(rootView: AnyView(root))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 900, height: 650)
        defer { window.close() }
        func columns(_ view: NSView) -> [TaskKanbanColumnDropView] {
            if let column = view as? TaskKanbanColumnDropView { return [column] }
            return view.subviews.flatMap { columns($0) }
        }
        let column = try XCTUnwrap(columns(host).first { $0.columnTaskIDs.contains(first.id) })
        let firstFrame = try XCTUnwrap(column.dropLayout.cards[first.id])
        let drag = DragInfo(taskID: source.id)
        defer { drag.draggingPasteboard.releaseGlobally() }
        let pointerY = firstFrame.minY + 5
        drag.draggingLocation = column.convert(CGPoint(x: 100,
            y: column.isFlipped ? pointerY : column.bounds.height - pointerY), to: nil)
        XCTAssertEqual(column.draggingEntered(drag), .move)
        InspectorPanelTestSupport.settle(window)
        _ = column.draggingUpdated(drag)
        InspectorPanelTestSupport.settle(window)
        let insertion = try XCTUnwrap(column.insertion)
        XCTAssertEqual(insertion.placement, .before(first.id))
        let image = try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow,
            CGWindowID(window.windowNumber), [.bestResolution]))
        let bitmap = NSBitmapImageRep(cgImage: image)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let markerPoint = column.convert(CGPoint(x: column.bounds.midX,
            y: column.isFlipped ? insertion.y : column.bounds.height - insertion.y), to: host)
        let imageY = host.isFlipped ? markerPoint.y : host.bounds.height - markerPoint.y
        var coloredSamples = 0
        for x in stride(from: markerPoint.x - 80, through: markerPoint.x + 80, by: 4) {
            let hasInk = (-2...2).contains { offset in
                guard let color = bitmap.colorAt(x: Int(x * scale),
                    y: Int((imageY + CGFloat(offset)) * scale))?.usingColorSpace(.sRGB) else { return false }
                return color.blueComponent > color.redComponent + 0.15
                    && color.blueComponent > color.greenComponent + 0.1
            }
            if hasInk { coloredSamples += 1 }
        }
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/workfollow-kanban-insertion-feedback.png"))
        XCTAssertGreaterThan(coloredSamples, 30, "真实看板重绘列高亮后仍应绘制连续的插入线")
        column.draggingExited(drag)
        XCTAssertNil(column.insertion)
        XCTAssertFalse(workspace.canUndo, "悬停反馈不改动任务")
    }

    private func destination(_ workspace: TaskWorkspaceModel,
                             target: TaskKanbanCreationTarget) -> TaskKanbanColumnDropView {
        let view = TaskKanbanColumnDropView(rootView: AnyView(EmptyView()))
        view.workspace = workspace
        view.target = target
        view.allowsMove = true
        return view
    }

    private final class DragInfo: NSObject, NSDraggingInfo {
        var draggingDestinationWindow: NSWindow? { nil }
        var draggingSourceOperationMask: NSDragOperation = [.copy, .move]
        var draggingLocation: NSPoint = .zero
        var draggedImageLocation: NSPoint { .zero }
        var draggedImage: NSImage? { nil }
        let draggingPasteboard = NSPasteboard.withUniqueName()
        var draggingSource: Any? { nil }
        var draggingSequenceNumber: Int { 1 }
        var draggingFormation: NSDraggingFormation = .none
        var animatesToDestination = true
        var numberOfValidItemsForDrop = 1
        var springLoadingHighlight: NSSpringLoadingHighlight { .none }

        init(taskID: UUID) {
            super.init()
            draggingPasteboard.writeObjects([SidebarDragPayload.encode(.task(taskID)) as NSString])
        }

        func slideDraggedImage(to screenPoint: NSPoint) {}
        override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
        func resetSpringLoading() {}
        func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions,
                                    for view: NSView?, classes classArray: [AnyClass],
                                    searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    }
}
