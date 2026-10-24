import EventKit
import SwiftUI
import UserNotifications

struct TaskReminderDeliveryPresentation: Equatable {
    let title: String
    let detail: String
    let needsAttention: Bool

    static func make(usesApple: Bool, appleEnabled: Bool, syncStatus: String,
                     nativeEnabled: Bool, nativeAuthorized: Bool) -> Self {
        if usesApple {
            return .init(title: "Apple 提醒事项", detail: "由 Apple 提醒事项执行到点提醒，WorkFollow 不重复响铃。已写入 Mac；iPhone 接收由 iCloud 完成。", needsAttention: false)
        }
        let local = nativeEnabled && nativeAuthorized
        let syncNeedsAction = appleEnabled && ["授权", "待处理", "待重试", "已移除", "暂停"].contains { syncStatus.contains($0) }
        let reason = local ? "由这台 Mac 的通知提醒。" : "本机通知未开启，当前无法由 WorkFollow 发送到点提醒。"
        return .init(title: local ? "本机通知" : "提醒待处理",
            detail: reason + (appleEnabled ? " Apple 同步：" + syncStatus + "。" : ""),
            needsAttention: !local || syncNeedsAction)
    }
}

struct TaskReminderSourceView: View {
    let task: Task
    @ObservedObject var sync: RemindersSyncCoordinator
    @ObservedObject var local: NativeReminderService
    let onRetry: () -> Void
    let onSettings: (SettingsSection) -> Void
    @State private var presented = false
    private var value: TaskReminderDeliveryPresentation {
        .make(usesApple: sync.handlesAlerts(for: task), appleEnabled: sync.store.snapshot.enabled,
            syncStatus: sync.status(for: task), nativeEnabled: local.state.snapshot.preferences.enabled,
            nativeAuthorized: local.authorization == .authorized || local.authorization == .provisional)
    }
    private var taskConflicts: [RemindersSyncConflict] {
        let references = Set(sync.store.snapshot.bindings.filter { RemindersIntegrationStore.matches($0, task) }.map(\.id))
        return sync.conflicts.filter { references.contains($0.id) }
    }
    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 4) {
                if value.needsAttention { Image(systemName: "exclamationmark.circle") }
                Text(value.title)
            }.font(WFType.supporting).lineLimit(1)
                .foregroundStyle(value.needsAttention ? WFColors.danger : WFColors.secondaryText)
        }.buttonStyle(.plain).help("查看这条任务的提醒来源")
        .background(AnchoredPropertyPanel(isPresented: $presented, width: PopupMetrics.syncStatusWidth,
            focusPolicy: .preservePresenter, title: "提醒来源") {
            VStack(alignment: .leading, spacing: 12) {
                Text(value.title).font(WFType.section)
                Text(value.detail).font(WFType.supporting).fixedSize(horizontal: false, vertical: true)
                ForEach(taskConflicts) { conflict in
                    AppleSyncConflictView(conflict: conflict) { sync.resolve(conflict, useReminder: $0) }
                }
                HStack {
                    if sync.store.snapshot.enabled {
                        if sync.authorization != .fullAccess {
                            Button("允许提醒事项访问") {
                                _Concurrency.Task { await sync.connect(); onRetry() }
                            }.disabled(sync.connecting)
                        } else if sync.status(for: task).contains("已移除") {
                            Button("重新关联") { sync.reconnect(task); onRetry() }
                        } else {
                            Button("重试同步", action: onRetry).disabled(sync.syncing || sync.connecting)
                        }
                    }
                    Spacer()
                    Button("查看设置") {
                        presented = false
                        onSettings(sync.store.snapshot.enabled ? .appleSync : .localNotifications)
                    }
                }
            }.padding(PopupMetrics.formInset)
        })
    }
}
