import Combine
import Foundation

/// 倒数纪念日模块的 Store：记录经 `JSONFileStore` 持久化为 `countdowns.json`，
/// 写入走防抖 `schedule`，终止时由 `flush` 兜底。形状与 `HabitStore` 一致。
@MainActor
final class CountdownStore: ObservableObject, ModuleStoreFlushable {
    /// 未归档的记录：置顶在前，其余按 sortOrder（新建追加到末尾）。
    @Published private(set) var events: [CountdownEvent] = []
    /// 已归档的记录，排序规则同上。
    @Published private(set) var archivedEvents: [CountdownEvent] = []
    /// 跨天刷新用的版本号：倒数天数由「今天」算出，跨天要让界面重算一次。
    @Published private(set) var dateRevision = 0

    private var allEvents: [CountdownEvent] = []
    private let persistence: JSONFileStore<CountdownArchive>
    private let clock: () -> Date
    private let calendar: Calendar
    /// 上次算过的「今天」。定时器每分钟都会来问一次，靠它把重算压到日界那一次。
    private var lastRefreshDay: Date?

    struct CountdownArchive: Codable {
        var events: [CountdownEvent] = []
        /// 色板版本。老文件里没有这个键，解出来是 nil = 版本 1，载入时按
        /// `CountdownPalette.legacyRemap` 把 `colorIndex` 搬一次。
        var paletteVersion: Int? = nil
    }

    init(clock: @escaping () -> Date = Date.init, calendar: Calendar = .current,
         directory: URL? = nil) {
        self.clock = clock
        self.calendar = calendar
        let store: JSONFileStore<CountdownArchive>
        if let directory {
            store = JSONFileStore(filename: "countdowns.json", directory: directory)
        } else {
            store = JSONFileStore(filename: "countdowns.json")
        }
        persistence = store
        let archive = store.load()
        allEvents = CountdownPalette.migrated(archive?.events ?? [], from: archive?.paletteVersion)
        lastRefreshDay = calendar.startOfDay(for: clock())
        refreshDerivedState()
        // 老文件搬过一次就落盘，别每次启动都重搬一遍。搬迁本身幂等（表里是
        // 老下标→新下标），但白写盘一次没有意义。
        if let archive, archive.paletteVersion != CountdownPalette.version {
            store.schedule(CountdownArchive(events: allEvents,
                                            paletteVersion: CountdownPalette.version))
        }
    }

    // MARK: - 增删改

    /// 新建记录。名称去首尾空白，符号/颜色归一化，提醒集合过滤为白名单，
    /// sortOrder 追加到末尾。
    @discardableResult
    func add(name: String, kind: CountdownKind, rule: CountdownRule,
             symbol: String? = nil, colorIndex: Int? = nil,
             reminderOffsets: [Int] = CountdownEvent.defaultReminderOffsets,
             showsInSmartList: Bool = true,
             smartListDisplay: CountdownSmartListDisplay? = nil,
             displayUnit: CountdownDisplayUnit? = nil,
             showsAge: Bool = false,
             note: String = "") -> CountdownEvent {
        let event = CountdownEvent(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            rule: rule,
            symbol: symbol,
            colorIndex: colorIndex.map(normalizedColorIndex),
            reminderOffsets: reminderOffsets,
            showsInSmartList: showsInSmartList,
            smartListDisplay: smartListDisplay,
            displayUnit: displayUnit,
            showsAge: kind.hasAgeOption && showsAge,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            sortOrder: (allEvents.map(\.sortOrder).max() ?? -1) + 1,
            createdAt: clock())
        allEvents.append(event)
        persist()
        return event
    }

    /// 整体替换一条记录（编辑面板提交时用）。身份、归档状态与 sortOrder 保持不变；
    /// 归一化与 `add` 走同一套，避免两条路径写出不同的值。
    func update(_ event: CountdownEvent) {
        guard let index = allEvents.firstIndex(where: { $0.id == event.id }) else { return }
        var next = event
        next.name = event.name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.note = event.note.trimmingCharacters(in: .whitespacesAndNewlines)
        next.symbol = CountdownEvent.symbolOptions.contains(event.symbol)
            ? event.symbol : event.kind.defaultSymbol
        next.colorIndex = normalizedColorIndex(event.colorIndex)
        next.reminderOffsets = CountdownEvent.normalizedReminderOffsets(event.reminderOffsets)
        next.smartListDisplay = event.smartListDisplay
        // 老字段跟新字段保持同步：存量读的是它。
        next.showsInSmartList = event.effectiveSmartListDisplay.showsInSmartList
        // 编辑面板没有「单位」这一项，点卡片轮换出来的值不能被编辑覆盖掉，沿用原值。
        next.displayUnit = allEvents[index].displayUnit
        next.showsAge = event.kind.hasAgeOption && event.showsAge
        // 编辑面板不负责归档与排序，一律沿用原值。
        next.archivedAt = allEvents[index].archivedAt
        next.sortOrder = allEvents[index].sortOrder
        next.createdAt = allEvents[index].createdAt
        allEvents[index] = next
        persist()
    }

    /// 归档：从主列表移出，记录本身保留（可在「已归档」里恢复）。
    func archive(_ id: UUID) {
        guard let index = allEvents.firstIndex(where: { $0.id == id }),
              allEvents[index].archivedAt == nil else { return }
        allEvents[index].archivedAt = clock()
        persist()
    }

    /// 恢复已归档的记录（保留原 sortOrder）。
    func restore(_ id: UUID) {
        guard let index = allEvents.firstIndex(where: { $0.id == id }),
              allEvents[index].archivedAt != nil else { return }
        allEvents[index].archivedAt = nil
        persist()
    }

    /// 彻底删除。与 `HabitStore.hardDelete` 不同，这里不要求先归档——参考实现的
    /// 卡片菜单在未归档状态下也直接给「删除」，删除前由界面确认。
    @discardableResult
    func hardDelete(_ id: UUID) -> Bool {
        guard allEvents.contains(where: { $0.id == id }) else { return false }
        allEvents.removeAll { $0.id == id }
        persist()
        return true
    }

    /// 切换置顶。置顶只影响排序，不改变任何日期语义。
    func togglePin(_ id: UUID) {
        guard let index = allEvents.firstIndex(where: { $0.id == id }) else { return }
        allEvents[index].pinned.toggle()
        persist()
    }

    /// 点卡片轮换主数字的单位：天 → 月 → 周 → 天。
    /// 单位是**每条记录各自**的状态（参照实现里也是各卡独立），所以按 id 改单条。
    /// 从 `effectiveDisplayUnit` 起算，存量记录（nil）第一次点就是从「天」跳到「月」。
    func cycleDisplayUnit(_ id: UUID) {
        guard let index = allEvents.firstIndex(where: { $0.id == id }) else { return }
        allEvents[index].displayUnit = allEvents[index].effectiveDisplayUnit.next
        persist()
    }

    /// 更新备注（卡片菜单「备注」）。
    func setNote(_ id: UUID, note: String) {
        guard let index = allEvents.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allEvents[index].note != trimmed else { return }
        allEvents[index].note = trimmed
        persist()
    }

    /// 更新样式（卡片菜单「样式」）：只动符号与颜色。
    func setStyle(_ id: UUID, symbol: String, colorIndex: Int) {
        guard let index = allEvents.firstIndex(where: { $0.id == id }) else { return }
        allEvents[index].symbol = CountdownEvent.symbolOptions.contains(symbol)
            ? symbol : allEvents[index].kind.defaultSymbol
        allEvents[index].colorIndex = normalizedColorIndex(colorIndex)
        persist()
    }

    /// 在主列表内移动到 `index`（越界自动收敛），并按新顺序重排 sortOrder。
    func move(_ id: UUID, to index: Int) {
        guard let from = events.firstIndex(where: { $0.id == id }), !events.isEmpty else { return }
        let target = min(max(index, 0), events.count - 1)
        guard target != from else { return }
        var ordered = events
        let moved = ordered.remove(at: from)
        ordered.insert(moved, at: target)
        for (position, item) in ordered.enumerated() {
            if let source = allEvents.firstIndex(where: { $0.id == item.id }) {
                allEvents[source].sortOrder = position
            }
        }
        persist()
    }

    // MARK: - 查询

    func event(for id: UUID) -> CountdownEvent? {
        allEvents.first { $0.id == id }
    }

    /// 未归档记录按类型过滤；传 nil 返回全部。
    ///
    /// 收的是集合而不是单个类型：页头「纪念日」胶囊要把生日一起收进来
    /// （见 `CountdownFilter.kinds`），单类型签名表达不了这件事。
    func events(matching kinds: Set<CountdownKind>?) -> [CountdownEvent] {
        guard let kinds else { return events }
        return events.filter { kinds.contains($0.kind) }
    }

    // MARK: - 跨天

    /// 跨天回到应用时调用：天数由「今天」算出，界面据此重算。
    ///
    /// 只在**日界真的跨过**时才 bump 版本号。定时器每分钟都会调它，而农历规则要
    /// 从今天起逐日向上扫一年，没必要每分钟为每张卡片重算一遍。
    func refresh() {
        let today = calendar.startOfDay(for: clock())
        guard lastRefreshDay != today else { return }
        lastRefreshDay = today
        refreshDerivedState()
        dateRevision &+= 1
    }

    // MARK: - Persistence

    func flush(_ completion: @escaping (Error?) -> Void) {
        persistence.flush(completion)
    }

    // MARK: - Private

    private func persist() {
        refreshDerivedState()
        persistence.schedule(CountdownArchive(events: allEvents,
                                              paletteVersion: CountdownPalette.version))
    }

    /// 排序：置顶在前，其余按 sortOrder（同序号回落到创建时间），保证顺序稳定。
    private func refreshDerivedState() {
        let sorted = allEvents.sorted { left, right in
            if left.pinned != right.pinned { return left.pinned }
            if left.sortOrder != right.sortOrder { return left.sortOrder < right.sortOrder }
            return left.createdAt < right.createdAt
        }
        events = sorted.filter(\.isActive)
        archivedEvents = sorted.filter { !$0.isActive }
    }

    /// 颜色下标归一化到 0..<paletteSize（负数也可回绕）。
    private func normalizedColorIndex(_ value: Int) -> Int {
        let count = max(CountdownEvent.paletteSize, 1)
        return ((value % count) + count) % count
    }
}
