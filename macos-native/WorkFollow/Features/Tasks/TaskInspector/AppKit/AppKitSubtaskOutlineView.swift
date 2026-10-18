import AppKit
import SwiftUI

/// 子任务区 AppKit 树形渲染（滴答 `AXOutline` 对应）。
///
/// 用 `NSOutlineView` 承载多级子任务：支持折叠（disclosure triangle）、层级、
/// 双击行内改名。完成框、标题、日期均为 AppKit 控件；命中与动作由外层
/// SwiftUI 通过回调接入，渲染锚点与契约不受影响。
struct AppKitSubtaskOutlineView: NSViewRepresentable {
    /// 顶层子任务（当前任务的直接子任务），按 childOrder 升序。
    let rootTasks: [Task]
    /// 全量任务，用于递归构建子树。
    let allTasks: [Task]
    let completionSize: CGFloat
    /// 行内改名的目标任务（正在编辑则对应标题进入编辑态）。
    let inlineEditingID: UUID?
    /// 日期文本（nil 不显示）。
    let dateLabel: (Task) -> String?
    let onComplete: (UUID) -> Void
    let onOpen: (UUID) -> Void
    let onRename: (UUID, String) -> Void
    /// 拖拽落点：`(被拖任务, 移除自己之后的兄弟下标)`；等于兄弟数即拖到末尾。
    let onReorder: (UUID, Int) -> Void
    /// 折叠状态持久化（按子任务 id）。
    var foldStore = SubtaskFoldStore()

    func makeCoordinator() -> Coordinator {
        Coordinator(foldStore: foldStore)
    }

    func makeNSView(context: Context) -> NSView {
        // 直接返回 NSOutlineView，作为宿主 ScrollView 的普通内容随详情整体滚动，
        // 不再用 NSScrollView 包裹（独立滚动会与宿主滚动冲突，导致坐标错乱）。
        return context.coordinator.outlineView
    }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.rootTasks = rootTasks
        coordinator.allTasks = allTasks
        coordinator.completionSize = completionSize
        coordinator.dateLabel = dateLabel
        coordinator.onComplete = onComplete
        coordinator.onOpen = onOpen
        coordinator.onRename = onRename
        coordinator.onReorder = onReorder
        coordinator.foldStore = foldStore
        coordinator.reload()
        // 仅在"添加子任务"触发的自动编辑 id 变化时聚焦一次，避免每次刷新重复打断输入。
        if let inlineEditingID, inlineEditingID != coordinator.autoEditingID {
            coordinator.autoEditingID = inlineEditingID
            coordinator.beginEditing(taskID: inlineEditingID)
        } else if inlineEditingID == nil {
            coordinator.autoEditingID = nil
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.outlineView.dataSource = nil
        coordinator.outlineView.delegate = nil
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {
        let outlineView = NSOutlineView()
        var rootTasks: [Task] = []
        var allTasks: [Task] = []
        var completionSize: CGFloat = 19
        var autoEditingID: UUID?
        var dateLabel: (Task) -> String? = { _ in nil }
        var onComplete: (UUID) -> Void = { _ in }
        var onOpen: (UUID) -> Void = { _ in }
        var onRename: (UUID, String) -> Void = { _, _ in }
        var onReorder: (UUID, Int) -> Void = { _, _ in }
        var foldStore = SubtaskFoldStore()

        private var tasksByID: [UUID: Task] = [:]
        private var childrenByParent: [UUID: [Task]] = [:]
        private var lastRootTasks: [Task] = []
        private var lastAllTasks: [Task] = []

        static let subtaskDragType = NSPasteboard.PasteboardType("com.workfollow.subtask-id")

        init(foldStore: SubtaskFoldStore) {
            self.foldStore = foldStore
            super.init()
            let column = NSTableColumn(identifier: .init("subtask"))
            column.resizingMask = .autoresizingMask
            outlineView.addTableColumn(column)
            outlineView.outlineTableColumn = column
            outlineView.headerView = nil
            outlineView.rowSizeStyle = .custom
            outlineView.dataSource = self
            outlineView.delegate = self
            outlineView.indentationPerLevel = 16
            outlineView.allowsMultipleSelection = false
            outlineView.target = self
            outlineView.doubleAction = #selector(doubleClicked(_:))
            // 单击打开详情：手势挂在 NSOutlineView 上，不会被 cell 子视图拦截。
            let click = NSClickGestureRecognizer(target: self, action: #selector(outlineClicked(_:)))
            // 不延迟主键事件：行拖拽（TI2-04）要能立刻进入 NSOutlineView 自己的拖拽跟踪，
            // 否则首帧 mouseDown 被手势吃掉，拖拽会话起不来。
            click.delaysPrimaryMouseButtonEvents = false
            outlineView.addGestureRecognizer(click)
            // 子任务拖拽排序（同父级内）。跨父级移动不在这里做。
            outlineView.registerForDraggedTypes([Self.subtaskDragType])
            outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
            outlineView.setDraggingSourceOperationMask(.move, forLocal: false)
            NotificationCenter.default.addObserver(
                self, selector: #selector(itemDidCollapse(_:)),
                name: NSOutlineView.itemDidCollapseNotification, object: outlineView)
            NotificationCenter.default.addObserver(
                self, selector: #selector(itemDidExpand(_:)),
                name: NSOutlineView.itemDidExpandNotification, object: outlineView)
        }

        func reload() {
            // 数据未变就跳过 reloadData，避免行内编辑中的刷新重置 cell 编辑态。
            guard rootTasks != lastRootTasks || allTasks != lastAllTasks else { return }
            lastRootTasks = rootTasks
            lastAllTasks = allTasks
            tasksByID = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
            childrenByParent = [:]
            for task in allTasks where task.parentID != nil {
                childrenByParent[task.parentID!, default: []].append(task)
            }
            for key in childrenByParent.keys {
                childrenByParent[key]?.sort { $0.childOrder < $1.childOrder }
            }
            outlineView.reloadData()
            // 默认展开；用户折叠过的节点按 `SubtaskFoldStore` 恢复（TI2-04）。
            applyFoldState(item: nil)
        }

        private func applyFoldState(item: Any?) {
            let count = outlineView.numberOfChildren(ofItem: item)
            for index in 0..<count {
                let child = outlineView.child(index, ofItem: item) as AnyObject
                guard let task = child as? Task else { continue }
                guard outlineView.isExpandable(child) else { continue }
                if foldStore.isCollapsed(task.id) {
                    outlineView.collapseItem(child, collapseChildren: false)
                } else {
                    outlineView.expandItem(child)
                }
                applyFoldState(item: child)
            }
        }

        @objc private func itemDidCollapse(_ notification: Notification) {
            guard let task = notification.userInfo?["NSObject"] as? Task else { return }
            foldStore.setCollapsed(true, for: task.id)
        }

        @objc private func itemDidExpand(_ notification: Notification) {
            guard let task = notification.userInfo?["NSObject"] as? Task else { return }
            foldStore.setCollapsed(false, for: task.id)
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let task = item as? Task else { return rootTasks.count }
            return childrenByParent[task.id]?.count ?? 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if let task = item as? Task {
                return childrenByParent[task.id]![index]
            }
            return rootTasks[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let task = item as? Task else { return false }
            return !(childrenByParent[task.id]?.isEmpty ?? true)
        }

        // MARK: 拖拽排序（同父级）

        func outlineView(_ outlineView: NSOutlineView,
                         pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let task = item as? Task else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(task.id.uuidString, forType: Self.subtaskDragType)
            return pasteboardItem
        }

        private func draggedTaskID(_ info: NSDraggingInfo) -> UUID? {
            guard let value = info.draggingPasteboard.string(forType: Self.subtaskDragType) else {
                return nil
            }
            return UUID(uuidString: value)
        }

        /// 落点判定：只允许同父级、行与行之间（`index >= 0`）。
        /// -1 表示"落在某行上"（会变成它的子任务），本视图不支持；
        /// 跨父级移动走「关联主任务」等显式入口，拖拽只做排序。
        func acceptsDrop(of id: UUID, into parentID: UUID?, at index: Int) -> Bool {
            guard let source = tasksByID[id] else { return false }
            return source.parentID == parentID && index >= 0
        }

        /// NSOutlineView 给的下标包含被拖行；换算成"移除自己之后"的下标。
        static func adjustedDropIndex(proposed: Int, currentIndex: Int) -> Int {
            proposed - (currentIndex < proposed ? 1 : 0)
        }

        func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                         proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            guard let id = draggedTaskID(info),
                  acceptsDrop(of: id, into: (item as? Task)?.id, at: index) else { return [] }
            return .move
        }

        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo,
                         item: Any?, childIndex index: Int) -> Bool {
            guard let id = draggedTaskID(info),
                  let source = tasksByID[id],
                  acceptsDrop(of: id, into: (item as? Task)?.id, at: index) else { return false }
            let siblings = source.parentID.flatMap { childrenByParent[$0] } ?? rootTasks
            guard let currentIndex = siblings.firstIndex(where: { $0.id == id }) else { return false }
            onReorder(id, Self.adjustedDropIndex(proposed: index, currentIndex: currentIndex))
            return true
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        // MARK: Delegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let task = item as? Task else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("subtask-row")
            let row: SubtaskRowView
            if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? SubtaskRowView {
                row = reused
            } else {
                row = SubtaskRowView()
                row.identifier = identifier
            }
            row.coordinator = self
            // 缩进交给 NSOutlineView 自动处理（NSTableCellView 下 disclosure
            // triangle + 层级缩进都由系统负责），cell 内不再叠加手动缩进。
            row.configure(task: task, completionSize: completionSize,
                          dateText: dateLabel(task))
            return row
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            TaskInspectorMetrics.childRowMinHeight
        }

        // MARK: Row interaction

        func completeTapped(_ task: Task) { onComplete(task.id) }
        func openTapped(_ task: Task) { onOpen(task.id) }

        func beginEditing(taskID: UUID) {
            // reloadData 后行是懒加载的，等下一轮 runloop 再定位 cell。
            DispatchQueue.main.async { [weak self] in
                guard let self, let row = self.rowView(for: taskID) else { return }
                row.beginEditing()
            }
        }

        func commitEditing(taskID: UUID, text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            onRename(taskID, trimmed)
        }

        private func rowView(for taskID: UUID) -> SubtaskRowView? {
            for index in 0..<outlineView.numberOfRows {
                guard let task = outlineView.item(atRow: index) as? Task,
                      task.id == taskID else { continue }
                return outlineView.view(atColumn: 0, row: index, makeIfNecessary: true) as? SubtaskRowView
            }
            return nil
        }

        @objc private func outlineClicked(_ sender: NSClickGestureRecognizer) {
            let point = sender.location(in: outlineView)
            let row = outlineView.row(at: point)
            guard row >= 0, let task = outlineView.item(atRow: row) as? Task else { return }
            openTapped(task)
        }

        @objc private func doubleClicked(_ sender: Any?) {
            let row = outlineView.clickedRow
            guard row >= 0, let task = outlineView.item(atRow: row) as? Task else { return }
            openTapped(task)
        }

        // MARK: NSTextFieldDelegate

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField,
                  let row = field.superview as? SubtaskRowView,
                  let taskID = row.taskID else { return }
            commitEditing(taskID: taskID, text: field.stringValue)
        }
    }
}

/// 标题字段：非编辑态不拦截点击（穿透到 outlineView，让单击手势打开详情）。
final class SubtaskTitleField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        if isEditable { return super.hitTest(point) }
        return nil
    }
}

/// 子任务行的迷你标记（TI2-12）。
///
/// 滴答 `TTSubtasksCell` 有 `shouldShowTags` / `shouldShowMiniIcons` / `shouldShowAssignee`；
/// 本地先取"有数据才显示"的那部分，数据源与列表行完全同构（`TaskSecondaryMetadata`），
/// 不新增第二套规则。标签仍由详情里的 chips 行承载，不在行内重复。
enum SubtaskRowMetadata {
    static func indicatorSymbols(for task: Task) -> [String] {
        TaskSecondaryMetadata.items(for: task, subtaskProgress: nil)
            .filter { $0.id != "tags" }
            .compactMap(\.symbol)
    }
}

/// 子任务行 cell：完成框 + 标题（可编辑）+ 日期。
final class SubtaskRowView: NSTableCellView {
    weak var coordinator: AppKitSubtaskOutlineView.Coordinator?
    var taskID: UUID?
    private var task: Task?
    private var hovering = false

    private let completionBox = CompletionBoxView()
    private let titleField = SubtaskTitleField()
    private let dateField = NSTextField(labelWithString: "")
    private let completionButton = NSButton()
    private let indicatorStack = NSStackView()
    private var trackingArea: NSTrackingArea?
    /// 供测试断言：当前行渲染了几个迷你标记。
    var indicatorCount: Int { indicatorStack.arrangedSubviews.count }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        completionButton.title = ""
        completionButton.isBordered = false
        completionButton.isTransparent = true
        completionButton.bezelStyle = .inline
        completionButton.focusRingType = .none
        completionButton.target = self
        completionButton.action = #selector(completionClicked)

        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.lineBreakMode = .byTruncatingTail
        titleField.font = .systemFont(ofSize: 14, weight: .medium)
        titleField.delegate = nil
        titleField.target = self
        titleField.action = #selector(titleCommitted)

        dateField.font = .systemFont(ofSize: 12)
        dateField.textColor = .secondaryLabelColor
        dateField.isBordered = false
        dateField.drawsBackground = false

        indicatorStack.orientation = .horizontal
        indicatorStack.spacing = 4
        indicatorStack.alignment = .centerY
        indicatorStack.setAccessibilityLabel("任务标记")

        addSubview(completionBox)
        // completionButton 盖在完成框之上接收点击（完成/取消完成）。
        addSubview(completionButton)
        addSubview(titleField)
        addSubview(indicatorStack)
        addSubview(dateField)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    /// 只画悬停高亮（NSOutlineView 复用 cell 时 layer 背景会丢失）。
    /// 常态不再铺 4% 灰底——滴答子任务行是白底，底色会让整块子任务区像卡片。
    override func draw(_ dirtyRect: NSRect) {
        guard hovering else {
            super.draw(dirtyRect)
            return
        }
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        super.draw(dirtyRect)
    }

    func configure(task: Task, completionSize: CGFloat, dateText: String?) {
        self.task = task
        self.taskID = task.id
        // cell 复用时重置悬停态，避免复用带 hover 高亮的旧 cell。
        hovering = false
        needsDisplay = true
        completionBox.size = completionSize
        completionBox.completed = task.isClosed
        completionBox.needsDisplay = true
        titleField.stringValue = task.title.isEmpty ? "未命名子任务" : task.title
        titleField.textColor = task.isClosed ? .tertiaryLabelColor : .labelColor
        // cell 复用时重置编辑态；编辑由 coordinator.beginEditing 单独触发。
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.delegate = nil
        if let dateText, !dateText.isEmpty {
            dateField.stringValue = dateText
            dateField.isHidden = false
        } else {
            dateField.isHidden = true
        }
        configureIndicators(symbols: SubtaskRowMetadata.indicatorSymbols(for: task))
        needsLayout = true
    }

    /// 迷你标记：重复 / 提醒 / 描述 / 附件（有才画，图标 10pt、4pt 间距）。
    private func configureIndicators(symbols: [String]) {
        indicatorStack.arrangedSubviews.forEach {
            indicatorStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for symbol in symbols {
            let image = NSImageView()
            image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)
            image.contentTintColor = .tertiaryLabelColor
            image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            image.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                image.widthAnchor.constraint(equalToConstant: 14),
                image.heightAnchor.constraint(equalToConstant: 14)
            ])
            indicatorStack.addArrangedSubview(image)
        }
        indicatorStack.isHidden = symbols.isEmpty
    }

    func beginEditing() {
        guard let task else { return }
        titleField.isEditable = true
        titleField.isSelectable = true
        titleField.stringValue = task.title
        titleField.delegate = coordinator
        // 等 cell 挂到窗口后再夺焦点，否则 makeFirstResponder 落到空 window。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.titleField)
            self.titleField.currentEditor()?.selectAll(nil)
        }
    }

    @objc private func completionClicked() {
        guard let task else { return }
        coordinator?.completeTapped(task)
    }

    @objc private func titleCommitted() {
        guard let taskID, titleField.isEditable else { return }
        titleField.isEditable = false
        titleField.delegate = nil
        coordinator?.commitEditing(taskID: taskID, text: titleField.stringValue)
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        let completionSize = completionBox.size
        completionButton.frame = NSRect(x: 0, y: 0, width: 30, height: bounds.height)
        completionBox.frame = NSRect(x: 5, y: (bounds.height - completionSize) / 2,
                                     width: completionSize, height: completionSize)
        let titleX: CGFloat = 34
        let dateWidth: CGFloat = dateField.isHidden ? 0 : 90
        let indicatorCount = indicatorStack.isHidden ? 0 : indicatorStack.arrangedSubviews.count
        let indicatorWidth: CGFloat = indicatorCount == 0
            ? 0 : CGFloat(indicatorCount) * 14 + CGFloat(indicatorCount - 1) * 4
        let indicatorsX = max(titleX + 40, bounds.width - 12 - dateWidth
            - (dateWidth > 0 ? 8 : 0) - indicatorWidth)
        let titleWidth = max(40, indicatorsX - titleX - 8)
        titleField.frame = NSRect(x: titleX, y: (bounds.height - 20) / 2,
                                  width: titleWidth, height: 20)
        indicatorStack.frame = NSRect(x: indicatorsX, y: (bounds.height - 14) / 2,
                                      width: indicatorWidth, height: 14)
        if !dateField.isHidden {
            dateField.frame = NSRect(x: bounds.width - 12 - dateWidth,
                                     y: (bounds.height - 18) / 2,
                                     width: dateWidth, height: 18)
        }
        updateTrackingAreas()
    }
}
