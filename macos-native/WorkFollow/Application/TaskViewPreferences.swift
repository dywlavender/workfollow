import Foundation

/// 任务列表的分组方式（阶段1）。`byDate` 是"所有任务"的默认并保持历史行为；
/// 今天/最近 7 天/已完成的日期分组是视图本体，投影层会忽略这里的值（见
/// TaskListProjection.groups 的分支条件）。
enum TaskListGrouping: String, CaseIterable, Codable, Identifiable {
    case byDate, none, byPriority, byList, byTag

    var id: String { rawValue }

    var title: String {
        switch self {
        case .byDate: "按日期分组"
        case .none: "无分组"
        case .byPriority: "按优先级分组"
        case .byList: "按清单分组"
        case .byTag: "按标签分组"
        }
    }

    /// 分组菜单的可用项（纯函数，UI 与单测共用同一份规则）：智能清单根视图全部
    /// 可用；清单视图没有"按清单"、标签视图没有"按标签"；时间型视图不提供分组。
    static func availableOptions(destination: NativeDestination,
                                 activeList: String?, activeTag: String?) -> [TaskListGrouping] {
        guard destination == .allTasks else { return [] }
        switch (activeList != nil, activeTag != nil) {
        case (false, false): return [.byDate, .none, .byPriority, .byList, .byTag]
        case (true, false): return [.none, .byDate, .byPriority, .byTag]
        case (false, true): return [.none, .byDate, .byPriority, .byList]
        case (true, true): return [.none, .byDate, .byPriority]
        }
    }

    /// 没有持久化偏好时的默认值：智能根视图保持历史日期分组，清单/标签视图保持平铺。
    /// 默认值只在**缺键**时生效，用户显式选过就以用户为准。
    static func fallback(allTasksRoot: Bool) -> TaskListGrouping {
        allTasksRoot ? .byDate : .none
    }
}

/// 视图偏好的键：清单/标签视图按名字，智能视图按 destination。
/// 清单改名后旧键失效、回落默认——排序是低价值偏好，不做改名迁移。
enum TaskViewScopeKey {
    static func key(destination: NativeDestination, activeList: String?, activeTag: String?) -> String {
        if let activeList { return "list:" + activeList }
        if let activeTag { return "tag:" + activeTag }
        return "scope:" + destination.rawValue
    }
}

/// 单个视图的偏好。两个键都可缺：旧档案缺键解码为 nil，读取时回落默认。
struct TaskViewPreference: Equatable, Codable {
    var sortMode: TaskListSortMode?
    var grouping: TaskListGrouping?

    init(sortMode: TaskListSortMode? = nil, grouping: TaskListGrouping? = nil) {
        self.sortMode = sortMode
        self.grouping = grouping
    }

    private enum CodingKeys: String, CodingKey { case sortMode, grouping }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sortMode = try values.decodeIfPresent(TaskListSortMode.self, forKey: .sortMode)
        grouping = try values.decodeIfPresent(TaskListGrouping.self, forKey: .grouping)
    }
}

/// 任务列表的排序/分组记忆（阶段0）。模块级 JSON 小文件
/// （modules/view-preferences.json），与任务快照分开存取：重放/恢复任务数据
/// 不会把视图偏好一起冲掉。模式对齐 TemplateStore（同款防抖原子写 + 终止 flush）。
@MainActor
final class TaskViewPreferenceStore: ObservableObject, ModuleStoreFlushable {
    struct Archive: Codable {
        var preferences: [String: TaskViewPreference] = [:]
    }

    @Published private(set) var preferences: [String: TaskViewPreference]

    private let persistence: JSONFileStore<Archive>

    init(directory: URL? = nil) {
        let store = JSONFileStore<Archive>(filename: "view-preferences.json",
                                           directory: directory ?? JSONFileStore<Archive>.moduleDirectory)
        persistence = store
        preferences = store.load()?.preferences ?? [:]
    }

    /// 未选过 = 手动排序（滴答证实的"每个视图记忆排序"，缺省即旧行为）。
    func sortMode(for key: String) -> TaskListSortMode {
        preferences[key]?.sortMode ?? .manual
    }

    func grouping(for key: String, allTasksRoot: Bool) -> TaskListGrouping {
        preferences[key]?.grouping ?? TaskListGrouping.fallback(allTasksRoot: allTasksRoot)
    }

    func setSortMode(_ mode: TaskListSortMode, for key: String) {
        var entry = preferences[key] ?? TaskViewPreference()
        guard entry.sortMode != mode else { return }
        entry.sortMode = mode
        preferences[key] = entry
        persist()
    }

    func setGrouping(_ grouping: TaskListGrouping, for key: String) {
        var entry = preferences[key] ?? TaskViewPreference()
        guard entry.grouping != grouping else { return }
        entry.grouping = grouping
        preferences[key] = entry
        persist()
    }

    func flush(_ completion: @escaping (Error?) -> Void) {
        persistence.flush(completion)
    }

    private func persist() {
        persistence.schedule(Archive(preferences: preferences))
    }
}
