import AppKit
import SwiftUI

/// Native single-click editing; modifier clicks remain owned by row selection.
struct TaskRowTitleField: NSViewRepresentable {
    let title: String
    let color: Color
    let onSelect: () -> Void
    let onCommit: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> Field {
        let field = Field(string: title)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.placeholderString = "无标题"
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("行内任务标题")
        field.delegate = context.coordinator
        field.onSelect = { [weak coordinator = context.coordinator] in coordinator?.parent.onSelect() }
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        field.textColor = NSColor(color)
        if field.currentEditor() == nil { field.stringValue = title }
    }

    final class Field: NSTextField {
        var onSelect: (() -> Void)?
        private var outsideClickMonitor: Any?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            if NSApp.currentEvent?.modifierFlags.intersection([.command, .shift]).isEmpty == false {
                return nil
            }
            return super.hitTest(point)
        }
        override func mouseDown(with event: NSEvent) {
            onSelect?()
            if outsideClickMonitor == nil {
                outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    guard let self, self.currentEditor() != nil else { return event }
                    let point = self.convert(event.locationInWindow, from: nil)
                    let modifierSelection = !event.modifierFlags.intersection([.command, .shift]).isEmpty
                    if event.window !== self.window || !self.bounds.contains(point) || modifierSelection {
                        self.window?.makeFirstResponder(nil)
                    }
                    // Observing dismissal must never consume the target click.
                    return event
                }
            }
            super.mouseDown(with: event)
        }
        func stopObserving() {
            if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
            outsideClickMonitor = nil
        }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { stopObserving() }
            super.viewWillMove(toWindow: newWindow)
        }
        deinit { if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) } }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TaskRowTitleField
        private var cancelled = false
        init(parent: TaskRowTitleField) { self.parent = parent }
        func controlTextDidBeginEditing(_ notification: Notification) { cancelled = false }
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            (field as? Field)?.stopObserving()
            if cancelled { field.stringValue = parent.title }
            else if field.stringValue != parent.title { parent.onCommit(field.stringValue) }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                if textView.hasMarkedText() { return false }
                cancelled = true
                control.window?.makeFirstResponder(nil)
                return true
            }
            if selector == #selector(NSResponder.insertNewline(_:)) {
                control.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }
    }
}
