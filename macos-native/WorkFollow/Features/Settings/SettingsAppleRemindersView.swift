import EventKit
import SwiftUI

struct SettingsAppleRemindersView: View {
    @ObservedObject var integration: RemindersSyncCoordinator
    @ObservedObject var calendarIntegration: CalendarSyncCoordinator
    @State private var showLegacyCleanup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WFSpace.lg) {
                WFFormSection("Apple 提醒事项") {
                    WFFormToggleRow("同步任务到 Apple 提醒事项", isOn: Binding(
                        get: { integration.store.snapshot.enabled || integration.connecting },
                        set: { enabled in
                            if enabled { _Concurrency.Task { await integration.connect() } }
                            else { integration.store.configure { $0.enabled = false } }
                        }), showsDivider: false)
                        .disabled(integration.connecting)
                    WFFormNote("自动同步所有未完成任务。在 iPhone 的“提醒事项 → WorkFollow”中查看、完成和接收到点提醒，两端修改自动同步。")
                    WFFormNote("有日期的任务可直接显示在 Apple 日历的“计划的提醒事项”中，无需另建日历日程。")
                    if integration.connecting {
                        Label("正在连接 iCloud 提醒事项…", systemImage: "arrow.triangle.2.circlepath")
                            .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                            .padding(.horizontal, WFSpace.md)
                    } else if integration.store.snapshot.enabled {
                        if integration.authorization == .fullAccess {
                            syncStatus.padding(.horizontal, WFSpace.md)
                        } else {
                            WFFormNote("需要允许提醒事项访问，才能继续同步。")
                            Button("允许访问") { _Concurrency.Task { await integration.connect() } }
                                .padding(.horizontal, WFSpace.md)
                        }
                    } else if !integration.store.snapshot.bindings.isEmpty {
                        WFFormNote("同步已暂停，已同步到提醒事项的任务仍保留。")
                    }
                    if let message = integration.message {
                        Text(message).font(WFType.supporting).foregroundStyle(.red)
                            .padding(.horizontal, WFSpace.md)
                        Button("重试连接") { _Concurrency.Task { await integration.connect() } }
                            .disabled(integration.connecting)
                            .padding(.horizontal, WFSpace.md)
                    }
                }

                WFFormSection("系统日历") {
                    WFFormToggleRow("在 WorkFollow 显示系统日程", isOn: Binding(
                        get: { calendarIntegration.store.snapshot.enabled || calendarIntegration.connecting },
                        set: { enabled in
                            if enabled { _Concurrency.Task { await calendarIntegration.connect() } }
                            else { calendarIntegration.store.configure { $0.enabled = false } }
                        }), showsDivider: false)
                        .disabled(calendarIntegration.connecting)
                    WFFormNote("查看系统日历中已有的会议和预约，日程在 Apple 日历中编辑。")
                    if calendarIntegration.store.snapshot.enabled && calendarIntegration.authorization != .fullAccess {
                        Button("允许日历访问") { _Concurrency.Task { await calendarIntegration.connect() } }
                            .disabled(calendarIntegration.connecting)
                            .padding(.horizontal, WFSpace.md)
                    }
                    if calendarIntegration.legacyCopyCount > 0 {
                        WFFormNote("旧版保留了 \(calendarIntegration.legacyCopyCount) 条任务日历关联，可清理旧副本以避免重复。")
                        Button("清理旧版任务日历副本…") { showLegacyCleanup = true }
                            .disabled(calendarIntegration.cleaningUp || calendarIntegration.authorization != .fullAccess)
                            .padding(.horizontal, WFSpace.md)
                    }
                    if calendarIntegration.removedCopyCount > 0 {
                        Button("撤销副本清理") { _Concurrency.Task { await calendarIntegration.undoLegacyCleanup() } }
                            .disabled(calendarIntegration.cleaningUp || calendarIntegration.authorization != .fullAccess)
                            .padding(.horizontal, WFSpace.md)
                    }
                    if let result = calendarIntegration.cleanupResult { WFFormNote(result) }
                    if let message = calendarIntegration.message {
                        Text(message).font(WFType.supporting).foregroundStyle(.red)
                            .padding(.horizontal, WFSpace.md)
                    }
                }

                if !integration.conflicts.isEmpty {
                    WFFormSection("需要确认的修改") {
                        ForEach(integration.conflicts) { item in
                            AppleSyncConflictView(conflict: item) { integration.resolve(item, useReminder: $0) }
                        }
                    }
                }

                WFFormNote("手机需登录同一 Apple 账户，并开启 iCloud 提醒事项及提醒事项通知。首次开启时按系统提示允许访问即可。")
            }
            .padding(WFSpace.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { integration.refreshAccess(); calendarIntegration.refreshAccess() }
        .confirmationDialog("清理旧版任务日历副本？", isPresented: $showLegacyCleanup, titleVisibility: .visible) {
            Button("清理副本", role: .destructive) { _Concurrency.Task { await calendarIntegration.cleanupLegacyCopies() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("仅移除旧版创建且未单独修改的任务日历副本，任务和提醒事项保留。清理后可以撤销。")
        }
    }

    private var syncStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            if integration.message != nil {
                Label("同步需要重试", systemImage: "exclamationmark.circle")
            } else if !integration.conflicts.isEmpty {
                Label("有修改待确认", systemImage: "exclamationmark.circle")
            } else {
                Label(integration.syncing ? "正在同步…" : "已连接 iCloud · WorkFollow",
                    systemImage: integration.syncing ? "arrow.triangle.2.circlepath" : "checkmark.circle")
            }
            if let date = integration.lastSyncAt {
                Text("最近核对：" + date.formatted(.dateTime.month().day().hour().minute().locale(.appDate)))
            }
        }.font(.caption).foregroundStyle(.secondary)
    }

}
