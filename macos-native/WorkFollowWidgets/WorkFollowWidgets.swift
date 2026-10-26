import SwiftUI
import WidgetKit

struct TodayTaskEntry: TimelineEntry {
    let date: Date
    let snapshot: TaskWidgetSnapshot?
}

struct TodayTaskProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayTaskEntry { TodayTaskEntry(date: Date(), snapshot: Self.sample) }
    func getSnapshot(in context: Context, completion: @escaping (TodayTaskEntry) -> Void) {
        completion(TodayTaskEntry(date: Date(), snapshot: context.isPreview ? Self.sample : load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayTaskEntry>) -> Void) {
        let now = Date(), calendar = Calendar.current, snapshot = load()
        let midnight = calendar.startOfDay(for: now)
        let entries = [TodayTaskEntry(date: now, snapshot: snapshot)] + (1...7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: midnight).map { TodayTaskEntry(date: $0, snapshot: snapshot) }
        }
        // Prepared day changes work while the containing app is closed.
        completion(Timeline(entries: entries, policy: .after(calendar.date(byAdding: .hour, value: 1, to: now)!)))
    }
    private func load() -> TaskWidgetSnapshot? {
        let snapshot = try? TaskWidgetChannel.shared().readSnapshot()
        if snapshot == nil {
            // Adding the widget initializes its sandbox. Ask an already-running
            // host to retry publication now that its container is available.
            DistributedNotificationCenter.default().postNotificationName(Notification.Name(TaskWidgetChannel.notification),
                object: nil, userInfo: nil, deliverImmediately: true)
        }
        return snapshot
    }
    private static var sample: TaskWidgetSnapshot {
        let now = Date()
        return TaskWidgetSnapshot(updatedAt: now, tasks: ["梳理本周重点", "准备项目评审", "整理今天的进展", "阅读与学习"].enumerated().map { index, title in
            TaskWidgetItem(id: UUID(), title: title, listName: "工作", priority: index == 0 ? 3 : 0,
                dueAt: now, hasTime: false, isCompleted: false, updatedAt: now)
        }, countdowns: [TaskWidgetCountdownItem(id: UUID(), title: "周末", symbol: "hourglass",
            displayDate: now, relativeLabel: "今天")])
    }
}

@main
struct WorkFollowWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TaskWidgetChannel.kind, provider: TodayTaskProvider()) { entry in
            TodayTaskWidgetView(snapshot: entry.snapshot, date: entry.date)
        }
        .configurationDisplayName("今日待办")
        .description("查看今天的任务和倒数日，直接勾选完成，快速新增任务。")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
