import SwiftUI

/// 专注工作区：与 RootShell 的全局 Icon Rail 组成三栏结构；本页包含左侧计时和右侧概览。
/// 底色与应用一致，配色随系统外观切换。
/// `workspace` 为可选的任务关联入口。
struct FocusWorkspaceView: View {
    @ObservedObject var store: FocusStore
    let workspace: TaskWorkspaceModel?
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var environment: AppEnvironment

    /// 专注页主题：底色与整体一致，前后景随系统外观切换。
    private var theme: FocusTheme { FocusTheme(colorScheme) }

    private enum DurationChoice: Hashable {
        case preset(Int)
        case custom
    }

    private static let presetMinutes = [25, 45, 60]

    @State private var durationSelection: DurationChoice = .preset(25)
    @State private var customMinutes = ""
    @State private var durationHint: String?
    @State private var linkedTaskID: UUID?
    @State private var hoveredRecordID: UUID?
    @State private var showGiveUpConfirmation = false
    @State private var showGoalPopover = false
    @State private var showAddRecord = false
    @State private var addRecordTaskID: UUID?
    @State private var addRecordMinutes = "25"
    @State private var addRecordHint: String?
    @State private var showRhythmPopover = false
    @State private var showAddTimer = false
    @State private var addTimerName = ""
    @State private var addTimerStopwatch = false
    @State private var addTimerMinutes = "25"
    @State private var addTimerHint: String?
    @State private var addTimerEmoji = "😀"
    @State private var showEmojiPicker = false
    @State private var hoveredPresetID: UUID?

    init(store: FocusStore) {
        self.store = store
        self.workspace = nil
    }

    init(store: FocusStore, workspace: TaskWorkspaceModel?) {
        self.store = store
        self.workspace = workspace
    }

    var body: some View {
        GeometryReader { geo in
            let s = Self.scale(for: geo.size)
            content(scale: s, width: geo.size.width)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// 设计基准高 1150：窗口更矮时按比例收缩，更高时最多放大 15%。
    static func scale(for size: CGSize) -> CGFloat {
        min(1.2, max(0.6, min(size.height / 982, size.width / 1512)))
    }

    // MARK: - 骨架

    private func content(scale s: CGFloat, width: CGFloat) -> some View {
        let leftWidth = FocusLayoutMetrics.focusPaneWidth(availableWidth: width)
        return HStack(spacing: 0) {
            timerPane(s: s, paneWidth: leftWidth)
                .frame(width: leftWidth)
                .frame(maxHeight: .infinity)
            Rectangle()
                .fill(theme.hairline)
                .frame(width: FocusLayoutMetrics.dividerWidth)
            overviewPane(s: s)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            syncLocalState()
        }
    }

    // MARK: - 左栏 专注计时

    private func timerPane(s: CGFloat, paneWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            paneHeader(s: s)
            if !store.timers.isEmpty {
                presetChipsRow(s: s)
                    .padding(.top, 12 * s)
            }
            Spacer(minLength: 10 * s)
            selectorRow(s: s)
                .padding(.bottom, 18 * s)
            ringView(s: s, paneWidth: paneWidth)
            if store.phase != .idle {
                runningStatus(s: s)
                    .padding(.top, 18 * s)
            }
            if store.phase == .breaking, store.preferences.autoStartNextPomodoro {
                Text("下一番茄 \(nextAutoStartTime) 自动开始")
                    .font(.system(size: 14 * s))
                    .foregroundStyle(theme.text3)
                    .padding(.top, 10 * s)
            }
            Spacer(minLength: 10 * s)
            actionsColumn(s: s)
            Spacer().frame(height: 36 * s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 36 * s)
    }

    private func paneHeader(s: CGFloat) -> some View {
        HStack {
            Text("番茄专注")
                .font(.system(size: 21 * s, weight: .bold))
                .foregroundStyle(theme.text)
            Spacer()
            modeSegment(s: s)
            Spacer()
            headerIcons(s: s)
        }
        .padding(.top, 18 * s)
    }

    /// 模式分段：番茄计时 / 正计时（会话进行中锁定）。
    private func modeSegment(s: CGFloat) -> some View {
        HStack(spacing: 3 * s) {
            segmentItem("番茄计时",
                        selected: !store.preferences.stopwatchMode, s: s) {
                store.setStopwatchMode(false)
            }
            segmentItem("正计时",
                        selected: store.preferences.stopwatchMode, s: s) {
                store.setStopwatchMode(true)
            }
        }
        .padding(4 * s)
        .background(Capsule().fill(theme.chipBackground))
        .opacity(store.phase == .idle ? 1 : 0.55)
        .help(store.phase != .idle ? "会话结束后可切换" : "")
    }

    private func segmentItem(_ title: String, selected: Bool, s: CGFloat,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14 * s, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? theme.text : theme.text2)
                .padding(.horizontal, 15 * s)
                .padding(.vertical, 6 * s)
                .background(Capsule().fill(selected ? theme.segmentActive : .clear))
        }
        .buttonStyle(.plain)
    }

    /// 头部右侧：补记、铃声、节奏。
    private func headerIcons(s: CGFloat) -> some View {
        HStack(spacing: 18 * s) {
            Button {
                addTimerName = ""
                addTimerMinutes = "25"
                addTimerStopwatch = false
                addTimerHint = nil
                addTimerEmoji = "😀"
                showEmojiPicker = false
                showAddTimer = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17 * s, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text2)
            .help("添加常用专注")

            Menu {
                ForEach(FocusBell.allCases, id: \.self) { bell in
                    Button(bell.rawValue) { store.setBell(bell.rawValue) }
                }
            } label: {
                Image(systemName: bellIcon)
                    .font(.system(size: 16 * s))
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .foregroundStyle(theme.text2)
            .help("结束铃声：\(currentBellLabel)")

            Button { showRhythmPopover = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17 * s, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text2)
            .help("节奏设置")
            .popover(isPresented: $showRhythmPopover, arrowEdge: .bottom) {
                rhythmPopover(s: s)
            }
        }
    }

    private var bellIcon: String {
        (FocusBell(rawValue: store.preferences.bellSound ?? "") ?? .off) == .off
            ? "speaker.slash" : "speaker.wave.2"
    }

    private var currentBellLabel: String {
        (FocusBell(rawValue: store.preferences.bellSound ?? "") ?? .off).rawValue
    }

    /// 任务选择行：未绑定时是安静的「专注 ›」，绑定后显示清单色点 + 标题。
    @ViewBuilder
    private func selectorRow(s: CGFloat) -> some View {
        if let workspace {
            let linkID = store.phase == .idle ? linkedTaskID : store.currentTaskID
            let boundTask = linkID.flatMap { workspace.task(for: $0) }
            let title = boundTask.map { $0.title.isEmpty ? "未命名任务" : $0.title }
            let overdue = boundTask.map { isDueOverdue($0) } ?? false
            Menu {
                Button("不关联") {
                    if store.phase == .idle { linkedTaskID = nil } else { store.reattach(taskID: nil) }
                }
                ForEach(unfinishedTasks(in: workspace)) { task in
                    Button {
                        if store.phase == .idle { linkedTaskID = task.id } else { store.reattach(taskID: task.id) }
                    } label: {
                        if task.id == linkID {
                            Label(taskMenuTitle(task), systemImage: "checkmark")
                        } else {
                            Text(taskMenuTitle(task))
                        }
                    }
                }
            } label: {
                HStack(spacing: 8 * s) {
                    if let boundTask {
                        Circle()
                            .fill(listDotColor(for: boundTask.id))
                            .frame(width: 8 * s, height: 8 * s)
                    }
                    Text(title ?? "专注")
                        .font(.system(size: 15 * s, weight: title == nil ? .regular : .semibold))
                        .foregroundStyle(title == nil ? theme.text3
                                         : (overdue ? theme.warn : theme.text))
                        .lineLimit(1)
                    Text("›")
                        .font(.system(size: 14 * s))
                        .foregroundStyle(theme.text3)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("选择一个任务并开始专注")
        }
    }

    private func ringView(s: CGFloat, paneWidth: CGFloat) -> some View {
        let size = min(240 * s, paneWidth * 0.42)
        let active = store.phase == .focusing || store.phase == .breaking
        let stopwatch = store.preferences.stopwatchMode
        return ZStack {
            Circle()
                .stroke(theme.track,
                        style: stopwatch
                            ? StrokeStyle(lineWidth: 2 * max(s, 0.8), dash: [2.5, 5])
                            : StrokeStyle(lineWidth: 2 * max(s, 0.8)))
            Circle()
                .trim(from: 0, to: progress)
                .stroke(progressGradient,
                        style: StrokeStyle(lineWidth: 6 * s, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: progress)
            ringCenter(s: s)
        }
        .frame(width: size, height: size)
        .shadow(color: active ? theme.accent.opacity(0.18) : .clear, radius: 30 * s)
    }

    /// 环心：剩余/已计时间 + 阶段文案 + 关联任务名。
    private func ringCenter(s: CGFloat) -> some View {
        VStack(spacing: 10 * s) {
            Text(FocusViewLogic.clockText(displaySeconds))
                .font(.system(size: 34 * s, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(theme.text)
            Text(FocusViewLogic.phaseTitle(for: store.phase, isLongBreak: store.isLongBreak))
                .font(.system(size: 14 * s))
                .foregroundStyle(theme.text2)
            if let title = ringTaskTitle, store.phase != .idle {
                Text(title)
                    .font(.system(size: 15 * s))
                    .foregroundStyle(theme.text3)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40 * s)
            }
        }
    }

    private func runningStatus(s: CGFloat) -> some View {
        HStack(spacing: 10 * s) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 7 * s, height: 7 * s)
            Text("专注中 · 已专注 \(store.elapsedSeconds / 60) 分钟 · 第 \(store.todayPomodoros + 1) 个番茄")
                .font(.system(size: 14 * s))
                .foregroundStyle(theme.text2)
        }
    }

    private var statusDotColor: Color {
        switch store.phase {
        case .focusing, .breaking: theme.good
        case .pausedFocus, .pausedBreak, .idle: theme.text3
        }
    }

    // MARK: - 主操作

    @ViewBuilder
    private func actionsColumn(s: CGFloat) -> some View {
        VStack(spacing: 14 * s) {
            switch store.phase {
            case .idle:
                primaryButton("开始", s: s) { store.start(taskID: linkedTaskID) }
            case .focusing, .pausedFocus:
                let running = store.phase == .focusing
                primaryButton(running ? "暂 停" : "继 续", s: s) {
                    if running { store.pause() } else { store.resume() }
                }
                HStack(spacing: 22 * s) {
                    linkButton("完成本番茄", s: s) { store.finishEarly() }
                    linkButton("放弃", s: s) { showGiveUpConfirmation = true }
                }
            case .breaking:
                primaryButton("跳过休息", s: s) { _ = store.giveUp() }
            case .pausedBreak:
                HStack(spacing: 22 * s) {
                    primaryButton("继 续", s: s) { store.resume() }
                    linkButton("跳过休息", s: s) { _ = store.giveUp() }
                }
            }
        }
        .confirmationDialog("确定要放弃这个番茄吗？",
                            isPresented: $showGiveUpConfirmation,
                            titleVisibility: .visible) {
            Button("放弃番茄", role: .destructive) { _ = store.giveUp() }
            Button("继续专注", role: .cancel) {}
        } message: {
            Text("已专注满 5 分钟的记录将保留为未完成。")
        }
    }

    private func primaryButton(_ title: String, s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16 * s, weight: .semibold))
                .tracking(1 * s)
                .foregroundStyle(.white)
                .frame(width: 130 * s, height: 46 * s)
                .background(Capsule().fill(theme.accent))
        }
        .buttonStyle(.plain)
    }

    private func linkButton(_ title: String, s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14 * s))
                .foregroundStyle(theme.text2)
                .padding(.vertical, 10 * s)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 计时数据

    private var ringTaskTitle: String? {
        let id = store.phase == .idle ? linkedTaskID : store.currentTaskID
        return taskTitle(for: id)
    }

    private var displaySeconds: Int {
        if store.phase == .idle {
            return store.preferences.stopwatchMode ? 0 : store.preferences.focusMinutes * 60
        }
        if store.preferences.stopwatchMode, store.phase == .focusing || store.phase == .pausedFocus {
            return store.elapsedSeconds
        }
        return store.remainingSeconds
    }

    private var progress: CGFloat {
        guard store.phaseSeconds > 0 else { return 0 }
        let value = CGFloat(store.phaseSeconds - store.remainingSeconds) / CGFloat(store.phaseSeconds)
        return min(max(value, 0), 1)
    }

    /// 进度弧配色：专注 = 强调色渐变，休息 = 绿系渐变，暂停整体降透明。
    private var progressGradient: AngularGradient {
        let (a, b) = progressColors
        return AngularGradient(colors: [a, b],
                               center: .center,
                               startAngle: .degrees(-90),
                               endAngle: .degrees(270))
    }

    private var progressColors: (Color, Color) {
        let isBreak = store.phase == .breaking || store.phase == .pausedBreak
        let a = isBreak ? theme.good : theme.accent
        let b = isBreak ? theme.goodSoft : theme.accentSoft
        let paused = store.phase == .pausedFocus || store.phase == .pausedBreak
        return paused ? (a.opacity(0.4), b.opacity(0.4)) : (a, b)
    }

    /// 自动开始开启时，休息态显示下一番茄的开始时刻。
    private var nextAutoStartTime: String {
        let reference = workspace?.clock() ?? Date()
        return reference.addingTimeInterval(TimeInterval(store.remainingSeconds))
            .formatted(.dateTime.hour().minute())
    }

    private func applyCustomMinutes() {
        guard let minutes = Int(customMinutes.trimmingCharacters(in: .whitespaces)) else {
            durationHint = "请输入 5–180 之间的整数"
            return
        }
        durationHint = store.setFocusMinutes(minutes) ? nil : "时长需在 5–180 分钟之间"
    }

    // MARK: - 右栏 概览与记录

    private func overviewPane(s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("概览")
                .font(.system(size: 20 * s, weight: .bold))
                .foregroundStyle(theme.text)
                .padding(.bottom, 16 * s)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16 * s),
                                GridItem(.flexible(), spacing: 16 * s)],
                      spacing: 16 * s) {
                statCard("今日番茄", value: "\(store.todayPomodoros)", s: s)
                statCard("今日专注时长", value: "\(store.todayMinutes)m", s: s)
                statCard("总番茄", value: "\(store.allTimePomodoros)", s: s)
                statCard("总专注时长", value: "\(store.allTimeMinutes)m", s: s)
            }
            goalLine(s: s)
                .padding(.top, 20 * s)
            HStack(alignment: .firstTextBaseline) {
                Text("专注记录")
                    .font(.system(size: 20 * s, weight: .bold))
                    .foregroundStyle(theme.text)
                Spacer()
                Button { showAddRecord = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18 * s, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.text2)
                .help("补记专注")
            }
            .padding(.top, 32 * s)
            .padding(.bottom, 8 * s)
            if store.recordGroups.isEmpty {
                Spacer(minLength: 20 * s)
                VStack(spacing: 16 * s) {
                    Image(systemName: "timer")
                        .font(.system(size: 46 * s))
                        .foregroundStyle(theme.text3.opacity(0.7))
                    Text("还没有专注记录")
                        .font(.system(size: 17 * s))
                        .foregroundStyle(theme.text3)
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 20 * s)
            } else {
                ScrollView {
                    recordsList(s: s)
                }
            }
        }
        .padding(.horizontal, 42 * s)
        .padding(.vertical, 24 * s)
    }

    private func statCard(_ label: String, value: String, s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            Text(label)
                .font(.system(size: 14 * s))
                .foregroundStyle(theme.text2)
            Text(value)
                .font(.system(size: 28 * s, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20 * s)
        .padding(.vertical, 18 * s)
        .background(RoundedRectangle(cornerRadius: 12 * s).fill(theme.cardBackground))
    }

    /// 今日目标进度：文字 + 细线，点击弹原有目标编辑器。
    private func goalLine(s: CGFloat) -> some View {
        Button { showGoalPopover = true } label: {
            HStack(spacing: 16 * s) {
                Text("今日目标 \(store.todayPomodoros) / \(store.preferences.dailyGoal)")
                    .font(.system(size: 15 * s))
                    .foregroundStyle(theme.text2)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.track)
                        Capsule()
                            .fill(theme.accent)
                            .frame(width: max(0, geo.size.width *
                                CGFloat(min(store.todayPomodoros, store.preferences.dailyGoal)) /
                                CGFloat(max(1, store.preferences.dailyGoal))))
                    }
                }
                .frame(height: 3 * s)
            }
        }
        .buttonStyle(.plain)
        .help("点击修改每日目标")
        .popover(isPresented: $showGoalPopover, arrowEdge: .bottom) {
            goalEditor
        }
    }

    private func recordsList(s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(store.recordGroups) { group in
                Text(FocusViewLogic.dayLabel(for: group.day))
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(theme.text3)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
                ForEach(group.records) { record in
                    recordRow(record)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recordRow(_ record: PomodoroRecord) -> some View {
        let isHovered = hoveredRecordID == record.id
        return HStack(spacing: 12) {
            Text(timeText(record.startedAt))
                .font(.system(size: 15))
                .monospacedDigit()
                .foregroundStyle(theme.text3)
                .frame(width: 76, alignment: .leading)
            Text(recordTitle(for: record))
                .font(.system(size: 17))
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text("\(record.minutes) 分钟")
                .font(.system(size: 15))
                .monospacedDigit()
                .foregroundStyle(record.completed ? theme.text2 : theme.text3)
            Circle()
                .fill(record.completed ? theme.good : theme.warn)
                .frame(width: 6, height: 6)
            Button {
                store.deleteRecord(record.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text3)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help("删除记录")
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard let taskID = record.taskID else { return }
            workspace?.select(taskID)
            environment.navigation.destination = .allTasks
        }
        .onHover { hovering in
            if hovering {
                hoveredRecordID = record.id
            } else if hoveredRecordID == record.id {
                hoveredRecordID = nil
            }
        }
        .contextMenu {
            Button("删除记录", role: .destructive) { store.deleteRecord(record.id) }
        }
    }

    // MARK: - 节奏弹层

    /// 节奏弹层：短/长休息与长休息间隔步进、自动开始开关（全部落 FocusStore）。
    private func rhythmPopover(s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("节奏")
                .font(.system(size: 20 * s, weight: .semibold))
                .foregroundStyle(theme.text)
                .padding(.bottom, 8 * s)
            rhythmStepper("短休息", value: store.preferences.breakMinutes, unit: "分钟",
                          range: 1...60, s: s) { store.setBreakMinutes($0) }
            rhythmStepper("长休息", value: store.preferences.longBreakMinutes, unit: "分钟",
                          range: 1...60, s: s) { store.setLongBreakMinutes($0) }
            rhythmStepper("长休息间隔", value: store.preferences.longBreakInterval, unit: "番茄",
                          range: 2...8, s: s) { store.setLongBreakInterval($0) }
            HStack {
                Text("休息结束自动开始下一番茄")
                    .foregroundStyle(theme.text2)
                Spacer(minLength: 12 * s)
                SwitchView(isOn: Binding(
                    get: { store.preferences.autoStartNextPomodoro },
                    set: { store.setAutoStartNextPomodoro($0) }))
            }
            .font(.system(size: 15 * s))
            .padding(.vertical, 12 * s)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.hairline).frame(height: 1)
            }
            Text("开启后，休息结束时将用同一任务自动开始下一个番茄")
                .font(.system(size: 14 * s))
                .foregroundStyle(theme.text3)
                .padding(.top, 12 * s)
        }
        .padding(22 * s)
        .frame(width: 360 * s)
    }

    private func rhythmStepper(_ key: String, value: Int, unit: String, range: ClosedRange<Int>,
                               s: CGFloat, setter: @escaping (Int) -> Bool) -> some View {
        HStack(spacing: 10 * s) {
            Text(key).foregroundStyle(theme.text2)
            Spacer(minLength: 12 * s)
            stepperButton("minus", s: s) {
                if value > range.lowerBound { _ = setter(value - 1) }
            }
            Text("\(value) \(unit)")
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .frame(width: 88 * s)
            stepperButton("plus", s: s) {
                if value < range.upperBound { _ = setter(value + 1) }
            }
        }
        .font(.system(size: 15 * s))
        .padding(.vertical, 11 * s)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
    }

    private func stepperButton(_ symbol: String, s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(theme.text2)
                .frame(width: 26 * s, height: 26 * s)
                .background(Circle().fill(theme.chipBackground))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 常用专注

    /// 常用专注 chips：点击应用预设，悬浮出现删除。
    private func presetChipsRow(s: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10 * s) {
                ForEach(store.timers) { preset in
                    let active = store.preferences.stopwatchMode == preset.stopwatch
                        && (preset.stopwatch || store.preferences.focusMinutes == preset.minutes)
                    HStack(spacing: 8 * s) {
                        Text(preset.emoji)
                            .font(.system(size: 19 * s))
                        Text(preset.name)
                            .font(.system(size: 19 * s, weight: .medium))
                            .foregroundStyle(active ? theme.accent : theme.text)
                            .lineLimit(1)
                        Text(preset.stopwatch ? "正计时" : "\(preset.minutes) 分钟")
                            .font(.system(size: 17 * s))
                            .foregroundStyle(theme.text3)
                        Button {
                            store.deleteTimer(preset.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13 * s))
                                .foregroundStyle(theme.text3)
                        }
                        .buttonStyle(.plain)
                        .opacity(hoveredPresetID == preset.id ? 1 : 0)
                        .help("删除常用专注")
                    }
                    .padding(.horizontal, 16 * s)
                    .padding(.vertical, 9 * s)
                    .background(Capsule().fill(active ? theme.accentSoft : theme.chipBackground))
                    .contentShape(Capsule())
                    .onTapGesture { store.applyTimerPreset(preset) }
                    .onHover { hovering in
                        if hovering {
                            hoveredPresetID = preset.id
                        } else if hoveredPresetID == preset.id {
                            hoveredPresetID = nil
                        }
                    }
                }
            }
            .padding(.horizontal, 4 * s)
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

    // MARK: - 补记弹层

    /// 补记弹层：任务 + 时长，默认开始时间 = 此刻减去时长（即刚结束的一段）。
    private func addRecordPopover(s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16 * s) {
            Text("补记专注")
                .font(.system(size: 20 * s, weight: .semibold))
                .foregroundStyle(theme.text)
            Menu {
                Button("不关联") { addRecordTaskID = nil }
                ForEach(recordCandidates) { task in
                    Button {
                        addRecordTaskID = task.id
                    } label: {
                        if task.id == addRecordTaskID {
                            Label(taskMenuTitle(task), systemImage: "checkmark")
                        } else {
                            Text(taskMenuTitle(task))
                        }
                    }
                }
            } label: {
                HStack(spacing: 10 * s) {
                    Circle()
                        .fill(listDotColor(for: addRecordTaskID))
                        .frame(width: 9 * s, height: 9 * s)
                    Text(addRecordTaskTitle)
                        .font(.system(size: 16 * s))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 8 * s)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13 * s))
                        .foregroundStyle(theme.text3)
                }
                .frame(width: 280 * s)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            HStack(spacing: 12 * s) {
                Text("时长")
                    .font(.system(size: 15 * s))
                    .foregroundStyle(theme.text2)
                TextField("分钟", text: $addRecordMinutes)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16 * s))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.text)
                    .frame(width: 76 * s)
                    .padding(.vertical, 6 * s)
                    .background(Capsule().stroke(theme.hairline, lineWidth: 1.5))
                    .onSubmit(submitAddRecord)
            }
            if let addRecordHint {
                Text(addRecordHint)
                    .font(.system(size: 13 * s))
                    .foregroundStyle(theme.warn)
            }
            Text("仅支持补记最近 7 天内、此刻之前的专注")
                .font(.system(size: 13 * s))
                .foregroundStyle(theme.text3)
            HStack {
                Spacer()
                Button {
                    submitAddRecord()
                } label: {
                    Text("添 加")
                        .font(.system(size: 15 * s, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 110 * s, height: 36 * s)
                        .background(RoundedRectangle(cornerRadius: 8 * s).fill(theme.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22 * s)
        .frame(width: 330 * s)
    }

    private var recordCandidates: [Task] {
        guard let workspace else { return [] }
        return workspace.allTasks.filter { $0.deletedAt == nil && !$0.isAbandoned }
    }

    private var addRecordTaskTitle: String {
        guard let id = addRecordTaskID, let title = taskTitle(for: id) else { return "不关联" }
        return title
    }

    private func submitAddRecord() {
        let minutes = Int(addRecordMinutes.trimmingCharacters(in: .whitespaces)) ?? 0
        let endedNow = workspace?.clock() ?? Date()
        let startedAt = endedNow.addingTimeInterval(TimeInterval(-minutes * 60))
        if store.addRecord(taskID: addRecordTaskID, startedAt: startedAt, minutes: minutes) {
            showAddRecord = false
            addRecordHint = nil
            addRecordMinutes = "25"
        } else {
            addRecordHint = "补记失败：时长需 1–180 分钟，且时间要在最近 7 天内"
        }
    }

    // MARK: - 目标编辑

    private var goalEditor: some View {
        VStack(alignment: .leading, spacing: WFSpace.md) {
            Text("每日专注目标")
                .font(WFType.section)
            Stepper(value: Binding(
                get: { store.preferences.dailyGoal },
                set: { store.setDailyGoal($0) }), in: 1...24) {
                Text("\(store.preferences.dailyGoal) 个番茄/天")
                    .font(WFType.body)
            }
        }
        .padding(WFSpace.lg)
        .frame(width: 190, alignment: .leading)
    }

    // MARK: - Helpers

    private func unfinishedTasks(in workspace: TaskWorkspaceModel) -> [Task] {
        workspace.allTasks.filter {
            $0.status == .active && $0.deletedAt == nil && !$0.isAbandoned && $0.skippedAt == nil
        }
    }

    private func taskTitle(for id: UUID?) -> String? {
        guard let id, let workspace, let task = workspace.task(for: id) else { return nil }
        return task.title.isEmpty ? "未命名任务" : task.title
    }

    private func taskMenuTitle(_ task: Task) -> String {
        task.title.isEmpty ? "未命名任务" : task.title
    }

    private func recordTitle(for record: PomodoroRecord) -> String {
        record.taskID.flatMap { taskTitle(for: $0) } ?? "未关联任务"
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    /// 清单色点：来自侧栏清单元数据（TaskListMeta.colorARGB），无色回退强调色。
    private func listDotColor(for id: UUID?) -> Color {
        guard let id, let workspace, let task = workspace.task(for: id),
              let argb = workspace.listMetas.first(where: { $0.name == task.list.name })?.colorARGB
        else { return theme.accent }
        return Color(red: Double((argb >> 16) & 0xFF) / 255,
                     green: Double((argb >> 8) & 0xFF) / 255,
                     blue: Double(argb & 0xFF) / 255)
    }

    /// 绑定任务的安排日期早于今天即视为逾期，选择行整段标红提醒。
    private func isDueOverdue(_ task: Task) -> Bool {
        guard let workspace, let dueAt = task.schedule.dueAt else { return false }
        return workspace.calendar.startOfDay(for: dueAt)
            < workspace.calendar.startOfDay(for: workspace.clock())
    }

    private func syncLocalState() {
        let minutes = store.preferences.focusMinutes
        if Self.presetMinutes.contains(minutes) {
            durationSelection = .preset(minutes)
        } else {
            durationSelection = .custom
            customMinutes = String(minutes)
        }
        if linkedTaskID == nil {
            linkedTaskID = store.preferences.lastTaskID ?? workspace?.selectedTaskID
        }
    }
}

/// 专注页主题：与应用同一底色（WFColors.canvas），其余配色随系统外观切换。
private struct FocusTheme {
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
private struct SwitchView: View {
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
