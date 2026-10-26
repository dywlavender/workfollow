import XCTest
@testable import WorkFollow

/// P1：文本 ↔ 清单切换保留勾选、完成时间和项提醒。
@MainActor
final class ChecklistModeSwitchTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let completed = Date(timeIntervalSince1970: 1_700_000_000)
    private let reminder = Date(timeIntervalSince1970: 1_700_003_600)

    private func makeActions() -> (WorkspaceStore, TaskActions) {
        let store = WorkspaceStore()
        return (store, TaskActions(store: store, clock: { self.now }, calendar: calendar))
    }

    func testTextChecklistRoundTripRestoresCheckedStateAndReminder() throws {
        let (store, actions) = makeActions()
        let id = try XCTUnwrap(actions.create(title: "形态往返").taskID)
        actions.setDocument(id, NativeDocument(blocks: [
            DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: "标题")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "甲")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "乙")])
        ]))

        actions.setKind(id, .checklist)
        var checklist = try XCTUnwrap(store.task(id)?.document)
        checklist.blocks[1].kind = .checklist(true)
        checklist.blocks[1].checklist = ChecklistItemMeta(completedAt: completed)
        checklist.blocks[2].checklist = ChecklistItemMeta(reminderAt: reminder)
        actions.setDocument(id, checklist)

        XCTAssertEqual(store.task(id)?.document.blocks[1].kind, .checklist(true))
        XCTAssertEqual(store.task(id)?.document.blocks[2].kind, .checklist(false))

        actions.setKind(id, .text)
        let text = try XCTUnwrap(store.task(id)?.document)
        XCTAssertEqual(text.blocks[1].kind, .paragraph)
        XCTAssertTrue(text.blocks[1].runs[0].marks.contains(.strikethrough))
        XCTAssertEqual(text.blocks[1].checklist?.completedAt, completed)
        XCTAssertEqual(text.blocks[2].checklist?.reminderAt, reminder)
        XCTAssertEqual(text.blocks[0].kind, .heading(1), "富文本块不参与映射")

        actions.setKind(id, .checklist)
        let roundTrip = try XCTUnwrap(store.task(id)?.document)
        XCTAssertEqual(roundTrip.blocks[1].kind, .checklist(true), "按完成时间恢复勾选")
        XCTAssertEqual(roundTrip.blocks[1].checklist?.completedAt, completed)
        XCTAssertEqual(roundTrip.blocks[2].kind, .checklist(false))
        XCTAssertEqual(roundTrip.blocks[2].checklist?.reminderAt, reminder)
        XCTAssertEqual(roundTrip.blocks[0].kind, .heading(1))
    }

    func testSwitchingToChecklistIsOneUndoStep() throws {
        let (store, actions) = makeActions()
        let id = try XCTUnwrap(actions.create(title: "撤销形态").taskID)
        actions.setDocument(id, NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")])
        ]))
        store.clearUndo()

        actions.setKind(id, .checklist)
        XCTAssertEqual(store.task(id)?.kind, .checklist)
        XCTAssertEqual(store.task(id)?.document.blocks.first?.kind, .checklist(false))

        actions.undo()
        XCTAssertEqual(store.task(id)?.kind, .text)
        XCTAssertEqual(store.task(id)?.document.blocks.first?.kind, .paragraph)
    }
}
