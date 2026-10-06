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
            (text.isEmpty || (task.title + "\n" + task.document.plainText).localizedCaseInsensitiveContains(text))
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

/// 清单 14 色板（与 Flutter `desktop/lib/models/list_color.dart` 的
/// `listColorPalette` 逐条同值，**两端必须一起改**），加清单色的稳定推导与
/// 侧栏排序两条纯规则，保持可单测、不依赖 SwiftUI。
///
/// ## 0…10 十一个彩色槽：2026-10-06「提艳」一次
///
/// 起因是用户反馈日历页的任务条「不够亮」。根因不在色板，在**画法**：条是
/// `基色.opacity(0.36)` 叠在近白格底上（格底实测 rgb(242,244,248)），
/// **六成四是底色**，任何颜色都被稀释成粉彩。
///
/// 而白底上「更浅（L↑）」与「更艳（彩度↑）」是**反向**的：想更艳只能更深，
/// 想更浅只能更灰。合同 COLOR-005 记的那次失败正是这条路——降 α 后 L 208→218
/// 但彩度 43→32，用户仍说「太暗了」。**这反过来证明用户说的「暗」= 不鲜艳，
/// 不是亮度低。** 所以这里选「不动 α、只抬基色饱和度」：
/// HSL 里 S×1.55、L 不变，屏幕上的亮度几乎不位移（红 L200→195），
/// 彩度 +45%（47→67）。四个方案（只加浓 α / 提艳 / 提艳+微浓 / 强浓）里，
/// 这是唯一「更艳但不变深」的一档。
///
/// 11/12/13 三个无彩色**没动**：它们是「显式选色」才用得到的槽，
/// 不在自动取色范围内（见 `chromaticSlotCount`）。
enum WFListPalette {
    /// 槽 0…10 为提艳后的值，括号内是提艳前的原值。
    static let argb: [UInt32] = [
        0xFFFF4153, // red      (原 0xFFE35D6A)
        0xFFFF7228, // orange   (原 0xFFE8793F)
        0xFFFFB703, // yellow   (原 0xFFD7A62B)
        0xFFB1C41C, // olive    (原 0xFF9AA63A)
        0xFF27C264, // green    (原 0xFF42A66A)
        0xFF19C7B6, // mint     (原 0xFF38A89D)
        0xFF0AB8DA, // cyan     (原 0xFF2F9FB5)
        0xFF1A82FC, // blue     (原 0xFF4285D4)
        0xFF394DE7, // indigo   (原 0xFF5865C8)
        0xFF7837E6, // purple   (原 0xFF8056C7)
        0xFFE02DA5, // magenta  (原 0xFFC04D9A)
        0xFF9A756A, // warm grey  —— 无彩色，未动
        0xFF66758A, // slate      —— 无彩色，未动
        0xFF8A909B, // grey       —— 无彩色，未动
    ]

    /// 参与**自动取色**的槽位：0…10 是 11 个有彩色，11/12/13 是暖灰 / 板岩 / 灰。
    ///
    /// 自动取色不再落在无彩色上。原因不是审美：灰的清单条会被读成"已完成"——日历
    /// 的已完成档本来就是同一个清单色的淡版（α0.12），一条灰条和一个灰掉的任务在
    /// 屏幕上是同一件事。参考图里也没有一条灰的清单条（实测 80 条，全部有彩）。
    ///
    /// `argb` 表本身不动：它仍是与 Flutter 共享的 14 色契约表，**显式选色**照旧可以
    /// 选到那三个无彩色，只是"按名字自动推"这一步不选它们。
    static let chromaticSlotCount = 11
    /// 落到无彩色槽位时折回的有彩色：11→0（红）、12→4（绿）、13→8（靛）。
    private static let chromaticFallback = [0, 4, 8]

    /// 清单最终落在色板上的下标：显式 meta 优先（越界回退），未选色时按清单名
    /// 做稳定字符折叠（Flutter `listColorValueForName` 同款算法，`% 14`），
    /// 结果落在 11…13 三个无彩色上时折回有彩色（见 `chromaticFallback`）。
    /// 等名永远同色，折叠本身仍与 Flutter 一致。
    static func colorIndex(for name: String, explicit: Int?) -> Int {
        if let explicit, explicit >= 0, explicit < argb.count { return explicit }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        let score = name.unicodeScalars.reduce(0) { ($0 + Int($1.value)) & 0x7FFF_FFFF }
        let slot = score % argb.count
        if slot < chromaticSlotCount { return slot }
        return chromaticFallback[slot - chromaticSlotCount]
    }

    /// **日历条**落在色板上的下标：按任务，不按清单。
    ///
    /// 起因是「收集箱不可着色」——`setListColor` 明确拒绝收集箱（见 `ListMetaTests`），
    /// 而 35 条任务里 20 条都在收集箱，于是整屏只能是同一个蓝。清单色那条路被堵死，
    /// 按任务取色绕开它。代价：日历条不再告诉你任务在哪个清单。
    ///
    /// 散列自己写是因为 `String.hashValue` **每次启动换种子**——用它定色，日历每次重开
    /// 都换一套颜色。FNV-1a 是纯函数；实测在 35 个真实任务 id 上铺满全部 11 个有彩色槽位。
    ///
    /// 槽位只取有彩色（理由同 `chromaticSlotCount`：灰条会被读成「已完成」）。
    /// 一天里偶尔两条同色是正常的：11 个槽抽 5 次只有 34% 不撞，参照图 5 日那格自己
    /// 也有 3 条同色。
    static func taskColorIndex(for taskID: UUID) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325              // FNV-1a 64 位偏移基数
        for byte in taskID.uuidString.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(chromaticSlotCount))
    }
}

/// 侧栏清单显示顺序（对齐 Flutter WorkspaceController.orderedLists）：
/// 置顶在前，其余按 meta sortOrder，再按名字；无 meta 的清单排在有 meta
/// 之后、按字典序。纯函数，便于对排序语义做单测。
/// 侧栏拖放负载：任务（UUID）或**清单**（滴答拖清单叠清单 = 建文件夹）。
///
/// 侧栏原本只有"任务拖到清单 = 移入清单"，加清单互拖后同一个 `String` 传输里
/// 必须能区分两者：清单名带前缀编码，避免引入自定义 UTType。
enum SidebarDragPayload: Equatable {
    static let listPrefix = "wf-list:"
    case task(UUID)
    case list(String)

    static func encode(_ payload: SidebarDragPayload) -> String {
        switch payload {
        case .task(let id): id.uuidString
        case .list(let name): listPrefix + name
        }
    }

    static func decode(_ raw: String) -> SidebarDragPayload? {
        if raw.hasPrefix(listPrefix) {
            let name = String(raw.dropFirst(listPrefix.count))
            return name.isEmpty ? nil : .list(name)
        }
        return UUID(uuidString: raw).map(SidebarDragPayload.task)
    }
}

/// 分组标题的**单一来源**（列表视图与看板视图共用，避免两处各写一套文案）。
enum TaskGroupDisplay {
    static func title(_ group: TaskListGroup, now: Date) -> String {
        switch group.kind {
        case .pinned: "置顶"
        case .overdue: "已过期"
        // 滴答式组标题带星期上下文："今天, 周六"。
        case .today:
            "今天, " + now.formatted(.dateTime.weekday(.abbreviated).locale(.appDate))
        case .upcoming: "最近 7 天"
        case .later: "更远"
        case .undated: "无日期"
        case .day:
            group.day?.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated)
                .locale(.appDate)) ?? ""
        case .plain:
            group.label ?? ""
        case .completed:
            group.day?.formatted(.dateTime.month(.abbreviated).day().locale(.appDate))
                ?? group.label ?? "已完成"
        }
    }
}

/// 清单内自定义分组的投影（滴答第三级）。
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

/// 侧栏清单树节点（滴答层级：文件夹 → 清单；置顶清单仍单独在前）。
enum TaskListSidebarNode: Equatable, Identifiable {
    case list(String)
    case folder(name: String, lists: [String])

    var id: String {
        switch self {
        case .list(let name): "list:\(name)"
        case .folder(let name, _): "folder:\(name)"
        }
    }
}

enum TaskListOrdering {
    /// 侧栏清单树：置顶清单在前，随后是「顶层清单 + 文件夹」按 sortOrder 合并排序。
    ///
    /// - 文件夹是**独立实体**（`TaskListFolder`），位置由它自己的 `sortOrder` 决定，
    ///   所以**空文件夹也有位置**（对齐滴答「先添加文件夹，再放清单」）；
    /// - 清单引用了未登记的文件夹（导入数据的兼容路径）时，按隐式文件夹处理，
    ///   落在它第一个成员的位置；
    /// - 文件夹内成员保持既有顺序；置顶清单永远单独排在前面，不参与折叠。
    static func sidebarTree(_ names: [String], metas: [TaskListMeta],
                            folders: [TaskListFolder] = []) -> [TaskListSidebarNode] {
        let ordered = ordered(names, metas: metas)
        let byName = Dictionary(metas.map { ($0.name, $0) }, uniquingKeysWith: { current, _ in current })

        var folderOrders: [String: Int] = [:]
        for folder in folders { folderOrders[folder.name] = folder.sortOrder }
        for (index, name) in ordered.enumerated() {
            guard byName[name]?.isPinned != true,
                  let folder = byName[name]?.folderName, !folder.isEmpty else { continue }
            if folderOrders[folder] == nil { folderOrders[folder] = index }
        }

        var pinned: [TaskListSidebarNode] = []
        var rest: [(order: Int, name: String, node: TaskListSidebarNode)] = []
        for name in ordered {
            let meta = byName[name]
            if meta?.isPinned == true {
                pinned.append(.list(name))
                continue
            }
            if let folder = meta?.folderName, !folder.isEmpty { continue }  // 收进文件夹节点
            rest.append((meta?.sortOrder ?? Int.max, name, .list(name)))
        }
        for (folder, order) in folderOrders {
            let members = ordered.filter {
                byName[$0]?.folderName == folder && byName[$0]?.isPinned != true
            }
            rest.append((order, folder, .folder(name: folder, lists: members)))
        }
        return pinned + rest
            .sorted { ($0.order, $0.name) < ($1.order, $1.name) }
            .map(\.node)
    }

    static func ordered(_ names: [String], metas: [TaskListMeta]) -> [String] {
        let byName = Dictionary(metas.map { ($0.name, $0) },
                                uniquingKeysWith: { current, _ in current })
        return names.sorted { lhs, rhs in
            let left = byName[lhs], right = byName[rhs]
            if (left?.isPinned ?? false) != (right?.isPinned ?? false) {
                return left?.isPinned ?? false
            }
            let leftOrder = left?.sortOrder ?? Int.max
            let rightOrder = right?.sortOrder ?? Int.max
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return lhs.localizedCompare(rhs) == .orderedAscending
        }
    }
}
