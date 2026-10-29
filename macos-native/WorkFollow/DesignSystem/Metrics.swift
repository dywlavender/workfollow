import Foundation

enum RailMetrics {
    /// 图标栏几何，按滴答清单的实测值对齐（2026-10-03）。
    ///
    /// 读数来源：滴答在跑，直接读它自己的 AX 树，`AXScrollArea @0,123 62x601`
    /// ——栏宽 62、每行 `62x48`（步长 48）、行内 `AXImage @15,131 32x32`
    /// （32 是图标**框**，左边距 15 = (62−32)/2，居中）。
    ///
    /// 图标**墨迹**（不是框）要从截图量，而且**基准是栏里第 2 个元素**。
    ///
    /// ⚠️ 栏里**第 1 个不是图标，是用户头像**：实测 65x72px = 32.5x36pt，
    /// 比图标大一截。拿它当基准会把我们的图标定得过大。真正的图标基准是
    /// **第 2 个（任务）42x42px = 21pt**，其余图标 42~44px。
    ///
    /// 同理别拿 `AXImage 32x32` 当目标——那是滴答图标的**容器框**，不是画出来的大小。
    ///
    /// 第二轮校正（2026-10-03，用户指出「我们的比滴答的大」）：字号 23 时我们实测
    /// 墨迹 41~52px（中位 46），比滴答的 42~44（中位 42）大约 10%；且选中底色
    /// 34pt = 68px，是滴答选中态（42px，即图标自身填色）的 1.6 倍。
    /// 故 `iconSize` 23 → 21（墨迹落到 37~47px、中位 42，与基准对齐）。
    ///
    /// 第三轮（2026-10-03，用户指出「图标不一样，为什么选中后的颜色图案和滴答一样」）：
    /// 复量滴答的选中态，确认那块蓝**就是图标本体**——`40x40px = 20pt`，与旁边
    /// 灰图标墨迹同量级，背后**没有**底色块。我们原来抄了那块底、却留着描边图标，
    /// 于是蓝块成了贴上去的色块。两头现已对齐：图标全部换实心（见 `SidebarViews`
    /// 里 `IconRailView` 的注释），**选中态改为图标自己变蓝，`selectedSize` /
    /// `selectedRadius` 与 `.railSelectedBackground` 锚点一并删除**。
    ///
    /// `hitSize` 不动仍是 38：它是**不可见的点按区**，38 + `itemGap` 10 = pitch 48，
    /// 与滴答行距一致；把它改小只会牺牲可点性、还会连带改 pitch。
    ///
    /// 连带效应：`WFMetrics.railWidth` 直接取这个 width，`navigationBreakpoint`
    /// 随之变大（导航栏需要更宽的窗口才出现；具体值见 `WFMetrics` 里的公式）。
    /// 另外 `MainWindowChromeGeometry.trafficLightFrames` 按 railWidth 给红绿灯居中，
    /// 栏变宽后它们会自动散开（间距上限 6 会生效），**不需要单独改**。
    static let width: CGFloat = 62
    static let iconSize: CGFloat = 21
    static let hitSize: CGFloat = 38
    static let itemGap: CGFloat = 10
    static let topPadding: CGFloat = 16
}

/// 导航栏（左起第二栏）的行几何。
///
/// 这一栏的行高 `32` 原来硬编码在 **6 处**：`SidebarViews` 里 4 处
/// （智能清单行、笔记行、新建过滤器、过滤器行）+ `TaskManagementViews` 里 2 处
/// （清单行、标签行）。2026-10-03 用户报「每一行间距太近」，要求 +10%，
/// 顺手收成一个常量——下次调整只改这里，不会再出现只改一半、同一栏两种行距。
///
/// 取值：原 32 → 35（+9.4%，来自"行距太近、加 10%"的要求）→ **38**。
/// 2026-10-17 同窗口 AX 实测滴答导航行：`AXRow @62,45 212x38`，连续行 y=45/83/121
/// 步长 38、行间无额外间距，故本地统一改为 38，与滴答行高一致。
enum NavigationMetrics {
    static let rowHeight: CGFloat = 38
}

/// 列表行（任务列表 / 笔记列表共用）的行分割线几何。
///
/// 两栏原来各画各的：任务列表是 `Rectangle().fill(WFColors.hover)`（4% 墨色，
/// 左内缩 30、完成行 58 + depth×24，右内缩 16），笔记列表是系统 `Divider()`
/// （深一档，左右各缩 12，且选中行不画）。同一个人在两栏之间来回切，看到的是
/// 两种线。
///
/// 参照滴答清单实测（2026-10-03，AX 行框 + 分割线像素位置 + 勾选框中心距
/// 三条路径互证）：分割线是 1pt、`#F4F4F4`，**落在行的最后一像素里**——它的
/// 行距是 0，相邻两行的分割线正好压在上一行的底边上，不额外占高度。左端从
/// 标题文字的左边缘起（跳过勾选框列），右端让开它那条常驻滚动条。
///
/// 我们沿用它的**规则**，不照抄绝对值：我们的滚动条是 overlay 式、不占宽度，
/// 所以右内缩只留行自身的横向内边距；左内缩按各栏文字的实际左边缘给
/// （任务行有勾选框列、笔记行没有，两者差 46pt）。
enum ListRowMetrics {
    static let dividerHeight: CGFloat = 1
    /// 笔记行的文字左边缘：行内 `.padding(.horizontal, 12)`，没有勾选框列。
    static let notesDividerLeading: CGFloat = 12
}

enum WFMetrics {
    static let minimumWindow = CGSize(width: 360, height: 480)
    static let defaultWindow = CGSize(width: 1280, height: 820)
    static let railWidth: CGFloat = RailMetrics.width
    /// Fixed navigation column: 212pt in the 8.0.80 runtime reference.
    /// The task column remains independently resizable; its observed width is
    /// not a replacement for the user's saved list width.
    static let navigationWidth: CGFloat = 212
    /// 列表列宽度：任务列表与笔记列表**共用同一个值**（笔记页原来自己硬编码 330/300，
    /// 见 `NotesWorkspaceView`）。两处各写各的，用户在中栏来回切就会看到忽宽忽窄。
    ///
    /// 2026-10-30 按用户反馈，两栏一起从 360 降到 320：笔记行只有标题 + 单行预览，
    /// 360 用不满；任务列表保持同宽，切换时中栏不跳。360 原来自 2026-10-17 同窗口
    /// AX 实测滴答 `AXOutline @273,136 360×2684`，这次是为可读性主动偏离，不再是实测值。
    ///
    /// `listMinimum` 必须跟着下调：默认值会被 `min(max(值, listMinimum), …)` 夹住，
    /// 若最小值还留在 380，340 会被顶回 380，改默认值等于白改。
    /// 300 不是新拍的数——笔记页在窄窗口下原本就用 300，是个已经跑过的宽度。
    /// 连带效应：`splitMinimum` 由 `listMinimum` 派生（现为 621），`navigationBreakpoint`
    /// 随之变小，即导航栏在更窄的窗口就会显示（默认窗口 1280，两者都远在门槛之上）。
    static let listMinimum: CGFloat = 300
    static let listPreferred: CGFloat = 320
    static let listMaximum: CGFloat = 470
    static let inspectorMinimum: CGFloat = 320
    static let divider: CGFloat = 1
    static let splitMinimum = listMinimum + inspectorMinimum + divider
    /// 两处列分隔线改为覆盖绘制，不再占布局，断点里也不再计入两个 `divider`。
    static let navigationBreakpoint = railWidth + navigationWidth + splitMinimum
    static let rowHeight: CGFloat = 50
    static let rowVerticalPadding: CGFloat = 11
    static var rowContentMinHeight: CGFloat { rowHeight - rowVerticalPadding * 2 }
    static let controlHeight: CGFloat = 34
    static let corner: CGFloat = 8
    static let icon: CGFloat = 18
    static let secondaryMetadataLimit = 3
}
