import SwiftUI

/// 菜单/面板搜索框的统一形态：放大镜 + plain 输入，固定行高、圆角与底色。
/// 原先菜单用系统 roundedBorder、专注选择器自绘 chip，字号/圆角/底色各不相同。
struct PopupSearchField: View {
    var placeholder = "搜索"
    @Binding var text: String
    var height: CGFloat = PopupMetrics.searchFieldHeight
    var autofocus = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(WFColors.tertiaryText)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(WFType.body)
                .focused($focused)
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius)
            .fill(WFColors.hover))
        .overlay(RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius)
            .stroke(WFColors.border, lineWidth: 1))
        .onAppear {
            if autofocus { DispatchQueue.main.async { focused = true } }
        }
    }
}