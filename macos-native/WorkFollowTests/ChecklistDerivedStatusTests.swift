import XCTest
@testable import WorkFollow

/// P1：清单完成时间与任务状态派生。
@MainActor
final class ChecklistDerivedStatusTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let oldCompleted = Date(timeIntervalSince1970: 1_700_000_000)
    private let reminder = Date(timeIntervalSince1970: 1_700_003_600)

    private func makeActions() -> (WorkspaceStore, TaskActions) {
        let store = WorkspaceStore()
        return (store, TaskActions(store: store, clock: { self.now }, calendar: calendar))
    }

    @discardableResult
    private func makeChecklistTask(_ states: [Bool],
                                   actions: TaskActions) throws -> UUID {
        let id = try XCTUnwrap(actions.create(title: "清单任务").taskID)
        let blocks = states.enumerated().map { index, checked in
            DocumentBlock(kind: .checklist(checked),
                          runs: [DocumentRun(text: "事项\(index)")])
        }
        actions.setDocument(id, NativeDocument(blocks: blocks))
        actions.setKind(id, .checklist)
        return id
    }

    func testCheckingLastItemCompletesTaskAndWritesCompletionTimes() throws {
        let (store, actions) = makeActions()
        let id = try makeChecklistTask([false, false], actions: actions)

        var firstChecked = try XCTUnwrap(store.task(id)?.document)
        firstChecked.blocks[0].kind = .checklist(true)
        actions.setDocument(id, firstChecked)
        XCTAssertEqual(store.task(id)?.status, .active)
        XCTAssertEqual(store.task(id)?.document.blocks[0].checklist?.completedAt, now)

        var allChecked = try XCTUnwrap(store.task(id)?.document)
        allChecked.blocks[1].kind = .checklist(true)
        actions.setDocument(id, allChecked)

        XCTAssertEqual(store.task(id)?.status, .completed)
        XCTAssertEqual(store.task(id)?.completedAt, now)
        XCTAssertEqual(store.task(id)?.document.blocks.map { $0.checklist?.completedAt }, [now, now])

        actions.undo()
        XCTAssertEqual(store.task(id)?.status, .active, "勾选与自动完成应是一步撤销")
        XCTAssertEqual(store.task(id)?.document.blocks[0].kind, .checklist(true))
        XCTAssertEqual(store.task(id)?.document.blocks[1].kind, .checklist(false))
    }

    func testOpenSubtaskBlocksAutoCompletion() throws {
        let (store, actions) = makeActions()
        let id = try makeChecklistTask([false], actions: actions)
        _ = try XCTUnwrap(actions.createChild(id, title: "未完成子任务").taskID)

        var checked = try XCTUnwrap(store.task(id)?.document)
        checked.blocks[0].kind = .checklist(true)
        actions.setDocument(id, checked)

        XCTAssertEqual(store.task(id)?.status, .active)
    }

    func testManualCompleteRejectedWithOpenItems() throws {
        let (store, actions) = makeActions()
        let id = try makeChecklistTask([true, false], actions: actions)

        XCTAssertEqual(actions.complete(id), .failure(.checklistItemsIncomplete))
        XCTAssertEqual(store.task(id)?.status, .active)
    }

    func testManualRestoreRejectedWhileAllItemsChecked() throws {
        let (store, actions) = makeActions()
        let id = try makeChecklistTask([true], actions: actions)
        XCTAssertEqual(store.task(id)?.status, .completed)

        XCTAssertEqual(actions.restore(id), .failure(.checklistItemsCompleted))
        XCTAssertEqual(store.task(id)?.status, .completed)
    }

    func testUncheckingOneItemReopensCompletedTask() throws {
        let (store, actions) = makeActions()
        let id = try makeChecklistTask([true, true], actions: actions)
        XCTAssertEqual(store.task(id)?.status, .completed)

        var oneUnchecked = try XCTUnwrap(store.task(id)?.document)
        oneUnchecked.blocks[0].kind = .checklist(false)
        actions.setDocument(id, oneUnchecked)

        XCTAssertEqual(store.task(id)?.status, .active)
        XCTAssertNil(store.task(id)?.completedAt)
        XCTAssertNil(store.task(id)?.document.blocks[0].checklist?.completedAt)
    }

    func testZeroChecklistItemsDoesNotAutoCompleteOrBlock() throws {
        let (store, actions) = makeActions()
        let id = try XCTUnwrap(actions.create(title: "空清单").taskID)
        actions.setDocument(id, NativeDocument(blocks: [
            DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: "只有标题")])
        ]))
        actions.setKind(id, .checklist)
        XCTAssertEqual(store.task(id)?.status, .active)
        XCTAssertNil(store.task(id)?.document.checklistSummary)

        XCTAssertEqual(actions.complete(id).taskID, id)
        XCTAssertEqual(store.task(id)?.status, .completed)
    }

    func testUncheckingWhenOtherItemsWereAlreadyOpenDoesNotReopen() throws {
        let (store, actions) = makeActions()
        let id = try makeChecklistTask([true, true], actions: actions)
        XCTAssertEqual(store.task(id)?.status, .completed)

        // 已完成任务上新增一个未勾选项：总数变化，不重开。
        var withOpenItem = try XCTUnwrap(store.task(id)?.document)
        withOpenItem.blocks.append(DocumentBlock(kind: .checklist(false),
                                                 runs: [DocumentRun(text: "新增")]))
        actions.setDocument(id, withOpenItem)
        XCTAssertEqual(store.task(id)?.status, .completed)

        // 取消一个原勾选项，但取消前并非“其余项全部完成”，保持完成。
        var oneUnchecked = try XCTUnwrap(store.task(id)?.document)
        oneUnchecked.blocks[0].kind = .checklist(false)
        actions.setDocument(id, oneUnchecked)
        XCTAssertEqual(store.task(id)?.status, .completed)
    }

    func testMetadataReconciliationPreservesOldDateAndKeepsReminderOnUncheck() {
        let previous = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "旧完成")],
                          checklist: ChecklistItemMeta(completedAt: oldCompleted, reminderAt: reminder))
        ])
        var edited = previous
        edited.blocks[0].checklist = nil
        let preserved = TaskActions.reconcilingChecklistMetadata(in: edited, previous: previous, now: now)
        XCTAssertEqual(preserved.blocks[0].checklist?.completedAt, oldCompleted)

        var unchecked = preserved
        unchecked.blocks[0].kind = .checklist(false)
        let reopened = TaskActions.reconcilingChecklistMetadata(in: unchecked, previous: preserved, now: now)
        XCTAssertNil(reopened.blocks[0].checklist?.completedAt)
        XCTAssertEqual(reopened.blocks[0].checklist?.reminderAt, reminder)

        let fresh = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "新完成")])
        ])
        var newChecked = fresh
        newChecked.blocks[0].kind = .checklist(true)
        let completed = TaskActions.reconcilingChecklistMetadata(in: newChecked, previous: fresh, now: now)
        XCTAssertEqual(completed.blocks[0].checklist?.completedAt, now)
    }
}
