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

/// 任务条的实际布局锚点；跨周色带可能为同一个任务提供多个可点击区域。
struct PlanningTaskAnchorsKey: PreferenceKey {
    static var defaultValue: [UUID: [Anchor<CGRect>]] { [:] }
    static func reduce(value: inout [UUID: [Anchor<CGRect>]], nextValue: () -> [UUID: [Anchor<CGRect>]]) {
        value.merge(nextValue(), uniquingKeysWith: +)
    }
}

extension View {
    func planningTaskTarget(_ id: UUID) -> some View {
        anchorPreference(key: PlanningTaskAnchorsKey.self, value: .bounds) { [id: [$0]] }
    }
}

/// 锚定浮层的叠层：一张定位卡片 + 一层透明遮罩，画在页面自己的图层里。
/// 编辑任务时，遮罩为其它任务条留出命中区域，让一次点击直接切换详情。
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
    var taskHitRects: [CGRect] = []
    let onDismiss: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            let rect = resolvedRect(viewport: proxy.size)
            ZStack(alignment: .topLeading) {
                // 空白处关闭并消费点击，避免顺带触发网格的新建；任务条直接收点击。
                Color.clear
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(PlanningOverlayDismissRegion(taskHitRects: taskHitRects), eoFill: true)
                    .onTapGesture(perform: onDismiss)
                if let rect {
                    WFOverlayCard(radius: radius) { content }
                        .frame(width: rect.width, height: rect.height)
                        .contentShape(Rectangle())
                        .onTapGesture { }
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

private struct PlanningOverlayDismissRegion: Shape {
    let taskHitRects: [CGRect]
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        for target in taskHitRects {
            let visible = target.intersection(rect)
            if !visible.isNull, !visible.isEmpty { path.addRect(visible) }
        }
        return path
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
