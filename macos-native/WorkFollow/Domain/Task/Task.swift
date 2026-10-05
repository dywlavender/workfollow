import Foundation

enum TaskPriority: Int, Equatable, Codable {
    case none = 0, low, medium, high

    /// 菜单顺序：滴答实测为「高 → 中 → 低 → 无」（自上而下）。菜单按它渲染，
    /// 不在视图里再手写一遍顺序。
    static let menuOrder: [TaskPriority] = [.high, .medium, .low, .none]

    /// 面向界面的名称，与任务列表 / 右键菜单同一套措辞。
    var title: String {
        switch self {
        case .none: "无优先级"
        case .low: "低优先级"
        case .medium: "中优先级"
        case .high: "高优先级"
        }
    }

    /// 无障碍与 tooltip 用的短名（读作"优先级：低"）。
    var shortTitle: String {
        switch self {
        case .none: "无优先级"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }
}
enum TaskStatus: Equatable, Codable { case active, completed }
enum TaskRepeat: String, CaseIterable, Equatable, Codable {
    case never, daily, weekly, monthly, yearly, weekdays, weekends, workdays, holidays
    /// 农历重复：按锚定日换算的农历月/日推进（滴答"农历重复"对齐）。
    case lunarYearly, lunarMonthly
    /// 艾宾浩斯记忆法（滴答对齐）：完成后按记忆曲线间隔推进，
    /// 序列走完再循环（间隔序列见 RecurrenceEngine.ebbinghausIntervals）。
    case ebbinghaus
    /// 文案定义在 `ScheduleDisplay.repeatTitle`（单一来源，菜单与摘要共用）。
    var title: String { ScheduleDisplay.repeatTitle(self) }
    var component: Calendar.Component {
        switch self {
        case .never, .daily, .weekdays, .weekends, .workdays, .holidays, .lunarYearly, .lunarMonthly, .ebbinghaus: .day
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
/// 分组内排序（滴答「清单页 → … → 分组排序」）。
///
/// 官方口径：按时间 / 按优先级 / 按创建时间（新→旧、旧→新）/ 按修改时间（新→旧、旧→新），
/// 外加"恢复默认时间顺序"。它是**清单级**设置（不是每个分组各一份），nil = 默认（跟随视图排序）。
enum TaskSectionSort: String, CaseIterable, Codable {
    case dueDate
    case priority
    case createdNewest
    case createdOldest
    case modifiedNewest
    case modifiedOldest

    var title: String {
        switch self {
        case .dueDate: "按时间"
        case .priority: "按优先级"
        case .createdNewest: "按创建时间（新→旧）"
        case .createdOldest: "按创建时间（旧→新）"
        case .modifiedNewest: "按修改时间（新→旧）"
        case .modifiedOldest: "按修改时间（旧→新）"
        }
    }
}

struct TaskListMeta: Equatable, Codable {
    var name: String
    /// WFListPalette 下标；没有调色板色时再检查 colorARGB，否则按名称推导颜色。
    var colorIndex: Int?
    /// Imported Flutter colors outside the built-in palette remain exact ARGB values.
    var colorARGB: UInt32?
    var isPinned: Bool
    var sortOrder: Int
    /// 清单图标（Emoji）。nil = 回落到色点（现有行为）。additive：旧快照缺键 → nil。
    var icon: String?
    /// 所属文件夹（滴答层级：文件夹 → 清单）。nil = 顶层。
    /// additive：旧快照缺键 → nil；**文件夹本身不单独存**——存在 ⇔ 至少有一个清单指向它，
    /// 位置 = 它第一个成员清单的位置。
    var folderName: String?
    /// 分组内排序。nil = 默认（跟随视图排序）。additive：旧快照缺键 → nil。
    var sectionTaskSort: TaskSectionSort?

    init(name: String, colorIndex: Int? = nil, isPinned: Bool = false, sortOrder: Int = 0,
         colorARGB: UInt32? = nil, icon: String? = nil, folderName: String? = nil, sectionTaskSort: TaskSectionSort? = nil) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.colorIndex = colorIndex
        self.colorARGB = colorARGB
        self.isPinned = isPinned
        self.sortOrder = sortOrder
        self.icon = icon
        self.folderName = folderName
        self.sectionTaskSort = sectionTaskSort
    }

    private enum CodingKeys: String, CodingKey {
        case name, colorIndex, colorARGB, isPinned, sortOrder, icon, folderName, sectionTaskSort
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        colorIndex = try values.decodeIfPresent(Int.self, forKey: .colorIndex)
        colorARGB = try values.decodeIfPresent(UInt32.self, forKey: .colorARGB)
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        sortOrder = try values.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        icon = try values.decodeIfPresent(String.self, forKey: .icon)
        folderName = try values.decodeIfPresent(String.self, forKey: .folderName)
            .flatMap { $0.isEmpty ? nil : $0 }
        sectionTaskSort = try values.decodeIfPresent(TaskSectionSort.self, forKey: .sectionTaskSort)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(name, forKey: .name)
        try values.encodeIfPresent(colorIndex, forKey: .colorIndex)
        try values.encodeIfPresent(colorARGB, forKey: .colorARGB)
        try values.encode(isPinned, forKey: .isPinned)
        try values.encode(sortOrder, forKey: .sortOrder)
        try values.encodeIfPresent(icon, forKey: .icon)
        try values.encodeIfPresent(folderName, forKey: .folderName)
        try values.encodeIfPresent(sectionTaskSort, forKey: .sectionTaskSort)
    }
}

/// 清单文件夹（滴答层级第一级：文件夹 → 清单 → 分组 → 任务 → 子任务）。
///
/// **独立实体**：滴答有两条创建路径——① 拖清单叠清单；②
/// 「清单编辑页 → 更多设置 → 文件夹 → 添加文件夹」，第二条会先建出**空文件夹**
/// 再把清单放进去。所以文件夹不能只靠清单上的 `folderName` 派生，必须自带存储。
/// `sortOrder` 决定它与顶层清单在侧栏的相对位置（同名合并时以显式记录为准）。
struct TaskListFolder: Equatable, Codable, Identifiable {
    var id: String { name }
    var name: String
    var sortOrder: Int

    init(name: String, sortOrder: Int = 0) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sortOrder = sortOrder
    }

    private enum CodingKeys: String, CodingKey { case name, sortOrder }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = (try values.decode(String.self, forKey: .name))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        sortOrder = try values.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }
}


/// 清单内自定义分组（滴答层级第三级：文件夹 → 清单 → 分组 → 任务 → 子任务）。
///
/// 官方：**仅普通清单**支持自定义分组（智能清单不支持）；分组是任务的**结构性归属**，
/// 与"按优先级/时间分组"这类**系统智能分组**正交；看板视图以分组为列。
/// `id` 稳定（重命名不换身份），任务只认 id。
struct TaskListSection: Equatable, Codable, Identifiable {
    var id: String
    var listName: String
    var title: String
    var sortOrder: Int

    init(id: String = UUID().uuidString, listName: String, title: String, sortOrder: Int = 0) {
        self.id = id
        self.listName = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sortOrder = sortOrder
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
    var parentID: UUID?
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
    /// 所属清单分组（`TaskListSection.id`）。nil = 未分组。
    var sectionID: String? = nil

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
        case sourceNoteID, sectionID
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
        sectionID = try values.decodeIfPresent(String.self, forKey: .sectionID)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encodeIfPresent(sourceNoteID, forKey: .sourceNoteID)
        try values.encodeIfPresent(sectionID, forKey: .sectionID)
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
