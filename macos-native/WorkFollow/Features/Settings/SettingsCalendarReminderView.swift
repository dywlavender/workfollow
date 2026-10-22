import SwiftUI
import UserNotifications
import ServiceManagement

struct SettingsCalendarReminderView: View {
    @ObservedObject var reminders: NativeReminderService
    @ObservedObject var workspace: TaskWorkspaceModel
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("任务提醒") {
                HStack {
                    Text(notificationStatus)
                    Spacer()
                    Button("允许通知") { reminders.enable(for: workspace.tasksInActiveLists) }
                }
                Toggle("提醒声音", isOn: Binding(get: { reminders.state.snapshot.preferences.soundEnabled },
                    set: { flag in reminders.state.updatePreferences { $0.soundEnabled = flag } }))
                BusinessPicker("铃声", selection: Binding(get: { reminders.state.snapshot.preferences.bell },
                    set: { name in reminders.state.updatePreferences { $0.bell = name } }), options:
                    [BusinessChoice("Glass", "清脆"), BusinessChoice("Ping", "轻响"), BusinessChoice("Hero", "和弦"), BusinessChoice("Submarine", "低鸣")])
                BusinessPicker("默认稍后提醒", selection: Binding(get: { reminders.state.snapshot.preferences.snoozeMinutes },
                    set: { minutes in reminders.state.updatePreferences { $0.snoozeMinutes = minutes } }), options:
                    [5, 10, 15, 30, 60].map { BusinessChoice($0, "\($0) 分钟") })
                HStack {
                    Button("试听铃声") { reminders.previewSound() }
                    Button("5 秒后测试提醒") { reminders.sendTest() }
                        .disabled(reminders.authorization != .authorized && reminders.authorization != .provisional)
                }
                if let end = reminders.coverageEnd {
                    Text("已安排 \(reminders.pendingCount) 条提醒，最晚至 \(end.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("应用运行时可停止铃声；完全退出后使用系统短铃。稍后提醒不会改变任务日期。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("登录时启动 WorkFollow", isOn: Binding(get: { loginStatus == .enabled || loginStatus == .requiresApproval }, set: { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginStatus = SMAppService.mainApp.status; loginError = nil
                    } catch { loginError = error.localizedDescription; loginStatus = SMAppService.mainApp.status }
                }))
                if loginStatus == .requiresApproval {
                    Button("在系统设置中允许登录启动") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let loginError { Text(loginError).foregroundStyle(.red) }
                if let message = reminders.message { Text(message).foregroundStyle(.red) }
                if !reminders.missed.isEmpty {
                    Text("最近 24 小时错过的提醒").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(reminders.missed.suffix(10))) { item in
                        HStack {
                            Text(item.title).lineLimit(1)
                            Spacer()
                            Button("打开") { reminders.openReminder(item) }
                            Button("稍后提醒") { _Concurrency.Task { await reminders.handle(item, snoozeMinutes: reminders.state.snapshot.preferences.snoozeMinutes) } }
                            Button("停止") { _Concurrency.Task { await reminders.handle(item, snoozeMinutes: nil) } }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { reminders.reconcile(workspace.tasksInActiveLists, force: true) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginStatus = SMAppService.mainApp.status }
    }
    private var notificationStatus: String {
        switch reminders.authorization {
        case .authorized, .provisional: "系统通知已开启"
        case .denied: "系统通知已关闭"
        default: "尚未允许系统通知"
        }
    }
}
