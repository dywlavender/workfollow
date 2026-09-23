import AppKit

final class NativeTextView: NSTextView {
    var onEscape: (() -> InspectorEscapeEffect)?

    override init(frame frameRect: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: textContainer)
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isSelectable = true
        isEditable = true
        drawsBackground = false
        backgroundColor = .clear
        textColor = .labelColor
        font = .systemFont(ofSize: 15)
        textContainerInset = NSSize(width: 0, height: 4)
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                         height: CGFloat.greatestFiniteMagnitude)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
    }

    required init?(coder: NSCoder) {
        fatalError("NativeTextView is created programmatically")
    }

    override func cancelOperation(_ sender: Any?) {
        guard let onEscape else {
            super.cancelOperation(sender)
            return
        }
        _ = onEscape()
    }
}
