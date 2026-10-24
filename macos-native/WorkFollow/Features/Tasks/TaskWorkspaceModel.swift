import Combine
import AppKit
import Foundation

/// Presentation adapter: owns view-only selection/expansion state and routes
/// every mutation through TaskActions and every list shape through projections.
@MainActor
final class TaskWorkspaceModel: ObservableObject {
    static let inspectorLists = [
        TaskList.inbox,
        TaskList(name: "工作"),
        TaskList(name: "学习"),
        TaskList(name: "个人")
    ]

    @Published private(set) var selectedTaskID: UUID?
    // The occurrence is selection context, not a second visible selection.
    // selectedTaskID publishes the change once; updating the same preview
    // explicitly invalidates the presentation only when its value changes.
    private(set) var selectedOccurrence: TaskOccurrence?
    @Published private(set) var collapsedTaskIDs: Set<UUID> = []
    @Published private(set) var pendingChildTitleEditorID: UUID?
    @Published private(set) var revision = 0
    private struct ProjectionStamp: Equatable {
        let revision: Int
        let storeRevision: Int
        let dateRevision: Int
        let day: Date
        let filter: SavedFilter?
    }
    private struct GroupCacheEntry {
        let scope: TaskListScope
        let query: TaskListQuery
        let grouping: TaskListGrouping
        let hidesCompleted: Bool
        let viewMode: TaskListViewMode
        let groups: [TaskListGroup]
    }
    private struct NodeCacheEntry {
        let scope: TaskListScope
        let query: TaskListQuery
        let roots: [UUID]
        let expanded: Set<UUID>
        let nodes: [TaskTreeNode]
    }
    private var projectionStamp: ProjectionStamp?
    private var groupCache: [GroupCacheEntry] = []
    private var nodeCache: [NodeCacheEntry] = []
    private var sidebarCountCache: [NativeDestination: Int] = [:]
    private var subtaskProgressRevision: Int?
    private var subtaskProgressCache: [UUID: String] = [:]
    private(set) var projectionBuildCount = 0

    private func prepareProjectionCache() {
        let stamp = ProjectionStamp(revision: revision, storeRevision: store.readRevision, dateRevision: dateRevision,
                                    day: calendar.startOfDay(for: clock()), filter: activeFilter)
        guard projectionStamp != stamp else { return }
        projectionStamp = stamp
        groupCache.removeAll(keepingCapacity: true)
        nodeCache.removeAll(keepingCapacity: true)
        sidebarCountCache.removeAll(keepingCapacity: true)
    }
    /// Committed domain changes, separate from selection/filter/UI invalidation.
    let taskChanges = PassthroughSubject<TaskChangeSet, Never>()
    let listArchiveChanges = PassthroughSubject<Set<String>, Never>()
    /// Editors finish their outgoing input before selection publishes a new host.
    let selectionWillChange = PassthroughSubject<UUID?, Never>()
    /// Invalidates date-derived projections and labels without treating time
    /// passing as a task mutation or scheduling a persistence write.
    @Published private(set) var dateRevision = 0
    @Published private(set) var taskListPaneWidth = WFMetrics.listPreferred
    @Published var activeList: String?
    @Published var activeTag: String?
    @Published var activeFilterID: UUID?
    @Published var bulkSelection: Set<UUID> = []
    /// Range-selection bookkeeping, not displayed state. Publishing this would
    /// invalidate every workspace observer a second time on a plain selection.
    private(set) var bulkAnchorTaskID: UUID?

    private let store: WorkspaceStore
    private let actions: TaskActions
    /// 反馈出口（A3 HUD 反馈迁移），由 AppEnvironment 注入；为 nil 时动作照常执行、只是不弹 HUD。
    weak var feedbackSink: FeedbackCenter?
    var placementFeedback: ((Task?, Task, Int) -> Bool)?
    /// 新建（标题还没起过的）任务后要自动聚焦标题的任务 id（滴答 `focusOnTaskTitle`）。
    /// 与 `pendingChildTitleEditorID` 分开：那个是"在子任务树里开一行新行"，
    /// 这个是"整条任务刚建出来、等用户命名"。
    @Published private(set) var pendingTitleEditorID: UUID?
    @Published private(set) var recentlyCreatedTaskIDs: Set<UUID> = []
    private var creationHighlight: _Concurrency.Task<Void, Never>?

    @discardableResult
    private func reportPlacementChange(before: Task?, id: UUID?, count: Int = 1) -> Bool {
        guard let id, let after = task(for: id) else { return false }
        return placementFeedback?(before, after, count) ?? false
    }

    private func highlightCreated(_ ids: [UUID]) {
        creationHighlight?.cancel()
        recentlyCreatedTaskIDs = Set(ids)
        creationHighlight = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(for: .seconds(2))
            guard !_Concurrency.Task.isCancelled else { return }
            self?.recentlyCreatedTaskIDs = []
        }
    }
    private var filterStore: FilterStore?
    private var filterCancellable: AnyCancellable?
    private var activityCancellable: AnyCancellable?
    private var coalescesOrganizationRevision = false
    let clock: () -> Date
    let calendar: Calendar

    init(clock: @escaping () -> Date = Date.init,
         calendar: Calendar = .current,
         seedDemoData: Bool = true, initialTasks: [Task]? = nil, initialLists: [String] = [],
         initialListMeta: [TaskListMeta]? = nil,
         initialListFolders: [TaskListFolder]? = nil,
         initialListSections: [TaskListSection]? = nil,
         initialTags: [TaskTag]? = nil) {
        self.clock = clock
        self.calendar = calendar
        let store = WorkspaceStore()
        self.store = store
        self.actions = TaskActions(store: store, clock: clock, calendar: calendar)
        store.commit([], undoPolicy: .skip, tags: initialTags)
        if let initialTasks { store.commit(initialTasks); store.clearUndo() }
        else if seedDemoData { seed() }
        store.commit(store.tasks, lists: initialLists, listMetas: initialListMeta,
                     listFolders: initialListFolders,
                     listSections: initialListSections)
        if initialTags == nil {
            // The old sidebar used alphabetical tag names. Adopt that order
            // once when no independent directory has previously been saved.
            let tags = store.tags.sorted { $0.name < $1.name }.enumerated().map { index, tag in
                var value = tag; value.sortOrder = index; return value
            }
            store.commit(store.tasks, undoPolicy: .skip, tags: tags)
        }
        actions.hydrateOrganization()
        actions.hydrateSeries()
        store.clearUndo()
        // Install after hydration: consumers see committed edits, not a replay
        // of initial loading. The stream exists independently of Activity.
        store.prepareTaskCommit = { before, after in
            TaskWeeklyPlanning.recording(before: before, after: after, at: clock(), calendar: calendar)
        }
        store.onTaskChanges = { [weak self] changes in self?.taskChanges.send(changes) }
        store.onListArchiveChange = { [weak self] names in self?.listArchiveChanges.send(names) }
        store.onOrganizationRename = { [weak self] change in
            guard let self else { return }
            if change.kind == .list, self.activeList == change.oldName { self.activeList = change.newName }
            if change.kind == .tag, self.activeTag == change.oldName { self.activeTag = change.newName }
            self.filterStore?.renameReference(change)
            NotificationCenter.default.post(name: .workspaceOrganizationRenamed, object: nil,
                userInfo: ["kind": change.kind.rawValue, "old": change.oldName, "new": change.newName])
        }
    }

    var listNames: [String] {
        Array(Set(store.lists + allTasks.map { $0.list.name })).filter { $0 != TaskList.inbox.name }.sorted()
    }

    func refreshDates() {
        dateRevision += 1
    }

    func listReferenceID(for name: String) -> UUID { actions.listReferenceID(name) }
    func tagReferenceID(for name: String) -> UUID { actions.tagReferences([name])[0].id }

    var allListNames: [String] { [TaskList.inbox.name] + listNames }
    var activeListNames: [String] { listNames.filter { !isListArchived($0) } }
    /// 创建、移动和范围选择器只提供未归档清单；持久化始终使用 listNames 全集。
    var availableListNames: [String] { [TaskList.inbox.name] + activeListNames }
    var archivedListNames: [String] {
        TaskListOrdering.ordered(listNames.filter { isListArchived($0) }, metas: store.listMetas)
    }
    func isListArchived(_ name: String) -> Bool { store.archivedListNames.contains(name) }
    var tasksInActiveLists: [Task] {
        _ = revision
        let archived = store.archivedListNames
        return store.tasks.filter { !archived.contains($0.list.name) }
    }
    var taskTags: [TaskTag] { _ = revision; return store.tags }
    var orderedTags: [TaskTag] { TaskTag.ordered(taskTags) }
    var tagNames: [String] { taskTags.map(\.name).sorted() }
    var tagSidebarCounts: [String: Int] {
        let hierarchy = TaskTagHierarchy(taskTags)
        var counts: [String: Int] = [:]
        for task in tasksInActiveLists where !task.isClosed && !task.isConverted
            && task.deletedAt == nil && task.skippedAt == nil {
            for name in hierarchy.names(includingAncestorsOf: task.tags) {
                counts[name, default: 0] += 1
            }
        }
        return counts
    }
    func tag(for id: UUID) -> TaskTag? { _ = revision; return store.tag(id) }
    func tag(named name: String) -> TaskTag? {
        _ = revision
        return store.tag(named: TaskTag.normalizedName(name) ?? name)
    }

    @discardableResult
    func createTag(_ name: String, colorARGB: UInt32? = nil, parentID: UUID? = nil) -> UUID? {
        let id = actions.createTag(name, colorARGB: colorARGB, parentID: parentID)
        if id != nil { revision += 1 }
        return id
    }

    @discardableResult
    func saveTag(_ id: UUID? = nil, name: String, colorARGB: UInt32?, parentID: UUID?) -> UUID? {
        let previous = store.tags
        let wasCoalescing = coalescesOrganizationRevision
        coalescesOrganizationRevision = true
        defer { coalescesOrganizationRevision = wasCoalescing }
        let savedID = actions.saveTag(id, name: name, colorARGB: colorARGB, parentID: parentID)
        if store.tags != previous { revision += 1 }
        return savedID
    }

    @discardableResult
    func renameTag(_ id: UUID, to name: String) -> Bool {
        let changed = actions.renameTag(id, to: name)
        if changed { revision += 1 }
        return changed
    }

    @discardableResult
    func setTagColor(_ id: UUID, colorARGB: UInt32?) -> Bool {
        let changed = actions.setTagColor(id, colorARGB: colorARGB)
        if changed { revision += 1 }
        return changed
    }

    @discardableResult
    func reparentTag(_ id: UUID, parentID: UUID?) -> Bool {
        let changed = actions.reparentTag(id, parentID: parentID)
        if changed { revision += 1 }
        return changed
    }

    @discardableResult
    func reorderTag(_ id: UUID, before targetID: UUID?) -> Bool {
        let changed = actions.reorderTag(id, before: targetID)
        if changed { revision += 1 }
        return changed
    }

    @discardableResult
    func removeTag(_ id: UUID) -> Bool {
        let name = store.tag(id)?.name
        let changed = actions.removeTag(id)
        if changed {
            if activeTag == name { activeTag = nil }
            revision += 1
        }
        return changed
    }

    // MARK: 清单元数据（Round B1 加法）

    /// 侧栏清单显示顺序（对齐 Flutter orderedLists）：置顶在前，其余按 meta
    /// sortOrder、再按名字；未注册/无 meta 的清单按字典序排在后面。
    var orderedListNames: [String] {
        _ = revision
        return TaskListOrdering.ordered(activeListNames, metas: store.listMetas)
    }
    func listMeta(for name: String) -> TaskListMeta? {
        _ = revision
        return store.listMeta(for: name)
    }
    /// 全部清单 meta（持久化接线用：随快照的 taskListMeta 存取）。
    var listMetas: [TaskListMeta] {
        _ = revision
        return store.listMetas
    }
    /// 清单颜色（WFListPalette 下标，nil 清除显式色）。收集箱不可着色。
    @discardableResult
    func setListColor(_ name: String, colorIndex: Int?) -> Bool {
        let changed = actions.setListColor(name, colorIndex)
        if changed { revision += 1 }
        return changed
    }
    /// 置顶/取消置顶清单；侧栏置顶分组排在其余清单之前。
    @discardableResult
    func setListPinned(_ name: String, _ isPinned: Bool) -> Bool {
        let changed = actions.setListPinned(name, isPinned)
        if changed { revision += 1 }
        return changed
    }
    @discardableResult
    func setListArchived(_ name: String, _ archived: Bool) -> Bool {
        guard actions.setListArchived(name, archived) else { return false }
        clearBulkSelection()
        if selectedTask?.list.name == name { select(nil) }
        revision += 1
        report(FeedbackEvent(kind: .undoable,
            message: archived ? "已归档清单「\(name)」" : "已恢复清单「\(name)」",
            actionTitle: "撤销", action: undoStep()))
        return true
    }
    /// 清单图标（Emoji；nil 清除，侧栏回落到色点）。
    @discardableResult
    func setListIcon(_ name: String, _ icon: String?) -> Bool {
        let changed = actions.setListIcon(name, icon)
        if changed { revision += 1 }
        return changed
    }

    // MARK: 清单文件夹（滴答层级：文件夹 → 清单）

    /// 侧栏清单树：置顶清单 + 顶层清单 + 文件夹（成员在节点里，空文件夹也出现）。
    var listTree: [TaskListSidebarNode] {
        _ = revision
        return TaskListOrdering.sidebarTree(activeListNames, metas: store.listMetas, folders: store.listFolders)
    }

    /// 清单文件夹（含空文件夹），按自身 sortOrder。
    var listFolders: [TaskListFolder] {
        _ = revision
        return store.listFolders
    }

    /// 已知文件夹名（按侧栏出现顺序），供"移动到文件夹"菜单与重名判断。
    var listFolderNames: [String] {
        listTree.compactMap { node in
            if case .folder(let name, _) = node { return name }
            return nil
        }
    }

    func folderName(forList name: String) -> String? {
        listMeta(for: name)?.folderName
    }

    /// 新建空文件夹（滴答「清单编辑页 → 添加文件夹」路径）。
    @discardableResult
    func saveListFolder(_ name: String) -> Bool {
        let changed = actions.saveListFolder(name)
        if changed { revision += 1 }
        return changed
    }

    /// 拖拽建夹：把两个清单放进同一文件夹（文件夹不存在则建），一步撤销。
    @discardableResult
    func combineListsIntoFolder(_ first: String, _ second: String, folder: String) -> Bool {
        let changed = actions.combineListsIntoFolder(first, second, folder: folder)
        if changed { revision += 1 }
        return changed
    }

    @discardableResult
    func setListFolder(_ name: String, _ folder: String?) -> Bool {
        let changed = actions.setListFolder(name, folder)
        if changed { revision += 1 }
        return changed
    }

    @discardableResult
    func renameListFolder(from old: String, to new: String) -> Bool {
        let changed = actions.renameListFolder(from: old, to: new)
        if changed { revision += 1 }
        return changed
    }

    @discardableResult
    func dissolveListFolder(_ folder: String) -> Bool {
        let changed = actions.dissolveListFolder(folder)
        if changed { revision += 1 }
        return changed
    }

    // MARK: 清单内自定义分组（滴答第三级；官方：仅普通清单支持）

    var listSections: [TaskListSection] {
        _ = revision
        return store.listSections
    }

    /// 当前清单的分组（按 sortOrder）。
    func listSections(forList name: String) -> [TaskListSection] {
        listSections.filter { $0.listName == name }
            .sorted { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) }
    }

    /// 在分组里新建任务（滴答分组标题的 `+`）。
    @discardableResult
    func createTaskInSection(_ sectionID: String, list: String, title: String) -> Bool {
        let changed = actions.createTaskInSection(sectionID, list: list, title: title)
        if changed { revision += 1 }
        return changed
    }

    @discardableResult
    func insertListSection(_ list: String, title: String, above id: String?) -> Bool {
        let changed = actions.insertListSection(list, title: title, above: id)
        if changed { revision += 1 }
        return changed
    }

    @discardableResult
    func moveListSection(_ id: String, to list: String) -> Bool {
        let changed = actions.moveListSection(id, to: list)
        if changed { revision += 1 }
        return changed
    }

    @discardableResult
    func addListSection(_ list: String, title: String) -> Bool {
        let changed = actions.addListSection(list, title: title)
        if changed { revision += 1 }
        return changed
    }

    @discardableResult
    func renameListSection(_ id: String, title: String) -> Bool {
        let changed = actions.renameListSection(id, title: title)
        if changed { revision += 1 }
        return changed
    }

    @discardableResult
    func removeListSection(_ id: String) -> Bool {
        let changed = actions.removeListSection(id)
        if changed { revision += 1 }
        return changed
    }

    /// 任务改归属（nil = 移出分组）。
    @discardableResult
    func setTaskSection(_ id: UUID, sectionID: String?) -> TaskActionResult {
        let result = withMaterializedTask(id) { actions.setTaskSection($0, sectionID: sectionID) }
        didMutate(result)
        return result
    }

    /// 侧栏拖拽排序：把清单移到 target 之前（nil = 末尾）；
    /// `clearsFolder` = 落点在顶层空档，顺便移出文件夹。
    @discardableResult
    func moveList(_ name: String, before target: String?, clearsFolder: Bool = false) -> Bool {
        let changed = actions.moveList(name, before: target, clearsFolder: clearsFolder)
        if changed { revision += 1 }
        return changed
    }

    @discardableResult
    func saveList(_ raw: String, replacing old: String? = nil) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != TaskList.inbox.name,
              name == old || !allListNames.contains(name) else { return false }
        actions.renameList(old, to: name)
        if activeList == old { activeList = name }
        revision += 1
        return true
    }
    func removeList(_ name: String) {
        actions.removeList(name)
        if activeList == name { activeList = nil }
        revision += 1
    }
    @discardableResult
    func renameTag(_ old: String, to value: String?) -> Bool {
        guard let tag = tag(named: old) else { return false }
        if let value { return renameTag(tag.id, to: value) }
        return removeTag(tag.id)
    }

    /// Called once by AppEnvironment after both stores exist. Resolves
    /// `activeFilterID` through the store, refreshes projections when filter
    /// contents change, and clears the active filter if it is deleted anywhere.
    func attachActivityStore(_ activity: TaskActivityStore) {
        activityCancellable = taskChanges.sink { [weak activity] changes in
            activity?.recordChanges(changes)
        }
    }

    func attachFilterStore(_ store: FilterStore) {
        filterStore = store
        store.organizationResolver = { [weak self] lists, tags in
            guard let self else { return ([], []) }
            return (lists.map { self.actions.listReferenceID($0) }, self.actions.tagReferences(tags).map(\.id))
        }
        store.resolveOrganizationReferences()
        filterCancellable = store.$filters.sink { [weak self] filters in
            guard let self else { return }
            if !self.coalescesOrganizationRevision { self.revision += 1 }
            if let activeFilterID = self.activeFilterID,
               !filters.contains(where: { $0.id == activeFilterID }) {
                self.activeFilterID = nil
            }
        }
    }

    func openFilter(_ id: UUID?) {
        activeFilterID = id
    }

    /// Deletes through the attached store and, mirroring `renameTag`, clears
    /// the active selection when the deleted filter was the active one.
    @discardableResult
    func deleteFilter(_ id: UUID) -> Bool {
        guard let filterStore, filterStore.delete(id) else { return false }
        if activeFilterID == id { activeFilterID = nil }
        return true
    }

    var activeFilter: SavedFilter? {
        guard let activeFilterID else { return nil }
        return filterStore?.filter(withID: activeFilterID)
    }
    func applyBulk(_ operation: TaskBatchOperation) {
        let count = bulkSelection.count
        let tasksBeforeBatch = store.tasks
        actions.batch(bulkSelection, operation: operation)
        clearBulkSelection()
        revision += 1
        reportBulk(operation, count: count, changed: store.tasks != tasksBeforeBatch)
        if selectedTask?.deletedAt != nil { select(nil) }
    }

    /// 批量合并（滴答对齐,用户实机验证:所选任务全部变成子任务,父任务新建）。
    /// 返回新父任务 ID;少于 2 条可选时返回 nil,面板据此置灰瓦片。
    @discardableResult
    func mergeBulkTasks() -> UUID? {
        let ids = bulkSelection
        let result = actions.mergeTasks(ids)
        guard let parentID = result.taskID else { return nil }
        clearBulkSelection()
        revision += 1
        let parentTitle = store.task(parentID)?.title ?? "合并任务"
        report(FeedbackEvent(kind: .undoable, message: "已合并 \(ids.count) 个任务到「\(parentTitle)」",
                             actionTitle: "撤销", action: undoStep()))
        return parentID
    }

    /// The application prepares all note snapshots, then commits their task
    /// relations together with matching undo/redo callbacks in one history step.
    @discardableResult
    func convertBulkToNotes(environment: AppEnvironment) -> Int {
        let converted = environment.convertTasksToNotes(bulkSelection)
        if !converted.isEmpty { clearBulkSelection() }
        return converted.count
    }

    /// 批量复制文本（补齐轮）：所选任务标题逐行进剪贴板（列表手动排序的
    /// 存储序）。只读操作,不动集合不产生撤销步。

    /// 批量打开便签（滴答对齐）：每个所选任务各开一个浮窗,重复打开置前。
    func openBulkStickyNotes() {
        let ids = bulkSelection
        for id in ids { StickyNoteWindowController.shared.open(taskID: id) }
    }
    func copyBulkTitlesToPasteboard() {
        let titles = store.tasks
            .filter { bulkSelection.contains($0.id) }
            .map { $0.title.isEmpty ? "无标题" : $0.title }
        guard !titles.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(titles.joined(separator: "\n"), forType: .string)
        report(FeedbackEvent(kind: .success, message: "已复制 \(titles.count) 个任务标题"))
    }

    func setBulkSelected(_ id: UUID, _ selected: Bool) {
        if selected { bulkSelection.insert(id) } else { bulkSelection.remove(id) }
        bulkAnchorTaskID = id
    }

    /// Cmd/普通点击行进入或切换批量选中（状态机 A：S2 内点击一律切换）。
    /// `carryingSelection`：S1 上 Cmd+点击时，原选中行与点击行一并入集合；
    /// 锚点永远停在点击行，后续 Shift 范围从最后点击处延伸。集合清空时锚点
    /// 一并复位——空集合加残留锚点会让下一次 Shift 范围落空。
    func toggleBulkSelection(_ id: UUID, carryingSelection: Bool = false) {
        if carryingSelection, bulkSelection.isEmpty, let current = selectedTaskID, current != id {
            bulkSelection = [current, id]
            bulkAnchorTaskID = id
            return
        }
        if !bulkSelection.insert(id).inserted {
            bulkSelection.remove(id)
            if bulkSelection.isEmpty { bulkAnchorTaskID = nil }
        } else {
            bulkAnchorTaskID = id
        }
    }

    func setBulkSelection(in order: [UUID]) {
        bulkSelection = Set(order)
        bulkAnchorTaskID = order.first
    }

    func extendBulkSelection(to id: UUID, in order: [UUID]) {
        guard let anchor = bulkAnchorTaskID,
              let start = order.firstIndex(of: anchor),
              let end = order.firstIndex(of: id) else {
            bulkSelection.insert(id)
            return
        }
        bulkSelection.formUnion(order[min(start, end)...max(start, end)])
    }

    func clearBulkSelection() {
        if !bulkSelection.isEmpty { bulkSelection.removeAll() }
        bulkAnchorTaskID = nil
    }

    /// One session-wide width is shared by task lists and task trash, matching
    /// the Flutter workspace UI state without mixing presentation into task data.
    func setTaskListPaneWidth(_ width: CGFloat) {
        guard width.isFinite, taskListPaneWidth != width else { return }
        taskListPaneWidth = min(max(width, WFMetrics.listMinimum), WFMetrics.listMaximum)
    }

    func selectFromKeyboard(_ id: UUID) {
        clearBulkSelection()
        select(id)
    }
    /// 复制任务（Flutter 的"复制任务"）：连同子任务生成副本，HUD 带一步撤销。
    func duplicate(_ id: UUID) {
        let result = withMaterializedTask(id) { actions.duplicate($0) }
        didMutate(result)
        if result.taskID != nil {
            report(FeedbackEvent(kind: .success, message: "已复制\(quotedTitle(id))",
                                 actionTitle: "撤销", action: undoStep()))
        }
    }
    func skip(_ id: UUID) { didMutate(withMaterializedTask(id) { actions.skipOccurrence($0) }); select(nil) }
    func reorder(_ id: UUID, before target: UUID) { actions.reorder(id, before: target); revision += 1 }
    /// 子任务拖拽排序：落点是"移除自己之后的兄弟下标"（等于兄弟数即拖到末尾）。
    @discardableResult
    func reorder(_ id: UUID, toSiblingIndex index: Int) -> Bool {
        let changed = actions.reorder(id, toSiblingIndex: index)
        if changed { revision += 1 }
        return changed
    }

    /// Visible children belong to their parent's column even when their own
    /// attributes differ. Column membership therefore precedes target policy.
    func canAcceptKanbanDrop(_ id: UUID, to target: TaskKanbanCreationTarget?,
                             columnTaskIDs: [UUID]) -> Bool {
        guard let source = store.task(id), source.deletedAt == nil, source.skippedAt == nil,
              !source.isConverted, !isListArchived(source.list.name) else { return false }
        if columnTaskIDs.contains(id) { return true }
        guard let target else { return false }
        return canAcceptKanbanTask(id, to: target)
    }

    /// Attribute and sibling-position changes share one business undo step.
    /// A nil insertion leaves manual order intact for views sorted by a field.
    @discardableResult
    func applyKanbanDrop(_ id: UUID, to target: TaskKanbanCreationTarget?,
                         insertion: TaskDropPlacement?, columnTaskIDs: [UUID]) -> Bool {
        guard canAcceptKanbanDrop(id, to: target, columnTaskIDs: columnTaskIDs),
              let source = store.task(id) else { return false }
        let anchorID: UUID?
        let insertsAfter: Bool
        switch insertion {
        case .some(.before(let id)):
            anchorID = id; insertsAfter = false
        case .some(.after(let id)):
            anchorID = id; insertsAfter = true
        case nil:
            anchorID = nil; insertsAfter = false
        default:
            return false
        }
        if let anchorID {
            guard !source.isClosed, anchorID != id, columnTaskIDs.contains(anchorID),
                  let anchor = store.task(anchorID), anchor.parentID == source.parentID,
                  !anchor.isClosed else { return false }
        }

        let before = store.tasks
        var reordered = false
        var attributesChanged = false
        store.transaction {
            if let anchorID {
                let siblings = store.tasks.filter { $0.parentID == source.parentID && $0.id != id }
                if let anchorIndex = siblings.firstIndex(where: { $0.id == anchorID }) {
                    reordered = actions.reorder(id, toSiblingIndex: anchorIndex + (insertsAfter ? 1 : 0))
                }
            }
            // Shared attribute actions publish the final presentation revision;
            // position is already committed when that publication happens.
            if !columnTaskIDs.contains(id), let target {
                attributesChanged = moveKanbanTask(id, to: target)
            }
        }
        let changed = before != store.tasks
        if changed && reordered && !attributesChanged { didMutate(.success(id)) }
        return changed
    }

    /// 已过期组头"顺延"（对齐 Flutter _postponeOverdue）：逐任务保留各自时钟，
    /// 整组动作是单条事务，一次撤销整组生效；HUD 报告顺延数量。
    func postponeOverdue(_ ids: Set<UUID>) {
        let before = store.tasks
        actions.postponeOverdue(ids, to: clock())
        let moved = store.tasks.filter { task in
            guard let previous = before.first(where: { $0.id == task.id }) else { return false }
            return previous.schedule.dueAt != task.schedule.dueAt
        }.count
        revision += 1
        guard moved > 0 else {
            report(FeedbackEvent(kind: .info, message: "没有可顺延的任务"))
            return
        }
        report(FeedbackEvent(kind: .undoable, message: "已顺延 \(moved) 项到今天",
                             actionTitle: "撤销", action: undoStep()))
    }

    @discardableResult
    func createDraft(title: String, list: String, schedule: TaskSchedule, priority: TaskPriority,
                     tags: [String], reminder: Date?, reminderOffsets: [Int]? = nil,
                     repeatFrequency: TaskRepeat,
                     recurrenceRule: RecurrenceRule? = nil,
                     document: NativeDocument = .empty, selectCreatedTask: Bool = true,
                     focusTitle: Bool = false) -> TaskActionResult {
        let result = actions.createDraft(title: title, list: list, schedule: schedule, priority: priority,
                                         tags: tags, reminder: reminder, reminderOffsets: reminderOffsets,
                                         frequency: repeatFrequency,
                                         recurrenceRule: recurrenceRule, document: document)
        didMutate(result)
        if selectCreatedTask, let id = result.taskID { select(id) }
        // 标题还没被用户起过的创建（命令面板空查询落「无标题」）直接把焦点给标题
        // （滴答 `focusOnTaskTitle`）。快速添加不传这个标记——它的标题来自用户输入，
        // 抢焦点只会打断连续录入。
        if focusTitle, let id = result.taskID { pendingTitleEditorID = id }
        return result
    }

    @discardableResult
    func createWeeklyTask(title: String, list: String, weekOf: Date) -> UUID? {
        let result = actions.createWeeklyTask(title: title, list: list, weekOf: weekOf)
        didMutate(result)
        return result.taskID
    }

    /// Selective carry-over keeps identities and reminder bindings, and the
    /// whole selection is one ordinary workspace undo step.
    @discardableResult
    func planTasks(_ ids: Set<UUID>, weekOf: Date) -> Int {
        let count = actions.planTasks(ids, weekOf: weekOf)
        guard count > 0 else { return 0 }
        revision += 1
        report(FeedbackEvent(kind: .undoable, message: "已安排 \(count) 项到\(SummaryReviewBuilder.weekTitle(for: SummaryReviewBuilder.weekStart(of: weekOf, calendar: calendar), calendar: calendar))",
                             actionTitle: "撤销", action: undoStep()))
        return count
    }

    @discardableResult
    func submitWeeklyCapture(_ session: QuickCaptureSession, weekOf: Date, list: String?) -> [UUID] {
        let drafts = session.drafts(now: clock(), calendar: calendar, knownLists: Set(availableListNames),
            contextList: list, contextTag: nil, defaultDueAt: nil)
        let ids = actions.createWeeklyCaptures(drafts, weekOf: weekOf)
        if !ids.isEmpty { revision += 1; highlightCreated(ids) }
        return ids
    }

    @discardableResult
    func arrangeWeeklyTasks(_ ids: Set<UUID>, on day: Date?, weekOf: Date) -> Int {
        let count = actions.arrangeWeeklyTasks(ids, on: day, weekOf: weekOf)
        if count > 0 {
            revision += 1
            report(FeedbackEvent(kind: .undoable, message: day.map {
                "已安排 \(count) 项到" + ScheduleDisplay.dateText($0, hasTime: false, now: clock(), calendar: calendar, style: .compact)
            } ?? "已将 \(count) 项移至待安排日期", actionTitle: "撤销", action: undoStep()))
        }
        return count
    }

    func captureWeekPlan(weekOf: Date) {
        if actions.captureWeekPlan(weekOf: weekOf) { revision += 1 }
    }

    /// 创建通道的 plan 版：新建对话框等宿主直接把面板产出的计划交过来。
    @discardableResult
    func createDraft(title: String, list: String, plan: SchedulePlan, priority: TaskPriority,
                     tags: [String], document: NativeDocument = .empty) -> TaskActionResult {
        let result = actions.createDraft(title: title, list: list, plan: plan, priority: priority,
                                         tags: tags, document: document)
        didMutate(result)
        if let id = result.taskID { select(id) }
        return result
    }

    @discardableResult
    func submitCapture(_ session: QuickCaptureSession, defaultDueAt: Date? = nil, selectCreatedTask: Bool = true) -> [UUID] {
        let drafts = session.drafts(now: clock(), calendar: calendar, knownLists: Set(availableListNames),
            contextList: activeList.flatMap { isListArchived($0) ? nil : $0 },
            contextTag: activeTag, defaultDueAt: defaultDueAt)
        let ids = actions.createCaptures(drafts)
        if let last = ids.last {
            didMutate(.success(last))
            if selectCreatedTask { select(last) }
            highlightCreated(ids)
            reportPlacementChange(before: nil, id: last, count: ids.count)
        }
        return ids
    }

    /// 看板列内创建与列属性写入是一个事务，撤销不会留下未归列的中间任务。
    @discardableResult
    func createKanbanTask(title: String, target: TaskKanbanCreationTarget,
                          in scope: TaskListScope = .allTasks) -> UUID? {
        guard !scope.isClosedScope else { return nil }
        if case let .section(list, sectionID?) = target {
            guard store.listSection(sectionID)?.listName == list else { return nil }
        }
        let today = calendar.startOfDay(for: clock())
        let defaultDueAt: Date?
        switch scope {
        case .today, .nextSevenDays: defaultDueAt = today
        case .tomorrow: defaultDueAt = calendar.date(byAdding: .day, value: 1, to: today)
        default: defaultDueAt = nil
        }
        let parsedInputs = QuickAddComposition.batchLines(in: title).map {
            QuickCaptureSession(text: $0).parse(now: clock(), calendar: calendar, knownLists: Set(availableListNames))
        }.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var drafts = QuickCaptureSession(text: title).drafts(
            now: clock(), calendar: calendar, knownLists: Set(availableListNames),
            contextList: activeList, contextTag: activeTag, defaultDueAt: defaultDueAt)
        for index in drafts.indices {
            switch target {
            case .currentContext: break
            case .schedule(let day):
                // The column supplies a default; explicit capture fields keep
                // the same precedence as the list and global quick-add.
                if parsedInputs[index].tokens.contains(where: { $0.kind == .date }) { continue }
                if let day {
                    let old = drafts[index].plan.schedule.dueAt
                    let moved = old.map {
                        TaskDateDraft.movingDay($0, to: day, calendar: calendar)
                    } ?? calendar.startOfDay(for: day)
                    let start = drafts[index].plan.schedule.hasTime ? moved : calendar.startOfDay(for: moved)
                    if let old {
                        let delta = calendar.dateComponents([.day],
                            from: calendar.startOfDay(for: old), to: calendar.startOfDay(for: day)).day ?? 0
                        drafts[index].plan.schedule.dueEndAt = ScheduleSemantics.shifted(
                            drafts[index].plan.schedule.dueEndAt, byDays: delta, calendar: calendar)
                        drafts[index].plan.reminder = ScheduleSemantics.shifted(
                            drafts[index].plan.reminder, byDays: delta, calendar: calendar)
                    }
                    drafts[index].plan.schedule.dueAt = start
                } else {
                    drafts[index].plan.schedule = TaskSchedule()
                    drafts[index].plan.reminder = nil
                    drafts[index].plan.reminderOffsets = []
                }
            case .priority(let priority):
                if !parsedInputs[index].tokens.contains(where: { $0.kind == .priority }) {
                    drafts[index].priority = priority
                }
            case .list(let list):
                if parsedInputs[index].listName == nil { drafts[index].list = list }
            case .tag(let tag):
                if let tag { drafts[index].tags = [tag] + drafts[index].tags.filter { $0 != tag } }
                else { drafts[index].tags = [] }
            case .section(let list, _): drafts[index].list = list
            }
        }
        guard !drafts.isEmpty else { return nil }
        var ids: [UUID] = []
        store.transaction {
            ids = actions.createCaptures(drafts)
            if case let .section(_, sectionID) = target {
                for id in ids { _ = actions.setTaskSection(id, sectionID: sectionID) }
            }
        }
        if let last = ids.last {
            didMutate(.success(last)); select(last)
            highlightCreated(ids)
            reportPlacementChange(before: nil, id: last, count: ids.count)
        }
        return ids.last
    }

    @discardableResult
    func createFromTemplate(_ template: TaskTemplate) -> UUID? {
        let listName = template.listName.flatMap { availableListNames.contains($0) ? $0 : nil }
            ?? TaskList.inbox.name
        let result = actions.createFromTemplate(template, list: TaskList(name: listName))
        didMutate(result)
        if let id = result.taskID { select(id) }
        return result.taskID
    }

    var selectedTask: Task? {
        guard let selectedTaskID else { return nil }
        return store.task(selectedTaskID) ?? (selectedOccurrence?.task.id == selectedTaskID ? selectedOccurrence?.task : nil)
    }

    var allTasks: [Task] { _ = revision; return store.tasks }

    /// Parent badges depend on child changes, but not on selection or pane width.
    func subtaskProgress(for parentID: UUID) -> String? {
        if subtaskProgressRevision != revision {
            var counts: [UUID: (completed: Int, total: Int)] = [:]
            for task in store.tasks where task.deletedAt == nil && task.skippedAt == nil &&
                !task.isAbandoned && !task.isConverted {
                guard let parent = task.parentID else { continue }
                var count = counts[parent] ?? (0, 0)
                count.total += 1
                if task.status == .completed { count.completed += 1 }
                counts[parent] = count
            }
            subtaskProgressCache = counts.mapValues { "\($0.completed)/\($0.total)" }
            subtaskProgressRevision = revision
        }
        return subtaskProgressCache[parentID]
    }
    var canUndo: Bool { _ = revision; return store.canUndo }
    func undo() { actions.undo(); revision += 1; if selectedTask == nil { select(nil) } }
    var canRedo: Bool { _ = revision; return store.canRedo }
    func redo() { actions.redo(); revision += 1; if selectedTask == nil { select(nil) } }

    @discardableResult
    func updateAttributes(_ id: UUID, priority: TaskPriority? = nil,
                          schedule: TaskSchedule? = nil, list: TaskList? = nil,
                          tags: [String]? = nil) -> TaskActionResult {
        let before = self.task(for: id)
        let result = withMaterializedTask(id) { actions.updateAttributes($0, priority: priority, schedule: schedule, list: list, tags: tags) }
        didMutate(result)
        reportPlacementChange(before: before, id: result.taskID)
        return result
    }

    @discardableResult
    func setFocusEstimate(_ id: UUID, _ estimate: TaskFocusEstimate?) -> TaskActionResult {
        let result = withMaterializedTask(id) { actions.setFocusEstimate($0, estimate) }
        didMutate(result)
        return result
    }

    func occurrence(for task: Task) -> TaskOccurrence {
        let series = task.series ?? (task.recurrence == .never ? nil : TaskSeries(task: task, calendar: calendar, now: clock()))
        var value = task
        value.series = series
        let key = task.occurrenceKey ?? series?.initialKey
            ?? OccurrenceKey(seriesID: task.id, nominalDate: task.schedule.dueAt ?? task.createdAt, ordinal: 0)
        let virtual = store.task(task.id) == nil && selectedOccurrence?.key == key
        return TaskOccurrence(key: key, task: value, isVirtual: virtual,
            sourceTaskID: virtual ? (selectedOccurrence?.sourceTaskID ?? task.id) : task.id)
    }

    @discardableResult
    func materializeOccurrence(_ occurrence: TaskOccurrence) -> TaskActionResult {
        let result = actions.materializeOccurrence(occurrence)
        didMutate(result)
        return result
    }

    @discardableResult
    func completeOccurrence(_ occurrence: TaskOccurrence) -> TaskActionResult {
        let result = actions.completeOccurrence(occurrence)
        didMutate(result)
        if let id = result.taskID { select(id) }
        return result
    }

    @discardableResult
    func saveOccurrenceSchedule(_ plan: SchedulePlan, occurrence: TaskOccurrence,
                                scope: RecurrenceEditScope = .onlyThis) -> TaskActionResult {
        let result = actions.saveOccurrenceSchedule(plan, occurrence: occurrence, scope: scope)
        didMutate(result)
        if let id = result.taskID { select(id) }
        return result
    }

    /// Calendar movement keeps the complete interval and its absolute reminder.
    @discardableResult
    func moveSchedule(_ id: UUID, to start: Date, hasTime: Bool? = nil) -> TaskActionResult {
        guard let task = task(for: id) else { return .failure(.missingTask) }
        var next = task.schedule
        let exact = hasTime ?? next.hasTime
        let normalizedStart = exact ? start : calendar.startOfDay(for: start)
        if let oldStart = next.dueAt, let end = next.dueEndAt {
            next.dueEndAt = end.addingTimeInterval(normalizedStart.timeIntervalSince(oldStart))
        }
        next.dueAt = normalizedStart
        next.hasTime = exact
        return updateAttributes(id, schedule: next)
    }

    @discardableResult
    func resizeSchedule(_ id: UUID, start: Date? = nil, end: Date? = nil) -> TaskActionResult {
        guard let task = task(for: id) else { return .failure(.missingTask) }
        var next = task.schedule
        if let start { next.dueAt = next.hasTime ? start : calendar.startOfDay(for: start) }
        if let end { next.dueEndAt = next.hasTime ? end : calendar.startOfDay(for: end) }
        if let first = next.dueAt, let last = next.dueEndAt, last < first {
            return .failure(.invalidSchedule)
        }
        return updateAttributes(id, schedule: next)
    }
    func setRepeat(_ id: UUID, _ value: TaskRepeat) { didMutate(withMaterializedTask(id) { actions.setRepeat($0, value) }) }
    func setRecurrence(_ id: UUID, frequency: TaskRepeat, rule: RecurrenceRule?) {
        didMutate(withMaterializedTask(id) { actions.setRecurrence($0, frequency: frequency, rule: rule) })
    }
    func saveTiming(_ id: UUID, schedule: TaskSchedule, reminder: Date?, frequency: TaskRepeat,
                    recurrenceRule: RecurrenceRule? = nil, reminderOffsets: [Int]? = nil) {
        let before = self.task(for: id)
        let result = withMaterializedTask(id) { actions.saveTiming($0, schedule: schedule, reminder: reminder,
                                        frequency: frequency, recurrenceRule: recurrenceRule,
                                        reminderOffsets: reminderOffsets) }
        didMutate(result)
        reportPlacementChange(before: before, id: result.taskID)
    }
    /// 日程写入的唯一入口：宿主产出 `SchedulePlan`，不再逐字段拆参数。
    @discardableResult
    func saveSchedule(_ plan: SchedulePlan, to target: ScheduleTarget) -> TaskActionResult {
        let before: Task?
        if case .task(let id) = target { before = task(for: id) } else { before = nil }
        let result: TaskActionResult
        if case .task(let id) = target, let selectedOccurrence, selectedOccurrence.task.id == id, store.task(id) == nil {
            result = actions.saveOccurrenceSchedule(plan, occurrence: selectedOccurrence, scope: .onlyThis)
        } else { result = actions.saveSchedule(plan, to: target) }
        didMutate(result)
        if before != nil { reportPlacementChange(before: before, id: result.taskID) }
        return result
    }
    var deletedTasks: [Task] {
        allTasks.filter { $0.deletedAt != nil }.sorted {
            if $0.deletedAt == $1.deletedAt { return $0.createdAt > $1.createdAt }
            return $0.deletedAt! > $1.deletedAt!
        }
    }
    func restoreDeleted(_ id: UUID) {
        let result = actions.restoreDeleted(id)
        didMutate(result)
        if result.taskID != nil { select(nil) }
    }
    func permanentlyDelete(_ id: UUID) {
        didMutate(actions.permanentlyDelete(id))
        if selectedTaskID != nil && selectedTask == nil { select(nil) }
    }
    func emptyTrash() { actions.emptyTrash(); select(nil); revision += 1 }

    func task(for id: UUID) -> Task? {
        _ = revision
        return store.task(id) ?? (selectedOccurrence?.task.id == id ? selectedOccurrence?.task : nil)
    }

    static func scope(for destination: NativeDestination) -> TaskListScope? {
        switch destination {
        case .today: return .today
        case .tomorrow: return .tomorrow
        case .inbox: return .inbox
        case .allTasks: return .allTasks
        case .nextSevenDays: return .nextSevenDays
        case .completed: return .completed
        case .abandoned: return .abandoned
        default: return nil
        }
    }

    func groups(for scope: TaskListScope, query: TaskListQuery = TaskListQuery(),
                grouping: TaskListGrouping = .byDate,
                hidesCompleted: Bool = false,
                viewMode: TaskListViewMode = .list) -> [TaskListGroup] {
        _ = revision
        prepareProjectionCache()
        if let cached = groupCache.first(where: {
            $0.scope == scope && $0.query == query && $0.grouping == grouping
                && $0.hidesCompleted == hidesCompleted && $0.viewMode == viewMode
        }) { return cached.groups }
        projectionBuildCount += 1
        let result = applyingFilter(
            TaskListProjection.groups(in: scope, store: store, now: clock(), calendar: calendar,
                                      query: query, grouping: grouping,
                                      hidesCompleted: hidesCompleted, viewMode: viewMode))
        if groupCache.count >= 8 { groupCache.removeFirst() }
        groupCache.append(GroupCacheEntry(scope: scope, query: query, grouping: grouping,
                                         hidesCompleted: hidesCompleted, viewMode: viewMode, groups: result))
        return result
    }

    /// 卡片内的子任务跟随父卡片，折叠使用同一任务身份；显示偏好也覆盖已关闭子任务。
    func kanbanNodes(for task: Task, hidesCompleted: Bool = false) -> [TaskTreeNode] {
        _ = revision
        let root = self.task(for: task.id) ?? task
        let visibleChildren = Set(store.children(of: task.id).filter {
            !$0.isConverted && (!hidesCompleted || !$0.isClosed)
        }.map(\.id))
        let expanded: Set<UUID> = collapsedTaskIDs.contains(task.id) ? [] : [task.id]
        return TaskTreeProjection.nodes(roots: [root], store: store, expanded: expanded,
                                        matchingTaskIDs: visibleChildren)
    }

    /// Count for the visible list; when a saved filter is active the header
    /// count shrinks with the filtered content (like `activeList`/`activeTag`).
    func count(for scope: TaskListScope) -> Int {
        _ = revision
        return filteredMatches(in: scope, query: TaskListQuery())
            .filter { scope.isClosedScope || !$0.isClosed }.count
    }

    /// Sidebar badge count: intentionally ignores the saved filter (and the
    /// list/tag query) so destination badges stay stable while filtering.
    func count(for destination: NativeDestination) -> Int {
        if destination == .weekPlan {
            let projection = WeeklyPlanProjection(weekStart: SummaryReviewBuilder.weekStart(of: clock(), calendar: calendar), calendar: calendar)
            return projection.tasks(from: tasksInActiveLists).filter { !$0.isClosed }.count
        }
        if destination == .trash { return deletedTasks.count }
        guard let scope = Self.scope(for: destination) else { return 0 }
        prepareProjectionCache()
        if let cached = sidebarCountCache[destination] { return cached }
        projectionBuildCount += 1
        let result = TaskListProjection.count(in: scope, store: store, now: clock(), calendar: calendar)
        sidebarCountCache[destination] = result
        return result
    }

    func nodes(for group: TaskListGroup, scope: TaskListScope, query: TaskListQuery = TaskListQuery(),
               orderedRoots: [Task]? = nil) -> [TaskTreeNode] {
        _ = revision
        prepareProjectionCache()
        let rootTasks = orderedRoots ?? group.tasks
        let roots = Set(group.tasks.map(\.id))
        let expanded = query.isFiltering ? roots : roots.subtracting(collapsedTaskIDs)
        let rootIDs = rootTasks.map(\.id)
        if let cached = nodeCache.first(where: {
            $0.scope == scope && $0.query == query && $0.roots == rootIDs && $0.expanded == expanded
        }) { return cached.nodes }
        let followsMatchedParent = (scope == .today || scope == .tomorrow
                                    || scope == .nextSevenDays) &&
            query.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let matching = followsMatchedParent ? nil : Set(filteredMatches(in: scope, query: query).map(\.id))
        projectionBuildCount += 1
        let result = TaskTreeProjection.nodes(roots: rootTasks, store: store,
                                             expanded: expanded, matchingTaskIDs: matching)
        if nodeCache.count >= 16 { nodeCache.removeFirst() }
        nodeCache.append(NodeCacheEntry(scope: scope, query: query, roots: rootIDs,
                                       expanded: expanded, nodes: result))
        return result
    }

    func visibleNodes(for scope: TaskListScope, query: TaskListQuery = TaskListQuery()) -> [TaskTreeNode] {
        groups(for: scope, query: query).flatMap { nodes(for: $0, scope: scope, query: query) }
    }

    // MARK: Saved filter application

    private func filterMatches(_ task: Task) -> Bool {
        guard let filter = activeFilter else { return true }
        return FilterEvaluator.matches(task, filter: filter, now: clock(), calendar: calendar)
    }

    /// Post-filters projection output with the active saved filter, dropping
    /// groups that end up empty so the view falls back to its empty state. A
    /// root that fails the filter stays when one of its children passes, so
    /// the matched child remains reachable — mirroring how the list/tag query
    /// promotes matching children into rows.
    private func applyingFilter(_ groups: [TaskListGroup]) -> [TaskListGroup] {
        guard let filter = activeFilter else { return groups }
        return groups.compactMap { group in
            let tasks = group.tasks.filter { task in
                filterMatches(task) || hasMatchingChild(of: task, filter: filter)
            }
            guard !tasks.isEmpty else { return nil }
            guard tasks.count != group.tasks.count else { return group }
            return TaskListGroup(kind: group.kind, day: group.day, tasks: tasks, label: group.label,
                                 sectionID: group.sectionID, creationTarget: group.creationTarget)
        }
    }

    private func hasMatchingChild(of task: Task, filter: SavedFilter) -> Bool {
        store.children(of: task.id).contains {
            FilterEvaluator.matches($0, filter: filter, now: clock(), calendar: calendar)
        }
    }

    private func filteredMatches(in scope: TaskListScope, query: TaskListQuery) -> [Task] {
        TaskListProjection.matches(in: scope, store: store, now: clock(), calendar: calendar, query: query)
            .filter { filterMatches($0) }
    }

    func selectOccurrence(_ occurrence: TaskOccurrence) {
        if !occurrence.isVirtual { select(occurrence.task.id); return }
        if selectedTaskID != occurrence.task.id {
            selectionWillChange.send(occurrence.task.id)
            selectedOccurrence = occurrence
            selectedTaskID = occurrence.task.id
        } else if selectedOccurrence != occurrence {
            objectWillChange.send()
            selectedOccurrence = occurrence
        }
        bulkAnchorTaskID = occurrence.task.id
    }

    /// Browsing a projected period is read-only. Starting focus and other
    /// actions that need a durable relation resolve it at this boundary.
    func resolveTaskForAction(_ id: UUID) -> UUID? {
        if store.task(id) != nil { return id }
        guard let occurrence = selectedOccurrence, occurrence.task.id == id else { return nil }
        let result = actions.materializeOccurrence(occurrence)
        didMutate(result)
        return result.taskID
    }

    private func withMaterializedTask(_ id: UUID, _ mutation: (UUID) -> TaskActionResult) -> TaskActionResult {
        guard store.task(id) == nil, let occurrence = selectedOccurrence,
              occurrence.task.id == id else { return mutation(id) }
        var result: TaskActionResult = .failure(.missingTask)
        store.transaction {
            result = actions.materializeOccurrence(occurrence)
            if let realID = result.taskID { result = mutation(realID) }
        }
        return result
    }

    func select(_ id: UUID?) {
        if selectedTaskID != id {
            // Finish the outgoing editor while its occurrence context exists.
            selectionWillChange.send(id)
            if id != selectedOccurrence?.task.id { selectedOccurrence = nil }
            selectedTaskID = id
        }
        bulkAnchorTaskID = id
    }

    func toggleExpanded(_ id: UUID) {
        if !collapsedTaskIDs.insert(id).inserted {
            collapsedTaskIDs.remove(id)
        }
    }

    func selectAdjacent(_ offset: Int, in scope: TaskListScope) {
        let nodes = visibleNodes(for: scope)
        guard !nodes.isEmpty else { return }
        let current = nodes.firstIndex { $0.task.id == selectedTaskID }
        let index = current.map { min(max($0 + offset, 0), nodes.count - 1) }
            ?? (offset < 0 ? nodes.count - 1 : 0)
        selectFromKeyboard(nodes[index].task.id)
    }

    @discardableResult
    func createTask(title: String, in scope: TaskListScope) -> TaskActionResult {
        let today = calendar.startOfDay(for: clock())
        let schedule: TaskSchedule
        switch scope {
        case .today:
            schedule = TaskSchedule(dueAt: today)
        case .tomorrow:
            schedule = TaskSchedule(dueAt: calendar.date(byAdding: .day, value: 1, to: today))
        default:
            schedule = TaskSchedule()
        }
        let result = actions.create(title: title, list: .inbox, schedule: schedule)
        didMutate(result, scope: scope)
        if result.taskID != nil {
            report(FeedbackEvent(kind: .info, message: "已添加到「\(TaskList.inbox.name)」"))
        }
        return result
    }

    @discardableResult
    func createChild(_ parentID: UUID, title: String = "") -> TaskActionResult {
        let result = actions.createChild(parentID, title: title)
        didMutate(result)
        return result
    }

    @discardableResult
    func requestChildTitleEditor(for parentID: UUID) -> UUID? {
        let result = actions.createChild(parentID)
        didMutate(result)
        guard let childID = result.taskID else { return nil }
        select(parentID)
        pendingChildTitleEditorID = childID
        return childID
    }

    @discardableResult
    func assignParent(_ id: UUID, parentID: UUID) -> TaskActionResult {
        let result = actions.setParent(id, parentID: parentID)
        didMutate(result)
        if result.taskID != nil {
            collapsedTaskIDs.remove(parentID)
        }
        return result
    }

    /// A parent picked for a batch must accept every selected task. Revalidate
    /// before applying so a stale picker cannot silently edit only part of it.
    @discardableResult
    func assignBulkParent(_ ids: Set<UUID>, parentID: UUID) -> TaskActionResult {
        guard !ids.isEmpty, ids == bulkSelection,
              let parent = store.task(parentID) else { return .failure(.missingTask) }
        guard !ids.contains(parentID) else { return .failure(.cannotParentToSelf) }
        let sources = store.tasks.filter { ids.contains($0.id) }
        guard sources.count == ids.count else { return .failure(.missingTask) }
        for source in sources {
            if let rejection = TaskParentPolicy.rejection(task: source, parent: parent, tasks: store.tasks) {
                return .failure(rejection)
            }
        }
        applyBulk(.linkParent(parentID))
        collapsedTaskIDs.remove(parentID)
        return .success(parentID)
    }

    @discardableResult
    func moveTask(_ id: UUID, to placement: TaskDropPlacement) -> TaskActionResult {
        let result = actions.move(id, to: placement)
        didMutate(result)
        if result.taskID != nil, let parentID = task(for: id)?.parentID {
            collapsedTaskIDs.remove(parentID)
        }
        return result
    }

    func consumePendingChildTitleEditor() -> UUID? {
        defer { pendingChildTitleEditorID = nil }
        return pendingChildTitleEditorID
    }

    func consumePendingTitleEditor() -> UUID? {
        defer { pendingTitleEditorID = nil }
        return pendingTitleEditorID
    }

    @discardableResult
    func complete(_ id: UUID, in scope: TaskListScope? = nil) -> TaskActionResult {
        let result = withMaterializedTask(id) { actions.complete($0) }
        didMutate(result, scope: scope)
        if result.taskID != nil {
            report(FeedbackEvent(kind: .completion, message: "已完成\(quotedTitle(id))",
                                 actionTitle: "撤销", action: undoStep(), sound: .completion,
                                 coalesceKey: "task-completed",
                                 coalescedMessage: { "已完成 \($0) 个任务" }))
        }
        return result
    }

    @discardableResult
    func restore(_ id: UUID, in scope: TaskListScope? = nil) -> TaskActionResult {
        let result = withMaterializedTask(id) { actions.restore($0) }
        didMutate(result, scope: scope)
        if result.taskID != nil {
            report(FeedbackEvent(kind: .completion, message: "已恢复\(quotedTitle(id))",
                                 actionTitle: "撤销", action: undoStep()))
        }
        return result
    }

    @discardableResult
    func changeStatus(_ task: Task, in scope: TaskListScope? = nil) -> TaskActionResult {
        task.isClosed ? restore(task.id, in: scope) : complete(task.id, in: scope)
    }

    @discardableResult
    func abandon(_ id: UUID, in scope: TaskListScope? = nil) -> TaskActionResult {
        let result = withMaterializedTask(id) { actions.abandon($0) }
        didMutate(result, scope: scope)
        if result.taskID != nil {
            report(FeedbackEvent(kind: .undoable, message: "已放弃\(quotedTitle(id))",
                                 actionTitle: "撤销", action: undoStep()))
        }
        return result
    }

    @discardableResult
    func moveToList(_ id: UUID, _ list: TaskList) -> TaskActionResult {
        let before = self.task(for: id)
        let listBefore = before?.list.name
        let result = withMaterializedTask(id) { actions.moveToList($0, list) }
        didMutate(result)
        if reportPlacementChange(before: before, id: result.taskID) { return result }
        if result.taskID != nil, listBefore != list.name {
            report(FeedbackEvent(kind: .undoable,
                                 message: "已移动到「\(task(for: id)?.list.name ?? list.name)」",
                                 actionTitle: "撤销", action: undoStep()))
        }
        return result
    }

    func canMoveToList(_ id: UUID) -> Bool {
        guard let task = task(for: id) else { return false }
        return task.parentID == nil && task.deletedAt == nil
    }

    /// 换清单并**同时**指定分组——「移动到清单 → 某个清单 → 某个分组」走这条。
    ///
    /// 必须是**一次**提交：分成 `moveToList` + `setTaskSection` 两次提交的话，
    /// 撤销栈上就是两步，用户按一次 ⌘Z 只退回一半。
    /// 反馈文案把分组带上，否则跟单纯换清单的提示长得一样，看不出区别。
    @discardableResult
    func moveToList(_ id: UUID, _ list: TaskList, sectionID: String?) -> TaskActionResult {
        let before = self.task(for: id)
        let listBefore = before?.list.name
        let result = withMaterializedTask(id) { actions.moveToList($0, list, sectionID: sectionID) }
        didMutate(result)
        if reportPlacementChange(before: before, id: result.taskID) { return result }
        if result.taskID != nil {
            let destination = task(for: id)?.list.name ?? list.name
            let sectionTitle = sectionID.flatMap { sid in
                listSections(forList: destination).first { $0.id == sid }?.title
            }
            if listBefore != list.name || sectionTitle != nil {
                let place = sectionTitle.map { "\(destination) / \($0)" } ?? destination
                report(FeedbackEvent(kind: .undoable,
                                     message: "已移动到「\(place)」",
                                     actionTitle: "撤销", action: undoStep()))
            }
        }
        return result
    }

    @discardableResult
    func delete(_ id: UUID) -> TaskActionResult {
        // Finish input before the task becomes non-editable; undo must restore
        // the committed text, not the snapshot before its IME composition.
        if selectedTaskID == id, task(for: id)?.deletedAt == nil {
            selectionWillChange.send(nil)
        }
        let result = withMaterializedTask(id) { actions.delete($0) }
        guard result.taskID != nil else { return result }
        if selectedTaskID == id { select(nil) }
        StickyNoteWindowController.shared.close(taskID: id)
        didMutate(result)
        report(FeedbackEvent(kind: .undoable, message: "已删除\(quotedTitle(id))",
                             actionTitle: "撤销", action: undoStep()))
        return result
    }

    @discardableResult
    func setSchedule(_ id: UUID, _ schedule: TaskSchedule) -> TaskActionResult {
        let before = self.task(for: id)
        let result = withMaterializedTask(id) { actions.setSchedule($0, schedule) }
        didMutate(result)
        reportPlacementChange(before: before, id: result.taskID)
        return result
    }

    @discardableResult
    func setTitle(_ id: UUID, _ title: String) -> TaskActionResult {
        let result = withMaterializedTask(id) { actions.setTitle($0, title) }
        didMutate(result)
        return result
    }

    @discardableResult
    func applyRemindersEdit(_ occurrence: TaskOccurrence, fields: ReminderTaskFields) -> TaskActionResult {
        let result = actions.applyRemindersEdit(occurrence, fields: fields)
        didMutate(result)
        return result
    }

    @discardableResult
    func setDocument(_ id: UUID, _ document: NativeDocument) -> TaskActionResult {
        let result = withMaterializedTask(id) { actions.setDocument($0, document) }
        didMutate(result)
        return result
    }

    /// 任务形态切换（TI2-05b），内容映射见 `TaskActions.document(_:convertingTo:)`。
    @discardableResult
    func setKind(_ id: UUID, _ kind: TaskKind) -> TaskActionResult {
        let result = withMaterializedTask(id) { actions.setKind($0, kind) }
        didMutate(result)
        return result
    }

    /// 合并子任务到正文（底栏 mergeButton）：子任务标题并入正文后软删子任务。
    @discardableResult
    func mergeChildrenIntoDocument(_ id: UUID) -> TaskActionResult {
        let result = withMaterializedTask(id) { actions.mergeChildrenIntoDocument($0) }
        didMutate(result)
        return result
    }

    func setSourceNote(_ id: UUID, _ noteID: UUID) { didMutate(withMaterializedTask(id) { actions.setSourceNote($0, noteID) }) }

    /// The editor owns reference undo; persist its document/source pair without
    /// adding a competing business undo record.
    @discardableResult
    func commitEditorReference(_ id: UUID, document: NativeDocument, sourceNoteID: UUID?) -> TaskActionResult {
        let result = withMaterializedTask(id) { actions.commitEditorReference($0, document: document, sourceNoteID: sourceNoteID) }
        didMutate(result)
        return result
    }

    @discardableResult
    func setPriority(_ id: UUID, _ priority: TaskPriority) -> TaskActionResult {
        let result = withMaterializedTask(id) { actions.setPriority($0, priority) }
        didMutate(result)
        return result
    }

    @discardableResult
    func setPinned(_ id: UUID, _ isPinned: Bool) -> TaskActionResult {
        let pinnedBefore = task(for: id)?.isPinned
        let result = withMaterializedTask(id) { actions.setPinned($0, isPinned) }
        didMutate(result)
        if result.taskID != nil, pinnedBefore != isPinned {
            report(FeedbackEvent(kind: .success, message: isPinned ? "已置顶" : "已取消置顶"))
        }
        return result
    }

    @discardableResult
    func convertToNote(_ id: UUID, noteID: UUID, undoNote: @escaping () -> Void) -> TaskActionResult {
        convertToNote(id, noteID: noteID, undoNote: undoNote, redoNote: nil)
    }

    func convertToNote(_ id: UUID, noteID: UUID, undoNote: @escaping () -> Void,
                       redoNote: (() -> Void)?) -> TaskActionResult {
        let result = withMaterializedTask(id) { actions.convertToNote($0, noteID: noteID, undoNote: undoNote, redoNote: redoNote) }
        didMutate(result)
        if result.taskID != nil { select(nil) }
        if result.taskID != nil {
            report(FeedbackEvent(kind: .undoable, message: "已转换为笔记",
                                 actionTitle: "撤销", action: undoStep()))
        }
        return result
    }

    @discardableResult
    func convertToNotes(_ noteIDs: [UUID: UUID], undoNotes: @escaping () -> Void,
                        redoNotes: @escaping () -> Void) -> [UUID] {
        let converted = actions.convertToNotes(noteIDs, undoNotes: undoNotes, redoNotes: redoNotes)
        guard let first = converted.first else { return [] }
        didMutate(.success(first))
        select(nil)
        report(FeedbackEvent(kind: .undoable, message: "已转换 \(converted.count) 个任务为笔记",
                             actionTitle: "撤销", action: undoStep()))
        return converted
    }

    func setTags(_ id: UUID, _ tags: [String]) { didMutate(withMaterializedTask(id) { actions.setTags($0, tags) }) }
    func setReminder(_ id: UUID, _ date: Date?) { didMutate(withMaterializedTask(id) { actions.setReminder($0, date) }) }
    func setAttachments(_ id: UUID, _ values: [NativeAttachment]) { didMutate(withMaterializedTask(id) { actions.setAttachments($0, values) }) }

    func dateFromToday(_ offset: Int) -> Date {
        let start = calendar.startOfDay(for: clock())
        return calendar.date(byAdding: .day, value: offset, to: start) ?? start
    }

    @discardableResult
    func setDueDate(_ id: UUID, _ date: Date?) -> TaskActionResult {
        guard var schedule = task(for: id)?.schedule else { return .failure(.missingTask) }
        schedule.dueAt = date.map(calendar.startOfDay(for:))
        schedule.hasTime = false
        // 没有开始日的区间不成区间：清掉安排日时时间段一并清掉（Flutter 同款）。
        if date == nil { schedule.dueEndAt = nil }
        return setSchedule(id, schedule)
    }

    @discardableResult
    func clearDueDate(_ id: UUID) -> TaskActionResult {
        guard let task = task(for: id) else { return .failure(.missingTask) }
        var schedule = task.schedule
        schedule.dueAt = nil
        schedule.hasTime = false
        schedule.dueEndAt = nil
        let before = self.task(for: id)
        let result = withMaterializedTask(id) { actions.saveTiming($0, schedule: schedule, reminder: task.reminderAt,
                                        frequency: task.recurrence,
                                        recurrenceRule: task.recurrenceRule) }
        didMutate(result)
        reportPlacementChange(before: before, id: result.taskID)
        return result
    }

    @discardableResult
    func clearScheduledProperties(_ id: UUID) -> TaskActionResult {
        guard let task = task(for: id) else { return .failure(.missingTask) }
        var schedule = task.schedule
        schedule.dueAt = nil
        schedule.hasTime = false
        schedule.dueEndAt = nil
        let before = self.task(for: id)
        let result = withMaterializedTask(id) { actions.saveTiming($0, schedule: schedule, reminder: nil,
                                        frequency: .never, recurrenceRule: nil) }
        didMutate(result)
        reportPlacementChange(before: before, id: result.taskID)
        return result
    }

    @discardableResult
    func moveDueDate(_ id: UUID, to date: Date) -> TaskActionResult {
        guard let current = task(for: id)?.schedule else { return .failure(.missingTask) }
        let moved = TaskDateDraft.movingDay(current.dueAt ?? date, to: date, calendar: calendar)
        var next = TaskDateDraft.applying(date: moved, hasTime: current.hasTime,
                                          deadline: false, to: current, calendar: calendar)
        // 对齐 Flutter `updateTaskDue`：改期平移整个时间段，区间长度不变。
        // 只挪开始日会把「9/1 – 9/5」压成「9/3 – 9/5」——日历上一条跨天色带
        // 被拖到别的日子后长度不该变。
        if let start = current.dueAt, let end = current.dueEndAt {
            let shifted = end.addingTimeInterval(moved.timeIntervalSince(start))
            next.dueEndAt = current.hasTime ? shifted : calendar.startOfDay(for: shifted)
        }
        return setSchedule(id, next)
    }

    @discardableResult
    func setDeadline(_ id: UUID, _ date: Date?) -> TaskActionResult {
        guard var schedule = task(for: id)?.schedule else { return .failure(.missingTask) }
        schedule.deadlineAt = date.map(calendar.startOfDay(for:))
        return setSchedule(id, schedule)
    }

    /// 是否有未删除的一级子任务。四象限行尾的「有子任务」标记用它。
    func hasChildren(_ id: UUID) -> Bool {
        allTasks.contains { task in
            task.parentID == id && task.deletedAt == nil && task.skippedAt == nil &&
                !task.isAbandoned && !task.isConverted
        }
    }

    /// 任务被拖进某个象限时的语义（对齐 Flutter `moveTaskToMatrix`）。
    ///
    /// 象限由「重要」（优先级）与「紧急」（安排日在三天内）两个属性推出来，
    /// 所以跨象限就是改这两项：重要性与紧迫性在**改动之前**各算一次，然后按
    /// 象限补齐缺的那一项。`later` 象限里先降优先级再判「重要」会得到另一个
    /// 答案，所以那两个布尔值必须先落定。
    ///
    /// 日期只挪「日」的部分，时刻跟着走（06:30 的任务拖进 Ⅰ 象限仍是今天
    /// 06:30），全天任务仍然是全天。
    @discardableResult
    func moveTaskToMatrix(_ id: UUID, _ quadrant: MatrixQuadrant) -> TaskActionResult {
        guard let current = task(for: id), current.deletedAt == nil,
              current.skippedAt == nil, !current.isAbandoned, !current.isConverted else {
            return .failure(.missingTask)
        }
        let now = clock()
        let important = PlanningProjection.isImportant(current)
        let urgent = PlanningProjection.isUrgent(current, now: now, calendar: calendar)

        func onDay(_ offset: Int) -> TaskSchedule {
            var next = TaskDateDraft.applying(date: TaskDateDraft.movingDay(
                current.schedule.dueAt ?? dateFromToday(offset),
                to: dateFromToday(offset), calendar: calendar),
                hasTime: current.schedule.hasTime, deadline: false,
                to: current.schedule, calendar: calendar)
            // 只挪开始日会截断区间：时间段跟着一起平移，长度不变。
            if let start = current.schedule.dueAt, let end = current.schedule.dueEndAt {
                let shifted = end.addingTimeInterval(
                    (next.dueAt ?? start).timeIntervalSince(start))
                next.dueEndAt = current.schedule.hasTime ? shifted : calendar.startOfDay(for: shifted)
            }
            return next
        }

        var priority: TaskPriority?
        var schedule: TaskSchedule?
        switch quadrant {
        case .doNow:
            if !important { priority = .high }
            if !urgent { schedule = onDay(0) }
        case .schedule:
            if !important { priority = .high }
            if urgent { schedule = onDay(7) }
        case .delegate:
            if important { priority = .low }
            if !urgent { schedule = onDay(0) }
        case .later:
            if important { priority = TaskPriority.none }
            if urgent { schedule = onDay(7) }
        }
        return updateAttributes(id, priority: priority, schedule: schedule)
    }

    // MARK: 反馈上报（A3 加法：动作层只声明发生了什么；显示、时长与仲裁归 FeedbackCenter）

    private func report(_ event: FeedbackEvent) {
        feedbackSink?.show(event)
    }

    /// 单步全局撤销：WorkspaceStore 快照栈回退一次（批量操作是单条事务，一次撤销整批生效）。
    private func undoStep() -> () -> Void {
        { [weak self] in self?.undo() }
    }

    private func quotedTitle(_ id: UUID) -> String {
        guard let title = task(for: id)?.title, !title.isEmpty else { return "任务" }
        return "「\(title)」"
    }

    private func reportBulk(_ operation: TaskBatchOperation, count: Int, changed: Bool) {
        guard changed, count > 0 else { return }
        switch operation {
        case .complete:
            // 批量自带总数，不参与单条合并（再叠一条会重计成 2）。
            report(FeedbackEvent(kind: .completion, message: "已完成 \(count) 个任务",
                                 actionTitle: "撤销", action: undoStep(), sound: .completion))
        case .delete:
            report(FeedbackEvent(kind: .undoable, message: "已删除 \(count) 个任务",
                                 actionTitle: "撤销", action: undoStep()))
        case .move(let list):
            report(FeedbackEvent(kind: .undoable, message: "已移动 \(count) 个任务到「\(list)」",
                                 actionTitle: "撤销", action: undoStep()))
        case .schedule:
            report(FeedbackEvent(kind: .undoable, message: "已调整 \(count) 个任务的日期",
                                 actionTitle: "撤销", action: undoStep()))
        case .priority:
            report(FeedbackEvent(kind: .success, message: "已更新 \(count) 个任务的优先级"))
        case .reminderOffsets:
            report(FeedbackEvent(kind: .success, message: "已更新 \(count) 个任务的提醒"))
        case .pin(let isPinned):
            report(FeedbackEvent(kind: .undoable,
                                 message: isPinned ? "已置顶 \(count) 个任务" : "已取消置顶 \(count) 个任务",
                                 actionTitle: "撤销", action: undoStep()))
        case .duplicate:
            report(FeedbackEvent(kind: .undoable, message: "已复制 \(count) 个任务",
                                 actionTitle: "撤销", action: undoStep()))
        case .abandon:
            report(FeedbackEvent(kind: .undoable, message: "已放弃 \(count) 个任务",
                                 actionTitle: "撤销", action: undoStep()))
        case .tags(let picked):
            report(FeedbackEvent(kind: .success,
                                 message: "已为 \(count) 个任务添加标签「\(picked.joined(separator: "、"))」"))
        case .linkParent:
            report(FeedbackEvent(kind: .undoable, message: "已关联 \(count) 个任务到主任务",
                                 actionTitle: "撤销", action: undoStep()))
        }
    }

    private func didMutate(_ result: TaskActionResult, scope: TaskListScope? = nil) {
        guard result.taskID != nil else { return }
        revision += 1
        if let scope, let selectedTaskID,
           !TaskListProjection.matches(in: scope, store: store, now: clock(), calendar: calendar)
            .contains(where: { $0.id == selectedTaskID }) {
            select(nil)
        }
    }

    private func seed() {
        let today = calendar.startOfDay(for: clock())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        guard let parentID = actions.create(
            title: "整理本周用户反馈",
            list: TaskList(name: "工作"),
            schedule: TaskSchedule(dueAt: today),
            priority: .high
        ).taskID else { return }
        if let first = actions.createChild(parentID, title: "归纳高频问题").taskID {
            _ = actions.setSchedule(first, TaskSchedule(dueAt: today))
        }
        if let second = actions.createChild(parentID, title: "整理改进建议").taskID {
            _ = actions.setSchedule(second, TaskSchedule(dueAt: today))
        }
        _ = actions.create(title: "阅读《设计心理学》第四章",
                           list: TaskList(name: "学习"),
                           schedule: TaskSchedule(dueAt: today))
        _ = actions.create(title: "准备季度复盘材料",
                           list: TaskList(name: "工作"),
                           schedule: TaskSchedule(dueAt: today))
        _ = actions.create(title: "记录下次旅行的想法",
                           list: TaskList(name: "个人"),
                           schedule: TaskSchedule(dueAt: tomorrow))
        if let finished = actions.create(title: "确认本周安排",
                                         list: TaskList(name: "工作"),
                                         schedule: TaskSchedule(dueAt: today)).taskID {
            _ = actions.complete(finished)
        }
        _ = actions.create(title: "随手收集一个想法")
        revision = 0
        store.clearUndo()
    }
}
