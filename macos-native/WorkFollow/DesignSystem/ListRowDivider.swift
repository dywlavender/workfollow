import SwiftUI

/// 列表行底部的细分割线。任务列表与笔记列表共用同一条。
///
/// **画在行的内部**（作为 `.overlay(alignment: .bottom)` 贴在行的底边），
/// 所以它不参与布局、不给行距加高度。这一点是和原来写法最关键的差别：
/// 原来两栏都是把 1pt 的 `Rectangle` / `Divider` 当成 `LazyVStack` 的**兄弟
/// 视图**塞在行与行之间，于是每行实际多出 1pt——任务列表的实测 pitch 是 51
/// 而不是 50、笔记列表是 65/70 而不是 61，两栏的行距都不是 0。改成 overlay
/// 之后 pitch 才真正等于行高，和滴答一致。
///
/// 左右内缩由各栏按自己文字的左边缘传进来：任务行前面有勾选框列、笔记行没有，
/// 两者的文字左边缘差 46pt，共用一个数值会让其中一栏的线横穿控件。
struct ListRowDivider: View {
    var leading: CGFloat
    var trailing: CGFloat

    var body: some View {
        Rectangle()
            .fill(WFColors.listRowSeparator)
            .frame(height: ListRowMetrics.dividerHeight)
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .allowsHitTesting(false)
    }
}
