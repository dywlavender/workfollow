import SwiftUI

/// Left Focus Pane. Core geometry is fixed in points; only its containing pane width responds.
struct FocusTimerPane: View {
    @ObservedObject var store: FocusStore
    let workspace: TaskWorkspaceModel?
    @Binding var linkedTaskID: UUID?
    @Binding var showGiveUpConfirmation: Bool
    let onAddTimer: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showRhythmPopover = false
    @State private var hoveredPresetID: UUID?

    private var theme: FocusTheme { FocusTheme(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            paneHeader

            if !store.timers.isEmpty {
                presetChipsRow
                    .frame(height: FocusLayoutMetrics.presetChipsRowHeight)
                    .padding(.top, FocusLayoutMetrics.presetChipsRowTop)
            }

            timerStage(hasPresetChips: !store.timers.isEmpty)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            actionsColumn
                .frame(maxWidth: .infinity)
                .frame(height: FocusLayoutMetrics.footerHeight, alignment: .top)
        }
        .padding(.horizontal, FocusLayoutMetrics.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var paneHeader: some View {
        ZStack {
            HStack(spacing: 0) {
                Text("番茄专注")
                    .font(.system(size: FocusLayoutMetrics.titleFontSize, weight: .semibold))
                    .foregroundStyle(theme.text)
                Spacer(minLength: 0)
                headerIcons
            }

            modeSegment
        }
        .frame(height: FocusLayoutMetrics.headerHeight)
        .padding(.top, FocusLayoutMetrics.topPadding)
    }

    private var modeSegment: some View {
        HStack(spacing: 0) {
            segmentItem("番茄计时", selected: !store.preferences.stopwatchMode) {
                store.setStopwatchMode(false)
            }
            segmentItem("正计时", selected: store.preferences.stopwatchMode) {
                store.setStopwatchMode(true)
            }
        }
        .padding(FocusLayoutMetrics.segmentTrackInset)
        .frame(width: FocusLayoutMetrics.segmentWidth, height: FocusLayoutMetrics.segmentHeight)
        .background(Capsule().fill(theme.chipBackground))
        .opacity(store.phase == .idle ? 1 : 0.55)
        .help(store.phase != .idle ? "会话结束后可切换" : "")
    }

    private func segmentItem(_ title: String, selected: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: FocusLayoutMetrics.segmentFontSize,
                              weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? theme.text : theme.text2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().fill(selected ? theme.segmentActive : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var headerIcons: some View {
        HStack(spacing: FocusLayoutMetrics.headerButtonSpacing) {
            Button(action: onAddTimer) {
                Image(systemName: "plus")
                    .font(.system(size: FocusLayoutMetrics.headerIconSize, weight: .medium))
                    .frame(width: FocusLayoutMetrics.headerButtonSize,
                           height: FocusLayoutMetrics.headerButtonSize)
                    .contentShape(Rectangle())
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
                    .font(.system(size: FocusLayoutMetrics.headerIconSize))
                    .frame(width: FocusLayoutMetrics.headerButtonSize,
                           height: FocusLayoutMetrics.headerButtonSize)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .foregroundStyle(theme.text2)
            .help("结束铃声：\(currentBellLabel)")

            Button { showRhythmPopover = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: FocusLayoutMetrics.headerIconSize, weight: .medium))
                    .frame(width: FocusLayoutMetrics.headerButtonSize,
                           height: FocusLayoutMetrics.headerButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text2)
            .help("节奏设置")
            .popover(isPresented: $showRhythmPopover, arrowEdge: .bottom) {
                rhythmPopover
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

    private func timerStage(hasPresetChips: Bool) -> some View {
        VStack(spacing: 0) {
            selectorRow
                .frame(height: FocusLayoutMetrics.focusLabelHeight)
                .padding(.top, FocusLayoutMetrics.selectorTopPadding(hasPresetChips: hasPresetChips))

            FocusTimerRing(store: store, theme: theme, taskTitle: ringTaskTitle)
                .focusRenderAnchor(.timerRing)
                .padding(.top, FocusLayoutMetrics.ringTopGap)

            if store.phase != .idle {
                runningStatus
                    .padding(.top, FocusLayoutMetrics.statusTopGap)
            }

            if store.phase == .breaking, store.preferences.autoStartNextPomodoro {
                Text("下一番茄 \(nextAutoStartTime) 自动开始")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text3)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var selectorRow: some View {
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
                        if store.phase == .idle { linkedTaskID = task.id }
                        else { store.reattach(taskID: task.id) }
                    } label: {
                        if task.id == linkID {
                            Label(taskMenuTitle(task), systemImage: "checkmark")
                        } else {
                            Text(taskMenuTitle(task))
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if let boundTask {
                        Circle()
                            .fill(listDotColor(for: boundTask.id))
                            .frame(width: 8, height: 8)
                    }
                    Text(title ?? "专注")
                        .font(.system(size: 15, weight: title == nil ? .regular : .semibold))
                        .foregroundStyle(title == nil ? theme.text3
                                         : (overdue ? theme.warn : theme.text))
                        .lineLimit(1)
                    Text("›")
                        .font(.system(size: 14))
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

    private var runningStatus: some View {
        HStack(spacing: FocusLayoutMetrics.statusSpacing) {
            Circle()
                .fill(statusDotColor)
                .frame(width: FocusLayoutMetrics.statusDotSize,
                       height: FocusLayoutMetrics.statusDotSize)
            Text("专注中 · 已专注 \(store.elapsedSeconds / 60) 分钟 · 第 \(store.todayPomodoros + 1) 个番茄")
                .font(.system(size: 14))
                .foregroundStyle(theme.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var statusDotColor: Color {
        switch store.phase {
        case .focusing, .breaking: theme.good
        case .pausedFocus, .pausedBreak, .idle: theme.text3
        }
    }

    private var actionsColumn: some View {
        VStack(spacing: 14) {
            switch store.phase {
            case .idle:
                primaryButton("开始") { store.start(taskID: linkedTaskID) }
            case .focusing, .pausedFocus:
                let running = store.phase == .focusing
                primaryButton(running ? "暂停" : "继续") {
                    if running { store.pause() } else { store.resume() }
                }
                HStack(spacing: 22) {
                    linkButton("完成本番茄") { store.finishEarly() }
                    linkButton("放弃") { showGiveUpConfirmation = true }
                }
            case .breaking:
                primaryButton("跳过休息") { _ = store.giveUp() }
            case .pausedBreak:
                HStack(spacing: 22) {
                    primaryButton("继续") { store.resume() }
                    linkButton("跳过休息") { _ = store.giveUp() }
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

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: FocusLayoutMetrics.primaryButtonWidth,
                       height: FocusLayoutMetrics.primaryButtonHeight)
                .background(Capsule().fill(theme.accent))
        }
        .buttonStyle(.plain)
        .focusRenderAnchor(.primaryButton)
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(theme.text2)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private var ringTaskTitle: String? {
        let id = store.phase == .idle ? linkedTaskID : store.currentTaskID
        return taskTitle(for: id)
    }

    private var nextAutoStartTime: String {
        let reference = workspace?.clock() ?? Date()
        return reference.addingTimeInterval(TimeInterval(store.remainingSeconds))
            .formatted(.dateTime.hour().minute())
    }

    private var rhythmPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("节奏")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.text)
                .padding(.bottom, 8)
            rhythmStepper("短休息", value: store.preferences.breakMinutes, unit: "分钟",
                          range: 1...60) { store.setBreakMinutes($0) }
            rhythmStepper("长休息", value: store.preferences.longBreakMinutes, unit: "分钟",
                          range: 1...60) { store.setLongBreakMinutes($0) }
            rhythmStepper("长休息间隔", value: store.preferences.longBreakInterval, unit: "番茄",
                          range: 2...8) { store.setLongBreakInterval($0) }
            HStack {
                Text("休息结束自动开始下一番茄")
                    .foregroundStyle(theme.text2)
                Spacer(minLength: 12)
                SwitchView(isOn: Binding(
                    get: { store.preferences.autoStartNextPomodoro },
                    set: { store.setAutoStartNextPomodoro($0) }))
            }
            .font(.system(size: 15))
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.hairline).frame(height: 1)
            }
            Text("开启后，休息结束时将用同一任务自动开始下一个番茄")
                .font(.system(size: 14))
                .foregroundStyle(theme.text3)
                .padding(.top, 12)
        }
        .padding(22)
        .frame(width: 360)
    }

    private func rhythmStepper(_ key: String, value: Int, unit: String,
                               range: ClosedRange<Int>, setter: @escaping (Int) -> Bool) -> some View {
        HStack(spacing: 10) {
            Text(key).foregroundStyle(theme.text2)
            Spacer(minLength: 12)
            stepperButton("minus") {
                if value > range.lowerBound { _ = setter(value - 1) }
            }
            Text("\(value) \(unit)")
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .frame(width: 88)
            stepperButton("plus") {
                if value < range.upperBound { _ = setter(value + 1) }
            }
        }
        .font(.system(size: 15))
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
    }

    private func stepperButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.text2)
                .frame(width: 26, height: 26)
                .background(Circle().fill(theme.chipBackground))
        }
        .buttonStyle(.plain)
    }

    private var presetChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.timers) { preset in
                    let active = store.preferences.stopwatchMode == preset.stopwatch
                        && (preset.stopwatch || store.preferences.focusMinutes == preset.minutes)
                    HStack(spacing: 8) {
                        Text(preset.emoji)
                            .font(.system(size: 19))
                        Text(preset.name)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(active ? theme.accent : theme.text)
                            .lineLimit(1)
                        Text(preset.stopwatch ? "正计时" : "\(preset.minutes) 分钟")
                            .font(.system(size: 17))
                            .foregroundStyle(theme.text3)
                        Button {
                            store.deleteTimer(preset.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.text3)
                        }
                        .buttonStyle(.plain)
                        .opacity(hoveredPresetID == preset.id ? 1 : 0)
                        .help("删除常用专注")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(active ? theme.accentSoft : theme.chipBackground))
                    .contentShape(Capsule())
                    .onTapGesture { store.applyTimerPreset(preset) }
                    .onHover { hovering in
                        if hovering { hoveredPresetID = preset.id }
                        else if hoveredPresetID == preset.id { hoveredPresetID = nil }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

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

    private func listDotColor(for id: UUID?) -> Color {
        guard let id, let workspace, let task = workspace.task(for: id),
              let argb = workspace.listMetas.first(where: { $0.name == task.list.name })?.colorARGB
        else { return theme.accent }
        return Color(red: Double((argb >> 16) & 0xFF) / 255,
                     green: Double((argb >> 8) & 0xFF) / 255,
                     blue: Double(argb & 0xFF) / 255)
    }

    private func isDueOverdue(_ task: Task) -> Bool {
        guard let workspace, let dueAt = task.schedule.dueAt else { return false }
        return workspace.calendar.startOfDay(for: dueAt)
            < workspace.calendar.startOfDay(for: workspace.clock())
    }
}
