import Foundation

@MainActor
final class NativeAutomationService {
    let tasks: TaskWorkspaceModel
    let notes: NotesWorkspaceModel
    let directory: URL
    let meetings: MeetingStore?
    init(tasks: TaskWorkspaceModel, notes: NotesWorkspaceModel, directory: URL, meetings: MeetingStore? = nil) {
        self.tasks = tasks; self.notes = notes; self.directory = directory; self.meetings = meetings
    }
    func execute(_ request: AutomationRequest) throws -> AutomationValue {
        guard Self.writes(request.operation), request.operation != "operation.undo" else { return try executeBody(request) }
        let before = tasks.automationUndoID
        let value = try tasks.automationTransaction { try executeBody(request) }
        if case var .object(fields) = value, let token = tasks.automationUndoID, token != before {
            fields["undoID"] = .string(token.uuidString)
            return .object(fields)
        }
        return value
    }
    private func executeBody(_ request: AutomationRequest) throws -> AutomationValue {
        guard request.version == 1, let allowed = AutomationInvocation.options[request.operation],
              Set(request.arguments.keys).isSubset(of: allowed) else {
            throw AutomationFailure.argument("不支持的操作或协议版本，请更新 CLI 与 App。")
        }
        let args = request.arguments
        if let result = try executeOrganization(request) { return result }
        switch request.operation {
        case "operation.undo":
            let token = try id(args)
            guard tasks.undoAutomation(token) else { throw AutomationFailure.argument("请先撤销更新的操作；这项操作当前不能单独撤销。") }
            return .object(["undoneID": .string(token.uuidString)])
        case "meeting.list", "meeting.get", "knowledge.search": return try queryMaterials(request)
        case "status":
            return .object(["protocolVersion": .number(1), "storageDirectory": .string(directory.path),
                            "appVersion": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"),
                            "processID": .number(Double(ProcessInfo.processInfo.processIdentifier))])
        case "task.lists": return .array(tasks.availableListNames.map { .string($0) })
        case "note.folders": return .array((["未归档"] + notes.folders).map { .string($0) })
        case "task.list":
            let items = try filteredTasks(args)
            return try page(items, args: args) { try taskValue($0, body: false) }
        case "task.count":
            let items = try filteredTasks(args)
            return .object(["total": .number(Double(items.count)),
                            "completed": .number(Double(items.filter { $0.status == .completed }.count)),
                            "active": .number(Double(items.filter { $0.status != .completed }.count))])
        case "task.get": return try taskValue(task(args), body: true)
        case "task.add":
            let title = try nonempty(args["title"], name: "title")
            let list = try taskList(args["list"] ?? "收集箱")
            let timing = try automationTiming(args)
            let priority = try priority(args["priority"] ?? "none")
            let section = try args["section"].map { try automationSection($0, inList: list.name, requiresActiveList: true) }
            let result = tasks.createDraft(title: title, list: list.name, schedule: timing.schedule, priority: priority,
                tags: [], reminder: timing.reminder, reminderOffsets: timing.reminderOffsets,
                repeatFrequency: timing.frequency, recurrenceRule: timing.recurrenceRule,
                document: NativeDocument(plainText: args["content"] ?? ""), selectCreatedTask: false, sectionID: section?.id)
            let id = try accepted(result)
            return try taskValue(try requiredTask(id), body: true)
        case "task.update":
            let current = try task(args)
            try checkVersion(args, date: current.updatedAt)
            guard !Set(args.keys).subtracting(["id", "version"]).isEmpty else { throw AutomationFailure.argument("没有要修改的字段。") }
            let title = try args["title"].map { try nonempty($0, name: "title") }
            let list = try args["list"].map(taskList)
            guard args["section"] == nil || args["clear-section"] == nil else {
                throw AutomationFailure.argument("section 与 clear-section 不能同时使用。")
            }
            let section = try args["section"].map {
                try automationSection($0, inList: list?.name ?? current.list.name, requiresActiveList: true)
            }
            let priority = try args["priority"].map(priority)
            let schedule = try schedule(args, base: current.schedule)
            let timing = try automationTiming(args, task: current)
            let document = args["content"].map { NativeDocument(plainText: $0) }
            _ = try current.document.materialized()
            _ = try accepted(tasks.applyAutomationEdit(current.id, title: title, list: list,
                priority: priority, schedule: schedule, document: document,
                sectionID: section?.id, clearsSection: args["clear-section"] == "true", timing: timing))
            return try taskValue(try requiredTask(current.id), body: true)
        case "task.complete", "task.reopen":
            let current = try task(args)
            try checkVersion(args, date: current.updatedAt)
            _ = try accepted(request.operation == "task.complete" ? tasks.complete(current.id) : tasks.restore(current.id))
            return try taskValue(try requiredTask(current.id), body: true)
        case "note.list":
            let items = notes.notes.filter {
                $0.deletedAt == nil && (args["folder"] == nil || $0.folder == args["folder"]) &&
                (args["query"] == nil || $0.document.matches(args["query"]!, prefix: $0.title))
            }
            return try page(items, args: args) { try noteValue($0, body: false) }
        case "note.get": return try noteValue(note(args), body: true)
        case "note.create":
            let folder = try noteFolder(args["folder"] ?? "未归档")
            let id = notes.create(folder: folder, select: false)
            notes.edit(id) {
                $0.title = args["title"] ?? ""
                $0.document = NativeDocument(plainText: args["content"] ?? "")
            }
            return try noteValue(try requiredNote(id), body: true)
        case "note.update", "note.append":
            let current = try note(args)
            try checkVersion(args, date: current.updatedAt)
            guard !Set(args.keys).subtracting(["id", "version"]).isEmpty else { throw AutomationFailure.argument("没有要修改的字段。") }
            let folder = try args["folder"].map(noteFolder)
            var document: NativeDocument?
            if let content = args["content"] {
                guard try current.originalContentValue() == nil else {
                    throw AutomationFailure(code: "read_only", message: "该笔记保留导入原文，请在 App 中创建可编辑副本后再修改正文。")
                }
                let existing = try current.document.materialized()
                if request.operation == "note.append" {
                    guard !content.isEmpty else { throw AutomationFailure.argument("追加内容不能为空。") }
                    let addition = NativeDocument(plainText: content)
                    document = existing.isEmpty ? addition : NativeDocument(blocks: existing.blocks + addition.blocks)
                } else { document = NativeDocument(plainText: content) }
            } else if request.operation == "note.append" { throw AutomationFailure.argument("请提供追加内容。") }
            notes.edit(current.id) {
                if let title = args["title"] { $0.title = title }
                if let folder { $0.folder = folder; $0.folderID = notes.folderID(named: folder) }
                if let document { $0.document = document }
            }
            return try noteValue(try requiredNote(current.id), body: true)
        default: throw AutomationFailure.argument("未知操作。")
        }
    }
    static func writes(_ operation: String) -> Bool {
        ["task.add", "task.update", "task.complete", "task.reopen", "note.create", "note.update", "note.append", "operation.undo"].contains(operation)
            || organizationWrites.contains(operation)
    }
    private func id(_ args: [String: String]) throws -> UUID {
        guard let raw = args["id"], let id = UUID(uuidString: raw) else { throw AutomationFailure.argument("请提供有效的 id。") }
        return id
    }
    private func task(_ args: [String: String]) throws -> Task { try requiredTask(id(args)) }
    private func requiredTask(_ id: UUID) throws -> Task {
        guard let value = tasks.task(for: id), value.kind != .note, value.deletedAt == nil, value.skippedAt == nil, !value.isConverted else {
            throw AutomationFailure(code: "not_found", message: "任务不存在或已移除。")
        }
        return value
    }
    private func note(_ args: [String: String]) throws -> Note { try requiredNote(id(args)) }
    private func requiredNote(_ id: UUID) throws -> Note {
        guard let value = notes.notes.first(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw AutomationFailure(code: "not_found", message: "笔记不存在或已移除。")
        }
        return value
    }
    private func checkVersion(_ args: [String: String], date: Date) throws {
        guard args["version"] == String(date.timeIntervalSinceReferenceDate) else {
            throw AutomationFailure(code: "version_conflict", message: "记录已更新，或缺少版本；请重新 get 后使用最新 version。")
        }
    }
    func nonempty(_ value: String?, name: String) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AutomationFailure.argument("\(name) 不能为空。") }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func taskList(_ name: String) throws -> TaskList {
        guard tasks.availableListNames.contains(name), !tasks.isListArchived(name) else {
            throw AutomationFailure.argument("任务清单不存在或已归档；请先运行 task lists。")
        }
        return TaskList(name: name)
    }
    private func noteFolder(_ name: String) throws -> String {
        guard name == "未归档" || notes.folders.contains(name) else { throw AutomationFailure.argument("笔记文件夹不存在；请先运行 note folders。") }
        return name
    }
    func priority(_ raw: String) throws -> TaskPriority {
        switch raw.lowercased() {
        case "none": return .none
        case "low": return .low
        case "medium": return .medium
        case "high": return .high
        default: throw AutomationFailure.argument("priority 可选 none、low、medium、high。")
        }
    }
    func boolean(_ raw: String?) throws -> Bool? {
        guard let raw else { return nil }
        switch raw { case "true": return true; case "false": return false; default: throw AutomationFailure.argument("completed 须为 true 或 false。") }
    }
    func schedule(_ args: [String: String], base: TaskSchedule) throws -> TaskSchedule {
        var result = base
        if let raw = args["date"] { result.dueAt = try date(raw); result.hasTime = raw.contains("T"); result.dueEndAt = nil }
        if let raw = args["due"] { result.deadlineAt = try date(raw) }
        if args["clear-date"] == "true" { result.dueAt = nil; result.dueEndAt = nil; result.hasTime = false }
        if args["clear-due"] == "true" { result.deadlineAt = nil }
        return result
    }
    func date(_ raw: String) throws -> Date {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = iso.date(from: raw) { return value }
        iso.formatOptions = [.withInternetDateTime]
        if let value = iso.date(from: raw) { return value }
        let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.calendar = Calendar(identifier: .gregorian)
        day.dateFormat = "yyyy-MM-dd"; day.isLenient = false
        if let value = day.date(from: raw), day.string(from: value) == raw { return value }
        throw AutomationFailure.argument("日期须为 YYYY-MM-DD 或带时区的 ISO8601 时间。")
    }
    private func accepted(_ result: TaskActionResult) throws -> UUID {
        if case let .success(id) = result { return id }
        throw AutomationFailure(code: "operation_failed", message: "任务操作未完成：\(result)")
    }
    func page<T>(_ items: [T], args: [String: String], encode: (T) throws -> AutomationValue) throws -> AutomationValue {
        let limit = try integer(args["limit"] ?? "20", minimum: 1, maximum: 100)
        let offset = try integer(args["offset"] ?? "0", minimum: 0, maximum: Int.max)
        let end = min(items.count, offset > items.count ? items.count : offset + min(limit, items.count - offset))
        let page = offset < items.count ? Array(items[offset..<end]) : []
        return .object(["items": .array(try page.map(encode)), "total": .number(Double(items.count)),
                        "offset": .number(Double(offset)), "limit": .number(Double(limit))])
    }
    private func integer(_ raw: String, minimum: Int, maximum: Int) throws -> Int {
        guard let value = Int(raw), (minimum...maximum).contains(value) else { throw AutomationFailure.argument("分页参数无效，limit 须为 1–100，offset 须非负。") }
        return value
    }
    private func optionalDate(_ date: Date?) -> AutomationValue { date.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null }
    private func taskValue(_ task: Task, body: Bool) throws -> AutomationValue {
        var value: [String: AutomationValue] = ["id": .string(task.id.uuidString), "title": .string(task.title),
            "list": .string(task.list.name), "priority": .string(String(describing: task.priority)),
            "group": tasks.folderName(forList: task.list.name).map { .string($0) } ?? .null,
            "sectionID": task.sectionID.map { .string($0) } ?? .null,
            "sectionTitle": task.sectionID.flatMap { id in tasks.listSections.first { $0.id == id }?.title }.map { .string($0) } ?? .null,
            "parentID": task.parentID.map { .string($0.uuidString) } ?? .null,
            "sourceNoteID": task.sourceNoteID.map { .string($0.uuidString) } ?? .null,
            "sourceMeetingID": task.sourceMeetingID.map { .string($0.uuidString) } ?? .null,
            "completed": .bool(task.status == .completed), "date": optionalDate(task.schedule.dueAt), "due": optionalDate(task.schedule.deadlineAt),
            "reminder": optionalDate(task.reminderAt),
            "reminderOffsets": .array((task.reminderOffsets ?? []).map { .number(Double($0)) }),
            "repeat": .string(task.recurrence.rawValue),
            "repeatInterval": .number(Double(task.recurrenceRule?.interval ?? 1)),
            "repeatWeekdays": .array((task.recurrenceRule?.weekdays ?? []).map { .number(Double($0)) }),
            "repeatUntil": optionalDate(task.recurrenceRule?.endDate),
            "repeatCount": task.recurrenceRule?.remainingCount.map { .number(Double($0)) } ?? .null,
            "version": .string(String(task.updatedAt.timeIntervalSinceReferenceDate)), "url": .string(NativeResourceLink.task(task.id).url.absoluteString)]
        if body { value["content"] = .string(try task.document.materialized().plainText) }
        return .object(value)
    }
    private func noteValue(_ note: Note, body: Bool) throws -> AutomationValue {
        var value: [String: AutomationValue] = ["id": .string(note.id.uuidString), "title": .string(note.title),
            "folder": .string(note.folder), "version": .string(String(note.updatedAt.timeIntervalSinceReferenceDate)),
            "url": .string(NativeResourceLink.note(note.id).url.absoluteString)]
        if body { value["content"] = .string(try note.document.materialized().plainText) }
        return .object(value)
    }
}
