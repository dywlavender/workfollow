import SwiftUI

/// 专注工作区：滴答清单式单列专注页——大圆环计时、单行主操作、今日概览与安静记录列表。
/// `workspace` 为可选的任务关联入口。
struct FocusWorkspaceView: View {
    @ObservedObject var store: FocusStore
    let workspace: TaskWorkspaceModel?

    private enum DurationChoice: Hashable {
        case preset(Int)
        case custom
    }

    private static let presetMinutes = [25, 45, 60]
    private static let ringSize: CGFloat = 240
    private static let ringWidth: CGFloat = 12

    @State private var durationSelection: DurationChoice = .preset(25)
    @State private var customMinutes = ""
    @State private var durationHint: String?
    @State private var linkedTaskID: UUID?
    @State private var hoveredRecordID: UUID?
    @State private var showGiveUpConfirmation = false
    @State private var showGoalPopover = false

    init(store: FocusStore) {
        self.store = store
        self.workspace = nil
    }

    init(store: FocusStore, workspace: TaskWorkspaceModel?) {
        self.store = store
        self.workspace = workspace
    }

    var body: some View {
        // 页面整体不滚动：上三段固定高度，剩余空间全部交给记录列表内部滚动。
        VStack(spacing: 0) {
            VStack(spacing: WFSpace.page) {
                ringSection
                controlsSection
                overviewLine
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, WFSpace.lg)

            recordsSection
                .padding(.top, WFSpace.page)
                .padding(.bottom, WFSpace.page)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, WFSpace.page)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WFColors.canvas)
        .onAppear {
            store.refresh()
            syncLocalState()
        }
    }

    // MARK: - 段1 圆环

    private var ringSection: some View {
        VStack(spacing: WFSpace.lg) {
            ring
            if store.phase == .idle { taskMenuRow }
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(WFColors.border, lineWidth: Self.ringWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: progress)
            ringCenter
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
    }

    /// 环心：剩余时间 + 阶段文案 + 关联任务名。
    private var ringCenter: some View {
        VStack(spacing: WFSpace.xs) {
            Text(FocusViewLogic.clockText(displaySeconds))
                .font(.system(size: 44, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(WFColors.text)
            Text(FocusViewLogic.phaseTitle(for: store.phase, isLongBreak: store.isLongBreak))
                .font(WFType.supporting)
                .foregroundStyle(WFColors.secondaryText)
            if let title = ringTaskTitle {
                Text(title)
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.tertiaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, WFSpace.md)
            }
        }
        .padding(.horizontal, WFSpace.xl)
    }

    /// 就绪态圆环下方的安静任务选择 Menu；无 workspace 时整行隐藏。
    @ViewBuilder
    private var taskMenuRow: some View {
        if let workspace {
            let unfinished = unfinishedTasks(in: workspace)
            if unfinished.isEmpty {
                Text("暂无未完成任务")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.tertiaryText)
            } else {
                Menu {
                    Button("不关联") { linkedTaskID = nil }
                    ForEach(unfinished) { task in
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
                    HStack(spacing: 6) {
                        Text(taskMenuLabel)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .font(WFType.body)
                    .foregroundStyle(linkedTaskID == nil ? WFColors.secondaryText : WFColors.text)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(store.phase != .idle)
                .help("选择一个任务并开始专注")
            }
        }
    }

    private var taskMenuLabel: String {
        guard let id = linkedTaskID, let title = taskTitle(for: id) else { return "选择任务…" }
        return title
    }

    private func taskMenuTitle(_ task: Task) -> String {
        task.title.isEmpty ? "未命名任务" : task.title
    }

    private var ringTaskTitle: String? {
        let id = store.phase == .idle ? linkedTaskID : store.currentTaskID
        return taskTitle(for: id)
    }

    private var displaySeconds: Int {
        store.phase == .idle ? store.preferences.focusMinutes * 60 : store.remainingSeconds
    }

    private var progress: CGFloat {
        guard store.phaseSeconds > 0 else { return 0 }
        let value = CGFloat(store.phaseSeconds - store.remainingSeconds) / CGFloat(store.phaseSeconds)
        return min(max(value, 0), 1)
    }

    private var ringColor: Color {
        let base: Color = store.phase == .breaking || store.phase == .pausedBreak ? .green : WFColors.accent
        let paused = store.phase == .pausedFocus || store.phase == .pausedBreak
        return paused ? base.opacity(0.4) : base
    }

    // MARK: - 段2 主操作

    /// 就绪态 = 时长分段 + 开始专注；进行中 = 暂停/继续 + 放弃 + 提前完成；休息中 = 跳过休息。
    @ViewBuilder
    private var controlsSection: some View {
        if store.phase == .idle {
            VStack(spacing: WFSpace.lg) {
                Picker("时长", selection: $durationSelection) {
                    ForEach(Self.presetMinutes, id: \.self) { Text("\($0) 分钟").tag(DurationChoice.preset($0)) }
                    Text("自定义").tag(DurationChoice.custom)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                .onChange(of: durationSelection) { _, choice in
                    if case .preset(let minutes) = choice { store.setFocusMinutes(minutes) }
                }
                if durationSelection == .custom {
                    customDurationRow
                }
                Button {
                    store.start(taskID: linkedTaskID)
                } label: {
                    Label("开始专注", systemImage: "play.fill")
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        } else {
            sessionButtons
        }
    }

    private var customDurationRow: some View {
        VStack(spacing: WFSpace.xs) {
            HStack(spacing: WFSpace.sm) {
                TextField("分钟（5–180）", text: $customMinutes)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(width: 84)
                    .onSubmit(applyCustomMinutes)
                Button("应用", action: applyCustomMinutes)
            }
            if let durationHint {
                Text(durationHint)
                    .font(WFType.supporting)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var sessionButtons: some View {
        switch store.phase {
        case .idle:
            EmptyView()
        case .focusing, .pausedFocus:
            let running = store.phase == .focusing
            HStack(spacing: WFSpace.md) {
                Button(running ? "暂停" : "继续") {
                    if running { store.pause() } else { store.resume() }
                }
                .buttonStyle(.bordered)
                Button("放弃", role: .destructive) { showGiveUpConfirmation = true }
                    .buttonStyle(.bordered)
                Button("提前完成") { store.finishEarly() }
                    .buttonStyle(.bordered)
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
            Button("跳过休息") { _ = store.giveUp() }
                .buttonStyle(.borderedProminent)
        case .pausedBreak:
            HStack(spacing: WFSpace.md) {
                Button("继续") { store.resume() }
                    .buttonStyle(.bordered)
                Button("跳过休息") { _ = store.giveUp() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func applyCustomMinutes() {
        guard let minutes = Int(customMinutes.trimmingCharacters(in: .whitespaces)) else {
            durationHint = "请输入 5–180 之间的整数"
            return
        }
        durationHint = store.setFocusMinutes(minutes) ? nil : "时长需在 5–180 分钟之间"
    }

    // MARK: - 段3 今日概览

    /// 一行纯文字概览；目标数字可点击弹 popover 修改。
    private var overviewLine: some View {
        HStack(spacing: WFSpace.xs) {
            Text(FocusViewLogic.todayFocusSummary(minutes: store.todayMinutes, pomodoros: store.todayPomodoros))
                .font(WFType.body)
                .foregroundStyle(WFColors.secondaryText)
            Text("·")
                .font(WFType.body)
                .foregroundStyle(WFColors.tertiaryText)
            Button {
                showGoalPopover = true
            } label: {
                Text(FocusViewLogic.todayGoalText(pomodoros: store.todayPomodoros,
                                                  goal: store.preferences.dailyGoal))
                    .font(WFType.body)
            }
            .buttonStyle(.link)
            .popover(isPresented: $showGoalPopover, arrowEdge: .bottom) {
                goalEditor
            }
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

    // MARK: - 段4 记录

    /// 安静的最近记录列表：头部一行近 7 天小字，日期分组头 + 行；列表内部滚动，页面不滚。
    private var recordsSection: some View {
        VStack(spacing: WFSpace.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近记录")
                    .font(WFType.section)
                    .foregroundStyle(WFColors.secondaryText)
                Spacer()
                Text(weeklySummaryText)
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.tertiaryText)
            }
            if store.recordGroups.isEmpty {
                Text("选择一个任务并开始专注")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.tertiaryText)
                    .padding(.top, WFSpace.lg)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    recordsList
                }
            }
        }
    }

    private var recordsList: some View {
        VStack(alignment: .leading, spacing: WFSpace.xs) {
            ForEach(store.recordGroups) { group in
                Text(FocusViewLogic.dayLabel(for: group.day))
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.tertiaryText)
                    .padding(.top, WFSpace.md)
                ForEach(group.records) { record in
                    recordRow(record)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, WFSpace.xs)
    }

    private func recordRow(_ record: PomodoroRecord) -> some View {
        let isHovered = hoveredRecordID == record.id
        return HStack(spacing: WFSpace.sm) {
            Image(systemName: record.completed ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 13))
                .foregroundStyle(record.completed ? WFColors.accent : WFColors.tertiaryText)
            Text(recordTitle(for: record))
                .font(WFType.body)
                .foregroundStyle(WFColors.text)
                .lineLimit(1)
            Spacer(minLength: WFSpace.md)
            Text("\(timeText(record.startedAt)) · \(record.minutes) 分钟")
                .font(WFType.supporting)
                .foregroundStyle(WFColors.secondaryText)
            Button {
                store.deleteRecord(record.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(WFColors.tertiaryText)
            .opacity(isHovered ? 1 : 0)
            .help("删除记录")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
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

    private func recordTitle(for record: PomodoroRecord) -> String {
        record.taskID.flatMap { taskTitle(for: $0) } ?? "未关联任务"
    }

    private var weeklySummaryText: String {
        FocusViewLogic.weeklySummary(store.recentDailyStats().map {
            FocusViewLogic.DayStat(minutes: $0.minutes, pomodoros: $0.pomodoros)
        })
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

    private func syncLocalState() {
        let minutes = store.preferences.focusMinutes
        if Self.presetMinutes.contains(minutes) {
            durationSelection = .preset(minutes)
        } else {
            durationSelection = .custom
            customMinutes = String(minutes)
        }
        if linkedTaskID == nil { linkedTaskID = workspace?.selectedTaskID }
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
