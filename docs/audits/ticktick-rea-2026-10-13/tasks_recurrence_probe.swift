import Foundation
struct NativeDocument: Equatable, Codable { static let empty = NativeDocument() }
struct NativeAttachment: Equatable, Codable {}
enum ScheduleDisplay { static func repeatTitle(_ value: TaskRepeat) -> String { value.rawValue } }
enum ChineseWorkCalendar { static func isWorkday(date: Date, calendar: Calendar) -> Bool { ![1,7].contains(calendar.component(.weekday, from: date)) } }
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

/// 日程的领域语义 —— **只此一份**。
///
/// 这些规则此前散在三个层里，靠注释声明"两边一致"：
/// - `TaskDateDraftModel.allDayAnchorHour`（表现层草稿）
/// - `ReminderSchedule.allDayAnchorHour`（通知排期）
/// - `TaskActions.makeNextOccurrence` 里局部的日平移闭包
///
/// 只要有一处改动不同步，就会出现"面板按 09:00 显示、通知在别的时间响"这类漂移。
/// 现在锚点、区间校验、日归一、重复平移都走这里，UI 预览 / 提交 / 通知排期 / 重复生成
/// 共用同一实现。
enum ScheduleSemantics {

    /// 全天任务的锚点小时（09:00）：面板预设、提醒偏移、通知排期共用。
    static let allDayAnchorHour = 9

    /// 某一天的 09:00（全天任务的锚点时刻）。
    static func allDayAnchor(on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: allDayAnchorHour, minute: 0, second: 0,
                      of: calendar.startOfDay(for: day))
    }

    /// 偏移锚点：定时任务取到期时刻本身；全天任务取当天 09:00；无日期则无锚点。
    static func anchor(due: Date?, hasTime: Bool, calendar: Calendar) -> Date? {
        guard let due else { return nil }
        return hasTime ? due : allDayAnchor(on: due, calendar: calendar)
    }

    /// 无时间的日程落在当天 0 点；有时间的原样保留；空值仍是空值。
    static func normalized(_ date: Date?, hasTime: Bool, calendar: Calendar) -> Date? {
        guard let date else { return nil }
        return hasTime ? date : calendar.startOfDay(for: date)
    }

    /// 区间校验：结束**严格早于**开始才非法。
    /// 判据照抄 Flutter `apply()` 的 `to.isBefore(from)`——相等合法（09:00 → 09:00 可提交），
    /// 不要自行改成 `<=`。
    static func rangeError(start: Date?, end: Date?) -> String? {
        guard let start, let end else { return nil }
        return end < start ? "结束时间不能早于开始时间" : nil
    }

    /// 重复生成时的整体平移：按天数平移、保留时刻。
    /// `due` / `dueEnd` / `deadline` / `reminder` 必须用同一条平移，
    /// 否则新实例的截止与提醒会各自落在不同天。
    static func shifted(_ date: Date?, byDays days: Int, calendar: Calendar) -> Date? {
        guard let date else { return nil }
        return calendar.date(byAdding: .day, value: days, to: date)
    }
}

struct ProbeStore {
 var tasks: [Task]
 func children(of id: UUID) -> [Task] { tasks.filter { $0.parentID == id && $0.deletedAt == nil } }
}
struct ProbeActions {
 let store: ProbeStore
 let calendar: Calendar
 let clock: () -> Date
    func makeNextOccurrence(of task: Task, completedAt: Date) -> (spawn: Task, children: [Task])? {
        let base = task.schedule.dueAt ?? calendar.startOfDay(for: completedAt)
        var rule = task.recurrenceRule ?? RecurrenceRule()
        rule.monthDay = rule.monthDay ?? calendar.component(.day, from: base)
        guard let next = rule.nextOccurrence(after: base, frequency: task.recurrence, calendar: calendar) else { return nil }
        let days = calendar.dateComponents([.day], from: base, to: next).day ?? 0
        // 平移规则只有一处实现（`ScheduleSemantics.shifted`）：due / dueEnd / deadline /
        // reminder 用同一条，避免新实例的截止与提醒落到不同天。
        func shifted(_ date: Date?) -> Date? {
            ScheduleSemantics.shifted(date, byDays: days, calendar: calendar)
        }
        let now = clock()
        var spawn = Task(id: UUID(), title: task.title, document: task.document,
                         tags: task.tags, recurrence: task.recurrence, list: task.list,
                         priority: task.priority, schedule: task.schedule,
                         parentID: task.parentID, childOrder: task.childOrder,
                         createdAt: now, updatedAt: now)
        spawn.schedule.dueAt = next
        spawn.schedule.dueEndAt = shifted(task.schedule.dueEndAt)
        spawn.schedule.deadlineAt = shifted(task.schedule.deadlineAt)
        spawn.reminderAt = shifted(task.reminderAt)
        spawn.reminderOffsets = task.reminderOffsets
        spawn.attachments = task.attachments
        spawn.recurrenceRule = rule.following
        // 艾宾浩斯：interval 承载"已完成次数",spawn 带着递增后的值,引擎据此
        // 取记忆曲线的下一段间隔（RecurrenceRule.nextOccurrence .ebbinghaus）。
        if task.recurrence == .ebbinghaus {
            var ebbingRule = spawn.recurrenceRule ?? RecurrenceRule()
            ebbingRule.interval = max(1, ebbingRule.interval) + 1
            spawn.recurrenceRule = ebbingRule
        }
        spawn.sourceNoteID = task.sourceNoteID
        let children = store.children(of: task.id).enumerated().map { order, child -> Task in
            var value = Task(id: UUID(), title: child.title, document: child.document,
                             tags: child.tags, list: child.list, priority: child.priority,
                             schedule: child.schedule, parentID: spawn.id, childOrder: order,
                             createdAt: now, updatedAt: now)
            value.schedule.dueAt = shifted(child.schedule.dueAt)
            value.schedule.dueEndAt = shifted(child.schedule.dueEndAt)
            value.schedule.deadlineAt = shifted(child.schedule.deadlineAt)
            value.reminderAt = shifted(child.reminderAt)
            value.reminderOffsets = child.reminderOffsets
            value.attachments = child.attachments
            value.convertedNoteID = child.convertedNoteID
            value.sourceNoteID = child.sourceNoteID
            // Fresh defaults: status .active, recurrence .never, rule nil —
            // only the parent drives the chain of occurrences.
            return value
        }
        return (spawn, children)
    }

}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
let df = DateFormatter()
df.calendar = cal; df.timeZone = cal.timeZone; df.dateFormat = "yyyy-MM-dd HH:mm"
let now = df.date(from: "2026-10-14 12:00")!
let due = df.date(from: "2026-10-10 09:00")!
let original = Task(id: UUID(), title: "Daily standup", recurrence: .daily,
 list: TaskList(name: "Work"), priority: .high,
 schedule: TaskSchedule(dueAt: due, hasTime: true), parentID: nil, childOrder: 0,
 createdAt: due, updatedAt: due, isPinned: true, sectionID: "doing")
let actions = ProbeActions(store: ProbeStore(tasks: [original]), calendar: cal, clock: { now })
let next = actions.makeNextOccurrence(of: original, completedAt: now)!.spawn
print("original section:",original.sectionID ?? "nil", "next section:",next.sectionID ?? "nil")
print("original due:",df.string(from:due),"completed:",df.string(from:now),"next due:",df.string(from:next.schedule.dueAt!))
