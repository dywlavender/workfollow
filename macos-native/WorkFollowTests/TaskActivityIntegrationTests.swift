import AppKit
import Combine
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskActivityIntegrationTests: XCTestCase {
    func testWorkspaceCommandsRecordRealChangesWithoutBackfilling() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("activity-integration-\(UUID())")
        let activity = TaskActivityStore(directory: directory)
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let oldID = try XCTUnwrap(workspace.createTask(title: "旧任务", in: .inbox).taskID)
        workspace.attachActivityStore(activity)
        XCTAssertTrue(activity.events.isEmpty)
        _ = workspace.setTitle(oldID, "新标题")
        let count = activity.events.count
        _ = workspace.setTitle(oldID, "新标题")
        XCTAssertEqual(activity.events.count, count)
        _ = workspace.setPriority(oldID, .high)
        workspace.setTags(oldID, ["测试"])
        _ = workspace.complete(oldID)
        _ = workspace.restore(oldID)
        _ = workspace.createChild(oldID, title: "子任务")
        let kinds = Set(activity.events(for: oldID).map(\.kind))
        XCTAssertTrue(kinds.isSuperset(of: [.titleChanged, .priorityChanged, .tagsChanged, .completed, .restored, .childCreated]))
        XCTAssertFalse(kinds.contains(.created))
        let newID = try XCTUnwrap(workspace.createTask(title: "新任务", in: .inbox).taskID)
        XCTAssertEqual(activity.events(for: newID).map(\.kind), [.created])
    }

    func testOuterTransactionReportsFinalSnapshotAndUndoReportsRestore() {
        let store = WorkspaceStore()
        var snapshots: [([Task], [Task])] = []
        var changes: [TaskChangeSet] = []
        store.onTasksChanged = { snapshots.append(($0, $1)) }
        store.onTaskChanges = { changes.append($0) }
        store.transaction {
            var task = Task(id: UUID(), title: "初始", list: .inbox, priority: .none,
                            schedule: TaskSchedule(), parentID: nil, childOrder: 0,
                            createdAt: Date(), updatedAt: Date())
            store.commit([task])
            task.title = "最终"
            store.commit([task])
        }
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].1.first?.title, "最终")
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].entries.map(\.operation), [.insert])
        XCTAssertEqual(changes[0].entries.first?.after?.title, "最终")
        store.undo()
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertTrue(snapshots[1].1.isEmpty)
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes[1].entries.map(\.operation), [.delete])
        XCTAssertEqual(changes[1].entries.first?.before?.title, "最终")
    }

    func testCommitAndUndoPublishBeforeAndAfterTaskValues() {
        let store = WorkspaceStore()
        var changes: [TaskChangeSet] = []
        store.onTaskChanges = { changes.append($0) }
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let original = Task(id: UUID(), title: "原名", list: .inbox, priority: .none,
                            schedule: TaskSchedule(), parentID: nil, childOrder: 0,
                            createdAt: stamp, updatedAt: stamp)
        store.commit([original])
        var edited = original
        edited.title = "修改名"
        store.commit([edited])

        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes[1].entries.first?.operation, .update)
        XCTAssertEqual(changes[1].entries.first?.before?.title, "原名")
        XCTAssertEqual(changes[1].entries.first?.after?.title, "修改名")

        store.undo()
        XCTAssertEqual(changes.count, 3)
        XCTAssertEqual(changes[2].entries.first?.operation, .update)
        XCTAssertEqual(changes[2].entries.first?.before?.title, "修改名")
        XCTAssertEqual(changes[2].entries.first?.after?.title, "原名")
        XCTAssertTrue(store.canUndo)
    }

    func testWorkspacePublishesCommittedChangesWithoutActivityAttachment() throws {
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let workspace = TaskWorkspaceModel(clock: { stamp }, seedDemoData: false)
        let taskID = try XCTUnwrap(workspace.createTask(title: "原任务", in: .inbox).taskID)
        let filterStore = FilterStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("filter-revision-\(UUID())", isDirectory: true))

        var changes: [TaskChangeSet] = []
        let cancellable = workspace.taskChanges.sink { changes.append($0) }
        defer { cancellable.cancel() }

        let revisionBeforeUIChanges = workspace.revision
        workspace.select(taskID)
        workspace.attachFilterStore(filterStore)
        let filter = SavedFilter(name: "集成测试筛选")
        XCTAssertTrue(filterStore.add(filter))
        workspace.openFilter(filter.id)
        XCTAssertGreaterThan(workspace.revision, revisionBeforeUIChanges)
        XCTAssertTrue(changes.isEmpty)

        _ = workspace.setTitle(taskID, "新标题")
        XCTAssertEqual(changes.count, 1)
        let titleEntry = try XCTUnwrap(changes[0].entries.first)
        XCTAssertEqual(titleEntry.operation, .update)
        XCTAssertEqual(titleEntry.before?.title, "原任务")
        XCTAssertEqual(titleEntry.after?.title, "新标题")
        XCTAssertEqual(titleEntry.changedFields, [.title])
        XCTAssertTrue(changes[0].affectsReminders)

        let document = NativeDocument(plainText: "正文")
        _ = workspace.setDocument(taskID, document)
        XCTAssertEqual(changes.count, 2)
        let documentEntry = try XCTUnwrap(changes[1].entries.first)
        XCTAssertEqual(documentEntry.changedFields, [.document])
        XCTAssertFalse(changes[1].affectsReminders)

        let unchangedCount = changes.count
        _ = workspace.setTitle(taskID, "新标题")
        _ = workspace.setDocument(taskID, document)
        XCTAssertEqual(changes.count, unchangedCount)
    }

    func testTaskChangeSetReminderClassificationIncludesScheduleEligibilityAndConversion() {
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let original = Task(id: UUID(), title: "任务", list: .inbox, priority: .none,
                            schedule: TaskSchedule(), parentID: nil, childOrder: 0,
                            createdAt: stamp, updatedAt: stamp)
        let mutations: [(String, (inout Task) -> Void)] = [
            ("title", { task in task.title = "新标题" }),
            ("list", { task in task.list = TaskList(name: "工作") }),
            ("schedule", { task in task.schedule.dueAt = stamp }),
            ("recurrence", { task in task.recurrence = .daily }),
            ("recurrenceRule", { task in task.recurrenceRule = RecurrenceRule(interval: 2) }),
            ("reminderAt", { task in task.reminderAt = stamp }),
            ("reminderOffsets", { task in task.reminderOffsets = [-15] }),
            ("status", { task in task.status = .completed }),
            ("isAbandoned", { task in task.abandonedAt = stamp }),
            ("deletedAt", { task in task.deletedAt = stamp }),
            ("skippedAt", { task in task.skippedAt = stamp }),
            ("convertedNoteID", { task in task.convertedNoteID = UUID() })
        ]

        for (field, mutate) in mutations {
            var updated = original
            mutate(&updated)
            XCTAssertTrue(TaskChangeSet(before: [original], after: [updated]).affectsReminders,
                          "Expected \(field) to trigger reminder reconciliation")
        }

        var bodyOnly = original
        bodyOnly.document = NativeDocument(plainText: "正文")
        XCTAssertFalse(TaskChangeSet(before: [original], after: [bodyOnly]).affectsReminders)
        var sourceOnly = original
        sourceOnly.sourceNoteID = UUID()
        let sourceChanges = TaskChangeSet(before: [original], after: [sourceOnly])
        XCTAssertEqual(sourceChanges.entries.first?.changedFields, [.sourceNoteID])
        XCTAssertFalse(sourceChanges.affectsReminders)
        XCTAssertTrue(TaskChangeSet(before: [], after: [original]).affectsReminders)
        XCTAssertTrue(TaskChangeSet(before: [original], after: []).affectsReminders)
    }

    func testChangeSetSkipsEqualTasksAndClassifiesEveryPersistedTaskField() throws {
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let original = Task(id: UUID(), title: "原任务", list: .inbox, priority: .none,
                            schedule: TaskSchedule(), parentID: nil, childOrder: 0,
                            createdAt: stamp, updatedAt: stamp)
        let untouched = Task(id: UUID(), title: "未变任务", list: .inbox, priority: .none,
                             schedule: TaskSchedule(), parentID: nil, childOrder: 0,
                             createdAt: stamp, updatedAt: stamp)
        let updated = Task(
            id: original.id,
            title: "新标题",
            document: NativeDocument(plainText: "新正文"),
            tags: ["标签"],
            recurrence: .weekly,
            recurrenceRule: RecurrenceRule(interval: 2),
            reminderAt: stamp.addingTimeInterval(60),
            reminderOffsets: [-15],
            attachments: [NativeAttachment(id: UUID(), name: "附件", storedName: "attachment")],
            list: TaskList(name: "工作"),
            priority: .high,
            schedule: TaskSchedule(dueAt: stamp, hasTime: true,
                                  dueEndAt: stamp.addingTimeInterval(3_600),
                                  deadlineAt: stamp.addingTimeInterval(7_200)),
            status: .completed,
            parentID: UUID(),
            childOrder: 1,
            createdAt: stamp.addingTimeInterval(1),
            updatedAt: stamp.addingTimeInterval(2),
            completedAt: stamp.addingTimeInterval(3),
            deletedAt: stamp.addingTimeInterval(4),
            isPinned: true,
            abandonedAt: stamp.addingTimeInterval(5),
            skippedAt: stamp.addingTimeInterval(6),
            convertedNoteID: UUID(),
            sourceNoteID: UUID())

        let changes = TaskChangeSet(before: [original, untouched], after: [updated, untouched])
        XCTAssertEqual(changes.entries.count, 1)
        let entry = try XCTUnwrap(changes.entries.first)
        XCTAssertEqual(entry.taskID, original.id)
        XCTAssertEqual(entry.operation, .update)
        XCTAssertEqual(entry.before, original)
        XCTAssertEqual(entry.after, updated)
        let expectedFields: Set<TaskChangeSet.Field> = [
            .title, .document, .tags, .recurrence, .recurrenceRule,
            .reminderAt, .reminderOffsets, .attachments, .list, .priority,
            .schedule, .status, .parentID, .childOrder, .createdAt,
            .updatedAt, .completedAt, .deletedAt, .isPinned, .abandonedAt,
            .isAbandoned, .skippedAt, .convertedNoteID, .sourceNoteID
        ]
        XCTAssertEqual(entry.changedFields, expectedFields)
        XCTAssertTrue(changes.affectsReminders)

        let unchanged = TaskChangeSet(before: [untouched], after: [untouched])
        XCTAssertTrue(unchanged.entries.isEmpty)
        XCTAssertFalse(unchanged.affectsReminders)

        let replacementID = Task(id: UUID(), title: untouched.title, list: untouched.list,
                                  priority: untouched.priority, schedule: untouched.schedule,
                                  parentID: untouched.parentID, childOrder: untouched.childOrder,
                                  createdAt: untouched.createdAt, updatedAt: untouched.updatedAt)
        let identityChange = TaskChangeSet(before: [untouched], after: [replacementID])
        XCTAssertEqual(identityChange.entries.map(\.operation), [.insert, .delete])
        XCTAssertTrue(identityChange.affectsReminders)
    }

    func testOnlySuccessfulFocusStartNotifiesActivity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("activity-focus-\(UUID())")
        let activity = TaskActivityStore(directory: directory)
        let focus = FocusStore(directory: directory)
        focus.onTaskFocusStarted = { activity.recordFocusStart(taskID: $0, stopwatch: $1) }
        let id = UUID()
        XCTAssertTrue(focus.start(taskID: id, stopwatch: true))
        XCTAssertFalse(focus.start(taskID: id, stopwatch: false))
        XCTAssertEqual(activity.events(for: id).count, 1)
        XCTAssertEqual(activity.events(for: id).first?.kind, .focusStarted)
        _ = focus.giveUp()
    }

    func testActivityPanelClosesMoreAndUsesArrowlessChildWithEscape() throws {
        let environment = AppEnvironment()
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "动态浮层验收", in: .inbox).taskID)
        workspace.select(id)
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, environment: environment)
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.close() }
        try InspectorPanelTestSupport.clickButton(containing: "更多任务操作", in: window)
        let more = try InspectorPanelTestSupport.actionPanel(in: window)
        XCTAssertEqual(more.frame.width, 208, accuracy: 1)
        try InspectorPanelTestSupport.clickButton(containing: "任务动态", in: more)
        XCTAssertFalse(more.isVisible)

        let panel = try InspectorPanelTestSupport.actionPanel(in: window)
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertEqual(panel.title, InspectorPanelTestSupport.actionPanelTitle)
        XCTAssertEqual(panel.frame.width, 320, accuracy: 1)
        XCTAssertTrue(window.frame.insetBy(dx: 8, dy: 8).contains(panel.frame),
                      "Footer activity must stay inside the owner even on a larger screen")
        try InspectorPanelTestSupport.sendEscape(to: panel)
        XCTAssertFalse(panel.isVisible)
    }

}
