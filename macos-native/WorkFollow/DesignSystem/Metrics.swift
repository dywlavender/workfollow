import Foundation

enum RailMetrics {
    /// 图标栏几何，按滴答清单的实测值对齐（2026-10-03）。
    ///
    /// 读数来源：滴答在跑，直接读它自己的 AX 树，`AXScrollArea @0,123 62x601`
    /// ——栏宽 62、每行 `62x48`（步长 48）、行内 `AXImage @15,131 32x32`
    /// （32 是图标**框**，左边距 15 = (62−32)/2，居中）。
    ///
    /// 图标**墨迹**（不是框）要从截图量：滴答的日历与四宫格都是 42px @2x = 21pt。
    /// 我们原来的日历是 33px = 16.5pt，所以字号 18 × 21/16.5 ≈ 23 才对得上。
    /// ⚠️ 别拿滴答的 32pt「图标框」当目标——那是它的容器，不是画出来的大小。
    ///
    /// `itemGap` 从 12 降到 10 是为了凑 pitch：38 + 10 = 48，与滴答的行距一致。
    ///
    /// 连带效应：`WFMetrics.railWidth` 直接取这个 width，于是
    /// `navigationBreakpoint` 871 → 881（导航栏在 881pt 宽才出现）。
    /// 另外 `MainWindowChromeGeometry.trafficLightFrames` 按 railWidth 给红绿灯居中，
    /// 栏变宽后它们会自动散开（间距上限 6 会生效），**不需要单独改**。
    static let width: CGFloat = 62
    static let iconSize: CGFloat = 23
    static let hitSize: CGFloat = 38
    static let selectedSize: CGFloat = 34
    static let selectedRadius: CGFloat = 10
    static let itemGap: CGFloat = 10
    static let topPadding: CGFloat = 16
}

enum WFMetrics {
    static let minimumWindow = CGSize(width: 360, height: 480)
    static let defaultWindow = CGSize(width: 1280, height: 820)
    static let railWidth: CGFloat = RailMetrics.width
    static let navigationWidth: CGFloat = 196
    /// 列表列宽度：任务列表与笔记列表**共用同一个值**（笔记页原来自己硬编码 330/300，
    /// 见 `NotesWorkspaceView`）。两处各写各的，用户在中栏来回切就会看到忽宽忽窄。
    ///
    /// `listPreferred` = 340 来自滴答清单的实测默认值，两个独立来源互证：
    /// ① 读它自己的 AX 树：`AXOutline @273,136 340x753`（`AXScrollArea` 338，
    ///    差额是左右边框）；② 用户给的截图在 2× 下量到面板边框 x=34..713 = 680px ÷ 2 = 340。
    /// 同一张截图里 62(图标栏) + 212(导航栏) + 338(任务列) + 900(详情) = 1512，
    /// 正好等于滴答窗口宽度，说明这条读法没漏掉任何一栏。
    ///
    /// `listMinimum` 必须跟着下调：默认值会被 `min(max(值, listMinimum), …)` 夹住，
    /// 若最小值还留在 380，340 会被顶回 380，改默认值等于白改。
    /// 300 不是新拍的数——笔记页在窄窗口下原本就用 300，是个已经跑过的宽度。
    /// 连带效应：`splitMinimum` 701→621、`navigationBreakpoint` 951→871，
    /// 即导航栏在更窄的窗口就会显示（默认窗口 1280，两条都远在门槛之上）。
    static let listMinimum: CGFloat = 300
    static let listPreferred: CGFloat = 340
    static let listMaximum: CGFloat = 470
    static let inspectorMinimum: CGFloat = 320
    static let divider: CGFloat = 1
    static let splitMinimum = listMinimum + inspectorMinimum + divider
    static let navigationBreakpoint = railWidth + navigationWidth + splitMinimum + 2 * divider
    static let rowHeight: CGFloat = 50
    static let rowVerticalPadding: CGFloat = 11
    static var rowContentMinHeight: CGFloat { rowHeight - rowVerticalPadding * 2 }
    static let controlHeight: CGFloat = 34
    static let corner: CGFloat = 8
    static let icon: CGFloat = 18
    static let secondaryMetadataLimit = 3
}
