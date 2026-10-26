import AppKit
import XCTest
@testable import WorkFollow

/// P2：检查项行号映射、VoiceOver 描述与行内自定义动作。
@MainActor
final class ChecklistAccessibilityTests: XCTestCase {
    private let reminder = Date(timeIntervalSince1970: 1_800_003_600)

    func testLineRangesIncludeTheTrailingEmptyParagraph() throws {
        let view = try makeView(document: NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "甲")]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "乙")]),
            DocumentBlock(kind: .checklist(false), runs: [])
        ]))
        XCTAssertEqual(view.characterRange(forChecklistLine: 0), NSRange(location: 0, length: 2))
        XCTAssertEqual(view.characterRange(forChecklistLine: 2), NSRange(location: 4, length: 0))
        XCTAssertNil(view.characterRange(forChecklistLine: 3))
    }

    func testVoiceOverLabelReportsCheckedStateAndReminder() throws {
        let view = try makeView(document: NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "未完成项")]),
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "已完成项")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")])
        ]))
        view.profile.checklistRemindersEnabled = true
        view.profile.checklistItem = { line in
            line == 0 ? ChecklistItemMeta(reminderAt: self.reminder) : nil
        }

        XCTAssertEqual(view.checklistAccessibilityLabel(forLine: 0), "检查事项：未完成项，未完成，有提醒")
        XCTAssertEqual(view.checklistAccessibilityLabel(forLine: 1), "检查事项：已完成项，已完成")
        XCTAssertNil(view.checklistAccessibilityLabel(forLine: 2), "正文行不冒充检查事项")

        view.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertEqual(view.accessibilityLabel(), "检查事项：未完成项，未完成，有提醒",
                       "自定义描述必须真正接到 AX 层")
        let body = (view.string as NSString).range(of: "正文").location
        view.setSelectedRange(NSRange(location: body, length: 0))
        XCTAssertNotEqual(view.accessibilityLabel(), "检查事项：未完成项，未完成，有提醒")
    }

    func testCustomActionsExposeToggleReminderAndDeleteOnChecklistRows() throws {
        let view = try makeView(document: NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "事项")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")])
        ]))
        view.profile.checklistRemindersEnabled = true

        view.setSelectedRange(NSRange(location: 1, length: 0))
        let checklistActions = (view.accessibilityCustomActions() ?? []).map(\.name)
        XCTAssertTrue(checklistActions.contains("勾选"))
        XCTAssertTrue(checklistActions.contains("设置检查事项提醒"))
        XCTAssertTrue(checklistActions.contains("删除检查事项"))

        view.setSelectedRange(NSRange(location: (view.string as NSString).range(of: "正文").location, length: 0))
        let bodyActions = (view.accessibilityCustomActions() ?? []).map(\.name)
        XCTAssertFalse(bodyActions.contains("设置检查事项提醒"))
    }

    func testCustomActionsKeepToggleButDropReminderControlsOutsideChecklistMode() throws {
        let view = try makeView(document: NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "笔记内复选项")])
        ]))
        view.profile.checklistRemindersEnabled = false
        view.setSelectedRange(NSRange(location: 0, length: 0))
        let names = (view.accessibilityCustomActions() ?? []).map(\.name)
        XCTAssertTrue(names.contains("勾选"), "笔记里的检查项仍应能通过 VoiceOver 勾选")
        XCTAssertFalse(names.contains("设置检查事项提醒"))
        XCTAssertFalse(names.contains("删除检查事项"))
    }

    func testRevealChecklistLineMovesTheCaretToThatParagraph() throws {
        let view = try makeView(document: NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "甲")]),
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "乙")])
        ]))
        view.revealChecklistLine(1)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 2, length: 0))
    }

    // MARK: - Helpers

    private func makeView(document: NativeDocument) throws -> NativeTextView {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200), textContainer: nil)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        window.orderFront(nil)
        addTeardownBlock { window.close() }
        view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        window.makeFirstResponder(view)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        return view
    }
}
