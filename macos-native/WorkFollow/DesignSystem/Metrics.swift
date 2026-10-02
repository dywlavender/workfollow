import Foundation

enum RailMetrics {
    static let width: CGFloat = 52
    static let iconSize: CGFloat = 18
    static let hitSize: CGFloat = 34
    static let selectedSize: CGFloat = 30
    static let selectedRadius: CGFloat = 9
    static let itemGap: CGFloat = 12
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
