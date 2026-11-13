import AppKit
import SwiftUI

struct SettingsShortcutsView: View {
    @ObservedObject var store: AppShortcutStore
    var quickAdd: GlobalQuickAddController? = nil
    @State private var recording: AppShortcutAction?
    @State private var error: String?

    var body: some View {
        SettingsPage {
            HStack {
                Text("快捷键").font(WFType.detailTitle)
                Spacer()
                Button("恢复默认", action: restoreDefaults).disabled(store.overrides.isEmpty)
            }
            if let error {
                Text(error).font(WFType.supporting).foregroundStyle(WFColors.danger)
            }
            ForEach(AppShortcutAction.Group.allCases, id: \.self) { group in
                let actions = AppShortcutAction.allCases.filter { $0.definition.group == group }
                SettingsGroup(group.rawValue) {
                    ForEach(actions) { action in
                        WFFormRow(action.title, showsDivider: action != actions.last) {
                            Button {
                                if recording == action { stopRecording() }
                                else {
                                    error = nil
                                    recording = action
                                    quickAdd?.setShortcutRecording(true)
                                }
                            } label: {
                                Text(recording == action ? "按下快捷键" : store.chord(for: action).label)
                                    .frame(minWidth: 88)
                            }
                            .controlSize(.small)
                            .accessibilityLabel("更改\(action.title)快捷键")
                            .accessibilityValue(recording == action ? "正在录制" : store.chord(for: action).label)
                            .accessibilityIdentifier("shortcut.\(action.rawValue)")
                            .help(recording == action ? "按 Esc 取消" : "点击后按下新的快捷键")
                        }
                    }
                }
            }
        }
        .background(ShortcutKeyRecorder(receive: recording == nil ? nil : record))
        .onDisappear { stopRecording() }
    }

    private var applyGlobal: ((AppShortcutChord) -> Bool)? {
        guard let quickAdd else { return nil }
        return { quickAdd.rebindShortcut($0) }
    }

    private func record(_ event: NSEvent) {
        guard let action = recording, !event.isARepeat else { return }
        if event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            stopRecording()
            return
        }
        guard let chord = AppShortcutChord(event: event) else { return }
        do {
            try store.set(chord, for: action, applyGlobal: applyGlobal)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        stopRecording()
    }

    private func stopRecording() {
        recording = nil
        quickAdd?.setShortcutRecording(false)
    }

    private func restoreDefaults() {
        stopRecording()
        do {
            try store.restoreDefaults(applyGlobal: applyGlobal)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ShortcutKeyRecorder: NSViewRepresentable {
    let receive: ((NSEvent) -> Void)?

    func makeNSView(context: Context) -> RecorderView { RecorderView() }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.receive = receive
    }

    static func dismantleNSView(_ view: RecorderView, coordinator: Void) { view.receive = nil }

    final class RecorderView: NSView {
        var receive: ((NSEvent) -> Void)? { didSet { updateMonitor() } }
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateMonitor()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func updateMonitor() {
            if receive == nil || window == nil {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            } else if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, let window = self.window, window.isKeyWindow,
                          event.window === window, let receive = self.receive else { return event }
                    receive(event)
                    return nil
                }
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
