import SwiftUI

/// `#` / `@` 的实时候选列表，浮在快速添加条下方。
///
/// 用 `overlay` 而不是 `.popover`：候选列表要在用户**继续打字**时一直存在，
/// 而 `.popover` 会生成真正的 `NSPopover` 并抢走 first responder，键盘输入随即
/// 落到面板上、输入框中止。overlay 只借用绘制层，焦点始终留在 `NSTextField`。
///
/// 行高与内边距是常量，因为外层需要用它算出「挂在条下方」的偏移量——overlay
/// 的尺寸不会撑开父视图，拿不到实测高度。
struct QuickAddCandidateList: View {
    let names: [String]
    let selectedIndex: Int
    let emptyMessage: String
    let icon: String
    let onHover: (Int) -> Void
    let onCommit: (String) -> Void

    static let rowHeight: CGFloat = 28
    static let verticalPadding: CGFloat = 6
    static let width: CGFloat = 220

    /// 面板高度：至少一行（空态也要占一行），最多 `QuickAddComposition.candidateLimit` 行。
    static func height(forCount count: Int) -> CGFloat {
        CGFloat(max(count, 1)) * rowHeight + verticalPadding * 2
    }

    var body: some View {
        VStack(spacing: 0) {
            if names.isEmpty {
                Text(emptyMessage)
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
                    .lineLimit(1)
                    .padding(.horizontal, WFSpace.md)
                    .frame(height: Self.rowHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(names.indices, id: \.self) { index in
                    let name = names[index]
                    Button {
                        onCommit(name)
                    } label: {
                        HStack(spacing: WFSpace.sm) {
                            Image(systemName: icon)
                                .font(.system(size: 11))
                                .foregroundStyle(index == selectedIndex ? WFColors.accent : WFColors.secondaryText)
                            Text(name)
                                .font(WFType.control)
                                .foregroundStyle(WFColors.text)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, WFSpace.md)
                        .frame(height: Self.rowHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(index == selectedIndex ? WFColors.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { onHover(index) }
                    }
                }
            }
        }
        .padding(.vertical, Self.verticalPadding)
        .frame(width: Self.width)
        .background(
            RoundedRectangle(cornerRadius: WFMetrics.corner, style: .continuous)
                .fill(WFColors.overlay)
                .overlay(
                    RoundedRectangle(cornerRadius: WFMetrics.corner, style: .continuous)
                        .strokeBorder(WFColors.overlayBorder)
                )
                .shadow(color: WFColors.overlayShadow, radius: 12, y: 4)
        )
        // 候选列表只是输入的辅助层：指针点击走按钮，滚轮/点击穿透到下面的列表没有意义，
        // 但键盘必须始终归输入框，所以这里不做任何焦点相关的修饰。
        .accessibilityElement(children: .contain)
    }
}
