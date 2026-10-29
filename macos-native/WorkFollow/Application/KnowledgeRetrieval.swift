import Foundation
import NaturalLanguage

enum KnowledgeKind: String, Codable, Sendable {
    case task, note, meeting
    var title: String { switch self { case .task: "任务"; case .note: "笔记"; case .meeting: "会议" } }
    var symbol: String { switch self { case .task: "checkmark.square"; case .note: "text.alignleft"; case .meeting: "mic" } }
}

struct KnowledgePassage: Identifiable, Equatable, Sendable {
    var id: String
    let kind: KnowledgeKind
    let resourceID: UUID
    var lineID: UUID?
    let title: String
    let content: String
    let date: Date
    var location: String
    var position: Double = 0
    var parameters: [String: String] { ["id": id, "title": String(title.prefix(300)), "content": content] }
}

struct KnowledgeSearchResult: Sendable {
    var sources: [KnowledgePassage] = []
    var matchingPassages = 0
    var unreadableDocuments = 0
}

/// Immutable snapshots are read on a utility task, only after an explicit question.
/// DeferredDocument protects its immutable read cache with a lock.
struct KnowledgeCorpus: @unchecked Sendable {
    var tasks: [Task]
    var notes: [Note]
    var meetings: [MeetingRecord]
    var currentList: String?
    var now = Date()
    var calendar = Calendar.current

    func search(_ rawQuestion: String) throws -> KnowledgeSearchResult {
        var question = rawQuestion
        if let currentList {
            question = question.replacingOccurrences(of: "这个项目", with: currentList)
                .replacingOccurrences(of: "当前清单", with: currentList)
        }
        let filter = KnowledgeQuery(question, now: now, calendar: calendar)
        var candidates: [(passage: KnowledgePassage, score: Int)] = []
        var result = KnowledgeSearchResult()
        func append(kind: KnowledgeKind, id: UUID, title: String, metadata: String, body: String,
                    date: Date, location: String, lineID: UUID? = nil, position: Double = 0) throws {
            for (index, chunk) in Self.chunks(body).enumerated() {
                try _Concurrency.Task.checkCancellation()
                let score = filter.score(title: title + " " + location, body: chunk)
                guard score > 0 else { continue }
                let content = String((metadata + "\n" + chunk).prefix(2400))
                candidates.append((KnowledgePassage(id: "\(kind.rawValue)-\(id)-\(lineID?.uuidString ?? "body")-\(index)",
                    kind: kind, resourceID: id, lineID: lineID, title: title, content: content,
                    date: date, location: location, position: position + Double(index)), score))
            }
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HH:mm"
        func date(_ value: Date?) -> String { value.map { formatter.string(from: $0) } ?? "未设置" }
        if filter.includes(kind: .task) {
            for task in tasks where !task.isNoteTask && task.deletedAt == nil && task.skippedAt == nil && !task.isConverted && !task.isAbandoned {
                try _Concurrency.Task.checkCancellation()
                guard filter.completed == nil || (task.status == .completed) == filter.completed else { continue }
                let relevantDate = filter.completed == true ? task.completedAt : task.schedule.dueAt ?? task.schedule.deadlineAt
                guard filter.includes(relevantDate) else { continue }
                guard filter.couldMatch(task.document, title: task.title + " " + task.list.name) else { continue }
                do {
                    let body = try task.document.materialized().plainText
                    let title = task.title.isEmpty ? "无标题任务" : task.title
                    let metadata = "任务：\(String(title.prefix(200)))\n清单：\(String(task.list.name.prefix(150)))\n状态：\(task.isClosed ? "已完成" : "未完成")\n重要性：\(task.priority.title)\n安排日期：\(date(task.schedule.dueAt))\n截止日期：\(date(task.schedule.deadlineAt))\n完成时间：\(date(task.completedAt))"
                    try append(kind: .task, id: task.id, title: title, metadata: metadata,
                        body: body.isEmpty ? "任务标题：" + title : body,
                        date: task.updatedAt, location: task.list.name)
                } catch is CancellationError { throw CancellationError() }
                catch { result.unreadableDocuments += 1 }
            }
        }
        if filter.includes(kind: .note) {
            for note in notes where note.deletedAt == nil {
                try _Concurrency.Task.checkCancellation()
                guard filter.includes(note.updatedAt) else { continue }
                guard filter.couldMatch(note.document, title: note.title + " " + note.folder) else { continue }
                do {
                    let body = try note.document.materialized().plainText
                    try append(kind: .note, id: note.id, title: note.title.isEmpty ? "未命名笔记" : note.title,
                        metadata: "笔记：\(String(note.title.prefix(200)))\n文件夹：\(String(note.folder.prefix(150)))\n编辑时间：\(date(note.updatedAt))",
                        body: body, date: note.updatedAt, location: note.folder)
                } catch is CancellationError { throw CancellationError() }
                catch { result.unreadableDocuments += 1 }
            }
        }
        if filter.includes(kind: .meeting) {
            for meeting in meetings {
                try _Concurrency.Task.checkCancellation()
                guard filter.includes(meeting.createdAt) else { continue }
                let metadata = "会议：\(String(meeting.title.prefix(200)))\n会议时间：\(date(meeting.createdAt))"
                if !meeting.minutes.isEmpty {
                    try append(kind: .meeting, id: meeting.id, title: meeting.title,
                        metadata: metadata + (meeting.minutesIsManual ? "\n以下为手工编辑的会议纪要：" : "\n以下为会议纪要（整理参考）："),
                        body: meeting.minutes, date: meeting.createdAt, location: "纪要")
                }
                for line in meeting.transcript {
                    let time = Self.timestamp(line.offset)
                    try append(kind: .meeting, id: meeting.id, title: meeting.title,
                        metadata: metadata + "\n定稿发言 · \(time) · \(line.speakerDisplayName)",
                        body: line.text, date: meeting.createdAt, location: time, lineID: line.id, position: line.offset)
                }
            }
        }
        if filter.latestMeeting, let latest = candidates.max(by: { $0.passage.date < $1.passage.date })?.passage.resourceID {
            candidates.removeAll { $0.passage.resourceID != latest }
        }
        candidates.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.passage.date != $1.passage.date { return $0.passage.date > $1.passage.date }
            if $0.passage.resourceID == $1.passage.resourceID {
                if $0.passage.kind == .meeting {
                    if ($0.passage.location == "纪要") != ($1.passage.location == "纪要") { return $0.passage.location == "纪要" }
                    if $0.passage.position != $1.passage.position { return $0.passage.position > $1.passage.position }
                } else if $0.passage.position != $1.passage.position { return $0.passage.position < $1.passage.position }
            }
            return $0.passage.id < $1.passage.id
        }
        result.matchingPassages = candidates.count
        // Keep enough diversity for a cross-resource answer. Long documents can
        // contribute a second passage, without taking the entire context.
        var counts: [UUID: Int] = [:]
        for candidate in candidates {
            let source = candidate.passage
            guard counts[source.resourceID, default: 0] < (filter.latestMeeting ? 8 : 2) else { continue }
            counts[source.resourceID, default: 0] += 1
            var selected = source; selected.id = "S\(result.sources.count + 1)"
            result.sources.append(selected)
            if result.sources.count == 8 { break }
        }
        return result
    }

    static func chunks(_ text: String) -> [String] {
        guard !text.isEmpty else { return [""] }
        var result: [String] = [], start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: 1400, limitedBy: text.endIndex) ?? text.endIndex
            result.append(String(text[start..<end]))
            guard end < text.endIndex else { break }
            start = text.index(end, offsetBy: -120, limitedBy: start) ?? end
        }
        return result
    }

    static func timestamp(_ offset: TimeInterval) -> String {
        let seconds = max(0, Int(offset))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct KnowledgeQuery {
    var kinds: Set<KnowledgeKind> = []
    var completed: Bool?
    var interval: DateInterval?
    var latestMeeting = false
    var terms: [String] = []
    var scopeTerms: [String] = []

    init(_ question: String, now: Date, calendar: Calendar) {
        let openWords = ["未完成", "没完成", "没有完成", "没做完", "未做完", "待完成", "未办", "没做"]
        if openWords.contains(where: question.contains) { completed = false; kinds = [.task] }
        else if question.contains("已完成") || question.contains("已经完成") || question.contains("做完了") {
            // A status check must still retrieve an unfinished task, so its
            // actual metadata can answer "是否已完成" accurately.
            if !["是否", "有没有", "了吗", "了没有"].contains(where: question.contains) { completed = true }
            kinds = [.task]
        } else if question.contains("待办") { completed = false; kinds = [.task] }
        else {
            if question.contains("会议") || question.contains("发言") { kinds.insert(.meeting) }
            if question.contains("笔记") { kinds.insert(.note) }
            if question.contains("任务") { kinds.insert(.task) }
        }
        // A compound status question can also ask about decisions or budgets
        // held in other resources. Do not let one task clause hide that evidence.
        let clauses = question.components(separatedBy: CharacterSet(charactersIn: "，,？?；;。"))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if completed == nil && kinds == [.task] && clauses.count > 1 { kinds = [] }
        latestMeeting = ["上次会议", "上一次会议", "最近一次会议"].contains(where: question.contains) && kinds == [.meeting]
        if question.contains("今天") { interval = calendar.dateInterval(of: .day, for: now) }
        else if question.contains("昨天"), let previous = calendar.date(byAdding: .day, value: -1, to: now) {
            interval = calendar.dateInterval(of: .day, for: previous)
        } else if question.contains("上周"), let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: now) {
            interval = calendar.dateInterval(of: .weekOfYear, for: previous)
        } else if question.contains("本周") || question.contains("这周") { interval = calendar.dateInterval(of: .weekOfYear, for: now) }
        else if question.contains("本月") || question.contains("这个月") { interval = calendar.dateInterval(of: .month, for: now) }
        var text = question.lowercased()
        for phrase in openWords + ["已经完成", "已完成", "做完了", "待办", "上一次会议", "最近一次会议", "上次会议", "本周", "这周", "上周", "本月", "这个月", "今天", "昨天"] {
            text = text.replacingOccurrences(of: phrase, with: " ")
        }
        let stop: Set<String> = ["我", "我们", "的", "了", "有", "在", "和", "与", "是", "还", "要", "定", "做", "什么", "哪些", "怎么", "如何", "怎样", "一下", "帮我", "请", "告诉", "告诉我", "目前", "现在", "还有", "有没有", "是否", "关于", "这个", "这些", "所有", "全部", "项目", "进展", "情况", "内容", "任务", "待办", "笔记", "会议", "发言", "确定", "决定", "总结", "整理", "列出", "查询", "查找", "最近", "上次", "一次", "何时", "什么时候", "时候", "为什么", "需要", "事情", "事项", "项", "可以", "能", "帮", "看看", "个", "之前", "后", "前", "中", "记录", "相关", "最后", "结论"]
        let tokenizer = NLTokenizer(unit: .word); tokenizer.string = text
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range]).trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            if !token.isEmpty, !stop.contains(token), !tokens.contains(token) { tokens.append(token) }
            return true
        }
        terms = tokens
        scopeTerms = tokens.filter { question.lowercased().contains($0 + "项目") || question.lowercased().contains($0 + "计划") }
    }

    func includes(_ date: Date?) -> Bool {
        guard let interval else { return true }
        guard let date else { return false }
        return date >= interval.start && date < interval.end
    }

    func includes(kind: KnowledgeKind) -> Bool { kinds.isEmpty || kinds.contains(kind) }

    func score(title: String, body: String) -> Int {
        guard !terms.isEmpty else { return 1 }
        let title = title.lowercased(), body = body.lowercased()
        guard scopeTerms.isEmpty || scopeTerms.contains(where: { title.contains($0) || body.contains($0) }) else { return 0 }
        var score = 0, matched = 0
        for term in terms {
            if title.contains(term) { score += 10; matched += 1 }
            else if body.contains(term) { score += 3; matched += 1 }
        }
        return matched >= min(2, terms.count) ? score : 0
    }

    func couldMatch(_ document: NativeDocument, title: String) -> Bool {
        guard !terms.isEmpty else { return true }
        let title = title.lowercased()
        guard scopeTerms.isEmpty || scopeTerms.contains(where: { title.contains($0) || document.matches($0, lowercase: true) }) else { return false }
        let matched = terms.filter { title.contains($0) || document.matches($0, lowercase: true) }.count
        return matched >= min(2, terms.count)
    }
}
