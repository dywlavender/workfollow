import EventKit
import XCTest
@testable import WorkFollow

@MainActor
final class SystemRemindersIntegrationTests: XCTestCase {
    private var now: Date { Date(timeIntervalSince1970: 1_792_300_000) }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 28800)!; return value
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("system-reminders-test-" + UUID().uuidString) }
    private func task(scheduled: Bool = true) -> Task {
        var value = Task(id: UUID(), title: "准备会议", list: .inbox, priority: .medium,
            schedule: scheduled ? .init(dueAt: now.addingTimeInterval(3600), hasTime: true, deadlineAt: now.addingTimeInterval(86400)) : .init(),
            childOrder: 0, createdAt: now, updatedAt: now)
        if scheduled { value.reminderOffsets = [-10, 0] }
        return value
    }
    private func coordinator(_ folder: URL, _ client: FakeSystemRemindersClient) -> RemindersSyncCoordinator {
        let value = RemindersSyncCoordinator(directory: folder, client: client, clock: { self.now }, calendar: calendar)
        value.store.configure { $0.enabled = true; $0.targetListID = "icloud-workfollow"; $0.autoSyncLists = [RemindersIntegrationSnapshot.allTasksScope] }
        return value
    }
    private func sync(_ value: RemindersSyncCoordinator, _ tasks: [Task]) async {
        value.requestSync(tasks: tasks, activeLists: [TaskList.inbox.name]); await value.waitForSync()
    }
    private func attach(_ value: RemindersSyncCoordinator, _ workspace: TaskWorkspaceModel) {
        value.applyExternal = { reference, fields, expected in
            guard let occurrence = CalendarTaskReference.resolve(reference, tasks: workspace.allTasks, calendar: self.calendar),
                  ReminderTaskMapping.fields(occurrence.task, calendar: self.calendar) == expected else { return false }
            return workspace.applyRemindersEdit(occurrence, fields: fields).taskID != nil
        }
    }

    func testConnectCreatesOneDedicatedListAndAutomaticallyIncludesNewLists() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemRemindersClient(); client.availableLists = []
        let value = RemindersSyncCoordinator(directory: folder, client: client)
        await value.connect(); await value.connect()
        XCTAssertEqual(client.createdLists.count, 1)
        XCTAssertEqual(client.createdLists.first?.accountID, "icloud")
        XCTAssertEqual(client.createdLists.first?.title, "WorkFollow")
        XCTAssertEqual(value.store.snapshot.targetListID, client.createdLists.first?.id)
        XCTAssertTrue(value.store.snapshot.enabled)
        XCTAssertTrue(value.store.snapshot.syncsAllTasks)
        XCTAssertTrue(value.store.snapshot.taskOverrides.isEmpty)
        XCTAssertTrue(value.store.snapshot.bidirectional)
        XCTAssertTrue(value.store.snapshot.useSystemAlerts)
        XCTAssertFalse(value.connecting)
        XCTAssertNil(value.message)
        let first = task(); var second = task(scheduled: false); second.list = TaskList(name: "工作")
        value.requestSync(tasks: [first, second], activeLists: [TaskList.inbox.name, "工作"])
        await value.waitForSync()
        XCTAssertEqual(client.values.count, 2)
        var third = task(scheduled: false); third.list = TaskList(name: "新建清单")
        value.requestSync(tasks: [first, second, third], activeLists: [TaskList.inbox.name, "工作", "新建清单"])
        await value.waitForSync()
        XCTAssertEqual(client.values.count, 3)
    }

    func testConnectReusesExistingDedicatedList() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemRemindersClient()
        let value = RemindersSyncCoordinator(directory: folder, client: client)
        await value.connect()
        XCTAssertEqual(value.store.snapshot.targetListID, "icloud-workfollow")
        XCTAssertTrue(client.createdLists.isEmpty)
    }

    func testEnableUsesDedicatedListAndFixedSyncDefaults() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemRemindersClient()
        client.availableLists.append(.init(id: "chosen-list", title: "我的任务", accountID: "icloud", accountTitle: "iCloud", writable: true))
        let value = RemindersSyncCoordinator(directory: folder, client: client)
        value.store.configure {
            $0.targetListID = "chosen-list"; $0.autoSyncLists = [TaskList.inbox.name]
            $0.bidirectional = false; $0.useSystemAlerts = false
        }
        await value.connect()
        XCTAssertEqual(value.store.snapshot.targetListID, "icloud-workfollow")
        XCTAssertTrue(value.store.snapshot.syncsAllTasks)
        XCTAssertTrue(value.store.snapshot.bidirectional)
        XCTAssertTrue(value.store.snapshot.useSystemAlerts)
        XCTAssertTrue(client.createdLists.isEmpty)
    }

    func testPreviousSelectiveSetupPausesWithoutRemovingExistingReminders() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemRemindersClient(); let value = coordinator(folder, client)
        let source = task(); await sync(value, [source])
        value.store.configure { $0.autoSyncLists = [TaskList.inbox.name] }
        await withCheckedContinuation { continuation in value.flush { _ in continuation.resume() } }
        let restored = RemindersSyncCoordinator(directory: folder, client: client)
        XCTAssertFalse(restored.store.snapshot.enabled)
        XCTAssertEqual(restored.store.snapshot.bindings.count, 1)
        await sync(restored, [source])
        XCTAssertEqual(client.values.count, 1)
        await restored.connect(); await sync(restored, [source])
        XCTAssertTrue(restored.store.snapshot.enabled)
        XCTAssertTrue(restored.store.snapshot.syncsAllTasks)
        XCTAssertEqual(client.values.count, 1)
    }

    func testConnectWithoutICloudExplainsSetupAndDoesNotCreateLocalList() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemRemindersClient()
        client.availableAccounts = [.init(id: "local", title: "我的 Mac")]
        client.availableLists = [.init(id: "local-list", title: "WorkFollow", accountID: "local", accountTitle: "我的 Mac", writable: true)]
        let value = RemindersSyncCoordinator(directory: folder, client: client)
        await value.connect()
        XCTAssertFalse(value.store.snapshot.enabled)
        XCTAssertNil(value.store.snapshot.targetListID)
        XCTAssertTrue(client.createdLists.isEmpty)
        XCTAssertTrue(value.message?.contains("iCloud") == true)
    }

    func testScheduledAndUndatedTasksKeepDatesAndMultipleAlarmsSeparate() {
        let source = task()
        let fields = ReminderTaskMapping.fields(source, calendar: calendar)
        XCTAssertEqual(fields.due, source.schedule.dueAt)
        XCTAssertEqual(fields.alarms, [now.addingTimeInterval(3000), now.addingTimeInterval(3600)])
        XCTAssertEqual(ReminderTaskMapping.reminderValues(fields, calendar: calendar).offsets, [-10, 0])
        let undated = ReminderTaskMapping.fields(task(scheduled: false), calendar: calendar)
        XCTAssertNil(undated.due); XCTAssertFalse(undated.hasTime); XCTAssertTrue(undated.alarms.isEmpty)
        var allDay = source; allDay.schedule.hasTime = false; allDay.reminderOffsets = [0]
        let day = ReminderTaskMapping.fields(allDay, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: day.alarms[0]), 9)
        XCTAssertEqual(calendar.component(.hour, from: day.due!), 0)
    }

    func testCreateRescheduleChangeAlarmAndUnchangedSyncKeepOneItem() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemRemindersClient(); let value = coordinator(folder, client); var source = task()
        await sync(value, [source]); let id = try XCTUnwrap(client.values.first?.key)
        XCTAssertEqual(client.values.count, 1); XCTAssertTrue(value.handlesAlerts(for: source))
        let writes = client.writes; await sync(value, [source]); XCTAssertEqual(client.writes, writes)
        source.schedule.dueAt!.addTimeInterval(3600); source.reminderOffsets = [-30]
        XCTAssertFalse(value.handlesAlerts(for: source), "新提醒写入成功前保留本地提醒")
        XCTAssertEqual(value.status(for: source), "等待写入提醒事项")
        await sync(value, [source])
        XCTAssertEqual(client.values.count, 1)
        XCTAssertEqual(client.values[id]?.fields.alarms, [now.addingTimeInterval(5400)])
        XCTAssertEqual(client.values[id]?.fields.due, source.schedule.dueAt)
        XCTAssertEqual(client.values[id]?.fields.priority, .medium)
    }

    func testUndatedTaskCompletesReopensDeletesAndRestores() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemRemindersClient(); let value = coordinator(folder, client); var source = task(scheduled: false)
        await sync(value, [source]); let id = try XCTUnwrap(client.values.first?.key)
        source.status = .completed; await sync(value, [source]); XCTAssertEqual(client.values[id]?.fields.completed, true)
        source.status = .active; await sync(value, [source]); XCTAssertEqual(client.values[id]?.fields.completed, false)
        source.deletedAt = now; await sync(value, [source]); XCTAssertTrue(client.values.isEmpty)
        source.deletedAt = nil; await sync(value, [source]); XCTAssertEqual(client.values.count, 1)
    }

    func testPhoneEditsUseOneUndoAndPreserveIndependentDeadline() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = task(); let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, initialTasks: [source])
        let client = FakeSystemRemindersClient(); let value = coordinator(folder, client); attach(value, workspace)
        await sync(value, workspace.allTasks)
        let id = try XCTUnwrap(client.values.first?.key)
        client.values[id]!.fields.title = "手机修改标题"
        client.values[id]!.fields.due = now.addingTimeInterval(7200)
        client.values[id]!.fields.alarms = [now.addingTimeInterval(6300)]
        client.values[id]!.fields.priority = .high
        await sync(value, workspace.allTasks)
        let changed = try XCTUnwrap(workspace.task(for: source.id))
        XCTAssertEqual(changed.title, "手机修改标题"); XCTAssertEqual(changed.priority, .high)
        XCTAssertEqual(changed.reminderOffsets, [-15]); XCTAssertEqual(changed.schedule.dueAt, now.addingTimeInterval(7200))
        XCTAssertEqual(changed.schedule.deadlineAt, source.schedule.deadlineAt)
        workspace.undo(); await sync(value, workspace.allTasks)
        XCTAssertEqual(workspace.task(for: source.id)?.title, source.title)
        XCTAssertEqual(client.values[id]?.fields, ReminderTaskMapping.fields(source, calendar: calendar))
    }

    func testPhoneCompletionUsesActualDateAcrossWeekBoundaryAndDoesNotRepeatWrites() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = task()
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, initialTasks: [source])
        let client = FakeSystemRemindersClient(); let value = coordinator(folder, client); attach(value, workspace)
        await sync(value, workspace.allTasks)
        let id = try XCTUnwrap(client.values.first?.key)
        let thisWeek = SummaryReviewBuilder.weekStart(of: now, calendar: calendar)
        let phoneCompletion = thisWeek.addingTimeInterval(-3600)
        client.values[id]!.fields.completed = true
        client.values[id]!.fields.completedAt = phoneCompletion
        await sync(value, workspace.allTasks)
        XCTAssertEqual(workspace.task(for: source.id)?.completedAt, phoneCompletion)
        XCTAssertEqual(workspace.task(for: source.id)?.updatedAt, now)
        let builder = WeeklyReportBuilder(calendar: calendar)
        XCTAssertTrue(builder.report(tasks: workspace.allTasks, weekOf: now).completed.isEmpty)
        XCTAssertEqual(builder.report(tasks: workspace.allTasks, weekOf: phoneCompletion).completed.map(\.id), [source.id])
        let writes = client.writes
        await sync(value, workspace.allTasks)
        XCTAssertEqual(client.writes, writes)
        XCTAssertTrue(value.conflicts.isEmpty)
    }

    func testWeeklyCarryUpdatesSameReminderAndUndoRestoresAlarm() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = task()
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, initialTasks: [source])
        let client = FakeSystemRemindersClient(); let value = coordinator(folder, client); attach(value, workspace)
        await sync(value, workspace.allTasks)
        let binding = try XCTUnwrap(value.store.snapshot.bindings.first)
        let week = SummaryReviewBuilder.weekStart(of: source.schedule.dueAt!, calendar: calendar)
        let next = calendar.date(byAdding: .day, value: 7, to: week)!
        XCTAssertEqual(workspace.planTasks([source.id], weekOf: next), 1)
        await sync(value, workspace.allTasks)
        XCTAssertEqual(client.values.count, 1)
        XCTAssertEqual(value.store.snapshot.bindings.first?.reminderID, binding.reminderID)
        XCTAssertEqual(workspace.task(for: source.id)?.schedule.deadlineAt, source.schedule.deadlineAt)
        XCTAssertEqual(client.values[binding.reminderID]?.fields.due, source.schedule.dueAt?.addingTimeInterval(7 * 86400))
        XCTAssertEqual(client.values[binding.reminderID]?.fields.alarms,
            ReminderTaskMapping.fields(source, calendar: calendar).alarms.map { $0.addingTimeInterval(7 * 86400) })
        workspace.undo()
        await sync(value, workspace.allTasks)
        XCTAssertEqual(client.values.count, 1)
        XCTAssertEqual(client.values[binding.reminderID]?.fields, ReminderTaskMapping.fields(source, calendar: calendar))
    }

    func testPhoneCompletionAndUncompletionReturnToWorkspace() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = task(); let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, initialTasks: [source])
        let client = FakeSystemRemindersClient(); let value = coordinator(folder, client); attach(value, workspace)
        await sync(value, workspace.allTasks); let id = try XCTUnwrap(client.values.first?.key)
        client.values[id]!.fields.completed = true
        await sync(value, workspace.allTasks); XCTAssertEqual(workspace.task(for: source.id)?.status, .completed)
        client.values[id]!.fields.completed = false
        await sync(value, workspace.allTasks); XCTAssertEqual(workspace.task(for: source.id)?.status, .active)
    }

    func testIndependentChangesMergeAndSameFieldConflictNeedsChoice() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = task(); let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, initialTasks: [source])
        let client = FakeSystemRemindersClient(); let value = coordinator(folder, client); attach(value, workspace)
        await sync(value, workspace.allTasks); let id = try XCTUnwrap(client.values.first?.key)
        _ = workspace.setPriority(source.id, .high); client.values[id]!.fields.title = "手机标题"
        await sync(value, workspace.allTasks)
        XCTAssertTrue(value.conflicts.isEmpty); XCTAssertEqual(workspace.task(for: source.id)?.title, "手机标题")
        XCTAssertEqual(client.values[id]?.fields.priority, .high)
        _ = workspace.setTitle(source.id, "电脑标题"); client.values[id]!.fields.title = "手机另一标题"
        await sync(value, workspace.allTasks)
        let conflict = try XCTUnwrap(value.conflicts.first)
        XCTAssertEqual(value.presentationStatus, .needsAttention(1))
        XCTAssertEqual(workspace.task(for: source.id)?.title, "电脑标题")
        value.resolve(conflict, useReminder: true); await sync(value, workspace.allTasks)
        XCTAssertEqual(workspace.task(for: source.id)?.title, "手机另一标题"); XCTAssertTrue(value.conflicts.isEmpty)
    }

    func testRestartRepairsChangedSystemIdentifierWithoutDuplicate() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemRemindersClient(); let value = coordinator(folder, client); let source = task()
        await sync(value, [source])
        await withCheckedContinuation { continuation in value.flush { _ in continuation.resume() } }
        var existing = try XCTUnwrap(client.values.values.first); client.values.removeAll(); existing.id = "refreshed-id"; client.values[existing.id] = existing
        let restored = RemindersSyncCoordinator(directory: folder, client: client, clock: { self.now }, calendar: calendar)
        await sync(restored, [source])
        XCTAssertEqual(client.values.count, 1); XCTAssertEqual(restored.store.snapshot.bindings.first?.reminderID, existing.id)
    }

    func testPhoneDeletionDetachesAndUserCanReconnect() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemRemindersClient(); let value = coordinator(folder, client); let source = task()
        await sync(value, [source]); client.values.removeAll()
        await sync(value, [source]); await sync(value, [source])
        XCTAssertTrue(client.values.isEmpty); XCTAssertEqual(value.store.snapshot.bindings.first?.detached, true)
        XCTAssertFalse(value.handlesAlerts(for: source)); XCTAssertTrue(value.status(for: source).contains("重新关联"))
        value.reconnect(source); await sync(value, [source]); XCTAssertEqual(client.values.count, 1)
    }

    func testUnlinkCanRemoveCopyOrKeepCopyWithoutFurtherWrites() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemRemindersClient(); let value = coordinator(folder, client); var source = task()
        await sync(value, [source]); let id = try XCTUnwrap(client.values.first?.key)
        value.unlinkKeepingCopy(source); await sync(value, [source]); source.title = "不再同步"
        await sync(value, [source]); XCTAssertEqual(client.values[id]?.fields.title, "准备会议")
        value.store.setTask(source, enabled: true); await sync(value, [source]); XCTAssertEqual(client.values[id]?.fields.title, source.title)
        value.store.setTask(source, enabled: false); await sync(value, [source]); XCTAssertTrue(client.values.isEmpty)
    }

    func testNoAccessOrDisabledIntegrationDoesNotWrite() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemRemindersClient(); let value = coordinator(folder, client); let source = task()
        client.authorization = .denied; await sync(value, [source]); XCTAssertTrue(client.values.isEmpty)
        XCTAssertEqual(value.presentationStatus, .needsAccess)
        client.authorization = .fullAccess; value.store.configure { $0.enabled = false }
        await sync(value, [source]); XCTAssertTrue(client.values.isEmpty); XCTAssertFalse(value.handlesAlerts(for: source))
        XCTAssertEqual(value.presentationStatus, .off)
    }

    func testFailedWriteRetriesWithoutReportingSuccessOrSuppressingLocalReminder() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let client = FakeSystemRemindersClient(); let value = coordinator(folder, client); let source = task()
        client.failNextSave = true
        await sync(value, [source])
        XCTAssertNotNil(value.message); XCTAssertTrue(value.store.snapshot.bindings.isEmpty)
        XCTAssertEqual(value.presentationStatus, .needsAttention(1))
        XCTAssertFalse(value.handlesAlerts(for: source))
        await sync(value, [source])
        XCTAssertNil(value.message); XCTAssertEqual(client.values.count, 1); XCTAssertTrue(value.handlesAlerts(for: source))
        XCTAssertEqual(value.presentationStatus, .ready)
        XCTAssertEqual(value.presentationStatus.title, "已写入 Apple 提醒事项")
    }

    func testRepeatingOccurrencesPrepopulateAndPhoneCompletionMaterializesOnlyOnce() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        var source = task(); source.recurrence = .daily
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, initialTasks: [source])
        let client = FakeSystemRemindersClient(); let value = coordinator(folder, client); attach(value, workspace)
        await sync(value, workspace.allTasks)
        XCTAssertGreaterThan(client.values.count, 20)
        let binding = try XCTUnwrap(value.store.snapshot.bindings.first { $0.reference.occurrence?.ordinal == 2 })
        client.values[binding.reminderID]!.fields.completed = true
        await sync(value, workspace.allTasks); await sync(value, workspace.allTasks)
        XCTAssertEqual(workspace.allTasks.filter { $0.occurrenceKey == binding.reference.occurrence && $0.status == .completed }.count, 1)
        XCTAssertEqual(value.store.snapshot.bindings.filter { $0.id == binding.id }.count, 1)
        XCTAssertEqual(client.values[binding.reminderID]?.fields.completed, true)
    }

    func testChildrenAreIndependentRemindersAndArchiveRemovesManagedCopies() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let parent = task(); var child = task(scheduled: false); child.parentID = parent.id
        let client = FakeSystemRemindersClient(); let value = coordinator(folder, client)
        await sync(value, [parent, child]); XCTAssertEqual(client.values.count, 2)
        value.requestSync(tasks: [parent, child], activeLists: []); await value.waitForSync()
        XCTAssertTrue(client.values.isEmpty)
    }

    func testExternalReminderProviderRemovesDuplicateLocalNotificationsAndCanRestoreThem() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = task(); let client = FakeTaskNotificationClient()
        let reminders = NativeReminderService(clock: { self.now }, calendar: calendar, directory: folder, client: client)
        reminders.reconcile([source]); await reminders.waitForReconciliation(); XCTAssertEqual(client.values.count, 2)
        reminders.setExternallyRemindedTasks([source.id]); await reminders.waitForReconciliation(); XCTAssertTrue(client.values.isEmpty)
        reminders.setExternallyRemindedTasks([]); await reminders.waitForReconciliation(); XCTAssertEqual(client.values.count, 2)
    }
}

@MainActor
final class FakeSystemRemindersClient: SystemRemindersClient {
    var authorization: EKAuthorizationStatus = .fullAccess
    var onChange: (() -> Void)?
    var values: [String: SystemReminderItem] = [:]
    var writes = 0
    var failNextSave = false
    var availableAccounts: [SystemReminderAccount] = [.init(id: "icloud", title: "iCloud")]
    var availableLists: [SystemReminderList] = [.init(id: "icloud-workfollow", title: "WorkFollow", accountID: "icloud", accountTitle: "iCloud", writable: true)]
    var createdLists: [SystemReminderList] = []
    func requestAccess() async throws -> Bool { authorization == .fullAccess }
    func accounts() -> [SystemReminderAccount] { availableAccounts }
    func lists() -> [SystemReminderList] { availableLists }
    func createList(title: String, accountID: String) throws -> SystemReminderList {
        let value = SystemReminderList(id: "created-list-\(createdLists.count)", title: title,
            accountID: accountID, accountTitle: availableAccounts.first { $0.id == accountID }?.title ?? "", writable: true)
        availableLists.append(value); createdLists.append(value)
        return value
    }
    func reminders(listIDs: [String]) async throws -> [SystemReminderItem] { values.values.filter { listIDs.contains($0.listID) } }
    func save(_ fields: ReminderTaskFields, listID: String, sourceURL: URL, notes: String, existingID: String?) throws -> SystemReminderItem {
        if failNextSave { failNextSave = false; throw CalendarIntegrationError.message("临时写入失败") }
        writes += 1
        let id = existingID ?? UUID().uuidString
        let value = SystemReminderItem(id: id, listID: listID, sourceURL: sourceURL, fields: fields)
        values[id] = value; return value
    }
    func remove(id: String) throws { values.removeValue(forKey: id) }
}
