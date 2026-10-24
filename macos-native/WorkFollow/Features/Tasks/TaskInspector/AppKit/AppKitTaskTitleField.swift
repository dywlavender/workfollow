import AppKit
import SwiftUI

/// 标题 cell 的 AppKit 实现。
///
/// 组件对应：滴答 `TTTaskDetailTitleCell`（nib 内的 `NSTextField` 系标题）。
/// SwiftUI 侧只保留锚点与内边距，文字控件本身是原生 `NSTextField`，
/// 这样换行、选词、输入法、双击选词走系统文本控件，而不是 SwiftUI 的桥接层。
///
/// 视觉口径不变：19pt Medium（`WFType.taskTitle` 同一取值）、无边框无背景、
/// 多行按宽度换行、高度随内容。锚点仍由外层 SwiftUI 提供，渲染契约不受影响。
struct AppKitTaskTitleField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    let placeholder: String
    /// Return 的落点：标题编辑结束后把焦点交给正文（滴答 `focusOnContentIfNeeded`）。
    /// nil 时保持旧行为（只结束编辑）。
    var onSubmit: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> HeightTrackingTextField {
        let field = HeightTrackingTextField()
        field.delegate = context.coordinator
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = false
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.maximumNumberOfLines = 0
        field.font = .systemFont(ofSize: 19, weight: .medium)
        field.textColor = .labelColor
        // 占位符灰与待办框唯一真源同源（默认灰偏深）。
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: QuickAddBarStyle.placeholderNSColor,
            .font: NSFont.systemFont(ofSize: 19, weight: .medium)
        ])
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.stringValue = text
        field.setAccessibilityLabel("任务标题")
        field.onBeginEditing = { [weak coordinator = context.coordinator] in
            coordinator?.noteEditingBegan()
        }
        return field
    }

    func updateNSView(_ field: HeightTrackingTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if (field.placeholderString as String?) != placeholder {
            field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
                .foregroundColor: QuickAddBarStyle.placeholderNSColor,
                .font: NSFont.systemFont(ofSize: 19, weight: .medium)
            ])
        }
        // 宽度变化会改变换行位置，必须同步给 cell 才能算对高度。
        if field.bounds.width > 0, field.preferredMaxLayoutWidth != field.bounds.width {
            field.preferredMaxLayoutWidth = field.bounds.width
            field.invalidateIntrinsicContentSize()
        }
        syncFirstResponder(field)
    }

    /// `isEditing` 是外部的唯一真值：外部要求编辑就聚焦，外部结束就失焦。
    /// 只在状态不符时操作，避免每次 SwiftUI 更新都重设 firstResponder（会打断输入法）。
    private func syncFirstResponder(_ field: HeightTrackingTextField) {
        guard field.window != nil else { return }
        let editing = field.currentEditor() != nil
        if isEditing, !editing {
            DispatchQueue.main.async {
                guard self.isEditing, field.currentEditor() == nil else { return }
                field.window?.makeFirstResponder(field)
            }
        } else if !isEditing, editing {
            DispatchQueue.main.async {
                guard !self.isEditing, field.currentEditor() != nil else { return }
                field.window?.makeFirstResponder(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AppKitTaskTitleField

        init(_ parent: AppKitTaskTitleField) { self.parent = parent }

        /// 非 key 窗口的点击会先把焦点交给字段、再发事件；这一拍 AppKit 不一定
        /// 补 `controlTextDidBeginEditing`。若状态仍停在 false，下一轮
        /// `syncFirstResponder` 会把刚拿到的焦点当成“外部要求结束编辑”清掉。
        func noteEditingBegan() {
            guard !parent.isEditing else { return }
            DispatchQueue.main.async { [parent] in
                guard !parent.isEditing else { return }
                parent.isEditing = true
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if parent.text != field.stringValue { parent.text = field.stringValue }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            noteEditingBegan()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if let field = notification.object as? NSTextField, parent.text != field.stringValue {
                parent.text = field.stringValue
            }
            guard parent.isEditing else { return }
            DispatchQueue.main.async { [parent] in parent.isEditing = false }
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            // Return：结束标题编辑，并把焦点接力给正文（滴答 `focusOnContentIfNeeded`）。
            // 有 `onSubmit` 时不再 `makeFirstResponder(nil)`——那会先把焦点交给窗口，
            // 下一拍再抢回正文，中间闪一下且可能被 SwiftUI 更新打断。
            // Esc 只结束编辑，不接力。
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                DispatchQueue.main.async { [parent] in
                    let submit = parent.onSubmit
                    parent.isEditing = false
                    if let submit {
                        submit()
                    } else {
                        control.window?.makeFirstResponder(nil)
                    }
                }
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                DispatchQueue.main.async { [parent] in
                    parent.isEditing = false
                    control.window?.makeFirstResponder(nil)
                }
                return true
            }
            return false
        }
    }
}

/// 宽度固定、高度随文字换行的 `NSTextField`。
/// 默认 `NSTextField` 的 intrinsic 高度只按单行算，长标题会被裁掉。
final class HeightTrackingTextField: NSTextField {
    var onBeginEditing: (() -> Void)?

    /// 与列表行标题一致：非 key 窗口的第一次点击也要落进输入框。
    /// 默认 NSTextField 会把这一拍只用于激活窗口，标题看着点了却不进编辑。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, currentEditor() != nil { onBeginEditing?() }
        return accepted
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if currentEditor() != nil { onBeginEditing?() }
    }

    override var intrinsicContentSize: NSSize {
        guard bounds.width > 0, let cell else { return super.intrinsicContentSize }
        let measured = cell.cellSize(forBounds: NSRect(x: 0, y: 0,
                                                       width: bounds.width,
                                                       height: .greatestFiniteMagnitude))
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(measured.height))
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }
}
