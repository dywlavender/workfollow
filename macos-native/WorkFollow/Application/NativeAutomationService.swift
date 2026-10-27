import Foundation

@MainActor
final class NativeAutomationService {
    let tasks: TaskWorkspaceModel
    let notes: NotesWorkspaceModel
    let directory: URL
    init(tasks: TaskWorkspaceModel, notes: NotesWorkspaceModel, directory: URL) {
        self.tasks = tasks; self.notes = notes; self.directory = directory
    }
    func execute(_ request: AutomationRequest) throws -> AutomationValue {
        guard request.version == 1, let allowed = AutomationInvocation.options[request.operation],
              Set(request.arguments.keys).isSubset(of: allowed) else {
            throw AutomationFailure.argument("不支持的操作或协议版本，请更新 CLI 与 App。")
        }
        let args = request.arguments
        if let result = try executeOrganization(request) { return result }
        switch request.operation {
        case "status":
            return .object(["protocolVersion": .number(1), "storageDirectory": .string(directory.path),
                            "appVersion": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"),
                            "processID": .number(Double(ProcessInfo.processInfo.processIdentifier))])
        case "task.lists": return .array(tasks.availableListNames.map { .string($0) })
        case "note.folders": return .array((["未归档"] + notes.folders).map { .string($0) })
        case "task.list":
            let completed = try boolean(args["completed"])
            let section = try args["section"].map { try automationSection($0, inList: args["list"]) }
            let items = tasks.allTasks.filter {
                $0.kind != .note && $0.deletedAt == nil && $0.skippedAt == nil && !$0.isConverted &&
                (completed == nil || ($0.status == .completed) == completed) &&
                (args["list"] == nil || $0.list.name == args["list"]) &&
                (section == nil || $0.sectionID == section?.id) &&
                (args["query"] == nil || $0.document.matches(args["query"]!, prefix: $0.title))
            }
            return try page(items, args: args) { try taskValue($0, body: false) }
        case "task.get": return try taskValue(task(args), body: true)
        case "task.add":
            let title = try nonempty(args["title"], name: "title")
            let list = try taskList(args["list"] ?? "收集箱")
            let schedule = try schedule(args, base: TaskSchedule())
            let priority = try priority(args["priority"] ?? "none")
            let section = try args["section"].map { try automationSection($0, inList: list.name, requiresActiveList: true) }
            let result = tasks.createDraft(title: title, list: list.name, schedule: schedule, priority: priority,
                tags: [], reminder: nil, repeatFrequency: .never,
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
            let document = args["content"].map { NativeDocument(plainText: $0) }
            _ = try current.document.materialized()
            _ = try accepted(tasks.applyAutomationEdit(current.id, title: title, list: list,
                priority: priority, schedule: schedule, document: document,
                sectionID: section?.id, clearsSection: args["clear-section"] == "true"))
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
        ["task.add", "task.update", "task.complete", "task.reopen", "note.create", "note.update", "note.append"].contains(operation)
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
    private func priority(_ raw: String) throws -> TaskPriority {
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
    private func schedule(_ args: [String: String], base: TaskSchedule) throws -> TaskSchedule {
        var result = base
        if let raw = args["date"] { result.dueAt = try date(raw); result.hasTime = raw.contains("T"); result.dueEndAt = nil }
        if let raw = args["due"] { result.deadlineAt = try date(raw) }
        if args["clear-date"] == "true" { result.dueAt = nil; result.dueEndAt = nil; result.hasTime = false }
        if args["clear-due"] == "true" { result.deadlineAt = nil }
        return result
    }
    private func date(_ raw: String) throws -> Date {
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
