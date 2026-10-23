import SwiftUI

enum SettingsSection: Hashable { case general, data, appleSync, localNotifications }

struct SettingsShellView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        TabView(selection: $environment.settingsSection) {
            Form {
                Picker("外观", selection: $environment.appearance) {
                    ForEach(NativeAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                Section("编辑") {
                    Toggle("拼写检查", isOn: Binding(
                        get: { EditorPreferences.spellCheckingEnabled },
                        set: { EditorPreferences.setSpellCheckingEnabled($0) }))
                    Text("智能引号与破折号替换始终关闭，避免破坏 Markdown 语法。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("桌面小组件") {
                    Text("在桌面空白处右键，选择“编辑小组件”，搜索 WorkFollow 并添加“今日待办”。")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("查看今日和逾期任务，勾选完成，或快速进入本周计划。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }
            .tag(SettingsSection.general)

            SettingsDataView()
                .tabItem { Label("数据", systemImage: "externaldrive") }
                .tag(SettingsSection.data)

            SettingsAppleRemindersView(integration: environment.systemReminders, calendarIntegration: environment.systemCalendar)
                .tabItem { Label("Apple 同步", systemImage: "checklist") }
                .tag(SettingsSection.appleSync)

            SettingsCalendarReminderView(reminders: environment.reminders, workspace: environment.taskWorkspace)
                .tabItem { Label("本机通知", systemImage: "bell") }
                .tag(SettingsSection.localNotifications)
        }
        .frame(width: 500, height: 660)
        .navigationTitle("设置")
    }
}
