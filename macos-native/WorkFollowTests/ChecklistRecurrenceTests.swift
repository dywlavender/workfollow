import XCTest
@testable import WorkFollow

/// P5：重复任务重置检查项、复制/模板清空项元数据、子任务完成联动父清单。
@MainActor
final class ChecklistRecurrenceTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var futureReminder: Date { now.addingTimeInterval(3600) }
    private var staleReminder: Date { now.addingTimeInterval(-3 * 86400) }

    private func makeActions() -> (WorkspaceStore, TaskActions) {
        let store = WorkspaceStore()
        return (store, TaskActions(store: store, clock: { self.now }, calendar: calendar))
    }

    @discardableResult
    private func makeChecklist(_ states: [Bool], actions: TaskActions,
                               reminders: [Date?] = []) throws -> UUID {
        let id = try XCTUnwrap(actions.create(title: "清单任务").taskID)
        let blocks = states.enumerated().map { index, checked in
            DocumentBlock(kind: .checklist(checked), runs: [DocumentRun(text: "事项\(index)")],
                          checklist: index < reminders.count
                            ? reminders[index].map { ChecklistItemMeta(reminderAt: $0) } : nil)
        }
        actions.setDocument(id, NativeDocument(blocks: blocks))
        actions.setKind(id, .checklist)
        return id
    }

    private func setChecked(_ id: UUID, _ checked: Bool, store: WorkspaceStore,
                            actions: TaskActions) throws {
        var document = try XCTUnwrap(store.task(id)?.document)
        document.blocks = document.blocks.enumerated().map { index, block in
            var block = block
            if index == 0 { block.kind = .checklist(checked) }
            return block
        }
        actions.setDocument(id, document)
    }

    func testNextOccurrenceResetsItemsAndShiftsFutureReminders() throws {
        let (store, actions) = makeActions()
        let id = try makeChecklist([false, false], actions: actions,
                                   reminders: [futureReminder, staleReminder])
        actions.setSchedule(id, TaskSchedule(dueAt: now, hasTime: true))
        actions.setRecurrence(id, frequency: .daily, rule: RecurrenceRule())
        // 有未完成子任务时，勾满也不会提前自动完成。
        _ = try XCTUnwrap(actions.createChild(id, title: "子任务").taskID)
        for index in 0..<2 {
            var document = try XCTUnwrap(store.task(id)?.document)
            document.blocks[index].kind = .checklist(true)
            actions.setDocument(id, document)
        }
        XCTAssertEqual(store.task(id)?.status, .active)

        let result = actions.complete(id)
        let spawnID = try XCTUnwrap(result.taskID)
        XCTAssertNotEqual(spawnID, id)
        let spawn = try XCTUnwrap(store.task(spawnID))
        XCTAssertEqual(spawn.kind, .checklist)
        XCTAssertEqual(spawn.status, .active)
        XCTAssertEqual(spawn.document.blocks.map(\.kind), [.checklist(false), .checklist(false)])
        XCTAssertTrue(spawn.document.blocks.allSatisfy { $0.checklist?.completedAt == nil })
        let expected = calendar.date(byAdding: .day, value: 1, to: futureReminder)
        XCTAssertEqual(spawn.document.blocks[0].checklist?.reminderAt, expected,
                       "项提醒随任务日期平移一天")
        XCTAssertNil(spawn.document.blocks[1].checklist?.reminderAt,
                     "平移后仍落在过去的提醒要清空（D7）")

        actions.undo()
        XCTAssertNil(store.task(spawnID))
        XCTAssertEqual(store.task(id)?.status, .active)
    }

    func testMovingScheduleShiftsItemRemindersAndClearsPastOnes() throws {
        let (store, actions) = makeActions()
        let firstReminder = now.addingTimeInterval(3600)
        let secondReminder = now.addingTimeInterval(7200)
        let id = try makeChecklist([false, false], actions: actions,
                                   reminders: [firstReminder, secondReminder])
        _ = actions.setSchedule(id, TaskSchedule(dueAt: now.addingTimeInterval(86_400), hasTime: true))
        XCTAssertEqual(store.task(id)?.document.blocks[0].checklist?.reminderAt, firstReminder,
                       "首次设日期没有旧值可比较，项提醒保持绝对时间")

        _ = actions.setSchedule(id, TaskSchedule(dueAt: now.addingTimeInterval(2 * 86_400), hasTime: true))
        XCTAssertEqual(store.task(id)?.document.blocks[0].checklist?.reminderAt,
                       firstReminder.addingTimeInterval(86_400),
                       "改期一天，项提醒跟随时差平移")
        XCTAssertEqual(store.task(id)?.document.blocks[1].checklist?.reminderAt,
                       secondReminder.addingTimeInterval(86_400))

        _ = actions.setSchedule(id, TaskSchedule(dueAt: now, hasTime: true))
        XCTAssertNil(store.task(id)?.document.blocks[0].checklist?.reminderAt,
                     "平移后落在过去的项提醒清空")
        XCTAssertNil(store.task(id)?.document.blocks[1].checklist?.reminderAt)
    }

    func testDuplicateDropsItemCompletionAndReminders() throws {
        let (store, actions) = makeActions()
        let id = try makeChecklist([false], actions: actions, reminders: [futureReminder])
        try setChecked(id, true, store: store, actions: actions)
        XCTAssertEqual(store.task(id)?.status, .completed)

        let copyID = try XCTUnwrap(actions.duplicate(id).taskID)
        let copy = try XCTUnwrap(store.task(copyID))
        XCTAssertEqual(copy.kind, .checklist)
        XCTAssertEqual(copy.status, .active)
        XCTAssertEqual(copy.document.blocks.map(\.kind), [.checklist(false)])
        XCTAssertNil(copy.document.blocks[0].checklist,
                     "复制默认不带完成时间与项提醒")
    }

    func testTemplateInstantiationDropsItemCompletionAndReminders() throws {
        let (store, actions) = makeActions()
        let template = TaskTemplate(name: "模板", title: "从模板创建",
            document: NativeDocument(blocks: [
                DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "旧事项")],
                              checklist: ChecklistItemMeta(completedAt: now, reminderAt: futureReminder))
            ]), createdAt: now)
        let id = try XCTUnwrap(actions.createFromTemplate(template, list: .inbox).taskID)
        let created = try XCTUnwrap(store.task(id))
        XCTAssertEqual(created.document.blocks.map(\.kind), [.checklist(false)])
        XCTAssertNil(created.document.blocks[0].checklist)
    }

    func testCompletingLastOpenChildCompletesChecklistParentInOneUndoStep() throws {
        let (store, actions) = makeActions()
        let parent = try makeChecklist([false], actions: actions)
        let child = try XCTUnwrap(actions.createChild(parent, title: "子任务").taskID)
        try setChecked(parent, true, store: store, actions: actions)
        XCTAssertEqual(store.task(parent)?.status, .active, "未完成子任务阻止自动完成")

        let result = actions.complete(child)
        XCTAssertEqual(result.taskID, child)
        XCTAssertEqual(store.task(child)?.status, .completed)
        XCTAssertEqual(store.task(parent)?.status, .completed)

        actions.undo()
        XCTAssertEqual(store.task(child)?.status, .active)
        XCTAssertEqual(store.task(parent)?.status, .active,
                       "子任务与父清单的完成应是一步撤销")
    }

    func testCompletingChildDoesNotCompleteParentWithOpenItems() throws {
        let (store, actions) = makeActions()
        let parent = try makeChecklist([false, false], actions: actions)
        let child = try XCTUnwrap(actions.createChild(parent, title: "子任务").taskID)
        _ = actions.complete(child)
        XCTAssertEqual(store.task(parent)?.status, .active)
    }
}
