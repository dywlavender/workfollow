import AppIntents
import SwiftUI
import WidgetKit

struct TodayTaskWidgetView: View {
    let snapshot: TaskWidgetSnapshot?
    let date: Date
    @Environment(\.colorScheme) private var colorScheme
    private var accent: Color {
        colorScheme == .dark ? Color(red: 0.65, green: 0.63, blue: 1) : Color(red: 0.35, green: 0.32, blue: 1)
    }
    private var day: TaskWidgetDay { (snapshot ?? .empty).today(at: date) }
    private let limit = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Link(destination: TaskWidgetLink.today) {
                    HStack(spacing: 5) {
                        Text("今天").font(.system(size: 15, weight: .semibold))
                        Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 2)
                Link(destination: TaskWidgetLink.quickAdd) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent).frame(width: 20, height: 20)
                        .background(accent.opacity(0.09), in: Circle())
                }.accessibilityLabel("添加任务")
            }
            if snapshot == nil {
                emptyState(symbol: "checklist", title: "把今天安排好", detail: "打开 WorkFollow 查看任务")
            } else if day.remaining.isEmpty {
                emptyState(symbol: "checkmark.circle", title: day.completedCount > 0 ? "今天的任务已完成" : "今天没有待办",
                           detail: day.completedCount > 0 ? "已完成 \(day.completedCount) 项" : "添加任务，轻松开始")
            } else {
                VStack(spacing: 3) {
                    ForEach(Array(day.remaining.prefix(limit))) { item in row(item) }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 5) {
                    Text("已完成 \(day.completedCount)").foregroundStyle(.secondary)
                    if day.overdueCount > 0 { Text("· 逾期 \(day.overdueCount)").foregroundStyle(.orange) }
                    if day.remaining.count > limit { Text("· 待办 \(day.remaining.count)").foregroundStyle(.secondary) }
                    Spacer(minLength: 2)
                    Link(destination: TaskWidgetLink.weekPlan) {
                        HStack(spacing: 3) {
                            Text("本周剩余 \(day.weekRemainingCount)")
                            Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                        }.foregroundStyle(accent)
                    }.accessibilityLabel("本周剩余 \(day.weekRemainingCount) 项，查看本周计划")
            }.font(.system(size: 10))
        }
        .foregroundStyle(.primary)
        .widgetURL(TaskWidgetLink.today)
        .containerBackground(.background, for: .widget)
    }

    private func row(_ item: TaskWidgetItem) -> some View {
        HStack(spacing: 7) {
            Button(intent: CompleteWidgetTaskIntent(item: item)) {
                Image(systemName: "circle").font(.system(size: 17, weight: .light))
                    .foregroundStyle(priorityColor(item.priority)).frame(width: 20, height: 20)
            }.buttonStyle(.plain).accessibilityLabel("完成：" + item.title)
            Link(destination: item.url) {
                HStack(spacing: 6) {
                    Text(item.title).font(.system(size: 12)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let due = item.dueAt, item.hasTime {
                        Text(due, style: .time).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.frame(minHeight: 20).contentShape(Rectangle())
            }
        }.invalidatableContent()
    }
    private func priorityColor(_ value: Int) -> Color {
        switch value {
        case 3: .red
        case 2: .orange
        case 1: accent
        default: .secondary
        }
    }
    private func emptyState(symbol: String, title: String, detail: String) -> some View {
        Link(destination: snapshot == nil ? TaskWidgetLink.today : TaskWidgetLink.quickAdd) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: symbol).font(.system(size: 20, weight: .light)).foregroundStyle(accent)
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
