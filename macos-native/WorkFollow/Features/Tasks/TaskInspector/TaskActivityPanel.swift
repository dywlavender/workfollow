import SwiftUI

struct TaskActivityPanel: View {
    let taskID: UUID
    @ObservedObject var store: TaskActivityStore
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("任务动态").font(.headline)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭任务动态")
            }
            .padding(16)
            Divider()
            let events = store.events(for: taskID)
            if events.isEmpty {
                VStack(spacing: 8) {
                    Text("暂无任务动态").foregroundStyle(WFColors.text)
                    Text("仅记录启用后的任务变更，不补造历史记录。")
                        .font(.caption).foregroundStyle(WFColors.secondaryText)
                }
                .padding(24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
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
                    }
                    .padding(16)
                }
                .frame(height: 340)
            }
        }
        .accessibilityIdentifier("task-activity-panel")
    }
}
