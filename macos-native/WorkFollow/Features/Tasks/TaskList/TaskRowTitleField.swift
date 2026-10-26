import AppKit
import SwiftUI

@MainActor
final class TaskRowTitleHandle: ObservableObject {
    weak var field: TaskRowTitleField.Field?
    func beginEditing() { field?.beginEditing() }
}

/// 普通单击直接编辑标题；行内留白也通过同一入口聚焦到标题末尾。
/// 修饰键点击交给行手势（Cmd 批量、Shift 范围）。
struct TaskRowTitleField: NSViewRepresentable {
    let title: String
    let color: Color
    var handle: TaskRowTitleHandle? = nil
    let onEditingRequested: () -> Void
    let onEditingBegan: () -> Void
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
        field.onEditingRequested = { [weak coordinator = context.coordinator] in coordinator?.parent.onEditingRequested() }
        field.onFinish = { [weak coordinator = context.coordinator, weak field] cancel in
            guard let field else { return }
            coordinator?.finish(field, cancel: cancel)
        }
        handle?.field = field
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        handle?.field = field
        field.textColor = NSColor(color)
        if !field.editingSession, field.stringValue != title { field.stringValue = title }
    }

    final class Field: NSTextField {
        var onEditingRequested: (() -> Void)?
        var onFinish: ((Bool) -> Void)?
        var editingSession = false
        var selection = NSRange(location: 0, length: 0)
        private var outsideClickMonitor: Any?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        /// 窗口激活和行刷新不会自动进入编辑；由用户点击明确发起。
        override var acceptsFirstResponder: Bool { editingSession }
        override func hitTest(_ point: NSPoint) -> NSView? {
            if NSApp.currentEvent?.modifierFlags.intersection([.command, .shift]).isEmpty == false {
                return nil
            }
            return super.hitTest(point)
        }
        override func mouseDown(with event: NSEvent) {
            beginEditing()
            super.mouseDown(with: event)
            styleEditorBackground()
            if let editor = currentEditor() as? NSTextView { selection = editor.selectedRange() }
        }

        func beginEditing() {
            guard !editingSession, window != nil else { return }
            editingSession = true
            onEditingRequested?()
            installOutsideClickMonitor()
            selectText(nil)
            styleEditorBackground()
            selection = NSRange(location: (stringValue as NSString).length, length: 0)
            (currentEditor() as? NSTextView)?.setSelectedRange(selection)
            DispatchQueue.main.async { [weak self] in self?.restoreEditingFocus() }
        }

        private func installOutsideClickMonitor() {
            guard outsideClickMonitor == nil else { return }
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

        func restoreEditingFocus() {
            guard editingSession, let window else { return }
            styleEditorBackground()
            if window.firstResponder === currentEditor(), currentEditor() != nil { return }
            // A queued restore belongs only to a transient container refresh.
            // Another native input already owning focus is an actual handoff.
            if window.firstResponder is NSTextView || window.firstResponder is NSTextField {
                onFinish?(false)
                return
            }
            selectText(nil)
            styleEditorBackground()
            if let editor = currentEditor() as? NSTextView {
                let count = (stringValue as NSString).length
                editor.setSelectedRange(NSRange(location: min(selection.location, count),
                                               length: min(selection.length, max(0, count - selection.location))))
            }
        }

        /// 行内编辑的 field editor 默认是白底，会把选中行的底色挖出一块白；
        /// 改成透明，编辑时沿用行本身的选中色（对齐滴答）。
        func styleEditorBackground() {
            guard let editor = currentEditor() as? NSTextView else { return }
            editor.drawsBackground = false
            editor.backgroundColor = .clear
            editor.insertionPointColor = .labelColor
            editor.textContainerInset = .zero
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
        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? Field, field.editingSession else { return }
            parent.onEditingBegan()
        }
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
            if let editor = field.currentEditor(), field.window?.firstResponder === editor {
                field.window?.makeFirstResponder(nil)
            }
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
