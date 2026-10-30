import SwiftUI

struct TaskActivityPanel: View {
    let taskID: UUID
    @ObservedObject var store: TaskActivityStore
    let onClose: () -> Void
    @StateObject private var history = TaskActivityPageModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("任务动态").font(.headline)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .hoverTip("关闭任务动态")
                    .accessibilityLabel("关闭任务动态")
            }
            .padding(16)
            Divider()
            let events = history.events
            if events.isEmpty {
                if !history.isLoading && history.error == nil {
                    VStack(spacing: 8) {
                        Text("暂无任务动态").foregroundStyle(WFColors.text)
                        Text("仅记录启用后的任务变更，不补造历史记录。")
                            .font(.caption).foregroundStyle(WFColors.secondaryText)
                    }
                    .padding(24)
                }
                TaskActivityPageControls(history: history) {
                    await history.loadMore(store: store, taskIDs: [taskID])
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(events) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title).foregroundStyle(WFColors.text)
                                if let detail = event.detail {
                                    Text(detail).font(.callout)
                                        .foregroundStyle(WFColors.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text(event.occurredAt, format: .dateTime.year().month().day().hour().minute())
                                    .font(.caption).foregroundStyle(WFColors.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        TaskActivityPageControls(history: history) {
                            await history.loadMore(store: store, taskIDs: [taskID])
                        }
                    }
                    .padding(16)
                }
                .compactScrollbars()
                .frame(height: 340)
            }
        }
        // Keep the child window geometry stable across async loading states.
        .frame(height: 396, alignment: .top)
        .accessibilityIdentifier("task-activity-panel")
        .task(id: "\(taskID)-\(store.revision)") {
            await history.reset(store: store, taskIDs: [taskID])
        }
    }
}
