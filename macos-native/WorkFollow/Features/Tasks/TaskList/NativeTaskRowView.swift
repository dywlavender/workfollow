import AppKit
import Combine
import SwiftUI

/// A row's current data and commands. Domain mutations still go through the
/// same workspace; only the list's presentation uses AppKit instead of a host
/// and a SwiftUI graph for every task.
struct NativeTaskRowConfiguration {
    let task: Task
    let workspace: TaskWorkspaceModel
    let environment: AppEnvironment
    let depth: Int
    let hasChildren: Bool
    let expanded: Bool
    let bulkSelected: Bool
    let recentlyCreated: Bool
    let showsListBadge: Bool
    let hidesDetails: Bool
    let hiddenFields: [TaskRowDetailField]
    let allowsReordering: Bool
    let dateDisplay: TaskDateDisplayMode
    let feedback: TaskDropFeedback
    let onEditingRequested: () -> Void
    let onEditingBegan: () -> Void
    let onEditingEnded: () -> Void
    let onSelect: () -> Void
    let onBulkToggle: () -> Void
    let onRangeSelect: () -> Void
    let onComplete: () -> Void
    let onRestore: () -> Void
    let onToggleExpanded: () -> Void
}

final class NativeTaskRowView: NSView {
    private(set) var configuration: NativeTaskRowConfiguration?
    private var values = EnvironmentValues()
    private let hover = RowHoverView()
    private let completion = PaintButton()
    private let disclosure = PaintButton()
    private let dateButton = PaintButton()
    private let preview = TextLabel()
    private let dragHandle = DragHandle()
    private let divider = CALayer()
    private let strike = CAShapeLayer()
    private let dropOverlay = DropOverlay()
    private var metadata: [NSView] = []
    private var tags: [TextLabel] = []
    private var titleCoordinator: TaskRowTitleField.Coordinator!
    private(set) var titleField: TaskRowTitleField.Field!
    private var feedbackSubscription: AnyCancellable?
    private weak var observedFeedback: TaskDropFeedback?
    private var dropPlacement: TaskDropPlacement?
    private var selectedTaskID: UUID?
    private var selected = false
    private var isRowHovered = false
    private var metadataWidth: CGFloat = 0
    private struct AppearanceKey: Equatable {
        let scheme: ColorScheme
        let theme: NativeBackgroundTheme
        let canvas: Bool
    }
    private var appearanceKey: AppearanceKey?
    var framesDidChange: (() -> Void)?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clipsToBounds = false
        hover.onHover = { [weak self] inside in
            self?.isRowHovered = inside
            self?.updateDragHandleVisibility()
        }
        addSubview(hover)
        let initial = TaskRowTitleField(title: "", color: WFColors.text,
            onEditingRequested: {}, onEditingBegan: {}, onEditingEnded: {}, onCommit: { _ in })
        titleCoordinator = .init(parent: initial)
        titleField = TaskRowTitleField.makeField(parent: initial, coordinator: titleCoordinator)
        for view in [completion, disclosure, dateButton, preview, titleField!, dragHandle] { addSubview(view) }
        layer?.addSublayer(divider)
        layer?.addSublayer(strike)
        dropOverlay.row = self
        addSubview(dropOverlay)
        completion.drawContent = { [weak self] in self?.drawCompletion() }
        completion.pressed = { [weak self] in self?.toggleCompletion() }
        disclosure.drawContent = { [weak self] in
            guard let self, let config = self.configuration else { return }
            let rect = self.disclosure.bounds
            let path = NSBezierPath()
            if config.expanded {
                path.move(to: CGPoint(x: rect.midX - 3, y: rect.midY - 1.5))
                path.line(to: CGPoint(x: rect.midX, y: rect.midY + 1.5))
                path.line(to: CGPoint(x: rect.midX + 3, y: rect.midY - 1.5))
            } else {
                path.move(to: CGPoint(x: rect.midX - 1.5, y: rect.midY - 3))
                path.line(to: CGPoint(x: rect.midX + 1.5, y: rect.midY))
                path.line(to: CGPoint(x: rect.midX - 1.5, y: rect.midY + 3))
            }
            NSColor(WFColors.secondaryText).setStroke()
            path.lineWidth = 1.2; path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.stroke()
        }
        disclosure.pressed = { [weak self] in self?.configuration?.onToggleExpanded() }
        dateButton.pressed = { [weak self] in self?.openDate() }
        dragHandle.row = self
        setHoverTip("拖动调整任务顺序", on: dragHandle)
        strike.fillColor = nil
        strike.lineWidth = 1.25
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ config: NativeTaskRowConfiguration, selectedTaskID: UUID?, values: EnvironmentValues) {
        self.configuration = config
        self.selectedTaskID = selectedTaskID
        self.values = values
        strike.removeAllAnimations(); strike.path = nil; strike.opacity = 0
        let task = config.task
        let readOnly = config.workspace.isListArchived(task.list.name)
        titleCoordinator.parent = TaskRowTitleField(title: task.title, color: titleColor,
            onEditingRequested: config.onEditingRequested, onEditingBegan: config.onEditingBegan,
            onEditingEnded: config.onEditingEnded,
            onCommit: { [weak workspace = config.workspace] in _ = workspace?.setTitle(task.id, $0) })
        if !titleField.editingSession, titleField.stringValue != task.title { titleField.stringValue = task.title }
        titleField.isEditable = !readOnly
        completion.isEnabled = !readOnly
        completion.setAccessibilityLabel((task.isClosed ? "恢复：" : "完成：") + task.title)
        setHoverTip(task.isClosed ? "恢复任务" : "完成任务", on: completion)
        disclosure.isHidden = !(config.depth == 0 && config.hasChildren)
        disclosure.setAccessibilityLabel((config.expanded ? "收起子任务：" : "展开子任务：") + task.title)
        setHoverTip(config.expanded ? "收起子任务" : "展开子任务", on: disclosure)
        preview.stringValue = TaskListViewDefaults.bodyPreview(of: task.document) ?? ""
        preview.isHidden = preview.stringValue.isEmpty
        preview.font = .systemFont(ofSize: 12)
        updateMetadata()
        updateTags()
        if observedFeedback !== config.feedback {
            observedFeedback = config.feedback
            feedbackSubscription = config.feedback.$target.sink { [weak self] target in
                guard let self, let id = self.configuration?.task.id else { return }
                let next = target?.rowID == id ? target?.placement : nil
                if self.dropPlacement != next { self.dropPlacement = next; self.dropOverlay.needsDisplay = true }
            }
        }
        if config.allowsReordering { registerForDraggedTypes([.string]) } else { unregisterDraggedTypes() }
        appearanceKey = nil
        updateAppearance(values)
        setSelection(selectedTaskID)
        needsLayout = true
    }

    func updateAppearance(_ values: EnvironmentValues) {
        self.values = values
        let key = AppearanceKey(scheme: values.colorScheme, theme: values.workfollowBackgroundTheme,
                                canvas: values.workfollowPageCanvasActive)
        guard appearanceKey != key else { return }
        appearanceKey = key
        appearance = NSAppearance(named: values.colorScheme == .dark ? .darkAqua : .aqua)
        hover.selectedFill = WFColors.listSelectionFill(theme: values.workfollowBackgroundTheme,
                                                       pageCanvasActive: values.workfollowPageCanvasActive)
        titleField.textColor = NSColor(titleColor)
        preview.textColor = NSColor(configuration?.task.status == .completed ? WFColors.taskCompletedPreview : WFColors.taskPreviewText)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            divider.backgroundColor = NSColor(WFColors.listRowSeparator).cgColor
        }
        completion.needsDisplay = true
        disclosure.needsDisplay = true
        dateButton.needsDisplay = true
        needsDisplay = true
    }

    private var titleColor: Color {
        guard let task = configuration?.task else { return WFColors.text }
        return task.status == .completed ? WFColors.taskCompletedTitle : task.isClosed ? WFColors.secondaryText : WFColors.text
    }

    private var muted: NSColor {
        guard let task = configuration?.task else { return NSColor(WFColors.taskMetaText) }
        return NSColor(task.status == .completed ? WFColors.taskCompletedMetadata : task.isClosed ? WFColors.tertiaryText : WFColors.taskMetaText)
    }

    func setSelection(_ id: UUID?) {
        selectedTaskID = id
        guard let config = configuration else { return }
        selected = id == config.task.id || config.bulkSelected
        hover.setSelected(selected || config.recentlyCreated)
        divider.isHidden = selected
        updateDragHandleVisibility()
    }

    private func updateDragHandleVisibility() {
        dragHandle.isHidden = configuration?.allowsReordering != true
            || !(isRowHovered || selected)
        dragHandle.needsDisplay = true
    }

    private func label(_ value: String, size: CGFloat = 10, color: NSColor? = nil,
                       accessibility: String? = nil) -> TextLabel {
        let view = TextLabel()
        view.stringValue = value
        view.font = .systemFont(ofSize: size)
        view.textColor = color ?? muted
        if let accessibility {
            view.setAccessibilityLabel(accessibility)
            setHoverTip(accessibility, on: view)
        }
        return view
    }

    private func setHoverTip(_ title: String, on view: NSView) {
        let tip: HoverTipTrackingView
        if let existing = view.subviews.first(where: { $0 is HoverTipTrackingView }) as? HoverTipTrackingView {
            tip = existing
        } else {
            tip = HoverTipTrackingView(frame: view.bounds)
            tip.autoresizingMask = [.width, .height]
            view.addSubview(tip)
        }
        tip.title = title
    }

    private func updateMetadata() {
        metadata.forEach { $0.removeFromSuperview() }
        metadata.removeAll(keepingCapacity: true)
        dateButton.isHidden = true
        guard let c = configuration, !c.hidesDetails else { metadataWidth = 0; return }
        let task = c.task
        func append(_ view: NSView) { metadata.append(view); addSubview(view) }
        func icon(_ name: String, accessibility: String, color: NSColor? = nil) {
            let view = SymbolView()
            view.image = NSImage(systemSymbolName: name, accessibilityDescription: accessibility)?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
            view.contentTintColor = color ?? muted
            view.setAccessibilityLabel(accessibility)
            setHoverTip(accessibility, on: view)
            append(view)
        }
        if task.isPinned { icon("pin.fill", accessibility: "已置顶", color: task.isClosed ? muted : NSColor(WFColors.accent)) }
        if task.isAbandoned { append(label("已放弃")) }
        if c.showsListBadge, !c.hiddenFields.contains(.list), task.list.name != TaskList.inbox.name { append(label(task.list.name)) }
        if !c.hiddenFields.contains(.indicators) {
            let items = TaskSecondaryMetadata.items(for: task,
                subtaskProgress: c.workspace.subtaskProgress(for: task.id),
                checklistProgress: c.workspace.checklistProgress(for: task))
                .filter { $0.id != "tags" }.prefix(WFMetrics.secondaryMetadataLimit)
            for item in items {
                if let text = item.value { append(label(text, accessibility: item.accessibilityLabel)) }
                else if let symbol = item.symbol { icon(symbol, accessibility: item.accessibilityLabel) }
            }
        }
        let now = c.workspace.clock()
        let calendar = c.workspace.calendar
        if !c.hiddenFields.contains(.date), let deadline = task.schedule.deadlineAt {
            let overdue = !task.isClosed && calendar.startOfDay(for: deadline) <= calendar.startOfDay(for: now)
            append(label(TaskDateLabel.text(deadline, hasTime: false, now: now, calendar: calendar) + "截止",
                         color: overdue ? .systemRed : muted))
        }
        if !c.hiddenFields.contains(.date), let due = task.schedule.dueAt {
            dateButton.isHidden = false
            let text = TaskListViewDefaults.scheduleLabel(dueAt: due, dueEndAt: task.schedule.dueEndAt,
                hasTime: task.schedule.hasTime, now: now, calendar: calendar, dateDisplay: c.dateDisplay)
            let style = TaskListViewDefaults.dateBadgeStyle(dueAt: due, dueEndAt: task.schedule.dueEndAt,
                hasTime: task.schedule.hasTime, isClosed: task.isClosed, now: now, calendar: calendar)
            let color = task.isClosed ? muted : NSColor(TaskListViewDefaults.rowDateColor(for: style))
            dateButton.text = text
            dateButton.textColor = color
            dateButton.drawContent = nil
            setHoverTip("修改安排日期", on: dateButton)
            dateButton.isEnabled = !c.workspace.isListArchived(task.list.name)
            dateButton.setAccessibilityLabel("安排日期：" + (task.title.isEmpty ? "无标题" : task.title))
        }
        metadataWidth = metadata.reduce(0) { $0 + metadataSize($1) + 3 }
            + (dateButton.isHidden ? 0 : dateButton.textWidth)
        if dateButton.isHidden, !metadata.isEmpty { metadataWidth -= 3 }
    }

    private func metadataSize(_ view: NSView) -> CGFloat {
        if let label = view as? TextLabel {
            let isList = label.stringValue == configuration?.task.list.name
            return min(isList ? 40 : 140, label.textWidth)
        }
        return 14
    }

    private func updateTags() {
        tags.forEach { $0.removeFromSuperview() }
        tags.removeAll(keepingCapacity: true)
        guard let c = configuration, !c.hidesDetails, !c.hiddenFields.contains(.tags) else { return }
        for name in c.task.tags.prefix(TaskListMetrics.maxVisibleTags) {
            let tint = c.workspace.tag(named: name)?.colorARGB.map { NSColor(WFListPalette.swatch($0)) }
            let chip = label(name, size: 11, color: tint ?? NSColor(WFColors.text))
            chip.chipFill = tint?.withAlphaComponent(0.1) ?? NSColor(WFColors.hover)
            chip.horizontalPadding = 6
            chip.setAccessibilityLabel("标签：" + name)
            tags.append(chip); addSubview(chip)
        }
        let overflow = c.task.tags.count - TaskListMetrics.maxVisibleTags
        if overflow > 0 {
            let more = label("+\(overflow)", size: 11, color: NSColor(WFColors.secondaryText))
            tags.append(more); addSubview(more)
        }
    }

    override func layout() {
        #if DEBUG
        let started = ProcessInfo.processInfo.systemUptime
        defer { NativeTaskOutline.Diagnostics.rowLayoutTime += ProcessInfo.processInfo.systemUptime - started }
        #endif
        super.layout()
        guard let c = configuration else { return }
        hover.frame = bounds
        let indent = CGFloat(c.depth) * TaskListMetrics.hierarchyIndent
        let top = TaskListMetrics.rowVerticalPadding
        let titleX = TaskListMetrics.titleLeading + indent
        disclosure.frame = CGRect(x: TaskListMetrics.rowContentLeading + indent, y: top, width: 15, height: 19)
        completion.frame = CGRect(x: TaskListMetrics.checkboxLeading + indent, y: top, width: 19, height: 19)
        let right = max(titleX + 96, bounds.width - TaskListMetrics.rowTrailingPadding)
        let trailWidth = min(metadataWidth, max(0, right - titleX - 104))
        let trailX = right - trailWidth
        titleField.frame = titleField.frame(forAlignmentRect: CGRect(x: titleX, y: top,
            width: max(96, trailX - titleX - (trailWidth > 0 ? 8 : 0)), height: 18))
        var x = trailX
        for view in metadata {
            let width = min(metadataSize(view), max(0, right - x - (dateButton.isHidden ? 0 : dateButton.textWidth + 3)))
            view.frame = CGRect(x: x, y: top + 2, width: width, height: 14)
            x += width + 3
        }
        dateButton.frame = CGRect(x: right - dateButton.textWidth, y: top, width: dateButton.textWidth, height: 18)
        preview.frame = CGRect(x: titleX, y: top + 21, width: max(0, right - titleX), height: 15)
        var tagX = titleX
        let tagY = top + 18 + (preview.isHidden ? 0 : 18) + TaskListMetrics.tagRowSpacing
        for tag in tags {
            let width = min(tag.textWidth, max(0, right - tagX))
            tag.frame = CGRect(x: tagX, y: tagY, width: width, height: TaskListMetrics.tagChipHeight)
            tagX += width + 2
        }
        dragHandle.frame = CGRect(x: -14 + indent, y: (bounds.height - 14) / 2, width: 14, height: 14)
        dropOverlay.frame = bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        divider.frame = CGRect(x: titleX, y: bounds.height - ListRowMetrics.dividerHeight,
                               width: max(0, bounds.width - titleX - WFSpace.lg), height: ListRowMetrics.dividerHeight)
        CATransaction.commit()
        framesDidChange?()
    }

    private func drawDropFeedback() {
        guard let placement = dropPlacement else { return }
        NSColor(WFColors.accent).setStroke()
        let path: NSBezierPath
        switch placement {
        case .childOf:
            path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: WFMetrics.corner, yRadius: WFMetrics.corner)
            let text = "作为子任务" as NSString
            text.draw(at: CGPoint(x: max(3, bounds.width - 55), y: bounds.height - 16),
                      withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor(WFColors.secondaryText)])
        case .before, .rootBefore:
            path = NSBezierPath(); path.move(to: CGPoint(x: 16, y: 0.5)); path.line(to: CGPoint(x: bounds.width - 16, y: 0.5))
        case .after, .rootAfter:
            path = NSBezierPath(); path.move(to: CGPoint(x: 16, y: bounds.height - 0.5)); path.line(to: CGPoint(x: bounds.width - 16, y: bounds.height - 0.5))
        }
        path.lineWidth = 1; path.stroke()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if !dragHandle.isHidden, dragHandle.frame.contains(local), NSApp.currentEvent?.type != .rightMouseDown { return dragHandle }
        guard bounds.contains(local) else { return nil }
        if NSApp.currentEvent?.type == .rightMouseDown { return self }
        if NSApp.currentEvent?.modifierFlags.intersection([.command, .shift]).isEmpty == false { return self }
        if let c = configuration, c.workspace.isListArchived(c.task.list.name) { return self }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        guard let c = configuration else { return }
        if event.modifierFlags.contains(.command) { c.onBulkToggle() }
        else if event.modifierFlags.contains(.shift) { c.onRangeSelect() }
        else if c.workspace.isListArchived(c.task.list.name) { c.onSelect() }
        else { titleField.beginEditing() }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let c = configuration, !c.workspace.isListArchived(c.task.list.name),
              let task = c.workspace.task(for: c.task.id) else { return }
        if c.workspace.selectedTaskID != task.id, !c.workspace.bulkSelection.contains(task.id) {
            c.workspace.clearBulkSelection(); c.workspace.select(task.id)
        }
        let point = convert(event.locationInWindow, from: nil)
        TaskContextMenuPresenter.show(in: self, at: point, environment: c.environment,
            workspace: c.workspace, task: task, onCustomDate: { [weak self] in self?.openDate(at: point) })
    }

    private func toggleCompletion() {
        guard let c = configuration else { return }
        if c.task.isClosed { c.onRestore() }
        else {
            TaskCompletionFeedback.play()
            let path = CGMutablePath()
            let titleRect = titleField.alignmentRect(forFrame: titleField.frame)
            path.move(to: CGPoint(x: titleRect.minX, y: titleRect.minY + 9))
            path.addLine(to: CGPoint(x: titleRect.maxX, y: titleRect.minY + 9))
            strike.path = path; strike.strokeColor = NSColor(WFColors.taskCompletedTitle).cgColor
            strike.opacity = 1
            let sweep = CABasicAnimation(keyPath: "strokeEnd"); sweep.fromValue = 0; sweep.toValue = 1; sweep.duration = 0.26
            strike.add(sweep, forKey: "completion")
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1; fade.toValue = 0; fade.beginTime = CACurrentMediaTime() + 0.85; fade.duration = 0.25
            fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
            strike.add(fade, forKey: "completion-fade")
            c.onComplete()
        }
    }

    private func drawCompletion() {
        guard let task = configuration?.task else { return }
        if task.isAbandoned { drawSymbol("circle.slash", size: 15, color: NSColor(WFColors.secondaryText), in: completion.bounds); return }
        let box = CGRect(x: 0, y: 1, width: 17, height: 17)
        let path = NSBezierPath(roundedRect: box, xRadius: 4.3, yRadius: 4.3)
        if task.isClosed {
            NSColor(WFColors.taskCompletedCheckbox).setFill(); path.fill()
            drawSymbol("checkmark", size: 10, weight: .semibold, color: NSColor(WFColors.onAccent), in: box)
        } else {
            NSColor(TaskRowPriority.color(task.priority)).setStroke(); path.lineWidth = 1.5; path.stroke()
        }
    }

    private func drawSymbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, in rect: CGRect) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight)) else { return }
        let colored = image.withSymbolConfiguration(.init(paletteColors: [color])) ?? image
        let imageSize = colored.size
        colored.draw(in: CGRect(x: rect.midX - imageSize.width / 2, y: rect.midY - imageSize.height / 2,
                                width: imageSize.width, height: imageSize.height),
                     from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func openDate(at point: CGPoint? = nil) {
        guard let c = configuration, window != nil else { return }
        let rect = point.map { CGRect(origin: $0, size: CGSize(width: 1, height: 1)) } ?? dateButton.frame
        NativeTaskDatePresenter.show(in: self, anchor: rect, configuration: c, values: values)
    }

    private func destination(_ sender: NSDraggingInfo) -> TaskDropPlacement? {
        guard let c = configuration, c.allowsReordering else { return nil }
        return TaskReorderDropDelegate.destination(at: convert(sender.draggingLocation, from: nil),
            rowHeight: bounds.height, depth: c.depth, targetID: c.task.id, parentID: c.task.parentID)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let c = configuration, let placement = destination(sender),
              let payload = sender.draggingPasteboard.string(forType: .string), UUID(uuidString: payload) != nil else { return [] }
        c.feedback.update(rowID: c.task.id, placement: placement)
        if let event = NSApp.currentEvent { enclosingScrollView?.autoscroll(with: event) }
        return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        if let c = configuration { c.feedback.exit(rowID: c.task.id) }
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        sender.animatesToDestination = false
        return destination(sender) != nil
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let c = configuration, let placement = destination(sender),
              let payload = sender.draggingPasteboard.string(forType: .string) else { return false }
        c.feedback.clear()
        return TaskReorderDropDelegate.apply(payload: payload, placement: placement, workspace: c.workspace)
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { configuration?.feedback.clear() }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            strike.removeAllAnimations(); strike.path = nil; strike.opacity = 0
            titleField.onFinish?(false)
            if let c = configuration { c.feedback.exit(rowID: c.task.id) }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    #if DEBUG
    var renderFrames: [TaskTreeRenderAnchor: CGRect] {
        guard let id = configuration?.task.id else { return [:] }
        var parts: [TaskTreeRenderPart: CGRect] = [.row: bounds, .title: titleField.alignmentRect(forFrame: titleField.frame),
            .checkbox: completion.frame, .disclosure: disclosure.frame]
        if !preview.isHidden { parts[.preview] = preview.frame }
        if !dateButton.isHidden { parts[.date] = dateButton.frame }
        return Dictionary(uniqueKeysWithValues: parts.map { (TaskTreeRenderAnchor(taskID: id, part: $0.key), $0.value) })
    }
    #endif

    private final class SymbolView: NSImageView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private final class DropOverlay: NSView {
        weak var row: NativeTaskRowView?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) { row?.drawDropFeedback() }
    }

    private final class TextLabel: NSTextField {
        var chipFill: NSColor?
        var horizontalPadding: CGFloat = 0
        init() {
            super.init(frame: .zero)
            isBordered = false; drawsBackground = false; isEditable = false; isSelectable = false
            lineBreakMode = .byTruncatingTail; usesSingleLineMode = true
            focusRingType = .none
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        var textWidth: CGFloat { ceil((stringValue as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 10)]).width) + horizontalPadding * 2 }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) {
            if let chipFill { chipFill.setFill(); NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill() }
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 10), .foregroundColor: textColor ?? NSColor.labelColor, .paragraphStyle: paragraph]
            let height = (stringValue as NSString).size(withAttributes: attributes).height
            (stringValue as NSString).draw(in: CGRect(x: horizontalPadding, y: (bounds.height - height) / 2,
                width: max(0, bounds.width - horizontalPadding * 2), height: height), withAttributes: attributes)
        }
    }

    private final class PaintButton: NSButton {
        var pressed: (() -> Void)?
        var drawContent: (() -> Void)?
        var text = ""
        var textColor = NSColor.labelColor
        var textWidth: CGFloat { ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10)]).width) }
        override init(frame: NSRect) {
            super.init(frame: frame)
            isBordered = false; title = ""; target = self; action = #selector(activate)
            focusRingType = .none
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        @objc private func activate() { pressed?() }
        override func draw(_ dirtyRect: NSRect) {
            if let drawContent { drawContent(); return }
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: textColor]
            let height = (text as NSString).size(withAttributes: attributes).height
            (text as NSString).draw(in: CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height), withAttributes: attributes)
        }
    }

    private final class DragHandle: NSView, NSDraggingSource {
        weak var row: NativeTaskRowView?
        private var down: NSEvent?
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override init(frame: NSRect) { super.init(frame: frame); setAccessibilityRole(.button); setAccessibilityLabel("拖动调整任务顺序") }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func draw(_ dirtyRect: NSRect) { row?.drawSymbol("line.3.horizontal", size: 10, color: NSColor(WFColors.secondaryText), in: bounds) }
        override func mouseDown(with event: NSEvent) { down = event }
        override func mouseDragged(with event: NSEvent) {
            guard down != nil, let row, let c = row.configuration else { return }
            down = nil
            let item = NSDraggingItem(pasteboardWriter: c.task.id.uuidString as NSString)
            let text = c.task.title.isEmpty ? "无标题" : c.task.title
            let font = NSFont.systemFont(ofSize: 14)
            let size = CGSize(width: min(TaskListMetrics.dragPreviewMaxWidth, ceil((text as NSString).size(withAttributes: [.font: font]).width)), height: 22)
            let image = NSImage(size: size, flipped: true) { rect in
                let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
                (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: NSColor(WFColors.text), .paragraphStyle: paragraph]); return true
            }
            item.setDraggingFrame(CGRect(origin: convert(event.locationInWindow, from: nil), size: size), contents: image)
            beginDraggingSession(with: [item], event: event, source: self)
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? .move : [] }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { row?.configuration?.feedback.clear() }
    }
}

/// A date editor is hosted only while it is open, using the existing shared
/// panel lifecycle and schedule UI rather than a hidden host on every row.
@MainActor
enum NativeTaskDatePresenter {
    static var activeSession: Session?
    static func show(in row: NSView, anchor rect: CGRect, configuration c: NativeTaskRowConfiguration, values: EnvironmentValues) {
        activeSession?.close()
        guard let owner = row.window, let task = c.workspace.task(for: c.task.id) else { return }
        let session = Session(row: row, rect: rect)
        activeSession = session
        let presenter = PopupPresentingWindow(); presenter.window = owner
        session.coordinator.presentingWindow = presenter
        session.coordinator.material = values.workfollowMaterial
        session.coordinator.popupFill = values.workfollowBackgroundTheme.popupFillOrFallback(WFColors.content, for: values.colorScheme)
        session.coordinator.root = AnyView(TaskDatePopoverV2(task: task, workspace: c.workspace) { [weak session] in session?.close() }
            .environment(\.self, values).environmentObject(c.environment).environment(\.popupPresentingWindow, presenter))
        session.coordinator.update()
    }
    @MainActor final class Session {
        typealias Adapter = AnchoredPropertyPanel<AnyView>
        let coordinator = Adapter.Coordinator()
        let anchor: Adapter.AnchorView
        init(row: NSView, rect: CGRect) {
            anchor = Adapter.AnchorView(frame: rect); row.addSubview(anchor)
            coordinator.anchor = anchor; coordinator.width = ScheduleMetrics.panelWidth
            coordinator.placement = .schedule; coordinator.focusPolicy = .panelWindow
            coordinator.presented = true; coordinator.escapeDepth = 1
            coordinator.dismiss = { [weak self] in self?.close() }
            anchor.moved = { [weak self] in if self?.anchor.window == nil { self?.close() } }
        }
        func close() {
            coordinator.presented = false; coordinator.close()
            anchor.moved = nil; anchor.removeFromSuperview()
            if NativeTaskDatePresenter.activeSession === self { NativeTaskDatePresenter.activeSession = nil }
        }
    }
}
