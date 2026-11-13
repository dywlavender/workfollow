import SwiftUI

/// 专注工作区：与 RootShell 的全局 Icon Rail 组成三栏结构；本页包含左侧计时和右侧概览。
/// 底色与应用一致，配色随系统外观切换。
/// `workspace` 为可选的任务关联入口。
struct FocusWorkspaceView: View {
    @ObservedObject var store: FocusStore
    @ObservedObject private var shortcuts = AppShortcutStore.shared
    let workspace: TaskWorkspaceModel?
    let onSelectRecordTask: ((UUID) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workfollowBackgroundTheme) private var backgroundTheme

    /// 专注页主题：底色与整体一致，前后景随系统外观切换。
    private var theme: FocusTheme { FocusTheme(colorScheme) }

    @StateObject private var taskPicker = FocusTaskPickerSession()
    @State private var showGiveUpConfirmation = false
    @State private var showAddTimer = false
    @State private var addTimerName = ""
    @State private var addTimerStopwatch = false
    @State private var addTimerMinutes = "25"
    @State private var addTimerHint: String?
    @State private var addTimerTaskID: UUID?
    @State private var addTimerEmoji = "😀"
    @State private var showEmojiPicker = false

    init(store: FocusStore) {
        self.store = store
        self.workspace = nil
        self.onSelectRecordTask = nil
    }

    init(store: FocusStore, workspace: TaskWorkspaceModel?,
         onSelectRecordTask: ((UUID) -> Void)? = nil) {
        self.store = store
        self.workspace = workspace
        self.onSelectRecordTask = onSelectRecordTask
    }

    var body: some View {
        GeometryReader { geo in
            content(width: geo.size.width)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(minWidth: FocusLayoutMetrics.minimumWorkspaceWidth)
        .environment(\.calendar, store.presentationCalendar)
        .environment(\.timeZone, store.presentationCalendar.timeZone)
    }

    // MARK: - 骨架

    private func content(width: CGFloat) -> some View {
        let leftWidth = FocusLayoutMetrics.focusPaneWidth(availableWidth: width,
            isCompleted: store.completionContext != nil || store.workspacePage == .library)
        return HStack(spacing: 0) {
            Group {
                if store.workspacePage == .library {
                    FocusPresetLibraryPane(store: store, workspace: workspace, onAddTimer: prepareAddTimer)
                } else {
                    FocusTimerPane(store: store,
                                   workspace: workspace,
                                   taskPicker: taskPicker,
                                   showGiveUpConfirmation: $showGiveUpConfirmation)
                }
            }
                .frame(width: leftWidth)
                .frame(maxHeight: .infinity)
            Rectangle()
                .fill(theme.hairline)
                .frame(width: FocusLayoutMetrics.dividerWidth)
                .focusRenderAnchor(.divider)
            Group {
                if store.contentRoute == .statistics {
                    FocusStatisticsPane(store: store, workspace: workspace)
                } else if store.contentRoute == .records {
                    FocusOverviewPane(store: store, workspace: workspace, onSelectRecordTask: onSelectRecordTask)
                } else if store.workspacePage == .library {
                    if let id = store.browsedPresetID {
                        FocusPresetDetailPane(store: store, workspace: workspace, presetID: id,
                                              onSelectRecordTask: onSelectRecordTask)
                    } else {
                        FocusOverviewPane(store: store, workspace: workspace, onSelectRecordTask: onSelectRecordTask)
                    }
                } else {
                    FocusActiveSessionPane(store: store, workspace: workspace, onAssociate: { taskPicker.present() })
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .workfollowPageSurface()
        .background {
            if store.phase != .idle {
                Group {
                    Button("专注空格键") {
                        switch store.phase {
                        case .focusing: store.pause()
                        case .pausedFocus, .pausedBreak: store.resume()
                        case .breaking: store.pause()
                        case .idle: break
                        }
                    }
                    .keyboardShortcut(shortcuts.chord(for: .pauseFocus).swiftUIShortcut)
                    Button("专注Esc键") {
                        if store.phase == .focusing { showGiveUpConfirmation = true }
                    }
                    .keyboardShortcut(shortcuts.chord(for: .endFocus).swiftUIShortcut)
                }
                .frame(width: 0, height: 0)
                .opacity(0)
            }
        }
        .overlay {
            if showAddTimer {
                addTimerDialog
            }
        }
        .onAppear {
            store.refresh()
            if taskPicker.linkedTaskID == nil {
                taskPicker.linkedTaskID = store.preferences.lastTaskID ?? workspace?.selectedTaskID
            }
        }
    }

    /// 添加常用专注对话框：emoji 头像 + 名称 + 计时模式（不压暗页面，对齐滴答）。
    /// 结构与 SheetDialog 同口径：DialogHeader + Divider + 内容 + DialogFooter；
    /// 字号固定走令牌，不再按窗口比例缩放。
    private var addTimerDialog: some View {
        let nameValid = !addTimerName.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(spacing: 0) {
            DialogHeader(title: "添加常用专注")
            Divider()
            VStack(alignment: .leading, spacing: WFSpace.lg) {
                HStack(spacing: 14) {
                    Button { showEmojiPicker.toggle() } label: {
                        ZStack(alignment: .bottomTrailing) {
                            Circle()
                                .fill(theme.avatarBackground)
                                .frame(width: 48, height: 48)
                            Text(addTimerEmoji)
                                .font(.system(size: 26))
                            Circle()
                                .fill(theme.canvas)
                                .frame(width: 16, height: 16)
                                .overlay(Image(systemName: "pencil")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(theme.text2))
                                .offset(x: 2, y: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .hoverTip("选择表情")
                    TextField("名称", text: $addTimerName)
                        .textFieldStyle(.plain)
                        .font(WFType.body)
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius)
                            .stroke(theme.hairline, lineWidth: 1))
                }
                if let workspace {
                    BusinessPicker("关联任务", selection: $addTimerTaskID, options:
                        [BusinessChoice(nil, "不关联")] + workspace.allTasks.filter { !$0.isNoteTask && $0.deletedAt == nil && !$0.isAbandoned }.map { task in
                            BusinessChoice(Optional(task.id), task.title.isEmpty ? "未命名任务" : task.title, symbol: "checklist")
                        }, width: PopupMetrics.relationPickerWidth)
                }
                if showEmojiPicker {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(FocusTheme.emojiChoices, id: \.self) { emoji in
                                Button {
                                    addTimerEmoji = emoji
                                    showEmojiPicker = false
                                } label: {
                                    Text(emoji)
                                        .font(.system(size: 26))
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(
                                            addTimerEmoji == emoji ? theme.accentSoft : theme.chipBackground))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("计时模式")
                        .font(WFType.controlLabelStrong)
                        .foregroundStyle(theme.text)
                    HStack(spacing: 12) {
                        Button { addTimerStopwatch = false } label: {
                            HStack(spacing: 9) {
                                radioCircle(selected: !addTimerStopwatch)
                                Text("番茄计时")
                                    .font(WFType.body)
                                    .foregroundStyle(theme.text)
                            }
                        }
                        .buttonStyle(.plain)
                        if !addTimerStopwatch {
                            TextField("25", text: $addTimerMinutes)
                                .textFieldStyle(.plain)
                                .font(WFType.controlLarge)
                                .monospacedDigit()
                                .multilineTextAlignment(.center)
                                .foregroundStyle(theme.text)
                                .frame(width: 72)
                                .padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius)
                                    .fill(theme.chipBackground))
                            Text("分钟")
                                .font(WFType.bodyLarge)
                                .foregroundStyle(theme.text2)
                        }
                    }
                    Button { addTimerStopwatch = true } label: {
                        HStack(spacing: 9) {
                            radioCircle(selected: addTimerStopwatch)
                            Text("正计时")
                                .font(WFType.body)
                                .foregroundStyle(theme.text)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(PopupMetrics.formInset)
            DialogFooter(primaryTitle: "确定", canSubmit: nameValid,
                         onCancel: { showAddTimer = false }, onSubmit: submitAddTimer) {
                if let addTimerHint {
                    Text(addTimerHint).foregroundStyle(WFColors.danger)
                }
            }
        }
        .frame(width: SheetDialogMetrics.regularWidth)
        .background {
            WFGlassSurface(shape: RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius),
                           fallback: backgroundTheme.popupFillOrFallback(theme.canvas, for: colorScheme))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.16), radius: 24, x: 0, y: 5)
        }
        .overlay(RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius).stroke(theme.hairline, lineWidth: 1))
        .background(FocusOutsideClickObserver { showAddTimer = false })
        .background(PopupEscapeRouter(depth: 1) { showAddTimer = false })
    }

    private func radioCircle(selected: Bool) -> some View {
        ZStack {
            Circle().stroke(selected ? theme.accent : theme.text3, lineWidth: 1.5)
            if selected {
                Circle().fill(theme.accent).padding(3)
            }
        }
        .frame(width: 16, height: 16)
    }

    private func prepareAddTimer() {
        addTimerName = ""
        addTimerMinutes = "25"
        addTimerStopwatch = false
        addTimerHint = nil
        addTimerEmoji = "😀"
        addTimerTaskID = taskPicker.linkedTaskID
        showEmojiPicker = false
        showAddTimer = true
    }

    private func submitAddTimer() {
        let minutes = Int(addTimerMinutes.trimmingCharacters(in: .whitespaces)) ?? 0
        if store.addTimer(name: addTimerName, emoji: addTimerEmoji,
                          stopwatch: addTimerStopwatch, minutes: minutes, taskID: addTimerTaskID) {
            if let preset = store.timers.last { store.selectPresetForDetails(preset.id) }
            showAddTimer = false
        } else {
            addTimerHint = "名称必填；番茄计时需 5–180 分钟；常用专注最多 12 个"
        }
    }

}

/// 专注页主题：与应用同一底色（WFColors.canvas），其余配色随系统外观切换。
struct FocusTheme {
    /// 常用专注头像的可选 emoji。
    static let emojiChoices = ["😀", "😎", "🥳", "🤔", "🍅", "⏰", "📚", "💼", "🏃", "🧘", "💻", "🎨"]

    let canvas = WFColors.canvas
    let text: Color
    let text2: Color
    let text3: Color
    let hairline: Color
    let accent: Color
    let accentSoft: Color
    let track: Color
    let chipBackground: Color
    let cardBackground: Color
    let segmentActive: Color
    let avatarBackground: Color
    let good: Color
    let goodSoft: Color
    let warn: Color

    init(_ scheme: ColorScheme) {
        if scheme == .dark {
            text = Color.white.opacity(0.96)
            text2 = Color.white.opacity(0.52)
            text3 = Color.white.opacity(0.30)
            hairline = Color.white.opacity(0.075)
            accent = WFColors.accent
            accentSoft = WFColors.accent.opacity(0.6)
            track = Color.white.opacity(0.09)
            chipBackground = Color.white.opacity(0.04)
            cardBackground = Color.white.opacity(0.06)
            segmentActive = Color.white.opacity(0.14)
            avatarBackground = Color.white.opacity(0.12)
            good = WFColors.focusGood
            goodSoft = WFColors.focusGoodSoft
            warn = WFColors.focusWarn
        } else {
            text = WFColors.text
            text2 = WFColors.secondaryText
            text3 = WFColors.tertiaryText
            hairline = WFColors.border.opacity(0.7)
            accent = WFColors.accent
            accentSoft = WFColors.accent.opacity(0.6)
            track = Color.primary.opacity(0.08)
            chipBackground = Color.primary.opacity(0.04)
            cardBackground = Color.primary.opacity(0.045)
            segmentActive = .white
            avatarBackground = WFColors.focusAvatarBackground
            good = WFColors.focusGood
            goodSoft = WFColors.focusGoodSoft
            warn = WFColors.focusWarn
        }
    }
}

/// 迷你开关：专注页节奏弹层用的胶囊式 Switch。
struct SwitchView: View {
    @Binding var isOn: Bool
    var accessibilityTitle = "自动开始下一番茄"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = FocusTheme(colorScheme)
        Capsule()
            .fill(isOn ? theme.accent : theme.track)
            .frame(width: 44, height: 26)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .padding(3)
            }
            .contentShape(Capsule())
            .onTapGesture { isOn.toggle() }
            .animation(.easeInOut(duration: 0.15), value: isOn)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityAddTraits(.isButton)
    }
}

/// 专注页纯展示逻辑：时间/阶段/概览文案与日期分组头，供视图与单元测试共用。
enum FocusViewLogic {
    /// 剩余时间 mm:ss；负值按 0 处理。
    static func clockText(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// 阶段文案：就绪/专注中/休息中/长休息/已暂停/休息已暂停。
    static func phaseTitle(for phase: PomodoroPhase, isLongBreak: Bool) -> String {
        switch phase {
        case .idle: "就绪"
        case .focusing: "专注中"
        case .breaking: isLongBreak ? "长休息" : "休息中"
        case .pausedFocus: "已暂停"
        case .pausedBreak: "休息已暂停"
        }
    }

    /// 今日概览主段："今日专注 32 分钟 · 3 个番茄"。
    static func todayFocusSummary(minutes: Int, pomodoros: Int) -> String {
        "今日专注 \(minutes) 分钟 · \(pomodoros) 个番茄"
    }

    /// 今日概览目标段："距目标还差 2 个" / "已达目标"。
    static func todayGoalText(pomodoros: Int, goal: Int) -> String {
        let missing = max(0, goal - pomodoros)
        return missing == 0 ? "已达目标" : "距目标还差 \(missing) 个"
    }

    /// 近 7 天逐日统计的轻量投影，避免视图层依赖 store 类型做纯计算。
    struct DayStat {
        let minutes: Int
        let pomodoros: Int
    }

    /// 记录区头部一行小字：有记录给合计，无记录给提示。
    static func weeklySummary(_ stats: [DayStat]) -> String {
        let minutes = stats.reduce(0) { $0 + $1.minutes }
        let pomodoros = stats.reduce(0) { $0 + $1.pomodoros }
        if minutes == 0 && pomodoros == 0 { return "最近 7 天暂无专注记录" }
        return "最近 7 天专注 \(minutes) 分钟 · \(pomodoros) 个番茄"
    }

    /// 记录日期分组头：今天/昨天，其余给月日星期。
    static func dayLabel(for day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "今天" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: yesterday) { return "昨天" }
        var style = Date.FormatStyle.dateTime.month().day().weekday(.abbreviated)
        style.calendar = calendar; style.timeZone = calendar.timeZone
        return day.formatted(style)
    }

    static func timeLabel(for date: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.calendar = calendar; style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    static func dateTimeLabel(for date: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle.dateTime.year().month().day().hour().minute()
        style.calendar = calendar; style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}
