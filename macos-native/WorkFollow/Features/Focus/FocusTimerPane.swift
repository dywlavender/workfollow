import SwiftUI

/// Left Focus Pane. Core geometry is fixed in points; only its containing pane width responds.
struct FocusTimerPane: View {
    @ObservedObject var store: FocusStore
    let workspace: TaskWorkspaceModel?
    @ObservedObject var taskPicker: FocusTaskPickerSession
    @Binding var showGiveUpConfirmation: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var showRhythmPopover = false
    @StateObject private var durationEditor = FocusDurationEditorSession()

    private var theme: FocusTheme { FocusTheme(colorScheme) }
    private var isActiveFocus: Bool {
        store.phase == .focusing || store.phase == .pausedFocus
    }

    var body: some View {
        Group {
            if store.completionContext != nil {
                FocusCompletionPane(store: store, workspace: workspace)
            } else {
                VStack(spacing: 0) {
                    paneHeader
                    timerStage(hasPresetChips: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    actionsColumn
                        .frame(maxWidth: .infinity)
                        .frame(height: FocusLayoutMetrics.footerHeight, alignment: .top)
                }
                .padding(.horizontal, FocusLayoutMetrics.horizontalPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusDurationPopover(session: durationEditor,
                              onConfirm: { store.setFocusMinutes($0) })
        .onChange(of: store.phase) { _, phase in
            if phase == .idle { taskPicker.linkedTaskID = store.preferences.lastTaskID }
        }
        .onChange(of: store.preferences.lastTaskID) { _, taskID in
            if store.phase == .idle { taskPicker.linkedTaskID = taskID }
        }
    }

    private var paneHeader: some View {
        ZStack {
            HStack(spacing: 0) {
                Button { store.showPresetLibrary() } label: {
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .medium))
                        .frame(width: 24, height: FocusLayoutMetrics.headerButtonSize)
                }
                .buttonStyle(.plain).foregroundStyle(theme.text2).hoverTip("返回常用专注库")
                .accessibilityIdentifier("focus-timer-back-library").focusRenderAnchor(.timerBackToLibrary)
                Spacer(minLength: 0)
                headerIcons
            }

            if store.phase == .idle {
                modeSegment
                    .focusRenderAnchor(.focusModeSegment)
            }
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
            BusinessMenu {
                ForEach(FocusBell.allCases, id: \.self) { bell in
                    BusinessMenuOption(bell.rawValue, selected: store.preferences.bell == bell) { store.setBell(bell.rawValue) }
                }
            } label: {
                Image(systemName: bellIcon)
                    .font(.system(size: FocusLayoutMetrics.headerIconSize))
                    .frame(width: FocusLayoutMetrics.headerButtonSize,
                           height: FocusLayoutMetrics.headerButtonSize)
                    .contentShape(Rectangle())
            }


            .foregroundStyle(theme.text2)
            .hoverTip("结束铃声：\(currentBellLabel)")

            Button { showRhythmPopover = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: FocusLayoutMetrics.headerIconSize, weight: .medium))
                    .frame(width: FocusLayoutMetrics.headerButtonSize,
                           height: FocusLayoutMetrics.headerButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text2)
            .hoverTip("节奏设置")
            .background(AnchoredPropertyPanel(isPresented: $showRhythmPopover, width: PopupMetrics.rhythmPopoverWidth) {
                rhythmPopover
            })
        }
    }

    private var bellIcon: String {
        store.preferences.bell == .off
            ? "speaker.slash" : "speaker.wave.2"
    }

    private var currentBellLabel: String {
        store.preferences.bell.rawValue
    }

    private func timerStage(hasPresetChips: Bool) -> some View {
        VStack(spacing: 0) {
            selectorRow
                .frame(height: FocusLayoutMetrics.focusLabelHeight)
                .padding(.top, FocusLayoutMetrics.selectorTopPadding(hasPresetChips: hasPresetChips))

            FocusTimerRing(store: store, durationEditor: durationEditor,
                           theme: theme, taskTitle: ringTaskTitle,
                           onEditDuration: {
                               durationEditor.present(currentMinutes: store.preferences.focusMinutes)
                           })
                .focusRenderAnchor(.timerRing)
                .padding(.top, FocusLayoutMetrics.ringTopGap)

            if store.phase != .idle && !isActiveFocus {
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
            let linkID = store.phase == .idle ? taskPicker.linkedTaskID : store.currentTaskID
            let boundTask = linkID.flatMap { workspace.task(for: $0) }
            let preset = store.currentSessionPresetID.flatMap { id in store.timers.first { $0.id == id } }
            let title = preset?.name ?? boundTask.map { $0.title.isEmpty ? "未命名任务" : $0.title }
            let overdue = boundTask.map { isDueOverdue($0) } ?? false

            Button {
                taskPicker.present()
            } label: {
                HStack(spacing: 8) {
                    if let boundTask, preset == nil {
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
            .buttonStyle(.plain)
            .fixedSize()
            .help("选择一个任务并开始专注")
            .background(AnchoredPropertyPanel(
                isPresented: taskPicker.presentationBinding,
                width: FocusTaskPickerMetrics.width,
                focusPolicy: .panel
            ) {
                FocusTaskPickerPopover(
                    workspace: workspace,
                    selectedTaskID: linkID,
                    scope: $taskPicker.scope,
                    query: $taskPicker.query,
                    isScopePickerPresented: taskPicker.scopePickerBinding,
                    onSelectScope: { taskPicker.selectScope($0) },
                    onSelectTask: { assignFocusTask($0.id) },
                    onClearTask: { assignFocusTask(nil) }
                )
            })
        }
    }

    private func assignFocusTask(_ taskID: UUID?) {
        if store.phase == .idle {
            taskPicker.selectTask(taskID)
        } else {
            _ = store.reattach(taskID: taskID)
            taskPicker.dismiss()
        }
    }

    private var runningStatus: some View {
        HStack(spacing: FocusLayoutMetrics.statusSpacing) {
            Circle()
                .fill(statusDotColor)
                .frame(width: FocusLayoutMetrics.statusDotSize,
                       height: FocusLayoutMetrics.statusDotSize)
            Text(store.presentation.phaseTitle)
                .font(.system(size: 14))
                .foregroundStyle(theme.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .focusRenderAnchor(.focusRunningStatus)
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
                if store.completionContext?.extraTimeStartedAt != nil {
                    primaryButton("保存追加时间") { _ = store.appendCompletionExtraTime() }
                } else if store.pendingBreak {
                    primaryButton("开始休息") { _ = store.startBreak() }
                    linkButton("跳过休息") { _ = store.skipBreak() }
                    linkButton("退出") { store.dismissCompletion(); store.showOverview() }
                } else {
                    primaryButton("开始") { store.start(taskID: taskPicker.linkedTaskID) }
                }
            case .focusing:
                outlineButton("暂停") { store.pause() }
                    .focusRenderAnchor(.focusPauseButton)
                HStack(spacing: 24) {
                    linkButton("结束") { _ = store.perform(.end) }
                    linkButton("放弃专注") { showGiveUpConfirmation = true }
                }
            case .pausedFocus:
                VStack(spacing: 14) {
                    primaryButton("继续") { store.resume() }
                        .focusRenderAnchor(.focusResumeButton)
                    outlineButton("结束") { _ = store.perform(.end) }
                        .focusRenderAnchor(.focusEndButton)
                }
            case .breaking:
                primaryButton("跳过休息") { _ = store.skipBreak() }
                linkButton("暂停休息") { _ = store.pause() }
            case .pausedBreak:
                HStack(spacing: 22) {
                    primaryButton("继续") { store.resume() }
                    linkButton("跳过休息") { _ = store.skipBreak() }
                }
            }
        }
        .confirmationDialog("确定要放弃本次专注吗？",
                            isPresented: $showGiveUpConfirmation,
                            titleVisibility: .visible) {
            Button("放弃专注", role: .destructive) { _ = store.giveUp() }
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

    private func outlineButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: FocusLayoutMetrics.primaryButtonWidth,
                       height: FocusLayoutMetrics.primaryButtonHeight)
                .background(Capsule().fill(theme.canvas))
                .overlay(Capsule().stroke(theme.accent, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
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
        let id = store.phase == .idle ? taskPicker.linkedTaskID : store.currentTaskID
        return taskTitle(for: id)
    }

    private var nextAutoStartTime: String {
        FocusViewLogic.timeLabel(for: store.currentTime.addingTimeInterval(TimeInterval(store.remainingSeconds)),
                                 calendar: store.presentationCalendar)
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
                Text("专注结束自动开始休息").foregroundStyle(theme.text2)
                Spacer(minLength: 12)
                SwitchView(isOn: Binding(get: { store.preferences.autoStartBreak },
                    set: { store.setAutoStartBreak($0) }), accessibilityTitle: "自动开始休息")
            }.font(.system(size: 15)).padding(.vertical, 12)
            rhythmStepper("自动轮数", value: store.preferences.automaticCycleLimit, unit: "轮",
                          range: 0...12) { store.setAutomaticCycleLimit($0) }
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
            Text("自动轮数 0 表示持续；休息结束后使用下次配置开始。")
                .font(.system(size: 14))
                .foregroundStyle(theme.text3)
                .padding(.top, 12)
            Divider().padding(.top, 14)
            HStack(spacing: 18) {
                Button("Mini 专注") { FocusPresentationWindows.showMini(store: store) }
                Button("沉浸专注") { FocusPresentationWindows.showImmersive(store: store) }
            }.buttonStyle(.plain).foregroundStyle(theme.accent).padding(.top, 14)
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
        .hoverTip(symbol == "plus" ? "增加" : "减少")
    }

    private func taskTitle(for id: UUID?) -> String? {
        guard let id, let workspace, let task = workspace.task(for: id) else { return nil }
        return task.title.isEmpty ? "未命名任务" : task.title
    }

    private func listDotColor(for id: UUID?) -> Color {
        guard let id, let workspace, let task = workspace.task(for: id),
              task.list.name != TaskList.inbox.name else { return theme.accent }
        return WFPlanningPalette.listColor(name: task.list.name,
                                           meta: workspace.listMeta(for: task.list.name))
    }

    private func isDueOverdue(_ task: Task) -> Bool {
        guard let workspace, let dueAt = task.schedule.dueAt else { return false }
        return workspace.calendar.startOfDay(for: dueAt)
            < workspace.calendar.startOfDay(for: workspace.clock())
    }
}
