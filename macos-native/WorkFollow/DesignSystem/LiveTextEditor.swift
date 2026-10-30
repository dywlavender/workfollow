import AppKit
import SwiftUI

/// SwiftUI `TextEditor` 的轻量替代，另回传"编辑区里是否没有字"（含输入法组合串）。
/// `TextEditor` 的绑定在组合阶段不更新，自绘占位文案只能靠这条实时信号即时让位。
struct LiveTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: 14)
    var textColor: NSColor = .labelColor
    var accessibilityLabel: String?
    var accessibilityIdentifier: String?
    var onLiveTextIsEmptyChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LiveTextEditor
        private var lastReported: Bool?

        init(_ parent: LiveTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            commit(textView)
        }

        /// 组合串上屏/取消后，storage 已是最终文字；同步给模型并刷新空态。
        func compositionEnded(_ textView: NSTextView) {
            commit(textView)
        }

        func reportLiveEmptiness(_ textView: NSTextView) {
            let empty = textView.string.isEmpty
            guard lastReported != empty else { return }
            lastReported = empty
            parent.onLiveTextIsEmptyChange(empty)
        }

        /// 视图更新期间换文档不能当场发布状态，等本轮结束再读 storage。
        func reportAfterViewUpdate(_ textView: NSTextView) {
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.reportLiveEmptiness(textView)
            }
        }

        private func commit(_ textView: NSTextView) {
            parent.text = textView.string
            reportLiveEmptiness(textView)
        }
    }

    final class EditorView: NSTextView {
        var onLiveTextChange: (() -> Void)?
        var onCompositionEnded: (() -> Void)?

        override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
            onLiveTextChange?()
        }

        override func unmarkText() {
            super.unmarkText()
            onCompositionEnded?()
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.focusRingType = .none
        CompactScrollStyle.apply(to: scroll)

        let textView = makeTextView()
        textView.string = text
        textView.delegate = context.coordinator
        textView.onLiveTextChange = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView, let coordinator else { return }
            coordinator.reportLiveEmptiness(textView)
        }
        textView.onCompositionEnded = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView, let coordinator else { return }
            coordinator.compositionEnded(textView)
        }
        scroll.documentView = textView
        context.coordinator.reportAfterViewUpdate(textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? EditorView else { return }
        textView.font = font
        textView.textColor = textColor
        if let accessibilityLabel { textView.setAccessibilityLabel(accessibilityLabel) }
        if let accessibilityIdentifier { textView.setAccessibilityIdentifier(accessibilityIdentifier) }
        if textView.string != text, !textView.hasMarkedText() {
            textView.string = text
            context.coordinator.reportAfterViewUpdate(textView)
        }
    }

    /// 参数与 SwiftUI `TextEditor` 的底层一致，换过来后文字位置不跳。
    /// 必须用 `init(frame:)` 建立自带排版系统：`textContainer: nil` 的实例
    /// 没有 layout manager，`setMarkedText` 会静默失败（输入法打不出字）。
    private func makeTextView() -> EditorView {
        let textView = EditorView(frame: .zero)
        textView.font = font
        textView.textColor = textColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 5
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.focusRingType = .none
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isContinuousSpellCheckingEnabled = false
        if let accessibilityLabel { textView.setAccessibilityLabel(accessibilityLabel) }
        if let accessibilityIdentifier { textView.setAccessibilityIdentifier(accessibilityIdentifier) }
        return textView
    }
}

#if DEBUG
/// 渲染回归用：当前画出来的自绘占位文案；发布构建不包含。
struct LivePlaceholderTitles: PreferenceKey {
    static var defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) { value += nextValue() }
}

extension View {
    func livePlaceholderProbe(_ title: String) -> some View {
        preference(key: LivePlaceholderTitles.self, value: [title])
    }
}
#else
extension View {
    func livePlaceholderProbe(_ title: String) -> some View { self }
}
#endif
