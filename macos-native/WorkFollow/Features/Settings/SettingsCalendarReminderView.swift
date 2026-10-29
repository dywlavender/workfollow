import SwiftUI
import UserNotifications

struct SettingsCalendarReminderView: View {
    @ObservedObject var reminders: NativeReminderService
    @ObservedObject var workspace: TaskWorkspaceModel
    @State private var showDiagnostics = false

    var body: some View {
        SettingsPage {
            WFFormSection {
                WFFormRow("系统通知") {
                    if notificationsAllowed {
                        Text("已开启").foregroundStyle(WFColors.secondaryText)
                    } else if reminders.authorization == .denied {
                        Button("前往系统设置") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    } else {
                        Button("允许通知") { reminders.enable(for: workspace.tasksForLocalReminders) }
                    }
                }
                WFFormToggleRow("提醒声音", isOn: Binding(get: { reminders.state.snapshot.preferences.soundEnabled },
                    set: { flag in reminders.state.updatePreferences { $0.soundEnabled = flag } }))
                WFFormRow("铃声") {
                    HStack(spacing: 10) {
                        BusinessPicker("", selection: Binding(get: { reminders.state.snapshot.preferences.bell },
                            set: { name in reminders.state.updatePreferences { $0.bell = name } }), options:
                            [BusinessChoice("Jingle", "叮"), BusinessChoice("Drip", "水滴"),
                             BusinessChoice("Knock", "敲击"), BusinessChoice("Spiral", "螺旋")])
                            .labelsHidden()
                        Button { reminders.previewSound() } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("试听铃声")
                        .hoverTip("试听铃声")
                    }.disabled(!reminders.state.snapshot.preferences.soundEnabled)
                }
                WFFormRow("默认稍后提醒", showsDivider: false) {
                    BusinessPicker("", selection: Binding(get: { reminders.state.snapshot.preferences.snoozeMinutes },
                        set: { minutes in reminders.state.updatePreferences { $0.snoozeMinutes = minutes } }), options:
                        [5, 10, 15, 30, 60].map { BusinessChoice($0, "\($0) 分钟") })
                        .labelsHidden()
                }
                if let message = reminders.message {
                    Text(message).foregroundStyle(.red).font(WFType.supporting)
                        .padding(.horizontal, WFSpace.md)
                }
            }

            if !reminders.missed.isEmpty {
                WFFormSection("错过的提醒") {
                    ForEach(Array(reminders.missed.suffix(10))) { item in
                        HStack {
                            Text(item.title).lineLimit(1)
                            Spacer()
                            Button("打开") { reminders.openReminder(item) }
                            Button("稍后提醒") { _Concurrency.Task { await reminders.handle(item, snoozeMinutes: reminders.state.snapshot.preferences.snoozeMinutes) } }
                            Button("停止") { _Concurrency.Task { await reminders.handle(item, snoozeMinutes: nil) } }
                        }
                        .font(WFType.body)
                        .padding(.horizontal, WFSpace.md)
                    }
                }
            }

            DisclosureGroup("提醒测试与详情", isExpanded: $showDiagnostics) {
                VStack(alignment: .leading, spacing: 12) {
                    Button("5 秒后测试提醒") { reminders.sendTest() }
                        .disabled(!notificationsAllowed)
                    if let end = reminders.coverageEnd {
                        Text("已安排 \(reminders.pendingCount) 条提醒，最晚至 \(end.formatted(date: .abbreviated, time: .shortened))")
                    }
                    Text("应用退出后使用系统提示音。稍后提醒不改变任务日期。")
                }
                .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                .padding(.top, 10)
            }
            .font(WFType.body).padding(.horizontal, WFSpace.md)
        }
        .onAppear { reminders.reconcile(workspace.tasksForLocalReminders, force: true) }
    }

    private var notificationsAllowed: Bool {
        reminders.authorization == .authorized || reminders.authorization == .provisional
    }
}
