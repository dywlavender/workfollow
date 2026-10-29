import SwiftUI
import ServiceManagement

enum SettingsSection: Hashable { case general, ai, data, appleSync, localNotifications }

struct SettingsShellView: View {
    @EnvironmentObject private var environment: AppEnvironment
    var aiCatalog: PiModelCatalog? = nil

    var body: some View {
        TabView(selection: $environment.settingsSection) {
            SettingsGeneralView()
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(SettingsSection.general)

            SettingsAIModelsView(store: environment.meetingStore, models: environment.aiModels, catalog: aiCatalog)
                .tabItem { Label("AI 模型", systemImage: "sparkles") }
                .tag(SettingsSection.ai)

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
        .frame(width: 560, height: 520)
        .background(WFColors.content)
        .navigationTitle("设置")
        .hidesSystemFocusEffect()
    }
}

/// All settings pages share one inset and row rhythm; details expand in place.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24, content: content)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(WFColors.content)
    }
}

private struct SettingsGeneralView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showWidgetHelp = false
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        SettingsPage {
            WFFormSection {
                WFFormRow("外观") {
                    Picker("外观", selection: $environment.appearance) {
                        ForEach(NativeAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
                WFFormToggleRow("拼写检查", isOn: Binding(
                    get: { EditorPreferences.spellCheckingEnabled },
                    set: { EditorPreferences.setSpellCheckingEnabled($0) }))
                WFFormToggleRow("完成任务时播放提示音", isOn: Binding(
                    get: { TaskCompletionFeedback.isSoundEnabled },
                    set: { TaskCompletionFeedback.isSoundEnabled = $0 }))
                WFFormRow("完成提示音") {
                    BusinessPicker("", selection: Binding(
                        get: { TaskCompletionFeedback.sound.identifier },
                        set: { TaskCompletionFeedback.sound = TaskCompletionFeedback.Sound.resolve($0) }),
                        options: TaskCompletionFeedback.Sound.allCases.map {
                            BusinessChoice($0.identifier, $0.rawValue)
                        })
                        .labelsHidden()
                        .disabled(!TaskCompletionFeedback.isSoundEnabled)
                }
                WFFormToggleRow("登录时启动 WorkFollow", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: updateLoginItem), showsDivider: false)
                if loginStatus == .requiresApproval {
                    Button("在系统设置中允许登录启动") { SMAppService.openSystemSettingsLoginItems() }
                        .padding(.horizontal, WFSpace.md)
                }
                if let loginError {
                    Text(loginError).font(WFType.supporting).foregroundStyle(.red)
                        .padding(.horizontal, WFSpace.md)
                }
            }
            DisclosureGroup("添加桌面小组件", isExpanded: $showWidgetHelp) {
                Text("右键桌面 → 编辑小组件 → WorkFollow → 今日待办")
                    .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                    .padding(.top, 8)
            }
            .font(WFType.body)
            .padding(.horizontal, WFSpace.md)
        }
        .onAppear { loginStatus = SMAppService.mainApp.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch { loginError = error.localizedDescription }
        loginStatus = SMAppService.mainApp.status
    }
}
