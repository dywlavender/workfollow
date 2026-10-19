import AppKit
import QuartzCore
import SwiftUI

/// Own the destination lifecycle so an accepted drop removes the system preview
/// at release, before the original card is updated in its destination column.
struct TaskKanbanColumnDropHost<Content: View>: NSViewRepresentable {
    let workspace: TaskWorkspaceModel
    let target: TaskKanbanCreationTarget?
    let allowsMove: Bool
    var columnTaskIDs: [UUID] = []
    var allowsReorder = false
    let onTargeted: (Bool) -> Void
    @ViewBuilder let content: () -> Content

    final class Coordinator {
        weak var view: TaskKanbanColumnDropView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TaskKanbanColumnDropView {
        let view = TaskKanbanColumnDropView(rootView: root(context))
        view.registerForDraggedTypes([.string])
        context.coordinator.view = view
        configure(view)
        return view
    }

    func updateNSView(_ view: TaskKanbanColumnDropView, context: Context) {
        configure(view)
        view.rootView = root(context)
    }

    private func root(_ context: Context) -> AnyView {
        AnyView(content().environment(\.self, context.environment)
            .coordinateSpace(name: "kanban-column")
            .onPreferenceChange(TaskKanbanColumnLayoutKey.self) { layout in
                context.coordinator.view?.dropLayout = layout
            })
    }

    private func configure(_ view: TaskKanbanColumnDropView) {
        view.workspace = workspace
        view.target = target
        view.allowsMove = allowsMove
        view.columnTaskIDs = columnTaskIDs
        view.allowsReorder = allowsReorder
        view.onTargeted = onTargeted
    }
}

final class TaskKanbanColumnDropView: NSView {
    private let hostingView: NSHostingView<AnyView>
    var rootView: AnyView {
        get { hostingView.rootView }
        set { hostingView.rootView = newValue }
    }
    override var isFlipped: Bool { true }
    var workspace: TaskWorkspaceModel?
    var target: TaskKanbanCreationTarget?
    var allowsMove = false
    var columnTaskIDs: [UUID] = []
    var allowsReorder = false
    var dropLayout = TaskKanbanColumnLayout()
    var onTargeted: (Bool) -> Void = { _ in }
    private(set) var insertion: TaskKanbanInsertion?
    private var preparedInsertion: TaskKanbanInsertion?
    private var insertionMarker: TaskKanbanInsertionMarker?

    init(rootView: AnyView) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        hostingView.sizingOptions = []
        hostingView.safeAreaRegions = []
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = operation(for: sender)
        updateFeedback(sender, operation: operation)
        return operation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = operation(for: sender)
        if !operation.isEmpty, let event = NSApp.currentEvent {
            let point = convert(sender.draggingLocation, from: nil)
            _ = hitTest(point)?.enclosingScrollView?.autoscroll(with: event)
        }
        updateFeedback(sender, operation: operation)
        return operation
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { clearFeedback() }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !operation(for: sender).isEmpty else { return false }
        preparedInsertion = resolvedInsertion(for: sender)
        // AppKit reads this flag between prepare and perform. Leaving it enabled
        // slides the ghost into the newly inserted card and makes it linger.
        sender.animatesToDestination = false
        clearFeedback()
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let position = preparedInsertion ?? resolvedInsertion(for: sender)
        preparedInsertion = nil
        clearFeedback()
        guard let id = taskID(for: sender), let workspace else { return false }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            _ = workspace.applyKanbanDrop(id, to: target,
                insertion: position?.placement, columnTaskIDs: columnTaskIDs)
        }
        // A release in the same column is still an accepted drop. Reporting it
        // as a failure would play the system return animation for a valid no-op.
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        preparedInsertion = nil
        clearFeedback()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        preparedInsertion = nil
        clearFeedback()
    }

    private func updateFeedback(_ sender: NSDraggingInfo, operation: NSDragOperation) {
        onTargeted(!operation.isEmpty)
        insertion = operation.isEmpty ? nil : resolvedInsertion(for: sender)
        guard let insertion else { insertionMarker?.update(frame: nil); return }
        let marker: TaskKanbanInsertionMarker
        if let insertionMarker {
            marker = insertionMarker
        } else {
            marker = TaskKanbanInsertionMarker(frame: .zero)
            addSubview(marker, positioned: .above, relativeTo: nil)
            insertionMarker = marker
        }
        let height: CGFloat = 2
        let leading: CGFloat
        if let id = taskID(for: sender), workspace?.task(for: id)?.parentID != nil {
            leading = WFSpace.xs + 32
        } else {
            leading = WFSpace.xs
        }
        marker.update(frame: CGRect(x: leading,
            y: isFlipped ? insertion.y - height / 2 : bounds.height - insertion.y - height / 2,
            width: max(0, bounds.width - leading - WFSpace.xs), height: height))
    }

    private func clearFeedback() {
        onTargeted(false)
        insertion = nil
        insertionMarker?.update(frame: nil)
    }

    private func resolvedInsertion(for sender: NSDraggingInfo) -> TaskKanbanInsertion? {
        guard allowsReorder, let id = taskID(for: sender), let workspace,
              let source = workspace.task(for: id), !source.isClosed else { return nil }
        let siblings = columnTaskIDs.filter { candidate in
            guard candidate != id, let task = workspace.task(for: candidate) else { return false }
            return task.parentID == source.parentID && !task.isClosed
        }
        let point = convert(sender.draggingLocation, from: nil)
        let y = isFlipped ? point.y : bounds.height - point.y
        return .resolve(at: y, orderedIDs: siblings,
            frames: source.parentID == nil ? dropLayout.cards : dropLayout.rows,
            viewport: dropLayout.viewport)
    }

    private func operation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard taskID(for: sender) != nil else { return [] }
        if sender.draggingSourceOperationMask.contains(.move) { return .move }
        // Older SwiftUI String sources advertise copy; the shared domain action
        // still moves the existing task, just as the sidebar and calendar do.
        return sender.draggingSourceOperationMask.contains(.copy) ? .copy : []
    }

    private func taskID(for sender: NSDraggingInfo) -> UUID? {
        guard allowsMove, let workspace,
              sender.draggingPasteboard.pasteboardItems?.count == 1,
              let payload = sender.draggingPasteboard.string(forType: .string),
              let id = TaskSectionDropTarget.taskID(for: payload),
              workspace.canAcceptKanbanDrop(id, to: target,
                                           columnTaskIDs: columnTaskIDs) else { return nil }
        return id
    }
}

private final class TaskKanbanInsertionMarker: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(WFColors.accent).cgColor
        layer?.cornerRadius = 1
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(frame: CGRect?) {
        // Gap feedback follows the current drag event. Inheriting a surrounding
        // view animation makes the line slide behind the pointer between gaps.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let frame { self.frame = frame }
            isHidden = frame == nil
            layer?.removeAllAnimations()
            CATransaction.commit()
        }
    }
}

extension TaskListGroup {
    /// Only columns with a definite writable attribute accept a move. A heading
    /// such as "today" in creation-date grouping does not change the schedule.
    var kanbanDropTarget: TaskKanbanCreationTarget? {
        guard let creationTarget, creationTarget != .currentContext else { return nil }
        return creationTarget
    }
}

@MainActor
extension TaskWorkspaceModel {
    /// Acceptance includes same-column drops, which do not create undo history.
    func canAcceptKanbanTask(_ id: UUID, to target: TaskKanbanCreationTarget) -> Bool {
        guard let task = task(for: id), task.deletedAt == nil, task.skippedAt == nil,
              !task.isConverted, !isListArchived(task.list.name) else { return false }
        switch target {
        case .currentContext:
            return false
        case .schedule, .priority, .tag:
            return true
        case .list(let name):
            return task.parentID == nil && availableListNames.contains(name)
        case .section(let list, let sectionID):
            return task.parentID == nil && availableListNames.contains(list)
                && (sectionID == nil || listSections(forList: list).contains { $0.id == sectionID })
        }
    }

    /// Route column changes through the shared actions so persistence, task
    /// links, descendants and undo retain the same task identities.
    @discardableResult
    func moveKanbanTask(_ id: UUID, to target: TaskKanbanCreationTarget) -> Bool {
        guard canAcceptKanbanTask(id, to: target), let task = task(for: id) else { return false }
        switch target {
        case .currentContext:
            return false
        case .schedule(let day):
            guard let day else {
                guard task.schedule.dueAt != nil else { return false }
                var schedule = task.schedule
                schedule.dueAt = nil
                schedule.dueEndAt = nil
                schedule.hasTime = false
                saveTiming(id, schedule: schedule, reminder: nil, frequency: .never,
                           recurrenceRule: nil, reminderOffsets: [])
                return true
            }
            if let old = task.schedule.dueAt, calendar.isDate(old, inSameDayAs: day) { return false }
            let start = task.schedule.dueAt.map {
                TaskDateDraft.movingDay($0, to: day, calendar: calendar)
            } ?? calendar.startOfDay(for: day)
            return moveSchedule(id, to: start).taskID != nil
        case .priority(let priority):
            guard task.priority != priority else { return false }
            return setPriority(id, priority).taskID != nil
        case .list(let name):
            guard task.list.name != name else { return false }
            return moveToList(id, TaskList(name: name)).taskID != nil
        case .tag(let name):
            guard task.tags.first != name else { return false }
            let tags = name.map { tag in
                [tag] + task.tags.dropFirst().filter { $0 != tag }
            } ?? []
            setTags(id, tags)
            return self.task(for: id)?.tags != task.tags
        case .section(let list, let sectionID):
            guard task.list.name != list || task.sectionID != sectionID else { return false }
            return moveToList(id, TaskList(name: list), sectionID: sectionID).taskID != nil
        }
    }
}
