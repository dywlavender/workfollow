import XCTest
@testable import WorkFollow

final class InlineDateReminderTests: XCTestCase {
    /// 行内日期提醒写在普通段落上，也要进入摘要以便排期。
    func testPlainParagraphReminderIsProjectedIntoSummary() {
        var document = NativeDocument(plainText: "周五前提交方案")
        let blockID = document.blocks[0].id
        let fireDate = Date(timeIntervalSince1970: 9000)
        document.blocks[0].checklist = ChecklistItemMeta(completedAt: nil, reminderAt: fireDate, allDay: false)
        let summary = ChecklistSummary(blocks: document.blocks)
        XCTAssertEqual(summary.total, 0)
        XCTAssertEqual(summary.reminders.count, 1)
        XCTAssertEqual(summary.reminders.first?.blockID, blockID)
        XCTAssertEqual(summary.reminders.first?.title, "周五前提交方案")
        XCTAssertEqual(summary.reminders.first?.fireDate, fireDate)
    }
}
