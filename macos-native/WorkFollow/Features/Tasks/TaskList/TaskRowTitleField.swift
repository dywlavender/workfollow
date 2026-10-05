import AppKit
import SwiftUI

/// Native single-click editing; modifier clicks remain owned by row selection.
struct TaskRowTitleField: NSViewRepresentable {
    let title: String
    let color: Color
    let onSelect: () -> Void
    let onEditingEnded: () -> Void
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
        field.onFinish = { [weak coordinator = context.coordinator, weak field] cancel in
            guard let field else { return }
            coordinator?.finish(field, cancel: cancel)
        }
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        field.textColor = NSColor(color)
        if !field.editingSession { field.stringValue = title }
    }

    final class Field: NSTextField {
        var onSelect: (() -> Void)?
        var onFinish: ((Bool) -> Void)?
        var editingSession = false
        var selection = NSRange(location: 0, length: 0)
        private var outsideClickMonitor: Any?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            if NSApp.currentEvent?.modifierFlags.intersection([.command, .shift]).isEmpty == false {
                return nil
            }
            return super.hitTest(point)
        }
        override func mouseDown(with event: NSEvent) {
            editingSession = true
            onSelect?()
            if outsideClickMonitor == nil {
                outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    guard let self, self.editingSession else { return event }
                    let point = self.convert(event.locationInWindow, from: nil)
                    let modifierSelection = !event.modifierFlags.intersection([.command, .shift]).isEmpty
                    if event.window !== self.window || !self.bounds.contains(point) || modifierSelection {
                        self.onFinish?(false)
                    }
                    // Observing dismissal must never consume the target click.
                    return event
                }
            }
            super.mouseDown(with: event)
            if let editor = currentEditor() as? NSTextView { selection = editor.selectedRange() }
            DispatchQueue.main.async { [weak self] in self?.restoreEditingFocus() }
        }
        func restoreEditingFocus() {
            guard editingSession, let window else { return }
            if window.firstResponder === currentEditor(), currentEditor() != nil { return }
            selectText(nil)
            if let editor = currentEditor() as? NSTextView {
                let count = (stringValue as NSString).length
                editor.setSelectedRange(NSRange(location: min(selection.location, count),
                                               length: min(selection.length, max(0, count - selection.location))))
            }
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
        init(parent: TaskRowTitleField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? Field,
                  let editor = field.currentEditor() as? NSTextView else { return }
            field.selection = editor.selectedRange()
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? Field, field.editingSession else { return }
            // SwiftUI's container focus update can temporarily resign this native
            // editor. Only an explicit outside click / Return / Escape ends the
            // session; restore its focus intent after that update has settled.
            DispatchQueue.main.async { [weak field] in
                field?.restoreEditingFocus()
            }
        }
        func finish(_ field: Field, cancel: Bool) {
            guard field.editingSession else { return }
            field.editingSession = false
            field.stopObserving()
            if !cancel, field.stringValue != parent.title { parent.onCommit(field.stringValue) }
            parent.onEditingEnded()
            field.window?.makeFirstResponder(nil)
            if cancel { field.stringValue = parent.title }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                if textView.hasMarkedText() { return false }
                if let field = control as? Field { finish(field, cancel: true) }
                return true
            }
            if selector == #selector(NSResponder.insertNewline(_:)) {
                if let field = control as? Field { finish(field, cancel: false) }
                return true
            }
            return false
        }
    }
}
