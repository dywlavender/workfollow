import XCTest
@testable import WorkFollow

@MainActor
final class SummaryAlignmentTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 28800)!
        return value
    }
    private func date(_ day: Int, month: Int = 10, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private var builder: WeeklyReportBuilder { WeeklyReportBuilder(calendar: calendar) }
    private func task(_ title: String, list: String = "工作", due: Int? = 21, hasTime: Bool = true,
                      dueEnd: Int? = nil, completed: Int? = nil,
                      priority: TaskPriority = .medium, tags: [String] = []) -> Task {
        Task(id: UUID(), title: title, tags: tags, list: TaskList(name: list), priority: priority,
             schedule: .init(dueAt: due.map { date($0, hour: 9) }, hasTime: hasTime,
                             dueEndAt: dueEnd.map { date($0, hour: 18) }),
             status: completed == nil ? .active : .completed,
             childOrder: 0, createdAt: date(1), updatedAt: date(21), completedAt: completed.map { date($0, hour: 18) })
    }

    func testDatePresetsAndInclusiveCustomRangeUseCalendarBoundaries() throws {
        let now = date(21, hour: 14)
        let expected: [(SummaryDateRange.Preset, Date, Date)] = [
            (.today, date(21), date(22)), (.tomorrow, date(22), date(23)), (.yesterday, date(20), date(21)),
            (.thisWeek, date(19), date(26)), (.nextWeek, date(26), date(2, month: 11)), (.lastWeek, date(12), date(19)),
            (.thisMonth, date(1), date(1, month: 11)), (.lastMonth, date(1, month: 9), date(1))
        ]
        for (preset, start, end) in expected {
            let range = SummaryDateRange.preset(preset, now: now, calendar: calendar)
            XCTAssertEqual(range.start, start, preset.rawValue); XCTAssertEqual(range.end, end, preset.rawValue)
            XCTAssertTrue(range.contains(start)); XCTAssertFalse(range.contains(end))
        }
        let custom = try XCTUnwrap(SummaryDateRange.custom(start: date(20, hour: 11), through: date(22, hour: 18), calendar: calendar))
        XCTAssertEqual(custom.start, date(20)); XCTAssertEqual(custom.end, date(23))
        XCTAssertEqual(custom.next(calendar: calendar).end, date(26))
        XCTAssertNil(SummaryDateRange.custom(start: date(22), through: date(20), calendar: calendar))
        XCTAssertEqual(SummaryDateRange.preset(.thisMonth, now: now, calendar: calendar).next(calendar: calendar).end, date(1, month: 12))
    }

    func testDayAndMonthReportsFilterCompletionAndTaskDatesIndependently() {
        let completedToday = task("今天完成旧任务", due: 15, completed: 21)
        let completedYesterday = task("昨天已完成", due: 21, completed: 20)
        let unfinishedToday = task("今天待办")
        let later = task("月底待办", due: 30)
        let today = SummaryDateRange.preset(.today, now: date(21), calendar: calendar)
        let source = [completedToday, completedYesterday, unfinishedToday, later]
        let report = builder.report(tasks: source, weekOf: today.start, range: today)
        XCTAssertEqual(report.completed.map(\.id), [completedToday.id])
        XCTAssertEqual(report.pending.map(\.id), [unfinishedToday.id])
        let month = SummaryDateRange.preset(.thisMonth, now: date(21), calendar: calendar)
        XCTAssertEqual(builder.report(tasks: source, weekOf: month.start, range: month).completed.count, 2)
        XCTAssertEqual(builder.report(tasks: source, weekOf: month.start, range: month).pending.count, 2)
    }

    func testMultipleListsParentTagsAndPriorityCombineAsRealFilters() {
        let root = TaskTag(name: "项目"), childID = UUID()
        let child = TaskTag(id: childID, name: "交付", parentID: root.id)
        let work = task("工作交付", completed: 20, priority: .high, tags: [child.name])
        let study = task("学习交付", list: "学习", completed: 20, priority: .high, tags: [child.name])
        let personal = task("个人事项", list: "个人", completed: 20, priority: .high, tags: [child.name])
        let lower = task("低优先级", completed: 20, priority: .low, tags: [child.name])
        let otherTag = task("其他标签", completed: 20, priority: .high, tags: ["例行"])
        var filter = SummaryFilter.all; filter.priority = .high; filter.tagName = root.name
        let report = builder.report(tasks: [work, study, personal, lower, otherTag], weekOf: date(21), filter: filter,
            tagDirectory: [root, child], listNames: ["工作", "学习"])
        XCTAssertEqual(Set(report.completed.map(\.id)), [work.id, study.id])
        filter.priority = TaskPriority.none
        XCTAssertTrue(builder.report(tasks: [work], weekOf: date(21), filter: filter).completed.isEmpty)
    }

    func testInProgressAndAbandonedAreSeparateFromUntouchedTasks() {
        let untouched = task("尚未开始")
        var checklist = task("检查项进展")
        checklist.document = NativeDocument(blocks: [DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "已核对")]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "待核对")])])
        let focused = task("已投入专注")
        var abandoned = task("不再推进"); abandoned.abandonedAt = date(21, hour: 12)
        let done = task("已经完成", completed: 20)
        let records = [PomodoroRecord(id: UUID(), taskID: focused.id, startedAt: date(21, hour: 10), minutes: 25, completed: true)]
        let tasks = [untouched, checklist, focused, abandoned, done]
        var filter = SummaryFilter.all; filter.status = .inProgress
        XCTAssertEqual(Set(builder.report(tasks: tasks, weekOf: date(21), filter: filter, focusRecords: records).pending.map(\.id)), [checklist.id, focused.id])
        filter.status = .uncompleted
        let pending = builder.report(tasks: tasks, weekOf: date(21), filter: filter, focusRecords: records)
        XCTAssertEqual(pending.pending.map(\.id), [untouched.id]); XCTAssertTrue(pending.abandoned.isEmpty)
        filter.status = .abandoned
        let closed = builder.report(tasks: tasks, weekOf: date(21), filter: filter, focusRecords: records)
        XCTAssertEqual(closed.abandoned.map(\.id), [abandoned.id]); XCTAssertTrue(closed.pending.isEmpty)
    }

    func testTenContentFieldsUseTheirOwnSourceAndCanBeHiddenIndependently() {
        let parent = task("项目主任务", due: 24)
        var child = task("子任务名称", due: 19, completed: 20, tags: ["交付"])
        child.parentID = parent.id
        child.document = NativeDocument(plainText: "详细验收说明")
        let records = [PomodoroRecord(id: UUID(), taskID: child.id, startedAt: date(20, hour: 10), minutes: 25, completed: true)]
        let report = builder.report(tasks: [parent, child], weekOf: date(21), focusRecords: records)
        var options = SummaryDocumentOptions.standard
        options.content = Set(SummaryContentField.allCases)
        let full = builder.document(for: report, options: options)
        for value in ["已完成", "进度 1/1", "[10月20日]", "任务时间 10月19日 09:00", "子任务名称",
                      "主任务：项目主任务", "#交付", "专注 25分0秒 / 1个番茄", "（工作）", "详细验收说明"] {
            XCTAssertTrue(full.plainText.contains(value), value)
        }
        options.content = [.taskName]
        let names = builder.document(for: report, options: options).plainText
        for hidden in ["进度", "[10月", "任务时间", "主任务：", "#交付", "专注", "（工作）", "详细验收说明"] {
            XCTAssertFalse(names.contains(hidden), hidden)
        }
        options.content = [.completedTime]
        let dates = builder.document(for: report, options: options)
        XCTAssertFalse(dates.plainText.contains(child.title)); XCTAssertTrue(dates.plainText.contains("10月20日"))
        XCTAssertTrue(dates.blocks.flatMap(\.runs).flatMap(\.marks).contains(.link(NativeResourceLink.task(child.id).url.absoluteString)))
        XCTAssertEqual(SummaryDocumentOptions.standard.content, [.progress, .completedTime, .taskName])
    }

    func testCompletedFilterStillShowsCompletedChildrenOfAnOpenParent() {
        let parent = task("尚未完成的主任务")
        var child = task("已交付的子任务", completed: 20); child.parentID = parent.id
        var filter = SummaryFilter.all; filter.status = .completed
        let report = builder.report(tasks: [parent, child], weekOf: date(21), filter: filter)
        XCTAssertEqual(report.completed.map(\.id), [child.id]); XCTAssertTrue(report.progress.isEmpty)
        XCTAssertTrue(builder.document(for: report).plainText.contains(child.title))
        filter.status = .inProgress
        let started = builder.report(tasks: [parent, child], weekOf: date(21), filter: filter)
        var options = SummaryDocumentOptions.standard; options.filter = filter
        let text = builder.document(for: started, options: options).plainText
        XCTAssertTrue(text.contains(parent.title)); XCTAssertFalse(text.contains(child.title))
    }

    func testTimeGroupingUsesChronologicalCompletionOrScheduleDates() throws {
        let first = task("较早完成", due: 28, completed: 2)
        let second = task("较晚完成", due: 4, completed: 10)
        let range = try XCTUnwrap(SummaryDateRange.custom(start: date(1), through: date(31), calendar: calendar))
        let report = builder.report(tasks: [second, first], weekOf: range.start, range: range)
        var options = SummaryDocumentOptions.standard; options.grouping = .completedTime
        XCTAssertEqual(builder.document(for: report, options: options).blocks.filter { $0.kind == .heading(2) }.map(\.plainText), ["10月2日", "10月10日"])
        options.grouping = .taskTime
        XCTAssertEqual(builder.document(for: report, options: options).blocks.filter { $0.kind == .heading(2) }.map(\.plainText), ["10月4日", "10月28日"])
        XCTAssertFalse(SummaryGrouping.assignee.isAvailable)
    }

    func testNextPeriodFollowsSelectedDayAndMonthInsteadOfAlwaysAddingAWeek() {
        let today = task("今天任务"), tomorrow = task("明天任务", due: 22), nextWeek = task("下周任务", due: 28)
        let range = SummaryDateRange.preset(.today, now: date(21), calendar: calendar)
        let report = builder.report(tasks: [today, tomorrow, nextWeek], weekOf: range.start, range: range)
        XCTAssertEqual(report.nextWeek.map(\.id), [tomorrow.id])
        var options = SummaryDocumentOptions.standard
        XCTAssertFalse(builder.document(for: report, options: options).plainText.contains(tomorrow.title))
        options.includesNextWeek = true
        let text = builder.document(for: report, options: options).plainText
        XCTAssertTrue(text.contains(tomorrow.title)); XCTAssertFalse(text.contains(nextWeek.title))
        XCTAssertTrue(text.contains("下一周期任务"))
    }

    func testDefaultDocumentUsesFlatStatusSectionsAndCompactDatePrefixes() {
        let done = task("已完成任务", completed: 20)
        let open = task("未完成任务", due: 21)
        let document = builder.document(for: builder.report(tasks: [done, open], weekOf: date(21)))
        XCTAssertEqual(document.blocks.filter { $0.kind == .heading(2) }.map(\.plainText), ["已完成", "未完成"])
        XCTAssertTrue(document.blocks.contains { $0.kind == .bullet && $0.runs.first?.text == "[10月20日] " })
        XCTAssertFalse(document.plainText.contains("本周成果"))
        XCTAssertFalse(document.plainText.contains("本周复盘"))
        XCTAssertFalse(document.plainText.contains("进展与调整"))
    }

    func testDefaultRecipeKeepsGoldenOrderPrefixAndLinks() {
        let parent = task("项目主任务", due: 24)
        var child = task("子任务名称", due: 19, completed: 20, tags: ["交付"])
        child.parentID = parent.id
        let report = builder.report(tasks: [parent, child], weekOf: date(21))
        let document = builder.document(for: report)
        let bullets = document.blocks.filter { $0.kind == .bullet }
        XCTAssertEqual(bullets.map(\.plainText), ["[10月20日] 子任务名称", "项目主任务 · 进度 1/1"])
        XCTAssertEqual(bullets.first?.runs, [
            DocumentRun(text: "[10月20日] "),
            DocumentRun(text: "子任务名称",
                        marks: [.link(NativeResourceLink.task(child.id).url.absoluteString)]),
        ])
        XCTAssertEqual(bullets.last?.runs, [
            DocumentRun(text: "项目主任务",
                        marks: [.link(NativeResourceLink.task(parent.id).url.absoluteString)]),
            DocumentRun(text: " · "),
            DocumentRun(text: "进度 1/1"),
        ])
    }

    func testCustomOrderKeepsPrefixAndDetailOutsideInlineParts() {
        let parent = task("项目主任务", due: 24)
        var child = task("子任务名称", due: 19, completed: 20, tags: ["交付"])
        child.parentID = parent.id
        child.document = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "已核对")]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "待核对")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "验收说明")]),
        ])
        let records = [PomodoroRecord(id: UUID(), taskID: child.id,
                                      startedAt: date(20, hour: 10), minutes: 25, completed: true)]
        let report = builder.report(tasks: [parent, child], weekOf: date(21),
                                    focusRecords: records, listFolders: ["工作": "项目A"])
        var options = SummaryDocumentOptions.standard
        options.content = Set(SummaryContentField.allCases)
        options.contentOrder = [.list, .taskName, .tags, .status, .progress,
                                .taskTime, .parentTask, .focus]
        options.contentStyles.list = .listGroup
        let document = builder.document(for: report, options: options)
        let bullet = document.blocks.first { $0.kind == .bullet }
        XCTAssertEqual(bullet?.plainText, """
        [10月20日] （工作 / 项目A） · 子任务名称 · #交付 · 已完成 · 进度 1/2 · \
        任务时间 10月19日 09:00 · 主任务：项目主任务 · 专注 25分0秒 / 1个番茄
        """)
        XCTAssertEqual(bullet?.runs.first?.text, "[10月20日] ")
        let bulletIndex = document.blocks.firstIndex { $0.kind == .bullet } ?? -1
        let quoteIndexes = document.blocks.indices.filter { document.blocks[$0].kind == .quote }
        XCTAssertFalse(quoteIndexes.isEmpty)
        XCTAssertTrue(quoteIndexes.allSatisfy { $0 > bulletIndex })
        XCTAssertEqual(quoteIndexes.compactMap { document.blocks[$0].plainText },
                       ["已核对", "待核对", "验收说明"])
        XCTAssertFalse(bullet?.plainText.contains("已核对") == true)
    }

    func testCarrySuffixStaysAtEndOfReorderableInlinePart() throws {
        var moved = task("结转任务", due: 21)
        moved.weeklyPlanning = TaskWeeklyPlanning(currentWeek: "2026-10-26", history: [
            TaskWeeklyPlanning.Entry(weekKey: "2026-10-19", enteredAt: date(19),
                                     title: moved.title, listName: moved.list.name,
                                     schedule: moved.schedule, movedToWeek: "2026-10-26",
                                     movedAt: date(21)),
        ])
        let report = builder.report(tasks: [moved], weekOf: date(21))
        XCTAssertEqual(report.carried.map(\.id), [moved.id])
        var options = SummaryDocumentOptions.standard
        options.content = [.taskName, .list]
        options.contentOrder = [.list, .taskName, .status, .progress,
                                .taskTime, .parentTask, .tags, .focus]
        let bullet = try XCTUnwrap(builder.document(for: report, options: options)
            .blocks.first { $0.kind == .bullet })
        XCTAssertTrue(bullet.plainText.hasPrefix("（工作） · 结转任务 · 已结转到 "))
    }

    func testCompletedAndTaskTimeStylesCoverDateTimeAllDayAndMissingDate() {
        let done = task("完成样式", due: 19, completed: 20)
        let allDay = task("全天任务", due: 19, hasTime: false)
        var noDate = task("无日期", due: nil)
        noDate.weeklyPlanning = TaskWeeklyPlanning(
            currentWeek: TaskWeeklyPlanning.key(for: date(21), calendar: calendar))
        let report = builder.report(tasks: [done, allDay, noDate], weekOf: date(21))
        var options = SummaryDocumentOptions.standard
        options.content = [.taskName, .completedTime, .taskTime]

        let defaultText = builder.document(for: report, options: options).plainText
        XCTAssertTrue(defaultText.contains("[10月20日] 完成样式"))
        XCTAssertTrue(defaultText.contains("任务时间 10月19日 09:00"))
        XCTAssertTrue(defaultText.contains("全天任务 · 任务时间 10月19日"))
        XCTAssertTrue(defaultText.contains("无日期 · 未安排日期"))

        options.contentStyles.completedTime = .dateTime
        options.contentStyles.taskTime = .date
        let styled = builder.document(for: report, options: options).plainText
        XCTAssertTrue(styled.contains("[10月20日 18:00] 完成样式"))
        XCTAssertTrue(styled.contains("任务时间 10月19日"))
        XCTAssertFalse(styled.contains("09:00"))
    }

    func testCompletedTimeUsesAbandonedStampForAbandonedRows() throws {
        var abandoned = task("放弃任务", due: 21)
        abandoned.abandonedAt = date(21, hour: 11)
        let report = builder.report(tasks: [abandoned], weekOf: date(21))
        XCTAssertEqual(report.abandoned.map(\.id), [abandoned.id])
        var options = SummaryDocumentOptions.standard
        options.content = [.taskName, .completedTime]
        options.contentStyles.completedTime = .dateTime
        let bullet = try XCTUnwrap(builder.document(for: report, options: options)
            .blocks.first { $0.kind == .bullet })
        XCTAssertEqual(bullet.plainText, "[10月21日 11:00] 放弃任务")
    }

    func testTaskTimeRangeKeepsBothEndsAndHonoursDateOnlyStyle() {
        let ranged = task("跨天任务", due: 20, hasTime: true, dueEnd: 22)
        let report = builder.report(tasks: [ranged], weekOf: date(21))
        var options = SummaryDocumentOptions.standard
        options.content = [.taskName, .taskTime]
        XCTAssertTrue(builder.document(for: report, options: options).plainText
            .contains("任务时间 10月20日 09:00–10月22日 18:00"))
        options.contentStyles.taskTime = .date
        XCTAssertTrue(builder.document(for: report, options: options).plainText
            .contains("任务时间 10月20日–10月22日"))
    }

    func testListGroupStyleUsesFolderAndFallsBackWhenMissing() {
        let done = task("清单样式", completed: 20)
        var options = SummaryDocumentOptions.standard
        options.content = [.taskName, .list]
        options.contentStyles.list = .listGroup
        let folder = builder.report(tasks: [done], weekOf: date(21), listFolders: ["工作": "项目A"])
        XCTAssertTrue(builder.document(for: folder, options: options).plainText.contains("（工作 / 项目A）"))

        let plainList = builder.report(tasks: [done], weekOf: date(21))
        XCTAssertTrue(builder.document(for: plainList, options: options).plainText.contains("（工作）"))
        let emptyFolder = builder.report(tasks: [done], weekOf: date(21), listFolders: ["工作": ""])
        XCTAssertTrue(builder.document(for: emptyFolder, options: options).plainText.contains("（工作）"))
        XCTAssertFalse(builder.document(for: emptyFolder, options: options).plainText.contains(" / "))
        let blankFolder = builder.report(tasks: [done], weekOf: date(21), listFolders: ["工作": "   "])
        XCTAssertTrue(builder.document(for: blankFolder, options: options).plainText.contains("（工作）"))
        XCTAssertFalse(builder.document(for: blankFolder, options: options).plainText.contains(" / "))

        options.contentStyles.list = .list
        XCTAssertTrue(builder.document(for: folder, options: options).plainText.contains("（工作）"))
        XCTAssertFalse(builder.document(for: folder, options: options).plainText.contains("项目A"))
    }

    func testDetailFormattedKeepsRichRunsAndPlainStripsMarksAttachmentsAndDiagrams() {
        let attachment = NativeAttachment(id: UUID(), name: "验收.pdf", storedName: "验收.pdf")
        let diagram = NativeDiagram(xml: NativeDiagram.emptyXML, previewPNG: Data())
        var done = task("详情样式", completed: 20)
        done.document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [
                DocumentRun(text: "加粗", marks: [.bold]),
                DocumentRun(text: "高亮", marks: [.highlight]),
                DocumentRun(text: "链接", marks: [.link("https://example.com")]),
            ]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "", attachment: attachment)]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "", diagram: diagram)]),
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "已核对")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "   ")]),
        ])
        let report = builder.report(tasks: [done], weekOf: date(21))
        var options = SummaryDocumentOptions.standard
        options.content = [.detail]

        let formatted = builder.document(for: report, options: options)
        let formattedQuotes = formatted.blocks.filter { $0.kind == .quote }
        XCTAssertEqual(formattedQuotes.map(\.plainText),
                       ["加粗高亮链接", "", "已核对", "   "])
        let richRuns = formattedQuotes[0].runs
        XCTAssertTrue(richRuns.contains { $0.marks.contains(.bold) })
        XCTAssertTrue(richRuns.contains { $0.marks.contains(.highlight) })
        XCTAssertTrue(richRuns.contains { $0.marks.contains(.link("https://example.com")) })
        XCTAssertEqual(formattedQuotes[1].runs.first?.attachment, attachment)
        XCTAssertTrue(formatted.plainText.contains("任务详情"))

        options.contentStyles.detail = .plain
        let plain = builder.document(for: report, options: options)
        let plainQuotes = plain.blocks.filter { $0.kind == .quote }
        XCTAssertEqual(plainQuotes.map(\.plainText), ["加粗高亮链接", "已核对"])
        XCTAssertTrue(plainQuotes.allSatisfy { block in
            block.runs.count == 1 && block.runs[0].marks.isEmpty
                && block.runs[0].attachment == nil && block.runs[0].diagram == nil
        })
        XCTAssertFalse(plain.plainText.contains("验收.pdf"))
        XCTAssertFalse(plain.plainText.contains("流程图"))
        XCTAssertTrue(plain.plainText.contains("任务详情"))
    }

    func testDetailPlainWithOnlyAttachmentsSkipsFallbackHeader() {
        let attachment = NativeAttachment(id: UUID(), name: "验收.pdf", storedName: "验收.pdf")
        var done = task("仅有附件", completed: 20)
        done.document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "", attachment: attachment)]),
        ])
        let report = builder.report(tasks: [done], weekOf: date(21))
        var options = SummaryDocumentOptions.standard
        options.content = [.detail]
        options.contentStyles.detail = .plain
        let document = builder.document(for: report, options: options)
        XCTAssertFalse(document.blocks.contains { $0.kind == .bullet && $0.plainText == "任务详情" })
        XCTAssertTrue(document.blocks.filter { $0.kind == .quote }.isEmpty)
    }

    func testEmptyInlineFieldsDoNotLeaveExtraSeparators() throws {
        let open = task("无标签任务", due: 21)
        let report = builder.report(tasks: [open], weekOf: date(21))
        var options = SummaryDocumentOptions.standard
        options.content = [.taskName, .parentTask, .tags, .list]
        let bullet = try XCTUnwrap(builder.document(for: report, options: options)
            .blocks.first { $0.kind == .bullet })
        XCTAssertEqual(bullet.plainText, "无标签任务 · （工作）")
    }

    func testHidingTaskNameKeepsLinkAndEmptyContentShowsPlaceholder() {
        let done = task("隐藏名称", completed: 20)
        let report = builder.report(tasks: [done], weekOf: date(21))
        var options = SummaryDocumentOptions.standard
        options.content = [.status]
        let statusOnly = builder.document(for: report, options: options)
        let bullet = statusOnly.blocks.first { $0.kind == .bullet }
        XCTAssertEqual(bullet?.runs.first?.text, "已完成")
        XCTAssertTrue(bullet?.runs.first?.marks
            .contains(.link(NativeResourceLink.task(done.id).url.absoluteString)) == true)

        options.content = []
        let empty = builder.document(for: report, options: options)
        XCTAssertTrue(empty.plainText.contains("未选择显示内容，请在“显示内容”中勾选需要的项目。"))
        XCTAssertFalse(empty.blocks.contains { $0.kind == .bullet })
    }

    func testOldDisplayOptionsDecodeAndTranslateToIndependentFields() throws {
        let data = Data(#"{"filter":{"status":"所有状态","showsDate":true,"showsList":true,"showsTags":false},"grouping":"按清单","includesNextWeek":true}"#.utf8)
        let old = try JSONDecoder().decode(SummaryDocumentOptions.self, from: data)
        XCTAssertEqual(old.content, [.taskName, .progress, .completedTime, .taskTime, .list])
        XCTAssertEqual(old.grouping, .list); XCTAssertTrue(old.includesNextWeek); XCTAssertNil(old.filter.priority)
        XCTAssertEqual(try JSONDecoder().decode(SummaryDocumentOptions.self, from: JSONEncoder().encode(old)), old)
    }

    func testRangeAndMultipleListArchivesSurviveReloadWithoutReplacingWeeklyOrJournal() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("summary-ranges-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SummaryStore(directory: folder)
        let week = SummaryDateRange.week(containing: date(21), calendar: calendar)
        let day = SummaryDateRange.preset(.today, now: date(21), calendar: calendar)
        let month = SummaryDateRange.preset(.thisMonth, now: date(21), calendar: calendar)
        store.saveWeekly(document: .init(plainText: "原有手写周回顾"), weekKey: week.storageKey(calendar: calendar))
        store.save(content: "当天手记", dayKey: "2026-10-21")
        store.saveWeekly(document: .init(plainText: "跨清单月度总结"), weekKey: month.storageKey(calendar: calendar),
            scopeID: "work-study", options: .standard, range: month, listNames: ["工作", "学习"])
        store.saveWeekly(document: .init(plainText: "当天总结"), weekKey: day.storageKey(calendar: calendar), range: day)
        await withCheckedContinuation { continuation in store.flush { error in XCTAssertNil(error); continuation.resume() } }
        let restored = SummaryStore(directory: folder)
        XCTAssertEqual(restored.weeklyEntries.count, 3)
        XCTAssertEqual(restored.weeklyEntry(weekKey: "2026-10-19")?.document.plainText, "原有手写周回顾")
        XCTAssertEqual(restored.entry(for: "2026-10-21")?.content, "当天手记")
        let entry = try XCTUnwrap(restored.weeklyEntry(weekKey: month.storageKey(calendar: calendar), scopeID: "work-study"))
        XCTAssertEqual(entry.range, month); XCTAssertEqual(entry.listNames, ["工作", "学习"])
        restored.saveWeekly(document: .init(plainText: "续写月报"), weekKey: entry.weekKey, scopeID: entry.scopeID)
        XCTAssertEqual(restored.weeklyEntry(weekKey: entry.weekKey, scopeID: entry.scopeID)?.range, month)
    }

    func testNonWeeklyAIKeepsPeriodHeadingsAndDateRange() {
        var options = SummaryAIOptions.weeklyReview; options.isWeeklyPeriod = false
        let prompt = SummaryPiOptimizer.prompt(text: "10月1日-10月31日的任务事实", options: options)
        XCTAssertTrue(prompt.contains("本期成果、进展与调整、本期复盘、下一周期任务"))
        XCTAssertTrue(prompt.contains("遵守原文的日期范围"))
        let document = WeeklyReportBuilder.aiDocument(text: "本期成果\n- 按期交付\n本期复盘\n下次提前评审\n下一周期任务\n", title: "10月1日-10月31日")
        XCTAssertEqual(WeeklyReportBuilder.reflection(in: document).first?.plainText, "下次提前评审")
    }

    func testFocusSnapshotLoadsOnlySelectedPeriodAndRetainsEarlierStartedStatus() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("summary-focus-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let earlier = task("先前已开始"), current = task("本期专注")
        var archive = FocusStore.Archive()
        archive.records = [
            PomodoroRecord(id: UUID(), taskID: earlier.id, startedAt: date(10), minutes: 25, completed: true),
            PomodoroRecord(id: UUID(), taskID: current.id, startedAt: date(21), minutes: 50, completed: true)
        ]
        try JSONEncoder().encode(archive).write(to: folder.appendingPathComponent("focus.json"))
        let store = FocusStore(clock: { self.date(21) }, calendar: calendar, directory: folder)
        let before = store.hydratedRecordCount
        let range = SummaryDateRange.preset(.today, now: date(21), calendar: calendar)
        let snapshot = store.summarySnapshot(in: range)
        XCTAssertEqual(snapshot.records.map(\.taskID), [current.id])
        XCTAssertEqual(snapshot.startedTaskIDs, [earlier.id, current.id])
        XCTAssertEqual(store.hydratedRecordCount - before, 1)
        var filter = SummaryFilter.all; filter.status = .inProgress
        let report = builder.report(tasks: [earlier, current], weekOf: range.start, filter: filter,
            focusRecords: snapshot.records, range: range, startedTaskIDs: snapshot.startedTaskIDs)
        XCTAssertEqual(Set(report.pending.map(\.id)), [earlier.id, current.id]); XCTAssertEqual(report.focusSeconds, 50 * 60)
    }
}
