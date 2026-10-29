import SwiftUI

/// 自绘菜单的通用行：点击区、整行悬浮/选中底色和禁用态保持同一套口径。
struct PopupMenuRow<Label: View>: View {
    let action: () -> Void
    var selected = false
    var minHeight: CGFloat = 32
    var horizontalPadding: CGFloat = 8
    var cornerRadius: CGFloat = PopupMetrics.buttonCornerRadius
    var onHoverChanged: ((Bool) -> Void)?
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, horizontalPadding)
        .popupMenuRowBackground(selected: selected,
                                cornerRadius: cornerRadius,
                                onHoverChanged: onHoverChanged)
    }
}

extension View {
    /// 给已有自绘行补菜单底色；保留行自己的按钮、快捷键和 AppKit 绘制。
    func popupMenuRowBackground(
        selected: Bool = false,
        cornerRadius: CGFloat = PopupMetrics.buttonCornerRadius,
        horizontalInset: CGFloat = 0,
        onHoverChanged: ((Bool) -> Void)? = nil
    ) -> some View {
        modifier(PopupMenuRowBackgroundModifier(selected: selected,
                                                cornerRadius: cornerRadius,
                                                horizontalInset: horizontalInset,
                                                onHoverChanged: onHoverChanged))
    }
}

private struct PopupMenuRowBackgroundModifier: ViewModifier {
    let selected: Bool
    let cornerRadius: CGFloat
    let horizontalInset: CGFloat
    let onHoverChanged: ((Bool) -> Void)?
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.background {
            if isEnabled {
                RowHoverBackground(selected: selected,
                                   cornerRadius: cornerRadius,
                                   horizontalInset: horizontalInset,
                                   idleFill: .clear,
                                   selectedFill: WFColors.hover,
                                   hoverFill: WFColors.hover,
                                   activeInActiveApp: true,
                                   onHoverChanged: onHoverChanged)
            }
        }
    }
}
