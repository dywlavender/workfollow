import AppKit

/// 行首装饰（列表标记 / 引用竖线 / 活动行角标）的绘制层。
///
/// 为什么单独一层：macOS 14 的 TextKit 2 把选区画在私有子视图 `_NSTextSelectionView`
/// 上，层级高于 `NSTextView.draw(_:)`。装饰如果画在文本视图自己的 draw 里，整行被选中
/// 时（选区从容器原点起画，会盖住行首缩进区）复选框/圆点就被选区盖住——2026-10-18
/// 走查复现："鼠标拖拉选中内容和勾选框时勾选框不显示"。
/// 放到选区视图之上的透明层后，装饰始终可见，且不拦截鼠标事件。
final class BlockDecorationOverlay: NSView {
    weak var textView: NativeTextView?

    init(textView: NativeTextView) {
        self.textView = textView
        super.init(frame: textView.bounds)
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 与文本视图同一坐标系（NSTextView 是 flipped）。
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    /// 不拦截任何鼠标事件：点击/拖选/手柄命中都交给文本视图。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView else { return }
        textView.drawBlockDecorations(in: dirtyRect)
    }
}
