import Combine
import Foundation

/// 任务列表的分组方式（阶段1）。`byDate` 是"所有任务"的默认并保持历史行为；
/// 今天/最近 7 天/已完成的日期分组是视图本体，投影层会忽略这里的值（见
/// TaskListProjection.groups 的分支条件）。
enum TaskListGrouping: String, CaseIterable, Codable, Identifiable {
    case byDate, none, byPriority, byList, byTag, byCreatedAt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .byDate: "按日期分组"
        case .none: "无分组"
        case .byPriority: "按优先级分组"
        case .byList: "按清单分组"
        case .byTag: "按标签分组"
        case .byCreatedAt: "按创建时间分组"
        }
    }

    /// 分组菜单的可用项（纯函数，UI 与单测共用同一份规则）：智能清单根视图全部
    /// 可用；清单视图没有"按清单"、标签视图没有"按标签"；时间型视图不提供分组。
    static func availableOptions(destination: NativeDestination,
                                 activeList: String?, activeTag: String?) -> [TaskListGrouping] {
        guard destination == .allTasks else { return [] }
        switch (activeList != nil, activeTag != nil) {
        case (false, false): return [.byDate, .none, .byPriority, .byList, .byTag, .byCreatedAt]
        case (true, false): return [.none, .byDate, .byPriority, .byTag, .byCreatedAt]
        case (false, true): return [.none, .byDate, .byPriority, .byList, .byCreatedAt]
        case (true, true): return [.none, .byDate, .byPriority, .byCreatedAt]
        }
    }

    /// 没有持久化偏好时的默认值：智能根视图保持历史日期分组，清单/标签视图保持平铺。
    /// 默认值只在**缺键**时生效，用户显式选过就以用户为准。
    static func fallback(allTasksRoot: Bool) -> TaskListGrouping {
        allTasksRoot ? .byDate : .none
    }
}

/// 视图形态（滴答清单页 ··· → 视图：列表 / 看板 / 时间线）。
/// 时间线按普通清单或保存过滤器的范围开放。
enum TaskListViewMode: String, CaseIterable, Codable, Identifiable {
    case list
    case kanban
    case timeline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "列表"
        case .kanban: "看板"
        case .timeline: "时间线"
        }
    }

    /// Smart scopes keep their existing two presentations. Ordinary lists and
    /// saved filters opt into the schedule-capable timeline below.
    static let exposedCases: [TaskListViewMode] = [.list, .kanban]

    static func availableOptions(destination: NativeDestination, activeList: String?,
                                 activeTag: String?, activeFilterID: UUID? = nil) -> [TaskListViewMode] {
        guard destination == .allTasks, activeTag == nil else { return exposedCases }
        let ordinaryList = activeList.map { $0 != TaskList.inbox.name } ?? false
        return ordinaryList || activeFilterID != nil ? [.list, .kanban, .timeline] : exposedCases
    }
}

/// 智能清单的显示状态（对齐滴答：显示 / 隐藏 / 有内容时显示）。
enum SmartListVisibility: String, Codable, CaseIterable, Identifiable {
    case visible, hidden, automatic

    var id: String { rawValue }

    /// 菜单顺序对齐滴答（实测 2026-10-25：有内容时显示 → 显示 → 隐藏）。
    /// 不能用 `allCases`：枚举声明顺序是按代码语义排的，不是菜单顺序。
    static let menuOrder: [SmartListVisibility] = [.automatic, .visible, .hidden]

    var title: String {
        switch self {
        case .visible: "显示"
        case .hidden: "隐藏"
        case .automatic: "有内容时显示"
        }
    }

    /// 该状态在当前内容量下是否显示（`automatic` = 有未完成任务才显示）。
    func shows(hasContent: Bool) -> Bool {
        switch self {
        case .visible: return true
        case .hidden: return false
        case .automatic: return hasContent
        }
    }

    /// 收集箱是任务中转站：滴答不允许隐藏，这里也不给开关。
    static func isConfigurable(_ destination: NativeDestination) -> Bool {
        destination != .inbox
    }
}

/// 侧栏可折叠分组（滴答「清单 / 过滤器 / 标签」）。
/// 折叠状态是全局偏好，不随单个任务视图切换。
enum SidebarSectionID: String, CaseIterable, Identifiable {
    case collections, filters, tags

    var id: String { rawValue }
}

/// 视图偏好的键：清单/标签视图按名字，智能视图按 destination。
/// 改名时迁移兼容名称键，保留排序、分组及看板选择。
enum TaskViewScopeKey {
    static func key(destination: NativeDestination, activeList: String?, activeTag: String?,
                    activeFilterID: UUID? = nil) -> String {
        if let activeFilterID { return "filter:" + activeFilterID.uuidString }
        if let activeList { return "list:" + activeList }
        if let activeTag { return "tag:" + activeTag }
        return "scope:" + destination.rawValue
    }
}

/// 行内"详细"行的字段开关（滴答「清单页 → … → 显示设置」）。
/// 每一档都对应行内一个真实渲染分支，不做没有对应物的开关。
enum TaskRowDetailField: String, CaseIterable, Codable, Identifiable {
    case date
    case list
    case priority
    case tags
    case indicators

    var id: String { rawValue }

    /// 显示设置菜单顺序单独声明，枚举声明顺序不参与 UI 排序。
    static let menuOrder: [TaskRowDetailField] = [.date, .list, .priority, .tags, .indicators]

    var title: String {
        switch self {
        case .date: "日期"
        case .list: "所属清单"
        case .priority: "优先级"
        case .tags: "标签"
        case .indicators: "其他标记（子任务/重复/提醒/描述/附件）"
        }
    }
}

/// 单个视图的偏好。所有键都可缺：旧档案缺键解码为 nil，读取时回落默认。
struct TaskViewPreference: Equatable, Codable {
    var sortMode: TaskListSortMode?
    var grouping: TaskListGrouping?
    /// 排序方向：false / 缺键 = 升序（旧档案的既有行为）。
    var sortDescending: Bool?
    /// 隐藏已完成（滴答「清单页 → … → 隐藏已完成」）。nil / false = 显示。
    var hidesCompleted: Bool?
    /// 隐藏详细（整行元信息栏）。nil / false = 显示。
    var hidesDetails: Bool?
    /// 详细行里被关掉的字段。空 = 全显示。
    var hiddenFields: [TaskRowDetailField]?
    /// 视图形态。nil = 列表（滴答默认）。
    var viewMode: TaskListViewMode?
    /// 被折叠的分组 id（滴答 `taskCollapseStateChanged:` + `expandedTasksInSmartList`）。
    /// 存的是**折叠**而非展开：新增分组默认展开，旧档案缺键也就保持既有观感。
    var collapsedGroups: [String]?

    init(sortMode: TaskListSortMode? = nil, grouping: TaskListGrouping? = nil,
         sortDescending: Bool? = nil, hidesCompleted: Bool? = nil,
         hidesDetails: Bool? = nil, hiddenFields: [TaskRowDetailField]? = nil,
         viewMode: TaskListViewMode? = nil,
         collapsedGroups: [String]? = nil) {
        self.sortMode = sortMode
        self.grouping = grouping
        self.sortDescending = sortDescending
        self.hidesCompleted = hidesCompleted
        self.hidesDetails = hidesDetails
        self.hiddenFields = hiddenFields
        self.viewMode = viewMode
        self.collapsedGroups = collapsedGroups
    }

    /// 全是默认值 → 该视图不必留档案（与 resetSort 的"不留垃圾"同一口径）。
    var isDefault: Bool {
        sortMode == nil && grouping == nil && sortDescending == nil
            && hidesCompleted != true && hidesDetails != true && (hiddenFields ?? []).isEmpty
            && viewMode == nil && (collapsedGroups ?? []).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case sortMode, grouping, sortDescending, hidesCompleted, hidesDetails, hiddenFields,
             viewMode, collapsedGroups
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sortMode = try values.decodeIfPresent(TaskListSortMode.self, forKey: .sortMode)
        grouping = try values.decodeIfPresent(TaskListGrouping.self, forKey: .grouping)
        sortDescending = try values.decodeIfPresent(Bool.self, forKey: .sortDescending)
        hidesCompleted = try values.decodeIfPresent(Bool.self, forKey: .hidesCompleted)
        hidesDetails = try values.decodeIfPresent(Bool.self, forKey: .hidesDetails)
        hiddenFields = try values.decodeIfPresent([TaskRowDetailField].self, forKey: .hiddenFields)
        viewMode = try values.decodeIfPresent(TaskListViewMode.self, forKey: .viewMode)
        collapsedGroups = try values.decodeIfPresent([String].self, forKey: .collapsedGroups)
    }
}

/// 任务列表的排序/分组记忆（阶段0）。模块级 JSON 小文件
/// （modules/view-preferences.json），与任务快照分开存取：重放/恢复任务数据
/// 不会把视图偏好一起冲掉。模式对齐 TemplateStore（同款防抖原子写 + 终止 flush）。
@MainActor
final class TaskViewPreferenceStore: ObservableObject, ModuleStoreFlushable {
    struct Archive: Codable {
        var preferences: [String: TaskViewPreference] = [:]
        /// 智能清单显示状态：键 = destination.rawValue。缺省（不在字典里）= 显示。
        var smartListVisibility: [String: SmartListVisibility] = [:]
        /// 侧栏已折叠的分组 id（`SidebarSectionID.rawValue`，排序后写入）。
        var collapsedSidebarSections: [String] = []
        /// 侧栏分组的显示状态：键 = `SidebarSectionID.rawValue`。缺省 = 显示。
        var sidebarSectionVisibility: [String: SmartListVisibility] = [:]

        init(preferences: [String: TaskViewPreference] = [:],
             smartListVisibility: [String: SmartListVisibility] = [:],
             collapsedSidebarSections: [String] = [],
             sidebarSectionVisibility: [String: SmartListVisibility] = [:]) {
            self.preferences = preferences
            self.smartListVisibility = smartListVisibility
            self.collapsedSidebarSections = collapsedSidebarSections
            self.sidebarSectionVisibility = sidebarSectionVisibility
        }

        private enum CodingKeys: String, CodingKey {
            case preferences, smartListVisibility, collapsedSidebarSections, sidebarSectionVisibility
        }

        /// additive：旧 view-preferences.json 只有 `preferences` 键。
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            preferences = try values.decodeIfPresent([String: TaskViewPreference].self,
                                                     forKey: .preferences) ?? [:]
            smartListVisibility = try values.decodeIfPresent([String: SmartListVisibility].self,
                                                             forKey: .smartListVisibility) ?? [:]
            collapsedSidebarSections = try values.decodeIfPresent([String].self,
                                                                  forKey: .collapsedSidebarSections) ?? []
            sidebarSectionVisibility = try values.decodeIfPresent([String: SmartListVisibility].self,
                                                                  forKey: .sidebarSectionVisibility) ?? [:]
        }
    }

    @Published private(set) var preferences: [String: TaskViewPreference]
    @Published private(set) var smartListVisibility: [String: SmartListVisibility]
    @Published private(set) var collapsedSidebarSections: Set<String>
    @Published private(set) var sidebarSectionVisibility: [String: SmartListVisibility]

    private let persistence: JSONFileStore<Archive>
    private var organizationCancellable: AnyCancellable?

    init(directory: URL? = nil) {
        let store = JSONFileStore<Archive>(filename: "view-preferences.json",
                                           directory: directory ?? JSONFileStore<Archive>.moduleDirectory)
        persistence = store
        let archive = store.load()
        preferences = archive?.preferences ?? [:]
        smartListVisibility = archive?.smartListVisibility ?? [:]
        collapsedSidebarSections = Set(archive?.collapsedSidebarSections ?? [])
        sidebarSectionVisibility = archive?.sidebarSectionVisibility ?? [:]
        organizationCancellable = NotificationCenter.default.publisher(for: .workspaceOrganizationRenamed)
            .sink { [weak self] note in
                guard let kind = note.userInfo?["kind"] as? String,
                      let old = note.userInfo?["old"] as? String,
                      let new = note.userInfo?["new"] as? String else { return }
                self?.renameScope(kind: kind, from: old, to: new)
            }
    }

    func renameScope(kind: String, from old: String, to new: String) {
        let oldKey = kind + ":" + old
        let newKey = kind + ":" + new
        guard oldKey != newKey, let preference = preferences.removeValue(forKey: oldKey) else { return }
        preferences[newKey] = preference
        persist()
    }

    /// 未设过 = 显示（滴答默认）。
    func visibility(for destination: NativeDestination) -> SmartListVisibility {
        smartListVisibility[destination.rawValue] ?? .visible
    }

    /// 写显示状态。收集箱不可配置（滴答规则），`.visible` 是缺省值，直接删键不留垃圾。
    func setVisibility(_ visibility: SmartListVisibility, for destination: NativeDestination) {
        guard SmartListVisibility.isConfigurable(destination) else { return }
        guard self.visibility(for: destination) != visibility else { return }
        if visibility == .visible {
            smartListVisibility.removeValue(forKey: destination.rawValue)
        } else {
            smartListVisibility[destination.rawValue] = visibility
        }
        persist()
    }

    /// 侧栏分组默认展开；只记录用户主动收起的状态。
    func isSidebarSectionCollapsed(_ section: SidebarSectionID) -> Bool {
        collapsedSidebarSections.contains(section.rawValue)
    }

    func setSidebarSectionCollapsed(_ section: SidebarSectionID, _ collapsed: Bool) {
        var next = collapsedSidebarSections
        let changed = collapsed ? next.insert(section.rawValue).inserted
                               : next.remove(section.rawValue) != nil
        guard changed else { return }
        collapsedSidebarSections = next
        persist()
    }

    /// 侧栏分组本身默认显示；分组头始终保留，隐藏只收起组内的行。
    func visibility(for section: SidebarSectionID) -> SmartListVisibility {
        sidebarSectionVisibility[section.rawValue] ?? .visible
    }

    func setVisibility(_ visibility: SmartListVisibility, for section: SidebarSectionID) {
        guard self.visibility(for: section) != visibility else { return }
        if visibility == .visible {
            sidebarSectionVisibility.removeValue(forKey: section.rawValue)
        } else {
            sidebarSectionVisibility[section.rawValue] = visibility
        }
        persist()
    }

    /// 未选过 = 手动排序（滴答证实的"每个视图记忆排序"，缺省即旧行为）。
    func sortMode(for key: String) -> TaskListSortMode {
        preferences[key]?.sortMode ?? .manual
    }

    func grouping(for key: String, allTasksRoot: Bool) -> TaskListGrouping {
        preferences[key]?.grouping ?? TaskListGrouping.fallback(allTasksRoot: allTasksRoot)
    }

    /// 未选过 = 升序（旧档案与本工程历史行为）。
    func sortDescending(for key: String) -> Bool {
        preferences[key]?.sortDescending ?? false
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

    func setSortDescending(_ descending: Bool, for key: String) {
        var entry = preferences[key] ?? TaskViewPreference()
        guard entry.sortDescending != descending else { return }
        entry.sortDescending = descending
        preferences[key] = entry
        persist()
    }

    /// 未设过 = 显示已完成（滴答默认显示）。
    func hidesCompleted(for key: String) -> Bool {
        preferences[key]?.hidesCompleted ?? false
    }

    /// 未设过 = 显示详细。
    func hidesDetails(for key: String) -> Bool {
        preferences[key]?.hidesDetails ?? false
    }

    func hiddenDetailFields(for key: String) -> [TaskRowDetailField] {
        preferences[key]?.hiddenFields ?? []
    }

    /// 未设过 = 列表（滴答默认）。
    /// A preference from another scope cannot activate an unavailable mode.
    func viewMode(for key: String, availableModes: [TaskListViewMode] = TaskListViewMode.exposedCases) -> TaskListViewMode {
        let stored = storedViewMode(for: key)
        return availableModes.contains(stored) ? stored : .list
    }

    func storedViewMode(for key: String) -> TaskListViewMode {
        preferences[key]?.viewMode ?? .list
    }

    func setViewMode(_ mode: TaskListViewMode, for key: String) {
        update(key) { $0.viewMode = mode == .list ? nil : mode }
    }

    /// 折叠状态（滴答 `taskCollapseStateChanged:` 落盘的口径）。
    /// 全展开时不写键，让 `isDefault` 能把这个视图的档案整个清掉。
    func setCollapsedGroups(_ ids: Set<String>, for key: String) {
        let ordered = ids.sorted()
        update(key) { entry in
            entry.collapsedGroups = ordered.isEmpty ? nil : ordered
        }
    }

    func collapsedGroups(for key: String) -> Set<String> {
        Set(preferences[key]?.collapsedGroups ?? [])
    }

    /// 这个视图有没有"用户明确表过态"的折叠记录。
    ///
    /// 区分"从没展开过"与"用户把全部展开"——两者读出来都是空集合，
    /// 但后者不该再被"已完成组首次出现自动折叠"覆盖一次。
    func hasCollapsedGroupsRecord(for key: String) -> Bool {
        preferences[key]?.collapsedGroups != nil
    }

    func setHidesCompleted(_ hides: Bool, for key: String) {
        update(key) { $0.hidesCompleted = hides ? true : nil }
    }

    func setHidesDetails(_ hides: Bool, for key: String) {
        update(key) { $0.hidesDetails = hides ? true : nil }
    }

    func setDetailField(_ field: TaskRowDetailField, hidden: Bool, for key: String) {
        update(key) { entry in
            var fields = entry.hiddenFields ?? []
            if hidden {
                if !fields.contains(field) { fields.append(field) }
            } else {
                fields.removeAll { $0 == field }
            }
            entry.hiddenFields = fields.isEmpty ? nil : fields
        }
    }

    /// 单点写入口：改完归一（回默认就删键）+ 落盘。
    private func update(_ key: String, _ mutation: (inout TaskViewPreference) -> Void) {
        var entry = preferences[key] ?? TaskViewPreference()
        mutation(&entry)
        guard entry != preferences[key] else { return }
        if entry.isDefault { preferences.removeValue(forKey: key) } else { preferences[key] = entry }
        persist()
    }

    /// 「恢复默认排序」：清掉该视图的排序与方向，回落 `.manual`    /// 「恢复默认排序」：清掉该视图的排序与方向，回落 `.manual`
    /// （对齐滴答的"恢复默认时间顺序"）。
    func resetSort(for key: String) {
        guard var entry = preferences[key],
              entry.sortMode != nil || entry.sortDescending != nil else { return }
        entry.sortMode = nil
        entry.sortDescending = nil
        if entry.isDefault { preferences.removeValue(forKey: key) }
        else { preferences[key] = entry }
        persist()
    }

    func flush(_ completion: @escaping (Error?) -> Void) {
        persistence.flush(completion)
    }

    private func persist() {
        persistence.schedule(Archive(preferences: preferences,
                                     smartListVisibility: smartListVisibility,
                                     collapsedSidebarSections: collapsedSidebarSections.sorted(),
                                     sidebarSectionVisibility: sidebarSectionVisibility))
    }
}
