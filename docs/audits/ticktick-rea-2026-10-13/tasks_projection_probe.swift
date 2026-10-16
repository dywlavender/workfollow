import Foundation
struct NativeDocument: Equatable, Codable { static let empty = NativeDocument(); func matches(_ query: String, prefix: String) -> Bool { prefix.localizedCaseInsensitiveContains(query) } }
struct NativeAttachment: Equatable, Codable {}
enum ScheduleDisplay { static func repeatTitle(_ value: TaskRepeat) -> String { value.rawValue } }
enum ChineseWorkCalendar { static func isWorkday(date: Date, calendar: Calendar) -> Bool { ![1,7].contains(calendar.component(.weekday, from: date)) } }
enum TaskListGrouping { case byDate, none, byPriority, byList, byTag, byCreatedAt }
struct WorkspaceStore { var tasks: [Task]; var lists: [String]; var listSections: [TaskListSection] = [] }
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

    init(name: String, colorIndex: Int? = nil, isPinned: Bool = false, sortOrder: Int = 0,
         colorARGB: UInt32? = nil, icon: String? = nil, folderName: String? = nil) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.colorIndex = colorIndex
        self.colorARGB = colorARGB
        self.isPinned = isPinned
        self.sortOrder = sortOrder
        self.icon = icon
        self.folderName = folderName
    }

    private enum CodingKeys: String, CodingKey {
        case name, colorIndex, colorARGB, isPinned, sortOrder, icon, folderName
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

import Foundation

/// Optional alongside the original frequency, so existing preview JSON remains readable.
struct RecurrenceRule: Equatable, Codable {
    var interval: Int = 1
    var endDate: Date?
    /// Includes the current occurrence, matching Flutter's count contract.
    var remainingCount: Int?
    var monthDay: Int?
    /// Gregorian weekday 1=Sunday … 7=Saturday.
    var weekday: Int?
    var month: Int?
    /// 农历重复目标：月 1–12、日 1–30（每月最后一天按钳制取齐），
    /// 闰月显式标记。additive Codable：旧快照缺失时为 nil，按锚定日换算。
    var lunarMonth: Int?
    var lunarDay: Int?
    var lunarIsLeapMonth: Bool?
}

extension RecurrenceRule {
    /// The rule carried by the next occurrence: the count boundary is consumed
    /// by the occurrence that just completed (Flutter's followingConfig).
    var following: RecurrenceRule {
        var value = self
        value.remainingCount = remainingCount.map { max(0, $0 - 1) }
        return value
    }

    /// 艾宾浩斯记忆曲线间隔（天）。滴答 scratch 实测校正前用标准序列；
    /// 校正后只改这里（引擎与测试金标联动）。
    static let ebbinghausIntervals = [1, 2, 4, 7, 15, 30]

    /// Validates and repairs the rule; nil marks a structurally invalid rule
    /// (out-of-range weekday/month fields) that must not drive a recurrence —
    /// mirroring Flutter's RecurrenceDraft.normalized. A count below 1 is
    /// dropped (never-ending) rather than rejected, and endDate collapses to
    /// the start of its day so the whole day stays inside the boundary.
    func normalized(calendar: Calendar = .current) -> RecurrenceRule? {
        if let weekday, !(1...7).contains(weekday) { return nil }
        if let monthDay, !(1...31).contains(monthDay) { return nil }
        if let month, !(1...12).contains(month) { return nil }
        if let lunarMonth, !(1...12).contains(lunarMonth) { return nil }
        if let lunarDay, !(1...30).contains(lunarDay) { return nil }
        var value = self
        value.interval = max(1, interval)
        if let remainingCount, remainingCount < 1 { value.remainingCount = nil }
        value.endDate = endDate.map { calendar.startOfDay(for: $0) }
        return value
    }

    /// Next occurrence strictly after `after` (the current due moment), keeping
    /// the anchor's wall-clock time. Shifting child dates, deadlines and
    /// reminders deliberately lives in TaskActions. Years without an official
    /// holiday table degrade to the ordinary Monday–Friday calendar.
    func nextOccurrence(after base: Date?, frequency: TaskRepeat, calendar: Calendar) -> Date? {
        guard frequency != .never, let base else { return nil }
        guard remainingCount.map({ $0 > 1 }) ?? true else { return nil }
        let interval = max(1, self.interval)
        let time = calendar.dateComponents([.hour, .minute, .second], from: base)
        var next: Date?
        switch frequency {
        case .never:
            return nil
        case .daily:
            next = calendar.date(byAdding: .day, value: interval, to: base)
        case .weekly:
            let current = calendar.component(.weekday, from: base)
            let target = weekday ?? current
            let distance = (target - current + 7) % 7
            next = calendar.date(byAdding: .day, value: (distance == 0 ? 7 : distance) + 7 * (interval - 1), to: base)
        case .monthly, .yearly:
            // Advance from the first day, then clamp the original target day.
            // Jan 31 → Feb 28 → Mar 31, not Mar 28.
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: base)
            let target = monthDay ?? parts.day ?? 1
            parts.day = 1
            if frequency == .yearly, let month { parts.month = min(12, max(1, month)) }
            if let first = calendar.date(from: parts),
               let anchor = calendar.date(byAdding: frequency == .yearly ? .year : .month, value: interval, to: first),
               let days = calendar.range(of: .day, in: .month, for: anchor) {
                next = calendar.date(byAdding: .day, value: min(max(1, target), days.count) - 1, to: anchor)
            }
        case .weekdays, .weekends, .workdays, .holidays:
            var candidate = base
            var remaining = interval
            while remaining > 0 {
                guard let day = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
                candidate = day
                if matches(candidate, frequency: frequency, calendar: calendar) { remaining -= 1 }
            }
            next = candidate
        case .lunarYearly:
            // 逐日扫描，用农历历匹配目标月/日。农历重复的钳制语义与公历
            // monthly/yearly 一致：目标日超过月长时取当月最后一天（三十在
            // 小月取廿九）。闰月策略：目标标了闰月只落在闰月 occurrence
            // （无闰月的年份跳过，不落到平月）；目标为平月则永不落闰月。
            var lunarCal = Calendar(identifier: .chinese)
            lunarCal.timeZone = calendar.timeZone
            let targetMonth = lunarMonth ?? lunarCal.component(.month, from: base)
            let targetDay = lunarDay ?? lunarCal.component(.day, from: base)
            let wantLeap = lunarIsLeapMonth ?? false
            var candidate = base
            var stepsLeft = interval
            // 农历十九年七闰，闰月最大间隔约三年；1500 天覆盖任意目标。
            for _ in 0..<1500 {
                guard let day = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
                candidate = day
                let comps = lunarCal.dateComponents([.month, .day], from: candidate)
                guard comps.month == targetMonth,
                      (comps.isLeapMonth == true) == wantLeap else { continue }
                let monthLength = lunarCal.range(of: .day, in: .month, for: candidate)?.count ?? 30
                guard comps.day == min(targetDay, monthLength) else { continue }
                stepsLeft -= 1
                if stepsLeft == 0 {
                    next = candidate
                    break
                }
            }
        case .lunarMonthly:
            // 农历每月：只按农历日推进，每个月（含闰月）的该日都算一次。
            var lunarCal = Calendar(identifier: .chinese)
            lunarCal.timeZone = calendar.timeZone
            let targetDay = lunarDay ?? lunarCal.component(.day, from: base)
            var candidate = base
            var stepsLeft = interval
            for _ in 0..<200 {
                guard let day = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
                candidate = day
                let comps = lunarCal.dateComponents([.month, .day], from: candidate)
                let monthLength = lunarCal.range(of: .day, in: .month, for: candidate)?.count ?? 30
                guard comps.day == min(targetDay, monthLength) else { continue }
                stepsLeft -= 1
                if stepsLeft == 0 {
                    next = candidate
                    break
                }
            }
        case .ebbinghaus:
            // 艾宾浩斯记忆法：完成后按记忆曲线间隔推进。interval 承载"已完成
            // 次数"（TaskActions.makeNextOccurrence 每次完成时递增），第 N 次
            // 完成取序列[N-1]；走完从头循环（滴答实测校正前先用标准曲线）。
            let intervals = Self.ebbinghausIntervals
            let step = (max(1, interval) - 1) % intervals.count
            next = calendar.date(byAdding: .day, value: intervals[step], to: base)
        }
        guard let next else { return nil }
        // Rules above only move the day; rebuild so the clock survives exactly.
        var shifted = calendar.dateComponents([.year, .month, .day], from: next)
        shifted.hour = time.hour
        shifted.minute = time.minute
        shifted.second = time.second
        let result = calendar.date(from: shifted) ?? next
        if let end = endDate, calendar.startOfDay(for: result) > calendar.startOfDay(for: end) { return nil }
        return result
    }

    /// Up to `limit` future occurrence days for calendar previews; the count
    /// boundary is consumed step by step, so count rules terminate early.
    func occurrenceDays(after base: Date, frequency: TaskRepeat, calendar: Calendar, limit: Int) -> Set<Date> {
        var rule = self
        var cursor = base
        var days: Set<Date> = []
        for _ in 0..<max(0, limit) {
            guard let next = rule.nextOccurrence(after: cursor, frequency: frequency, calendar: calendar) else { break }
            days.insert(calendar.startOfDay(for: next))
            rule = rule.following
            // 艾宾浩斯的步数由 interval 承载（完成路径每次完成 +1），预览推进
            // 必须同步递增，否则退化成"每天重复"（完成路径与预览路径共用同一
            // 引擎，两边必须同语义）。
            if frequency == .ebbinghaus { rule.interval += 1 }
            cursor = next
        }
        return days
    }

    private func matches(_ date: Date, frequency: TaskRepeat, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let isWeekday = weekday != 1 && weekday != 7
        switch frequency {
        case .weekdays: return isWeekday
        case .weekends: return !isWeekday
        case .workdays: return ChineseWorkCalendar.isWorkday(date: date, calendar: calendar)
        case .holidays: return !ChineseWorkCalendar.isWorkday(date: date, calendar: calendar)
        default: return false
        }
    }
}

enum RecurrenceEngine {
    /// Task-level convenience kept for callers that hold a Task: resolves the
    /// rule (defaulting when unset) and anchors on the due moment, or on the
    /// start of `now` for undated tasks. Rule-level callers use
    /// `RecurrenceRule.nextOccurrence` directly.
    static func next(for task: Task, now: Date, calendar: Calendar) -> Date? {
        guard task.recurrence != .never else { return nil }
        let rule = task.recurrenceRule ?? RecurrenceRule()
        return rule.nextOccurrence(after: task.schedule.dueAt ?? calendar.startOfDay(for: now),
                                   frequency: task.recurrence, calendar: calendar)
    }
}

import Foundation

/// Date dimension of a saved filter. The predicates reuse TaskListProjection's
/// existing start-of-day math (with the caller's calendar) instead of a second
/// day-window definition:
/// - `today` matches the `.today` scope predicate (due day <= today, or a
///   deadline no later than today), so 已过期 tasks still show under 今天 views.
/// - `nextSevenDays` matches the `.nextSevenDays` scope predicate
///   (due day < today + 7, includes today and 已过期, excludes the boundary day).
/// - `overdue` / `noDate` match the 所有任务 date buckets (due day < today,
///   respectively dueAt == nil; deadlines alone do not create buckets).
enum SavedFilterDateRange: String, Codable, CaseIterable {
    case any
    case today
    case nextSevenDays
    case noDate
    case overdue

    var title: String {
        switch self {
        case .any: "任意"
        case .today: "今天"
        case .nextSevenDays: "最近 7 天"
        case .noDate: "无日期"
        case .overdue: "已逾期"
        }
    }
}

/// One saved smart filter (Wave 1 F5, aligned with TickTick's 过滤器).
/// Every enabled dimension is AND-combined; empty arrays and `.any` mean the
/// dimension is off and never rejects a task.
struct SavedFilter: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var listNames: [String] = []
    var tags: [String] = []
    var priorities: [TaskPriority] = []
    var dateRange: SavedFilterDateRange = .any
    /// 关键词（滴答「普通筛选」的"按关键词做内容筛选"）：**全部包含**才算命中，
    /// 匹配范围是标题 + 正文纯文本，大小写不敏感。空数组 = 该维度关闭。
    var keywords: [String] = []

    init(id: UUID = UUID(), name: String, listNames: [String] = [], tags: [String] = [],
         priorities: [TaskPriority] = [], dateRange: SavedFilterDateRange = .any,
         keywords: [String] = []) {
        self.id = id
        self.name = name
        self.listNames = listNames
        self.tags = tags
        self.priorities = priorities
        self.dateRange = dateRange
        self.keywords = keywords
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, listNames, tags, priorities, dateRange, keywords
    }

    /// additive Codable：旧 `filters.json` 缺 `keywords` 键时解码为空数组
    /// （属性默认值不会让合成解码器宽容缺键，所以显式写出来）。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        listNames = try values.decodeIfPresent([String].self, forKey: .listNames) ?? []
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        priorities = try values.decodeIfPresent([TaskPriority].self, forKey: .priorities) ?? []
        dateRange = try values.decodeIfPresent(SavedFilterDateRange.self, forKey: .dateRange) ?? .any
        keywords = try values.decodeIfPresent([String].self, forKey: .keywords) ?? []
    }

    /// 关键词原文 → token 列表：空格 / 半角逗号 / 中文逗号 / 顿号 / 换行分隔，
    /// 去重且保持输入顺序。编辑器与测试共用这一处解析。
    static func parseKeywords(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: " ,，、\t\n")
        var seen = Set<String>()
        return text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// Pure predicate: does `task` pass every enabled dimension of `filter`?
/// Closed (completed/abandoned) tasks are deliberately not excluded here —
/// matching them follows `TaskListQuery.matches`, which also ignores `isClosed`
/// and lets matching closed tasks stay in the view's 已完成 group.
enum FilterEvaluator {
    static func matches(_ task: Task, filter: SavedFilter,
                        now: Date, calendar: Calendar) -> Bool {
        if !filter.listNames.isEmpty && !filter.listNames.contains(task.list.name) {
            return false
        }
        if !filter.tags.isEmpty && !filter.tags.contains(where: { task.tags.contains($0) }) {
            return false
        }
        if !filter.priorities.isEmpty && !filter.priorities.contains(task.priority) {
            return false
        }
        if !filter.keywords.isEmpty {
            // 只在真有关键词时才拼正文，避免没有该维度时每个任务都拼一次。
            guard filter.keywords.allSatisfy({ task.document.matches($0, prefix: task.title + "\n") }) else {
                return false
            }
        }
        let today = calendar.startOfDay(for: now)
        switch filter.dateRange {
        case .any:
            return true
        case .today:
            let due = task.schedule.dueAt.map { calendar.startOfDay(for: $0) <= today } ?? false
            let deadline = task.schedule.deadlineAt.map { $0 <= today } ?? false
            return due || deadline
        case .nextSevenDays:
            guard let dueAt = task.schedule.dueAt else { return false }
            let end = calendar.date(byAdding: .day, value: 7, to: today)!
            return calendar.startOfDay(for: dueAt) < end
        case .noDate:
            return task.schedule.dueAt == nil
        case .overdue:
            guard let dueAt = task.schedule.dueAt else { return false }
            return calendar.startOfDay(for: dueAt) < today
        }
    }
}
import Foundation

enum TaskListScope { case today, tomorrow, inbox, allTasks, nextSevenDays, completed }
enum TaskGroupKind: Equatable { case pinned, overdue, today, day, upcoming, later, undated, plain, completed }
enum TaskListSortMode: String, CaseIterable, Codable {
    case manual, due, priority, title, createdAt, modified

    var title: String {
        switch self {
        case .manual: "手动排序"
        case .due: "按日期排序"
        case .priority: "按优先级排序"
        case .title: "按标题排序"
        case .createdAt: "按创建时间排序"
        case .modified: "按修改时间排序"
        }
    }
}
struct TaskListQuery: Equatable {
    var search = ""
    var list: String?
    var tag: String?
    var isFiltering: Bool { !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || list != nil || tag != nil }
    func matches(_ task: Task) -> Bool {
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return (list == nil || task.list.name == list) &&
            (tag == nil || task.tags.contains(tag!)) &&
            (text.isEmpty || task.document.matches(text, prefix: task.title + "\n"))
    }
}
struct TaskListGroup {
    let kind: TaskGroupKind
    let day: Date?
    let tasks: [Task]
    let label: String?
    /// 这一组对应的**自定义分组 id**（只有"列 = 分组"时有值）。
    /// 看板换列靠它定位落点：拖到某列 = `setTaskSection(任务, 该列的分组 id)`。
    let sectionID: String?

    /// 是否是「未分组」桶：它 `sectionID == nil`，与"按日期/优先级"那类系统分组标题
    /// 在数据上无法区分，而拖放语义正好相反（落上去 = **移出**分组）。
    /// 不存字段：判定只用投影里唯一的那份标题常量，避免再造一处要同步的真值。
    var isUnsectionedBucket: Bool {
        sectionID == nil && kind == .plain && label == TaskListSectionProjection.unsectionedTitle
    }

    /// Stable across sorting and heading changes so a folded group does not
    /// accidentally transfer to another group or reopen after its label shifts.
    var id: String {
        switch kind {
        case .pinned: "pinned"
        case .overdue: "overdue"
        case .today: "today"
        case .upcoming: "upcoming"
        case .later: "later"
        case .undated: "undated"
        case .plain:
            // 带标签的 plain 组（按优先级/清单/标签分组产生）各有身份，折叠状态
            // 互不串；无标签的 plain 组（平铺视图）沿用历史单一身份。
            if let label { "plain:\(label)" } else { "plain" }
        case .day:
            if let day { Self.dayGroupID(day) }
            else { "day-undated" }
        case .completed:
            if let day { Self.closedDayGroupID(day) }
            else if label == "无日期" { "closed-undated" }
            else { "closed" }
        }
    }

    static func dayGroupID(_ day: Date) -> String {
        "day:\(Int64(day.timeIntervalSince1970))"
    }

    static func closedDayGroupID(_ day: Date) -> String {
        "closed:\(Int64(day.timeIntervalSince1970))"
    }

    init(kind: TaskGroupKind, day: Date?, tasks: [Task], label: String? = nil,
         sectionID: String? = nil) {
        self.kind = kind
        self.day = day
        self.tasks = tasks
        self.label = label
        self.sectionID = sectionID
    }

    /// 组内排序（阶段1扩到五种）。所有模式都只是视图投影，**从不改 childOrder**：
    /// 切走手动排序再切回来，拖拽排出的顺序原样恢复。completed 组永远按完成
    /// 时间倒序，任何排序模式都不得重排。
    func orderedTasks(using mode: TaskListSortMode, descending: Bool = false,
                      calendar: Calendar) -> [Task] {
        guard kind != .completed, mode != .manual else { return tasks }
        return tasks.enumerated().sorted { lhs, rhs in
            switch mode {
            case .manual:
                return descending ? lhs.offset > rhs.offset : lhs.offset < rhs.offset
            case .priority:
                if lhs.element.priority != rhs.element.priority {
                    // 默认（升序）＝ 高 → 中 → 低 → 无：历史行为就是 rawValue 降序，
                    // 别把它改成字面意义的"升序"。降序时整体翻转。
                    let highFirst = lhs.element.priority.rawValue > rhs.element.priority.rawValue
                    return descending ? !highFirst : highFirst
                }
                return Self.orderedByDue(lhs, rhs, descending: descending)
            case .due:
                return Self.orderedByDue(lhs, rhs, descending: descending)
            case .title:
                let order = lhs.element.title.localizedCaseInsensitiveCompare(rhs.element.title)
                if order != .orderedSame {
                    return descending ? order == .orderedDescending : order == .orderedAscending
                }
                return lhs.offset < rhs.offset
            case .createdAt:
                if lhs.element.createdAt != rhs.element.createdAt {
                    let ascending = lhs.element.createdAt < rhs.element.createdAt
                    return descending ? !ascending : ascending
                }
                return lhs.offset < rhs.offset
            case .modified:
                if lhs.element.updatedAt != rhs.element.updatedAt {
                    let ascending = lhs.element.updatedAt < rhs.element.updatedAt
                    return descending ? !ascending : ascending
                }
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    /// 日期序、**无日期永远垫底**（不论方向），再按原有顺序稳定收尾（历史 due 模式的比较器）。
    private static func orderedByDue(_ lhs: (offset: Int, element: Task),
                                     _ rhs: (offset: Int, element: Task),
                                     descending: Bool = false) -> Bool {
        switch (lhs.element.schedule.dueAt, rhs.element.schedule.dueAt) {
        case let (left?, right?) where left != right:
            return descending ? left > right : left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.offset < rhs.offset
        }
    }
}

/// View-only folding state for task group headings.
struct TaskGroupExpansionState: Equatable {
    private(set) var collapsedIDs: Set<String> = []

    func isCollapsed(_ group: TaskListGroup) -> Bool {
        collapsedIDs.contains(group.id)
    }

    mutating func toggle(_ group: TaskListGroup) {
        if !collapsedIDs.insert(group.id).inserted {
            collapsedIDs.remove(group.id)
        }
    }

    mutating func reveal(_ task: Task, in scope: TaskListScope, calendar: Calendar) {
        guard task.isClosed else { return }
        if scope == .completed {
            let id = task.closedAt.map {
                TaskListGroup.closedDayGroupID(calendar.startOfDay(for: $0))
            } ?? "closed-undated"
            collapsedIDs.remove(id)
        } else {
            collapsedIDs.remove("closed")
        }
    }
}

enum TaskListProjection {
    /// Flutter keeps matching completed tasks in Today/Inbox, while their badge counts open tasks.
    static func matches(in scope: TaskListScope, store: WorkspaceStore,
                        now: Date, calendar: Calendar, query: TaskListQuery = TaskListQuery()) -> [Task] {
        matches(in: scope, tasks: store.tasks, now: now, calendar: calendar, query: query)
    }

    /// Value-input overload for feature projections that need the exact same
    /// scope/query membership rules without owning or mutating a WorkspaceStore.
    static func matches(in scope: TaskListScope, tasks: [Task],
                        now: Date, calendar: Calendar, query: TaskListQuery = TaskListQuery()) -> [Task] {
        tasks.filter { task in
            guard task.deletedAt == nil && task.skippedAt == nil && !task.isConverted else { return false }
            guard query.matches(task) else { return false }
            switch scope {
            case .allTasks: return true
            case .nextSevenDays:
                let start = calendar.startOfDay(for: now)
                let end = calendar.date(byAdding: .day, value: 7, to: start)!
                return task.schedule.dueAt.map { calendar.startOfDay(for: $0) < end } ?? false
            case .inbox: return task.list == .inbox
            case .completed: return task.isClosed
            case .today:
                guard !task.isAbandoned else { return false }
                let today = calendar.startOfDay(for: now)
                let due = task.schedule.dueAt.map { calendar.startOfDay(for: $0) <= today } ?? false
                let deadline = task.schedule.deadlineAt.map { $0 <= today } ?? false
                return due || deadline
            case .tomorrow:
                // 与「今天」同构：只看"落在明天"的到期/截止日；逾期属于今天视图，不在这里。
                guard !task.isAbandoned else { return false }
                let tomorrow = calendar.date(byAdding: .day, value: 1,
                                             to: calendar.startOfDay(for: now))!
                let due = task.schedule.dueAt.map { calendar.startOfDay(for: $0) == tomorrow } ?? false
                let deadline = task.schedule.deadlineAt.map { calendar.startOfDay(for: $0) == tomorrow } ?? false
                return due || deadline
            }
        }
    }

    static func rows(in scope: TaskListScope, store: WorkspaceStore,
                     now: Date, calendar: Calendar, query: TaskListQuery = TaskListQuery()) -> [Task] {
        let tasks = matches(in: scope, store: store, now: now, calendar: calendar, query: query)
        let ids = Set(tasks.map(\.id))
        return tasks.filter { $0.parentID.map { !ids.contains($0) } ?? true }
    }

    static func count(in scope: TaskListScope, store: WorkspaceStore,
                      now: Date, calendar: Calendar) -> Int {
        matches(in: scope, store: store, now: now, calendar: calendar)
            .filter { scope == .completed || !$0.isClosed }.count
    }

    static func groups(in scope: TaskListScope, store: WorkspaceStore,
                       now: Date, calendar: Calendar, query: TaskListQuery = TaskListQuery(),
                       grouping: TaskListGrouping = .byDate,
                       hidesCompleted: Bool = false) -> [TaskListGroup] {
        let rows = rows(in: scope, store: store, now: now, calendar: calendar, query: query)
        let closed = rows.filter(\.isClosed).sorted {
            ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast)
        }
        if scope == .completed {
            let dated = closed.filter { $0.closedAt != nil }
            let undated = closed.filter { $0.closedAt == nil }
            let days = Dictionary(grouping: dated) {
                calendar.startOfDay(for: $0.closedAt!)
            }
            var groups = days.keys.sorted(by: >).map { day in
                TaskListGroup(kind: .completed, day: day,
                              tasks: days[day]!.sorted { $0.closedAt! > $1.closedAt! })
            }
            if !undated.isEmpty {
                groups.append(TaskListGroup(kind: .completed, day: nil, tasks: undated,
                                            label: "无日期"))
            }
            return groups
        }
        let open = rows.filter { !$0.isClosed }
        let pinned = open.filter(\.isPinned)
        let ordinary = open.filter { !$0.isPinned }
        var groups: [TaskListGroup] = []
        if !pinned.isEmpty {
            groups.append(TaskListGroup(kind: .pinned, day: nil, tasks: pinned))
        }
        // 分组方式只作用于"所有任务"（含清单/标签过滤视图）；今天/最近 7 天/已完成
        // 的日期分组是视图本体，传进来的 grouping 一律忽略。
        if scope == .allTasks, let list = query.list,
           let sectionGroups = TaskListSectionProjection.groups(ordinary, list: list,
                                                                sections: store.listSections) {
            // 清单自定义分组优先于"分组方式"：分组是**归属**，不是展示规则。
            groups += sectionGroups
        } else if scope == .allTasks {
            switch grouping {
            case .byDate:
                if query.list == nil && query.tag == nil {
                    groups += allTaskDateGroups(ordinary, now: now, calendar: calendar)
                } else if !ordinary.isEmpty {
                    groups.append(TaskListGroup(kind: .plain, day: nil, tasks: ordinary))
                }
            case .none:
                if !ordinary.isEmpty {
                    groups.append(TaskListGroup(kind: .plain, day: nil, tasks: ordinary))
                }
            case .byPriority:
                groups += priorityGroups(ordinary)
            case .byList:
                groups += listGroups(ordinary, knownLists: store.lists)
            case .byTag:
                groups += tagGroups(ordinary)
            case .byCreatedAt:
                groups += createdAtGroups(ordinary, now: now, calendar: calendar)
            }
        } else if scope == .today {
            let today = calendar.startOfDay(for: now)
            let overdue = ordinary.filter { $0.schedule.dueAt.map { calendar.startOfDay(for: $0) < today } ?? false }
            let overdueIDs = Set(overdue.map(\.id))
            let remaining = ordinary.filter { !overdueIDs.contains($0.id) }
            if !overdue.isEmpty { groups.append(TaskListGroup(kind: .overdue, day: nil, tasks: overdue)) }
            if !remaining.isEmpty { groups.append(TaskListGroup(kind: .today, day: today, tasks: remaining)) }
        } else if scope == .tomorrow {
            // 时间型视图的日期分组是视图本体：明天只有一个桶（逾期归今天视图）。
            let tomorrow = calendar.date(byAdding: .day, value: 1,
                                         to: calendar.startOfDay(for: now))!
            if !ordinary.isEmpty {
                groups.append(TaskListGroup(kind: .day, day: tomorrow, tasks: ordinary))
            }
        } else if scope == .nextSevenDays {
            let today = calendar.startOfDay(for: now)
            let overdue = ordinary.filter { $0.schedule.dueAt.map { calendar.startOfDay(for: $0) < today } ?? false }
            if !overdue.isEmpty { groups.append(TaskListGroup(kind: .overdue, day: nil, tasks: overdue)) }

            let upcoming = ordinary.filter { $0.schedule.dueAt.map { calendar.startOfDay(for: $0) >= today } ?? false }
            let byDay = Dictionary(grouping: upcoming) {
                calendar.startOfDay(for: $0.schedule.dueAt!)
            }
            for day in byDay.keys.sorted() {
                groups.append(TaskListGroup(kind: day == today ? .today : .day,
                                            day: day, tasks: byDay[day]!))
            }
        } else if !ordinary.isEmpty {
            groups.append(TaskListGroup(kind: .plain, day: nil, tasks: ordinary))
        }
        // 「隐藏已完成」只作用于普通视图；`.completed` 视图本身在上面已提前返回。
        if !hidesCompleted, !closed.isEmpty {
            let hasCompleted = closed.contains { $0.status == .completed }
            let hasAbandoned = closed.contains { $0.isAbandoned }
            let label = hasCompleted && hasAbandoned ? "已完成&已放弃"
                : hasAbandoned ? "已放弃" : "已完成"
            groups.append(TaskListGroup(kind: .completed, day: nil, tasks: closed, label: label))
        }
        return groups
    }

    private static func allTaskDateGroups(_ tasks: [Task], now: Date,
                                          calendar: Calendar) -> [TaskListGroup] {
        let today = calendar.startOfDay(for: now)
        let recentEnd = calendar.date(byAdding: .day, value: 7, to: today)!
        let overdue = tasks.filter {
            $0.schedule.dueAt.map { calendar.startOfDay(for: $0) < today } ?? false
        }
        let onToday = tasks.filter {
            $0.schedule.dueAt.map { calendar.startOfDay(for: $0) == today } ?? false
        }
        let upcoming = tasks.filter {
            guard let dueAt = $0.schedule.dueAt else { return false }
            let day = calendar.startOfDay(for: dueAt)
            return day > today && day < recentEnd
        }
        let later = tasks.filter {
            $0.schedule.dueAt.map { calendar.startOfDay(for: $0) >= recentEnd } ?? false
        }
        let undated = tasks.filter { $0.schedule.dueAt == nil }

        func sortedByDueDay(_ values: [Task]) -> [Task] {
            values.enumerated().sorted { lhs, rhs in
                let lhsDay = calendar.startOfDay(for: lhs.element.schedule.dueAt!)
                let rhsDay = calendar.startOfDay(for: rhs.element.schedule.dueAt!)
                return lhsDay == rhsDay ? lhs.offset < rhs.offset : lhsDay < rhsDay
            }.map(\.element)
        }

        var groups: [TaskListGroup] = []
        if !overdue.isEmpty { groups.append(TaskListGroup(kind: .overdue, day: nil, tasks: overdue)) }
        if !onToday.isEmpty { groups.append(TaskListGroup(kind: .today, day: today, tasks: onToday)) }
        if !upcoming.isEmpty {
            groups.append(TaskListGroup(kind: .upcoming, day: nil, tasks: sortedByDueDay(upcoming)))
        }
        if !later.isEmpty {
            groups.append(TaskListGroup(kind: .later, day: nil, tasks: sortedByDueDay(later)))
        }
        if !undated.isEmpty { groups.append(TaskListGroup(kind: .undated, day: nil, tasks: undated)) }
        return groups
    }

    // MARK: - 分组策略（阶段1）：纯函数，空桶不出现，组身份是标签文本

    /// 创建时间分组：按创建日倒序（新→旧），同日内保持原顺序。
    /// 标题沿用日期组渲染（今天 / 月日），分组身份 = 那一天。
    private static func createdAtGroups(_ tasks: [Task], now: Date,
                                        calendar: Calendar) -> [TaskListGroup] {
        let today = calendar.startOfDay(for: now)
        let byDay = Dictionary(grouping: tasks) { calendar.startOfDay(for: $0.createdAt) }
        return byDay.keys.sorted(by: >).map { day in
            TaskListGroup(kind: day == today ? .today : .day, day: day, tasks: byDay[day]!)
        }
    }

    /// 优先级分组：高/中/低/无固定顺序。
    private static func priorityGroups(_ tasks: [Task]) -> [TaskListGroup] {
        let buckets: [(TaskPriority, String)] = [
            (.high, "高优先级"), (.medium, "中优先级"), (.low, "低优先级"), (.none, "无优先级")
        ]
        return buckets.compactMap { priority, label in
            let bucket = tasks.filter { $0.priority == priority }
            guard !bucket.isEmpty else { return nil }
            return TaskListGroup(kind: .plain, day: nil, tasks: bucket, label: label)
        }
    }

    /// 清单分组：收集箱在最前，随后按 store.lists 的保存顺序，任务里多出来的
    /// 清单按名字排在最后。
    private static func listGroups(_ tasks: [Task], knownLists: [String]) -> [TaskListGroup] {
        var order = [TaskList.inbox.name]
        order.append(contentsOf: knownLists.filter { $0 != TaskList.inbox.name })
        order.append(contentsOf: Set(tasks.map(\.list.name)).subtracting(order).sorted())
        return order.compactMap { name in
            let bucket = tasks.filter { $0.list.name == name }
            guard !bucket.isEmpty else { return nil }
            return TaskListGroup(kind: .plain, day: nil, tasks: bucket, label: name)
        }
    }

    /// 标签分组：一个任务只落进**第一个**标签组——列表以 task.id 为 SwiftUI 身份，
    /// 同一任务跨组出现会撞 ForEach 的 ID（滴答跨组重复显示，这里明确不做）。
    /// 无标签任务收进最后的"无标签"组。
    private static func tagGroups(_ tasks: [Task]) -> [TaskListGroup] {
        var buckets: [String: [Task]] = [:]
        var untagged: [Task] = []
        for task in tasks {
            if let first = task.tags.first { buckets[first, default: []].append(task) }
            else { untagged.append(task) }
        }
        var groups = buckets.keys.sorted().map { name in
            TaskListGroup(kind: .plain, day: nil, tasks: buckets[name]!, label: name)
        }
        if !untagged.isEmpty {
            groups.append(TaskListGroup(kind: .plain, day: nil, tasks: untagged, label: "无标签"))
        }
        return groups
    }
}
enum TaskListSectionProjection {
    /// 当前清单有自定义分组时按它分桶；没有分组 → nil（调用方沿用用户选的分组方式）。
    ///
    /// - 未分组任务排在最前（分组是**归属**，没归属的先列出来）；
    /// - 空分组也保留（分组是结构，不是"有内容的桶"）；
    /// - 组身份沿用 `.plain` 的标签身份 → 折叠状态按分组互不串。

    /// 「未分组」桶的标题。**唯一真值**：构造点用它，`TaskListGroup.isUnsectionedBucket`
    /// 也靠它判定，两边不会漂。
    static let unsectionedTitle = "未分组"

    static func groups(_ tasks: [Task], list: String,
                       sections: [TaskListSection]) -> [TaskListGroup]? {
        let ordered = sections.filter { $0.listName == list }
            .sorted { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) }
        guard !ordered.isEmpty else { return nil }
        let ids = Set(ordered.map(\.id))
        var groups: [TaskListGroup] = []
        let unsectioned = tasks.filter { task in
            guard let id = task.sectionID else { return true }
            return !ids.contains(id)
        }
        if !unsectioned.isEmpty {
            groups.append(TaskListGroup(kind: .plain, day: nil,
                                        tasks: unsectioned, label: "未分组"))
        }
        for section in ordered {
            groups.append(TaskListGroup(kind: .plain, day: nil,
                                        tasks: tasks.filter { $0.sectionID == section.id },
                                        label: section.title, sectionID: section.id))
        }
        return groups
    }

    /// 高 → 中 → 低 → 无（与 `priorityGroups` 同一顺序）。
    static func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: 0
        case .medium: 1
        case .low: 2
        case .none: 3
        }
    }

    /// 稳定排序：同键任务保持原有相对顺序（否则"恢复默认"会抖动）。
    private static func stable(_ tasks: [Task], less: (Task, Task) -> Bool) -> [Task] {
        tasks.enumerated().sorted { lhs, rhs in
            if less(lhs.element, rhs.element) { return true }
            if less(rhs.element, lhs.element) { return false }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
let df = DateFormatter(); df.calendar = cal; df.timeZone = cal.timeZone; df.dateFormat = "yyyy-MM-dd HH:mm"
let now = df.date(from: "2026-10-14 12:00")!
func task(_ title: String, due: String) -> Task { Task(id: UUID(), title: title, list: TaskList(name: "Work"), priority: .none, schedule: TaskSchedule(dueAt: df.date(from: due)!), parentID: nil, childOrder: 0, createdAt: now, updatedAt: now) }
var tasks=[task("ZZZ",due: "2026-10-12 09:00"), task("AAA",due: "2026-10-14 09:00"), task("BBB",due: "2026-10-17 09:00")]
let store = WorkspaceStore(tasks: tasks, lists: ["Work"])
let root = TaskListProjection.groups(in: .allTasks, store: store, now: now, calendar: cal, grouping: .byDate)
let list = TaskListProjection.groups(in: .allTasks, store: store, now: now, calendar: cal, query: TaskListQuery(list:"Work"), grouping:.byDate)
print("byDate root:",root.map { String(describing:$0.kind) },"byDate list:",list.map { String(describing:$0.kind) })
print("raw group:",list[0].tasks.map(\.title),"ordered group by title:",list[0].orderedTasks(using:.title,calendar:cal).map(\.title))
tasks[0].tags=["A","B"]
let tagStore = WorkspaceStore(tasks: tasks, lists: ["Work"])
let tags = TaskListProjection.groups(in: .allTasks, store: tagStore, now: now, calendar: cal, grouping:.byTag)
print("A+B task tag group:",tags.map { ($0.label ?? "",$0.tasks.map(\.title)) })
let filter = SavedFilter(name:"Work filter",listNames:["Work"])
print("filter before list rename:",FilterEvaluator.matches(tasks[0],filter:filter,now:now,calendar:cal))
tasks[0].list=TaskList(name:"New Work")
print("filter after list rename:",FilterEvaluator.matches(tasks[0],filter:filter,now:now,calendar:cal))
