import SwiftUI

/// 专注工作区：沉浸式深色画布——中央大圆环计时为主角，左侧时长与节奏、右侧
/// 今日统计与安静记录列（设计定稿：focus mock 2026-09 深色全宽版）。
/// 浅色应用里该页刻意用深色，表达「进入专注模式」的空间切换。
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

    /// 设计稿基准高 1150：窗口更矮时按比例收缩圆环与栏宽，更高时最多放大 15%。
    static func scale(for size: CGSize) -> CGFloat {
        min(1.15, max(0.55, min(size.height / 1150, size.width / 1500)))
    }

    // MARK: - 画布与骨架

    private func content(scale s: CGFloat, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            headerBar(s: s)
            HStack(alignment: .center, spacing: 72 * s) {
                heroColumn(s: s)
                    .frame(maxWidth: .infinity)
                recordsRail(s: s)
                    .frame(width: min(440 * s, max(330, width * 0.36)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 88 * s)
            .padding(.bottom, 48 * s)
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
        .onAppear {
            store.refresh()
            syncLocalState()
        }
    }

    private func headerBar(s: CGFloat) -> some View {
        HStack {
            Text("专 注")
                .font(.system(size: 24 * s, weight: .semibold))
                .tracking(6 * s)
                .foregroundStyle(theme.text2)
            Spacer()
            HStack(spacing: 40 * s) {
                modeTab("番茄", active: !store.preferences.stopwatchMode, s: s) {
                    store.setStopwatchMode(false)
                }
                modeTab("正计时", active: store.preferences.stopwatchMode, s: s) {
                    store.setStopwatchMode(true)
                }
            }
        }
        .padding(.horizontal, 88 * s)
        .frame(height: 92 * s)
    }

    private func modeTab(_ title: String, active: Bool, s: CGFloat,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7 * s) {
                Text(title)
                    .font(.system(size: 23 * s, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? theme.accent : theme.text2)
                Capsule()
                    .fill(active ? theme.accent : .clear)
                    .frame(width: 30 * s, height: 2.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(store.phase != .idle)
        .help(store.phase != .idle ? "会话结束后可切换" : "")
    }

    // MARK: - 中栏 计时主角

    private func heroColumn(s: CGFloat) -> some View {
        VStack(spacing: 0) {
            taskChip(s: s)
                .padding(.bottom, 30 * s)
            ringView(s: s)
                .padding(.bottom, 30 * s)
            if store.phase != .idle {
                statusLine(s: s)
                    .padding(.bottom, 30 * s)
            }
            if store.phase == .breaking, store.preferences.autoStartNextPomodoro {
                Text("下一番茄 \(nextAutoStartTime) 自动开始")
                    .font(.system(size: 20 * s))
                    .foregroundStyle(theme.text3)
                    .padding(.bottom, 20 * s)
            }
            if store.phase == .idle {
                if !store.preferences.stopwatchMode {
                    durationPills(s: s)
                        .padding(.bottom, 14 * s)
                    if durationSelection == .custom {
                        customDurationRow(s: s)
                            .padding(.bottom, 14 * s)
                    }
                }
                Button { showRhythmPopover = true } label: {
                    Text("节奏 ›")
                        .font(.system(size: 20 * s))
                        .foregroundStyle(theme.text3)
                }
                .buttonStyle(.plain)
                .help("短休息、长休息与自动开始")
                .popover(isPresented: $showRhythmPopover, arrowEdge: .top) {
                    rhythmPopover(s: s)
                }
                .padding(.bottom, 20 * s)
            }
            actionsRow(s: s)
            if store.phase == .focusing {
                Text("剩余不足 5 分钟时，会询问是否提前完成本番茄")
                    .font(.system(size: 19 * s))
                    .foregroundStyle(theme.text3)
                    .padding(.top, 26 * s)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 时长选择：滴答式 pills，就绪态出现在计时器下方；选中态描边 + 强调色。
    private func durationPills(s: CGFloat) -> some View {
        HStack(spacing: 14 * s) {
            ForEach(Self.presetMinutes, id: \.self) { minutes in
                pill("\(minutes) 分钟",
                     selected: durationSelection == .preset(minutes),
                     s: s) {
                    durationSelection = .preset(minutes)
                    store.setFocusMinutes(minutes)
                }
            }
            pill("自定义", selected: durationSelection == .custom, s: s) {
                durationSelection = .custom
            }
        }
    }

    private func pill(_ title: String, selected: Bool, s: CGFloat,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 23 * s, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? theme.accent : theme.text2)
                .padding(.horizontal, 28 * s)
                .padding(.vertical, 14 * s)
                .background(Capsule().stroke(
                    selected ? theme.accent : theme.hairline, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func customDurationRow(s: CGFloat) -> some View {
        VStack(spacing: 8 * s) {
            HStack(spacing: 12 * s) {
                TextField("分钟（5–180）", text: $customMinutes)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22 * s))
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.center)
                    .frame(width: 130 * s)
                    .onSubmit(applyCustomMinutes)
                Button("应用", action: applyCustomMinutes)
                    .buttonStyle(.plain)
                    .font(.system(size: 21 * s))
                    .foregroundStyle(theme.accent)
            }
            if let durationHint {
                Text(durationHint)
                    .font(.system(size: 19 * s))
                    .foregroundStyle(theme.warn)
            }
        }
    }

    /// 任务绑定 chip：清单色点 + 标题 + 元信息；就绪态可点击换绑、✕ 解绑。
    @ViewBuilder
    private func taskChip(s: CGFloat) -> some View {
        if let workspace {
            let linkID = store.phase == .idle ? linkedTaskID : store.currentTaskID
            if let title = taskTitle(for: linkID) {
                let chipView = HStack(spacing: 14 * s) {
                    Circle()
                        .fill(listDotColor(for: linkID))
                        .frame(width: 11 * s, height: 11 * s)
                    Text(title)
                        .font(.system(size: 26 * s, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    chipMeta(for: linkID, s: s)
                    if store.phase == .idle {
                        Button {
                            linkedTaskID = nil
                        } label: {
                            Text("✕")
                                .font(.system(size: 20 * s))
                                .foregroundStyle(theme.text3)
                        }
                        .buttonStyle(.plain)
                        .help("解除关联")
                    }
                }
                .padding(.horizontal, 26 * s)
                .padding(.vertical, 12 * s)
                .background(Capsule().fill(theme.chipBackground))
                .contentShape(Capsule())

                if store.phase == .idle {
                    Menu {
                        Button("不关联") { linkedTaskID = nil }
                        ForEach(unfinishedTasks(in: workspace)) { task in
                            Button {
                                linkedTaskID = task.id
                            } label: {
                                if task.id == linkedTaskID {
                                    Label(taskMenuTitle(task), systemImage: "checkmark")
                                } else {
                                    Text(taskMenuTitle(task))
                                }
                            }
                        }
                    } label: { chipView }
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("选择一个任务并开始专注")
                } else {
                    Menu {
                        Button("不关联") { store.reattach(taskID: nil) }
                        ForEach(unfinishedTasks(in: workspace)) { task in
                            Button {
                                store.reattach(taskID: task.id)
                            } label: {
                                if store.currentTaskID == task.id {
                                    Label(taskMenuTitle(task), systemImage: "checkmark")
                                } else {
                                    Text(taskMenuTitle(task))
                                }
                            }
                        }
                    } label: { chipView }
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("更换专注任务")
                }
            } else if store.phase == .idle {
                if unfinishedTasks(in: workspace).isEmpty {
                    Text("暂无未完成任务")
                        .font(.system(size: 23 * s))
                        .foregroundStyle(theme.text3)
                } else {
                    Menu {
                        Button("不关联") { linkedTaskID = nil }
                        ForEach(unfinishedTasks(in: workspace)) { task in
                            Button {
                                linkedTaskID = task.id
                            } label: {
                                if task.id == linkedTaskID {
                                    Label(taskMenuTitle(task), systemImage: "checkmark")
                                } else {
                                    Text(taskMenuTitle(task))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 14 * s) {
                            Circle()
                                .stroke(theme.text3, lineWidth: 1.5)
                                .frame(width: 11 * s, height: 11 * s)
                            Text("选择任务…")
                                .font(.system(size: 26 * s, weight: .semibold))
                                .foregroundStyle(theme.text2)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 16 * s, weight: .medium))
                                .foregroundStyle(theme.text3)
                        }
                        .padding(.horizontal, 26 * s)
                        .padding(.vertical, 12 * s)
                        .background(Capsule().fill(theme.chipBackground))
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("选择一个任务并开始专注")
                }
            }
        }
    }

    @ViewBuilder
    private func chipMeta(for id: UUID?, s: CGFloat) -> some View {
        if let id, let workspace, let task = workspace.task(for: id) {
            let meta = chipMetaText(task)
            if !meta.isEmpty {
                Text(meta)
                    .font(.system(size: 21 * s))
                    .foregroundStyle(isDueOverdue(task) ? theme.warn : theme.text3)
                    .lineLimit(1)
            }
        }
    }

    /// 绑定任务的安排日期早于今天即视为逾期，chip 元信息整段标红提醒。
    private func isDueOverdue(_ task: Task) -> Bool {
        guard let workspace, let dueAt = task.schedule.dueAt else { return false }
        return workspace.calendar.startOfDay(for: dueAt)
            < workspace.calendar.startOfDay(for: workspace.clock())
    }

    private func chipMetaText(_ task: Task) -> String {
        var parts: [String] = [task.list.name]
        if let dueAt = task.schedule.dueAt {
            parts.append(dueAt.formatted(.dateTime.month().day().locale(.appDate)))
        }
        return parts.joined(separator: " · ")
    }

    private var ringSize: CGFloat { 560 }

    private func ringView(s: CGFloat) -> some View {
        let size = ringSize * s
        let active = store.phase == .focusing || store.phase == .breaking
        return ZStack {
            Circle()
                .stroke(theme.track, lineWidth: 5 * s)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(progressGradient,
                        style: StrokeStyle(lineWidth: 10 * s, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: progress)
            ringCenter(s: s)
        }
        .frame(width: size, height: size)
        .shadow(color: active ? theme.accent.opacity(0.26) : .clear, radius: 48 * s)
    }

    /// 环心：剩余时间 + 阶段文案 + 关联任务名。
    private func ringCenter(s: CGFloat) -> some View {
        VStack(spacing: 18 * s) {
            Text(FocusViewLogic.clockText(displaySeconds))
                .font(.system(size: 150 * s, weight: .thin))
                .monospacedDigit()
                .foregroundStyle(theme.text)
            Text(FocusViewLogic.phaseTitle(for: store.phase, isLongBreak: store.isLongBreak))
                .font(.system(size: 23 * s))
                .foregroundStyle(theme.text2)
            if let title = ringTaskTitle, store.phase != .idle {
                Text(title)
                    .font(.system(size: 21 * s))
                    .foregroundStyle(theme.text3)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60 * s)
            }
        }
    }

    private func taskMenuTitle(_ task: Task) -> String {
        task.title.isEmpty ? "未命名任务" : task.title
    }

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

    private func statusLine(s: CGFloat) -> some View {
        HStack(spacing: 12 * s) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 9 * s, height: 9 * s)
            Text(FocusViewLogic.phaseTitle(for: store.phase, isLongBreak: store.isLongBreak))
                .font(.system(size: 23 * s))
            if store.phase == .focusing {
                Text("· 已专注 \(store.elapsedSeconds / 60) 分钟")
                    .font(.system(size: 23 * s))
                Text("· 第 \(store.todayPomodoros + 1) 个番茄")
                    .font(.system(size: 23 * s))
            }
        }
        .foregroundStyle(theme.text2)
    }

    private var statusDotColor: Color {
        switch store.phase {
        case .focusing: theme.good
        case .breaking: theme.good
        case .pausedFocus, .pausedBreak: theme.text3
        case .idle: theme.text3
        }
    }

    /// 自动开始开启时，休息态显示下一番茄的开始时刻。
    private var nextAutoStartTime: String {
        let reference = workspace?.clock() ?? Date()
        return reference.addingTimeInterval(TimeInterval(store.remainingSeconds))
            .formatted(.dateTime.hour().minute())
    }

    @ViewBuilder
    private func actionsRow(s: CGFloat) -> some View {
        switch store.phase {
        case .idle:
            primaryButton("开始专注", s: s) { store.start(taskID: linkedTaskID) }
        case .focusing, .pausedFocus:
            let running = store.phase == .focusing
            HStack(spacing: 34 * s) {
                primaryButton(running ? "暂 停" : "继 续", s: s) {
                    if running { store.pause() } else { store.resume() }
                }
                linkButton("完成本番茄", s: s) { store.finishEarly() }
                linkButton("放弃", s: s) { showGiveUpConfirmation = true }
            }
            .confirmationDialog("确定要放弃这个番茄吗？",
                                isPresented: $showGiveUpConfirmation,
                                titleVisibility: .visible) {
                Button("放弃番茄", role: .destructive) { _ = store.giveUp() }
                Button("继续专注", role: .cancel) {}
            } message: {
                Text("已专注满 5 分钟的记录将保留为未完成。")
            }
        case .breaking:
            primaryButton("跳过休息", s: s) { _ = store.giveUp() }
        case .pausedBreak:
            HStack(spacing: 34 * s) {
                primaryButton("继 续", s: s) { store.resume() }
                linkButton("跳过休息", s: s) { _ = store.giveUp() }
            }
        }
    }

    private func primaryButton(_ title: String, s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 27 * s, weight: .semibold))
                .tracking(3 * s)
                .foregroundStyle(.white)
                .frame(width: 300 * s, height: 64 * s)
                .background(Capsule().fill(theme.accent))
        }
        .buttonStyle(.plain)
    }

    private func linkButton(_ title: String, s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 24 * s))
                .foregroundStyle(theme.text2)
                .padding(.vertical, 14 * s)
        }
        .buttonStyle(.plain)
    }

    private func applyCustomMinutes() {
        guard let minutes = Int(customMinutes.trimmingCharacters(in: .whitespaces)) else {
            durationHint = "请输入 5–180 之间的整数"
            return
        }
        durationHint = store.setFocusMinutes(minutes) ? nil : "时长需在 5–180 分钟之间"
    }

    // MARK: - 右栏 今日统计与记录

    private func recordsRail(s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 52 * s) {
                bigStat(store.todayMinutes, label: "今日分钟", s: s)
                let goalMet = store.preferences.dailyGoal > 0
                    && store.todayPomodoros >= store.preferences.dailyGoal
                bigStat(store.todayPomodoros,
                        label: goalMet ? "已达今日目标" : "今日番茄",
                        s: s, valueColor: goalMet ? theme.good : nil)
            }
            .padding(.bottom, 30 * s)
            goalLine(s: s)
                .padding(.bottom, 34 * s)
            if store.recentDailyStats().reduce(0, { $0 + $1.minutes }) > 0 {
                sparkline(s: s)
                    .padding(.bottom, 34 * s)
            }
            let topTasks = store.weeklyTaskTotals()
            if !topTasks.isEmpty {
                Text("本周时间分布")
                    .font(.system(size: 18 * s, weight: .semibold))
                    .tracking(4 * s)
                    .foregroundStyle(theme.text3)
                    .padding(.bottom, 4 * s)
                ForEach(topTasks.indices, id: \.self) { index in
                    let total = topTasks[index]
                    HStack(spacing: 12 * s) {
                        Circle()
                            .fill(listDotColor(for: total.taskID))
                            .frame(width: 9 * s, height: 9 * s)
                        Text(taskTitle(for: total.taskID) ?? "未关联任务")
                            .font(.system(size: 21 * s))
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                        Spacer(minLength: 10 * s)
                        Text("\(total.minutes) 分钟")
                            .font(.system(size: 20 * s))
                            .monospacedDigit()
                            .foregroundStyle(theme.text2)
                    }
                    .padding(.vertical, 8 * s)
                }
            }
            HStack {
                Text("记 录")
                    .font(.system(size: 18 * s, weight: .semibold))
                    .tracking(4 * s)
                    .foregroundStyle(theme.text3)
                Spacer()
                Button { showAddRecord = true } label: {
                    Text("＋ 补记")
                        .font(.system(size: 20 * s))
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .help("手动添加一条过去的专注记录")
            }
            .padding(.bottom, 8 * s)
            .popover(isPresented: $showAddRecord, arrowEdge: .leading) {
                addRecordPopover(s: s)
            }
            if store.recordGroups.isEmpty {
                Text("选择一个任务并开始专注")
                    .font(.system(size: 21 * s))
                    .foregroundStyle(theme.text3)
                    .padding(.top, 12 * s)
            } else {
                ScrollView {
                    recordsList(s: s)
                }
            }
        }
    }

    /// 补记弹层：任务 + 时长，默认开始时间 = 此刻减去时长（即刚结束的一段）。
    private func addRecordPopover(s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20 * s) {
            Text("补记专注")
                .font(.system(size: 24 * s, weight: .semibold))
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
                HStack(spacing: 12 * s) {
                    Circle()
                        .fill(listDotColor(for: addRecordTaskID))
                        .frame(width: 10 * s, height: 10 * s)
                    Text(addRecordTaskTitle)
                        .font(.system(size: 22 * s))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 8 * s)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 15 * s))
                        .foregroundStyle(theme.text3)
                }
                .frame(width: 320 * s)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            HStack(spacing: 14 * s) {
                Text("时长")
                    .font(.system(size: 21 * s))
                    .foregroundStyle(theme.text2)
                TextField("分钟", text: $addRecordMinutes)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22 * s))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.text)
                    .frame(width: 96 * s)
                    .padding(.vertical, 8 * s)
                    .background(Capsule().stroke(theme.hairline, lineWidth: 1.5))
                    .onSubmit(submitAddRecord)
            }
            if let addRecordHint {
                Text(addRecordHint)
                    .font(.system(size: 19 * s))
                    .foregroundStyle(theme.warn)
            }
            Text("仅支持补记最近 7 天内、此刻之前的专注")
                .font(.system(size: 18 * s))
                .foregroundStyle(theme.text3)
            HStack {
                Spacer()
                Button {
                    submitAddRecord()
                } label: {
                    Text("添 加")
                        .font(.system(size: 22 * s, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 140 * s, height: 44 * s)
                        .background(Capsule().fill(theme.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(30 * s)
        .frame(width: 380 * s)
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

    private func bigStat(_ value: Int, label: String, s: CGFloat, valueColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            Text("\(value)")
                .font(.system(size: 46 * s, weight: .light))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? theme.text)
            Text(label)
                .font(.system(size: 20 * s))
                .foregroundStyle(theme.text2)
        }
    }

    /// 今日目标进度：文字 + 细线，点击弹原有目标编辑器。
    private func goalLine(s: CGFloat) -> some View {
        Button { showGoalPopover = true } label: {
            HStack(spacing: 16 * s) {
                Text("今日目标 \(store.todayPomodoros) / \(store.preferences.dailyGoal)")
                    .font(.system(size: 22 * s))
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
                .frame(height: 4 * s)
            }
        }
        .buttonStyle(.plain)
        .help("点击修改每日目标")
        .popover(isPresented: $showGoalPopover, arrowEdge: .bottom) {
            goalEditor
        }
    }

    /// 近 7 天专注分钟迷你柱状图；最后一天（今天）用强调色。
    private func sparkline(s: CGFloat) -> some View {
        let stats = store.recentDailyStats()
        let peak = max(stats.map(\.minutes).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 14 * s) {
            ForEach(stats.indices, id: \.self) { index in
                let stat = stats[index]
                Capsule()
                    .fill(index == stats.count - 1 ? theme.accent : theme.track)
                    .frame(height: max(6 * s, 72 * s * CGFloat(stat.minutes) / CGFloat(peak)))
                    .help("\(stat.day.formatted(.dateTime.weekday(.abbreviated).locale(.appDate))) · \(stat.minutes) 分钟")
            }
        }
        .frame(height: 74 * s, alignment: .bottom)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recordsList(s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(store.recordGroups) { group in
                Text(FocusViewLogic.dayLabel(for: group.day))
                    .font(.system(size: 19, weight: .semibold))
                    .tracking(4)
                    .foregroundStyle(theme.text3)
                    .padding(.top, 26)
                    .padding(.bottom, 6)
                ForEach(group.records) { record in
                    recordRow(record)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recordRow(_ record: PomodoroRecord) -> some View {
        let isHovered = hoveredRecordID == record.id
        return HStack(spacing: 16) {
            Text(timeText(record.startedAt))
                .font(.system(size: 21))
                .monospacedDigit()
                .foregroundStyle(theme.text3)
                .frame(width: 92, alignment: .leading)
            Text(recordTitle(for: record))
                .font(.system(size: 23))
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Spacer(minLength: 16)
            Text("\(record.minutes) 分钟")
                .font(.system(size: 21))
                .monospacedDigit()
                .foregroundStyle(record.completed ? theme.text2 : theme.text3)
            Circle()
                .fill(record.completed ? theme.good : theme.warn)
                .frame(width: 7, height: 7)
            Button {
                store.deleteRecord(record.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.text3)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help("删除记录")
        }
        .padding(.vertical, 15)
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

    private func recordTitle(for record: PomodoroRecord) -> String {
        record.taskID.flatMap { taskTitle(for: $0) } ?? "未关联任务"
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
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

    /// 清单色点：来自侧栏清单元数据（TaskListMeta.colorARGB），无色回退强调色。
    private func listDotColor(for id: UUID?) -> Color {
        guard let id, let workspace, let task = workspace.task(for: id),
              let argb = workspace.listMetas.first(where: { $0.name == task.list.name })?.colorARGB
        else { return theme.accent }
        return Color(red: Double((argb >> 16) & 0xFF) / 255,
                     green: Double((argb >> 8) & 0xFF) / 255,
                     blue: Double(argb & 0xFF) / 255)
    }

    /// 节奏弹层：短/长休息与长休息间隔步进、自动开始开关（全部落 FocusStore）。
    private func rhythmPopover(s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("节奏")
                .font(.system(size: 24 * s, weight: .semibold))
                .foregroundStyle(theme.text)
                .padding(.bottom, 10 * s)
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
            .font(.system(size: 21 * s))
            .padding(.vertical, 15 * s)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.hairline).frame(height: 1)
            }
            Text("开启后，休息结束时将用同一任务自动开始下一个番茄")
                .font(.system(size: 18 * s))
                .foregroundStyle(theme.text3)
                .padding(.top, 14 * s)
        }
        .padding(28 * s)
        .frame(width: 400 * s)
    }

    private func rhythmStepper(_ key: String, value: Int, unit: String, range: ClosedRange<Int>,
                               s: CGFloat, setter: @escaping (Int) -> Bool) -> some View {
        HStack(spacing: 14 * s) {
            Text(key).foregroundStyle(theme.text2)
            Spacer(minLength: 12 * s)
            stepperButton("minus", s: s) {
                if value > range.lowerBound { _ = setter(value - 1) }
            }
            Text("\(value) \(unit)")
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .frame(width: 110 * s)
            stepperButton("plus", s: s) {
                if value < range.upperBound { _ = setter(value + 1) }
            }
        }
        .font(.system(size: 21 * s))
        .padding(.vertical, 13 * s)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
    }

    private func stepperButton(_ symbol: String, s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14 * s, weight: .semibold))
                .foregroundStyle(theme.text2)
                .frame(width: 30 * s, height: 30 * s)
                .background(Circle().fill(theme.chipBackground))
        }
        .buttonStyle(.plain)
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

/// 专注页主题：与应用同一底色（WFColors.canvas），其余配色随系统外观切换——
/// 深色外观下即是沉浸深色稿，浅色外观下为极简浅色稿。
private struct FocusTheme {

    let canvas = WFColors.canvas
    let text: Color
    let text2: Color
    let text3: Color
    let hairline: Color
    let accent: Color
    let accentSoft: Color
    let track: Color
    let chipBackground: Color
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
            .frame(width: 52, height: 30)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 24, height: 24)
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
