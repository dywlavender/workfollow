import AppKit
import SwiftUI

enum QuickAddTokenColor {
    static func swiftUIColor(for kind: QuickAddToken.Kind) -> Color {
        switch kind {
        case .date: WFColors.accent
        case .time: WFColors.accentHover
        case .recurrence: WFColors.secondaryText
        case .tag: WFColors.success
        case .list: WFColors.warning
        case .priority: WFColors.danger
        }
    }

    static func appKitColor(for kind: QuickAddToken.Kind) -> NSColor {
        NSColor(swiftUIColor(for: kind))
    }
}

/// NSTextField bridge used by list Quick Add so recognized smart-entry spans
/// can be styled in place without swapping out the editable field (or its IME).
struct QuickAddTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let tokens: [QuickAddToken]
    /// 程序化聚焦意图（SwiftUI → 控件）。
    ///
    /// **必须是普通 `Binding`，不能是 `FocusState<Bool>.Binding`。**
    /// `NSViewRepresentable` 上挂不了 `.focused()`，SwiftUI 因此不为它维护焦点状态：
    /// 往里写 `wrappedValue = true` 不生效，读出来**永远是 `false`**（已实测）。
    /// 拿它当聚焦真值，所有「请求聚焦」的代码都会静默失效，`guard quickAddFocused`
    /// 之类的守卫也会恒假——症状散落在「Esc 没反应」「关掉浮层焦点不回来」
    /// 「列表方向键抢键」这些看起来无关的现象里。
    ///
    /// 换成 `@State` 的 `Binding` 之后，读和写都按普通状态走，两个方向都可靠。
    let focused: Binding<Bool>
    let onSubmit: () -> Void
    let onEscape: () -> Void
    /// Tab：候选列表打开时提交当前候选，否则进入任务描述行。
    let onTab: () -> Void
    /// Shift+↩︎：与 Tab 同义，直接进描述行（滴答的提示原文是
    /// 「敲击 Enter 添加任务；敲击 Tab 添加任务描述」，同一屏里还给了
    /// 「Shift+↩︎ 可添加描述」）。AppKit 把 Shift+Return 映射到
    /// `insertNewlineIgnoringFieldEditor:`，所以要单独接这个 selector。
    let onShiftReturn: () -> Void
    /// 上下键：只有候选列表打开时才消费，返回 true 表示已处理。
    let onMoveUp: () -> Bool
    let onMoveDown: () -> Bool
    /// 输入框**自己**报告聚焦状态（控件 → SwiftUI）。
    ///
    /// 与上面的 `focused` 是同一件事的两个方向，落到调用方**同一个** `@State` 上。
    /// 之所以还留这条回调，是因为它比 delegate 的 `controlTextDidBeginEditing` 更早、
    /// 更可靠：AppKit 在「已经是第一响应者」时**不会再发**那个通知，
    /// 而 `mouseDown` 是「用户点了输入框」最早的可观测点。
    let onFieldFocusChange: (Bool) -> Void
    /// 列表快速添加条与全局面板的字号不同（13 / 14），其余排版保持一致。
    var fontSize: CGFloat = 13

    private var font: NSFont { NSFont.systemFont(ofSize: fontSize, weight: .regular) }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// 造出输入框本体，并把「点击即上报聚焦」这条接缝一并接好。
    ///
    /// 抽成静态工厂是为了让接缝可测：`makeNSView` 需要一个只有 SwiftUI 内部才能构造的
    /// `Context`，而把整个 representable 塞进 `NSHostingView` 在无头测试进程里会直接
    /// 崩（实测 SIGSEGV）。把「必须是上报子类」和「钩子必须接上」两件事收进这里，
    /// 测试就能绕过 SwiftUI 直接验证——这两点也正是实际会坏的地方。
    static func makeField(text: String,
                          placeholder: String,
                          font: NSFont,
                          onFocusChange: @escaping (Bool) -> Void) -> QuickAddFocusReportingField {
        let field = QuickAddFocusReportingField(string: text)
        field.identifier = NSUserInterfaceItemIdentifier("quick-add-title")
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.textColor = .labelColor
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // 点进输入框要**立刻**算作聚焦：`mouseDown` 是这件事最早的可观测点，
        // 比 delegate 的 `controlTextDidBeginEditing` 更可靠（已经是第一响应者时
        // 那个回调不会再发）。
        field.onMouseDown = { onFocusChange(true) }
        return field
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = Self.makeField(text: text, placeholder: placeholder, font: font) {
            [weak coordinator = context.coordinator] isFocused in
            coordinator?.parent.onFieldFocusChange(isFocused)
        }
        field.delegate = context.coordinator
        return field
    }

    /// 反向收回的判据：**意图说没聚焦、且控件确实还占着第一响应者**，才放手。
    ///
    /// 单独抽出来是因为它就是那个曾经把「点击展开」毁掉的判断：以前这里读的是
    /// 恒假的 `@FocusState`，于是「意图说没聚焦」恒成立 → 每次点击后都把刚拿到的
    /// 焦点收走。表里第一行（意图为真时**绝不**收回）就是那条回归的护栏。
    static func shouldRelinquishFocus(intent: Bool, fieldOwnsFocus: Bool) -> Bool {
        !intent && fieldOwnsFocus
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        syncTextAndStyling(field)

        guard let window = field.window else { return }
        let editor = field.currentEditor()
        let fieldOwnsFocus = window.firstResponder === field
            || (editor != nil && window.firstResponder === editor)

        if focused.wrappedValue {
            // 意图要聚焦、AppKit 还没给 → 交给它。延后一个 runloop 再读一次意图，
            // 避免和「用户在同一帧里又点了别处」抢焦点。
            guard !fieldOwnsFocus else { return }
            DispatchQueue.main.async {
                guard self.focused.wrappedValue, let window = field.window else { return }
                window.makeFirstResponder(field)
            }
        } else if fieldOwnsFocus {
            // 意图说没聚焦、AppKit 还占着第一响应者 → 交还焦点（对齐滴答
            // 「第一下 Esc 只收起、不清草稿」：意图置假之后焦点要真的松开，
            // 否则打字仍会落进输入框，视觉上也还停在展开态）。
            //
            // **必须延后一个 runloop 再读实时值，不能当场收。** 点击路径上
            // `mouseDown` 先上报聚焦（`onFieldFocusChange(true)`），SwiftUI 这一轮
            // update 可能落在那次状态回写生效之前；当场 `makeFirstResponder(nil)`
            // 等于把刚点出来的焦点掐掉，条又折回去——这正是「点了没反应、
            // 打字才展开」的历史成因（当时该分支是同步执行的）。
            // 延后读到的才是最新值，只有确实没聚焦时才放手。
            DispatchQueue.main.async {
                guard let window = field.window else { return }
                let editor = field.currentEditor()
                let stillOwns = window.firstResponder === field
                    || (editor != nil && window.firstResponder === editor)
                guard Self.shouldRelinquishFocus(intent: self.focused.wrappedValue,
                                                 fieldOwnsFocus: stillOwns) else { return }
                window.makeFirstResponder(nil)
            }
        }
    }

    private func syncTextAndStyling(_ field: NSTextField) {
        let editor = field.currentEditor() as? NSTextView
        if editor?.hasMarkedText() == true { return }

        if let editor {
            if editor.string != text {
                let selection = editor.selectedRange()
                editor.string = text
                editor.setSelectedRange(Self.clamped(selection, to: (text as NSString).length))
            }
        } else if field.stringValue != text {
            field.stringValue = text
        }

        let styled = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]
        )
        for token in tokens.sorted(by: { $0.range.location < $1.range.location }) {
            guard token.range.location >= 0,
                  NSMaxRange(token.range) <= styled.length,
                  token.range.length > 0 else { continue }
            let color = QuickAddTokenColor.appKitColor(for: token.kind)
            styled.addAttributes([
                .foregroundColor: color,
                .backgroundColor: color.withAlphaComponent(0.14),
                .font: font
            ], range: token.range)
        }

        if let editor {
            guard editor.attributedString().isEqual(to: styled) == false else { return }
            let selection = editor.selectedRange()
            editor.textStorage?.setAttributedString(styled)
            editor.setSelectedRange(Self.clamped(selection, to: styled.length))
        } else if !field.attributedStringValue.isEqual(to: styled) {
            field.attributedStringValue = styled
        }
    }

    private static func clamped(_ range: NSRange, to length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(max(0, range.length), length - location))
    }

    /// 粘贴多行文本时绕开 AppKit 的默认插入路径。
    ///
    /// 「换行可添加多个任务」要求草稿里保留原始 `\n`，但单行 `NSTextField` 的
    /// `insertText` 会把换行替换成空格——实测 `insertText("red\ngreen")` 之后字段里
    /// 只剩 `"red green"`，批量添加于是永远只剩一行。这里直接读剪贴板原文、与当前
    /// 选区合并后写回绑定；字段编辑器会经 `syncTextAndStyling` 的赋值路径拿到它，
    /// 而赋值路径是保留换行的（同样实测过）。
    ///
    /// 只处理含换行的粘贴；普通粘贴返回 false，交回 AppKit 走默认路径（保住撤销、
    /// 自动替换等系统行为）。
    func pastePreservingNewlines(_ field: NSTextField?, editor: NSTextView) -> Bool {
        guard !editor.hasMarkedText(),
              let raw = NSPasteboard.general.string(forType: .string) else { return false }
        return insertPreservingNewlines(raw, field: field, editor: editor)
    }

    /// 与剪贴板无关的那一半：判断是否接管、把文本写回绑定并摆好插入点。
    /// 单独拆出来是为了能在测试里直接喂字符串，不必去动用户的系统剪贴板。
    func insertPreservingNewlines(_ raw: String, field: NSTextField?, editor: NSTextView) -> Bool {
        guard raw.contains(where: { $0.isNewline }) else { return false }
        let current = text as NSString
        let selection = editor.selectedRange()
        guard selection.location >= 0, NSMaxRange(selection) <= current.length else { return false }
        text = current.replacingCharacters(in: selection, with: raw)
        if let field { syncTextAndStyling(field) }
        // 光标落在刚粘进来的文本之后，接着输入就是继续追加而不是插回开头。
        let caret = selection.location + (raw as NSString).length
        editor.setSelectedRange(NSRange(location: min(caret, (text as NSString).length), length: 0))
        return true
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QuickAddTextField

        init(parent: QuickAddTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        /// 编辑开始/结束都是**可靠的**聚焦信号，前提是 `focused` 是普通 `Binding`。
        /// 以前它绑在 `@FocusState` 上，这两行是无效写（读代码看不出来）。
        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.focused.wrappedValue = true
            parent.onFieldFocusChange(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.focused.wrappedValue = false
            parent.onFieldFocusChange(false)
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                parent.onTab()
                return true
            }
            // Shift+↩︎ 走的是另一个 selector（见 StandardKeyBinding.dict 的 `~\r`）。
            if commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                parent.onShiftReturn()
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                return parent.onMoveUp()
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                return parent.onMoveDown()
            }
            if commandSelector == #selector(NSTextView.paste(_:)) {
                return parent.pastePreservingNewlines(control as? NSTextField, editor: textView)
            }
            return false
        }
    }
}

/// 会在鼠标按下时立刻上报的输入框。
///
/// `NSTextField.mouseDown` 会让自己成为第一响应者，但**不一定**再触发
/// `controlTextDidBeginEditing`（已经是第一响应者时就不会）。
/// 而「点一下就展开」依赖的是「点」这个动作本身，不是编辑状态的变化，
/// 所以在这里单独上报一次，保证点击一定被算作聚焦。
/// 故意不加 `private`：这是「点击 → 上报聚焦」的唯一接缝，测试要从真实的
/// `NSHostingView` 视图树里把它取出来、发一次真的 `mouseDown` 验证它确实上报。
final class QuickAddFocusReportingField: NSTextField {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}

/// Wraps smart-capture chips onto additional rows instead of compressing them
/// into a single horizontal strip when the draft contains several properties.
struct QuickAddTokenFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 5
    var verticalSpacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let availableWidth = proposal.width ?? sizes.reduce(0) { $0 + $1.width }
            + horizontalSpacing * CGFloat(max(0, sizes.count - 1))
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for size in sizes {
            if x > 0, x + size.width > availableWidth {
                widestRow = max(widestRow, x - horizontalSpacing)
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
        widestRow = max(widestRow, max(0, x - horizontalSpacing))
        return CGSize(width: proposal.width ?? widestRow,
                      height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
