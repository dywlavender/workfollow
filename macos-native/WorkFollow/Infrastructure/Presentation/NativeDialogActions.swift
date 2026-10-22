import AppKit

@MainActor
enum NativeDialogActions {
    /// Preserve NSAlert's response order while giving Escape an explicit cancel
    /// action. Destructive confirmations default to cancel on Return as well.
    static func configure(_ alert: NSAlert, primary: NSButton, cancel: NSButton,
                          destructive: Bool = false) {
        cancel.keyEquivalent = "\u{1b}"
        primary.hasDestructiveAction = destructive
        primary.keyEquivalent = destructive ? "" : "\r"
        alert.window.defaultButtonCell = (destructive ? cancel : primary).cell as? NSButtonCell
        alert.window.appearance = NSApp.keyWindow?.effectiveAppearance
    }

    static func runModal(_ alert: NSAlert, cancel: NSButton) -> NSApplication.ModalResponse {
        // AppKit gives each button one key equivalent. Keep Cancel reachable
        // through Escape and the declared default through Return in this modal
        // session, then remove the observer before returning to the editor.
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated {
                guard [36, 53, 76].contains(event.keyCode), event.window === alert.window,
                      NSApp.modalWindow === alert.window else { return false }
                if let input = alert.window.firstResponder as? NSTextView {
                    if input.hasMarkedText() { return false }
                    if event.keyCode != 53 && !input.isFieldEditor { return false }
                }
                if event.keyCode == 53 { cancel.performClick(nil) }
                else {
                    guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                          let button = alert.window.defaultButtonCell?.controlView as? NSButton else { return false }
                    alert.window.makeFirstResponder(nil)
                    button.performClick(nil)
                }
                return true
            }
            return handled ? nil : event
        }
        defer { if let monitor { NSEvent.removeMonitor(monitor) } }
        return alert.runModal()
    }
}
