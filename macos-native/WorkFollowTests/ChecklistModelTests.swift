import XCTest
@testable import WorkFollow

/// P1：检查项元数据、Delta 行属性与摘要投影。
final class ChecklistModelTests: XCTestCase {
    private let completed = Date(timeIntervalSince1970: 1_700_000_000)
    private let reminder = Date(timeIntervalSince1970: 1_700_003_600)

    func testChecklistMetaRoundTripsThroughNativeDocumentAndDelta() throws {
        let meta = ChecklistItemMeta(completedAt: completed, reminderAt: reminder, allDay: true)
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "已完成")], checklist: meta),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "待办")])
        ])

        let decoded = try JSONDecoder().decode(NativeDocument.self,
            from: try JSONEncoder().encode(document))
        XCTAssertEqual(decoded.blocks[0].checklist, meta)
        XCTAssertNil(decoded.blocks[1].checklist)

        let fromDelta = QuillDeltaCodec.document(from: QuillDeltaCodec.delta(from: document))
        XCTAssertEqual(fromDelta.blocks[0].id, document.blocks[0].id)
        XCTAssertEqual(fromDelta.blocks[0].checklist, meta)
        XCTAssertEqual(fromDelta.blocks[1].checklist, nil)
    }

    func testLegacyBlockArchiveWithoutChecklistKeyDecodesAsNil() throws {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "旧档")],
                          checklist: ChecklistItemMeta(completedAt: completed))
        ])
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(["blocks": document.blocks])) as? [String: Any])
        var blocks = try XCTUnwrap(json["blocks"] as? [[String: Any]])
        blocks[0].removeValue(forKey: "checklist")
        json["blocks"] = blocks
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(NativeDocument.self, from: data)
        XCTAssertEqual(decoded.blocks.first?.kind, .checklist(true))
        XCTAssertNil(decoded.blocks.first?.checklist)
    }

    func testEmptyMetaNormalizesToNil() {
        let block = DocumentBlock(kind: .checklist(false),
                                  runs: [DocumentRun(text: "空元数据")],
                                  checklist: ChecklistItemMeta())
        XCTAssertNil(block.checklist)
    }

    func testChecklistSummaryCountsOnlyChecklistBlocksAndSkipsCompletedReminders() {
        let openReminder = Date(timeIntervalSince1970: 1_700_007_200)
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "完成")],
                          checklist: ChecklistItemMeta(completedAt: completed, reminderAt: reminder)),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "待办")],
                          checklist: ChecklistItemMeta(reminderAt: openReminder)),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "无提醒")])
        ])

        let summary = try? XCTUnwrap(document.checklistSummary)
        XCTAssertEqual(summary?.total, 3)
        XCTAssertEqual(summary?.done, 1)
        XCTAssertEqual(summary?.reminders.count, 1)
        XCTAssertEqual(summary?.reminders.first?.title, "待办")
        XCTAssertEqual(summary?.reminders.first?.fireDate, openReminder)
        XCTAssertEqual(summary?.reminders.first?.blockID, document.blocks[1].id)
    }

    func testEmptyChecklistDocumentHasNoSummary() {
        let document = NativeDocument(plainText: "正文")
        XCTAssertNil(document.checklistSummary)
    }
}
