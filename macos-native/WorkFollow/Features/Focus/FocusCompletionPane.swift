import SwiftUI

/// 完成页占据原计时区；右栏继续展示同一条会话的时间轴与笔记。
struct FocusCompletionPane: View {
    @ObservedObject var store: FocusStore
    let workspace: TaskWorkspaceModel?
    @Environment(\.colorScheme) private var scheme
    @State private var recordDraft: FocusRecordDraft?
    @State private var showDurationEditor = false
    @State private var durationDraft: FocusRecordDurationDraft?
    @State private var durationMinuteRange = 5...5
    @State private var isHarvestHovered = false
    @State private var showSavedToast = false
    private var theme: FocusTheme { FocusTheme(scheme) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let record = store.completedRecord {
                    paneHeader
                        .padding(.horizontal, FocusLayoutMetrics.horizontalPadding)
                        .padding(.top, FocusLayoutMetrics.completionHeaderTop)

                    harvestFigure(record)
                        .frame(width: FocusLayoutMetrics.completionFigureSize,
                               height: FocusLayoutMetrics.completionFigureSize)
                        .focusRenderAnchor(.completionFigure)
                        .position(x: geometry.size.width / 2, y: FocusLayoutMetrics.completionFigureCenterY)

                    completionTitle(record)
                        .frame(maxWidth: .infinity)
                        .offset(y: FocusLayoutMetrics.completionTitleTop)

                    completionActions(record)
                        .frame(width: FocusLayoutMetrics.primaryButtonWidth)
                        .frame(maxWidth: .infinity)
                        .offset(y: FocusLayoutMetrics.completionActionsTop)
                        .focusRenderAnchor(.completionActions)

                    if showSavedToast {
                        Text("已保存").font(.system(size: 13)).foregroundStyle(theme.text2)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(theme.chipBackground, in: RoundedRectangle(cornerRadius: 6))
                            .frame(maxWidth: .infinity)
                            .offset(y: min(geometry.size.height - 50, 740))
                            .accessibilityIdentifier("focus-completion-saved")
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .focusRenderAnchor(.completionSummary)
        .sheet(item: $recordDraft) { value in
            FocusRecordEditor(store: store, workspace: workspace, draft: value)
        }
    }

    private var paneHeader: some View {
        HStack {
            Button { store.showPresetLibrary() } label: {
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain).hoverTip("返回常用专注库")
            .accessibilityIdentifier("focus-completion-navigation")
            .focusRenderAnchor(.timerBackToLibrary)
            Spacer()
            BusinessMenu {
                if let record = store.completedRecord {
                    Button("编辑记录") { recordDraft = FocusRecordDraft(record: record) }
                }
                Button("Mini 专注") { FocusPresentationWindows.showMini(store: store) }
                Button("沉浸专注") { FocusPresentationWindows.showImmersive(store: store) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16)).frame(width: 24, height: 28)
            }
            .fixedSize()
            .hoverTip("更多专注操作")
            .accessibilityIdentifier("focus-completion-menu")
        }.foregroundStyle(theme.text2)
    }

    private func harvestFigure(_ record: PomodoroRecord) -> some View {
        ZStack {
            if record.mode == .pomodoro {
                FocusHarvestTomato()
            } else {
                Circle().fill(theme.accent.opacity(0.16))
                    .frame(width: FocusLayoutMetrics.completionTomatoSize,
                           height: FocusLayoutMetrics.completionTomatoSize)
                Image(systemName: "checkmark").font(.system(size: 25, weight: .medium))
                    .foregroundStyle(theme.accent).offset(y: -40)
            }
            Button { openDurationEditor(record) } label: {
                Text(FocusViewLogic.clockText(store.completedDisplaySeconds ?? record.activeSeconds))
                    .font(.system(size: FocusLayoutMetrics.completionClockFontSize, weight: .semibold))
                    .monospacedDigit().foregroundStyle(record.mode == .pomodoro ? .white : theme.text)
                    .frame(width: 122, height: 42)
            }
            .buttonStyle(.plain).help("编辑专注时长")
            .accessibilityIdentifier("focus-completed-edit-duration")
            .focusRenderAnchor(.editCompletedDuration)
            .background(AnchoredPropertyPanel(isPresented: $showDurationEditor,
                                               width: FocusLayoutMetrics.completionPopoverWidth) {
                durationEditor(record)
            })

            if store.isTrackingPendingExtraTime {
                Button {
                    if store.appendCompletionExtraTime() {
                        showSavedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showSavedToast = false }
                    }
                } label: {
                    Text("+" + FocusViewLogic.clockText(store.availableExtraSeconds))
                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .overlay(Capsule().stroke(.white.opacity(0.85),
                                                 style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                }
                .buttonStyle(.plain).offset(y: 34)
                .disabled(store.availableExtraSeconds == 0)
                .opacity(isHarvestHovered ? 1 : 0).allowsHitTesting(isHarvestHovered)
                .help("点击即可添加到专注时长")
                .accessibilityIdentifier("focus-pending-extra-append")
            }
        }
        .contentShape(Rectangle()).onHover { isHarvestHovered = $0 }
    }

    private func completionTitle(_ record: PomodoroRecord) -> some View {
        VStack(spacing: 12) {
            Text(record.mode == .pomodoro ? "你刚收获了一个番茄" : "本次专注已完成")
                .font(.system(size: FocusLayoutMetrics.completionTitleFontSize, weight: .semibold))
                .foregroundStyle(theme.text).focusRenderAnchor(.completionTitle)
            Text(completionSubtitle(record))
                .font(.system(size: FocusLayoutMetrics.completionSubtitleFontSize))
                .foregroundStyle(theme.text2)
        }
    }

    private func completionSubtitle(_ record: PomodoroRecord) -> String {
        if store.completionContext?.extraTimeStartedAt != nil {
            return "追加专注中 " + FocusViewLogic.clockText(store.availableExtraSeconds)
        }
        if store.phase == .breaking || store.phase == .pausedBreak {
            return store.presentation.phaseTitle + " " + FocusViewLogic.clockText(store.remainingSeconds)
        }
        if store.pendingBreak { return "休息 \(store.isLongBreak ? store.preferences.longBreakMinutes : store.preferences.breakMinutes) 分钟吧" }
        return record.mode == .stopwatch ? "已记录本次专注时长" : "本次专注已保存"
    }

    private func completionActions(_ record: PomodoroRecord) -> some View {
        VStack(spacing: FocusLayoutMetrics.completionActionGap) {
            if store.pendingBreak {
                actionButton("开始休息", prominent: true) { _ = store.startBreak() }
                    .accessibilityIdentifier("focus-completion-start-break").focusRenderAnchor(.completionStartBreak)
                actionButton("跳过休息") { _ = store.skipBreak() }
                    .accessibilityIdentifier("focus-completion-skip-break").focusRenderAnchor(.completionSkipBreak)
            } else if store.phase == .breaking || store.phase == .pausedBreak {
                actionButton(store.phase == .pausedBreak ? "继续休息" : "暂停休息", prominent: true) {
                    if store.phase == .pausedBreak { _ = store.resume() } else { _ = store.pause() }
                }.accessibilityIdentifier("focus-completion-toggle-break")
                actionButton("跳过休息") { _ = store.skipBreak() }
                    .accessibilityIdentifier("focus-completion-skip-break").focusRenderAnchor(.completionSkipBreak)
            } else if store.completionContext?.extraTimeStartedAt != nil {
                actionButton("保存追加时间", prominent: true) { _ = store.appendCompletionExtraTime() }
                    .accessibilityIdentifier("focus-extra-save")
            } else if store.completionContext?.tracksPendingExtraTime != true {
                actionButton("继续专注并追加", prominent: true) { _ = store.startCompletionExtraTime() }
                    .accessibilityIdentifier("focus-extra-start")
            }
            actionButton("退出") { store.dismissCompletion(); store.showPresetLibrary(); store.showOverview() }
                .accessibilityIdentifier("focus-completion-exit").focusRenderAnchor(.completionExit)
        }
    }

    private func actionButton(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        let completionAccent = Color(red: 0, green: 0.79, blue: 0.61)
        return Button(action: action) {
            Text(title).font(.system(size: 14))
                .foregroundStyle(prominent ? Color.white : completionAccent)
                .frame(width: FocusLayoutMetrics.primaryButtonWidth, height: FocusLayoutMetrics.primaryButtonHeight)
                .background(prominent ? completionAccent : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(completionAccent, lineWidth: prominent ? 0 : 1))
        }.buttonStyle(.plain)
    }

    private func openDurationEditor(_ record: PomodoroRecord) {
        durationMinuteRange = FocusRecordDurationDraft.completionMinuteRange(record: record,
                                                                            pendingExtraSeconds: store.availableExtraSeconds)
        let shownMinutes = record.mode == .pomodoro
            ? (store.completedDisplaySeconds ?? record.activeSeconds) / 60 : record.minutes
        durationDraft = FocusRecordDurationDraft(record: record,
            displayedMinutes: min(durationMinuteRange.upperBound, max(durationMinuteRange.lowerBound, shownMinutes)),
            alignsEndWithDuration: record.mode == .pomodoro)
        showDurationEditor = true
    }

    private func durationEditor(_ record: PomodoroRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("专注时长").font(.system(size: 13))
                Spacer()
                BusinessPicker("分钟", selection: durationMinutesBinding, options:
                    durationMinuteRange.map { BusinessChoice($0, "\($0) 分钟") }).labelsHidden().frame(width: 96)
                    .accessibilityIdentifier("focus-completed-duration-minutes")
            }
            Text(durationPreview(record)).font(.system(size: 12)).foregroundStyle(theme.text2)
                .accessibilityIdentifier("focus-completed-duration-preview")
            HStack {
                Spacer()
                Button("取消") { durationDraft = nil; showDurationEditor = false }
                    .accessibilityIdentifier("focus-completed-duration-cancel")
                Button("保存") {
                    if let durationDraft, store.saveRecordDurationDraft(durationDraft) {
                        self.durationDraft = nil; showDurationEditor = false
                    }
                }.buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("focus-completed-duration-save")
            }
        }
        .padding(16).frame(width: FocusLayoutMetrics.completionPopoverWidth)
        .focusRenderAnchor(.completedDurationPopover)
    }

    private func durationPreview(_ record: PomodoroRecord) -> String {
        let start = FocusViewLogic.timeLabel(for: record.startedAt, calendar: store.presentationCalendar)
        let end: Date?
        if let durationDraft, durationDraft.alignsEndWithDuration {
            end = durationDraft.previewEnd(startedAt: record.startedAt)
        } else { end = record.endedAt }
        return "专注时长：" + start + " - " + (end.map {
            FocusViewLogic.timeLabel(for: $0, calendar: store.presentationCalendar)
        } ?? "未知")
    }

    private var durationMinutesBinding: Binding<Int> {
        Binding(get: { durationDraft?.minutes ?? durationMinuteRange.lowerBound },
                set: { durationDraft?.minutes = $0 })
    }
}

/// 原生路径绘制的完成番茄，未使用参考客户端的图片资源。
private struct FocusHarvestTomato: View {
    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for index in 0...32 {
                    let angle = Double(index) / 32 * .pi - .pi / 2
                    let outer = size.width / 2
                    let inner = outer - (index.isMultiple(of: 4) ? 8.0 : 5.0)
                    var tick = Path()
                    tick.move(to: CGPoint(x: center.x + CGFloat(cos(angle)) * inner, y: center.y + CGFloat(sin(angle)) * inner))
                    tick.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * outer, y: center.y + CGFloat(sin(angle)) * outer))
                    context.stroke(tick, with: .color(Color(red: 1, green: 0.70, blue: 0.47)), lineWidth: 1)
                }
            }
            HarvestTomatoBody()
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.75, blue: 0.57),
                                              Color(red: 1, green: 0.58, blue: 0.63)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: FocusLayoutMetrics.completionTomatoSize, height: FocusLayoutMetrics.completionTomatoSize)
                .offset(y: 4)
            HarvestTomatoLeaf().fill(Color(red: 0.30, green: 0.76, blue: 0.67))
                .frame(width: 48, height: 29).offset(y: -56)
            Image(systemName: "sparkle").font(.system(size: 15, weight: .light))
                .foregroundStyle(Color(red: 1, green: 0.77, blue: 0.49)).offset(x: -76, y: -61)
        }
    }
}

private struct HarvestTomatoBody: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.12))
        p.addCurve(to: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.midY),
                   control1: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.minY - rect.height * 0.04),
                   control2: CGPoint(x: rect.minX - rect.width * 0.02, y: rect.minY + rect.height * 0.20))
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                   control1: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.maxY - rect.height * 0.10),
                   control2: CGPoint(x: rect.midX - rect.width * 0.19, y: rect.maxY))
        p.addCurve(to: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.midY),
                   control1: CGPoint(x: rect.midX + rect.width * 0.19, y: rect.maxY),
                   control2: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.maxY - rect.height * 0.10))
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.12),
                   control1: CGPoint(x: rect.maxX + rect.width * 0.02, y: rect.minY + rect.height * 0.20),
                   control2: CGPoint(x: rect.maxX - rect.width * 0.15, y: rect.minY - rect.height * 0.04))
        p.closeSubpath(); return p
    }
}

private struct HarvestTomatoLeaf: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.width * 0.49, y: rect.height * 0.44))
        p.addQuadCurve(to: CGPoint(x: rect.width * 0.23, y: 0), control: CGPoint(x: rect.width * 0.43, y: 0))
        p.addLine(to: CGPoint(x: rect.width * 0.27, y: rect.height * 0.42))
        p.addLine(to: CGPoint(x: 0, y: rect.height * 0.35))
        p.addQuadCurve(to: CGPoint(x: rect.width * 0.31, y: rect.height * 0.75),
                       control: CGPoint(x: rect.width * 0.05, y: rect.height * 0.78))
        p.addLine(to: CGPoint(x: rect.width * 0.20, y: rect.height))
        p.addLine(to: CGPoint(x: rect.width * 0.51, y: rect.height * 0.84))
        p.addLine(to: CGPoint(x: rect.width * 0.82, y: rect.height))
        p.addLine(to: CGPoint(x: rect.width * 0.71, y: rect.height * 0.75))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.height * 0.35),
                       control: CGPoint(x: rect.width * 0.95, y: rect.height * 0.78))
        p.addLine(to: CGPoint(x: rect.width * 0.63, y: rect.height * 0.44))
        p.addLine(to: CGPoint(x: rect.width * 0.82, y: rect.height * 0.14))
        p.closeSubpath(); return p
    }
}
