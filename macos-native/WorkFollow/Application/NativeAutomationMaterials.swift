import Foundation

extension NativeAutomationService {
    func automationTiming(_ args: [String: String], task: Task? = nil) throws -> SchedulePlan {
        let schedule = try schedule(args, base: task?.schedule ?? TaskSchedule())
        var reminder = task?.reminderAt, offsets = task?.reminderOffsets ?? []
        if let raw = args["reminder"] { reminder = try date(raw); offsets = [] }
        if let raw = args["reminder-offsets"] {
            offsets = try raw.split(separator: ",").map {
                guard let value = Int($0), value <= 0 else { throw AutomationFailure.argument("提醒偏移使用 0（准时）或负分钟数。") }
                return value
            }
            guard schedule.dueAt != nil else { throw AutomationFailure.argument("相对提醒需要先设置安排日期。") }
            reminder = nil
        }
        if args["clear-reminder"] == "true" { reminder = nil; offsets = [] }
        var frequency = task?.recurrence ?? .never, rule = task?.recurrenceRule
        if let raw = args["repeat"] {
            guard let value = TaskRepeat(rawValue: raw) else { throw AutomationFailure.argument("重复类型无效，请运行 --help。") }
            frequency = value
        }
        if args["clear-repeat"] == "true" { frequency = .never }
        if frequency != .never {
            guard schedule.dueAt != nil else { throw AutomationFailure.argument("重复任务需要安排日期作为起点。") }
            var value = rule ?? RecurrenceRule()
            if let raw = args["repeat-interval"] {
                guard let interval = Int(raw), interval > 0 else { throw AutomationFailure.argument("重复间隔须为正整数。") }
                value.interval = interval
            }
            if let raw = args["repeat-weekdays"] {
                value.weekdays = try raw.split(separator: ",").map {
                    guard let day = Int($0), (1...7).contains(day) else { throw AutomationFailure.argument("星期使用 1（周日）至 7（周六）。") }
                    return day
                }
            }
            if let raw = args["repeat-until"] { value.endDate = try date(raw) }
            if let raw = args["repeat-count"] {
                guard let count = Int(raw), count > 0 else { throw AutomationFailure.argument("重复次数须为正整数。") }
                value.remainingCount = count
            }
            guard let normalized = value.normalized(calendar: tasks.calendar) else { throw AutomationFailure.argument("重复规则无效。") }
            rule = normalized
        } else { rule = nil }
        return SchedulePlan(schedule: schedule, reminder: reminder, reminderOffsets: offsets,
                            frequency: frequency, recurrenceRule: rule)
    }

    func filteredTasks(_ args: [String: String]) throws -> [Task] {
        let completed = try boolean(args["completed"])
        let dateField = try args["date-field"].map { value in
            guard let field = KnowledgeTaskDateField(rawValue: value) else {
                throw AutomationFailure.argument("date-field 须为 schedule、deadline 或 completed。")
            }
            return field
        }
        let section = try args["section"].map { try automationSection($0, inList: args["list"]) }
        let priority = try args["priority"].map(priority)
        let from = try args["from"].map(date)
        let to = try args["to"].map { raw -> Date in
            let value = try date(raw)
            return raw.contains("T") ? value : tasks.calendar.date(byAdding: .day, value: 1, to: value) ?? value
        }
        return tasks.allTasks.filter {
            let task = $0
            let time = dateField.map { $0.date(in: task) }
                ?? (completed == true ? task.completedAt : task.schedule.dueAt ?? task.schedule.deadlineAt)
            return !$0.isNoteTask && $0.deletedAt == nil && $0.skippedAt == nil && !$0.isConverted && !$0.isAbandoned &&
                (completed == nil || ($0.status == .completed) == completed) &&
                (args["list"] == nil || $0.list.name == args["list"]) &&
                (section == nil || $0.sectionID == section?.id) && (priority == nil || $0.priority == priority) &&
                (args["tag"].map { task.tags.contains($0) } ?? true) &&
                (from == nil || time.map { $0 >= from! } == true) &&
                (to == nil || time.map { $0 < to! } == true) &&
                (args["query"] == nil || $0.document.matches(args["query"]!, prefix: $0.title))
        }
    }

    func queryMaterials(_ request: AutomationRequest) throws -> AutomationValue {
        let args = request.arguments
        if request.operation == "knowledge.search" {
            let query = try nonempty(args["query"], name: "query")
            let kind = try args["kind"].map { value in
                guard let kind = KnowledgeKind(rawValue: value) else {
                    throw AutomationFailure.argument("kind 须为 task、note 或 meeting。")
                }
                return kind
            }
            let found = try KnowledgeCorpus(tasks: tasks.allTasks, notes: notes.notes,
                meetings: meetings?.meetings ?? [], currentList: tasks.activeList,
                now: tasks.clock(), calendar: tasks.calendar, index: knowledgeIndex)
                .search(query, scope: .init(kind: kind, list: args["list"], folder: args["folder"], tag: args["tag"]))
            return .object(["matchingPassages": .number(Double(found.matchingPassages)), "sources": .array(found.sources.map { source in
                return .object(["title": .string(source.title), "kind": .string(source.kind.rawValue),
                    "content": .string(source.content), "url": .string(source.url?.absoluteString ?? "")])
            })])
        }
        let all = meetings?.meetings ?? []
        if request.operation == "meeting.list" {
            let matching = all.filter { args["query"] == nil || ($0.title + " " + $0.minutes + " " + $0.transcript.map(\.text).joined(separator: " ")).localizedStandardContains(args["query"]!) }
                .sorted { $0.createdAt > $1.createdAt }
            return try page(matching, args: args) { .object(["id": .string($0.id.uuidString), "title": .string($0.title),
                "date": .string(ISO8601DateFormatter().string(from: $0.createdAt)), "url": .string("workfollow://meeting/\($0.id)")]) }
        }
        guard let id = args["id"].flatMap(UUID.init(uuidString:)), let meeting = all.first(where: { $0.id == id }) else {
            throw AutomationFailure.argument("会议不存在。")
        }
        let lines = meeting.transcript.filter { args["query"] == nil || ($0.speaker + " " + $0.text).localizedStandardContains(args["query"]!) }
        return .object(["id": .string(id.uuidString), "title": .string(meeting.title), "minutes": .string(meeting.minutes),
            "transcript": .array(lines.map { .object(["speaker": .string($0.speakerDisplayName), "text": .string($0.text),
                "offset": .number($0.offset), "url": .string("workfollow://meeting/\(id)?line=\($0.id)")]) })])
    }
}
