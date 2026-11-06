import XCTest
@testable import WorkFollow

@MainActor
final class AIScheduledJobTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return value
    }
    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    private func schedule(_ frequency: AIJobSchedule.Frequency = .daily, day: Int = 3, hour: Int = 9) -> AIJobSchedule {
        .init(frequency: frequency, firstRunAt: date(day, hour), timeZoneID: calendar.timeZone.identifier)
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ai-schedules-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await _Concurrency.Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Scheduled AI run did not settle")
    }

    func testCalendarSchedulesRespectFrequencyAndCoalesceMissedOccurrences() {
        XCTAssertEqual(schedule(.once).next(after: date(3, 8)), date(3, 9))
        XCTAssertNil(schedule(.once).next(after: date(3, 10)))
        XCTAssertEqual(schedule().next(after: date(3, 10)), date(4, 9))
        XCTAssertEqual(schedule(.weekly).next(after: date(3, 10)), date(10, 9))
        XCTAssertEqual(schedule(.weekdays).next(after: date(6, 10)), date(9, 9))
        XCTAssertEqual(schedule(.weekdays).latest(notBefore: date(3, 9), through: date(8, 12)), date(6, 9))
        XCTAssertEqual(schedule().latest(notBefore: date(3, 9), through: date(6, 12)), date(6, 9))
    }

    func testRestartExecutesOnlyLatestMissedRunAndAdvancesBeforeGeneration() throws {
        let root = try directory(); var now = date(3, 8)
        let store = AIScheduledJobStore(directory: root, clock: { now })
        let job = try store.add(instruction: "汇总虚构待办", schedule: schedule())
        now = date(6, 12)
        let run = try store.begin(job.id, manual: false, conversationID: UUID())
        XCTAssertEqual(run.scheduledFor, date(6, 9))
        XCTAssertEqual(store.job(job.id)?.nextRunAt, date(7, 9))
        let reopened = AIScheduledJobStore(directory: root, clock: { now })
        XCTAssertEqual(reopened.job(job.id)?.lastRun?.state, .interrupted)
        XCTAssertEqual(reopened.job(job.id)?.nextRunAt, date(7, 9))
        XCTAssertThrowsError(try reopened.begin(job.id, manual: false, conversationID: UUID()))
    }

    func testSingleRunDisablesAndManualRunPreservesAFutureSchedule() throws {
        var now = date(3, 8)
        let store = AIScheduledJobStore(directory: try directory(), clock: { now })
        let job = try store.add(instruction: "虚构单次总结", schedule: schedule(.once))
        let manual = try store.begin(job.id, manual: true, conversationID: UUID())
        XCTAssertEqual(store.job(job.id)?.nextRunAt, date(3, 9))
        try store.finish(job.id, runID: manual.id, state: .complete)
        now = date(3, 10)
        let due = try store.begin(job.id, manual: false, conversationID: UUID())
        XCTAssertEqual(due.scheduledFor, date(3, 9))
        XCTAssertFalse(try XCTUnwrap(store.job(job.id)).isEnabled)
        XCTAssertNil(store.job(job.id)?.nextRunAt)
    }

    func testEditingAndPausingUseVersionsAndKeepCurrentRunState() throws {
        let store = AIScheduledJobStore(directory: try directory(), clock: { self.date(3, 8) })
        let job = try store.add(instruction: "虚构原指令", schedule: schedule())
        let run = try store.begin(job.id, manual: true, conversationID: UUID())
        let changed = try store.update(job.id, version: job.version, instruction: "虚构新指令", schedule: schedule(hour: 11))
        XCTAssertEqual(changed.lastRun?.id, run.id)
        XCTAssertThrowsError(try store.update(job.id, version: job.version, enabled: false))
        try store.finish(job.id, runID: run.id, state: .complete)
        XCTAssertEqual(store.job(job.id)?.nextRunAt, date(3, 11))
        let paused = try store.update(job.id, version: changed.version, enabled: false)
        XCTAssertNil(paused.nextRunAt)
        let enabled = try store.update(job.id, version: paused.version, enabled: true)
        XCTAssertEqual(enabled.nextRunAt, date(3, 11))
    }

    func testBackgroundResultsKeepTheCurrentChatAndDraftAndDoNotDuplicate() async throws {
        let root = try directory(); var now = date(3, 8), calls = 0
        let store = AIScheduledJobStore(directory: root, clock: { now }), chats = AIChatStore(directory: root)
        let original = chats.current.record.id; chats.current.input = "尚未发送的草稿"
        let job = try store.add(instruction: "汇总虚构待办", schedule: schedule())
        let runner = AIScheduledJobRunner(store: store, chats: chats) { _, _, _ in
            { _, _, _, message, updates in
                calls += 1; XCTAssertTrue(message.contains("汇总虚构待办"))
                updates(AITextUpdate(kind: "text", text: "虚构流式回复"))
                return "虚构任务已汇总"
            }
        }
        now = date(5, 10); runner.start(timers: false)
        try await wait { store.job(job.id)?.lastRun?.state == .complete }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(chats.current.record.id, original)
        XCTAssertEqual(chats.current.input, "尚未发送的草稿")
        XCTAssertEqual(chats.records.count, 1)
        XCTAssertEqual(chats.records.first?.messages.last?.text, "虚构任务已汇总")
        runner.checkDue(); XCTAssertEqual(calls, 1)
        runner.shutdown()
    }

    func testOpeningAndStoppingARunKeepsActualReceiptsAndPreventsAutomaticReplay() async throws {
        let root = try directory(), store = AIScheduledJobStore(directory: root, clock: { self.date(3, 8) })
        let chats = AIChatStore(directory: root)
        let job = try store.add(instruction: "虚构的较长任务", schedule: schedule())
        let runner = AIScheduledJobRunner(store: store, chats: chats) { _, _, _ in
            { id, _, _, _, _ in
                XCTAssertTrue(AIConversationRegistry.shared.append(.init(title: "虚构已保存笔记", details: "已保存"), id: id))
                try await _Concurrency.Task.sleep(for: .seconds(30))
                return "不应完成"
            }
        }
        runner.start(timers: false); try runner.runNow(job.id)
        try await wait { chats.records.first?.messages.last?.actions?.count == 1 }
        let conversation = try XCTUnwrap(store.job(job.id)?.lastRun?.conversationID)
        chats.select(conversation)
        XCTAssertTrue(chats.current.isRunning, "打开结果应连接仍在执行的同一个会话")
        runner.stop(job.id)
        XCTAssertEqual(store.job(job.id)?.lastRun?.state, .interrupted)
        XCTAssertEqual(chats.records.first?.messages.last?.actions?.count, 1)
        XCTAssertEqual(chats.current.record.messages.last?.state, .stopped)
        XCTAssertEqual(store.job(job.id)?.nextRunAt, date(3, 9))
        runner.shutdown()
    }

    func testOpeningAndLeavingARunKeepsBackgroundResultsAndReceipts() async throws {
        let root = try directory(), store = AIScheduledJobStore(directory: root, clock: { self.date(3, 8) })
        let chats = AIChatStore(directory: root)
        let job = try store.add(instruction: "虚构的后台任务", schedule: schedule())
        var resume: CheckedContinuation<String, Never>?
        let runner = AIScheduledJobRunner(store: store, chats: chats) { _, _, _ in
            { id, _, _, _, _ in
                XCTAssertTrue(AIConversationRegistry.shared.append(.init(title: "虚构已保存笔记", details: "已保存"), id: id))
                return await withCheckedContinuation { resume = $0 }
            }
        }
        defer { runner.shutdown(); resume?.resume(returning: "清理") }
        runner.start(timers: false); try runner.runNow(job.id)
        try await wait { resume != nil }
        let id = try XCTUnwrap(store.job(job.id)?.lastRun?.conversationID)
        XCTAssertEqual(chats.runningIDs, [id]); XCTAssertTrue(chats.isAnyRunning)
        chats.select(id)
        let running = chats.current
        chats.newConversation()
        chats.current.input = "独立草稿"
        let selected = chats.current.record.id
        XCTAssertTrue(running.isRunning)
        let completion = resume; resume = nil; completion?.resume(returning: "后台任务已完成")
        try await wait { store.job(job.id)?.lastRun?.state == .complete }
        XCTAssertEqual(chats.current.record.id, selected); XCTAssertEqual(chats.current.input, "独立草稿")
        XCTAssertTrue(chats.runningIDs.isEmpty); XCTAssertFalse(chats.isAnyRunning)
        await withCheckedContinuation { continuation in chats.flush { error in XCTAssertNil(error); continuation.resume() } }
        let restored = AIChatStore(directory: root)
        restored.select(id)
        XCTAssertEqual(restored.current.latestResult, "后台任务已完成")
        XCTAssertEqual(restored.current.record.messages.last?.actions?.first?.title, "虚构已保存笔记")
        chats.select(id); XCTAssertTrue(chats.current === running)
    }

    func testCLIUsesTheSharedScheduleStoreAndLeavesTaskUndoAlone() throws {
        let root = try directory(), store = AIScheduledJobStore(directory: root, clock: { self.date(3, 8) })
        let tasks = TaskWorkspaceModel(seedDemoData: false, initialTasks: [])
        var requested: UUID?
        let service = NativeAutomationService(tasks: tasks, notes: NotesWorkspaceModel(taskWorkspace: tasks), directory: root,
            scheduledJobs: store, runScheduledJob: { requested = $0 })
        func command(_ tokens: [String]) throws -> AutomationValue {
            try service.execute(XCTUnwrap(AutomationInvocation.parse(tokens) { _ in "" }.request))
        }
        let added = try command(["schedule", "add", "--content", "汇总虚构待办", "--at", "2026-11-03T09:00:00+08:00", "--repeat", "daily"])
        let id = try XCTUnwrap(added["id"]?.string), version = try XCTUnwrap(added["version"]?.string)
        XCTAssertEqual(store.jobs.count, 1)
        XCTAssertNil(tasks.automationUndoID)
        let get = try command(["schedule", "get", "--id", id])
        XCTAssertEqual(get["content"]?.string, "汇总虚构待办")
        let run = try command(["schedule", "run", "--id", id])
        XCTAssertEqual(run["queued"], .bool(true)); XCTAssertEqual(requested?.uuidString, id)
        let paused = try command(["schedule", "update", "--id", id, "--version", version, "--enabled", "false"])
        XCTAssertEqual(paused["enabled"], .bool(false))
        XCTAssertThrowsError(try command(["schedule", "delete", "--id", id, "--version", version]))
        _ = try command(["schedule", "delete", "--id", id, "--version", try XCTUnwrap(paused["version"]?.string)])
        XCTAssertTrue(store.jobs.isEmpty)
    }
}
