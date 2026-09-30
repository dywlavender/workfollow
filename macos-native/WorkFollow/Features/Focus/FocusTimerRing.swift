import SwiftUI

/// Fixed-size timer face shared by idle, focus, pause and break phases.
struct FocusTimerRing: View {
    @ObservedObject var store: FocusStore
    @ObservedObject var durationEditor: FocusDurationEditorSession
    let theme: FocusTheme
    let taskTitle: String?
    let onEditDuration: (() -> Void)?

    private var progress: CGFloat {
        guard store.phaseSeconds > 0 else { return 0 }
        let value = CGFloat(store.phaseSeconds - store.remainingSeconds) / CGFloat(store.phaseSeconds)
        return min(max(value, 0), 1)
    }

    private var displaySeconds: Int {
        if store.phase == .idle {
            return store.preferences.stopwatchMode ? 0 : store.preferences.focusMinutes * 60
        }
        if store.preferences.stopwatchMode,
           store.phase == .focusing || store.phase == .pausedFocus {
            return store.elapsedSeconds
        }
        return store.remainingSeconds
    }

    private var progressColors: (Color, Color) {
        let isBreak = store.phase == .breaking || store.phase == .pausedBreak
        let start = isBreak ? theme.good : theme.accent
        let end = isBreak ? theme.goodSoft : theme.accentSoft
        let isPaused = store.phase == .pausedFocus || store.phase == .pausedBreak
        return isPaused ? (start.opacity(0.4), end.opacity(0.4)) : (start, end)
    }

    private var progressGradient: AngularGradient {
        let (start, end) = progressColors
        return AngularGradient(colors: [start, end], center: .center,
                               startAngle: .degrees(-90), endAngle: .degrees(270))
    }

    var body: some View {
        let active = store.phase == .focusing || store.phase == .breaking

        ZStack {
            if usesStopwatchDial {
                FocusStopwatchDial(theme: theme)
            } else {
                Circle()
                    .stroke(theme.track,
                            style: StrokeStyle(lineWidth: FocusLayoutMetrics.ringLineWidth))
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(progressGradient,
                            style: StrokeStyle(lineWidth: FocusLayoutMetrics.progressRingLineWidth,
                                               lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: progress)
            }
            ringCenter
        }
        .frame(width: FocusLayoutMetrics.ringSize, height: FocusLayoutMetrics.ringSize)
        .shadow(color: active ? theme.accent.opacity(0.18) : .clear,
                radius: FocusLayoutMetrics.ringShadowRadius)
    }

    private var ringCenter: some View {
        VStack(spacing: FocusLayoutMetrics.ringCenterSpacing) {
            if FocusDurationEditorSession.canEditDuration(
                phase: store.phase, stopwatchMode: store.preferences.stopwatchMode
            ), let onEditDuration {
                Button(action: onEditDuration) {
                    clockLabel
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("focus-duration-trigger")
                .help("点击调整专注时长")
                .focusRenderAnchor(.focusDurationTrigger)
                .focusDurationTriggerAnchor()
            } else {
                clockLabel
            }
            if store.phase == .pausedFocus {
                Text("已暂停")
                    .font(.system(size: FocusLayoutMetrics.phaseFontSize))
                    .foregroundStyle(theme.text2)
                    .focusRenderAnchor(.focusPausedTimerLabel)
            } else if store.phase == .breaking || store.phase == .pausedBreak {
                Text(FocusViewLogic.phaseTitle(for: store.phase, isLongBreak: store.isLongBreak))
                    .font(.system(size: FocusLayoutMetrics.phaseFontSize))
                    .foregroundStyle(theme.text2)
                if let taskTitle {
                    Text(taskTitle)
                        .font(.system(size: 15))
                        .foregroundStyle(theme.text3)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
        }
    }

    private var usesStopwatchDial: Bool {
        guard store.preferences.stopwatchMode else { return false }
        return store.phase == .idle || store.phase == .focusing || store.phase == .pausedFocus
    }

    private var clockLabel: some View {
        Text(FocusViewLogic.clockText(displaySeconds))
            .font(.system(size: FocusLayoutMetrics.timerFontSize, weight: .regular))
            .monospacedDigit()
            .foregroundStyle(theme.text)
            .accessibilityIdentifier("focus-timer-clock")
            .focusRenderAnchor(.focusTimerDigits)
    }
}
