import Foundation

/// 智能清单里的一条倒数记录——渲染需要的最小信息，**不含 `Task`**。
///
/// 参考图 `18-countdown-in-today-group.png`：行 = 图标 + 名称 + **右对齐的相对日标签**，
/// **没有勾选框**（它不是任务，不可完成）。
struct CountdownSmartListEntry: Identifiable, Equatable {
    let id: UUID
    let name: String
    let symbol: String
    let colorIndex: Int
    /// 距落点还有几天；0 = 今天。负数 = 已经过去。
    let daysUntil: Int
    /// 右侧那个相对日标签。
    let relativeLabel: String
}

/// 智能清单里的「倒数纪念日」小节。
///
/// 参考图里它**自成一节**（不是混进任务组）：标题 + 条数，下面是若干行。
/// 标题就是模块名，与侧栏一致。
struct CountdownSmartListSection: Equatable {
    static let title = "倒数纪念日"

    let entries: [CountdownSmartListEntry]

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    static let empty = CountdownSmartListSection(entries: [])
}

/// 「显示」行真正落地的地方——把 `CountdownSmartListDisplay` 从「存了但没人读」
/// 变成「决定这条记录进不进智能清单」。
///
/// 纯函数、不依赖 SwiftUI，便于单测。整条链路上**只有这里**解释那个字段的语义，
/// 界面只管把结果画出来。
enum CountdownSmartListProjection {

    /// 一条记录在 `daysUntil` 天前是否该出现在智能清单里。
    ///
    /// 判据两条：① `effectiveSmartListDisplay` 给的**提前量**是否覆盖今天；
    /// ② 落点是不是**已经过去**。
    ///
    /// **取舍（已过去的记录）**：`daysUntil < 0` 一律不进清单，**含「一直显示」**。
    /// 参照图只观察到「当天显示 + 落点就是今天」这一态，过期的单次记录该怎么处理
    /// 无从判断；放进「今天」会让一条早就过完的记录永远挂在今天，代价明显大于收益。
    /// 重复类记录的落点永远在未来，不受这条影响。
    ///
    /// **取舍（提前量的边界）**：「提前 3 天显示」按「从 3 天前开始显示」实现，
    /// 即 `0...3` 共 4 天，而不是「只在第 3 天那一天显示」。
    static func isVisible(_ event: CountdownEvent, daysUntil: Int) -> Bool {
        guard daysUntil >= 0 else { return false }
        switch event.effectiveSmartListDisplay {
        case .never: return false
        case .sameDay: return daysUntil == 0
        case .threeDaysBefore: return daysUntil <= 3
        case .sevenDaysBefore: return daysUntil <= 7
        case .always: return true
        }
    }

    /// 右侧那个相对日标签。
    ///
    /// 参考图实测只有 0 天那一态：**「今天」**（`18-countdown-in-today-group.png`）。
    /// 其余取值是**取舍**，没有参照可对——照同一份参照图里任务行的相对日口径
    /// （「昨天」）取的，没有用绝对日期。
    static func relativeLabel(daysUntil: Int) -> String {
        switch daysUntil {
        case 0: return "今天"
        case 1: return "明天"
        case -1: return "昨天"
        case let n where n > 1: return "\(n) 天后"
        default: return "\(-daysUntil) 天前"
        }
    }

    /// 生成小节。没有可见记录时返回 `.empty`，调用方据此整节不渲染
    /// （标题带条数，空着渲染出来就是「倒数纪念日 0」这种噪音）。
    ///
    /// 排序：**近的在前**；同一天保持传入顺序——store 已经排好
    /// （置顶 → sortOrder → 创建时间），这里不再另立一套。
    static func section(events: [CountdownEvent], now: Date,
                        calendar: Calendar = .current) -> CountdownSmartListSection {
        let today = calendar.startOfDay(for: now)
        let visible = events.compactMap { event -> CountdownSmartListEntry? in
            guard event.isActive else { return nil }
            let occurrence = event.occurrence(onOrAfter: today, calendar: calendar)
            let daysUntil = calendar.dateComponents([.day], from: today, to: occurrence).day ?? 0
            guard isVisible(event, daysUntil: daysUntil) else { return nil }
            return CountdownSmartListEntry(
                id: event.id,
                name: event.displayName,
                symbol: event.safeSymbol,
                colorIndex: event.colorIndex,
                daysUntil: daysUntil,
                relativeLabel: relativeLabel(daysUntil: daysUntil))
        }
        let ordered = visible.enumerated().sorted { lhs, rhs in
            lhs.element.daysUntil == rhs.element.daysUntil
                ? lhs.offset < rhs.offset
                : lhs.element.daysUntil < rhs.element.daysUntil
        }.map(\.element)
        return CountdownSmartListSection(entries: ordered)
    }
}
