import CryptoKit
import Foundation

// MARK: - 解析错误（文案与 Flutter 迁移层一致）

enum MigrationFormatError: LocalizedError, Equatable {
    case invalidJSON
    case notJSONObject
    case unknownFormat
    case unsupportedVersion(Int)
    case missingField(String)
    case malformedCollection
    case malformedRecord
    case invalidAttachmentName(String)
    case corruptAttachment(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "无法读取这个文件，请重新导出后再试。"
        case .notJSONObject: return "导入文件必须是 JSON 对象。"
        case .unknownFormat: return "这不是打勾个人版的数据文件。"
        case .unsupportedVersion(let version): return "暂不支持数据文件版本 \(version)，请先升级 macOS 版。"
        case .missingField(let key): return "数据文件缺少有效的 \(key)。"
        case .malformedCollection: return "数据文件中的集合字段格式不正确。"
        case .malformedRecord: return "数据文件中的记录格式不正确。"
        case .invalidAttachmentName(let name): return "附件名称无效：\(name)"
        case .corruptAttachment(let name): return "附件数据无法解码：\(name)"
        }
    }
}

// MARK: - 迁移文件记录（workfollow-personal-migration v1/v2/v3）

struct MigrationListRecord: Equatable {
    let id: String?
    let name: String
    let sortOrder: Int
    let isProtected: Bool
    let color: String?
    let isPinned: Bool
}

struct MigrationFolderRecord: Equatable {
    let id: String
    let parentID: String?
    let name: String
    let sortOrder: Int
    let createdAt: String?
    let updatedAt: String?
}

/// v1/v2 的旧版子任务（只读兼容；v3 导出永远写 parentTaskId/childOrder）。
struct MigrationSubtaskRecord: Equatable {
    let id: String
    let title: String
    let completed: Bool
}

/// Flutter recurrenceConfig 里可映射到 RecurrenceRule 的键（count/endDate/dayOfMonth/weekday/month）。
struct MigrationRecurrenceConfig: Equatable {
    var count: Int?
    var endDate: String?
    var dayOfMonth: Int?
    var weekday: Int?
    var month: Int?
}

struct MigrationTaskRecord: Equatable {
    let id: String
    let title: String
    let description: String?
    let status: String
    let priority: String
    let dueAt: String?
    /// 时间段的结束（安排结束）。与 `deadlineAt`（截止日期）是两个字段：
    /// 前者定义区间，后者只是截止点，日历色带只认前者。
    let dueEndAt: String?
    let deadlineAt: String?
    let hasDueTime: Bool?
    let reminderAt: String?
    let reminderOffsets: [Int]
    let recurrenceType: String
    let recurrenceConfig: MigrationRecurrenceConfig?
    let listName: String
    let tags: [String]
    let subtasks: [MigrationSubtaskRecord]
    let parentTaskId: String?
    let childOrder: Int
    let sourceNoteId: String?
    let attachments: [String]
    let createdAt: String?
    let updatedAt: String?
    let completedAt: String?
    let deletedAt: String?
    let skippedAt: String?
    let isPinned: Bool
    let abandonedAt: String?
    let convertedNoteId: String?
    /// 原生模型没有对应字段的键（bucket/timeLabel/contentJson），或只做了降级
    /// 映射的键（reminderOffsets），降级映射时计数。`dueEndAt` 已迁入
    /// `TaskSchedule.dueEndAt`，不再计入。
    let ignoredKeys: Set<String>
}

struct MigrationNoteRecord: Equatable {
    let id: String
    let folderId: String?
    let title: String
    let plainText: String
    let isFavorite: Bool
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?
    /// contentJson/originalContentJson 非空时为 true：原生只保留纯文本投影。
    let hasRichContent: Bool
}

struct MigrationBundle: Equatable {
    static let personalFormat = "workfollow-personal-migration"
    static let localSnapshotFormat = "workfollow-local-snapshot"
    static let supportedSchemaVersions: Set<Int> = [1, 2, 3]

    let format: String
    let schemaVersion: Int
    let exportedAt: String?
    let lists: [MigrationListRecord]
    let folders: [MigrationFolderRecord]
    let tasks: [MigrationTaskRecord]
    let notes: [MigrationNoteRecord]
    /// 附件名 -> base64。
    let embeddedFiles: [String: String]

    var attachmentCount: Int { embeddedFiles.count }
}

// MARK: - 导入摘要

struct MigrationImportSummary: Equatable {
    var importedTasks = 0
    var skippedTasks = 0
    var importedNotes = 0
    var skippedNotes = 0
    /// 自动新建的清单数。
    var importedLists = 0
    /// 文件夹计数（原生快照没有独立文件夹实体，仅作展示）。
    var importedFolders = 0
    /// v1/v2 旧版 subtasks 展开出的真实任务数。
    var importedLegacyChildren = 0
    /// 降级忽略的字段 -> 出现次数。
    var ignoredFieldCounts: [String: Int] = [:]

    mutating func countIgnored(_ keys: Set<String>) {
        for key in keys { ignoredFieldCounts[key, default: 0] += 1 }
    }
}

// MARK: - 解析 + 映射 + 导出

/// workfollow-personal-migration v1/v2/v3 的读取、导出与合并/替换语义，
/// 对齐 Flutter desktop 的 migration.dart / LocalWorkspaceStore / WorkspaceController。
enum MigrationSnapshot {
    static let inboxListName = "收集箱"
    static let unfiledFolderName = "未归档"
    static let defaultListNames = ["收集箱", "工作", "个人", "学习"]
    /// 旧版子任务的确定性 id 前缀：`legacy-child-{parentId}-{subId}`。
    static let legacyChildPrefix = "legacy-child"

    // MARK: 解析

    static func parse(_ data: Data) throws -> MigrationBundle {
        let object: [String: Any]
        do {
            let raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            guard let dict = raw as? [String: Any] else { throw MigrationFormatError.notJSONObject }
            object = dict
        } catch let error as MigrationFormatError {
            throw error
        } catch {
            throw MigrationFormatError.invalidJSON
        }

        let format = stringValue(object["format"])
        guard format == MigrationBundle.personalFormat || format == MigrationBundle.localSnapshotFormat else {
            throw MigrationFormatError.unknownFormat
        }
        let schemaVersion = intValue(object["schemaVersion"])
        guard MigrationBundle.supportedSchemaVersions.contains(schemaVersion) else {
            throw MigrationFormatError.unsupportedVersion(schemaVersion)
        }

        return MigrationBundle(
            format: format,
            schemaVersion: schemaVersion,
            exportedAt: nullableString(object["exportedAt"]),
            lists: try records(object["lists"], listRecord),
            folders: try records(object["folders"], folderRecord),
            tasks: try records(object["tasks"], taskRecord),
            notes: try records(object["notes"], noteRecord),
            embeddedFiles: embeddedFiles(object["attachmentFiles"])
        )
    }

    private static func listRecord(_ json: [String: Any]) throws -> MigrationListRecord {
        MigrationListRecord(
            id: nullableString(json["id"]),
            name: try requiredString(json, "name"),
            sortOrder: intValue(json["sortOrder"]),
            isProtected: tolerantBool(json["protected"]),
            color: nullableString(json["color"]),
            isPinned: tolerantBool(json["pinned"])
        )
    }

    private static func folderRecord(_ json: [String: Any]) throws -> MigrationFolderRecord {
        MigrationFolderRecord(
            id: try requiredString(json, "id"),
            parentID: nullableString(json["parentId"]),
            name: try requiredString(json, "name"),
            sortOrder: intValue(json["sortOrder"]),
            createdAt: nullableString(json["createdAt"]),
            updatedAt: nullableString(json["updatedAt"])
        )
    }

    private static func subtaskRecord(_ json: [String: Any]) throws -> MigrationSubtaskRecord {
        MigrationSubtaskRecord(
            id: stringValue(json["id"]),
            title: stringValue(json["title"]),
            completed: tolerantBool(json["completed"])
        )
    }

    private static func taskRecord(_ json: [String: Any]) throws -> MigrationTaskRecord {
        var ignored: Set<String> = []
        for key in ["bucket", "timeLabel"] where json[key] != nil && !(json[key] is NSNull) {
            ignored.insert(key)
        }
        if let offsets = json["reminderOffsets"] as? [Any], !offsets.isEmpty { ignored.insert("reminderOffsets") }
        if let content = json["contentJson"], !(content is NSNull) { ignored.insert("contentJson") }

        return MigrationTaskRecord(
            id: try requiredString(json, "id"),
            title: try requiredString(json, "title"),
            description: nullableString(json["description"]),
            status: stringValue(json["status"], fallback: "TODO"),
            priority: stringValue(json["priority"], fallback: "NONE"),
            dueAt: nullableString(json["dueAt"]),
            dueEndAt: nullableString(json["dueEndAt"]),
            deadlineAt: nullableString(json["deadlineAt"]),
            hasDueTime: strictBool(json["hasDueTime"]),
            reminderAt: nullableString(json["reminderAt"]),
            reminderOffsets: sortedIntSet(intList(json["reminderOffsets"])),
            recurrenceType: stringValue(json["recurrenceType"], fallback: "NONE"),
            recurrenceConfig: recurrenceConfig(json["recurrenceConfig"]),
            listName: stringValue(json["listName"], fallback: inboxListName),
            tags: stringList(json["tags"]),
            subtasks: try records(json["subtasks"], subtaskRecord),
            parentTaskId: nullableString(json["parentTaskId"]),
            childOrder: intValue(json["childOrder"]),
            sourceNoteId: nullableString(json["sourceNoteId"]),
            attachments: stringList(json["attachments"]),
            createdAt: nullableString(json["createdAt"]),
            updatedAt: nullableString(json["updatedAt"]),
            completedAt: nullableString(json["completedAt"]),
            deletedAt: nullableString(json["deletedAt"]),
            skippedAt: nullableString(json["skippedAt"]),
            isPinned: tolerantBool(json["isPinned"]),
            abandonedAt: nullableString(json["abandonedAt"]),
            convertedNoteId: nullableString(json["convertedNoteId"]),
            ignoredKeys: ignored
        )
    }

    private static func recurrenceConfig(_ value: Any?) -> MigrationRecurrenceConfig? {
        guard let json = value as? [String: Any] else { return nil }
        var config = MigrationRecurrenceConfig()
        config.count = optionalInt(json["count"])
        config.endDate = nullableString(json["endDate"])
        config.dayOfMonth = optionalInt(json["dayOfMonth"])
        config.weekday = optionalInt(json["weekday"])
        config.month = optionalInt(json["month"])
        return config
    }

    private static func noteRecord(_ json: [String: Any]) throws -> MigrationNoteRecord {
        var hasRichContent = false
        if let content = json["contentJson"] as? [String: Any], !content.isEmpty { hasRichContent = true }
        if let original = json["originalContentJson"] as? [String: Any], !original.isEmpty { hasRichContent = true }

        return MigrationNoteRecord(
            id: try requiredString(json, "id"),
            folderId: nullableString(json["folderId"]),
            title: try requiredString(json, "title"),
            plainText: stringValue(json["plainText"]),
            isFavorite: tolerantBool(json["isFavorite"]),
            createdAt: nullableString(json["createdAt"]),
            updatedAt: nullableString(json["updatedAt"]),
            deletedAt: nullableString(json["deletedAt"]),
            hasRichContent: hasRichContent
        )
    }

    private static func embeddedFiles(_ value: Any?) -> [String: String] {
        guard let json = value as? [String: Any] else { return [:] }
        var files: [String: String] = [:]
        for (key, value) in json {
            if let base64 = value as? String { files[key] = base64 }
        }
        return files
    }

    // MARK: 宽容取值（对齐 Dart jsonDecode 后的取值行为）

    private static func stringValue(_ value: Any?, fallback: String = "") -> String {
        nullableString(value) ?? fallback
    }

    private static func nullableString(_ value: Any?) -> String? {
        guard value != nil, !(value is NSNull) else { return nil }
        if let string = value as? String { return string }
        return String(describing: value!)
    }

    private static func requiredString(_ json: [String: Any], _ key: String) throws -> String {
        guard let value = nullableString(json[key]), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MigrationFormatError.missingField(key)
        }
        return value
    }

    private static func intValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    private static func optionalInt(_ value: Any?) -> Int? {
        guard value != nil, !(value is NSNull) else { return nil }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    /// Dart 的宽容布尔：bool 原样；数字非 0；字符串 "true"。
    private static func tolerantBool(_ value: Any?) -> Bool {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
            return number.intValue != 0
        }
        if let string = value as? String { return string.lowercased() == "true" }
        return false
    }

    /// Dart 的严格布尔：仅 true/false（hasDueTime 语义）。
    private static func strictBool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber else { return nil }
        guard CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func stringList(_ value: Any?) -> [String] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { item in
            if let string = item as? String { return string }
            if let number = item as? NSNumber { return number.stringValue }
            if item is NSNull { return nil }
            return String(describing: item)
        }
    }

    private static func intList(_ value: Any?) -> [Int] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { item in
            if let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.intValue }
            if let string = item as? String { return Int(string) }
            return nil
        }
    }

    private static func sortedIntSet(_ values: [Int]) -> [Int] {
        Array(Set(values)).sorted()
    }

    private static func records<T>(_ value: Any?, _ transform: ([String: Any]) throws -> T) throws -> [T] {
        guard let value, !(value is NSNull) else { return [] }
        guard let array = value as? [Any] else { throw MigrationFormatError.malformedCollection }
        return try array.map { item in
            guard let dict = item as? [String: Any] else { throw MigrationFormatError.malformedRecord }
            return try transform(dict)
        }
    }

    // MARK: 确定性 ID 映射（Flutter 字符串 id <-> 原生 UUID）

    /// Flutter 数据的 id 是任意字符串，原生 Task.id 是 UUID：
    /// 本身就是 UUID 的直接用；否则用 MD5("workfollow-migration:" + id) 生成
    /// 确定性 UUID——同一条旧数据每次导入得到同一 id，重复导入才会被"同 ID 跳过"。
    static func uuid(forRawID raw: String) -> UUID {
        if let existing = UUID(uuidString: raw) { return existing }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = UUID(uuidString: trimmed) { return existing }
        let digest = Insecure.MD5.hash(data: Data("workfollow-migration:".utf8) + Data(trimmed.utf8))
        var bytes = Array(digest)
        bytes[6] = (bytes[6] & 0x0F) | 0x30 // version 3
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let formatted = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
        return UUID(uuidString: formatted)!
    }

    /// v1/v2 旧版子任务的确定性原始 id，再经 uuid(forRawID:) 落到 UUID。
    static func legacyChildRawID(parentID: String, subtaskID: String, index: Int) -> String {
        subtaskID.isEmpty
            ? "\(legacyChildPrefix)-\(parentID)-index-\(index)"
            : "\(legacyChildPrefix)-\(parentID)-\(subtaskID)"
    }

    // MARK: bundle -> 原生快照

    /// 合并导入：保留本机内容，同 ID 跳过，未知清单自动创建。
    /// 附件文件须先经 restoreEmbeddedFiles 写盘，再传 names。
    static func merged(_ bundle: MigrationBundle,
                       into local: NativeWorkspaceSnapshot,
                       attachmentNames: Set<String>,
                       now: Date = Date()) -> (snapshot: NativeWorkspaceSnapshot, summary: MigrationImportSummary) {
        var summary = MigrationImportSummary()
        summary.importedFolders = bundle.folders.count

        var lists = local.taskLists ?? []
        for record in bundle.lists.sorted(by: { $0.sortOrder < $1.sortOrder })
        where !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !lists.contains(record.name) {
            lists.append(record.name)
            summary.importedLists += 1
        }

        var localIDs = Set(local.tasks.map(\.id))
        var importedTasks: [Task] = []
        var legacyChildren: [Task] = []
        for record in bundle.tasks {
            let id = uuid(forRawID: record.id)
            guard localIDs.insert(id).inserted else {
                summary.skippedTasks += 1
                summary.countIgnored(record.ignoredKeys)
                continue
            }
            summary.countIgnored(record.ignoredKeys)
            importedTasks.append(task(from: record, attachmentNames: attachmentNames, now: now))
            for child in legacyChildTasks(from: record, now: now) {
                if localIDs.insert(child.id).inserted {
                    legacyChildren.append(child)
                    summary.importedLegacyChildren += 1
                }
            }
        }
        for name in (importedTasks + legacyChildren).map({ $0.list.name }) where !lists.contains(name) {
            lists.append(name)
            summary.importedLists += 1
        }

        var localNoteIDs = Set(local.notes.map(\.id))
        var importedNotes: [Note] = []
        for record in bundle.notes {
            let id = uuid(forRawID: record.id)
            guard localNoteIDs.insert(id).inserted else {
                summary.skippedNotes += 1
                continue
            }
            if record.hasRichContent { summary.countIgnored(["contentJson"]) }
            importedNotes.append(note(from: record, bundle: bundle, now: now))
        }

        let snapshot = NativeWorkspaceSnapshot(
            tasks: importedTasks + legacyChildren + local.tasks,
            notes: importedNotes + local.notes,
            taskLists: normalizedListNames(lists))
        summary.importedTasks = importedTasks.count + legacyChildren.count
        summary.importedNotes = importedNotes.count
        return (snapshot, summary)
    }

    /// 清空本机后导入：以文件内容为准（首次导入 / 恢复快照的逃生门）。
    static func replaced(_ bundle: MigrationBundle,
                         attachmentNames: Set<String>,
                         now: Date = Date()) -> (snapshot: NativeWorkspaceSnapshot, summary: MigrationImportSummary) {
        var summary = MigrationImportSummary()
        summary.importedFolders = bundle.folders.count

        var lists = bundle.lists
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .map(\.name)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if lists.isEmpty { lists = defaultListNames }

        var ids = Set<UUID>()
        var tasks: [Task] = []
        for record in bundle.tasks {
            let id = uuid(forRawID: record.id)
            guard ids.insert(id).inserted else { continue }
            summary.countIgnored(record.ignoredKeys)
            tasks.append(task(from: record, attachmentNames: attachmentNames, now: now))
            for child in legacyChildTasks(from: record, now: now) {
                if ids.insert(child.id).inserted {
                    tasks.append(child)
                    summary.importedLegacyChildren += 1
                }
            }
        }
        for name in tasks.map({ $0.list.name }) where !lists.contains(name) { lists.append(name) }

        var notes: [Note] = []
        for record in bundle.notes {
            if record.hasRichContent { summary.countIgnored(["contentJson"]) }
            notes.append(note(from: record, bundle: bundle, now: now))
        }

        let snapshot = NativeWorkspaceSnapshot(tasks: tasks, notes: notes, taskLists: normalizedListNames(lists))
        summary.importedTasks = tasks.count
        summary.importedNotes = notes.count
        summary.importedLists = lists.count
        return (snapshot, summary)
    }

    /// 收集箱永远在最前，其余按出现顺序去重。
    static func normalizedListNames(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in [inboxListName] + raw {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private static func task(from record: MigrationTaskRecord,
                             attachmentNames: Set<String>,
                             now: Date) -> Task {
        let due = parseDate(record.dueAt)
        let hasTime = record.hasDueTime ?? inferredHasTime(due)
        let skipped = record.status.uppercased() == "SKIPPED" || record.skippedAt != nil
        let completed = !skipped && record.status.uppercased() == "DONE"
        let status = record.status.uppercased() == "ABANDONED"
        let skippedAt = parseDate(record.skippedAt)
            ?? (record.status.uppercased() == "SKIPPED" ? (parseDate(record.updatedAt) ?? now) : nil)
        let abandonedAt = parseDate(record.abandonedAt) ?? (status ? (parseDate(record.updatedAt) ?? now) : nil)

        return Task(
            id: uuid(forRawID: record.id),
            title: record.title,
            document: (record.description?.isEmpty ?? true) ? .empty : NativeDocument(plainText: record.description ?? ""),
            tags: record.tags,
            recurrence: recurrence(for: record.recurrenceType),
            recurrenceRule: recurrenceRule(for: record.recurrenceType, config: record.recurrenceConfig),
            reminderAt: parseDate(record.reminderAt),
            attachments: attachments(named: record.attachments, in: attachmentNames),
            list: TaskList(name: record.listName),
            priority: priority(for: record.priority),
            schedule: TaskSchedule(dueAt: due, hasTime: hasTime,
                                   dueEndAt: parseDate(record.dueEndAt),
                                   deadlineAt: parseDate(record.deadlineAt)),
            status: completed ? .completed : .active,
            parentID: record.parentTaskId.map(uuid(forRawID:)),
            childOrder: record.childOrder,
            createdAt: parseDate(record.createdAt) ?? now,
            updatedAt: parseDate(record.updatedAt) ?? now,
            completedAt: parseDate(record.completedAt),
            deletedAt: parseDate(record.deletedAt),
            isPinned: record.isPinned,
            abandonedAt: abandonedAt,
            skippedAt: skippedAt,
            convertedNoteID: record.convertedNoteId.map(uuid(forRawID:)),
            sourceNoteID: record.sourceNoteId.map(uuid(forRawID:)))
    }

    /// v1/v2 subtasks 数组展开为真实任务（确定性 id、childOrder = 下标、保留完成标记）。
    private static func legacyChildTasks(from record: MigrationTaskRecord, now: Date) -> [Task] {
        guard !record.subtasks.isEmpty else { return [] }
        return record.subtasks.enumerated().map { index, sub in
            Task(
                id: uuid(forRawID: legacyChildRawID(parentID: record.id, subtaskID: sub.id, index: index)),
                title: sub.title,
                tags: [],
                list: TaskList(name: record.listName),
                priority: .none,
                schedule: TaskSchedule(),
                status: sub.completed ? .completed : .active,
                parentID: uuid(forRawID: record.id),
                childOrder: index,
                createdAt: parseDate(record.createdAt) ?? now,
                updatedAt: parseDate(record.updatedAt) ?? now)
        }
    }

    private static func note(from record: MigrationNoteRecord, bundle: MigrationBundle, now: Date) -> Note {
        Note(
            id: uuid(forRawID: record.id),
            title: record.title,
            document: NativeDocument(plainText: record.plainText),
            folder: folderName(for: record.folderId, in: bundle.folders),
            favorite: record.isFavorite,
            updatedAt: parseDate(record.updatedAt) ?? now,
            deletedAt: parseDate(record.deletedAt))
    }

    private static func folderName(for folderId: String?, in folders: [MigrationFolderRecord]) -> String {
        guard let folderId else { return unfiledFolderName }
        return folders.first { $0.id == folderId }?.name ?? unfiledFolderName
    }

    private static func attachments(named names: [String], in available: Set<String>) -> [NativeAttachment] {
        names.compactMap { name in
            guard available.contains(name) else { return nil }
            return NativeAttachment(id: UUID(), name: name, storedName: name)
        }
    }

    private static func priority(for raw: String) -> TaskPriority {
        switch raw.uppercased() {
        case "LOW": return .low
        case "MEDIUM": return .medium
        case "HIGH": return .high
        default: return .none
        }
    }

    private static func recurrence(for raw: String) -> TaskRepeat {
        switch raw.uppercased() {
        case "DAILY": return .daily
        case "WEEKLY": return .weekly
        case "MONTHLY": return .monthly
        case "YEARLY": return .yearly
        case "WEEKDAYS": return .weekdays
        case "WEEKENDS": return .weekends
        case "WORKDAYS": return .workdays
        case "HOLIDAYS": return .holidays
        default: return .never
        }
    }

    private static func recurrenceRule(for type: String, config: MigrationRecurrenceConfig?) -> RecurrenceRule? {
        guard recurrence(for: type) != .never, let config, config.count != nil || config.endDate != nil
            || config.dayOfMonth != nil || config.weekday != nil || config.month != nil else { return nil }
        var rule = RecurrenceRule()
        rule.remainingCount = config.count
        rule.endDate = parseDate(config.endDate)
        rule.monthDay = config.dayOfMonth
        rule.weekday = config.weekday
        rule.month = config.month
        return rule
    }

    private static func inferredHasTime(_ due: Date?) -> Bool {
        guard let due else { return false }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: due)
        return (parts.hour ?? 0) != 0 || (parts.minute ?? 0) != 0
    }

    // MARK: 附件还原

    /// 把导出文件内嵌的 base64 附件写回附件目录；同名文件已存在则跳过（与 Flutter 一致）。
    @discardableResult
    static func restoreEmbeddedFiles(_ files: [String: String], into directory: URL) throws -> Int {
        guard !files.isEmpty else { return 0 }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var restored = 0
        for (name, base64) in files {
            guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), name != "..", name != "." else {
                throw MigrationFormatError.invalidAttachmentName(name)
            }
            guard let data = Data(base64Encoded: base64) else {
                throw MigrationFormatError.corruptAttachment(name)
            }
            let target = directory.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: target.path) else { continue }
            try data.write(to: target, options: .atomic)
            restored += 1
        }
        return restored
    }

    static func attachmentNames(in directory: URL) -> Set<String> {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return Set(names.filter { !$0.hasPrefix(".") })
    }

    // MARK: 导出（v3：只写 parentTaskId/childOrder，绝不写 subtasks）

    static func exportJSON(from snapshot: NativeWorkspaceSnapshot,
                           attachmentDirectory: URL?,
                           now: Date = Date()) throws -> Data {
        var listNames = snapshot.taskLists ?? []
        for name in snapshot.tasks.map({ $0.list.name }) where !listNames.contains(name) { listNames.append(name) }
        listNames = normalizedListNames(listNames)

        var folderNames: [String] = []
        for note in snapshot.notes {
            let name = note.folder.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != unfiledFolderName, !folderNames.contains(name) else { continue }
            folderNames.append(name)
        }
        let folders: [[String: Any]] = folderNames.enumerated().map { index, name in
            [
                "id": "folder-" + uuid(forRawID: name).uuidString,
                "parentId": NSNull(),
                "name": name,
                "sortOrder": index,
                "createdAt": NSNull(),
                "updatedAt": NSNull(),
            ]
        }

        var payload: [String: Any] = [
            "format": MigrationBundle.personalFormat,
            "schemaVersion": 3,
            "exportedAt": formatDate(now),
            "lists": listNames.enumerated().map { index, name in
                ["id": NSNull(), "name": name, "sortOrder": index, "protected": name == inboxListName]
            },
            "folders": folders,
            "tasks": snapshot.tasks.map(taskRecord),
            "notes": snapshot.notes.map { noteRecord($0, folderNames: folderNames) },
        ]

        var embedded: [String: String] = [:]
        if let attachmentDirectory, let names = try? FileManager.default.contentsOfDirectory(atPath: attachmentDirectory.path) {
            for name in names.sorted() where !name.hasPrefix(".") {
                let url = attachmentDirectory.appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      !isDirectory.boolValue, let data = try? Data(contentsOf: url) else { continue }
                embedded[name] = data.base64EncodedString()
            }
        }
        if !embedded.isEmpty { payload["attachmentFiles"] = embedded }

        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private static func taskRecord(_ task: Task) -> [String: Any] {
        let description = task.document.plainText
        let status: String
        if task.skippedAt != nil {
            status = "SKIPPED"
        } else if task.isAbandoned {
            status = "ABANDONED"
        } else {
            status = task.status == .completed ? "DONE" : "TODO"
        }
        let priorityNames = ["NONE", "LOW", "MEDIUM", "HIGH"]

        var record: [String: Any] = [
            "id": task.id.uuidString,
            "title": task.title,
            "description": description.isEmpty ? NSNull() : description,
            "contentJson": NSNull(),
            "status": status,
            "priority": priorityNames[task.priority.rawValue],
            "dueAt": task.schedule.dueAt.map(formatDate) ?? NSNull(),
            "dueEndAt": task.schedule.dueEndAt.map(formatDate) ?? NSNull(),
            "deadlineAt": task.schedule.deadlineAt.map(formatDate) ?? NSNull(),
            "hasDueTime": task.schedule.dueAt != nil ? task.schedule.hasTime : NSNull(),
            "reminderAt": task.reminderAt.map(formatDate) ?? NSNull(),
            "recurrenceType": recurrenceTypeString(task.recurrence),
            "recurrenceConfig": recurrenceConfigJSON(task) ?? NSNull(),
            "listName": task.list.name,
            "tags": task.tags,
            "sourceNoteId": task.sourceNoteID?.uuidString ?? NSNull(),
            "attachments": task.attachments.map(\.storedName),
            "createdAt": formatDate(task.createdAt),
            "updatedAt": formatDate(task.updatedAt),
            "completedAt": task.completedAt.map(formatDate) ?? NSNull(),
            "deletedAt": task.deletedAt.map(formatDate) ?? NSNull(),
            "skippedAt": task.skippedAt.map(formatDate) ?? NSNull(),
            "isPinned": task.isPinned,
            "abandonedAt": task.abandonedAt.map(formatDate) ?? NSNull(),
            "convertedNoteId": task.convertedNoteID?.uuidString ?? NSNull(),
        ]
        if let parentID = task.parentID { record["parentTaskId"] = parentID.uuidString }
        if task.childOrder > 0 { record["childOrder"] = task.childOrder }
        return record
    }

    private static func noteRecord(_ note: Note, folderNames: [String]) -> [String: Any] {
        let folderID: Any
        if folderNames.contains(note.folder) {
            folderID = "folder-" + uuid(forRawID: note.folder).uuidString
        } else {
            folderID = NSNull()
        }
        return [
            "id": note.id.uuidString,
            "folderId": folderID,
            "title": note.title,
            "contentJson": plainDocumentJSON(note.document.plainText),
            "plainText": note.document.plainText,
            "isFavorite": note.favorite,
            "createdAt": NSNull(),
            "updatedAt": formatDate(note.updatedAt),
            "deletedAt": note.deletedAt.map(formatDate) ?? NSNull(),
        ]
    }

    /// 原生纯文本 -> 最简 ProseMirror 形状，导入回 Flutter 端时可读。
    private static func plainDocumentJSON(_ text: String) -> [String: Any] {
        let paragraphs = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { line -> [String: Any] in
                let content: [[String: Any]] = line.isEmpty
                    ? []
                    : [["type": "text", "text": line]]
                return ["type": "paragraph", "content": content]
            }
        return ["type": "doc", "content": paragraphs]
    }

    private static func recurrenceTypeString(_ repeat: TaskRepeat) -> String {
        switch `repeat` {
        case .never: return "NONE"
        case .daily: return "DAILY"
        case .weekly: return "WEEKLY"
        case .monthly: return "MONTHLY"
        case .yearly: return "YEARLY"
        case .weekdays: return "WEEKDAYS"
        case .weekends: return "WEEKENDS"
        case .workdays: return "WORKDAYS"
        case .holidays: return "HOLIDAYS"
        }
    }

    private static func recurrenceConfigJSON(_ task: Task) -> [String: Any]? {
        guard task.recurrence != .never, let rule = task.recurrenceRule else { return nil }
        var config: [String: Any] = [:]
        if let count = rule.remainingCount { config["count"] = count }
        if let endDate = rule.endDate { config["endDate"] = formatDate(endDate) }
        if let monthDay = rule.monthDay { config["dayOfMonth"] = monthDay }
        if let weekday = rule.weekday { config["weekday"] = weekday }
        if let month = rule.month { config["month"] = month }
        return config.isEmpty ? nil : config
    }

    // MARK: 日期（Flutter 本地时间 ISO 字符串 <-> Date）

    private static let dateLock = NSLock()

    private static let localDateTimeFormatter: DateFormatter = posixFormatter("yyyy-MM-dd'T'HH:mm:ss")
    private static let localDateTimeShortFormatter: DateFormatter = posixFormatter("yyyy-MM-dd'T'HH:mm")
    private static let localDateTimeMicroFormatter: DateFormatter = posixFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSS")
    private static let localSpaceFormatter: DateFormatter = posixFormatter("yyyy-MM-dd HH:mm:ss")
    private static let localSpaceShortFormatter: DateFormatter = posixFormatter("yyyy-MM-dd HH:mm")
    private static let localDateOnlyFormatter: DateFormatter = posixFormatter("yyyy-MM-dd")

    private static let isoFormatter = ISO8601DateFormatter()
    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func posixFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }

    /// 输出 Flutter 本地时间格式（不带时区后缀，对应 Dart 本地 DateTime.toIso8601String()）。
    static func formatDate(_ date: Date) -> String {
        dateLock.lock()
        defer { dateLock.unlock() }
        return localDateTimeFormatter.string(from: date)
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 带时区后缀（Z 或 ±HH:mm）的按绝对时刻解析；原生侧 Date 即绝对时刻。
        if trimmed.hasSuffix("Z") || trimmed.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil {
            dateLock.lock()
            defer { dateLock.unlock() }
            return isoFormatter.date(from: trimmed) ?? isoFractionalFormatter.date(from: trimmed)
        }

        dateLock.lock()
        defer { dateLock.unlock() }
        for formatter in [localDateTimeMicroFormatter, localDateTimeFormatter, localDateTimeShortFormatter,
                          localSpaceFormatter, localSpaceShortFormatter, localDateOnlyFormatter] {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }
}
