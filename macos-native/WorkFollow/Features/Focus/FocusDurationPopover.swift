import AppKit
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
    @FocusState private var minutesFieldFocused: Bool

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
                    .focused($minutesFieldFocused)

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
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.14),
                radius: 14, x: 0, y: 5)
        .onAppear {
            // The timer digits open an editor prefilled with the current value.
            // Select that value so typing a replacement doesn't append to it
            // and silently leave the Confirm button disabled (for example 25 → 2530).
            DispatchQueue.main.async {
                minutesFieldFocused = true
                DispatchQueue.main.async {
                    (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil)
                }
            }
        }
        .background(PopupEscapeRouter(depth: 1) { session.cancel() })
        .onExitCommand { session.cancel() }
    }

    private func durationButtonStyle(isPrimary: Bool) -> some ButtonStyle {
        DurationButtonStyle(theme: theme, isPrimary: isPrimary)
    }
}

private struct FocusDurationTriggerAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

extension View {
    func focusDurationTriggerAnchor() -> some View {
        anchorPreference(key: FocusDurationTriggerAnchorKey.self, value: .bounds) { $0 }
    }

    func focusDurationPopover(session: FocusDurationEditorSession,
                              onConfirm: @escaping (Int) -> Bool) -> some View {
        modifier(FocusDurationPopoverPresenter(session: session, onConfirm: onConfirm))
    }
}

private struct FocusDurationPopoverPresenter: ViewModifier {
    @ObservedObject var session: FocusDurationEditorSession
    let onConfirm: (Int) -> Bool

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(FocusDurationTriggerAnchorKey.self) { anchor in
            GeometryReader { geometry in
                if session.isPresented, let anchor {
                    let trigger = geometry[anchor]
                    let panelWidth: CGFloat = 232
                    let panelHeight: CGFloat = 104
                    let gap: CGFloat = 12
                    let belowY = trigger.maxY + gap + panelHeight / 2
                    let aboveY = trigger.minY - gap - panelHeight / 2
                    let fitsBelow = belowY + panelHeight / 2 <= geometry.size.height - 8
                    let proposedY = fitsBelow ? belowY : aboveY
                    let centerY = min(max(proposedY, panelHeight / 2 + 8),
                                      geometry.size.height - panelHeight / 2 - 8)
                    let centerX = min(max(trigger.midX, panelWidth / 2 + 8),
                                      geometry.size.width - panelWidth / 2 - 8)
                    let panelFrame = CGRect(x: centerX - panelWidth / 2,
                                            y: centerY - panelHeight / 2,
                                            width: panelWidth, height: panelHeight)

                    FocusDurationPopover(session: session, onConfirm: onConfirm)
                        .frame(width: panelWidth, height: panelHeight)
                        .background {
                            FocusOutsideClickObserver { session.cancel() }
                        }
                        .position(x: centerX, y: centerY)
                        .preference(key: FocusRenderFramesPreferenceKey.self,
                                    value: [.focusDurationPopover: panelFrame])
                }
            }
        }
    }
}

/// The panel owns this observer; its AppKit window and bounds are the source of truth.
/// It observes clicks across that window, including Overview, without consuming them.
struct FocusOutsideClickObserver: NSViewRepresentable {
    let onOutsideClick: () -> Void

    func makeNSView(context: Context) -> FocusDurationOutsideClickView {
        let view = FocusDurationOutsideClickView()
        view.onOutsideClick = onOutsideClick
        return view
    }

    func updateNSView(_ view: FocusDurationOutsideClickView, context: Context) {
        view.onOutsideClick = onOutsideClick
    }

    static func dismantleNSView(_ view: FocusDurationOutsideClickView, coordinator: ()) {
        view.invalidate()
    }
}

@MainActor
final class FocusDurationOutsideClickView: NSView {
    var onOutsideClick: (() -> Void)?
    private var registration: UUID?
    var isMonitoring: Bool { registration != nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard let window else { return }
        registration = PopupInteractionRegistry.shared.register(window: window, contains: { [weak self] event in
            self?.containsMouseDown(event) ?? true
        }, dismiss: { [weak self] in self?.onOutsideClick?() })
    }

    /// Always return the original event so the clicked control can act normally.
    func routeMouseDown(_ event: NSEvent) -> NSEvent {
        guard isMonitoring, window != nil,
              !isHiddenOrHasHiddenAncestor, !bounds.isEmpty else { return event }
        if !containsMouseDown(event) { onOutsideClick?() }
        return event
    }

    private func containsMouseDown(_ event: NSEvent) -> Bool {
        guard !isHiddenOrHasHiddenAncestor, !bounds.isEmpty else { return true }
        return event.window === window && bounds.contains(convert(event.locationInWindow, from: nil))
    }

    func invalidate() {
        stopMonitoring()
        onOutsideClick = nil
    }

    private func stopMonitoring() {
        if let registration { PopupInteractionRegistry.shared.unregister(registration) }
        registration = nil
    }

    deinit {
        if let registration {
            MainActor.assumeIsolated { PopupInteractionRegistry.shared.unregister(registration) }
        }
    }
}

private struct DurationButtonStyle: ButtonStyle {
    let theme: FocusTheme
    let isPrimary: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isPrimary ? Color.white.opacity(isEnabled ? 1 : 0.55) : theme.text2)
            .frame(width: 72, height: 30)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isPrimary
                          ? (isEnabled ? theme.accent : theme.accent.opacity(0.35))
                          : theme.canvas)
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
