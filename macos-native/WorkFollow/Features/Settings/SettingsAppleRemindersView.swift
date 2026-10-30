import EventKit
import SwiftUI

struct SettingsAppleRemindersView: View {
    @ObservedObject var integration: RemindersSyncCoordinator
    @ObservedObject var calendarIntegration: CalendarSyncCoordinator
    @State private var showLegacyCleanup = false
    @State private var showLegacyDetails = false
    @State private var showSyncHelp = false

    var body: some View {
        SettingsPage {
            WFFormSection {
                WFFormToggleRow("同步任务到 Apple 提醒事项", isOn: Binding(
                    get: { integration.store.snapshot.enabled || integration.connecting },
                    set: { enabled in
                        if enabled { _Concurrency.Task { await integration.connect() } }
                        else { integration.store.configure { $0.enabled = false } }
                    }), showsDivider: false)
                    .disabled(integration.connecting)
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

            WFFormSection {
                WFFormToggleRow("在 WorkFollow 显示系统日程", isOn: Binding(
                    get: { calendarIntegration.store.snapshot.enabled || calendarIntegration.connecting },
                    set: { enabled in
                        if enabled { _Concurrency.Task { await calendarIntegration.connect() } }
                        else { calendarIntegration.store.configure { $0.enabled = false } }
                    }), showsDivider: false)
                    .disabled(calendarIntegration.connecting)
                if calendarIntegration.store.snapshot.enabled && calendarIntegration.authorization != .fullAccess {
                    Button("允许日历访问") { _Concurrency.Task { await calendarIntegration.connect() } }
                        .disabled(calendarIntegration.connecting)
                        .padding(.horizontal, WFSpace.md)
                }
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

            if calendarIntegration.legacyCopyCount > 0 || calendarIntegration.removedCopyCount > 0 || calendarIntegration.cleanupResult != nil {
                DisclosureGroup("旧版日历副本", isExpanded: $showLegacyDetails) {
                    VStack(alignment: .leading, spacing: 10) {
                        if calendarIntegration.legacyCopyCount > 0 {
                            Button("清理 \(calendarIntegration.legacyCopyCount) 条旧版关联…") { showLegacyCleanup = true }
                                .disabled(calendarIntegration.cleaningUp || calendarIntegration.authorization != .fullAccess)
                        }
                        if calendarIntegration.removedCopyCount > 0 {
                            Button("撤销副本清理") { _Concurrency.Task { await calendarIntegration.undoLegacyCleanup() } }
                                .disabled(calendarIntegration.cleaningUp || calendarIntegration.authorization != .fullAccess)
                        }
                        if let result = calendarIntegration.cleanupResult { Text(result).foregroundStyle(WFColors.secondaryText) }
                    }.padding(.top, 10)
                }
                .font(WFType.body).padding(.horizontal, WFSpace.md)
            }

            DisclosureGroup("iPhone 同步说明", isExpanded: $showSyncHelp) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("使用同一 Apple 账户，并开启 iCloud 提醒事项和通知。")
                    Text("任务在“提醒事项 → WorkFollow”中双向同步，有日期的任务也可显示在 Apple 日历中。")
                    Text("系统日程来自 Apple 日历，在日历中编辑。")
                }
                .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                .padding(.top, 10)
            }
            .font(WFType.body).padding(.horizontal, WFSpace.md)
        }
        .onAppear { integration.refreshAccess(); calendarIntegration.refreshAccess() }
        .workfollowAlert(
            "清理旧版任务日历副本？",
            message: "仅移除旧版创建且未单独修改的任务日历副本，任务和提醒事项保留。清理后可以撤销。",
            isPresented: $showLegacyCleanup,
            actions: [
                .cancel(),
                .destructive("清理副本") { _Concurrency.Task { await calendarIntegration.cleanupLegacyCopies() } }
            ])
    }

    private var syncStatus: some View {
        Group {
            if integration.message != nil {
                Label("同步需要重试", systemImage: "exclamationmark.circle")
            } else if !integration.conflicts.isEmpty {
                Label("有修改待确认", systemImage: "exclamationmark.circle")
            } else {
                Label(integration.syncing ? "正在同步…" : "已连接 iCloud",
                    systemImage: integration.syncing ? "arrow.triangle.2.circlepath" : "checkmark.circle")
            }
        }
        .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
        .help(integration.lastSyncAt.map { "最近同步：" + $0.formatted(.dateTime.month().day().hour().minute().locale(.appDate)) } ?? "iCloud 提醒事项")
    }

}
