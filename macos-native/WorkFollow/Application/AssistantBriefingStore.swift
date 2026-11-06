import Combine
import Foundation

struct AssistantBriefingFacts: Codable, Sendable {
    struct Item: Codable, Sendable {
        let id: UUID
        let title: String
        let list: String
        let url: String
        let date: String?
        let end: String?
        let deadline: String?
        let hasTime: Bool
        let priority: String
        let categories: [String]
    }
    let localTime: String
    let timeZone: String
    let todayCount: Int
    let overdueCount: Int
    let deadlineCount: Int
    let importantCount: Int
    let tasks: [Item]

    static func make(tasks: [Task], now: Date, calendar: Calendar) -> Self {
        let start = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start)!
        let deadlineEnd = calendar.date(byAdding: .day, value: 3, to: start)!
        let window = DateInterval(start: start, end: tomorrow)
        let active = tasks.filter { !$0.isNoteTask && !$0.isClosed && !$0.isConverted && $0.deletedAt == nil && $0.skippedAt == nil }
        // Keep completed occurrences in the input so projection cannot recreate them.
        let occurrences = TaskOccurrenceProjection.occurrences(tasks: tasks, in: window, calendar: calendar)
            .filter { !$0.task.isNoteTask && !$0.task.isClosed && !$0.task.isConverted && $0.task.skippedAt == nil }
        var candidates = Dictionary(uniqueKeysWithValues: active.map { ($0.id, ($0, $0.id, false)) })
        for occurrence in occurrences {
            candidates[occurrence.task.id] = (occurrence.task, occurrence.sourceTaskID, true)
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let iso = ISO8601DateFormatter()
        let priorities: [TaskPriority: String] = [.none: "none", .low: "low", .medium: "medium", .high: "high"]
        let items = candidates.values.compactMap { task, sourceID, projectedToday -> Item? in
            var categories: [String] = []
            if projectedToday || TaskOccurrenceProjection.intersects(task.schedule, window: window, calendar: calendar) { categories.append("today") }
            if ScheduleOverdue.isOverdue(schedule: task.schedule, now: now, calendar: calendar) { categories.append("overdue") }
            if let due = task.schedule.deadlineAt, due < deadlineEnd { categories.append("deadline") }
            if task.priority == .high { categories.append("important") }
            guard !categories.isEmpty else { return nil }
            return Item(id: task.id, title: task.title, list: task.list.name,
                url: "workfollow://task/" + sourceID.uuidString,
                date: task.schedule.dueAt.map(iso.string), end: task.schedule.dueEndAt.map(iso.string),
                deadline: task.schedule.deadlineAt.map(iso.string), hasTime: task.schedule.hasTime,
                priority: priorities[task.priority] ?? "none", categories: categories)
        }.sorted {
            let lhs = $0.date ?? $0.deadline ?? "~", rhs = $1.date ?? $1.deadline ?? "~"
            return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs < rhs
        }
        func count(_ category: String) -> Int { items.filter { $0.categories.contains(category) }.count }
        return Self(localTime: formatter.string(from: now), timeZone: calendar.timeZone.identifier,
            todayCount: count("today"), overdueCount: count("overdue"), deadlineCount: count("deadline"),
            importantCount: count("important"), tasks: items)
    }

    var parameters: [String: Any] {
        // A Codable projection keeps the backend independent of native domain models.
        (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))) as? [String: Any] ?? [:]
    }
}

struct AssistantDailyBriefing: Codable, Sendable {
    let day: String
    let timeZone: String
    let generatedAt: Date
    let facts: AssistantBriefingFacts
    let text: String
}

@MainActor
final class AssistantBriefingStore: ObservableObject {
    typealias Generate = (@escaping @Sendable (AITextUpdate) -> Void) async throws -> (AssistantBriefingFacts, String)
    private struct Snapshot: Codable { var automaticEnabled = true; var record: AssistantDailyBriefing? }
    @Published private(set) var record: AssistantDailyBriefing?
    @Published private(set) var automaticEnabled = true
    @Published private(set) var isRunning = false
    @Published private(set) var preview = ""
    @Published private(set) var error: String?
    private let file: URL
    private let clock: () -> Date
    private let calendar: Calendar
    private var loadFailed = false
    private var attemptedDay: String?
    private var worker: _Concurrency.Task<Void, Never>?
    private var token = UUID()

    init(directory: URL, clock: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        file = directory.appendingPathComponent("assistant-briefing.json")
        self.clock = clock; self.calendar = calendar
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let saved = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
                record = saved.record; automaticEnabled = saved.automaticEnabled
            } catch { loadFailed = true; self.error = "今日简报读取失败：" + error.localizedDescription }
        }
    }

    var current: AssistantDailyBriefing? {
        guard let record, record.day == dayKey, record.timeZone == calendar.timeZone.identifier else { return nil }
        return record
    }
    private var dayKey: String { SummaryStore.dayKey(clock(), calendar: calendar) }
    var shouldRefreshAutomatically: Bool {
        !isRunning && !loadFailed && automaticEnabled && current == nil && attemptedDay != dayKey
    }
    var context: String {
        guard let current else { return "" }
        return "今日简报（生成时的参考快照，实际状态请通过 CLI 核对）：\n" + current.text
    }

    func setAutomaticEnabled(_ enabled: Bool) throws {
        try persist(Snapshot(automaticEnabled: enabled, record: record))
        automaticEnabled = enabled
        if !enabled { stop() }
    }

    func refresh(force: Bool = false, generate: @escaping Generate) {
        guard !isRunning, !loadFailed else { return }
        let day = dayKey, zone = calendar.timeZone.identifier
        guard force || shouldRefreshAutomatically else { return }
        attemptedDay = day; error = nil; preview = ""; isRunning = true
        let request = UUID(); token = request
        worker = _Concurrency.Task { [weak self] in
            do {
                let (facts, text) = try await generate { [weak self] update in
                    _Concurrency.Task { @MainActor in
                        guard let self, self.token == request, self.isRunning, update.kind == "text" else { return }
                        self.preview = update.text ?? ""
                    }
                }
                try _Concurrency.Task.checkCancellation()
                guard let self, self.token == request else { return }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIBackendError.invalidResponse }
                let next = AssistantDailyBriefing(day: day, timeZone: zone, generatedAt: self.clock(), facts: facts, text: text)
                try self.persist(Snapshot(automaticEnabled: self.automaticEnabled, record: next))
                self.record = next
                self.finish()
            } catch {
                guard let self, self.token == request else { return }
                self.error = error is CancellationError ? nil : error.localizedDescription
                self.finish()
            }
        }
    }

    func stop() { worker?.cancel(); token = UUID(); finish() }
    private func finish() { isRunning = false; worker = nil; preview = "" }
    private func persist(_ value: Snapshot) throws {
        guard !loadFailed else { throw AIBackendError.failed(error ?? "今日简报读取失败。") }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
    }
}
