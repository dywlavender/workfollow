import SwiftUI

/// Fixed-size timer face shared by idle, focus, pause and break phases.
struct FocusTimerRing: View {
    @ObservedObject var store: FocusStore
    let theme: FocusTheme
    let taskTitle: String?

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
        let stopwatch = store.preferences.stopwatchMode

        ZStack {
            Circle()
                .stroke(theme.track,
                        style: stopwatch
                            ? StrokeStyle(lineWidth: FocusLayoutMetrics.ringLineWidth, dash: [2.5, 5])
                            : StrokeStyle(lineWidth: FocusLayoutMetrics.ringLineWidth))
            Circle()
                .trim(from: 0, to: progress)
                .stroke(progressGradient,
                        style: StrokeStyle(lineWidth: FocusLayoutMetrics.progressRingLineWidth,
                                           lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: progress)
            ringCenter
        }
        .frame(width: FocusLayoutMetrics.ringSize, height: FocusLayoutMetrics.ringSize)
        .shadow(color: active ? theme.accent.opacity(0.18) : .clear,
                radius: FocusLayoutMetrics.ringShadowRadius)
    }

    private var ringCenter: some View {
        VStack(spacing: FocusLayoutMetrics.ringCenterSpacing) {
            Text(FocusViewLogic.clockText(displaySeconds))
                .font(.system(size: FocusLayoutMetrics.timerFontSize, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(theme.text)
            if store.phase != .idle {
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
}
