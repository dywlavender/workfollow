import Foundation

/// 一个习惯。JSON 键是 Wave 1 F2 桩引入的 `habits.json` 格式的一部分，
/// 字段调整需保持可重编码（允许新增字段，历史数据解码失败会回退为空库）。
struct Habit: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    /// SF Symbol 名，只能从 `symbolOptions` 白名单中选取。
    var symbol: String
    /// 固定色板下标（0..<`paletteSize`，界面侧负责映射为具体颜色）。
    var colorIndex: Int
    /// 公历 weekday，1 = 周日；空数组表示每天。
    var scheduleDays: [Int]
    var createdAt: Date
    /// nil 表示未归档。
    var archivedAt: Date?
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String = Habit.symbolOptions[0],
        colorIndex: Int = 0,
        scheduleDays: [Int] = [],
        createdAt: Date = Date(timeIntervalSince1970: 0),
        archivedAt: Date? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorIndex = colorIndex
        self.scheduleDays = scheduleDays
        self.createdAt = createdAt
        self.archivedAt = archivedAt
        self.sortOrder = sortOrder
    }

    /// 未归档即为进行中。
    var isActive: Bool { archivedAt == nil }

    /// 展示用符号名：白名单外的历史数据回退到第一个符号。
    var safeSymbol: String {
        Self.symbolOptions.contains(symbol) ? symbol : Self.symbolOptions[0]
    }
}

/// 一次打卡记录：某习惯某天的一条记录（含心得）。`id` 由习惯与日键拼接，
/// 保证“一个习惯一天最多一条”，该键不参与 JSON 编解码。
struct HabitCheckIn: Identifiable, Codable, Equatable {
    var id: String { habitID.uuidString + dayKey }
    let habitID: UUID
    let dayKey: String  // yyyy-MM-dd in the user's calendar.
    var note: String
    let createdAt: Date

    init(habitID: UUID, dayKey: String, note: String = "", createdAt: Date) {
        self.habitID = habitID
        self.dayKey = dayKey
        self.note = note
        self.createdAt = createdAt
    }
}

// MARK: - Symbols & palette

extension Habit {
    /// 符号白名单（新建/编辑页按此顺序展示）。
    static let symbolOptions = [
        "checkmark.circle",
        "figure.run",
        "book",
        "drop",
        "moon.stars",
        "dumbbell",
        "fork.knife",
        "paintbrush",
        "music.note",
        "pills",
    ]

    /// 固定色板数量；具体颜色映射在界面侧（Domain 不依赖 SwiftUI），需与
    /// HabitsWorkspaceView.swift 中的 `habitPalette` 保持一致。
    static let paletteSize = 6

    /// 归一化计划日：仅保留 1...7 并去重排序。
    static func normalizedScheduleDays(_ days: [Int]) -> [Int] {
        Array(Set(days.filter { (1...7).contains($0) })).sorted()
    }
}

// MARK: - Schedule & statistics（纯函数，Calendar 注入）

extension Habit {
    /// 是否计划在某个 weekday（1 = 周日）打卡；空计划 = 每天。
    func isScheduled(onWeekday weekday: Int) -> Bool {
        scheduleDays.isEmpty || scheduleDays.contains(weekday)
    }

    /// 是否计划在某个日期打卡。
    func isScheduled(on date: Date, calendar: Calendar) -> Bool {
        isScheduled(onWeekday: calendar.component(.weekday, from: date))
    }

    /// 当前连续打卡天数：从 `asOf` 往前数连续“计划日”均已打卡的天数。
    /// 今天未打卡不打断（从昨天起算）；今天已打卡且是计划日则计入；
    /// 非计划日既不计数也不打断。
    func currentStreak(asOf date: Date, checkIns: [HabitCheckIn], calendar: Calendar) -> Int {
        let checked = Set(checkIns.filter { $0.habitID == id }.map(\.dayKey))
        var streak = 0
        var day = calendar.startOfDay(for: date)
        if isScheduled(on: day, calendar: calendar),
           checked.contains(Self.dayKey(day, calendar: calendar)) {
            streak += 1
        }
        while let previous = calendar.date(byAdding: .day, value: -1, to: day) {
            day = previous
            guard isScheduled(on: day, calendar: calendar) else { continue }
            guard checked.contains(Self.dayKey(day, calendar: calendar)) else { break }
            streak += 1
        }
        return streak
    }

    /// 区间 [from, to]（按天、含两端）内的计划日数量。
    func scheduledDayCount(from start: Date, to end: Date, calendar: Calendar) -> Int {
        guard start <= end else { return 0 }
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        var count = 0
        while day <= last {
            if isScheduled(on: day, calendar: calendar) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    /// 区间内“计划日已打卡”的天数；非计划日的打卡不计入。
    func checkedDayCount(
        from start: Date, to end: Date, checkIns: [HabitCheckIn], calendar: Calendar
    ) -> Int {
        guard start <= end else { return 0 }
        let checked = Set(checkIns.filter { $0.habitID == id }.map(\.dayKey))
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        var count = 0
        while day <= last {
            if isScheduled(on: day, calendar: calendar),
               checked.contains(Self.dayKey(day, calendar: calendar)) {
                count += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    /// 区间内计划日中已打卡的比例（0...1）；区间内没有计划日时返回 0。
    func checkInRate(
        from start: Date, to end: Date, checkIns: [HabitCheckIn], calendar: Calendar
    ) -> Double {
        let scheduled = scheduledDayCount(from: start, to: end, calendar: calendar)
        guard scheduled > 0 else { return 0 }
        let checked = checkedDayCount(from: start, to: end, checkIns: checkIns, calendar: calendar)
        return Double(checked) / Double(scheduled)
    }
}

// MARK: - Day keys

extension Habit {
    /// 格式化日期为 `yyyy-MM-dd` 日键。
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 把 `yyyy-MM-dd` 日键解析回当天零点；解析失败返回 nil。
    static func date(fromDayKey dayKey: String, calendar: Calendar) -> Date? {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
