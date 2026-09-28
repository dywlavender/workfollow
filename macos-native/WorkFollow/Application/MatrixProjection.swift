import Foundation

/// 四象限的四个分类。顺序即棋盘顺序，数值即归类结果的下标。
enum MatrixQuadrant: Int, CaseIterable, Identifiable {
    case doNow = 0
    case schedule = 1
    case delegate = 2
    case later = 3

    var id: Int { rawValue }

    /// 稳定标识片段。分组的 id 由它拼出来，折叠状态也按它成组（对齐 Flutter
    /// 用 `quadrant.name` 做前缀的做法）。
    var key: String {
        switch self {
        case .doNow: "doNow"
        case .schedule: "schedule"
        case .delegate: "delegate"
        case .later: "later"
        }
    }

    /// 序号。原版用拉丁大写 I / II / III / IV。
    var numeral: String {
        switch self {
        case .doNow: "I"
        case .schedule: "II"
        case .delegate: "III"
        case .later: "IV"
        }
    }

    var title: String {
        switch self {
        case .doNow: "重要且紧急"
        case .schedule: "重要不紧急"
        case .delegate: "不重要但紧急"
        case .later: "不重要不紧急"
        }
    }

    /// 在这个象限里新建任务的默认优先级。
    var defaultPriority: TaskPriority {
        switch self {
        case .doNow, .schedule: .high
        case .delegate: .low
        case .later: .none
        }
    }

    /// 在这个象限里新建任务的默认安排日（相对今天的天数；nil = 不安排日期）。
    var defaultScheduleOffset: Int? {
        switch self {
        case .doNow: 0
        case .schedule: 7
        case .delegate: 0
        case .later: nil
        }
    }
}

/// 一行任务在四象限里需要的全部读法。派生值算在投影层，视图不再自己推日期
/// 标签或探测是否有子任务。
struct MatrixTaskViewModel: Identifiable, Equatable {
    let task: Task
    let listName: String
    let dateLabel: String?
    let overdue: Bool
    let hasNote: Bool
    let hasSubtasks: Bool
    let hasReminder: Bool
    let recurring: Bool

    var id: UUID { task.id }
}

/// 一个清单分组，或该象限的「已完成」分组。
struct MatrixGroupViewModel: Identifiable, Equatable {
    let id: String
    let title: String
    let count: Int
    let completedGroup: Bool
    let tasks: [MatrixTaskViewModel]
}

struct MatrixQuadrantViewModel: Identifiable, Equatable {
    let quadrant: MatrixQuadrant
    let groups: [MatrixGroupViewModel]

    var id: Int { quadrant.rawValue }
    var taskCount: Int { groups.reduce(0) { $0 + $1.count } }

    /// 「显示已完成」开关走的就是这个分组：原版把它做成一个 id 固定的分组
    /// 回传给页面，象限自己不再留一份可见性状态。
    static let completedToggleID = "__toggle-completed__"
}

/// 把平铺的任务集合折成四象限要画的两层结构：活动任务按清单分组，
/// 每个象限末尾挂一个「已完成」分组。纯函数，不碰任务本身。
enum MatrixProjection {
    /// 清单分组的 id。折叠按 id 记，不按标题——两个象限里可能有同名清单。
    static func listGroupID(_ quadrant: MatrixQuadrant, _ listName: String) -> String {
        "\(quadrant.key):list:\(listName)"
    }

    /// 该象限「已完成」分组的 id。
    static func completedGroupID(_ quadrant: MatrixQuadrant) -> String {
        "\(quadrant.key):completed"
    }

    /// 某个象限所有分组的 id 前缀，供「全部展开 / 全部折叠」按象限成组使用。
    static func groupIDPrefix(_ quadrant: MatrixQuadrant) -> String {
        "\(quadrant.key):"
    }

    static func project(tasks: [Task],
                        now: Date,
                        listOrder: [String],
                        includeCompleted: Bool = true,
                        calendar: Calendar = .current,
                        hasChildren: (UUID) -> Bool = { _ in false })
        -> [MatrixQuadrantViewModel] {
        var order: [String] = []
        var seen: Set<String> = []
        for raw in listOrder {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, seen.insert(name).inserted { order.append(name) }
        }

        var active: [MatrixQuadrant: [String: [Task]]] = [:]
        var completed: [MatrixQuadrant: [Task]] = [:]
        for quadrant in MatrixQuadrant.allCases {
            active[quadrant] = [:]
            completed[quadrant] = []
        }

        for task in tasks {
            if task.deletedAt != nil || task.skippedAt != nil || task.isAbandoned || task.isConverted {
                continue
            }
            if !includeCompleted, task.status == .completed { continue }
            let quadrant = MatrixQuadrant(
                rawValue: PlanningProjection.quadrant(task, now: now, calendar: calendar)) ?? .later
            if task.status == .completed {
                completed[quadrant, default: []].append(task)
                continue
            }
            let listName = normalizedListName(task)
            active[quadrant]?[listName, default: []].append(task)
            if seen.insert(listName).inserted { order.append(listName) }
        }

        return MatrixQuadrant.allCases.map { quadrant in
            let groups = active[quadrant] ?? [:]
            var viewModels: [MatrixGroupViewModel] = []
            for listName in order {
                guard let tasks = groups[listName], !tasks.isEmpty else { continue }
                viewModels.append(MatrixGroupViewModel(
                    id: listGroupID(quadrant, listName),
                    title: listName,
                    count: tasks.count,
                    completedGroup: false,
                    tasks: tasks.map { row($0, now: now, calendar: calendar, hasChildren: hasChildren) }))
            }
            let done = completed[quadrant] ?? []
            if !done.isEmpty {
                viewModels.append(MatrixGroupViewModel(
                    id: completedGroupID(quadrant),
                    title: "已完成",
                    count: done.count,
                    completedGroup: true,
                    tasks: done.map { row($0, now: now, calendar: calendar, hasChildren: hasChildren) }))
            }
            return MatrixQuadrantViewModel(quadrant: quadrant, groups: viewModels)
        }
    }

    /// 空清单名落到收集箱，和列表页一致。
    static func normalizedListName(_ task: Task) -> String {
        let name = task.list.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? TaskList.inbox.name : name
    }

    private static func row(_ task: Task,
                            now: Date,
                            calendar: Calendar,
                            hasChildren: (UUID) -> Bool) -> MatrixTaskViewModel {
        let dueAt = task.schedule.dueAt
        let anchor = dueAt ?? (task.status == .completed ? task.completedAt : nil)
        let today = calendar.startOfDay(for: now)
        let day = anchor.map { calendar.startOfDay(for: $0) }
        return MatrixTaskViewModel(
            task: task,
            listName: normalizedListName(task),
            dateLabel: dateLabel(for: anchor, now: now, calendar: calendar),
            overdue: task.status != .completed && (day.map { $0 < today } ?? false),
            hasNote: !task.document.isEmpty,
            hasSubtasks: hasChildren(task.id),
            hasReminder: task.reminderAt != nil || !(task.reminderOffsets ?? []).isEmpty,
            recurring: task.recurrence != .never)
    }

    /// 行内日期标签：先相对日，再星期，最后日历日期。
    ///
    /// 星期这一档是让「下周二」短到能和清单名、属性图标同处一行的原因。
    /// 对齐 Flutter `MatrixProjection._dateLabel`（周一起算的一周）。
    static func dateLabel(for date: Date?, now: Date, calendar: Calendar = .current) -> String? {
        guard let date else { return nil }
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        let difference = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        if difference == 0 { return "今天" }
        if difference == 1 { return "明天" }
        if difference == -1 { return "昨天" }

        let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]
        // Calendar 的工作日编号是 周日 1 … 周六 7，标签表是周一开头。
        let weekdayIndex = (calendar.component(.weekday, from: target) + 5) % 7
        let weekday = weekdayNames[weekdayIndex]
        let daysFromMonday = (calendar.component(.weekday, from: today) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) else {
            return nil
        }
        let days = calendar.dateComponents([.day], from: monday, to: target).day ?? 0
        let week = days / 7   // 与 Dart 的 ~/ 同为向零截断
        if week == 0 { return "周\(weekday)" }
        if week == 1 { return "下周\(weekday)" }

        let year = calendar.component(.year, from: target)
        let thisYear = calendar.component(.year, from: today)
        let month = calendar.component(.month, from: target)
        let day = calendar.component(.day, from: target)
        return year == thisYear ? "\(month)月\(day)日" : "\(year)年\(month)月\(day)日"
    }
}
