import XCTest
import UserNotifications
@testable import WorkFollow

/// P4：检查项提醒进入系统通知队列，并随勾选/删除/切模式/完成任务自动失效。
@MainActor
final class ChecklistReminderNotificationTests: XCTestCase {
    private var now: Date { Date(timeIntervalSince1970: 1_800_000_000) }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 28800)!
        return value
    }
    private var reminder: Date { now.addingTimeInterval(3600) }
    private var otherReminder: Date { now.addingTimeInterval(7200) }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("checklist-reminder-" + UUID().uuidString)
    }

    private func task(_ items: [(Bool, Date?)], kind: TaskKind = .checklist,
                      status: TaskStatus = .active) -> Task {
        let blocks = items.enumerated().map { index, item in
            DocumentBlock(kind: .checklist(item.0), runs: [DocumentRun(text: "事项\(index)")],
                          checklist: item.1.map { ChecklistItemMeta(reminderAt: $0) })
        }
        var value = Task(id: UUID(), title: "清单任务", list: .inbox, priority: .none,
                         schedule: .init(), childOrder: 0, createdAt: now, updatedAt: now)
        value.kind = kind
        value.status = status
        value.document = NativeDocument(blocks: blocks)
        return value
    }

    private func makeService(_ client: FakeTaskNotificationClient,
                             folder: URL) -> NativeReminderService {
        NativeReminderService(clock: { self.now }, calendar: calendar, directory: folder,
                              client: client)
    }

    /// 保留任务与块身份，只改勾选态——通知标识依赖块 ID，不能重建文档。
    private func updating(_ source: Task, checked: [Bool]) -> Task {
        var value = source
        var blocks = value.document.blocks
        for (index, state) in checked.enumerated() where index < blocks.count {
            blocks[index].kind = .checklist(state)
        }
        value.document = NativeDocument(blocks: blocks)
        return value
    }

    func testPlannerEmitsOnlyOpenChecklistItemsWithIsolatedPrefix() {
        let source = task([(false, reminder), (true, otherReminder)])
        let deliveries = TaskReminderPlanner.deliveries(tasks: [source], countdowns: [], now: now,
            calendar: calendar, decisions: [:])
        XCTAssertEqual(deliveries.count, 1)
        let delivery = deliveries[0]
        XCTAssertEqual(delivery.kind, .checklistItem)
        XCTAssertTrue(delivery.id.hasPrefix("checklist.\(source.id.uuidString)."))
        XCTAssertEqual(delivery.title, "事项0")
        XCTAssertEqual(delivery.body, "清单任务")
        XCTAssertEqual(delivery.originalDate, reminder)
        XCTAssertEqual(delivery.checklistItemID, source.document.blocks[0].id)
    }

    func testPlannerIgnoresClosedTasksTextTasksAndInlineChecklists() {
        let closed = task([(false, reminder)], status: .completed)
        let text = task([(false, reminder)], kind: .text)
        XCTAssertTrue(TaskReminderPlanner.deliveries(tasks: [closed, text], countdowns: [], now: now,
            calendar: calendar, decisions: [:]).isEmpty)
    }

    func testCheckingRemovingAndCompletingItemsCancelTheirNotifications() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        var source = task([(false, reminder), (false, otherReminder)])
        let client = FakeTaskNotificationClient()
        let service = makeService(client, folder: folder)
        service.reconcile([source]); await service.waitForReconciliation()
        XCTAssertEqual(client.values.keys.filter { $0.hasPrefix("checklist.") }.count, 2)

        // 勾选第一项：只剩第二项。
        source = updating(source, checked: [true, false])
        service.reconcile([source]); await service.waitForReconciliation()
        let remaining = client.values.keys.filter { $0.hasPrefix("checklist.") }
        XCTAssertEqual(remaining.count, 1)
        XCTAssertTrue(remaining[0].contains(source.document.blocks[1].id.uuidString))

        // 删除第二项：队列清空。
        var removed = source
        removed.document = NativeDocument(blocks: [source.document.blocks[0]])
        service.reconcile([removed]); await service.waitForReconciliation()
        XCTAssertTrue(client.values.keys.filter { $0.hasPrefix("checklist.") }.isEmpty)

        // 切回文本也不再生成。
        var text = removed
        text.kind = .text
        text.document = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "事项0")],
                          checklist: ChecklistItemMeta(reminderAt: reminder))
        ])
        service.reconcile([text]); await service.waitForReconciliation()
        XCTAssertTrue(client.values.isEmpty)
    }

    func testUncheckingRequeuesFutureReminderAndCompletedTaskCancelsIt() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        var source = task([(true, reminder)])
        let client = FakeTaskNotificationClient()
        let service = makeService(client, folder: folder)
        service.reconcile([source]); await service.waitForReconciliation()
        XCTAssertTrue(client.values.isEmpty, "已勾选项不排通知")

        source = updating(source, checked: [false])
        service.reconcile([source]); await service.waitForReconciliation()
        XCTAssertEqual(client.values.keys.filter { $0.hasPrefix("checklist.") }.count, 1)

        var completed = source
        completed.status = .completed
        service.reconcile([completed]); await service.waitForReconciliation()
        XCTAssertTrue(client.values.isEmpty)
    }

    func testSnoozeAppliesToChecklistItemDelivery() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = task([(false, reminder)])
        let client = FakeTaskNotificationClient()
        let service = makeService(client, folder: folder)
        service.reconcile([source]); await service.waitForReconciliation()
        let delivery = try XCTUnwrap(service.deliveries.first { $0.kind == .checklistItem })
        let id = delivery.id
        await service.handle(delivery, snoozeMinutes: 10)
        XCTAssertEqual(client.values[id]?.delivery.fireDate,
                       now.addingTimeInterval(600), "稍后提醒重建为 10 分钟后")
        XCTAssertEqual(source.document.blocks[0].checklist?.reminderAt, reminder,
                       "稍后提醒只改投递，不改文档里的原始时间")
    }

    func testCapacityIsCappedPerPrefixSoTaskAndChecklistDoNotEvictEachOther() async {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        var busy = Task(id: UUID(), title: "任务提醒", list: .inbox, priority: .none,
                        schedule: .init(dueAt: now.addingTimeInterval(100_000), hasTime: true),
                        childOrder: 0, createdAt: now, updatedAt: now)
        busy.reminderOffsets = (0...300).map { -$0 }
        let item = task([(false, now.addingTimeInterval(90_000))])
        let client = FakeTaskNotificationClient()
        let service = makeService(client, folder: folder)
        service.reconcile([busy, item]); await service.waitForReconciliation()
        let ids = Array(client.values.keys)
        XCTAssertEqual(ids.filter { $0.hasPrefix("task.") }.count, 256)
        XCTAssertEqual(ids.filter { $0.hasPrefix("checklist.") }.count, 1,
                       "任务提醒占满自己的额度后，检查项提醒仍应保留")
    }

    func testSameFireDateDeliveriesSortStablyByItemIdentity() {
        let source = task([(false, reminder), (false, reminder), (false, reminder)])
        let first = TaskReminderPlanner.deliveries(tasks: [source], countdowns: [], now: now,
            calendar: calendar, decisions: [:])
        let second = TaskReminderPlanner.deliveries(tasks: [source], countdowns: [], now: now,
            calendar: calendar, decisions: [:])
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.map(\.id), first.map(\.id).sorted())
    }

    func testReminderDeliveryRoundTripsChecklistItemIdentity() throws {
        let source = task([(false, reminder)])
        let delivery = try XCTUnwrap(TaskReminderPlanner.deliveries(
            tasks: [source], countdowns: [], now: now, calendar: calendar, decisions: [:]).first)
        let data = try JSONEncoder().encode(delivery)
        let decoded = try JSONDecoder().decode(ReminderDelivery.self, from: data)
        XCTAssertEqual(decoded, delivery)
        XCTAssertEqual(decoded.checklistItemID, source.document.blocks[0].id)
    }
}
