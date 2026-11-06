import Combine
import Foundation

@MainActor
final class AIScheduledJobStore: ObservableObject {
    @Published private(set) var jobs: [AIScheduledJob] = []
    @Published private(set) var storageError: String?
    var onChange: (() -> Void)?
    private let file: URL
    let clock: () -> Date

    init(directory: URL, clock: @escaping () -> Date = Date.init) {
        file = directory.appendingPathComponent("ai-scheduled-tasks.json"); self.clock = clock
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                jobs = try JSONDecoder().decode([AIScheduledJob].self, from: Data(contentsOf: file))
                var recovered = jobs
                for index in recovered.indices where recovered[index].lastRun?.state == .running {
                    recovered[index].lastRun?.state = .interrupted
                    recovered[index].lastRun?.finishedAt = clock()
                    recovered[index].lastRun?.error = "上次执行随 App 退出而中断，可查看结果或手动重试。"
                }
                if recovered != jobs { try persist(recovered) }
            } catch { storageError = "定时任务读取失败：" + error.localizedDescription }
        }
    }

    func job(_ id: UUID) -> AIScheduledJob? { jobs.first { $0.id == id } }

    @discardableResult
    func add(title: String = "", instruction: String, schedule: AIJobSchedule, enabled: Bool = true) throws -> AIScheduledJob {
        let text = try content(instruction)
        try validate(schedule)
        let next = enabled ? try nextDate(schedule) : nil
        let job = AIScheduledJob(title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(text.prefix(28)) : title,
            instruction: text, schedule: schedule, isEnabled: enabled, nextRunAt: next)
        try persist(jobs + [job]); return job
    }

    @discardableResult
    func update(_ id: UUID, version: Int, title: String? = nil, instruction: String? = nil,
                schedule: AIJobSchedule? = nil, enabled: Bool? = nil) throws -> AIScheduledJob {
        let index = try checkedIndex(id, version: version)
        var next = jobs
        if let title { next[index].title = try content(title) }
        if let instruction { next[index].instruction = try content(instruction) }
        if let schedule { try validate(schedule); next[index].schedule = schedule }
        if let enabled { next[index].isEnabled = enabled }
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
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].lastRun?.id == runID else { return }
        var next = jobs
        next[index].lastRun?.state = state; next[index].lastRun?.finishedAt = clock()
        next[index].lastRun?.error = error
        try persist(next)
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
    private func persist(_ next: [AIScheduledJob]) throws {
        if let storageError { throw AutomationFailure(code: "storage_unavailable", message: storageError) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: file, options: .atomic)
        jobs = next; onChange?()
    }
}
