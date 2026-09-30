import SwiftUI

/// Draft state for the idle focus-duration editor. Changes reach FocusStore only on confirm.
@MainActor
final class FocusDurationEditorSession: ObservableObject {
    @Published private(set) var isPresented = false
    @Published var draftText = "25"

    var parsedMinutes: Int? {
        guard let value = Int(draftText.trimmingCharacters(in: .whitespacesAndNewlines)),
              PomodoroSettings.focusRange.contains(value) else { return nil }
        return value
    }

    var canConfirm: Bool { parsedMinutes != nil }

    var presentationBinding: Binding<Bool> {
        Binding(get: { self.isPresented },
                set: { if !$0 { self.cancel() } })
    }

    var stepperBinding: Binding<Int> {
        Binding(get: { self.parsedMinutes ?? PomodoroSettings.focusRange.lowerBound },
                set: { self.draftText = String($0) })
    }

    func present(currentMinutes: Int) {
        let minutes = PomodoroSettings.focusRange.contains(currentMinutes) ? currentMinutes : 25
        draftText = String(minutes)
        isPresented = true
    }

    func cancel() {
        isPresented = false
    }

    @discardableResult
    func confirm(apply: (Int) -> Bool) -> Bool {
        guard let minutes = parsedMinutes, apply(minutes) else { return false }
        isPresented = false
        return true
    }

    static func canEditDuration(phase: PomodoroPhase, stopwatchMode: Bool) -> Bool {
        phase == .idle && !stopwatchMode
    }
}

struct FocusDurationPopover: View {
    @ObservedObject var session: FocusDurationEditorSession
    let onConfirm: (Int) -> Bool
    @Environment(\.colorScheme) private var colorScheme

    private var theme: FocusTheme { FocusTheme(colorScheme) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("25", text: $session.draftText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .frame(width: 62, height: 30)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.hairline, lineWidth: 1))
                    .accessibilityIdentifier("focus-duration-minutes")

                Stepper("调整分钟", value: session.stepperBinding,
                        in: PomodoroSettings.focusRange)
                    .labelsHidden()
                    .accessibilityIdentifier("focus-duration-stepper")

                Text("分钟")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.text2)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("取消") { session.cancel() }
                    .buttonStyle(durationButtonStyle(isPrimary: false))
                    .accessibilityIdentifier("focus-duration-cancel")
                Button("确定") { _ = session.confirm(apply: onConfirm) }
                    .buttonStyle(durationButtonStyle(isPrimary: true))
                    .disabled(!session.canConfirm)
                    .accessibilityIdentifier("focus-duration-confirm")
            }
        }
        .padding(12)
        .frame(width: 232, height: 104)
        .background(theme.canvas, in: RoundedRectangle(cornerRadius: 12))
        .onExitCommand { session.cancel() }
    }

    private func durationButtonStyle(isPrimary: Bool) -> some ButtonStyle {
        DurationButtonStyle(theme: theme, isPrimary: isPrimary)
    }
}

private struct DurationButtonStyle: ButtonStyle {
    let theme: FocusTheme
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isPrimary ? Color.white : theme.text2)
            .frame(width: 72, height: 30)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isPrimary ? theme.accent : theme.canvas)
                    .overlay {
                        if !isPrimary {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(theme.hairline, lineWidth: 1)
                        }
                    }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
