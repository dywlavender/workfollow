import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

final class FocusTaskPickerProjectionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }

    private var now: Date { date(2026, 9, 26, hour: 12) }

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    private func makeTask(_ title: String, dueAt: Date? = nil, deadlineAt: Date? = nil,
                          list: String = TaskList.inbox.name, status: TaskStatus = .active,
                          parentID: UUID? = nil, document: String = "") -> Task {
        let stamp = Date(timeIntervalSince1970: 0)
        return Task(id: UUID(), title: title, document: NativeDocument(plainText: document),
                    list: TaskList(name: list), priority: .none,
                    schedule: TaskSchedule(dueAt: dueAt, deadlineAt: deadlineAt),
                    status: status, parentID: parentID, childOrder: 0,
                    createdAt: stamp, updatedAt: stamp)
    }

    func testTodayUsesTaskListMembershipAndGroupsDeadlineOnlyTasksWithToday() {
        let overdue = makeTask("逾期安排", dueAt: date(2026, 9, 24))
        let today = makeTask("今天安排", dueAt: date(2026, 9, 26, hour: 9))
        let deadlineOnlyOverdue = makeTask("只有截止日期", deadlineAt: date(2026, 9, 25))
        let futureDeadlineOnly = makeTask("未来截止日期", deadlineAt: date(2026, 9, 27))
        let futureDue = makeTask("明天安排", dueAt: date(2026, 9, 27))
        let tasks = [overdue, today, deadlineOnlyOverdue, futureDeadlineOnly, futureDue]

        let groups = FocusTaskPickerProjection.groups(tasks: tasks, scope: .today,
                                                      query: "", now: now, calendar: calendar)

        XCTAssertEqual(groups.map(\.title), ["已过期", "今天"])
        XCTAssertEqual(groups[0].tasks.map(\.id), [overdue.id])
        XCTAssertEqual(Set(groups[1].tasks.map(\.id)), Set([today.id, deadlineOnlyOverdue.id]))
        XCTAssertFalse(groups.flatMap(\.tasks).contains { $0.id == futureDeadlineOnly.id })
        XCTAssertFalse(groups.flatMap(\.tasks).contains { $0.id == futureDue.id })
    }

    func testPickerExcludesNonActiveOrHiddenTasksButKeepsParentAndChildRows() {
        let due = date(2026, 9, 26)
        let parent = makeTask("父任务", dueAt: due)
        let child = makeTask("子任务", dueAt: due, parentID: parent.id)
        var completed = makeTask("已完成", dueAt: due, status: .completed)
        completed.completedAt = now
        var deleted = makeTask("已删除", dueAt: due)
        deleted.deletedAt = now
        var abandoned = makeTask("已放弃", dueAt: due)
        abandoned.abandonedAt = now
        var skipped = makeTask("已跳过", dueAt: due)
        skipped.skippedAt = now
        var converted = makeTask("已转笔记", dueAt: due)
        converted.convertedNoteID = UUID()

        let groups = FocusTaskPickerProjection.groups(
            tasks: [parent, child, completed, deleted, abandoned, skipped, converted],
            scope: .today, query: "", now: now, calendar: calendar
        )

        XCTAssertEqual(Set(groups.flatMap(\.tasks).map(\.id)), Set([parent.id, child.id]),
                       "Picker lists child tasks directly; it does not apply task-list tree row lifting")
    }

    func testTomorrowMatchesOnlyDueDayAndNotDeadline() {
        let tomorrow = makeTask("明天", dueAt: date(2026, 9, 27, hour: 8))
        let todayLate = makeTask("今天晚些时候", dueAt: date(2026, 9, 26, hour: 23))
        let dayAfter = makeTask("后天", dueAt: date(2026, 9, 28))
        let deadlineTomorrow = makeTask("仅明天截止", deadlineAt: date(2026, 9, 27))

        let groups = FocusTaskPickerProjection.groups(
            tasks: [tomorrow, todayLate, dayAfter, deadlineTomorrow], scope: .tomorrow,
            query: "", now: now, calendar: calendar
        )

        XCTAssertEqual(groups.map(\.title), ["明天"])
        XCTAssertEqual(groups[0].tasks.map(\.id), [tomorrow.id])
    }

    func testRecentSevenDaysReusesMembershipAndGroupsOverdueThenByDay() {
        let overdue = makeTask("逾期", dueAt: date(2026, 9, 25))
        let today = makeTask("今天", dueAt: date(2026, 9, 26))
        let withinRange = makeTask("范围内", dueAt: date(2026, 10, 2))
        let outsideRange = makeTask("第七天", dueAt: date(2026, 10, 3))

        let groups = FocusTaskPickerProjection.groups(
            tasks: [overdue, today, withinRange, outsideRange], scope: .nextSevenDays,
            query: "", now: now, calendar: calendar
        )

        XCTAssertEqual(groups.first?.title, "已过期")
        XCTAssertEqual(groups.first?.tasks.map(\.id), [overdue.id])
        XCTAssertEqual(groups.dropFirst().flatMap(\.tasks).map(\.id), [today.id, withinRange.id])
        XCTAssertFalse(groups.flatMap(\.tasks).contains { $0.id == outsideRange.id })
    }

    func testInboxAndCustomListScopesRespectCurrentScopeSearchAndDocumentText() {
        let inboxMatch = makeTask("收集项", list: TaskList.inbox.name, document: "季度复盘材料")
        let workMatch = makeTask("工作项", list: "工作", document: "季度复盘材料")
        let tomorrowMatch = makeTask("明天的报告", dueAt: date(2026, 9, 27), list: "工作")

        let inboxGroups = FocusTaskPickerProjection.groups(
            tasks: [inboxMatch, workMatch, tomorrowMatch], scope: .inbox,
            query: "复盘", now: now, calendar: calendar
        )
        let workGroups = FocusTaskPickerProjection.groups(
            tasks: [inboxMatch, workMatch, tomorrowMatch], scope: .list("工作"),
            query: "复盘", now: now, calendar: calendar
        )
        let todaySearch = FocusTaskPickerProjection.groups(
            tasks: [workMatch, tomorrowMatch], scope: .today,
            query: "报告", now: now, calendar: calendar
        )
        let tomorrowSearch = FocusTaskPickerProjection.groups(
            tasks: [workMatch, tomorrowMatch], scope: .tomorrow,
            query: "报告", now: now, calendar: calendar
        )

        XCTAssertEqual(inboxGroups.flatMap(\.tasks).map(\.id), [inboxMatch.id])
        XCTAssertEqual(workGroups.flatMap(\.tasks).map(\.id), [workMatch.id])
        XCTAssertTrue(todaySearch.isEmpty, "Search must not escape the selected scope")
        XCTAssertEqual(tomorrowSearch.flatMap(\.tasks).map(\.id), [tomorrowMatch.id])
    }

    func testTitleSearchIsCaseInsensitiveAndDeadlineDateCanBeShown() {
        let task = makeTask("Quarterly Review", deadlineAt: date(2026, 9, 25))
        let groups = FocusTaskPickerProjection.groups(
            tasks: [task], scope: .inbox, query: "quarterly", now: now, calendar: calendar
        )

        XCTAssertEqual(groups.flatMap(\.tasks).map(\.id), [task.id])
        XCTAssertEqual(FocusTaskPickerProjection.displayTitle(for: task), "Quarterly Review")
        XCTAssertEqual(FocusTaskPickerProjection.date(for: task), date(2026, 9, 25))
    }
}

@MainActor
final class FocusTaskPickerSizingTests: XCTestCase {
    func testTaskPickerPopoverRendersAtContractSizeAndWritesScreenshot() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 12))!
        let task = Task(id: UUID(), title: "准备季度评审", list: .inbox, priority: .none,
                        schedule: TaskSchedule(dueAt: now), parentID: nil, childOrder: 0,
                        createdAt: now, updatedAt: now)
        let workspace = TaskWorkspaceModel(clock: { now }, calendar: calendar,
                                           seedDemoData: false, initialTasks: [task])
        let root = FocusTaskPickerPopover(
            workspace: workspace,
            selectedTaskID: nil,
            scope: .constant(.today),
            query: .constant(""),
            isScopePickerPresented: .constant(false),
            onSelectScope: { _ in },
            onSelectTask: { _ in }, onClearTask: {}, onDismiss: {}
        ).preferredColorScheme(.light)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0,
                                                   width: FocusTaskPickerMetrics.width,
                                                   height: FocusTaskPickerMetrics.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .clear
        window.hasShadow = false
        let hostingView = NSHostingView(rootView: root)
        window.contentView = hostingView
        window.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        XCTAssertEqual(hostingView.fittingSize.width, FocusTaskPickerMetrics.width, accuracy: 0.5)
        XCTAssertEqual(hostingView.fittingSize.height, FocusTaskPickerMetrics.height, accuracy: 0.5)

        let image = try XCTUnwrap(CGWindowListCreateImage(
            .null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.bestResolution]))
        let bitmap = NSBitmapImageRep(cgImage: image)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let screenshot = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-task-picker-popover.png")
        try png.write(to: screenshot)
        window.orderOut(nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshot.path))
    }

    func testScopePopoverRendersSystemScopesAndCustomListsAtNarrowWidth() throws {
        let root = FocusTaskScopePopover(
            selectedScope: .today,
            listNames: ["工作", "学习"],
            listColor: { _ in WFColors.accent },
            onSelect: { _ in },
            onDismiss: {}
        ).preferredColorScheme(.light)
        let expectedHeight: CGFloat = 4 * FocusTaskPickerMetrics.scopeRowHeightCompact
            + 9 + 2 * FocusTaskPickerMetrics.scopeRowHeightCompact + 16
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0,
                                                   width: FocusTaskPickerMetrics.scopeWidth,
                                                   height: expectedHeight),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .clear
        window.hasShadow = false
        let hostingView = NSHostingView(rootView: root)
        window.contentView = hostingView
        window.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        XCTAssertEqual(hostingView.fittingSize.width, FocusTaskPickerMetrics.scopeWidth, accuracy: 0.5)
        XCTAssertEqual(hostingView.fittingSize.height, expectedHeight, accuracy: 0.5)

        let image = try XCTUnwrap(CGWindowListCreateImage(
            .null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.bestResolution]))
        let bitmap = NSBitmapImageRep(cgImage: image)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let screenshot = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-task-scope-popover.png")
        try png.write(to: screenshot)
        window.orderOut(nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshot.path))
    }
}
