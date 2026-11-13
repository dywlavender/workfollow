import Combine
import Foundation

@MainActor
final class AIScheduledJobStore: ObservableObject {
    private struct Snapshot: Codable {
        let jobs: [AIScheduledJob]
        let deliveries: [AIScheduledDelivery]
    }
    @Published private(set) var jobs: [AIScheduledJob] = []
    @Published private(set) var deliveries: [AIScheduledDelivery] = []
    @Published private(set) var storageError: String?
    var onChange: (() -> Void)?
    private let file: URL
    let clock: () -> Date

    init(directory: URL, clock: @escaping () -> Date = Date.init) {
        file = directory.appendingPathComponent("ai-scheduled-tasks.json"); self.clock = clock
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let data = try Data(contentsOf: file)
                let decoder = JSONDecoder()
                if let snapshot = try? decoder.decode(Snapshot.self, from: data) {
                    jobs = snapshot.jobs
                    deliveries = snapshot.deliveries
                } else {
                    jobs = try decoder.decode([AIScheduledJob].self, from: data)
                }
                for job in jobs {
                    guard let run = job.lastRun, run.state == .running else { continue }
                    try finish(job.id, runID: run.id, state: .interrupted,
                        error: "上次执行随 App 退出而中断，可查看结果或手动重试。")
                }
            } catch { storageError = "定时任务读取失败：" + error.localizedDescription }
        }
    }

    func job(_ id: UUID) -> AIScheduledJob? { jobs.first { $0.id == id } }

    @discardableResult
    func add(title: String = "", instruction: String, schedule: AIJobSchedule, enabled: Bool = true,
             deliverResult: Bool = false) throws -> AIScheduledJob {
        let text = try content(instruction)
        try validate(schedule)
        let next = enabled ? try nextDate(schedule) : nil
        let job = AIScheduledJob(title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(text.prefix(28)) : title,
            instruction: text, schedule: schedule, isEnabled: enabled, nextRunAt: next, deliverResult: deliverResult)
        try persist(jobs + [job]); return job
    }

    @discardableResult
    func update(_ id: UUID, version: Int, title: String? = nil, instruction: String? = nil,
                schedule: AIJobSchedule? = nil, enabled: Bool? = nil, deliverResult: Bool? = nil) throws -> AIScheduledJob {
        let index = try checkedIndex(id, version: version)
        var next = jobs
        if let title { next[index].title = try content(title) }
        if let instruction { next[index].instruction = try content(instruction) }
        if let schedule { try validate(schedule); next[index].schedule = schedule }
        if let enabled { next[index].isEnabled = enabled }
        if let deliverResult { next[index].deliverResult = deliverResult }
        if !next[index].isEnabled { next[index].nextRunAt = nil }
        else if schedule != nil || jobs[index].isEnabled == false { next[index].nextRunAt = try nextDate(next[index].schedule) }
        next[index].version += 1
        try persist(next); return next[index]
    }

    func delete(_ id: UUID, version: Int) throws {
        let index = try checkedIndex(id, version: version)
        var next = jobs; next.remove(at: index); try persist(next)
    }

    /// Advance the schedule before calling Pi. A resumed App never replays a
    /// partially executed run; missed occurrences coalesce into the latest one.
    func begin(_ id: UUID, manual: Bool, conversationID: UUID) throws -> AIScheduledRun {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { throw missing() }
        guard jobs[index].lastRun?.state != .running else { throw AutomationFailure.argument("该定时任务正在执行。") }
        let now = clock(), planned = jobs[index].nextRunAt
        let due = jobs[index].isEnabled && planned.map { $0 <= now } == true
        guard manual || due else { throw AutomationFailure.argument("该任务尚未到执行时间。") }
        let scheduled = due ? jobs[index].schedule.latest(notBefore: planned!, through: now) ?? planned! : now
        let run = AIScheduledRun(scheduledFor: scheduled, startedAt: now, conversationID: conversationID)
        var next = jobs; next[index].lastRun = run
        if due {
            next[index].nextRunAt = next[index].schedule.next(after: now)
            if next[index].nextRunAt == nil { next[index].isEnabled = false }
        }
        try persist(next); return run
    }

    func finish(_ id: UUID, runID: UUID, state: AIScheduledRun.State, error: String? = nil) throws {
        guard let index = jobs.firstIndex(where: { $0.id == id }), var run = jobs[index].lastRun,
              run.id == runID, run.state == .running else { return }
        var next = jobs
        run.state = state; run.finishedAt = clock(); run.error = error
        next[index].lastRun = run
        var results = deliveries
        if next[index].deliverResult == true { results.insert(.init(title: next[index].title, run: run), at: 0) }
        try persist(next, deliveries: results)
    }

    func dismissDelivery(_ id: UUID) throws {
        try persist(jobs, deliveries: deliveries.filter { $0.id != id })
    }

    private func checkedIndex(_ id: UUID, version: Int) throws -> Int {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { throw missing() }
        guard jobs[index].version == version else {
            throw AutomationFailure(code: "version_conflict", message: "定时任务已更新，请重新读取后修改。")
        }
        return index
    }
    private func missing() -> AutomationFailure { .init(code: "not_found", message: "定时任务已不存在。") }
    private func content(_ value: String) throws -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AutomationFailure.argument("任务指令和标题不能为空。") }
        return text
    }
    private func validate(_ schedule: AIJobSchedule) throws {
        guard TimeZone(identifier: schedule.timeZoneID) != nil else { throw AutomationFailure.argument("时区无效。") }
    }
    private func nextDate(_ schedule: AIJobSchedule) throws -> Date {
        guard let date = schedule.next(after: clock()) else { throw AutomationFailure.argument("请选择未来的执行时间。") }
        return date
    }
    private func persist(_ next: [AIScheduledJob], deliveries nextDeliveries: [AIScheduledDelivery]? = nil) throws {
        if let storageError { throw AutomationFailure(code: "storage_unavailable", message: storageError) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let results = nextDeliveries ?? deliveries
        try JSONEncoder().encode(Snapshot(jobs: next, deliveries: results)).write(to: file, options: .atomic)
        deliveries = results
        jobs = next; onChange?()
    }
}
