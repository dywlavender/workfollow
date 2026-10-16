import XCTest
@testable import WorkFollow

@MainActor
final class TaskReplicaContractTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }
    private func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func repeatedTask(rule: RecurrenceRule? = nil) -> Task {
        var value = Task(id: UUID(), title: "需求评审", recurrence: .daily,
            recurrenceRule: rule, list: TaskList(name: "工作"), priority: .high,
            schedule: TaskSchedule(dueAt: date(13, 9), hasTime: true, dueEndAt: date(13, 10)),
            childOrder: 0, createdAt: date(13), updatedAt: date(13))
        value.sectionID = "doing"
        value.focusEstimate = TaskFocusEstimate(minutes: 50, pomodoros: nil)
        return value
    }
    private func workspace(_ task: Task) -> TaskWorkspaceModel {
        TaskWorkspaceModel(clock: { self.date(13, 12) }, calendar: calendar,
            seedDemoData: false, initialTasks: [task], initialLists: ["工作"])
    }
    private var window: DateInterval { DateInterval(start: date(13), end: date(18)) }

    func testNaturalNextWeekAndClockAgreeAcrossCaptureEntrypoints() throws {
        let model = TaskWorkspaceModel(clock: { self.date(13, 12) }, calendar: calendar, seedDemoData: false)
        let globalID = try XCTUnwrap(GlobalQuickAddComposer(workspace: model).submit(text: "下周一上午9点开会"))
        let listID = try XCTUnwrap(model.submitCapture(QuickCaptureSession(text: "下周一上午9点开会")).first)
        XCTAssertEqual(model.task(for: globalID)?.schedule.dueAt, date(19, 9))
        XCTAssertEqual(model.task(for: listID)?.schedule, model.task(for: globalID)?.schedule)
        let range = QuickAddParser.parse("明天9:00-10:00开会", now: date(13, 12), calendar: calendar, knownLists: [])
        XCTAssertEqual(range.dueAt, date(14, 9))
        XCTAssertTrue(range.title.contains("10:00"))
    }

    func testManualCaptureFieldsSurviveTitleReparseAndBatchHasOneHistoryStep() throws {
        let model = TaskWorkspaceModel(clock: { self.date(13, 12) }, calendar: calendar, seedDemoData: false)
        let capture = QuickCaptureSession(text: "明天开会\n后天复盘", description: "草稿描述",
            scheduleOverride: QuickAddScheduleDraft(dueAt: date(20, 11), hasTime: true),
            priorityOverride: .medium, listOverride: "收集箱", tagsOverride: ["工作"])
        let ids = model.submitCapture(capture)
        XCTAssertEqual(ids.count, 2)
        XCTAssertTrue(model.allTasks.allSatisfy { $0.schedule.dueAt == date(20, 11) && $0.priority == .medium && $0.tags == ["工作"] })
        model.undo()
        XCTAssertTrue(model.allTasks.isEmpty)
        model.redo()
        XCTAssertEqual(model.allTasks.map(\.id), ids)
    }

    func testCaretCandidateReplacementPreservesTitleSuffix() throws {
        let input = "开会 #工 稍后讨论"
        let marker = try XCTUnwrap(QuickAddComposition.markerQuery(in: input, selection: NSRange(location: 5, length: 0)))
        XCTAssertEqual(marker.query, "工")
        let result = QuickAddComposition.replacingMarker(in: input, selection: NSRange(location: 5, length: 0), with: "工作")
        XCTAssertEqual(result.text, "开会 #工作 稍后讨论")
        XCTAssertEqual(result.selection.location, 6)
    }

    func testBusinessRedoKeepsLaterTextAndOriginalTaskIdentities() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.date(13) }, calendar: calendar)
        let id = try XCTUnwrap(actions.create(title: "评审").taskID)
        store.clearUndo()
        _ = actions.setPriority(id, .high)
        _ = actions.setTitle(id, "修改后的评审")
        store.undo()
        XCTAssertEqual(store.task(id)?.title, "修改后的评审")
        XCTAssertEqual(store.task(id)?.priority, TaskPriority.none)
        _ = actions.setDocument(id, NativeDocument(plainText: "保留正文"))
        store.redo()
        XCTAssertEqual(store.task(id)?.id, id)
        XCTAssertEqual(store.task(id)?.title, "修改后的评审")
        XCTAssertEqual(store.task(id)?.document.plainText, "保留正文")
        XCTAssertEqual(store.task(id)?.priority, .high)
    }

    func testCalendarMovementPreservesDurationReminderAndSingleUndo() {
        var task = repeatedTask()
        task.recurrence = .never
        task.reminderAt = date(13, 9).addingTimeInterval(-300)
        let model = workspace(task)
        _ = model.moveSchedule(task.id, to: date(15, 11))
        XCTAssertEqual(model.task(for: task.id)?.schedule.dueEndAt, date(15, 12))
        XCTAssertEqual(model.task(for: task.id)?.reminderAt, date(15, 11).addingTimeInterval(-300))
        model.undo()
        XCTAssertEqual(model.task(for: task.id)?.schedule, task.schedule)
        XCTAssertEqual(model.task(for: task.id)?.reminderAt, task.reminderAt)
    }

    func testSameQuadrantDropLeavesDateAndHistoryUntouched() {
        var task = repeatedTask()
        task.recurrence = .never
        task.schedule.dueAt = date(14, 9)
        task.schedule.dueEndAt = date(14, 10)
        let model = workspace(task)
        _ = model.moveTaskToMatrix(task.id, .doNow)
        XCTAssertEqual(model.task(for: task.id)?.schedule, task.schedule)
        XCTAssertFalse(model.canUndo)
    }

    func testRecurringCompletionUndoRedoCarriesSectionEstimateAndChildren() throws {
        let parent = repeatedTask()
        let child = Task(id: UUID(), title: "准备议程", list: parent.list, priority: .none,
            schedule: TaskSchedule(), parentID: parent.id, childOrder: 0, createdAt: date(13), updatedAt: date(13))
        let model = TaskWorkspaceModel(clock: { self.date(13, 12) }, calendar: calendar,
            seedDemoData: false, initialTasks: [parent, child], initialLists: ["工作"])
        let nextID = try XCTUnwrap(model.complete(parent.id).taskID)
        let nextChildren = model.allTasks.filter { $0.parentID == nextID }.map(\.id)
        XCTAssertEqual(model.task(for: nextID)?.sectionID, "doing")
        XCTAssertEqual(model.task(for: nextID)?.focusEstimate, parent.focusEstimate)
        XCTAssertEqual(nextChildren.count, 1)
        model.undo()
        XCTAssertEqual(model.task(for: parent.id)?.status, .active)
        XCTAssertNil(model.task(for: nextID))
        model.redo()
        XCTAssertEqual(model.allTasks.filter { $0.parentID == nextID }.map(\.id), nextChildren)
    }

    func testFutureBrowseIsReadOnlyAndFirstEditMaterializesOnce() throws {
        let model = workspace(repeatedTask())
        let occurrences = TaskOccurrenceProjection.occurrences(tasks: model.allTasks, in: window, calendar: calendar)
        let future = try XCTUnwrap(occurrences.first { $0.key.ordinal == 2 })
        model.selectOccurrence(future)
        XCTAssertEqual(model.selectedTask?.id, future.task.id)
        XCTAssertEqual(model.allTasks.count, 1)
        XCTAssertFalse(model.canUndo)
        _ = model.setTitle(future.task.id, "本期评审")
        XCTAssertEqual(model.allTasks.count, 2)
        XCTAssertEqual(model.selectedTask?.id, future.task.id)
        _ = model.setPriority(future.task.id, .medium)
        XCTAssertEqual(model.allTasks.count, 2)
    }

    func testFutureTaskFocusResolvesDurableIDAndRecordRelationship() throws {
        let model = workspace(repeatedTask())
        let future = try XCTUnwrap(TaskOccurrenceProjection.occurrences(tasks: model.allTasks, in: window, calendar: calendar).first { $0.key.ordinal == 2 })
        model.selectOccurrence(future)
        let realID = try XCTUnwrap(model.resolveTaskForAction(future.task.id))
        XCTAssertTrue(model.allTasks.contains { $0.id == realID && $0.occurrenceKey == future.key })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = date(13, 12)
        let focus = FocusStore(clock: { now }, directory: directory)
        XCTAssertTrue(focus.start(taskID: realID, stopwatch: true))
        now = now.addingTimeInterval(90)
        let record = try XCTUnwrap(focus.finishEarly())
        XCTAssertEqual(record.taskID, realID)
        XCTAssertEqual(focus.recordsForTask(realID).first?.id, record.id)
        let decoded = try JSONDecoder().decode([Task].self, from: JSONEncoder().encode(model.allTasks))
        XCTAssertTrue(decoded.contains { $0.id == realID && $0.occurrenceKey == future.key })
    }

    func testOnlyThisMovePreservesNominalIdentityAndRemovesOriginalGhost() throws {
        let model = workspace(repeatedTask())
        let future = try XCTUnwrap(TaskOccurrenceProjection.occurrences(tasks: model.allTasks, in: window, calendar: calendar).first { $0.key.ordinal == 2 })
        let plan = SchedulePlan(schedule: TaskSchedule(dueAt: date(16, 11), hasTime: true, dueEndAt: date(16, 12)),
            reminder: nil, reminderOffsets: [], frequency: .daily, recurrenceRule: nil)
        _ = model.saveOccurrenceSchedule(plan, occurrence: future, scope: .onlyThis)
        let after = TaskOccurrenceProjection.occurrences(tasks: model.allTasks, in: window, calendar: calendar)
        XCTAssertEqual(after.filter { $0.key == future.key }.count, 1)
        XCTAssertEqual(after.first { $0.key == future.key }?.task.schedule.dueAt, date(16, 11))
        XCTAssertEqual(after.first { $0.key.ordinal == 3 }?.task.schedule.dueAt, date(16, 9))
        model.undo()
        XCTAssertEqual(model.allTasks.count, 1)
        model.redo()
        XCTAssertEqual(model.allTasks.count, 2)
    }

    func testThisAndFutureSplitsAtChosenPeriodAndKeepsPastDates() throws {
        let model = workspace(repeatedTask())
        let future = try XCTUnwrap(TaskOccurrenceProjection.occurrences(tasks: model.allTasks, in: window, calendar: calendar).first { $0.key.ordinal == 2 })
        let plan = SchedulePlan(schedule: TaskSchedule(dueAt: date(16, 11), hasTime: true, dueEndAt: date(16, 12)),
            reminder: nil, reminderOffsets: [], frequency: .daily, recurrenceRule: nil)
        _ = model.saveOccurrenceSchedule(plan, occurrence: future, scope: .thisAndFuture)
        let after = TaskOccurrenceProjection.occurrences(tasks: model.allTasks, in: window, calendar: calendar)
        XCTAssertEqual(after.filter { $0.key.seriesID == future.key.seriesID }.map { $0.task.schedule.dueAt! }, [date(13, 9), date(14, 9)])
        XCTAssertEqual(after.filter { $0.key.seriesID != future.key.seriesID }.map { $0.task.schedule.dueAt! }, [date(16, 11), date(17, 11)])
    }

    func testAllNotCompletedRetainsCompletedHistoryAndDoesNotResurrectPeriod() throws {
        let parent = repeatedTask()
        let model = workspace(parent)
        let nextID = try XCTUnwrap(model.complete(parent.id).taskID)
        let next = try XCTUnwrap(model.task(for: nextID))
        let plan = SchedulePlan(schedule: TaskSchedule(dueAt: date(15, 11), hasTime: true, dueEndAt: date(15, 12)),
            reminder: nil, reminderOffsets: [], frequency: .daily, recurrenceRule: nil)
        _ = model.saveOccurrenceSchedule(plan, occurrence: model.occurrence(for: next), scope: .allNotCompleted)
        XCTAssertEqual(model.task(for: parent.id)?.schedule, parent.schedule)
        XCTAssertEqual(model.task(for: parent.id)?.status, .completed)
        let after = TaskOccurrenceProjection.occurrences(tasks: model.allTasks, in: window, calendar: calendar)
        XCTAssertEqual(after.filter { $0.key.ordinal == 0 }.count, 1)
        XCTAssertEqual(after.filter { $0.key.ordinal == 0 }.first?.task.status, .completed)
        XCTAssertEqual(model.task(for: nextID)?.schedule.dueAt, date(15, 11))
    }

    func testRangeScheduleEditsPreserveIndependentContentOrganizationAndSingleUndoRedo() throws {
        for scope in [RecurrenceEditScope.thisAndFuture, .allNotCompleted] {
            var task = repeatedTask(rule: RecurrenceRule(remainingCount: 6))
            task.document = NativeDocument(plainText: "通用评审说明")
            task.tags = ["常规"]
            task.attachments = [NativeAttachment(id: UUID(), name: "议程.pdf", storedName: "agenda.pdf")]
            let store = WorkspaceStore()
            store.commit([task])
            let actions = TaskActions(store: store, clock: { self.date(13, 12) }, calendar: calendar)
            actions.hydrateOrganization()
            actions.hydrateSeries()
            let originalTemplate = try XCTUnwrap(store.task(task.id)?.series?.template)
            let projected = TaskOccurrenceProjection.occurrences(tasks: store.tasks,
                in: DateInterval(start: date(13), end: date(20)), calendar: calendar)
            for ordinal in [1, 2, 4] {
                let occurrence = try XCTUnwrap(projected.first { $0.key.ordinal == ordinal })
                let id = try XCTUnwrap(actions.materializeOccurrence(occurrence).taskID)
                _ = actions.setTitle(id, "第\(ordinal)期独立评审")
                _ = actions.setDocument(id, NativeDocument(plainText: "第\(ordinal)期的决议和待办"))
                _ = actions.setPriority(id, ordinal == 2 ? .medium : .none)
                _ = actions.moveToList(id, TaskList(name: "项目\(ordinal)"), sectionID: "section-\(ordinal)")
                _ = actions.setTags(id, ["阶段\(ordinal)"])
                _ = actions.setPinned(id, ordinal == 4)
                _ = actions.setFocusEstimate(id, TaskFocusEstimate(minutes: 20 + ordinal, pomodoros: nil))
                _ = actions.setSourceNote(id, UUID())
            }
            let before = store.tasks
            let selected = try XCTUnwrap(before.first { $0.occurrenceKey?.ordinal == 1 })
            let key = try XCTUnwrap(selected.occurrenceKey)
            let plan = SchedulePlan(schedule: TaskSchedule(dueAt: date(15, 11), hasTime: true,
                dueEndAt: date(15, 12)), reminder: date(15, 11).addingTimeInterval(-300),
                reminderOffsets: [-5], frequency: .daily, recurrenceRule: selected.recurrenceRule)
            store.clearUndo()

            XCTAssertEqual(actions.saveOccurrenceSchedule(plan,
                occurrence: TaskOccurrence(key: key, task: selected, isVirtual: false, sourceTaskID: selected.id),
                scope: scope).taskID, selected.id)

            XCTAssertEqual(store.tasks.count, before.count)
            for old in before {
                let edited = try XCTUnwrap(store.task(old.id))
                XCTAssertEqual(edited.title, old.title, scope.rawValue)
                XCTAssertEqual(edited.document, old.document, scope.rawValue)
                XCTAssertEqual(edited.priority, old.priority, scope.rawValue)
                XCTAssertEqual(edited.list, old.list, scope.rawValue)
                XCTAssertEqual(edited.listID, old.listID, scope.rawValue)
                XCTAssertEqual(edited.tags, old.tags, scope.rawValue)
                XCTAssertEqual(edited.tagReferences, old.tagReferences, scope.rawValue)
                XCTAssertEqual(edited.sectionID, old.sectionID, scope.rawValue)
                XCTAssertEqual(edited.isPinned, old.isPinned, scope.rawValue)
                XCTAssertEqual(edited.focusEstimate, old.focusEstimate, scope.rawValue)
                XCTAssertEqual(edited.sourceNoteID, old.sourceNoteID, scope.rawValue)
                XCTAssertEqual(edited.attachments, old.attachments, scope.rawValue)
                XCTAssertEqual(edited.createdAt, old.createdAt, scope.rawValue)
                if scope == .thisAndFuture && old.id == task.id {
                    XCTAssertEqual(edited.schedule, old.schedule)
                } else {
                    let start = try XCTUnwrap(old.schedule.dueAt).addingTimeInterval(26 * 3600)
                    XCTAssertEqual(edited.schedule.dueAt, start)
                    XCTAssertEqual(edited.schedule.dueEndAt, start.addingTimeInterval(3600))
                    XCTAssertEqual(edited.reminderAt, start.addingTimeInterval(-300))
                    XCTAssertEqual(edited.reminderOffsets, [-5])
                }
            }
            let editedSeriesID = try XCTUnwrap(store.task(selected.id)?.series?.id)
            let virtual = TaskOccurrenceProjection.occurrences(tasks: store.tasks,
                in: DateInterval(start: date(13), end: date(20)), calendar: calendar).filter {
                    $0.key.seriesID == editedSeriesID && $0.isVirtual
                }
            XCTAssertFalse(virtual.isEmpty, scope.rawValue)
            for occurrence in virtual {
                XCTAssertEqual(occurrence.task.title, originalTemplate.title, scope.rawValue)
                XCTAssertEqual(occurrence.task.document, originalTemplate.document, scope.rawValue)
                XCTAssertEqual(occurrence.task.priority, originalTemplate.priority, scope.rawValue)
                XCTAssertEqual(occurrence.task.listID, originalTemplate.listID, scope.rawValue)
                XCTAssertEqual(occurrence.task.tags, originalTemplate.tags, scope.rawValue)
                XCTAssertEqual(occurrence.task.tagReferences, originalTemplate.tagReferences, scope.rawValue)
                XCTAssertEqual(occurrence.task.sectionID, originalTemplate.sectionID, scope.rawValue)
            }
            let after = store.tasks
            store.undo()
            XCTAssertEqual(store.tasks, before, scope.rawValue)
            XCTAssertFalse(store.canUndo, scope.rawValue)
            store.redo()
            XCTAssertEqual(store.tasks, after, scope.rawValue)
            XCTAssertFalse(store.canRedo, scope.rawValue)
        }
    }

    func testShorteningRangeCountOrEndDateDetachesLaterStoredTasksWithoutMovingThem() throws {
        for scope in [RecurrenceEditScope.thisAndFuture, .allNotCompleted] {
            for rule in [RecurrenceRule(remainingCount: 2), RecurrenceRule(endDate: date(15))] {
                let store = WorkspaceStore()
                store.commit([repeatedTask(rule: RecurrenceRule(remainingCount: 6))])
                let actions = TaskActions(store: store, clock: { self.date(13, 12) }, calendar: calendar)
                actions.hydrateSeries()
                let projectionWindow = DateInterval(start: date(13), end: date(22))
                let projected = TaskOccurrenceProjection.occurrences(tasks: store.tasks,
                    in: projectionWindow, calendar: calendar)
                for occurrence in projected where occurrence.isVirtual {
                    let id = try XCTUnwrap(actions.materializeOccurrence(occurrence).taskID)
                    _ = actions.setTitle(id, "第\(occurrence.key.ordinal)期评审")
                    _ = actions.setDocument(id, NativeDocument(plainText: "第\(occurrence.key.ordinal)期独立记录"))
                }
                let before = store.tasks
                let selected = try XCTUnwrap(before.first { $0.occurrenceKey?.ordinal == 1 })
                let key = try XCTUnwrap(selected.occurrenceKey)
                let plan = SchedulePlan(schedule: TaskSchedule(dueAt: date(14, 11), hasTime: true,
                    dueEndAt: date(14, 12)), reminder: nil, reminderOffsets: [],
                    frequency: .daily, recurrenceRule: rule)
                store.clearUndo()

                _ = actions.saveOccurrenceSchedule(plan,
                    occurrence: TaskOccurrence(key: key, task: selected, isVirtual: false, sourceTaskID: selected.id),
                    scope: scope)

                XCTAssertEqual(store.tasks.count, before.count)
                for old in before {
                    let edited = try XCTUnwrap(store.task(old.id))
                    let ordinal = try XCTUnwrap(old.occurrenceKey?.ordinal)
                    XCTAssertEqual(edited.title, old.title, scope.rawValue)
                    XCTAssertEqual(edited.document, old.document, scope.rawValue)
                    if ordinal > 2 {
                        XCTAssertEqual(edited.schedule, old.schedule, scope.rawValue)
                        XCTAssertEqual(edited.reminderAt, old.reminderAt, scope.rawValue)
                        XCTAssertEqual(edited.reminderOffsets, old.reminderOffsets, scope.rawValue)
                        XCTAssertEqual(edited.recurrence, .never, scope.rawValue)
                        XCTAssertNil(edited.recurrenceRule)
                        XCTAssertNil(edited.series)
                        XCTAssertNil(edited.occurrenceKey)
                        XCTAssertNil(edited.occurrenceOverride)
                    } else if scope == .allNotCompleted || ordinal > 0 {
                        XCTAssertEqual(edited.schedule.dueAt, date(13 + ordinal, 11), scope.rawValue)
                        XCTAssertEqual(edited.schedule.dueEndAt, date(13 + ordinal, 12), scope.rawValue)
                        XCTAssertNotNil(edited.series)
                    } else {
                        XCTAssertEqual(edited.schedule, old.schedule)
                    }
                }
                let afterProjection = TaskOccurrenceProjection.occurrences(tasks: store.tasks,
                    in: projectionWindow, calendar: calendar)
                XCTAssertEqual(afterProjection.count, before.count)
                XCTAssertFalse(afterProjection.contains { $0.isVirtual })
                XCTAssertEqual(Set(store.tasks.compactMap { $0.schedule.dueAt }).count, before.count)
                let after = store.tasks
                store.undo()
                XCTAssertEqual(store.tasks, before)
                XCTAssertFalse(store.canUndo)
                store.redo()
                XCTAssertEqual(store.tasks, after)
            }
        }
    }

    func testDisablingRepeatInRangeKeepsOtherStoredOccurrencesAtTheirDates() throws {
        for scope in [RecurrenceEditScope.thisAndFuture, .allNotCompleted] {
            let store = WorkspaceStore()
            store.commit([repeatedTask(rule: RecurrenceRule(remainingCount: 5))])
            let actions = TaskActions(store: store, clock: { self.date(13, 12) }, calendar: calendar)
            actions.hydrateSeries()
            let projected = TaskOccurrenceProjection.occurrences(tasks: store.tasks, in: window, calendar: calendar)
            for occurrence in projected where occurrence.isVirtual {
                let id = try XCTUnwrap(actions.materializeOccurrence(occurrence).taskID)
                _ = actions.setDocument(id, NativeDocument(plainText: "第\(occurrence.key.ordinal)期的保留内容"))
            }
            let before = store.tasks
            let selected = try XCTUnwrap(before.first { $0.occurrenceKey?.ordinal == 1 })
            let key = try XCTUnwrap(selected.occurrenceKey)
            let plan = SchedulePlan(schedule: TaskSchedule(dueAt: date(14, 11), hasTime: true,
                dueEndAt: date(14, 12)), reminder: nil, reminderOffsets: [], frequency: .never, recurrenceRule: nil)
            store.clearUndo()

            _ = actions.saveOccurrenceSchedule(plan,
                occurrence: TaskOccurrence(key: key, task: selected, isVirtual: false, sourceTaskID: selected.id),
                scope: scope)

            XCTAssertEqual(store.tasks.count, before.count)
            for old in before {
                let edited = try XCTUnwrap(store.task(old.id))
                XCTAssertEqual(edited.title, old.title)
                XCTAssertEqual(edited.document, old.document)
                XCTAssertEqual(edited.schedule, old.id == selected.id ? plan.schedule : old.schedule)
                if scope == .allNotCompleted || old.occurrenceKey?.ordinal != 0 {
                    XCTAssertEqual(edited.recurrence, .never)
                    XCTAssertNil(edited.recurrenceRule)
                    XCTAssertNil(edited.series)
                    XCTAssertNil(edited.occurrenceKey)
                    XCTAssertNil(edited.occurrenceOverride)
                }
            }
            XCTAssertFalse(TaskOccurrenceProjection.occurrences(tasks: store.tasks,
                in: window, calendar: calendar).contains { $0.isVirtual })
            XCTAssertEqual(Set(store.tasks.compactMap { $0.schedule.dueAt }).count, before.count)
            let after = store.tasks
            store.undo()
            XCTAssertEqual(store.tasks, before)
            XCTAssertFalse(store.canUndo)
            store.redo()
            XCTAssertEqual(store.tasks, after)
        }
    }

    func testRangeScheduleEditsRetainExcludedPeriodsAndCompletionSkipsThem() throws {
        for scope in [RecurrenceEditScope.thisAndFuture, .allNotCompleted] {
            let task = repeatedTask(rule: RecurrenceRule(remainingCount: 9))
            let store = WorkspaceStore()
            store.commit([task])
            let actions = TaskActions(store: store, clock: { self.date(13, 12) }, calendar: calendar)
            actions.hydrateOrganization()
            actions.hydrateSeries()
            let projectionWindow = DateInterval(start: date(13), end: date(24))
            let projected = TaskOccurrenceProjection.occurrences(tasks: store.tasks,
                in: projectionWindow, calendar: calendar)
            var ids = [0: task.id]
            for ordinal in 1...7 {
                let occurrence = try XCTUnwrap(projected.first { $0.key.ordinal == ordinal })
                ids[ordinal] = try XCTUnwrap(actions.materializeOccurrence(occurrence).taskID)
            }
            _ = actions.complete(try XCTUnwrap(ids[0]))
            _ = actions.delete(try XCTUnwrap(ids[2]))
            _ = actions.skipOccurrence(try XCTUnwrap(ids[3]))
            _ = actions.convertToNote(try XCTUnwrap(ids[4]), noteID: UUID(), undoNote: {})
            _ = actions.abandon(try XCTUnwrap(ids[5]))
            _ = actions.complete(try XCTUnwrap(ids[6]))
            let before = store.tasks
            let excluded = before.filter { !$0.isActiveSeriesOccurrence }
            XCTAssertEqual(excluded.count, 6)
            let selected = try XCTUnwrap(store.task(try XCTUnwrap(ids[1])))
            let key = try XCTUnwrap(selected.occurrenceKey)
            let plan = SchedulePlan(schedule: TaskSchedule(dueAt: date(15, 11), hasTime: true,
                dueEndAt: date(15, 12)), reminder: nil, reminderOffsets: [],
                frequency: .daily, recurrenceRule: selected.recurrenceRule)
            store.clearUndo()

            _ = actions.saveOccurrenceSchedule(plan,
                occurrence: TaskOccurrence(key: key, task: selected, isVirtual: false, sourceTaskID: selected.id),
                scope: scope)

            for old in excluded { XCTAssertEqual(store.task(old.id), old, scope.rawValue) }
            let changed = try XCTUnwrap(store.task(selected.id)?.series)
            let excludedOrdinals = scope == .thisAndFuture ? [1, 2, 3, 4, 5] : [0, 2, 3, 4, 5, 6]
            XCTAssertEqual(changed.excludedOrdinals, excludedOrdinals)
            let after = store.tasks
            let restored = try JSONDecoder().decode([Task].self, from: JSONEncoder().encode(after))
            XCTAssertEqual(restored, after)
            let afterProjection = TaskOccurrenceProjection.occurrences(tasks: restored,
                in: projectionWindow, calendar: calendar)
            XCTAssertFalse(afterProjection.contains {
                $0.isVirtual && $0.key.seriesID == changed.id && excludedOrdinals.contains($0.key.ordinal)
            }, scope.rawValue)
            for ordinal in [2, 3, 4] {
                let hiddenID = try XCTUnwrap(ids[ordinal])
                XCTAssertFalse(afterProjection.contains { $0.task.id == hiddenID }, scope.rawValue)
            }
            store.undo()
            XCTAssertEqual(store.tasks, before, scope.rawValue)
            XCTAssertFalse(store.canUndo, scope.rawValue)
            store.redo()
            XCTAssertEqual(store.tasks, after, scope.rawValue)

            XCTAssertEqual(actions.complete(selected.id).taskID, ids[7], scope.rawValue)
            XCTAssertEqual(store.tasks.count, after.count, scope.rawValue)
            for old in excluded { XCTAssertEqual(store.task(old.id), old, scope.rawValue) }
        }
    }

    func testCompletionAfterRangeEditDoesNotRecreateSubsequentlyDeletedNextOccurrence() throws {
        for scope in [RecurrenceEditScope.thisAndFuture, .allNotCompleted] {
            let store = WorkspaceStore()
            store.commit([repeatedTask(rule: RecurrenceRule(remainingCount: 6))])
            let actions = TaskActions(store: store, clock: { self.date(13, 12) }, calendar: calendar)
            actions.hydrateSeries()
            let future = try XCTUnwrap(TaskOccurrenceProjection.occurrences(tasks: store.tasks,
                in: window, calendar: calendar).first { $0.key.ordinal == 1 })
            let plan = SchedulePlan(schedule: TaskSchedule(dueAt: date(15, 11), hasTime: true,
                dueEndAt: date(15, 12)), reminder: nil, reminderOffsets: [],
                frequency: .daily, recurrenceRule: future.task.recurrenceRule)
            let currentID = try XCTUnwrap(actions.saveOccurrenceSchedule(plan, occurrence: future, scope: scope).taskID)
            let current = try XCTUnwrap(store.task(currentID))
            let currentKey = try XCTUnwrap(current.occurrenceKey)
            let next = try XCTUnwrap(TaskOccurrenceProjection.occurrences(tasks: store.tasks,
                in: window, calendar: calendar).first {
                    $0.key.seriesID == currentKey.seriesID && $0.key.ordinal == currentKey.ordinal + 1
                })
            let deletedID = try XCTUnwrap(actions.materializeOccurrence(next).taskID)
            _ = actions.delete(deletedID)
            let deleted = try XCTUnwrap(store.task(deletedID))
            XCTAssertNotNil(deleted.deletedAt)
            XCTAssertFalse(current.series?.excludedOrdinals?.contains(next.key.ordinal) ?? false)
            let beforeCompletion = store.tasks
            store.clearUndo()

            let followingID = try XCTUnwrap(actions.complete(currentID).taskID)

            let following = try XCTUnwrap(store.task(followingID))
            XCTAssertEqual(following.occurrenceKey?.seriesID, currentKey.seriesID, scope.rawValue)
            XCTAssertEqual(following.occurrenceKey?.ordinal, currentKey.ordinal + 2, scope.rawValue)
            XCTAssertEqual(following.schedule.dueAt, date(17, 11), scope.rawValue)
            XCTAssertEqual(store.task(deletedID), deleted, scope.rawValue)
            XCTAssertEqual(store.tasks.filter { $0.occurrenceKey == next.key }.count, 1, scope.rawValue)
            XCTAssertFalse(TaskOccurrenceProjection.occurrences(tasks: store.tasks,
                in: window, calendar: calendar).contains { $0.key == next.key }, scope.rawValue)
            let afterCompletion = store.tasks
            store.undo()
            XCTAssertEqual(store.tasks, beforeCompletion, scope.rawValue)
            XCTAssertFalse(store.canUndo, scope.rawValue)
            store.redo()
            XCTAssertEqual(store.tasks, afterCompletion, scope.rawValue)
        }
    }

    func testConvertedRecurringTaskDoesNotProjectNewOccurrences() throws {
        let store = WorkspaceStore()
        let task = repeatedTask()
        store.commit([task])
        let actions = TaskActions(store: store, clock: { self.date(13, 12) }, calendar: calendar)
        actions.hydrateSeries()
        store.clearUndo()
        let noteID = UUID()
        var noteExists = true
        _ = actions.convertToNote(task.id, noteID: noteID,
            undoNote: { noteExists = false }, redoNote: { noteExists = true })
        let converted = store.tasks
        XCTAssertEqual(store.task(task.id)?.convertedNoteID, noteID)
        XCTAssertTrue(noteExists)
        XCTAssertTrue(TaskOccurrenceProjection.occurrences(tasks: store.tasks, in: window, calendar: calendar).isEmpty)
        store.undo()
        XCTAssertFalse(noteExists)
        XCTAssertNil(store.task(task.id)?.convertedNoteID)
        XCTAssertTrue(store.canRedo)
        XCTAssertEqual(TaskOccurrenceProjection.occurrences(tasks: store.tasks, in: window, calendar: calendar).count, 5)
        store.redo()
        XCTAssertTrue(noteExists)
        XCTAssertEqual(store.tasks, converted)
        XCTAssertTrue(TaskOccurrenceProjection.occurrences(tasks: store.tasks, in: window, calendar: calendar).isEmpty)
    }

    func testCompletionDateBaseHasNoSpeculativeFutureAndUsesCompletionDay() throws {
        let store = WorkspaceStore()
        let task = repeatedTask(rule: RecurrenceRule(base: .completionDate))
        store.commit([task]); store.clearUndo()
        let actions = TaskActions(store: store, clock: { self.date(16, 12) }, calendar: calendar)
        actions.hydrateSeries()
        XCTAssertEqual(TaskOccurrenceProjection.occurrences(tasks: store.tasks, in: window, calendar: calendar).count, 1)
        let nextID = try XCTUnwrap(actions.complete(task.id).taskID)
        XCTAssertEqual(store.task(nextID)?.schedule.dueAt, date(17, 9))
    }

    func testWeekdaysOrdinalAndSelectedDatesUseOneEngine() throws {
        let weekly = RecurrenceRule(weekdays: [2, 4, 6])
        XCTAssertEqual(weekly.nextOccurrence(after: date(14, 9), frequency: .weekly, calendar: calendar), date(16, 9))
        let lastMonday = RecurrenceRule(weekday: 2, monthlyOrdinal: -1)
        XCTAssertEqual(lastMonday.nextOccurrence(after: date(13, 9), frequency: .monthly, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 9)))
        let selected = RecurrenceRule(base: .selectedDates, selectedDates: [date(13), date(20), date(28)])
        XCTAssertEqual(selected.nextOccurrence(after: date(13, 9), frequency: .daily, calendar: calendar), date(20, 9))
    }

    func testOrganizationRenameUndoRedoKeepsFilterResultsAndViewPreferences() throws {
        var task = repeatedTask(); task.recurrence = .never; task.tags = ["项目"]
        let model = workspace(task)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let filters = FilterStore(directory: directory)
        model.attachFilterStore(filters)
        XCTAssertTrue(filters.add(SavedFilter(name: "项目任务", listNames: ["工作"], tags: ["项目"])))
        let preference = TaskViewPreferenceStore(directory: directory)
        preference.setViewMode(.kanban, for: "list:工作")
        let original = try XCTUnwrap(model.task(for: task.id))
        XCTAssertTrue(model.saveList("交付", replacing: "工作"))
        XCTAssertEqual(model.task(for: task.id)?.listID, original.listID)
        XCTAssertEqual(filters.filters.first?.listNames, ["交付"])
        XCTAssertTrue(FilterEvaluator.matches(model.task(for: task.id)!, filter: filters.filters[0], now: date(13), calendar: calendar))
        XCTAssertEqual(preference.viewMode(for: "list:交付"), .kanban)
        model.undo()
        XCTAssertEqual(filters.filters.first?.listNames, ["工作"])
        XCTAssertEqual(preference.viewMode(for: "list:工作"), .kanban)
        model.redo()
        XCTAssertEqual(filters.filters.first?.listNames, ["交付"])
        model.renameTag("项目", to: "交付项目")
        XCTAssertEqual(model.task(for: task.id)?.tagReferences?.first?.id, original.tagReferences?.first?.id)
        XCTAssertEqual(filters.filters.first?.tags, ["交付项目"])
    }

    func testDateDraftKeepsNewRuleFieldsAndLegacyTaskStillDecodes() throws {
        let rule = RecurrenceRule(weekdays: [2, 4, 6], base: .dueDate, monthlyOrdinal: -1)
        let task = repeatedTask(rule: rule)
        let draft = TaskDateDraftModel(task: task, calendar: calendar, now: { self.date(13) }, deadline: false)
        draft.chooseInterval(2)
        XCTAssertEqual(draft.draftRule?.weekdays, [2, 4, 6])
        XCTAssertEqual(draft.draftRule?.monthlyOrdinal, -1)
        let data = try JSONEncoder().encode(task)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for field in ["series", "occurrenceKey", "occurrenceOverride", "focusEstimate", "listID", "tagReferences"] { json.removeValue(forKey: field) }
        let old = try JSONDecoder().decode(Task.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.id, task.id)
        XCTAssertNil(old.focusEstimate)
        XCTAssertNil(old.series)
    }
}
