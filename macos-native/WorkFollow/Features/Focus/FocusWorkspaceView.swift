import SwiftUI

/// 专注工作区：与 RootShell 的全局 Icon Rail 组成三栏结构；本页包含左侧计时和右侧概览。
/// 底色与应用一致，配色随系统外观切换。
/// `workspace` 为可选的任务关联入口。
struct FocusWorkspaceView: View {
    @ObservedObject var store: FocusStore
    let workspace: TaskWorkspaceModel?
    let onSelectRecordTask: ((UUID) -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    /// 专注页主题：底色与整体一致，前后景随系统外观切换。
    private var theme: FocusTheme { FocusTheme(colorScheme) }

    @StateObject private var taskPicker = FocusTaskPickerSession()
    @State private var showGiveUpConfirmation = false
    @State private var showAddTimer = false
    @State private var addTimerName = ""
    @State private var addTimerStopwatch = false
    @State private var addTimerMinutes = "25"
    @State private var addTimerHint: String?
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
            let dialogScale = Self.scale(for: geo.size)
            content(dialogScale: dialogScale, width: geo.size.width)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(minWidth: FocusLayoutMetrics.minimumWorkspaceWidth)
    }

    /// 仅保留常用专注创建弹框的既有缩放；左右 pane 尺寸均由固定 point 契约控制。
    static func scale(for size: CGSize) -> CGFloat {
        min(1.2, max(0.6, min(size.height / 982, size.width / 1512)))
    }

    // MARK: - 骨架

    private func content(dialogScale s: CGFloat, width: CGFloat) -> some View {
        let leftWidth = FocusLayoutMetrics.focusPaneWidth(availableWidth: width)
        return HStack(spacing: 0) {
            FocusTimerPane(store: store,
                           workspace: workspace,
                           taskPicker: taskPicker,
                           showGiveUpConfirmation: $showGiveUpConfirmation,
                           onAddTimer: prepareAddTimer)
                .frame(width: leftWidth)
                .frame(maxHeight: .infinity)
            Rectangle()
                .fill(theme.hairline)
                .frame(width: FocusLayoutMetrics.dividerWidth)
                .focusRenderAnchor(.divider)
            if store.phase == .focusing || store.phase == .pausedFocus {
                FocusActiveSessionPane(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FocusOverviewPane(store: store, workspace: workspace,
                                  onSelectRecordTask: onSelectRecordTask)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.canvas)
        .background {
            if store.phase != .idle {
                Group {
                    Button("专注空格键") {
                        switch store.phase {
                        case .focusing: store.pause()
                        case .pausedFocus, .pausedBreak: store.resume()
                        case .breaking: _ = store.giveUp()
                        case .idle: break
                        }
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    Button("专注Esc键") {
                        if store.phase == .focusing { showGiveUpConfirmation = true }
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .frame(width: 0, height: 0)
                .opacity(0)
            }
        }
        .overlay {
            if showAddTimer {
                addTimerDialog(s: s)
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
    private func addTimerDialog(s: CGFloat) -> some View {
        let nameValid = !addTimerName.trimmingCharacters(in: .whitespaces).isEmpty
        return ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showAddTimer = false }
            VStack(spacing: 16 * s) {
                Text("添加常用专注")
                    .font(.system(size: 20 * s, weight: .semibold))
                    .foregroundStyle(theme.text)
                HStack(spacing: 14 * s) {
                    Button { showEmojiPicker.toggle() } label: {
                        ZStack(alignment: .bottomTrailing) {
                            Circle()
                                .fill(theme.avatarBackground)
                                .frame(width: 48 * s, height: 48 * s)
                            Text(addTimerEmoji)
                                .font(.system(size: 26 * s))
                            Circle()
                                .fill(theme.canvas)
                                .frame(width: 16 * s, height: 16 * s)
                                .overlay(Image(systemName: "pencil")
                                    .font(.system(size: 9 * s, weight: .semibold))
                                    .foregroundStyle(theme.text2))
                                .offset(x: 2 * s, y: 2 * s)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("选择表情")
                    TextField("名称", text: $addTimerName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16 * s))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 12 * s)
                        .padding(.vertical, 10 * s)
                        .background(RoundedRectangle(cornerRadius: 10 * s)
                            .stroke(theme.hairline, lineWidth: 1.5))
                }
                if showEmojiPicker {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10 * s) {
                            ForEach(FocusTheme.emojiChoices, id: \.self) { emoji in
                                Button {
                                    addTimerEmoji = emoji
                                    showEmojiPicker = false
                                } label: {
                                    Text(emoji)
                                        .font(.system(size: 26 * s))
                                        .frame(width: 44 * s, height: 44 * s)
                                        .background(Circle().fill(
                                            addTimerEmoji == emoji ? theme.accentSoft : theme.chipBackground))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12 * s) {
                    Text("计时模式")
                        .font(.system(size: 16 * s, weight: .semibold))
                        .foregroundStyle(theme.text)
                    HStack(spacing: 12 * s) {
                        Button { addTimerStopwatch = false } label: {
                            HStack(spacing: 9 * s) {
                                radioCircle(selected: !addTimerStopwatch, s: s)
                                Text("番茄计时")
                                    .font(.system(size: 16 * s))
                                    .foregroundStyle(theme.text)
                            }
                        }
                        .buttonStyle(.plain)
                        if !addTimerStopwatch {
                            TextField("25", text: $addTimerMinutes)
                                .textFieldStyle(.plain)
                                .font(.system(size: 16 * s))
                                .monospacedDigit()
                                .multilineTextAlignment(.center)
                                .foregroundStyle(theme.text)
                                .frame(width: 72 * s)
                                .padding(.vertical, 7 * s)
                                .background(RoundedRectangle(cornerRadius: 7 * s).fill(theme.chipBackground))
                            Text("分钟")
                                .font(.system(size: 15 * s))
                                .foregroundStyle(theme.text2)
                        }
                    }
                    Button { addTimerStopwatch = true } label: {
                        HStack(spacing: 9 * s) {
                            radioCircle(selected: addTimerStopwatch, s: s)
                            Text("正计时")
                                .font(.system(size: 16 * s))
                                .foregroundStyle(theme.text)
                        }
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Spacer()
                    Button { showAddTimer = false } label: {
                        Text("取消")
                            .font(.system(size: 15 * s))
                            .foregroundStyle(theme.text2)
                            .frame(width: 92 * s, height: 36 * s)
                            .background(RoundedRectangle(cornerRadius: 8 * s)
                                .fill(theme.canvas)
                                .overlay(RoundedRectangle(cornerRadius: 8 * s)
                                    .stroke(theme.hairline, lineWidth: 1.5)))
                    }
                    .buttonStyle(.plain)
                    Button { submitAddTimer() } label: {
                        Text("确定")
                            .font(.system(size: 15 * s, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 92 * s, height: 36 * s)
                            .background(RoundedRectangle(cornerRadius: 8 * s)
                                .fill(theme.accent.opacity(nameValid ? 1 : 0.45)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!nameValid)
                }
            }
            .padding(28 * s)
            .frame(width: 560 * s)
            .background(RoundedRectangle(cornerRadius: 16 * s).fill(theme.canvas)
                .shadow(color: .black.opacity(0.16), radius: 30 * s))
            .overlay(RoundedRectangle(cornerRadius: 16 * s).stroke(theme.hairline, lineWidth: 1))
        }
    }

    private func radioCircle(selected: Bool, s: CGFloat) -> some View {
        ZStack {
            Circle().stroke(selected ? theme.accent : theme.text3, lineWidth: 1.5)
            if selected {
                Circle().fill(theme.accent).padding(3 * s)
            }
        }
        .frame(width: 16 * s, height: 16 * s)
    }

    private func prepareAddTimer() {
        addTimerName = ""
        addTimerMinutes = "25"
        addTimerStopwatch = false
        addTimerHint = nil
        addTimerEmoji = "😀"
        showEmojiPicker = false
        showAddTimer = true
    }

    private func submitAddTimer() {
        let minutes = Int(addTimerMinutes.trimmingCharacters(in: .whitespaces)) ?? 0
        if store.addTimer(name: addTimerName, emoji: addTimerEmoji,
                          stopwatch: addTimerStopwatch, minutes: minutes) {
            if let preset = store.timers.last { store.applyTimerPreset(preset) }
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
            accent = Color(red: 0.545, green: 0.486, blue: 0.969)
            accentSoft = Color(red: 0.757, green: 0.659, blue: 1.0)
            track = Color.white.opacity(0.09)
            chipBackground = Color.white.opacity(0.04)
            cardBackground = Color.white.opacity(0.06)
            segmentActive = Color.white.opacity(0.14)
            avatarBackground = Color.white.opacity(0.12)
            good = Color(red: 0.290, green: 0.871, blue: 0.502)
            goodSoft = Color(red: 0.545, green: 0.937, blue: 0.702)
            warn = Color(red: 0.973, green: 0.443, blue: 0.443)
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
            avatarBackground = Color(red: 1.0, green: 0.94, blue: 0.62)
            good = Color(red: 0.082, green: 0.686, blue: 0.427)
            goodSoft = Color(red: 0.220, green: 0.808, blue: 0.553)
            warn = .red
        }
    }
}

/// 迷你开关：专注页节奏弹层用的胶囊式 Switch。
struct SwitchView: View {
    @Binding var isOn: Bool
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
            .accessibilityLabel("自动开始下一番茄")
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
    static func dayLabel(for day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        return day.formatted(.dateTime.month().day().weekday(.abbreviated))
    }
}
