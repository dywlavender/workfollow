import Foundation

struct AITaskRequest: Identifiable {
    enum Source { case note(UUID), meeting(UUID), task(UUID) }
    let id = UUID()
    let source: Source
    let title: String
    let content: String
    let referenceDate: Date
    var existingTitles: [String] = []
    var isBreakdown: Bool { if case .task = source { true } else { false } }
    var actionTitle: String { isBreakdown ? "拆分子任务" : "提取待办" }
    var sourceURL: URL {
        switch source {
        case let .note(id): NativeResourceLink.note(id).url
        case let .meeting(id): NativeResourceLink.meeting(id).url
        case let .task(id): NativeResourceLink.task(id).url
        }
    }
    var backendParameters: [String: Any] {
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"; day.locale = Locale(identifier: "en_US_POSIX")
        day.calendar = Calendar(identifier: .gregorian)
        return ["action": isBreakdown ? "breakdown_task" : "extract_tasks", "title": title,
                "content": content, "existingTitles": existingTitles,
                "referenceDate": day.string(from: referenceDate), "timeZone": TimeZone.current.identifier]
    }

}

struct AITaskDraft: Identifiable {
    let id = UUID()
    var selected = true
    var title: String
    var schedule: TaskSchedule = TaskSchedule()
    var priority: TaskPriority = .none
    var quote = ""

    static func normalizedTitle(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined().lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
    }

    static func decode(_ text: String, request: AITaskRequest) throws -> [Self] {
        struct Payload: Decodable { var tasks: [Row] }
        struct Row: Decodable { var title: String; var date: String?; var due: String?; var priority: String?; var quote: String? }
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("```"), raw.hasSuffix("```"), let line = raw.firstIndex(of: "\n") {
            raw = String(raw[raw.index(after: line)..<raw.index(raw.endIndex, offsetBy: -3)])
        }
        let payload = try JSONDecoder().decode(Payload.self, from: Data(raw.utf8))
        var known = Set(request.existingTitles.map(normalizedTitle))
        let source = request.title + "\n" + request.content
        return try payload.tasks.compactMap { row in
            let title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, known.insert(normalizedTitle(title)).inserted else { return nil }
            let quote = row.quote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard request.isBreakdown || (!quote.isEmpty && source.contains(quote)) else { return nil }
            let date = try row.date.map(parseDate), due = try row.due.map(parseDate)
            let priority: TaskPriority
            switch row.priority ?? "none" {
            case "high": priority = .high
            case "medium": priority = .medium
            case "low": priority = .low
            default: priority = .none
            }
            return Self(title: title, schedule: TaskSchedule(dueAt: date, hasTime: row.date?.contains("T") == true,
                deadlineAt: due), priority: priority, quote: quote)
        }
    }

    private static func parseDate(_ raw: String) throws -> Date {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.calendar = Calendar(identifier: .gregorian)
        day.dateFormat = "yyyy-MM-dd"; day.isLenient = false
        if let date = day.date(from: raw), day.string(from: date) == raw { return date }
        throw AITaskError.invalidDates
    }

    func document(for request: AITaskRequest) -> NativeDocument {
        var blocks = [DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "来源："),
            DocumentRun(text: request.title, marks: [.link(request.sourceURL.absoluteString)])])]
        if !quote.isEmpty { blocks.append(DocumentBlock(kind: .quote, runs: [DocumentRun(text: quote)])) }
        return NativeDocument(blocks: blocks)
    }
}

enum AITaskError: LocalizedError {
    case sourceMissing, invalidTarget, invalidDates
    var errorDescription: String? {
        switch self {
        case .sourceMissing: "原内容已移除或任务已结束，请返回原页面检查。"
        case .invalidTarget: "目标清单或分组已不可用，请重新选择。"
        case .invalidDates: "AI 返回了无法识别的日期，请重新生成。"
        }
    }
}
