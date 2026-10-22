import XCTest
@testable import WorkFollow

@MainActor
final class WeeklyPlanningTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 28800)!
        return value
    }
    private func day(_ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func task(_ title: String, due: Date? = nil, parent: UUID? = nil, created: Date? = nil) -> Task {
        Task(id: UUID(), title: title, list: TaskList(name: "工作"), priority: .medium,
             schedule: .init(dueAt: due, hasTime: due != nil), parentID: parent,
             childOrder: 0, createdAt: created ?? day(12), updatedAt: day(12))
    }
    private func workspace(_ tasks: [Task] = []) -> TaskWorkspaceModel {
        TaskWorkspaceModel(clock: { self.day(21, hour: 12) }, calendar: calendar,
                           seedDemoData: false, initialTasks: tasks)
    }
    private var projection: WeeklyPlanProjection { .init(weekStart: day(19), calendar: calendar) }

    func testWeeklyCaptureDoesNotInventDateAndOneUndoRemovesWholeCapture() throws {
        let overdue = task("上周遗留", due: day(16))
        let future = task("下周", due: day(27))
        let model = workspace([overdue, future])
        let id = try XCTUnwrap(model.createWeeklyTask(title: "本周做方案", list: "工作", weekOf: day(21)))
        let added = try XCTUnwrap(model.task(for: id))
        XCTAssertNil(added.schedule.dueAt)
        XCTAssertNil(added.reminderAt)
        XCTAssertEqual(added.weeklyPlanning?.currentWeek, "2026-10-19")
        XCTAssertEqual(projection.tasks(from: model.allTasks).map(\.id), [id])
        XCTAssertEqual(model.count(for: .weekPlan), 1)
        XCTAssertTrue(WeeklyPlanProjection(weekStart: day(12), calendar: calendar).includes(overdue))
        model.undo()
        XCTAssertNil(model.task(for: id))
        XCTAssertEqual(model.allTasks.count, 2)
        model.redo()
        XCTAssertEqual(model.task(for: id)?.weeklyPlanning, added.weeklyPlanning)
    }

    func testSelectiveCarryKeepsIdentitiesTimingAndHistoryAndIsOneUndo() throws {
        var first = task("第一项", due: day(20, hour: 10))
        first.schedule.dueEndAt = day(20, hour: 12)
        first.schedule.deadlineAt = day(23, hour: 18)
        first.reminderAt = day(20, hour: 9)
        first.reminderOffsets = [-10]
        let child = task("跟随子任务", due: day(21, hour: 11), parent: first.id)
        let second = task("留在本周", due: day(22))
        let model = workspace([first, child, second])
        model.captureWeekPlan(weekOf: day(21))
        let before = model.allTasks
        XCTAssertEqual(model.planTasks([first.id], weekOf: day(26)), 1)
        let moved = try XCTUnwrap(model.task(for: first.id))
        XCTAssertEqual(model.allTasks.count, 3)
        XCTAssertEqual(moved.schedule.dueAt, day(27, hour: 10))
        XCTAssertEqual(moved.schedule.dueEndAt, day(27, hour: 12))
        XCTAssertEqual(moved.schedule.deadlineAt, first.schedule.deadlineAt)
        XCTAssertEqual(moved.reminderAt, day(27, hour: 9))
        XCTAssertEqual(moved.reminderOffsets, [-10])
        XCTAssertEqual(model.task(for: child.id)?.schedule.dueAt, day(28, hour: 11))
        XCTAssertEqual(model.task(for: child.id)?.parentID, first.id)
        XCTAssertEqual(projection.tasks(from: model.allTasks).map(\.id), [second.id])
        let entry = try XCTUnwrap(moved.weeklyPlanning?.history.first { $0.weekKey == "2026-10-19" })
        XCTAssertEqual(entry.schedule, first.schedule)
        XCTAssertEqual(entry.movedToWeek, "2026-10-26")
        let review = WeeklyReportBuilder(calendar: calendar).report(tasks: model.allTasks, weekOf: day(21))
        XCTAssertEqual(Set(review.planned.map(\.id)), [first.id, second.id])
        XCTAssertEqual(review.carried.map(\.id), [first.id])
        model.undo()
        XCTAssertEqual(model.allTasks, before)
        model.redo()
        XCTAssertEqual(model.task(for: first.id), moved)
    }

    func testInspectorRescheduleRecordsOldWeekAndClearingDateKeepsWeeklyPlan() throws {
        let source = task("安排评审", due: day(21, hour: 10))
        let model = workspace([source])
        var schedule = source.schedule
        schedule.dueAt = day(28, hour: 14)
        _ = model.setSchedule(source.id, schedule)
        let rescheduled = try XCTUnwrap(model.task(for: source.id))
        XCTAssertEqual(rescheduled.weeklyPlanning?.currentWeek, "2026-10-26")
        XCTAssertEqual(rescheduled.weeklyPlanning?.history.first?.schedule.dueAt, source.schedule.dueAt)
        XCTAssertEqual(rescheduled.weeklyPlanning?.history.first?.movedToWeek, "2026-10-26")
        _ = model.setSchedule(source.id, .init())
        let undated = try XCTUnwrap(model.task(for: source.id))
        XCTAssertNil(undated.schedule.dueAt)
        XCTAssertEqual(undated.weeklyPlanning?.currentWeek, "2026-10-26")
        XCTAssertTrue(WeeklyPlanProjection(weekStart: day(26), calendar: calendar).includes(undated))
        model.undo(); model.undo()
        XCTAssertEqual(model.task(for: source.id)?.schedule, source.schedule)
        XCTAssertNil(model.task(for: source.id)?.weeklyPlanning)
    }

    func testRecurringCompletionCreatesFreshWeekMembershipWithoutCopyingHistory() throws {
        var source = task("每周复盘", due: day(21, hour: 10))
        source.recurrence = .weekly
        let model = workspace([source])
        model.captureWeekPlan(weekOf: day(21))
        _ = model.complete(source.id)
        let next = try XCTUnwrap(model.allTasks.first { $0.id != source.id && !$0.isClosed })
        XCTAssertEqual(next.weeklyPlanning?.currentWeek, "2026-10-26")
        XCTAssertEqual(next.weeklyPlanning?.history.map(\.weekKey), ["2026-10-26"])
        XCTAssertEqual(projection.tasks(from: model.allTasks).map(\.id), [source.id])
    }

    func testChildProgressAndCompletedParentDoNotDoubleCountOutcomes() {
        let parent = task("交付项目", due: day(22))
        var child = task("完成接口", due: day(20), parent: parent.id)
        child.status = .completed; child.completedAt = day(20, hour: 18)
        let unfinished = task("联调", parent: parent.id)
        let builder = WeeklyReportBuilder(calendar: calendar)
        let first = builder.report(tasks: [parent, child, unfinished], weekOf: day(21))
        XCTAssertTrue(first.completed.isEmpty)
        XCTAssertEqual(first.planned.map(\.id), [parent.id])
        XCTAssertEqual(first.progress.first?.completedChildren.map(\.id), [child.id])
        XCTAssertEqual(first.progress.first?.totalChildren, 2)
        var doneParent = parent; doneParent.status = .completed; doneParent.completedAt = day(23, hour: 18)
        let second = builder.report(tasks: [doneParent, child, unfinished], weekOf: day(21))
        XCTAssertEqual(second.completed.map(\.id), [parent.id])
        XCTAssertTrue(second.progress.isEmpty)
    }

    func testRefreshingFactsKeepsReflectionAndOriginalTaskLinks() throws {
        let source = task("写交付文档", due: day(21))
        let builder = WeeklyReportBuilder(calendar: calendar)
        let report = builder.report(tasks: [source], weekOf: day(21))
        var document = builder.document(for: report)
        let index = try XCTUnwrap(document.blocks.firstIndex { $0.plainText == "本周复盘" })
        document.blocks[index + 1].runs = [DocumentRun(text: "评审应提前一天，已和团队约定。", marks: [.bold])]
        let regenerated = builder.document(for: report, preserving: document)
        XCTAssertTrue(regenerated.plainText.contains("评审应提前一天，已和团队约定。"))
        XCTAssertEqual(WeeklyReportBuilder.reflection(in: regenerated).first?.runs.first?.marks, [.bold])
        let links = regenerated.blocks.flatMap(\.runs).flatMap(\.marks)
        XCTAssertTrue(links.contains(.link(NativeResourceLink.task(source.id).url.absoluteString)))
        let legacy = NativeDocument(plainText: "我手写的旧总结")
        XCTAssertTrue(builder.document(for: report, preserving: legacy).plainText.contains(legacy.plainText))
    }

    func testWeekScopeAndFocusUseSameListAndNaturalWeek() {
        let work = task("工作", due: day(21))
        var personal = task("个人", due: day(21)); personal.list = TaskList(name: "个人")
        let records = [
            PomodoroRecord(id: UUID(), taskID: work.id, startedAt: day(19, hour: 9), minutes: 25, completed: true),
            PomodoroRecord(id: UUID(), taskID: personal.id, startedAt: day(21), minutes: 50, completed: true),
            PomodoroRecord(id: UUID(), taskID: work.id, startedAt: day(18, hour: 23), minutes: 10, completed: true)
        ]
        let report = WeeklyReportBuilder(calendar: calendar).report(tasks: [work, personal], weekOf: day(21),
            listName: "工作", focusRecords: records)
        XCTAssertEqual(report.pending.map(\.id), [work.id])
        XCTAssertEqual(report.focusSeconds, 25 * 60)
        let context = WeeklyPlanningContext(clock: { self.day(21) }, calendar: calendar)
        context.listName = "工作"; context.shift(1)
        XCTAssertEqual(context.weekKey, "2026-10-26")
        XCTAssertEqual(context.listName, "工作")
    }

    func testChangesAndAbandonmentRemainReviewableAndAIDraftKeepsSectionsEditable() {
        let source = task("评审方案", due: day(20), created: day(19, hour: 9))
        let model = workspace([source])
        model.captureWeekPlan(weekOf: day(21))
        _ = model.setSchedule(source.id, .init(dueAt: day(23)))
        let builder = WeeklyReportBuilder(calendar: calendar)
        let updated = builder.report(tasks: model.allTasks, weekOf: day(21))
        XCTAssertEqual(updated.added.map(\.id), [source.id])
        XCTAssertEqual(updated.rescheduled.map(\.id), [source.id])
        _ = model.abandon(source.id)
        let abandoned = builder.report(tasks: model.allTasks, weekOf: day(21))
        XCTAssertEqual(abandoned.abandoned.map(\.id), [source.id])
        XCTAssertTrue(abandoned.pending.isEmpty)
        let ai = WeeklyReportBuilder.aiDocument(text: "## 本周成果\n- 完成一项\n## 本周复盘\n下次提前评审\n## 下周重点\n- 推进交付", title: updated.title)
        XCTAssertEqual(WeeklyReportBuilder.reflection(in: ai).first?.plainText, "下次提前评审")
    }

    func testWeeklyPlanningSurvivesTaskSnapshotAndPortableExport() throws {
        let model = workspace()
        let id = try XCTUnwrap(model.createWeeklyTask(title: "周目标", list: "工作", weekOf: day(21)))
        _ = model.planTasks([id], weekOf: day(26))
        let source = try XCTUnwrap(model.task(for: id))
        let decoded = try JSONDecoder().decode(Task.self, from: JSONEncoder().encode(source))
        XCTAssertEqual(decoded.weeklyPlanning, source.weeklyPlanning)
        let snapshot = NativeWorkspaceSnapshot(tasks: [source], notes: [], taskLists: ["工作"])
        let data = try MigrationSnapshot.exportJSON(from: snapshot, attachmentDirectory: nil)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let taskRecord = try XCTUnwrap((object["tasks"] as? [[String: Any]])?.first)
        let planning = try XCTUnwrap(taskRecord["weeklyPlanning"])
        let imported = try JSONDecoder().decode(TaskWeeklyPlanning.self, from: JSONSerialization.data(withJSONObject: planning))
        XCTAssertEqual(imported, source.weeklyPlanning)
        let bundle = try MigrationSnapshot.parse(data)
        let result = MigrationSnapshot.merged(bundle,
            into: NativeWorkspaceSnapshot(tasks: [], notes: [], taskLists: []), attachmentNames: [])
        XCTAssertEqual(result.snapshot.tasks.first?.weeklyPlanning, source.weeklyPlanning)
    }
}
