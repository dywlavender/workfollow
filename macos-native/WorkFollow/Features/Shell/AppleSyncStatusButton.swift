import EventKit
import SwiftUI

struct AppleSyncStatusButton: View {
    @ObservedObject var integration: RemindersSyncCoordinator
    let onRetry: () -> Void
    let onOpenSettings: () -> Void
    @State private var presented = false

    private var status: AppleTaskSyncStatus { integration.presentationStatus }

    var body: some View {
        Button { presented.toggle() } label: {
            Image(systemName: status.issueCount > 0 ? "icloud.slash" : "icloud")
                .font(.system(size: 17))
                .foregroundStyle(status.issueCount > 0 ? WFColors.danger : WFColors.secondaryText)
                .frame(width: RailMetrics.hitSize, height: RailMetrics.hitSize)
                .overlay(alignment: .topTrailing) {
                    if status.issueCount > 0 {
                        Text(status.issueCount > 9 ? "9+" : "\(status.issueCount)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(3).background(WFColors.danger, in: Circle())
                    }
                }
        }
        .buttonStyle(.plain)
        .help("Apple 同步：" + status.title)
        .accessibilityLabel("Apple 同步：" + status.title)
        // Open inward from the rail; keep the actual icon as the anchor.
        .background {
            AnchoredPropertyPanel(isPresented: $presented, width: PopupMetrics.syncStatusWidth,
                                  placement: .submenu,
                                  focusPolicy: .preservePresenter, title: "Apple 同步状态") {
                panelContent
            }
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(status.title).font(.headline)
            if status == .syncing || status == .connecting {
                ProgressView().controlSize(.small)
            }
            if let date = integration.lastSyncAt {
                Text("最近核对：" + date.formatted(.dateTime.month().day().hour().minute().locale(.appDate)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = integration.message {
                Text(message).font(.callout).foregroundStyle(WFColors.danger)
            }
            if !integration.conflicts.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(integration.conflicts) { conflict in
                            AppleSyncConflictView(conflict: conflict) {
                                integration.resolve(conflict, useReminder: $0)
                            }
                        }
                    }
                    .compactScrollbars()
                }.frame(maxHeight: 230)
            }
            Text("“已写入”仅表示 Mac 本地写入成功；iPhone 接收由 iCloud 完成。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if integration.store.snapshot.enabled && integration.authorization == .fullAccess {
                    Button("重试同步") {
                        _Concurrency.Task { await integration.connect(); onRetry() }
                    }.disabled(integration.syncing || integration.connecting)
                }
                Spacer()
                Button("Apple 同步设置…") {
                    presented = false
                    onOpenSettings()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { integration.refreshAccess() }
    }
}

struct AppleSyncConflictView: View {
    let conflict: RemindersSyncConflict
    let onResolve: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(conflict.title).font(.headline)
            Text("WorkFollow：" + summary(conflict.task))
            Text("提醒事项：" + summary(conflict.reminder))
            HStack {
                Button("采用提醒事项修改") { onResolve(true) }
                Button("保留 WorkFollow 修改") { onResolve(false) }
            }
        }.font(.caption)
    }

    private func summary(_ fields: ReminderTaskFields) -> String {
        var value = fields.title + (fields.completed ? " · 已完成" : " · 未完成")
        if let due = fields.due {
            value += " · " + due.formatted(date: .abbreviated, time: fields.hasTime ? .shortened : .omitted)
        }
        value += " · " + fields.priority.title
        if let alarm = fields.alarms.first {
            value += " · 提醒 " + alarm.formatted(date: .abbreviated, time: .shortened)
        }
        return value
    }
}
