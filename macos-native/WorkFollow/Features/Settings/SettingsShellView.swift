import SwiftUI

enum SettingsSection: Hashable { case general, data, appleSync, localNotifications }

struct SettingsShellView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        TabView(selection: $environment.settingsSection) {
            ScrollView {
                VStack(alignment: .leading, spacing: WFSpace.lg) {
                    WFFormSection("外观") {
                        Picker("外观", selection: $environment.appearance) {
                            ForEach(NativeAppearance.allCases) { appearance in
                                Text(appearance.title).tag(appearance)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 360)
                        .padding(.horizontal, WFSpace.md)
                    }
                    WFFormSection("编辑") {
                        WFFormToggleRow("拼写检查", isOn: Binding(
                            get: { EditorPreferences.spellCheckingEnabled },
                            set: { EditorPreferences.setSpellCheckingEnabled($0) }))
                        WFFormNote("智能引号与破折号替换始终关闭，避免破坏 Markdown 语法。")
                    }
                    WFFormSection("声音") {
                        WFFormToggleRow("完成任务时播放提示音", isOn: Binding(
                            get: { TaskCompletionFeedback.isSoundEnabled },
                            set: { TaskCompletionFeedback.isSoundEnabled = $0 }), showsDivider: false)
                        WFFormNote("勾选完成瞬间播放短促提示音（与滴答一致），可随时关闭。")
                    }
                    WFFormSection("桌面小组件") {
                        WFFormNote("在桌面空白处右键，选择“编辑小组件”，搜索 WorkFollow 并添加“今日待办”。")
                        WFFormNote("查看今日和逾期任务，勾选完成，或快速进入本周计划。")
                    }
                }
                .padding(WFSpace.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
