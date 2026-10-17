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

    func makeCoordinator() -> Coordinator {
        Coordinator()
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

        private var tasksByID: [UUID: Task] = [:]
        private var childrenByParent: [UUID: [Task]] = [:]
        private var lastRootTasks: [Task] = []
        private var lastAllTasks: [Task] = []

        override init() {
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
            outlineView.addGestureRecognizer(click)
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
            // 默认展开所有层级（多级子任务可见；用户可手动折叠）。
            expandAll(item: nil)
        }

        private func expandAll(item: Any?) {
            let count = outlineView.numberOfChildren(ofItem: item)
            for index in 0..<count {
                let child = outlineView.child(index, ofItem: item) as AnyObject
                outlineView.expandItem(child)
                expandAll(item: child)
            }
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
    private var trackingArea: NSTrackingArea?

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

        addSubview(completionBox)
        // completionButton 盖在完成框之上接收点击（完成/取消完成）。
        addSubview(completionButton)
        addSubview(titleField)
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

    /// 悬停高亮用 draw 绘制（NSOutlineView 复用 cell 时 layer 背景会丢失）。
    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = 5
        if hovering {
            NSColor.labelColor.withAlphaComponent(0.07).setFill()
        } else {
            NSColor.labelColor.withAlphaComponent(0.04).setFill()
        }
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
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
        needsLayout = true
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
        let titleWidth = max(40, bounds.width - titleX - dateWidth - 12)
        titleField.frame = NSRect(x: titleX, y: (bounds.height - 20) / 2,
                                  width: titleWidth, height: 20)
        if !dateField.isHidden {
            dateField.frame = NSRect(x: titleX + titleWidth + 8, y: (bounds.height - 18) / 2,
                                     width: dateWidth, height: 18)
        }
        updateTrackingAreas()
    }
}
