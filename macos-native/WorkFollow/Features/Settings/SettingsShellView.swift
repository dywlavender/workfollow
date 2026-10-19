import SwiftUI

struct SettingsShellView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        TabView {
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

            SettingsDataView()
                .tabItem { Label("数据", systemImage: "externaldrive") }

            SettingsCalendarReminderView(reminders: environment.reminders,
                integration: environment.systemCalendar, workspace: environment.taskWorkspace)
                .tabItem { Label("日历与提醒", systemImage: "calendar.badge.clock") }
        }
        .frame(width: 500, height: 660)
        .navigationTitle("设置")
    }
}
