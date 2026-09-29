import Foundation

enum TaskPriority: Int, Equatable, Codable { case none = 0, low, medium, high }
enum TaskStatus: Equatable, Codable { case active, completed }
enum TaskRepeat: String, CaseIterable, Equatable, Codable {
    case never, daily, weekly, monthly, yearly, weekdays, weekends, workdays, holidays
    var title: String {
        switch self {
        case .never: "不重复"
        case .daily: "每天"
        case .weekly: "每周"
        case .monthly: "每月"
        case .yearly: "每年"
        case .weekdays: "每周一至周五"
        case .weekends: "每周六、周日"
        case .workdays: "法定工作日"
        case .holidays: "法定休息日"
        }
    }
    var component: Calendar.Component {
        switch self {
        case .never, .daily, .weekdays, .weekends, .workdays, .holidays: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
    }
}

struct TaskList: Equatable, Codable {
    let name: String
    init(name: String) { self.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
    static let inbox = TaskList(name: "收集箱")
}

/// 侧栏清单元数据（对齐 Flutter MigrationListRecord 的 color/pinned/sortOrder）。
/// 按清单名关联、随快照单独存取，不写进任务本身；旧快照没有 meta 的清单
/// 退回默认色板色与字典序。additive Codable：缺失键解码为中性值。
struct TaskListMeta: Equatable, Codable {
    var name: String
    /// WFListPalette 下标；没有调色板色时再检查 colorARGB，否则按名称推导颜色。
    var colorIndex: Int?
    /// Imported Flutter colors outside the built-in palette remain exact ARGB values.
    var colorARGB: UInt32?
    var isPinned: Bool
    var sortOrder: Int

    init(name: String, colorIndex: Int? = nil, isPinned: Bool = false, sortOrder: Int = 0,
         colorARGB: UInt32? = nil) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.colorIndex = colorIndex
        self.colorARGB = colorARGB
        self.isPinned = isPinned
        self.sortOrder = sortOrder
    }

    private enum CodingKeys: String, CodingKey { case name, colorIndex, colorARGB, isPinned, sortOrder }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        colorIndex = try values.decodeIfPresent(Int.self, forKey: .colorIndex)
        colorARGB = try values.decodeIfPresent(UInt32.self, forKey: .colorARGB)
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        sortOrder = try values.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(name, forKey: .name)
        try values.encodeIfPresent(colorIndex, forKey: .colorIndex)
        try values.encodeIfPresent(colorARGB, forKey: .colorARGB)
        try values.encode(isPinned, forKey: .isPinned)
        try values.encode(sortOrder, forKey: .sortOrder)
    }
}

/// Schedule, period end and deadline are three different things and stay
/// separate, exactly as in the Flutter baseline:
///
/// - `dueAt` is when the work starts (the day a task appears on);
/// - `dueEndAt` is the end of the period, which is what makes a task cover more
///   than one day. Without it a "9月1日 – 9月5日" task is indistinguishable from
///   a one-day task, and the calendar has no way to draw it as a band;
/// - `deadlineAt` is the separate 截止日期, which never defines a range.
struct TaskSchedule: Equatable, Codable {
    var dueAt: Date?
    var hasTime: Bool
    var dueEndAt: Date?
    var deadlineAt: Date?
    init(dueAt: Date? = nil, hasTime: Bool = false,
         dueEndAt: Date? = nil, deadlineAt: Date? = nil) {
        self.dueAt = dueAt
        self.hasTime = dueAt != nil && hasTime
        self.dueEndAt = dueEndAt
        self.deadlineAt = deadlineAt
    }
}

/// Value entity, independent of SwiftUI, AppKit, persistence and preview fixtures.
struct Task: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var document: NativeDocument = .empty
    var tags: [String] = []
    var recurrence: TaskRepeat = .never
    var recurrenceRule: RecurrenceRule?
    var reminderAt: Date?
    /// Reminder offsets in minutes relative to the schedule anchor (0 = on
    /// time, negative = early). nil keeps the legacy single absolute reminderAt;
    /// a non-empty list drives multiple notifications instead (Flutter parity).
    var reminderOffsets: [Int]? = nil
    var attachments: [NativeAttachment] = []
    var list: TaskList
    var priority: TaskPriority
    var schedule: TaskSchedule
    var status: TaskStatus = .active
    let parentID: UUID?
    var childOrder: Int
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var deletedAt: Date?
    var isPinned: Bool = false
    var abandonedAt: Date? = nil
    var skippedAt: Date? = nil
    var convertedNoteID: UUID? = nil
    var sourceNoteID: UUID? = nil

    var isAbandoned: Bool { abandonedAt != nil }
    var isClosed: Bool { status == .completed || isAbandoned }
    var closedAt: Date? { status == .completed ? completedAt : abandonedAt }
    var isConverted: Bool { convertedNoteID != nil }
}

// Native preview snapshots are independent from Flutter storage, but they
// still need to survive additive model changes. Older snapshots have no
// isPinned or abandonedAt key, so decode those as their neutral states.
extension Task {
    private enum CodingKeys: String, CodingKey {
        case id, title, document, tags, recurrence, recurrenceRule, reminderAt, reminderOffsets
        case attachments, list, priority, schedule, status, parentID, childOrder
        case createdAt, updatedAt, completedAt, deletedAt, isPinned, abandonedAt, skippedAt, convertedNoteID
        case sourceNoteID
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        document = try values.decodeIfPresent(NativeDocument.self, forKey: .document) ?? .empty
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        recurrence = try values.decodeIfPresent(TaskRepeat.self, forKey: .recurrence) ?? .never
        recurrenceRule = try values.decodeIfPresent(RecurrenceRule.self, forKey: .recurrenceRule)
        reminderAt = try values.decodeIfPresent(Date.self, forKey: .reminderAt)
        reminderOffsets = try values.decodeIfPresent([Int].self, forKey: .reminderOffsets)
        attachments = try values.decodeIfPresent([NativeAttachment].self, forKey: .attachments) ?? []
        list = try values.decode(TaskList.self, forKey: .list)
        priority = try values.decode(TaskPriority.self, forKey: .priority)
        schedule = try values.decode(TaskSchedule.self, forKey: .schedule)
        status = try values.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .active
        parentID = try values.decodeIfPresent(UUID.self, forKey: .parentID)
        childOrder = try values.decode(Int.self, forKey: .childOrder)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        deletedAt = try values.decodeIfPresent(Date.self, forKey: .deletedAt)
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        abandonedAt = try values.decodeIfPresent(Date.self, forKey: .abandonedAt)
        skippedAt = try values.decodeIfPresent(Date.self, forKey: .skippedAt)
        convertedNoteID = try values.decodeIfPresent(UUID.self, forKey: .convertedNoteID)
        sourceNoteID = try values.decodeIfPresent(UUID.self, forKey: .sourceNoteID)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encodeIfPresent(sourceNoteID, forKey: .sourceNoteID)
        try values.encode(title, forKey: .title)
        try values.encode(document, forKey: .document)
        try values.encode(tags, forKey: .tags)
        try values.encode(recurrence, forKey: .recurrence)
        try values.encodeIfPresent(recurrenceRule, forKey: .recurrenceRule)
        try values.encodeIfPresent(reminderAt, forKey: .reminderAt)
        try values.encodeIfPresent(reminderOffsets, forKey: .reminderOffsets)
        try values.encode(attachments, forKey: .attachments)
        try values.encode(list, forKey: .list)
        try values.encode(priority, forKey: .priority)
        try values.encode(schedule, forKey: .schedule)
        try values.encode(status, forKey: .status)
        try values.encodeIfPresent(parentID, forKey: .parentID)
        try values.encode(childOrder, forKey: .childOrder)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encodeIfPresent(completedAt, forKey: .completedAt)
        try values.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try values.encode(isPinned, forKey: .isPinned)
        try values.encodeIfPresent(abandonedAt, forKey: .abandonedAt)
        try values.encodeIfPresent(skippedAt, forKey: .skippedAt)
        try values.encodeIfPresent(convertedNoteID, forKey: .convertedNoteID)
    }
}
