import SwiftUI

/// 专注工作区：沉浸式深色画布——中央大圆环计时为主角，左侧时长与节奏、右侧
/// 今日统计与安静记录列（设计定稿：focus mock 2026-09 深色全宽版）。
/// 浅色应用里该页刻意用深色，表达「进入专注模式」的空间切换。
/// `workspace` 为可选的任务关联入口。
struct FocusWorkspaceView: View {
    @ObservedObject var store: FocusStore
    let workspace: TaskWorkspaceModel?

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
            content(scale: s)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// 设计稿基准高 1150：窗口更矮时按比例收缩圆环与栏宽，更高时最多放大 15%。
    static func scale(for size: CGSize) -> CGFloat {
        min(1.15, max(0.55, min(size.height / 1150, size.width / 1500)))
    }

    // MARK: - 画布与骨架

    private func content(scale s: CGFloat) -> some View {
        VStack(spacing: 0) {
            headerBar(s: s)
            HStack(alignment: .center, spacing: 72 * s) {
                heroColumn(s: s)
                    .frame(maxWidth: .infinity)
                recordsRail(s: s)
                    .frame(width: 440 * s)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 88 * s)
            .padding(.bottom, 48 * s)
        }
        .background(FocusPalette.background)
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
                .foregroundStyle(FocusPalette.text2)
            Spacer()
            HStack(spacing: 40 * s) {
                modeTab("番茄", active: true, s: s)
                Text("正计时")
                    .font(.system(size: 23 * s))
                    .foregroundStyle(FocusPalette.text3)
                    .help("正计时模式即将上线")
            }
        }
        .padding(.horizontal, 88 * s)
        .frame(height: 92 * s)
    }

    private func modeTab(_ title: String, active: Bool, s: CGFloat) -> some View {
        VStack(spacing: 7 * s) {
            Text(title)
                .font(.system(size: 23 * s, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? FocusPalette.accent : FocusPalette.text2)
            Capsule()
                .fill(active ? FocusPalette.accent : .clear)
                .frame(width: 30 * s, height: 2.5)
        }
    }

    // MARK: - 中栏 计时主角

    private func heroColumn(s: CGFloat) -> some View {
        VStack(spacing: 0) {
            taskChip(s: s)
                .padding(.bottom, 30 * s)
            ringView(s: s)
                .padding(.bottom, 30 * s)
            statusLine(s: s)
                .padding(.bottom, 30 * s)
            if store.phase == .idle {
                durationPills(s: s)
                    .padding(.bottom, 22 * s)
                if durationSelection == .custom {
                    customDurationRow(s: s)
                        .padding(.bottom, 16 * s)
                }
            }
            actionsRow(s: s)
            if store.phase == .focusing {
                Text("剩余不足 5 分钟时，会询问是否提前完成本番茄")
                    .font(.system(size: 19 * s))
                    .foregroundStyle(FocusPalette.text3)
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
                .foregroundStyle(selected ? FocusPalette.accent : FocusPalette.text2)
                .padding(.horizontal, 28 * s)
                .padding(.vertical, 14 * s)
                .background(Capsule().stroke(
                    selected ? FocusPalette.accent : FocusPalette.hairline, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func customDurationRow(s: CGFloat) -> some View {
        VStack(spacing: 8 * s) {
            HStack(spacing: 12 * s) {
                TextField("分钟（5–180）", text: $customMinutes)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22 * s))
                    .foregroundStyle(FocusPalette.text)
                    .multilineTextAlignment(.center)
                    .frame(width: 130 * s)
                    .onSubmit(applyCustomMinutes)
                Button("应用", action: applyCustomMinutes)
                    .buttonStyle(.plain)
                    .font(.system(size: 21 * s))
                    .foregroundStyle(FocusPalette.accent)
            }
            if let durationHint {
                Text(durationHint)
                    .font(.system(size: 19 * s))
                    .foregroundStyle(FocusPalette.warn)
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
                        .foregroundStyle(FocusPalette.text)
                        .lineLimit(1)
                    if store.phase == .idle {
                        chipMeta(for: linkID, s: s)
                        Button {
                            linkedTaskID = nil
                        } label: {
                            Text("✕")
                                .font(.system(size: 20 * s))
                                .foregroundStyle(FocusPalette.text3)
                        }
                        .buttonStyle(.plain)
                        .help("解除关联")
                    }
                }
                .padding(.horizontal, 26 * s)
                .padding(.vertical, 12 * s)
                .background(Capsule().fill(Color.white.opacity(0.04)))
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
                    chipView
                }
            } else if store.phase == .idle {
                if unfinishedTasks(in: workspace).isEmpty {
                    Text("暂无未完成任务")
                        .font(.system(size: 23 * s))
                        .foregroundStyle(FocusPalette.text3)
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
                                .stroke(FocusPalette.text3, lineWidth: 1.5)
                                .frame(width: 11 * s, height: 11 * s)
                            Text("选择任务…")
                                .font(.system(size: 26 * s, weight: .semibold))
                                .foregroundStyle(FocusPalette.text2)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 16 * s, weight: .medium))
                                .foregroundStyle(FocusPalette.text3)
                        }
                        .padding(.horizontal, 26 * s)
                        .padding(.vertical, 12 * s)
                        .background(Capsule().fill(Color.white.opacity(0.04)))
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
                    .foregroundStyle(FocusPalette.text3)
                    .lineLimit(1)
            }
        }
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
                .stroke(FocusPalette.track, lineWidth: 5 * s)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(progressGradient,
                        style: StrokeStyle(lineWidth: 10 * s, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: progress)
            ringCenter(s: s)
        }
        .frame(width: size, height: size)
        .shadow(color: active ? FocusPalette.accent.opacity(0.26) : .clear, radius: 48 * s)
    }

    /// 环心：剩余时间 + 阶段文案 + 关联任务名。
    private func ringCenter(s: CGFloat) -> some View {
        VStack(spacing: 18 * s) {
            Text(FocusViewLogic.clockText(displaySeconds))
                .font(.system(size: 150 * s, weight: .thin))
                .monospacedDigit()
                .foregroundStyle(FocusPalette.text)
            Text(FocusViewLogic.phaseTitle(for: store.phase, isLongBreak: store.isLongBreak))
                .font(.system(size: 23 * s))
                .foregroundStyle(FocusPalette.text2)
            if let title = ringTaskTitle, store.phase != .idle {
                Text(title)
                    .font(.system(size: 21 * s))
                    .foregroundStyle(FocusPalette.text3)
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
        store.phase == .idle ? store.preferences.focusMinutes * 60 : store.remainingSeconds
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
        let a = isBreak ? FocusPalette.good : FocusPalette.accent
        let b = isBreak ? FocusPalette.goodSoft : FocusPalette.accent2
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
                Text("· 已专注 \(max(0, store.phaseSeconds - store.remainingSeconds) / 60) 分钟")
                    .font(.system(size: 23 * s))
            }
        }
        .foregroundStyle(FocusPalette.text2)
    }

    private var statusDotColor: Color {
        switch store.phase {
        case .focusing: FocusPalette.good
        case .breaking: FocusPalette.good
        case .pausedFocus, .pausedBreak: FocusPalette.text3
        case .idle: FocusPalette.text3
        }
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
                .background(Capsule().fill(FocusPalette.accent))
        }
        .buttonStyle(.plain)
    }

    private func linkButton(_ title: String, s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 24 * s))
                .foregroundStyle(FocusPalette.text2)
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
                bigStat(store.todayPomodoros, label: "今日番茄", s: s)
            }
            .padding(.bottom, 30 * s)
            goalLine(s: s)
                .padding(.bottom, 34 * s)
            sparkline(s: s)
                .padding(.bottom, 34 * s)
            if store.recordGroups.isEmpty {
                Text("选择一个任务并开始专注")
                    .font(.system(size: 21 * s))
                    .foregroundStyle(FocusPalette.text3)
                    .padding(.top, 12 * s)
            } else {
                ScrollView {
                    recordsList(s: s)
                }
            }
        }
    }

    private func bigStat(_ value: Int, label: String, s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            Text("\(value)")
                .font(.system(size: 46 * s, weight: .light))
                .monospacedDigit()
                .foregroundStyle(FocusPalette.text)
            Text(label)
                .font(.system(size: 20 * s))
                .foregroundStyle(FocusPalette.text2)
        }
    }

    /// 今日目标进度：文字 + 细线，点击弹原有目标编辑器。
    private func goalLine(s: CGFloat) -> some View {
        Button { showGoalPopover = true } label: {
            HStack(spacing: 16 * s) {
                Text("今日目标 \(store.todayPomodoros) / \(store.preferences.dailyGoal)")
                    .font(.system(size: 22 * s))
                    .foregroundStyle(FocusPalette.text2)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(FocusPalette.track)
                        Capsule()
                            .fill(FocusPalette.accent)
                            .frame(width: max(0, geo.size.width *
                                CGFloat(min(store.todayPomodoros, store.preferences.dailyGoal)) /
                                CGFloat(max(1, store.preferences.dailyGoal))))
                    }
                }
                .frame(height: 4 * s)
            }
        }
        .buttonStyle(.plain)
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
                let isToday = index == stats.count - 1
                Capsule()
                    .fill(isToday ? FocusPalette.accent : FocusPalette.track)
                    .frame(height: max(6 * s, 72 * s * CGFloat(stats[index].minutes) / CGFloat(peak)))
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
                    .foregroundStyle(FocusPalette.text3)
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
                .foregroundStyle(FocusPalette.text3)
                .frame(width: 92, alignment: .leading)
            Text(recordTitle(for: record))
                .font(.system(size: 23))
                .foregroundStyle(FocusPalette.text)
                .lineLimit(1)
            Spacer(minLength: 16)
            Text("\(record.minutes) 分钟")
                .font(.system(size: 21))
                .monospacedDigit()
                .foregroundStyle(record.completed ? FocusPalette.text2 : FocusPalette.text3)
            Circle()
                .fill(record.completed ? FocusPalette.good : FocusPalette.warn)
                .frame(width: 7, height: 7)
            Button {
                store.deleteRecord(record.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(FocusPalette.text3)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help("删除记录")
        }
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FocusPalette.hairline).frame(height: 1)
        }
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
        else { return FocusPalette.accent }
        return Color(red: Double((argb >> 16) & 0xFF) / 255,
                     green: Double((argb >> 8) & 0xFF) / 255,
                     blue: Double(argb & 0xFF) / 255)
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

/// 专注页专用深色配色：浅色应用里这一页刻意沉浸。
private enum FocusPalette {
    static let background = RadialGradient(
        colors: [Color(red: 0.114, green: 0.114, blue: 0.161),
                 Color(red: 0.086, green: 0.086, blue: 0.118)],
        center: UnitPoint(x: 0.5, y: -0.1), startRadius: 10, endRadius: 1500)
    static let text = Color.white.opacity(0.96)
    static let text2 = Color.white.opacity(0.52)
    static let text3 = Color.white.opacity(0.30)
    static let hairline = Color.white.opacity(0.075)
    static let accent = Color(red: 0.545, green: 0.486, blue: 0.969)
    static let accent2 = Color(red: 0.757, green: 0.659, blue: 1.0)
    static let track = Color.white.opacity(0.09)
    static let good = Color(red: 0.290, green: 0.871, blue: 0.502)
    static let goodSoft = Color(red: 0.545, green: 0.937, blue: 0.702)
    static let warn = Color(red: 0.973, green: 0.443, blue: 0.443)
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
