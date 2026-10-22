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
