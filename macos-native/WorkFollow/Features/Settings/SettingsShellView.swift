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
        .workfollowPopupSurface()
        .navigationTitle("设置")
        .hidesSystemFocusEffect()
        // 设置窗口里的下拉、确认面板也沿用主题弹层底色。
        .environment(\.workfollowBackgroundTheme, environment.backgroundTheme)
        .environment(\.workfollowBackgroundIntensity, environment.backgroundIntensity)
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
        .workfollowPopupSurface()
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
            WFFormSection("背景", footnote: "侧栏、列表、各页面留白和弹窗都会带上主题色；正文与卡片保持纯色。") {
                BackgroundThemePreview()
                    .padding(.horizontal, WFSpace.md)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                WFFormRow("背景浓度") {
                    Picker("背景浓度", selection: $environment.backgroundIntensity) {
                        ForEach(NativeBackgroundIntensity.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .disabled(!environment.backgroundTheme.isThemed)
                }
                WFFormToggleRow("背景动效", isOn: $environment.backgroundAnimated, showsDivider: false)
                    .disabled(!environment.backgroundTheme.isThemed)
            }
            WFFormSection("小伙伴", footnote: "只对真实事件做轻反馈：新建、完成、高优先级、逾期、AI、会议、专注、同步和夜间，不会改变任务或专注流程。") {
                WFFormToggleRow("显示小伙伴", isOn: $environment.companionEnabled)
                WFFormRow("角色") {
                    Picker("角色", selection: $environment.companionCharacter) {
                        ForEach(CompanionCharacter.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .disabled(!environment.companionEnabled)
                }
                HStack(spacing: 10) {
                    CompanionMascotView(character: environment.companionCharacter,
                                        phase: .happy, animated: false, size: 44)
                        .accessibilityHidden(true)
                    Text("它会回应你正在做的事，不另开一套操作。")
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, WFSpace.md)
                .padding(.vertical, 8)
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

private struct BackgroundThemePreview: View {
    @EnvironmentObject private var environment: AppEnvironment

    private var selection: NativeBackgroundTheme { environment.backgroundTheme }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                previewSurface
                    .frame(height: 124)
                HStack(spacing: 6) {
                    Text(selection.title).font(.system(size: 12, weight: .semibold))
                    Text(selection.subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WFColors.border))

            HStack(spacing: 6) {
                ForEach(NativeBackgroundTheme.allCases) { theme in
                    swatch(theme)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: selection)
        }
    }

    @ViewBuilder
    private var previewSurface: some View {
        if selection.isThemed {
            WorkFollowBackgroundView(theme: selection,
                                     intensity: environment.backgroundIntensity,
                                     animated: environment.backgroundAnimated)
        } else {
            ZStack {
                WFColors.secondarySurface
                VStack(spacing: 6) {
                    Image(systemName: "paintbrush.pointed").font(.system(size: 18))
                    Text("当前使用系统纯色表面").font(.system(size: 11))
                }
                .foregroundStyle(WFColors.tertiaryText)
            }
        }
    }

    private func swatch(_ theme: NativeBackgroundTheme) -> some View {
        Button {
            environment.backgroundTheme = theme
        } label: {
            VStack(spacing: 5) {
                BackgroundThemeSwatch(theme: theme)
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(selection == theme ? WFColors.accent : WFColors.border,
                                          lineWidth: selection == theme ? 1.8 : 1)
                    }
                Text(theme.title)
                    .font(.system(size: 10.5, weight: selection == theme ? .semibold : .regular))
                    .foregroundStyle(selection == theme ? WFColors.text : WFColors.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("背景主题：\(theme.title)")
        .accessibilityValue(selection == theme ? "已选择" : "")
    }
}

private struct BackgroundThemeSwatch: View {
    let theme: NativeBackgroundTheme

    var body: some View {
        if theme.isThemed {
            WorkFollowBackgroundView(theme: theme, intensity: .full, animated: false)
        } else {
            ZStack {
                WFColors.secondarySurface
                Image(systemName: "slash.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(WFColors.tertiaryText)
            }
        }
    }
}
