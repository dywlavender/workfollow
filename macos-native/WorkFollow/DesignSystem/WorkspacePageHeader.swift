import SwiftUI

/// 独立页面的统一页头。
///
/// 六个独立页（日历、四象限、倒数日、会议、专注、AI 对话）原来各写一套：
/// 标题令牌 20/18 混用、页头高度 36/44/52/56/58 并存、左右内边距 10/14/16/20/24/26
/// 都有，切换页面时标题的 x/y 和右侧控件命中区都在跳。
///
/// 这里只统一**容器**——高度、内边距、标题令牌、右侧控件尺寸；
/// 页面自己往 `leading` / `accessory` / `trailing` 里放什么控件由各页决定。
struct WorkspacePageHeader<Leading: View, Accessory: View, Trailing: View>: View {
    let title: String
    /// AI 对话要避开窗口红绿灯，单独给一个顶部内边距。
    var topInset: CGFloat = WorkspacePageHeaderMetrics.topInset
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: WFSpace.sm) {
            leading()
            Text(title)
                .font(WFType.pageTitle)
                .foregroundStyle(WFColors.text)
                .lineLimit(1)
            accessory()
            Spacer(minLength: WFSpace.sm)
            trailing()
        }
        .padding(.horizontal, WorkspacePageHeaderMetrics.horizontalInset)
        .padding(.top, topInset)
        .frame(height: WorkspacePageHeaderMetrics.height, alignment: .center)
    }
}

// MARK: - 常用组合

extension WorkspacePageHeader where Leading == EmptyView, Accessory == EmptyView {
    init(title: String, topInset: CGFloat = WorkspacePageHeaderMetrics.topInset,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(title: title, topInset: topInset,
                  leading: { EmptyView() }, accessory: { EmptyView() }, trailing: trailing)
    }
}

extension WorkspacePageHeader where Leading == EmptyView {
    init(title: String, topInset: CGFloat = WorkspacePageHeaderMetrics.topInset,
         @ViewBuilder accessory: @escaping () -> Accessory,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(title: title, topInset: topInset,
                  leading: { EmptyView() }, accessory: accessory, trailing: trailing)
    }
}

extension WorkspacePageHeader where Accessory == EmptyView {
    init(title: String, topInset: CGFloat = WorkspacePageHeaderMetrics.topInset,
         @ViewBuilder leading: @escaping () -> Leading,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(title: title, topInset: topInset,
                  leading: leading, accessory: { EmptyView() }, trailing: trailing)
    }
}

enum WorkspacePageHeaderMetrics {
    /// 页头总高。44 是会议页原有的值，也是六个页面里最靠中间的；取它作为基准，
    /// 各页往上/下浮动都不超过 8pt。
    static let height: CGFloat = 44
    /// 左右内边距。26 是日历页原有的值（也是滴答实测值），其余页面比它窄。
    static let horizontalInset: CGFloat = 26
    /// 标题顶部内边距。AI 对话需要让出红绿灯位置，其余页面用 0。
    static let topInset: CGFloat = 0
    /// 页头右侧图标按钮的统一下限尺寸（命中区），与 `WFGlassControlGroup` 对齐。
    static let controlSize: CGFloat = 30
    /// 页头图标字号。
    static let controlIconSize: CGFloat = 16
}
