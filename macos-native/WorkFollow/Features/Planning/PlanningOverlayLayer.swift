import SwiftUI

/// 页面声明的浮层坐标系。锚点矩形与浮层位置都在这一个坐标系里算，弹框才贴得住被点
/// 的那一条。
enum PlanningCoordinateSpace {
    static let name = "planning-overlay"
}

/// 浮层锚点：被点元素在页面坐标系里的矩形。
///
/// SwiftUI 拿不到「自己背后的 `NSView`」，但弹框位置本来就只需要这个矩形——原版
/// （Flutter `_globalRect`）取的也是同一个东西，所以这里不绕道 AppKit。
@MainActor
final class PlanningAnchorRef {
    /// 目前被点元素的矩形；还没有布局过时为 nil。
    var rect: CGRect?
}

/// 贴在要当锚的视图上（通常是 `.background`），把它的矩形报给引用。
struct PlanningAnchorProbe: View {
    let ref: PlanningAnchorRef

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(PlanningCoordinateSpace.name))
            Color.clear
                .onAppear { ref.rect = frame }
                .onChange(of: frame) { _, value in ref.rect = value }
        }
    }
}

/// 锚定浮层的叠层：一张定位卡片 + 一层透明遮罩，画在**页面自己的图层**里。
///
/// 这与原版同架构——Flutter 的 `showAnchoredPopover` 也是画在窗口叠层里的一张卡
/// （`_AnchoredPopoverPage`），不是另一个窗口。曾经用无边框 `NSPanel` 子窗口实现，
/// 结果是浮层永远拿不到键盘：`becomesKeyOnlyIfNeeded` 靠 AppKit 的"控件需要键盘时
/// 才变 key"机制，而 SwiftUI 的输入控件不会触发它（`SlashCommandPanel` 敢用是因为
/// 那是个纯列表，永远不需要键盘）。另外独立窗口里的 `NSHostingView` 也不继承主
/// 窗口的 environment。
///
/// 位置仍由 `WFOverlayGeometryMath` 决定，与原版逐点一致：间距 6、安全边距 12、
/// 近边装不下就翻转、十字对齐、再夹进可视区。
struct PlanningOverlayLayer<Content: View>: View {
    let anchor: PlanningAnchorRef
    let placement: WFOverlayPlacement
    let size: CGSize
    var radius: CGFloat = WFPlanningOverlayMetrics.radius
    let onDismiss: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            let rect = resolvedRect(viewport: proxy.size)
            ZStack(alignment: .topLeading) {
                // 原版的透明遮罩：卡以外任何一处按下都关掉浮层，并且吃掉这次点击，
                // 不会顺手点到下面的格子或任务条。
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
                if let rect {
                    WFOverlayCard(radius: radius) { content }
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        // Esc：内层控件（正文编辑器、Slash、格式栏）先有机会处理，
                        // 没人处理才关浮层——与原版叠层内的 Shortcuts 同一顺序。
                        .onExitCommand(perform: onDismiss)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func resolvedRect(viewport: CGSize) -> CGRect? {
        guard let anchorRect = anchor.rect else { return nil }
        return WFOverlayGeometryMath.compute(anchor: anchorRect,
                                             viewport: viewport,
                                             desired: size,
                                             placement: placement).rect
    }
}

/// 浮层卡面：原版 `WorkFollowSurfaceTokens.popover` 的三件事——浮层底色 `overlay`、
/// 1pt `border` 描边、level2 阴影（blur 18 / offset (0,6)）。
struct WFOverlayCard<Content: View>: View {
    let radius: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(WFColors.overlay, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(WFColors.overlayBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .shadow(color: WFColors.overlayShadow,
                    radius: WFPlanningOverlayMetrics.shadowRadius,
                    y: WFPlanningOverlayMetrics.shadowOffsetY)
    }
}
