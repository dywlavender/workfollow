import AppKit
import SwiftUI

/// 标题 cell 的 AppKit 实现。
///
/// 组件对应：滴答 `TTTaskDetailTitleCell`（nib 内的 `NSTextField` 系标题）。
/// SwiftUI 侧只保留锚点与内边距，文字控件本身是原生 `NSTextField`，
/// 这样换行、选词、输入法、双击选词走系统文本控件，而不是 SwiftUI 的桥接层。
///
/// 视觉口径：详情用 19pt Medium、多行按宽度换行；浮窗标题复用同一控件，
/// 传入 15pt Semibold + 单行。无边框无背景、高度随内容（浮窗由标题行固定高度）。
/// 锚点仍由外层 SwiftUI 提供，渲染契约不受影响。
struct AppKitTaskTitleField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    let placeholder: String
    var font: NSFont = .systemFont(ofSize: 19, weight: .medium)
    var accessibilityLabel: String = "任务标题"
    /// 浮窗标题只有一行；详情标题按宽度多行换行。
    var singleLine: Bool = false
    /// Return 的落点：标题编辑结束后把焦点交给正文（滴答 `focusOnContentIfNeeded`）。
    /// nil 时保持旧行为（只结束编辑）。
    var onSubmit: (() -> Void)? = nil
    /// 右方向键越过标题末尾的落点：把焦点交给正文第一行行首。nil 时保持默认（光标原地不动）。
    var onArrowRightAtEnd: (() -> Void)? = nil
    /// 浮窗接管期间，原详情里的标题只展示、不可编辑。
    var readOnly = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> HeightTrackingTextField {
        let field = HeightTrackingTextField()
        field.delegate = context.coordinator
        field.isEditable = !readOnly
        field.isSelectable = true
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = singleLine
        field.lineBreakMode = singleLine ? .byTruncatingTail : .byWordWrapping
        field.cell?.wraps = !singleLine
        field.cell?.isScrollable = singleLine
        field.maximumNumberOfLines = singleLine ? 1 : 0
        field.font = font
        field.textColor = NSColor(WFColors.documentText)
        // 占位符灰与待办框唯一真源同源（默认灰偏深）。
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: QuickAddBarStyle.placeholderNSColor,
            .font: font
        ])
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.stringValue = text
        field.setAccessibilityLabel(accessibilityLabel)
        field.onBeginEditing = { [weak field, weak coordinator = context.coordinator] in
            guard let field else { return }
            coordinator?.reportFocus(field)
        }
        return field
    }

    func updateNSView(_ field: HeightTrackingTextField, context: Context) {
        context.coordinator.parent = self
        if field.isEditable == readOnly { field.isEditable = !readOnly }
        synchronizeText(field)
        if field.placeholderAttributedString?.string != placeholder {
            field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
                .foregroundColor: QuickAddBarStyle.placeholderNSColor,
                .font: font
            ])
        }
        // 宽度变化会改变换行位置，必须同步给 cell 才能算对高度。
        if field.bounds.width > 0, field.preferredMaxLayoutWidth != field.bounds.width {
            field.preferredMaxLayoutWidth = field.bounds.width
            field.invalidateIntrinsicContentSize()
        }
        context.coordinator.synchronizeFocus(field)
    }

    private func synchronizeText(_ field: HeightTrackingTextField) {
        if let editor = field.currentEditor() as? NSTextView {
            // 读取 NSTextField.stringValue 会校验当前编辑，提前结束输入法组合。
            guard !editor.hasMarkedText(), editor.string != text else { return }
            let selection = editor.selectedRange()
            let length = text.utf16.count
            let location = min(selection.location, length)
            editor.string = text
            editor.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
        } else if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AppKitTaskTitleField

        init(_ parent: AppKitTaskTitleField) { self.parent = parent }

        func synchronizeFocus(_ field: HeightTrackingTextField) {
            let shouldEdit = parent.isEditing && !parent.readOnly
            guard field.window != nil, shouldEdit != field.hasEditingFocus else { return }
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field, let window = field.window else { return }
                let shouldEdit = self.parent.isEditing && !self.parent.readOnly
                guard shouldEdit != field.hasEditingFocus else { return }
                if shouldEdit {
                    window.makeFirstResponder(field)
                    if let editor = field.currentEditor() as? NSTextView {
                        // 正文左键回到标题时落在末尾。
                        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
                    }
                } else {
                    window.makeFirstResponder(nil)
                }
            }
        }

        /// 通知可能在 AppKit 切换 firstResponder 期间发出，等切换完成后再读实际焦点。
        func reportFocus(_ field: HeightTrackingTextField) {
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field, field.window != nil else { return }
                let isEditing = field.hasEditingFocus
                if self.parent.isEditing != isEditing { self.parent.isEditing = isEditing }
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let editor = field.currentEditor() as? NSTextView, !editor.hasMarkedText() else { return }
            if parent.text != editor.string { parent.text = editor.string }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            if let field = notification.object as? HeightTrackingTextField { reportFocus(field) }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? HeightTrackingTextField else { return }
            let value = field.stringValue
            if parent.text != value { parent.text = value }
            reportFocus(field)
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
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
            // 右方向键越过标题末尾（含空标题）：焦点接力给正文第一行行首，
            // 与正文的左方向键回跳形成标题⇄正文的双向巡游。Shift+右（扩选）不受影响。
            if commandSelector == #selector(NSResponder.moveRight(_:)),
               let exitRight = parent.onArrowRightAtEnd,
               textView.selectedRange.location >= (textView.string as NSString).length {
                DispatchQueue.main.async { [parent] in
                    parent.isEditing = false
                    exitRight()
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

    var hasEditingFocus: Bool {
        guard let responder = window?.firstResponder else { return false }
        return responder === self || responder === currentEditor()
    }

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
