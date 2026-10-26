import AppKit
import XCTest
@testable import WorkFollow

/// P2：检查项行内铃铛/删除命中区、提醒落库与剪贴板口径。
@MainActor
final class ChecklistEditorInteractionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let reminder = Date(timeIntervalSince1970: 1_800_003_600)

    func testReminderAndDeleteHitRectsNeverOverlap() throws {
        let view = try makeView(document: NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "检查项")])
        ]))
        let bell = view.checklistReminderHitRect(centerY: 20)
        let delete = view.checklistDeleteHitRect(centerY: 20)
        XCTAssertEqual(bell.width, 24, accuracy: 0.5)
        XCTAssertEqual(bell.height, 24, accuracy: 0.5)
        XCTAssertEqual(delete.width, 24, accuracy: 0.5)
        XCTAssertLessThanOrEqual(bell.maxX, delete.minX, "铃铛在删除按钮左侧且不相交")
        XCTAssertLessThanOrEqual(delete.maxX, view.bounds.maxX)
        XCTAssertGreaterThan(bell.minX, view.bounds.midX)
    }

    func testLineIndexMatchesChecklistParagraphs() throws {
        let view = try makeView(document: NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "甲")]),
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "乙")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "丙")])
        ]))
        let source = view.string as NSString
        XCTAssertEqual(view.checklistLineIndex(for: 0), 0)
        XCTAssertEqual(view.checklistLineIndex(for: source.range(of: "乙").location), 1)
        XCTAssertEqual(view.checklistLineIndex(for: source.range(of: "丙").location), 2)
    }

    func testWorkspaceWritesAndClearsItemReminder() throws {
        let id = UUID()
        var task = Task(id: id, title: "清单", document: checklistDocument(), tags: [],
                        list: TaskList(name: "收件箱"), priority: .none,
                        schedule: TaskSchedule(), parentID: nil, childOrder: 0,
                        createdAt: now, updatedAt: now)
        task.kind = .checklist
        let workspace = TaskWorkspaceModel(clock: { self.now }, seedDemoData: false, initialTasks: [task])

        XCTAssertEqual(workspace.setChecklistItemReminder(id, line: 0, at: reminder).taskID, id)
        XCTAssertEqual(workspace.checklistItemMeta(id, line: 0)?.reminderAt, reminder)
        XCTAssertEqual(workspace.task(for: id)?.document.checklistSummary?.reminders.count, 1)

        XCTAssertEqual(workspace.setChecklistItemReminder(id, line: 0, at: nil).taskID, id)
        XCTAssertNil(workspace.checklistItemMeta(id, line: 0)?.reminderAt)
        XCTAssertEqual(workspace.task(for: id)?.document.checklistSummary?.reminders.count, 0)
    }

    func testRemovingAnItemDropsItsReminderFromTheSummary() throws {
        let id = UUID()
        var task = Task(id: id, title: "清单", document: checklistDocument(), tags: [],
                        list: TaskList(name: "收件箱"), priority: .none,
                        schedule: TaskSchedule(), parentID: nil, childOrder: 0,
                        createdAt: now, updatedAt: now)
        task.kind = .checklist
        let workspace = TaskWorkspaceModel(clock: { self.now }, seedDemoData: false, initialTasks: [task])
        _ = workspace.setChecklistItemReminder(id, line: 1, at: reminder)
        XCTAssertEqual(workspace.task(for: id)?.document.checklistSummary?.reminders.count, 1)

        var shortened = try XCTUnwrap(workspace.task(for: id)?.document)
        shortened.blocks.removeLast()
        _ = workspace.setDocument(id, shortened)

        XCTAssertEqual(workspace.task(for: id)?.document.checklistSummary?.reminders.count, 0)
        XCTAssertEqual(workspace.task(for: id)?.document.checklistSummary?.total, 1)
    }

    func testInternalPasteKeepsCheckedStateButNeverCarriesReminder() throws {
        let source = try makeView(document: NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "已完成项")]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "未完成项")])
        ]))
        source.profile.checklistRemindersEnabled = true
        source.profile.checklistItem = { line in
            line == 0 ? ChecklistItemMeta(completedAt: self.now, reminderAt: self.reminder) : nil
        }
        let line = (source.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        source.setSelectedRange(line)
        let board = NSPasteboard(name: NSPasteboard.Name("checklist-paste-\(UUID().uuidString)"))
        board.clearContents()
        XCTAssertTrue(source.copyDocumentFragment(to: board))

        let target = try makeView(document: NativeDocument(plainText: ""))
        target.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertTrue(target.pasteDocumentFragment(from: board))

        let pasted = DocumentTextCodec.decode(target.attributedString(),
            preserving: NativeDocument(plainText: target.string), trailing: target.pendingTrailingBlock)
        XCTAssertEqual(pasted.blocks.first?.kind, .checklist(true), "内部粘贴保留勾选状态")
        XCTAssertNil(pasted.blocks.first?.checklist, "剪贴板不携带完成时间与项提醒")
    }

    func testExternalPlainTextPasteCreatesNoChecklistMetadata() throws {
        let target = try makeView(document: NativeDocument(plainText: ""))
        target.setSelectedRange(NSRange(location: 0, length: 0))
        let board = NSPasteboard(name: NSPasteboard.Name("checklist-plain-\(UUID().uuidString)"))
        board.clearContents()
        board.setString("- 普通文本", forType: .string)
        target.paste(nil)

        let pasted = DocumentTextCodec.decode(target.attributedString(),
            preserving: NativeDocument(plainText: target.string), trailing: target.pendingTrailingBlock)
        XCTAssertTrue(pasted.blocks.allSatisfy { $0.checklist == nil })
    }

    func testReminderPresetsAndCustomDefaultUseCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 8))!
        let morningPresets = ChecklistItemReminderPanel.presets(now: morning, calendar: calendar)
        XCTAssertEqual(morningPresets.map(\.title), ["今天 09:00", "今天 18:00", "明天 09:00"])
        XCTAssertEqual(morningPresets[0].date,
                       calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 9)))
        XCTAssertEqual(morningPresets[1].date,
                       calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 18)))
        XCTAssertEqual(morningPresets[2].date,
                       calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 9)))
        XCTAssertEqual(ChecklistItemReminderPanel.defaultCustomDate(now: morning, calendar: calendar),
                       morningPresets[2].date)

        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 20))!
        let eveningPresets = ChecklistItemReminderPanel.presets(now: evening, calendar: calendar)
        XCTAssertEqual(eveningPresets.map(\.title), ["明天 09:00", "明天 18:00", "后天 09:00"])
        XCTAssertTrue(eveningPresets.allSatisfy { $0.date > evening },
                      "已过去的固定时刻不能再作为预设")
        XCTAssertEqual(ChecklistItemReminderPanel.dayText(
            eveningPresets[2].date, now: evening, calendar: calendar), "后天")
    }

    func testCalendarSelectionCombinesDayWithHalfHourTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 20))!
        let options = ChecklistItemReminderPanel.halfHourOptions(day: now, calendar: calendar)
        XCTAssertEqual(options.count, 48)
        XCTAssertEqual(ChecklistItemReminderPanel.clockText(options[0], calendar: calendar), "00:00")
        XCTAssertEqual(ChecklistItemReminderPanel.clockText(options[47], calendar: calendar), "23:30")

        let available = ChecklistItemReminderPanel.availableHalfHourOptions(
            day: now, now: now, calendar: calendar)
        XCTAssertEqual(ChecklistItemReminderPanel.clockText(available.first!, calendar: calendar), "20:30")
        XCTAssertTrue(available.allSatisfy { $0 > now })
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(ChecklistItemReminderPanel.availableHalfHourOptions(
            day: tomorrow, now: now, calendar: calendar).count, 48)

        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        let merged = try XCTUnwrap(ChecklistItemReminderPanel.combined(day: day, time: options[37],
                                                                      calendar: calendar))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: merged),
                       DateComponents(year: 2026, month: 11, day: 3, hour: 18, minute: 30))
        XCTAssertEqual(ChecklistItemReminderPanel.dayText(now, now: now, calendar: calendar), "今天")
        XCTAssertEqual(ChecklistItemReminderPanel.dayText(now.addingTimeInterval(86_400),
                                                          now: now, calendar: calendar), "明天")
    }

    func testPresentingAndDismissingTheReminderPanelTracksItsLifetime() throws {
        let view = try makeView(document: NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "事项")])
        ]))
        view.profile.checklistRemindersEnabled = true
        view.profile.checklistItem = { _ in ChecklistItemMeta() }
        let caret = try XCTUnwrap(view.viewRect(forCharacterAt: 0))

        view.presentChecklistReminderPanel(lineIndex: 0, centerY: caret.midY)
        let panel = try XCTUnwrap(view.checklistReminderPanel, "点铃铛应创建提醒面板")
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.canBecomeKey, "面板需要键盘焦点才能响应 Return/Esc")
        XCTAssertEqual(panel.parent, view.window)

        view.dismissChecklistReminderPanel()
        XCTAssertNil(view.checklistReminderPanel)
    }

    func testHoverTracksTheChecklistRowUnderThePointer() throws {
        let view = try makeView(document: NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "甲")]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "乙")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")])
        ]))
        view.profile.checklistRemindersEnabled = true
        let second = try XCTUnwrap(view.viewRect(forCharacterAt: 2))
        view.updateChecklistHover(at: NSPoint(x: second.midX, y: second.midY))
        XCTAssertEqual(view.hoveredChecklistLine, 1, "悬停第二行时控件跟随第二行")

        let body = try XCTUnwrap(view.viewRect(forCharacterAt: (view.string as NSString).range(of: "正文").location))
        view.updateChecklistHover(at: NSPoint(x: body.midX, y: body.midY))
        XCTAssertNil(view.hoveredChecklistLine, "正文行不显示清单控件")

        view.updateChecklistHover(at: nil)
        XCTAssertNil(view.hoveredChecklistLine)
    }

    func testHoverCoversWrappedLinesOfTheSameChecklistItem() throws {
        let long = String(repeating: "换行后的检查项内容", count: 12)
        let view = try makeView(document: NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: long)])
        ]))
        view.profile.checklistRemindersEnabled = true
        view.frame.size.width = 180
        view.layoutSubtreeIfNeeded()

        let source = view.string as NSString
        var firstY: CGFloat?
        var wrapped: NSRect?
        for index in 0..<source.length {
            guard let rect = view.viewRect(forCharacterAt: index) else { continue }
            if let firstY {
                if rect.midY > firstY + 1 { wrapped = rect; break }
            } else {
                firstY = rect.midY
            }
        }
        let rect = try XCTUnwrap(wrapped, "需要至少换出一行")
        view.updateChecklistHover(at: NSPoint(x: rect.midX, y: rect.midY))
        XCTAssertEqual(view.hoveredChecklistLine, 0, "换行后的第二视觉行仍属于同一检查项")
    }

    func testTogglingKeepsSelectionAndDoesNotReplaceText() throws {
        let view = try makeView(document: NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "甲", marks: [.bold])]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "乙")]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "丙")])
        ]))
        view.setSelectedRange(NSRange(location: 4, length: 0))
        let before = view.selectedRange()
        let text = view.string

        view.toggleNoteChecklist(at: 0)

        XCTAssertEqual(view.string, text, "勾选不替换正文")
        XCTAssertEqual(view.selectedRange(), before, "插入点留在原行，不跳回顶部")
        XCTAssertEqual(view.textStorage?.attribute(DocumentTextCodec.blockKey, at: 0,
                                                   effectiveRange: nil) as? String, "checked")
        XCTAssertTrue((view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            .map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false,
            "行内粗体不因勾选丢失")
    }

    func testTogglingIsUndoableWithAttributesRestored() throws {
        let view = try makeView(document: NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "甲")]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "乙")])
        ]))
        view.toggleNoteChecklist(at: 0)
        XCTAssertEqual(view.textStorage?.attribute(DocumentTextCodec.blockKey, at: 0,
                                                   effectiveRange: nil) as? String, "checked")

        view.undo(nil)
        XCTAssertEqual(view.textStorage?.attribute(DocumentTextCodec.blockKey, at: 0,
                                                   effectiveRange: nil) as? String, "checklist")
        XCTAssertEqual(view.string, "甲\n乙")
    }

    func testAttributeToggleCommitsCheckedStateThroughCoordinator() throws {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "事项")])
        ])
        let view = try makeView(document: document)
        var committed: NativeDocument?
        let coordinator = DocumentEditorCoordinator(documentID: UUID(), document: document,
            onDocumentChange: { committed = $0 },
            onEscape: { .keepInspector }, onEditingChanged: { _ in })
        view.delegate = coordinator

        view.toggleNoteChecklist(at: 0)

        XCTAssertEqual(committed?.blocks.first?.kind, .checklist(true))
        XCTAssertEqual(committed?.plainText, "事项")
    }

    func testChecklistRevealRequestIsConsumedOnlyForItsTask() throws {
        let workspace = TaskWorkspaceModel(clock: { self.now }, seedDemoData: false)
        let taskID = UUID()
        let blockID = UUID()
        workspace.requestChecklistReveal(taskID: taskID, blockID: blockID)
        XCTAssertNil(workspace.consumeChecklistReveal(for: UUID()), "别的任务不能消费这条定位请求")
        XCTAssertEqual(workspace.consumeChecklistReveal(for: taskID), blockID)
        XCTAssertNil(workspace.consumeChecklistReveal(for: taskID), "定位请求只消费一次")
    }

    // MARK: - Helpers

    private func checklistDocument() -> NativeDocument {
        NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "第一项")]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "第二项")])
        ])
    }

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
        view.typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
        window.makeFirstResponder(view)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        return view
    }
}
