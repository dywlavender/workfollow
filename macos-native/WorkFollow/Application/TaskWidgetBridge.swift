import AppKit
import Combine
import WidgetKit

@MainActor
final class TaskWidgetBridge {
    private let channel: TaskWidgetChannel
    private let workspace: TaskWorkspaceModel
    private let countdownStore: CountdownStore?
    private let canProcess: () -> Bool
    private let flush: (@escaping (Error?) -> Void) -> Void
    private let reload: () -> Void
    private var subscriptions = Set<AnyCancellable>()
    private var observer: NSObjectProtocol?
    private var publishing: DispatchWorkItem?
    private var processing = false
    private var lastItems: [TaskWidgetItem]?
    private var lastCountdowns: [TaskWidgetCountdownItem]?

    init(channel: TaskWidgetChannel, workspace: TaskWorkspaceModel,
         countdowns: CountdownStore? = nil,
         canProcess: @escaping () -> Bool,
         flush: @escaping (@escaping (Error?) -> Void) -> Void,
         reload: @escaping () -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: TaskWidgetChannel.kind) }) {
        self.channel = channel; self.workspace = workspace; self.canProcess = canProcess
        countdownStore = countdowns
        self.flush = flush; self.reload = reload
        workspace.taskChanges.sink { [weak self] _ in self?.schedulePublish() }.store(in: &subscriptions)
        workspace.listArchiveChanges.sink { [weak self] _ in self?.schedulePublish() }.store(in: &subscriptions)
        workspace.listSettingsChanges.sink { [weak self] _ in self?.schedulePublish() }.store(in: &subscriptions)
        if let countdowns {
            countdowns.$events.dropFirst().sink { [weak self] _ in self?.schedulePublish() }.store(in: &subscriptions)
            countdowns.$dateRevision.dropFirst().sink { [weak self] _ in self?.schedulePublish() }.store(in: &subscriptions)
        }
        observer = DistributedNotificationCenter.default().addObserver(forName: Notification.Name(TaskWidgetChannel.notification),
            object: nil, queue: .main) { [weak self] _ in
                _Concurrency.Task { @MainActor in await self?.processPending() }
            }
        publish()
        _Concurrency.Task { @MainActor [weak self] in await self?.processPending() }
    }

    deinit {
        publishing?.cancel()
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    private func schedulePublish() {
        publishing?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.publish() }
        publishing = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    @discardableResult
    func publish() -> Bool {
        guard canProcess() else { return false }
        let items = Self.items(workspace.tasksForSmartWidgets)
        let now = workspace.clock()
        let countdowns = Self.countdownItems(countdownStore?.events ?? [], now: now, calendar: workspace.calendar)
        guard items != lastItems || countdowns != lastCountdowns else { return true }
        do {
            try channel.publish(TaskWidgetSnapshot(updatedAt: now, tasks: items, countdowns: countdowns))
            lastItems = items
            lastCountdowns = countdowns
            reload()
            return true
        } catch { return false }
    }

    static func items(_ tasks: [Task]) -> [TaskWidgetItem] {
        tasks.filter { $0.deletedAt == nil && $0.skippedAt == nil && !$0.isAbandoned && !$0.isConverted }.map {
            TaskWidgetItem(id: $0.id, parentID: $0.parentID, title: $0.title.isEmpty ? "无标题" : $0.title,
                listName: $0.list.name, priority: $0.priority.rawValue, dueAt: $0.schedule.dueAt,
                dueEndAt: $0.schedule.dueEndAt, deadlineAt: $0.schedule.deadlineAt, hasTime: $0.schedule.hasTime,
                completedAt: $0.completedAt, isCompleted: $0.status == .completed,
                weekKey: $0.weeklyPlanning?.currentWeek, updatedAt: $0.updatedAt)
        }
    }

    static func countdownItems(_ events: [CountdownEvent], now: Date,
                               calendar: Calendar) -> [TaskWidgetCountdownItem] {
        let today = calendar.startOfDay(for: now)
        return (0...7).flatMap { offset -> [TaskWidgetCountdownItem] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return [] }
            return CountdownSmartListProjection.section(events: events, now: day, calendar: calendar).entries.map { entry in
                return TaskWidgetCountdownItem(id: entry.id, title: entry.name, symbol: entry.symbol,
                    displayDate: day, relativeLabel: entry.relativeLabel)
            }
        }
    }

    /// Completion stays on the main app's existing transaction/undo/sync path.
    /// A receipt is written only after workspace persistence has finished.
    func processPending() async {
        guard !processing, canProcess() else { return }
        processing = true
        defer { processing = false }
        // The system may have created the widget container since the host's
        // first publication attempt, including while the widget was added.
        _ = publish()
        do {
            while canProcess() {
                let commands = try channel.pending()
                if commands.isEmpty { break }
                for command in commands {
                    if try channel.receipt(for: command.id) != nil {
                        // A previous acknowledgement may have been interrupted
                        // after writing the receipt but before removing the request.
                        try channel.acknowledge(command, error: try channel.receipt(for: command.id)?.error)
                        continue
                    }
                    var message: String?
                    if let task = workspace.task(for: command.taskID), task.status == .completed {
                        // Repeated delivery must not complete the next recurrence.
                    } else if let task = workspace.task(for: command.taskID),
                              task.deletedAt == nil, task.skippedAt == nil, !task.isClosed, !task.isConverted,
                              !workspace.isListArchived(task.list.name) {
                        if task.updatedAt != command.expectedUpdatedAt {
                            message = "任务已更新，请在刷新后重新勾选。"
                        } else if workspace.complete(task.id).taskID == nil {
                            message = "暂时无法完成任务，请在应用中查看。"
                        }
                    } else { message = "任务已移除或不可用。" }
                    if message == nil {
                        let failure: Error? = await withCheckedContinuation { continuation in
                            flush { continuation.resume(returning: $0) }
                        }
                        message = failure.map { "任务保存失败：" + $0.localizedDescription }
                    }
                    _ = publish()
                    try channel.acknowledge(command, error: message)
                }
            }
        } catch {
            // Leave requests on disk for the next activation; never acknowledge
            // a task change that the app has not successfully persisted.
        }
    }
}
