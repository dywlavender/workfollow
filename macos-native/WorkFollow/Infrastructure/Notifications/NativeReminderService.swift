import UserNotifications
import Combine

/// Pure mapping from a task to its notification fire dates: the legacy absolute
/// `reminderAt`, or one date per configured offset (0 = on time, negative =
/// early; all-day tasks anchor to 09:00 of the due day, matching the schedule
/// panel's all-day reminder hint).
enum ReminderSchedule {
    static let allDayAnchorHour = 9

    /// The moment offsets anchor to: the due clock, or 09:00 for all-day tasks.
    static func reminderBase(for task: Task, calendar: Calendar) -> Date? {
        guard let due = task.schedule.dueAt else { return nil }
        guard task.schedule.hasTime else {
            return calendar.date(bySettingHour: allDayAnchorHour, minute: 0, second: 0,
                                 of: calendar.startOfDay(for: due))
        }
        return due
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
    /// （`allDayAnchorHour`），也与编辑器「提醒」下拉里挂着的 `09:00` 一致。
    static func fireDates(for event: CountdownEvent, calendar: Calendar, now: Date) -> [Date] {
        guard event.isActive else { return [] }
        let offsets = event.reminderOffsets
        guard !offsets.isEmpty else { return [] }
        let day = CountdownEvent.occurrence(of: event.rule, onOrAfter: now, calendar: calendar)
        guard let anchor = calendar.date(bySettingHour: allDayAnchorHour, minute: 0, second: 0,
                                         of: calendar.startOfDay(for: day)) else { return [] }
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
final class NativeReminderService: ObservableObject {
    @Published private(set) var message: String?

    /// 倒计时记录的通知来源，由 `AppEnvironment` 装配时注入。
    ///
    /// 用 `weak`：这个服务比倒计时 Store 建得早，强持有会连出一条没必要的
    /// 所有权链（服务 → Store → 界面），而服务本身不需要拥有它。
    weak var countdownStore: CountdownStore?

    private var pendingWork: _Concurrency.Task<Void, Never>?
    private var signature: [ReminderSignature]?
    private let clock: () -> Date
    private let calendar: Calendar

    init(clock: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.clock = clock
        self.calendar = calendar
    }

    // Permission is requested only by the user's explicit enable button.
    func enable(for tasks: [Task]) {
        _Concurrency.Task {
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                message = allowed ? nil : "请在系统设置中允许 WorkFollow Native 通知。"
                if allowed { reconcile(tasks, force: true) }
            } catch { message = error.localizedDescription }
        }
    }

    /// 重排全部通知：任务 + 倒计时记录。
    ///
    /// 倒计时记录从 `countdownStore` 现取，而不是让调用方传进来——调用点分布在
    /// 任务侧（检查器里的授权按钮、工作区 revision 订阅），把它们都改成同时传
    /// 两类记录，等于把「倒计时也有提醒」这件事散到几个不相干的界面里。
    func reconcile(_ tasks: [Task], force: Bool = false) {
        let countdowns = countdownStore?.events ?? []
        let next = ReminderSignature.values(tasks, countdowns: countdowns,
                                            calendar: calendar, now: clock())
        guard force || signature != next else { return }
        signature = next
        pendingWork?.cancel()
        pendingWork = _Concurrency.Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard !_Concurrency.Task.isCancelled else { return }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let pending = await center.pendingNotificationRequests()
            guard !_Concurrency.Task.isCancelled else { return }
            // 只清我们自己排的两种前缀；其他来源（比如专注计时）的通知不动。
            let prefixes = [ReminderSignature.Source.task.identifierPrefix,
                            ReminderSignature.Source.countdown.identifierPrefix]
            center.removePendingNotificationRequests(
                withIdentifiers: pending
                    .filter { request in prefixes.contains { request.identifier.hasPrefix($0) } }
                    .map(\.identifier))
            for task in tasks where task.deletedAt == nil && task.skippedAt == nil && !task.isClosed {
                guard !_Concurrency.Task.isCancelled else { return }
                let dates = ReminderSchedule.fireDates(for: task, calendar: calendar)
                for (index, date) in dates.enumerated() where date > clock() {
                    guard !_Concurrency.Task.isCancelled else { return }
                    await add(center, title: task.title.isEmpty ? "任务提醒" : task.title,
                              body: task.list.name, date: date,
                              source: .task, id: task.id, index: index, count: dates.count)
                }
            }
            for event in countdowns {
                guard !_Concurrency.Task.isCancelled else { return }
                let dates = ReminderSchedule.fireDates(for: event, calendar: calendar, now: clock())
                for (index, date) in dates.enumerated() where date > clock() {
                    guard !_Concurrency.Task.isCancelled else { return }
                    await add(center, title: event.displayName, body: event.kind.title,
                              date: date, source: .countdown, id: event.id,
                              index: index, count: dates.count)
                }
            }
        }
    }

    /// 排一条通知。
    ///
    /// 单条偏移量时标识符**不带序号**（`task.<uuid>`），与加偏移量之前的旧版本
    /// 保持一致，升级上来才不会出现新旧两条重复通知。
    private func add(_ center: UNUserNotificationCenter, title: String, body: String,
                     date: Date, source: ReminderSignature.Source, id: UUID,
                     index: Int, count: Int) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date), repeats: false)
        let identifier = count > 1
            ? "\(source.rawValue).\(id.uuidString)#\(index)"
            : "\(source.rawValue).\(id.uuidString)"
        do { try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)) }
        catch { message = error.localizedDescription }
    }
}
