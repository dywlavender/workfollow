import SwiftUI
import ServiceManagement

enum SettingsSection: String, CaseIterable, Hashable {
    case general, ai, data, appleSync, localNotifications

    var title: String {
        switch self {
        case .general: return "通用"
        case .ai: return "AI 模型"
        case .data: return "数据"
        case .appleSync: return "Apple 同步"
        case .localNotifications: return "本机通知"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .ai: return "sparkles"
        case .data: return "externaldrive"
        case .appleSync: return "checklist"
        case .localNotifications: return "bell"
        }
    }
}

struct SettingsShellView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var aiCatalog: PiModelCatalog? = nil

    private var glassActive: Bool {
        WFGlassSupport.isActive(environment.appearanceMaterial,
                                reduceTransparency: reduceTransparency || WFGlassSupport.systemReduceTransparency)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(WFColors.border.opacity(0.7)).frame(width: WFSpace.hairline)
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 760, height: 580)
        .workfollowPopupSurface()
        .background { WFGlassScrim(opacity: 0.82) }
        .wfGlassWindowBackdrop(glassActive)
        .navigationTitle("设置")
        .hidesSystemFocusEffect()
        // 设置窗口里的下拉、确认面板也沿用主题弹层底色。
        .environment(\.workfollowBackgroundTheme, environment.backgroundTheme)
        .environment(\.workfollowBackgroundIntensity, environment.backgroundIntensity)
        .environment(\.workfollowMaterial, environment.appearanceMaterial)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                SettingsSidebarItem(section: section,
                                    selected: environment.settingsSection == section) {
                    environment.settingsSection = section
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(width: 192)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.03))
    }

    @ViewBuilder
    private var page: some View {
        switch environment.settingsSection {
        case .general:
            SettingsGeneralView()
        case .ai:
            SettingsAIModelsView(store: environment.meetingStore, models: environment.aiModels,
                                 catalog: aiCatalog)
        case .data:
            SettingsDataView()
        case .appleSync:
            SettingsAppleRemindersView(integration: environment.systemReminders,
                                       calendarIntegration: environment.systemCalendar)
        case .localNotifications:
            SettingsCalendarReminderView(reminders: environment.reminders,
                                         workspace: environment.taskWorkspace)
        }
    }
}

private struct SettingsSidebarItem: View {
    let section: SettingsSection
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(selected ? WFColors.accent : WFColors.secondaryText)
                Text(section.title)
                    .font(WFType.listTitle)
                    .foregroundStyle(WFColors.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(selected ? WFColors.selection
                        : hovering ? WFColors.hover : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(section.title)
        .accessibilityValue(selected ? "已选择" : "未选择")
    }
}

/// 设置页统一的滚动留白与节奏。
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20, content: content)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .compactScrollbars()
    }
}

/// 设置分组：标题在卡片外，控件行收进一张浅色圆角卡片。
struct SettingsGroup<Content: View>: View {
    var title: String?
    var footnote: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, footnote: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title)
                    .font(WFType.controlLabelStrong)
                    .foregroundStyle(WFColors.secondaryText)
                    .padding(.horizontal, WFSpace.xs)
            }
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(WFColors.border.opacity(0.7), lineWidth: 1)
                }
            if let footnote {
                Text(footnote)
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.tertiaryText)
                    .padding(.horizontal, WFSpace.xs)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 设置页折叠入口：整行可点，右侧 chevron 旋转，替换系统 DisclosureGroup 的三角。
struct SettingsDisclosure<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    var insetsContent = true
    @ViewBuilder var content: () -> Content

    init(_ title: String, isExpanded: Binding<Bool>, insetsContent: Bool = true,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._isExpanded = isExpanded
        self.insetsContent = insetsContent
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(title).font(WFType.body).foregroundStyle(WFColors.text)
                    Spacer(minLength: WFSpace.md)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WFColors.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, WFSpace.md)
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "已展开" : "已折叠")
            if isExpanded {
                Rectangle().fill(WFColors.menuDivider).frame(height: WFSpace.hairline)
                content()
                    .padding(.horizontal, insetsContent ? WFSpace.md : 0)
                    .padding(.vertical, insetsContent ? 12 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// 设置页的数值步进：圆形 −/+ 与非激活时也不褪色的数值，替换系统 Stepper。
struct SettingsNumberStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    var step: Double = 1

    var body: some View {
        HStack(spacing: 8) {
            stepButton("minus", enabled: value > range.lowerBound) { adjust(-step) }
            Text("\(Int(value)) \(unit)")
                .font(WFType.body)
                .monospacedDigit()
                .foregroundStyle(WFColors.text)
                .frame(minWidth: 44)
            stepButton("plus", enabled: value < range.upperBound) { adjust(step) }
        }
    }

    private func adjust(_ delta: Double) {
        value = min(max(value + delta, range.lowerBound), range.upperBound)
    }

    private func stepButton(_ symbol: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(0.05)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .hoverTip(symbol == "plus" ? "增加" : "减少")
        .accessibilityLabel(symbol == "plus" ? "增加" : "减少")
    }
}

private struct SettingsGeneralView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showWidgetHelp = false
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @AppStorage(EditorPreferences.bodyFontSizeKey)
    private var bodyFontSize = Double(EditorPreferences.defaultBodyFontSize)

    var body: some View {
        SettingsPage {
            SettingsGroup("常规") {
                WFFormRow("外观") {
                    WFSegmentedControl(selection: $environment.appearance,
                                       options: NativeAppearance.allCases.map {
                                           WFSegmentedControl<NativeAppearance>.Option($0, $0.title)
                                       })
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
                        .padding(.bottom, 10)
                }
                if let loginError {
                    Text(loginError).font(WFType.supporting).foregroundStyle(WFColors.danger)
                        .padding(.horizontal, WFSpace.md)
                        .padding(.bottom, 10)
                }
            }
            SettingsGroup("编辑", footnote: "只改变编辑栏里没有单独设置字号的“正文”；已选“正文 1/2/3”、标题、代码与列表保持原样，存量笔记立即生效。") {
                WFFormRow("正文字号", showsDivider: false) {
                    SettingsNumberStepper(value: $bodyFontSize, range: bodyFontSizeRange, unit: "pt")
                        .accessibilityIdentifier("settings.body.fontSize")
                }
                Text("正文预览：记录想法、会议和下一步行动。")
                    .font(.system(size: EditorPreferences.clampedBodyFontSize(CGFloat(bodyFontSize))))
                    .foregroundStyle(WFColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, WFSpace.md)
                    .padding(.top, 2)
                    .padding(.bottom, 12)
            }
            SettingsGroup("背景", footnote: "侧栏、列表、各页面留白和弹窗都会带上主题色；正文与卡片保持纯色。液态玻璃需要 macOS 26 及以上，系统开启“降低透明度”时会自动回退经典材质。") {
                BackgroundThemePreview()
                    .padding(.horizontal, WFSpace.md)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                WFFormRow("背景浓度") {
                    WFSegmentedControl(selection: $environment.backgroundIntensity,
                                       options: NativeBackgroundIntensity.allCases.map {
                                           WFSegmentedControl<NativeBackgroundIntensity>.Option($0, $0.title)
                                       })
                        .frame(width: 180)
                        .disabled(!environment.backgroundTheme.isThemed)
                }
                WFFormRow("外观材质") {
                    WFSegmentedControl(selection: $environment.appearanceMaterial,
                                       options: WFAppearanceMaterial.allCases.map {
                                           WFSegmentedControl<WFAppearanceMaterial>.Option($0, $0.title)
                                       })
                        .frame(width: 180)
                        .disabled(!WFAppearanceMaterial.isAvailable)
                }
                WFFormToggleRow("背景动效", isOn: $environment.backgroundAnimated, showsDivider: false)
                    .disabled(!environment.backgroundTheme.isThemed)
            }
            SettingsGroup("小伙伴", footnote: "只对真实事件做轻反馈：新建、完成、高优先级、逾期、AI、会议、专注、同步和夜间，不会改变任务或专注流程。") {
                WFFormToggleRow("显示小伙伴", isOn: $environment.companionEnabled)
                WFFormRow("角色") {
                    WFSegmentedControl(selection: $environment.companionCharacter,
                                       options: CompanionCharacter.allCases.map {
                                           WFSegmentedControl<CompanionCharacter>.Option($0, $0.title)
                                       })
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
                .padding(.vertical, 10)
            }
            SettingsGroup {
                SettingsDisclosure("添加桌面小组件", isExpanded: $showWidgetHelp) {
                    Text("右键桌面 → 编辑小组件 → WorkFollow → 今日待办")
                        .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                }
            }
        }
        .onAppear { loginStatus = SMAppService.mainApp.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }

    private var bodyFontSizeRange: ClosedRange<Double> {
        return Double(EditorPreferences.bodyFontSizeRange.lowerBound)...Double(EditorPreferences.bodyFontSizeRange.upperBound)
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
                    Text(selection.title).font(WFType.captionStrong)
                    Text(selection.subtitle).font(WFType.taskMeta).foregroundStyle(.secondary)
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
                    Text("当前使用系统纯色表面").font(WFType.caption)
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
                    .font(selection == theme
                          ? Font.system(size: WFType.compactSize, weight: .semibold)
                          : WFType.compact)
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
