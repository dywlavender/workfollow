import AppKit
import SwiftUI

/// Return sends; Shift-Return inserts a line break. Composition Return stays with the IME.
struct AIConversationInput: NSViewRepresentable {
    @Binding var text: String
    var submit: () -> Void
    var receiveFiles: (([URL]) -> Void)? = nil
    var receiveImage: ((Data) -> Void)? = nil
    /// 编辑区实时是否为空（输入法组合串也算有字）。占位文案不能等上屏才让位。
    var onLiveTextIsEmptyChange: (Bool) -> Void = { _ in }
    final class Input: NSTextView {
        var submit: () -> Void = {}
        var onLiveTextChange: (() -> Void)?
        var onCompositionEnded: (() -> Void)?
        var receiveFiles: (([URL]) -> Void)?
        var receiveImage: ((Data) -> Void)?

        @discardableResult
        func receiveAttachments(from pasteboard: NSPasteboard) -> Bool {
            if let receiveFiles, let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
                receiveFiles(urls); return true
            }
            if let receiveImage, let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
                ?? NSImage(pasteboard: pasteboard)?.tiffRepresentation {
                receiveImage(data); return true
            }
            return false
        }
        override func paste(_ sender: Any?) {
            if !receiveAttachments(from: .general) { super.paste(sender) }
        }
        override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
            // Plain NSTextView rejects image-only pasteboards before paste(_:) is called.
            if item.action == #selector(NSText.paste(_:)), isEditable, accepts(.general) { return true }
            return super.validateUserInterfaceItem(item)
        }
        private func accepts(_ pasteboard: NSPasteboard) -> Bool {
            (receiveFiles != nil && pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]))
                || (receiveImage != nil && NSImage.canInit(with: pasteboard))
        }
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            accepts(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
        }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            accepts(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
        }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            receiveAttachments(from: sender.draggingPasteboard) || super.performDragOperation(sender)
        }

        override func keyDown(with event: NSEvent) {
            if (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText(),
               event.modifierFlags.intersection([.shift, .option, .control]).isEmpty {
                submit(); return
            }
            super.keyDown(with: event)
        }

        override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
            onLiveTextChange?()
        }

        override func unmarkText() {
            super.unmarkText()
            onCompositionEnded?()
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AIConversationInput
        private var lastReported: Bool?
        init(_ parent: AIConversationInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            apply(view)
        }
        func compositionEnded(_ view: NSTextView) { apply(view) }
        func reportLiveEmptiness(_ view: NSTextView) {
            let empty = view.string.isEmpty
            guard lastReported != empty else { return }
            lastReported = empty
            parent.onLiveTextIsEmptyChange(empty)
        }
        /// 视图更新期间清空/换稿不能当场发布状态，等本轮结束再读 storage。
        func reportAfterViewUpdate(_ view: NSTextView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.reportLiveEmptiness(view)
            }
        }
        private func apply(_ view: NSTextView) {
            parent.text = view.string
            reportLiveEmptiness(view)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        CompactScrollStyle.apply(to: scroll)
        let input = Input(frame: NSRect(x: 0, y: 0, width: 300, height: 64))
        input.minSize = NSSize(width: 0, height: 64)
        input.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        input.isRichText = false; input.drawsBackground = false
        input.allowsUndo = true
        input.font = .systemFont(ofSize: 14); input.textColor = .labelColor
        input.textContainerInset = NSSize(width: 2, height: 6)
        input.isVerticallyResizable = true; input.isHorizontallyResizable = false
        input.autoresizingMask = [.width]; input.textContainer?.widthTracksTextView = true
        input.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        input.delegate = context.coordinator; input.setAccessibilityLabel("输入消息")
        input.registerForDraggedTypes([.fileURL, .png, .tiff])
        input.onLiveTextChange = { [weak input, weak coordinator = context.coordinator] in
            guard let input, let coordinator else { return }
            coordinator.reportLiveEmptiness(input)
        }
        input.onCompositionEnded = { [weak input, weak coordinator = context.coordinator] in
            guard let input, let coordinator else { return }
            coordinator.compositionEnded(input)
        }
        scroll.documentView = input
        context.coordinator.reportAfterViewUpdate(input)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let input = scroll.documentView as? Input else { return }
        input.submit = submit
        input.receiveFiles = receiveFiles; input.receiveImage = receiveImage
        if input.string != text, !input.hasMarkedText() {
            input.string = text
            context.coordinator.reportAfterViewUpdate(input)
        }
    }
}
