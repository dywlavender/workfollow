import XCTest
@testable import WorkFollow

@MainActor
final class SummaryPresentationTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 28800)!; return value
    }
    private func day(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 10))!
    }
    private func task(_ title: String, list: String = "工作", completed: Bool = false,
                      priority: TaskPriority = .medium, tags: [String] = [], due: Int = 21) -> Task {
        Task(id: UUID(), title: title, tags: tags, list: TaskList(name: list), priority: priority,
             schedule: .init(dueAt: day(due)), status: completed ? .completed : .active,
             childOrder: 0, createdAt: day(19), updatedAt: day(21), completedAt: completed ? day(20) : nil)
    }
    private var builder: WeeklyReportBuilder { WeeklyReportBuilder(calendar: calendar) }

    func testStatusAndParentTagFiltersSelectTheActualSourceTasks() {
        let root = TaskTag(name: "项目")
        let child = TaskTag(name: "交付", parentID: root.id)
        let done = task("交付评审", completed: true, tags: [child.name])
        let pending = task("整理文档", tags: [child.name])
        let otherList = task("个人记录", list: "个人", completed: true, tags: [child.name])
        let otherTag = task("例行整理", completed: true, tags: ["日常"])
        var filter = SummaryFilter.all
        filter.tagName = root.name; filter.status = .completed
        let focus = [
            PomodoroRecord(id: UUID(), taskID: done.id, startedAt: day(20), minutes: 25, completed: true),
            PomodoroRecord(id: UUID(), taskID: pending.id, startedAt: day(21), minutes: 50, completed: true)
        ]
        let report = builder.report(tasks: [done, pending, otherList, otherTag], weekOf: day(21),
            listName: "工作", filter: filter, tagDirectory: [root, child], focusRecords: focus)
        XCTAssertEqual(report.completed.map(\.id), [done.id])
        XCTAssertTrue(report.pending.isEmpty)
        XCTAssertEqual(report.focusSeconds, 25 * 60)
        filter.status = .uncompleted
        let unfinished = builder.report(tasks: [done, pending, otherList, otherTag], weekOf: day(21),
            listName: "工作", filter: filter, tagDirectory: [root, child])
        XCTAssertTrue(unfinished.completed.isEmpty)
        XCTAssertEqual(unfinished.pending.map(\.id), [pending.id])
    }

    func testDisplayOptionsControlMetadataWhileKeepingLinksToOriginalTasks() {
        let source = task("准备会议", completed: true, tags: ["紧急"])
        let report = builder.report(tasks: [source], weekOf: day(21))
        var options = SummaryDocumentOptions.standard
        options.content = Set(SummaryContentField.allCases)
        let full = builder.document(for: report, options: options)
        XCTAssertTrue(full.plainText.contains("10月20日"))
        XCTAssertTrue(full.plainText.contains("（工作）"))
        XCTAssertTrue(full.plainText.contains("#紧急"))
        options.content = [.taskName]
        let minimal = builder.document(for: report, options: options)
        XCTAssertFalse(minimal.plainText.contains("10月20日"))
        XCTAssertFalse(minimal.plainText.contains("（工作）"))
        XCTAssertFalse(minimal.plainText.contains("#紧急"))
        XCTAssertTrue(minimal.blocks.flatMap(\.runs).flatMap(\.marks)
            .contains(.link(NativeResourceLink.task(source.id).url.absoluteString)))
    }

    func testGroupingChangesSectionsWithoutInflatingCompletedCount() {
        let first = task("高优先级交付", list: "工作", completed: true, priority: .high, tags: ["紧急", "项目"])
        let second = task("学习记录", list: "学习", completed: true, priority: .low, tags: ["项目"])
        let report = builder.report(tasks: [first, second], weekOf: day(21))
        var options = SummaryDocumentOptions.standard
        options.grouping = .priority
        let priorities = builder.document(for: report, options: options).blocks.filter { $0.kind == .heading(2) }.map(\.plainText)
        XCTAssertEqual(priorities, ["高优先级", "低优先级"])
        options.grouping = .list
        let lists = builder.document(for: report, options: options).blocks.filter { $0.kind == .heading(2) }.map(\.plainText)
        XCTAssertEqual(Set(lists), ["工作", "学习"])
        options.grouping = .tag
        let tags = builder.document(for: report, options: options).blocks.filter { $0.kind == .heading(2) }.map(\.plainText)
        XCTAssertEqual(Set(tags), ["紧急", "项目"])
        XCTAssertEqual(report.completed.count, 2)
    }

    func testNextCycleToggleAndRegenerationRetainTheWrittenReflection() throws {
        let current = task("本周交付", completed: true)
        let future = task("下周访谈", due: 28)
        let report = builder.report(tasks: [current, future], weekOf: day(21))
        var document = builder.document(for: report)
        document.blocks.append(DocumentBlock(kind: .heading(2), runs: [DocumentRun(text: "本周复盘")]))
        document.blocks.append(DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "下次提前沟通评审时间。", marks: [.bold])]))
        let reflection = document.blocks.count - 1
        XCTAssertFalse(document.plainText.contains(future.title))
        var options = SummaryDocumentOptions.standard; options.includesNextWeek = true
        let draft = builder.document(for: report, options: options, preserving: document)
        XCTAssertTrue(draft.plainText.contains(future.title))
        XCTAssertEqual(WeeklyReportBuilder.reflection(in: draft).first?.runs, document.blocks[reflection].runs)
        XCTAssertFalse(document.plainText.contains(future.title))
    }

    func testEmptyScopeStaysConciseAndDoesNotAccumulateGeneratedPlaceholders() {
        let report = builder.report(tasks: [], weekOf: day(21))
        let empty = builder.document(for: report)
        XCTAssertEqual(empty.blocks.count, 2)
        XCTAssertEqual(empty.blocks.last?.plainText, "当前范围内没有符合条件的任务")
        let refreshed = builder.document(for: report, preserving: empty)
        XCTAssertEqual(refreshed.plainText, empty.plainText)
        XCTAssertFalse(refreshed.plainText.contains("原有记录"))
        let written = NativeDocument(plainText: "这一周的手写记录。")
        XCTAssertTrue(builder.document(for: report, preserving: written).plainText.contains(written.plainText))
    }

    func testAppliedOptionsPersistEvenWhenTheDocumentTextHasNotChanged() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("summary-options-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SummaryStore(directory: directory)
        let document = NativeDocument(plainText: "保留手写总结")
        store.saveWeekly(document: document, weekKey: "2026-10-19", options: .standard)
        var options = SummaryDocumentOptions.standard
        options.grouping = .list; options.filter.status = .completed; options.includesNextWeek = true
        store.saveWeekly(document: document, weekKey: "2026-10-19", options: options)
        await withCheckedContinuation { continuation in store.flush { error in XCTAssertNil(error); continuation.resume() } }
        let restored = SummaryStore(directory: directory)
        XCTAssertEqual(restored.weeklyEntry(weekKey: "2026-10-19")?.document, document)
        XCTAssertEqual(restored.weeklyEntry(weekKey: "2026-10-19")?.options, options)
        restored.saveWeekly(document: .init(plainText: "继续编辑"), weekKey: "2026-10-19")
        XCTAssertEqual(restored.weeklyEntry(weekKey: "2026-10-19")?.options, options)
    }
}
