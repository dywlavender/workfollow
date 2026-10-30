import AppKit
import SwiftUI

/// Shared by task details and the note workspace. Host-specific fields stay
/// outside the editor's typography and formatting controls.
enum DocumentEditorPresentationMetrics {
    static let bodyFontSize: CGFloat = 14
    static let footerHeight: CGFloat = 48
    /// NSTextContainer 默认的左右 fragment padding：正文墨迹比宿主内缩 5pt。
    static let textContainerFragmentPadding: CGFloat = 5
}

struct DocumentFormattingToolbarBoundsKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

/// 常驻正文上方的格式工具条。与标题/正文共用内容原点：
/// 宿主传入的左右留白已扣掉 TextKit 的 fragment padding。
struct DocumentFormattingToolbarRow: View {
    @ObservedObject var handle: DocumentEditorHandle
    var leadingPadding: CGFloat
    var trailingPadding: CGFloat
    /// 笔记页正文有 820pt 最大宽度；工具条与其同宽并居中。
    var contentMaxWidth: CGFloat? = nil

    var body: some View {
        // 常驻行铺满宿主宽度，插入入口固定在右端，格式命令按需横向滚动。
        DocumentFormatToolbarView(handle: handle, maxWidth: .infinity, embedded: true)
            // 工具条浮在正文和空白命中层上方，必须自己登记箭头光标，
            // 否则下层登记的光标矩形会让按钮显示文本 I-beam。
            .overlay { ArrowCursorArea().allowsHitTesting(false) }
            .background {
                #if DEBUG
                GeometryReader { geometry in
                    Color.clear.preference(key: DocumentFormattingToolbarBoundsKey.self,
                                           value: geometry.frame(in: .global))
                }
                #endif
            }
            .padding(.leading, leadingPadding)
            .padding(.trailing, trailingPadding)
            .frame(maxWidth: contentMaxWidth ?? .infinity)
            .frame(maxWidth: .infinity)
    }
}

struct DocumentEditorPlaceholder: View {
    let title: String

    /// 模型为空、且编辑区里也确实没有字。只盯模型不够：输入法的组合串
    /// 还没提交，模型仍是空的，占位文案不能压在拼音下面等上屏。
    static func isVisible(for document: NativeDocument, handle: DocumentEditorHandle? = nil) -> Bool {
        document.isEmpty && document.blocks.count == 1 && document.blocks[0].kind == .paragraph
            && (handle?.liveTextIsEmpty ?? true)
    }

    var body: some View {
        #if DEBUG
        label.preference(key: DocumentEditorPlaceholderTitles.self, value: [title])
        #else
        label
        #endif
    }

    private var label: some View {
        Text(title)
            .font(.system(size: EditorPreferences.bodyFontSize))
            .foregroundStyle(WFColors.tertiaryText)
            .padding(.top, 4)
            .padding(.leading, 5)
            .allowsHitTesting(false)
    }
}

#if DEBUG
/// 渲染回归用：当前画出来的占位文案；发布构建不包含。
struct DocumentEditorPlaceholderTitles: PreferenceKey {
    static var defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) { value += nextValue() }
}
#endif

/// 只登记箭头光标矩形、不参与命中的透明层。
private struct ArrowCursorArea: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ view: CursorView, context: Context) {
        view.window?.invalidateCursorRects(for: view)
    }

    final class CursorView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .arrow)
        }

        // 只负责光标；点击仍落到下面的工具条按钮。
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            window?.invalidateCursorRects(for: self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }
    }
}
