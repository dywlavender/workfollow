import CoreGraphics

/// 锚定浮层的几何契约，逐值逐式对齐 Flutter 的
/// `desktop/lib/widgets/desktop_popover.dart`（`calculatePopoverGeometry`）与
/// `WorkFollowSpacing.popoverSafeArea` / `WorkFollowRadii.popover` /
/// `WorkFollowShadows.level2`。
///
/// 日历与四象限的「点任务条开编辑器」「点 + 新建」都用它：原版把这两个面板贴着
/// 被点的那一格/那一行弹出来，所以位置不是"居中"，而是**锚框的十字对齐 + 6pt 间距
/// + 近边不够就翻转 + 夹在窗口安全边距内**。这一层是纯值计算，不碰 AppKit，
/// 因此可以脱离窗口单测（见 `PlanningOverlayGeometryTests`）。
enum WFPlanningOverlayMetrics {
    /// Flutter `WorkFollowSpacing.popoverSafeArea`（= space3 = 12）。
    static let safeArea: CGFloat = 12

    /// Flutter `PopoverPlacement.gap` 的默认值。
    static let gap: CGFloat = 6

    /// Flutter `WorkFollowRadii.popover`：400 与 320 两种宽度都取 popover 圆角
    /// （只有工具条那种 `toolbarPopoverWidth` 才降到 control）。
    static let radius: CGFloat = 12

    /// Flutter `WorkFollowShadows.level2`：blur 18 / offset (0, 6)。
    static let shadowRadius: CGFloat = 18
    static let shadowOffsetY: CGFloat = 6

    /// 任务编辑器：`TaskSurfaceMetrics.editorWidth` / `editorMinHeight`
    /// （min 与 max 同为 356，所以上限就是 356）。
    static let editorWidth: CGFloat = 400
    static let editorHeight: CGFloat = 356

    /// 新建任务卡：`TaskSurfaceMetrics.composerWidth` /
    /// `composerMaxHeight` / `composerRowHeight` / `composerBodyHeight`。
    /// 卡高不是 maxHeight 而是内容高：42 + 1 + 126 + 1 + 42 = 212。
    static let composerWidth: CGFloat = 320
    static let composerMaxHeight: CGFloat = 280
    static let composerRowHeight: CGFloat = 42
    static let composerBodyHeight: CGFloat = 126
    static let composerHeight: CGFloat =
        composerRowHeight * 2 + composerBodyHeight + WFMetrics.divider * 2

}

/// Flutter `PopoverSide`。
enum WFOverlaySide: Equatable {
    case top, bottom, left, right

    var isVertical: Bool { self == .top || self == .bottom }
    var opposite: WFOverlaySide {
        switch self {
        case .top: .bottom
        case .bottom: .top
        case .left: .right
        case .right: .left
        }
    }
}

/// Flutter `PopoverAlignment`。
enum WFOverlayAlignment: Equatable {
    case start, center, end
}

/// Flutter `PopoverPlacement`。这里只收这两页实际用到的三个取值，用到再补。
struct WFOverlayPlacement: Equatable {
    var preferredSide: WFOverlaySide
    var alignment: WFOverlayAlignment
    var gap: CGFloat = WFPlanningOverlayMetrics.gap
    var allowFlip = true

    /// `showTaskFloatingEditor`：编辑器挂在被点任务条/行的**下方居中**。
    static let bottomCenter = WFOverlayPlacement(preferredSide: .bottom, alignment: .center)
    /// `showTaskEditorPopover(placement: .bottomEnd)`：新建卡挂在被点元素的**下方右缘对齐**。
    static let bottomEnd = WFOverlayPlacement(preferredSide: .bottom, alignment: .end)
    /// 新建卡里「更多属性」菜单：`PopoverPlacement.topEnd`。
    static let topEnd = WFOverlayPlacement(preferredSide: .top, alignment: .end)
}

/// Flutter `PopoverGeometry` 的等价物。矩形用**左上原点**坐标（同 Flutter），
/// 转成 AppKit 的屏幕坐标由呈现层负责。
struct WFOverlayGeometry: Equatable {
    var rect: CGRect
    var side: WFOverlaySide
    var flipped: Bool
}

enum WFOverlayGeometryMath {
    /// `calculatePopoverGeometry` 的逐行移植。
    ///
    /// - Parameters:
    ///   - anchor: 锚框，左上原点坐标。
    ///   - viewport: **窗口内容区**尺寸（Flutter 取的是 `MediaQuery.sizeOf(context)`，
    ///     不是屏幕），所以夹取范围也止于窗口。
    ///   - desired: 期望尺寸；高度是"最大可用高"，不是强制高。
    static func compute(anchor: CGRect,
                        viewport: CGSize,
                        desired: CGSize,
                        placement: WFOverlayPlacement,
                        safeArea: CGFloat = WFPlanningOverlayMetrics.safeArea) -> WFOverlayGeometry {
        let safeWidth = max(0, viewport.width - safeArea * 2)
        let safeHeight = max(0, viewport.height - safeArea * 2)
        let width = clamp(desired.width, 0, safeWidth)
        let height = clamp(desired.height, 0, safeHeight)

        func room(_ side: WFOverlaySide) -> CGFloat {
            switch side {
            case .top: max(0, anchor.minY - safeArea - placement.gap)
            case .bottom: max(0, viewport.height - safeArea - anchor.maxY - placement.gap)
            case .left: max(0, anchor.minX - safeArea - placement.gap)
            case .right: max(0, viewport.width - safeArea - anchor.maxX - placement.gap)
            }
        }

        let preferredRoom = room(placement.preferredSide)
        let opposite = placement.preferredSide.opposite
        let oppositeRoom = room(opposite)
        let desiredAxis = placement.preferredSide.isVertical ? height : width
        var side = placement.preferredSide
        if placement.allowFlip, preferredRoom < desiredAxis {
            if oppositeRoom >= desiredAxis || oppositeRoom > preferredRoom {
                side = opposite
            }
        }

        let axisCapacity = side.isVertical ? safeHeight : safeWidth
        let panelWidth = width
        let panelHeight = side.isVertical
            ? clamp(height, 0, axisCapacity)
            : clamp(height, 0, safeHeight)
        let crossSize = side.isVertical ? panelWidth : panelHeight

        func align(_ start: CGFloat, _ end: CGFloat, _ size: CGFloat) -> CGFloat {
            let value: CGFloat = switch placement.alignment {
            case .start: start
            case .center: (start + end - size) / 2
            case .end: end - size
            }
            let lower = side.isVertical ? safeArea : safeArea
            let upper = (side.isVertical ? safeArea + safeWidth : safeArea + safeHeight) - size
            return clamp(value, lower, upper)
        }

        let cross = side.isVertical
            ? align(anchor.minX, anchor.maxX, crossSize)
            : align(anchor.minY, anchor.maxY, crossSize)

        let top: CGFloat = switch side {
        case .top:
            clamp(anchor.minY - placement.gap - panelHeight,
                  safeArea, safeArea + safeHeight - panelHeight)
        case .bottom:
            clamp(anchor.maxY + placement.gap,
                  safeArea, safeArea + safeHeight - panelHeight)
        case .left, .right:
            cross
        }

        let left: CGFloat = switch side {
        case .left:
            clamp(anchor.minX - placement.gap - panelWidth,
                  safeArea, safeArea + safeWidth - panelWidth)
        case .right:
            clamp(anchor.maxX + placement.gap,
                  safeArea, safeArea + safeWidth - panelWidth)
        case .top, .bottom:
            cross
        }

        return WFOverlayGeometry(rect: CGRect(x: left, y: top, width: panelWidth, height: panelHeight),
                                 side: side,
                                 flipped: side != placement.preferredSide)
    }

    private static func clamp(_ value: CGFloat, _ min: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        // 同 Flutter `_clampDouble`：上限小于下限时返回下限，而不是让 clamp 抛错。
        guard maxValue >= min else { return min }
        return Swift.min(Swift.max(value, min), maxValue)
    }
}
