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
    let focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.identifier = NSUserInterfaceItemIdentifier("quick-add-title")
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Self.font
        field.textColor = .labelColor
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        syncTextAndStyling(field)

        guard let window = field.window else { return }
        let editor = field.currentEditor()
        let fieldOwnsFocus = window.firstResponder === field
            || (editor != nil && window.firstResponder === editor)
        if focused.wrappedValue {
            guard !fieldOwnsFocus else { return }
            DispatchQueue.main.async {
                guard self.focused.wrappedValue, let window = field.window else { return }
                window.makeFirstResponder(field)
            }
        } else if fieldOwnsFocus {
            window.makeFirstResponder(nil)
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
                .font: Self.font,
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
                .font: Self.font
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

    private static let font = NSFont.systemFont(ofSize: 13, weight: .regular)

    private static func clamped(_ range: NSRange, to length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(max(0, range.length), length - location))
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

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.focused.wrappedValue = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.focused.wrappedValue = false
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
            return false
        }
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
