import UserNotifications
import AppKit
import Combine

/// Pure mapping from a task to its notification fire dates: the legacy absolute
/// `reminderAt`, or one date per configured offset (0 = on time, negative =
/// early; all-day tasks anchor to 09:00 of the due day, matching the schedule
/// panel's all-day reminder hint).
enum ReminderSchedule {

    /// The moment offsets anchor to: the due clock, or 09:00 for all-day tasks.
    /// 实现只有一处：`ScheduleSemantics.anchor`（面板预览 / 提交 / 排期共用）。
    static func reminderBase(for task: Task, calendar: Calendar) -> Date? {
        ScheduleSemantics.anchor(due: task.schedule.dueAt,
                                 hasTime: task.schedule.hasTime,
                                 calendar: calendar)
    }

    /// Ascending fire dates. Without stored offsets the legacy absolute
    /// reminder applies; offsets without a schedulable anchor produce none.
    static func fireDates(for task: Task, calendar: Calendar) -> [Date] {
        let offsets = task.reminderOffsets ?? []
        if !offsets.isEmpty, let base = reminderBase(for: task, calendar: calendar) {
            return offsets.map { base.addingTimeInterval(TimeInterval($0) * 60) }.sorted()
        }
        return task.reminderAt.map { [$0] } ?? []
    }

    /// 倒计时记录的触发时刻。
    ///
    /// **语义与任务相反，别共用上面那个。** 两边同名字段 `reminderOffsets` 单位
    /// 都是分钟，但约定相反：
    /// - 任务：相对到期时刻的偏移，**提前用负数**（`-30` = 提前半小时）；
    /// - 倒计时：**提前多少分钟，非负**，且被归一化成整天
    ///   （`CountdownEvent.normalizedReminderOffsets` 会丢掉负值和不是整天的值）。
    ///
    /// 所以这里是**减** `offset`，不是加。抄了任务那份会把「提前 3 天」排成
    /// 「推后 3 天」——而且因为偏移量本身合法，排程会安静地成功。
    ///
    /// 落点取**下一次发生日**的 09:00：与任务的全天提醒同一时刻
    /// （`ScheduleSemantics.allDayAnchorHour`），也与编辑器「提醒」下拉里挂着的 `09:00` 一致。
    static func fireDates(for event: CountdownEvent, calendar: Calendar, now: Date) -> [Date] {
        guard event.isActive else { return [] }
        let offsets = event.reminderOffsets
        guard !offsets.isEmpty else { return [] }
        let day = CountdownEvent.occurrence(of: event.rule, onOrAfter: now, calendar: calendar)
        guard let anchor = ScheduleSemantics.allDayAnchor(on: day, calendar: calendar) else { return [] }
        return offsets.map { anchor.addingTimeInterval(-TimeInterval($0) * 60) }.sorted()
    }
}

struct ReminderSignature: Equatable {
    /// 通知来源。任务与倒计时共用一套排程，但**标识符前缀必须分开**：
    /// reconcile 是「先按前缀删掉自己的、再加回来」，共用一个前缀会让后跑的那轮
    /// 把另一类刚排好的通知一起删掉，而签名比对看不出这件事（它是另一类算的）。
    enum Source: String {
        case task, countdown
        var identifierPrefix: String { "\(rawValue)." }
    }

    let id: UUID
    let source: Source
    let dates: [Date]
    let title: String
    let list: String

    static func values(_ tasks: [Task], countdowns: [CountdownEvent] = [],
                       calendar: Calendar = .current, now: Date = Date()) -> [Self] {
        let fromTasks = tasks.compactMap { task -> Self? in
            guard !task.isClosed, task.deletedAt == nil, task.skippedAt == nil else { return nil }
            let dates = ReminderSchedule.fireDates(for: task, calendar: calendar)
            guard !dates.isEmpty else { return nil }
            return Self(id: task.id, source: .task, dates: dates,
                        title: task.title, list: task.list.name)
        }
        let fromCountdowns = countdowns.compactMap { event -> Self? in
            let dates = ReminderSchedule.fireDates(for: event, calendar: calendar, now: now)
            guard !dates.isEmpty else { return nil }
            return Self(id: event.id, source: .countdown, dates: dates,
                        title: event.displayName, list: event.kind.title)
        }
        // 排序键带上来源：两类记录的 UUID 理论上不会撞，但签名是拿去比 `==` 的，
        // 顺序必须完全确定，不能依赖两段拼接的先后。
        return (fromTasks + fromCountdowns)
            .sorted { "\($0.source.rawValue).\($0.id.uuidString)"
                    < "\($1.source.rawValue).\($1.id.uuidString)" }
    }
}

@MainActor
final class NativeReminderService: ObservableObject, ModuleStoreFlushable {
    @Published private(set) var message: String?
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var pendingCount = 0
    @Published private(set) var coverageEnd: Date?
    @Published private(set) var missed: [ReminderDelivery] = []
    let state: TaskReminderStateStore
    let notifications = NotificationCoordinator()
    weak var countdownStore: CountdownStore?
    var onOpen: ((ReminderDelivery) -> Void)?
    private let client: TaskNotificationClient
    private let presenter = TaskReminderPresenter()
    private let clock: () -> Date
    private let calendar: Calendar
    private var pendingWork: _Concurrency.Task<Void, Never>?
    private var generation = 0
    private var tasks: [Task] = []
    private(set) var deliveries: [ReminderDelivery] = []
    private var timer: Timer?
    private var presentedIDs: Set<String> = []
    private var authorizationActivation: AnyCancellable?

    init(clock: @escaping () -> Date = Date.init, calendar: Calendar = .current,
         directory: URL = JSONFileStore<TaskReminderStateStore.Snapshot>.moduleDirectory,
         client: TaskNotificationClient? = nil) {
        self.clock = clock; self.calendar = calendar
        self.client = client ?? SystemTaskNotificationClient()
        state = TaskReminderStateStore(directory: directory)
        state.onChange = { [weak self] in
            guard let self else { return }
            self.reconcile(self.tasks, force: true)
            self.objectWillChange.send()
        }
        notifications.onPresent = { [weak self] value in self?.present(value, playSound: true) ?? false }
        notifications.onAction = { [weak self] value, snooze in
            guard let self else { return }
            await self.handle(value, snoozeMinutes: snooze ? self.state.snapshot.preferences.snoozeMinutes : nil)
        }
        notifications.onOpen = { [weak self] value in self?.openReminder(value) }
    }

    func install() { notifications.install() }

    func enable(for tasks: [Task]) {
        if !NSApp.isActive {
            message = "请将 WorkFollow 置于前台，系统会显示通知授权。"
            authorizationActivation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
                .first().sink { [weak self] _ in self?.beginAuthorization(for: tasks) }
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        beginAuthorization(for: tasks)
    }

    private func beginAuthorization(for tasks: [Task]) {
        authorizationActivation = nil
        _Concurrency.Task {
            do {
                let allowed = try await client.authorize()
                NativeAcceptanceInteractionTrace.record("reminder.authorization", ["allowed": allowed, "active": NSApp.isActive])
                message = allowed ? nil : "请在系统设置中允许 WorkFollow Native 通知。"
                reconcile(tasks, force: true)
            } catch {
                authorization = await client.authorization()
                message = "系统未允许通知：\(error.localizedDescription)"
                let failure = error as NSError
                NativeAcceptanceInteractionTrace.record("reminder.authorization-error", ["domain": failure.domain, "code": failure.code,
                    "active": NSApp.isActive, "authorization": authorization.rawValue])
            }
        }
    }

    /// A serial drain ensures an old asynchronous add cannot finish after the
    /// latest reconciliation and leave a stale request behind.
    func reconcile(_ tasks: [Task], force: Bool = false) {
        self.tasks = tasks
        generation += 1
        guard pendingWork == nil else { return }
        pendingWork = _Concurrency.Task {
            while true {
                let revision = generation
                await synchronize()
                if revision == generation { break }
            }
            pendingWork = nil
        }
    }

    func waitForReconciliation() async { await pendingWork?.value }

    private func synchronize() async {
        let now = clock()
        deliveries = TaskReminderPlanner.deliveries(tasks: tasks, countdowns: countdownStore?.events ?? [],
            now: now, calendar: calendar, decisions: state.snapshot.decisions)
        missed = deliveries.filter { $0.fireDate <= now && $0.fireDate > now.addingTimeInterval(-86400) }
        if let active = presenter.activeID, !deliveries.contains(where: { $0.id == active }) { presenter.stop() }
        authorization = await client.authorization()
        guard authorization == .authorized || authorization == .provisional else {
            timer?.invalidate(); timer = nil
            return
        }
        let desired = deliveries.filter { $0.fireDate > now }.prefix(256).map {
            ScheduledTaskNotification(delivery: $0, sound: state.snapshot.preferences.soundEnabled,
                                      bell: state.snapshot.preferences.bell)
        }
        let valid = Set(deliveries.map(\.id))
        let delivered = await client.delivered()
        client.removeDelivered(delivered.filter { $0.kind != .test && !valid.contains($0.id) }.map(\.id))
        let current = await client.pending()
        let ids = await client.pendingManagedIDs()
        let wanted = Set(desired.map { $0.delivery.id })
        client.removePending(ids.filter { !wanted.contains($0) })
        let previous = Dictionary(current.map { ($0.delivery.id, $0) }, uniquingKeysWith: { _, next in next })
        var failed: String?
        for value in desired where previous[value.delivery.id] != value {
            do { try await client.add(value, calendar: calendar) }
            catch { failed = error.localizedDescription }
        }
        message = failed
        let successful = await client.pending().filter { wanted.contains($0.delivery.id) }
        pendingCount = successful.count
        coverageEnd = successful.map { $0.delivery.fireDate }.max()
        schedulePresentation()
    }

    func handle(_ delivery: ReminderDelivery, snoozeMinutes: Int?) async {
        NativeAcceptanceInteractionTrace.record("reminder.action", ["kind": delivery.kind.rawValue,
            "action": snoozeMinutes == nil ? "stop" : "snooze", "minutes": snoozeMinutes ?? 0])
        // A notification from before a task was completed or rescheduled is inert.
        guard delivery.kind == .test || deliveries.contains(where: { $0.id == delivery.id }) else {
            client.removeDelivered([delivery.id]); return
        }
        presenter.stop(id: delivery.id)
        client.removeDelivered([delivery.id])
        if delivery.kind == .test {
            if let minutes = snoozeMinutes {
                var next = delivery; next.fireDate = clock().addingTimeInterval(Double(minutes) * 60)
                try? await client.add(.init(delivery: next, sound: state.snapshot.preferences.soundEnabled,
                    bell: state.snapshot.preferences.bell), calendar: calendar)
            }
            return
        }
        let until = snoozeMinutes.map { clock().addingTimeInterval(Double($0) * 60) }
        presentedIDs.remove(delivery.id)
        state.decide(delivery, snoozeUntil: until)
        let error: Error? = await withCheckedContinuation { continuation in
            state.flush { continuation.resume(returning: $0) }
        }
        if let error { message = "提醒状态保存失败：\(error.localizedDescription)" }
        await waitForReconciliation()
    }

    func openReminder(_ delivery: ReminderDelivery) {
        presenter.stop(id: delivery.id)
        client.removeDelivered([delivery.id])
        onOpen?(delivery)
    }

    @discardableResult
    private func present(_ value: ReminderDelivery, playSound: Bool) -> Bool {
        guard value.kind == .test || deliveries.contains(where: { $0.id == value.id }) else { return false }
        presentedIDs.insert(value.id)
        return presenter.show(value, preferences: state.snapshot.preferences, playSound: playSound,
            onSnooze: { [weak self] minutes in
                _Concurrency.Task { await self?.handle(value, snoozeMinutes: minutes) }
            }, onStop: { [weak self] in
                _Concurrency.Task { await self?.handle(value, snoozeMinutes: nil) }
            }, onOpen: { [weak self] in self?.openReminder(value) })
    }

    private func schedulePresentation() {
        timer?.invalidate()
        guard let next = deliveries.first(where: { $0.fireDate > clock() && !presentedIDs.contains($0.id) }) else { return }
        timer = Timer.scheduledTimer(withTimeInterval: max(0.1, next.fireDate.timeIntervalSince(clock())), repeats: false) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                guard let self else { return }
                // Background audio belongs to the system notification. Foreground
                // notification callbacks and this timer share the same presenter.
                if let current = self.deliveries.first(where: { $0.id == next.id }) {
                    _ = self.present(current, playSound: NSApp.isActive)
                }
                // Refill the bounded system queue after a delivery, even when
                // the user leaves the app running without editing any tasks.
                self.reconcile(self.tasks, force: true)
            }
        }
    }

    func sendTest() {
        _Concurrency.Task {
            let value = ReminderDelivery(id: "reminder.test.\(UUID().uuidString)", kind: .test,
                sourceID: UUID(), title: "WorkFollow 测试提醒", body: "可以试用稍后提醒和停止。",
                originalDate: clock().addingTimeInterval(5), fireDate: clock().addingTimeInterval(5))
            do { try await client.add(.init(delivery: value, sound: state.snapshot.preferences.soundEnabled,
                bell: state.snapshot.preferences.bell), calendar: calendar) }
            catch { message = error.localizedDescription }
        }
    }
    func previewSound() { ReminderAudio.sound(state.snapshot.preferences.bell)?.play() }
    func flush(_ completion: @escaping (Error?) -> Void) { state.flush(completion) }
}
