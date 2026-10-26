import XCTest
@testable import WorkFollow

/// P1：任务形态与清单正文变更要进入变更集，并按需触发提醒对账。
final class TaskChangeSetChecklistTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let reminderA = Date(timeIntervalSince1970: 1_700_000_000)
    private let reminderB = Date(timeIntervalSince1970: 1_700_003_600)

    private func task(kind: TaskKind, blocks: [DocumentBlock]) -> Task {
        var task = Task(id: UUID(), title: "变更集", document: NativeDocument(blocks: blocks),
                        list: .inbox, priority: .none, schedule: TaskSchedule(),
                        parentID: nil, childOrder: 0, createdAt: now, updatedAt: now)
        task.kind = kind
        return task
    }

    func testKindOnlyChangeIsRecordedAndAffectsReminders() {
        let before = task(kind: .text, blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")])
        ])
        var after = before
        after.kind = .note

        let change = TaskChangeSet(updatedFrom: before, to: after)
        XCTAssertEqual(change.entries.count, 1)
        XCTAssertTrue(change.entries[0].changedFields.contains(.kind))
        XCTAssertTrue(change.affectsReminders)
    }

    func testChecklistTextEditWithoutReminderChangeDoesNotAffectReminders() {
        let before = task(kind: .checklist, blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "甲")])
        ])
        var after = before
        after.document = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "乙")])
        ])

        let change = TaskChangeSet(updatedFrom: before, to: after)
        XCTAssertTrue(change.entries[0].changedFields.contains(.document))
        XCTAssertFalse(change.affectsReminders)
    }

    func testChecklistReminderChangeAffectsReminders() {
        let before = task(kind: .checklist, blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "甲")],
                          checklist: ChecklistItemMeta(reminderAt: reminderA))
        ])
        var after = before
        after.document = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "甲")],
                          checklist: ChecklistItemMeta(reminderAt: reminderB))
        ])

        let change = TaskChangeSet(updatedFrom: before, to: after)
        XCTAssertTrue(change.affectsReminders)
    }

    func testNonChecklistTextEditDoesNotAffectReminders() {
        let before = task(kind: .text, blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "甲")])
        ])
        var after = before
        after.document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "乙")])
        ])

        let change = TaskChangeSet(updatedFrom: before, to: after)
        XCTAssertFalse(change.affectsReminders)
    }
}
