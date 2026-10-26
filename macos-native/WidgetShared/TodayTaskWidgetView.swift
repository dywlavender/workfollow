import AppIntents
import SwiftUI
import WidgetKit

struct TodayTaskWidgetView: View {
    let snapshot: TaskWidgetSnapshot?
    let date: Date
    @Environment(\.colorScheme) private var colorScheme
    private var accent: Color {
        colorScheme == .dark
            ? Color(.sRGB, red: 88.0 / 255, green: 138.0 / 255, blue: 251.0 / 255, opacity: 1)
            : Color(.sRGB, red: 65.0 / 255, green: 108.0 / 255, blue: 250.0 / 255, opacity: 1)
    }
    private var day: TaskWidgetDay { (snapshot ?? .empty).today(at: date) }
    private let limit = 4
    private var countdowns: [TaskWidgetCountdownItem] { Array(day.countdowns.prefix(limit)) }
    private var tasks: [TaskWidgetItem] { Array(day.remaining.prefix(max(0, limit - countdowns.count))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if snapshot == nil {
                emptyState(symbol: "checklist", title: "把今天安排好", detail: "打开 WorkFollow 查看任务")
            } else if day.entryCount == 0 {
                emptyState(symbol: "checkmark.circle", title: day.completedCount > 0 ? "今天的任务已完成" : "今天没有待办",
                           detail: day.completedCount > 0 ? "已完成 \(day.completedCount) 项" : "添加任务，轻松开始")
            } else {
                // The reference uses four roomy rows. Keep the same four entries
                // on smaller system content areas without clipping the last row.
                ViewThatFits(in: .vertical) {
                    rows(height: 29).fixedSize(horizontal: false, vertical: true)
                    rows(height: 27).fixedSize(horizontal: false, vertical: true)
                    rows(height: 25).fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 6, trailing: 14))
        .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
        .widgetURL(TaskWidgetLink.today)
        .containerBackground(.background, for: .widget)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Link(destination: TaskWidgetLink.today) {
                HStack(spacing: 8) {
                    Text("今天").font(.system(size: 15, weight: .semibold))
                    if snapshot != nil, day.entryCount > 0 {
                        Text(day.entryCount, format: .number)
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(accent.opacity(0.7))
                    }
                }
                .foregroundStyle(accent)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }.accessibilityLabel("今天，共 \(day.entryCount) 项")
            Spacer(minLength: 2)
            Button(intent: OpenWidgetQuickAddIntent()) {
                Image(systemName: "plus").font(.system(size: 17, weight: .regular))
                    .foregroundStyle(accent).frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("添加任务")
            .accessibilityHint("打开快速新增，默认安排在今天")
        }.frame(height: 24)
    }

    private func rows(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(countdowns) { countdownRow($0, height: height) }
            ForEach(tasks) { taskRow($0, height: height) }
        }
    }

    private func taskRow(_ item: TaskWidgetItem, height: CGFloat) -> some View {
        HStack(spacing: 3) {
            Button(intent: CompleteWidgetTaskIntent(item: item)) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(priorityColor(item.priority), lineWidth: 1)
                    .frame(width: 14, height: 14)
                    .frame(width: 24, height: height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("完成：" + item.title)
            .accessibilityHint("直接完成任务")
            Link(destination: item.url) {
                HStack(spacing: 6) {
                    Text(item.title).font(.system(size: 13, weight: .semibold))
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    taskDate(item)
                }.frame(height: height).contentShape(Rectangle())
            }.accessibilityHint("打开任务详情")
        }
        // Extend the hit area leftward while aligning the visible checkbox with
        // the heading; the larger countdown badge occupies this same slot.
        .padding(.leading, -4)
        .invalidatableContent()
    }

    private func taskDate(_ item: TaskWidgetItem) -> some View {
        Group {
            if let due = item.dueAt ?? item.deadlineAt {
                if item.isOverdue(on: date, calendar: .current) {
                    Text(verbatim: "\(Calendar.current.component(.month, from: due))月\(Calendar.current.component(.day, from: due))日")
                        .foregroundStyle(.red)
                } else if item.hasTime {
                    Text(due, style: .time).foregroundStyle(accent)
                } else {
                    Text("今天").foregroundStyle(accent)
                }
            }
        }.font(.system(size: 12)).fixedSize()
    }

    private func countdownRow(_ item: TaskWidgetCountdownItem, height: CGFloat) -> some View {
        Link(destination: TaskWidgetLink.countdowns) {
            HStack(spacing: 3) {
                Image(systemName: item.symbol).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color(.sRGB, red: 161.0 / 255, green: 217.0 / 255, blue: 1, opacity: 1), in: Circle())
                    .frame(width: 24, height: height)
                Text(item.title).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(item.relativeLabel).font(.system(size: 12)).foregroundStyle(accent).fixedSize()
            }.frame(height: height).padding(.leading, -4).contentShape(Rectangle())
        }
        .accessibilityLabel("\(item.title)，\(item.relativeLabel)，倒数纪念日")
        .accessibilityHint("打开倒数纪念日")
    }

    private func priorityColor(_ value: Int) -> Color {
        switch value {
        case 3: .red
        case 2: .orange
        case 1: accent
        default: .secondary.opacity(0.65)
        }
    }

    private func emptyState(symbol: String, title: String, detail: String) -> some View {
        let label = VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 20, weight: .light)).foregroundStyle(accent)
            Text(title).font(.system(size: 12, weight: .medium))
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        return Group {
            if snapshot == nil {
                Link(destination: TaskWidgetLink.today) { label }
            } else {
                Button(intent: OpenWidgetQuickAddIntent()) { label }.buttonStyle(.plain)
            }
        }
    }
}
