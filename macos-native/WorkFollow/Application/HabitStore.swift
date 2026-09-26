import Combine
import Foundation

/// 习惯打卡模块的 Store（Wave 1 F2）：习惯 + 每日打卡记录，经 `JSONFileStore`
/// 持久化为 `habits.json`。写入走防抖 `schedule`，终止时由 `flush` 兜底。
@MainActor
final class HabitStore: ObservableObject, ModuleStoreFlushable {
    /// 进行中的习惯（排除已归档），按 sortOrder 排序。
    @Published private(set) var habits: [Habit] = []
    /// 已归档的习惯，按 sortOrder 排序。
    @Published private(set) var archivedHabits: [Habit] = []
    /// 全部打卡记录（未排序，保持写入顺序）。
    @Published private(set) var checkIns: [HabitCheckIn] = []
    /// 今天计划打卡的习惯（按 sortOrder，排除已归档与非计划日）。
    @Published private(set) var todaysHabits: [Habit] = []

    /// 包括已归档在内的全部习惯（按 sortOrder 排序）。
    var habitsIncludingArchived: [Habit] { allHabits }

    private var allHabits: [Habit] = []
    private let persistence: JSONFileStore<HabitArchive>
    private let clock: () -> Date
    private var calendar: Calendar { .current }

    struct HabitArchive: Codable {
        var habits: [Habit] = []
        var checkIns: [HabitCheckIn] = []
    }

    init(clock: @escaping () -> Date = Date.init, directory: URL? = nil) {
        self.clock = clock
        let store: JSONFileStore<HabitArchive>
        if let directory {
            store = JSONFileStore(filename: "habits.json", directory: directory)
        } else {
            store = JSONFileStore(filename: "habits.json")
        }
        persistence = store
        let loaded = store.load() ?? HabitArchive()
        allHabits = loaded.habits
        checkIns = loaded.checkIns
        refreshDerivedState()
    }

    // MARK: - 增删改

    /// 新建习惯；名称去首尾空白，符号/颜色归一化到白名单与色板，
    /// 计划日过滤为合法 weekday，sortOrder 追加到末尾。
    @discardableResult
    func add(
        name: String,
        symbol: String = Habit.symbolOptions[0],
        colorIndex: Int = 0,
        scheduleDays: [Int] = []
    ) -> Habit {
        let habit = Habit(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            symbol: Habit.symbolOptions.contains(symbol) ? symbol : Habit.symbolOptions[0],
            colorIndex: normalizedColorIndex(colorIndex),
            scheduleDays: Habit.normalizedScheduleDays(scheduleDays),
            createdAt: clock(),
            sortOrder: (allHabits.map(\.sortOrder).max() ?? -1) + 1)
        allHabits.append(habit)
        persist()
        return habit
    }

    /// 更新名称/符号/颜色/计划日；传 nil 的字段保持不变，身份与打卡记录不受影响。
    func update(
        _ id: UUID,
        name: String? = nil,
        symbol: String? = nil,
        colorIndex: Int? = nil,
        scheduleDays: [Int]? = nil
    ) {
        guard let index = allHabits.firstIndex(where: { $0.id == id }) else { return }
        if let name {
            allHabits[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let symbol, Habit.symbolOptions.contains(symbol) {
            allHabits[index].symbol = symbol
        }
        if let colorIndex {
            allHabits[index].colorIndex = normalizedColorIndex(colorIndex)
        }
        if let scheduleDays {
            allHabits[index].scheduleDays = Habit.normalizedScheduleDays(scheduleDays)
        }
        persist()
    }

    /// 归档：从今日列表与进行中列表移除，历史打卡保留。
    func archive(_ id: UUID) {
        guard let index = allHabits.firstIndex(where: { $0.id == id }),
              allHabits[index].archivedAt == nil else { return }
        allHabits[index].archivedAt = clock()
        persist()
    }

    /// 恢复已归档的习惯（保留原 sortOrder）。
    func restore(_ id: UUID) {
        guard let index = allHabits.firstIndex(where: { $0.id == id }),
              allHabits[index].archivedAt != nil else { return }
        allHabits[index].archivedAt = nil
        persist()
    }

    /// 彻底删除：仅允许删除已归档的习惯，并连带删除它的全部打卡记录。
    @discardableResult
    func hardDelete(_ id: UUID) -> Bool {
        guard let habit = allHabits.first(where: { $0.id == id }), habit.archivedAt != nil else {
            return false
        }
        allHabits.removeAll { $0.id == id }
        checkIns.removeAll { $0.habitID == id }
        persist()
        return true
    }

    /// 在进行中列表内把习惯移动到 `index`（越界自动收敛），并按新顺序重排 sortOrder。
    func move(_ id: UUID, to index: Int) {
        guard let from = habits.firstIndex(where: { $0.id == id }),
              !habits.isEmpty else { return }
        let target = min(max(index, 0), habits.count - 1)
        guard target != from else { return }
        var ordered = habits
        let habit = ordered.remove(at: from)
        ordered.insert(habit, at: target)
        for (position, item) in ordered.enumerated() {
            if let source = allHabits.firstIndex(where: { $0.id == item.id }) {
                allHabits[source].sortOrder = position
            }
        }
        persist()
    }

    // MARK: - 打卡

    /// 打卡/补打卡：同一习惯同一天只会有一条记录（幂等）；已打卡且 `note`
    /// 为 nil 或与原值相同时不产生变化。`note` 非 nil 时刷新当天心得。
    @discardableResult
    func checkIn(_ habitID: UUID, dayKey: String, note: String? = nil) -> Bool {
        if let index = checkIns.firstIndex(where: { $0.habitID == habitID && $0.dayKey == dayKey }) {
            guard let note, checkIns[index].note != note else { return false }
            checkIns[index].note = note
            persist()
            return true
        }
        checkIns.append(
            HabitCheckIn(habitID: habitID, dayKey: dayKey, note: note ?? "", createdAt: clock()))
        persist()
        return true
    }

    /// 取消打卡（连同当天心得一并移除）；未打卡时无副作用。
    @discardableResult
    func uncheck(_ habitID: UUID, dayKey: String) -> Bool {
        let before = checkIns.count
        checkIns.removeAll { $0.habitID == habitID && $0.dayKey == dayKey }
        guard checkIns.count != before else { return false }
        persist()
        return true
    }

    /// 打卡圆环用的翻转便捷方法：已打卡则取消，未打卡则打卡（不改动已有心得）。
    func toggleCheckIn(_ habitID: UUID, dayKey: String) {
        if checkInRecord(habitID: habitID, dayKey: dayKey) != nil {
            uncheck(habitID, dayKey: dayKey)
        } else {
            checkIn(habitID, dayKey: dayKey)
        }
    }

    /// 保存某天的心得：当天未打卡时创建打卡记录；空白心得清空原心得但保留打卡；
    /// 内容无变化时不写入。
    func saveNote(_ habitID: UUID, dayKey: String, note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = checkIns.firstIndex(where: { $0.habitID == habitID && $0.dayKey == dayKey }) {
            guard checkIns[index].note != trimmed else { return }
            checkIns[index].note = trimmed
            persist()
            return
        }
        guard !trimmed.isEmpty else { return }
        checkIn(habitID, dayKey: dayKey, note: trimmed)
    }

    // MARK: - 查询

    /// 某习惯的全部打卡记录，按日键倒序（最新在前）。
    func checkIns(for habitID: UUID) -> [HabitCheckIn] {
        checkIns
            .filter { $0.habitID == habitID }
            .sorted {
                $0.dayKey == $1.dayKey ? $0.createdAt > $1.createdAt : $0.dayKey > $1.dayKey
            }
    }

    /// 某习惯某天的打卡记录；未打卡返回 nil。
    func checkInRecord(habitID: UUID, dayKey: String) -> HabitCheckIn? {
        checkIns.first { $0.habitID == habitID && $0.dayKey == dayKey }
    }

    /// 某习惯某天是否已打卡。
    func isChecked(_ habitID: UUID, dayKey: String) -> Bool {
        checkInRecord(habitID: habitID, dayKey: dayKey) != nil
    }

    /// 以 Store 当前时刻计算的连续打卡天数。
    func currentStreak(of habit: Habit) -> Int {
        habit.currentStreak(asOf: clock(), checkIns: checkIns, calendar: calendar)
    }

    /// Store 当前时刻的日键（yyyy-MM-dd）。
    var todayKey: String { Self.dayKey(clock(), calendar: calendar) }

    /// 重算派生状态（跨天回到应用时调用，刷新今日列表）。
    func refresh() {
        refreshDerivedState()
    }

    // MARK: - 日键

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        Habit.dayKey(date, calendar: calendar)
    }

    // MARK: - Persistence

    func flush(_ completion: @escaping (Error?) -> Void) {
        persistence.flush(completion)
    }

    // MARK: - Private

    private func persist() {
        refreshDerivedState()
        persistence.schedule(HabitArchive(habits: allHabits, checkIns: checkIns))
    }

    private func refreshDerivedState() {
        let sorted = allHabits.sorted {
            $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder
        }
        habits = sorted.filter(\.isActive)
        archivedHabits = sorted.filter { !$0.isActive }
        let weekday = calendar.component(.weekday, from: clock())
        todaysHabits = habits.filter { $0.isScheduled(onWeekday: weekday) }
    }

    /// 颜色下标归一化到 0..<paletteSize（负数也可回绕）。
    private func normalizedColorIndex(_ value: Int) -> Int {
        let count = max(Habit.paletteSize, 1)
        return ((value % count) + count) % count
    }
}
