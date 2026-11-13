import XCTest
@testable import WorkFollow

@MainActor
final class AssistantBriefingTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return value
    }
    private func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }
    private func task(_ title: String, day: Int? = nil, deadline: Int? = nil) -> Task {
        Task(id: UUID(), title: title, list: .inbox, priority: .none,
             schedule: TaskSchedule(dueAt: day.map { date($0) }, deadlineAt: deadline.map { date($0) }),
             childOrder: 0, createdAt: date(1), updatedAt: date(1))
    }
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("assistant-briefing-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func settled(_ store: AssistantBriefingStore) async throws {
        for _ in 0..<200 {
            if !store.isRunning { return }
            try await _Concurrency.Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Briefing did not finish")
    }

    func testFactsUseDatesAndStatusesWithoutReadingTaskBodies() {
        let today = task("虚构今日任务", day: 3)
        let overdue = task("虚构逾期任务", day: 2)
        let deadline = task("虚构临近截止任务", deadline: 5)
        var closed = task("已完成", day: 3); closed.status = .completed
        var deleted = task("已删除", day: 3); deleted.deletedAt = date(2)
        var note = task("笔记", day: 3); note.kind = .note
        let future = task("未来任务", day: 20)
        let facts = AssistantBriefingFacts.make(tasks: [today, overdue, deadline, closed, deleted, note, future],
                                               now: date(3, 8), calendar: calendar)
        XCTAssertEqual(facts.todayCount, 1)
        XCTAssertEqual(facts.overdueCount, 1)
        XCTAssertEqual(facts.deadlineCount, 1)
        XCTAssertEqual(Set(facts.tasks.map(\.id)), Set([today.id, overdue.id, deadline.id]))
        XCTAssertEqual(facts.tasks.first { $0.id == deadline.id }?.categories, ["deadline"])
        XCTAssertEqual(facts.tasks.first { $0.id == today.id }?.url, "workfollow://task/" + today.id.uuidString)
        XCTAssertEqual(facts.timeZone, "Asia/Shanghai")
    }

    func testRecurringTodayUsesTheProjectedOccurrenceAndSourceLink() {
        var recurring = task("虚构每日任务", day: 1); recurring.recurrence = .daily
        let facts = AssistantBriefingFacts.make(tasks: [recurring], now: date(3, 8), calendar: calendar)
        let occurrence = facts.tasks.first { $0.categories.contains("today") }
        XCTAssertNotNil(occurrence)
        XCTAssertEqual(occurrence?.url, "workfollow://task/" + recurring.id.uuidString)
        XCTAssertNotEqual(occurrence?.id, recurring.id)
    }

    func testDailyGenerationCoalescesPersistsAndRunsAgainOnTheNextDay() async throws {
        let directory = try root()
        var now = date(3, 8), calls = 0
        let cal = calendar
        let generate: AssistantBriefingStore.Generate = { updates in
            calls += 1
            updates(AITextUpdate(kind: "text", text: "虚构流式内容"))
            try await _Concurrency.Task.sleep(for: .milliseconds(30))
            return (.make(tasks: [], now: now, calendar: cal), "虚构完整简报")
        }
        let store = AssistantBriefingStore(directory: directory, clock: { now }, calendar: cal)
        store.refresh(generate: generate); store.refresh(generate: generate)
        try await settled(store)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.current?.text, "虚构完整简报")
        let reopened = AssistantBriefingStore(directory: directory, clock: { now }, calendar: cal)
        reopened.refresh(generate: generate)
        XCTAssertFalse(reopened.isRunning)
        XCTAssertEqual(calls, 1)
        now = date(4, 8)
        XCTAssertNil(reopened.current)
        reopened.refresh(generate: generate)
        try await settled(reopened)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(reopened.current?.day, "2026-11-04")
    }

    func testDisablingAutomaticGenerationStillAllowsManualRefreshAndRetry() async throws {
        let store = AssistantBriefingStore(directory: try root(), clock: { self.date(3, 8) }, calendar: calendar)
        try store.setAutomaticEnabled(false)
        var calls = 0
        store.refresh { _ in calls += 1; throw AIBackendError.failed("虚构失败") }
        XCTAssertFalse(store.isRunning)
        XCTAssertEqual(calls, 0)
        store.refresh(force: true) { _ in calls += 1; throw AIBackendError.failed("虚构失败") }
        try await settled(store)
        XCTAssertEqual(store.error, "虚构失败")
        XCTAssertNil(store.current)
        store.refresh(force: true) { _ in
            (.make(tasks: [], now: self.date(3, 8), calendar: self.calendar), "手动刷新成功")
        }
        try await settled(store)
        XCTAssertEqual(store.current?.text, "手动刷新成功")
        XCTAssertNil(store.error)
    }

    /// 「今日简报」卡的收起状态要跨启动保留（用户反馈卡片「一直」在），
    /// 且简报本身的其它写盘（提醒分钟、自动生成开关）不能把收起状态洗掉。
    func testCardHiddenPersistsAcrossReloadsAndOtherWrites() throws {
        let directory = try root()
        let store = AssistantBriefingStore(directory: directory, clock: { self.date(3, 8) }, calendar: calendar)
        XCTAssertFalse(store.cardHidden)
        try store.setCardHidden(true)
        try store.setDefaultReminderMinutes(15)
        try store.setAutomaticEnabled(false)
        let reopened = AssistantBriefingStore(directory: directory, clock: { self.date(3, 8) }, calendar: calendar)
        XCTAssertTrue(reopened.cardHidden, "收起状态应跨启动保留")
        XCTAssertEqual(reopened.defaultReminderMinutes, 15)
        XCTAssertEqual(reopened.automaticEnabled, false)
        try reopened.setCardHidden(false)
        let restored = AssistantBriefingStore(directory: directory, clock: { self.date(3, 8) }, calendar: calendar)
        XCTAssertFalse(restored.cardHidden)
    }
}
