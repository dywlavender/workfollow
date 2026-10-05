import Foundation

/// 分组标题菜单的条目表——**单一真值源**（与滴答对照图一致）。
///
/// 抽成数据表是为了自绘菜单那一步：滴答那版菜单是大圆角 + 宽内距 + 子菜单带搜索框，
/// 系统 `Menu` 做不出来，必须自己画；自绘时如果**另写一份条目**，一定会出现
/// "系统菜单改了、自绘菜单忘了改"的漂移。所以条目、文案、图标都放这里，
/// 视图只负责渲染与分发动作。
///
/// 顺序与文案以用户提供的滴答截图为准：重命名 → 在上方添加分组 → 在下方添加分组
/// → 移动到 → 删除（都带图标，且不带省略号——"删除后任务保留"本来就在确认弹窗里说）。
enum SectionMenuEntry: String, CaseIterable, Identifiable {
    case rename
    case addAbove
    case addBelow
    case moveTo
    case delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rename: "重命名"
        case .addAbove: "在上方添加分组"
        case .addBelow: "在下方添加分组"
        case .moveTo: "移动到"
        case .delete: "删除"
        }
    }

    var symbol: String {
        switch self {
        case .rename: "pencil"
        case .addAbove: "arrow.up.square"
        case .addBelow: "arrow.down.square"
        case .moveTo: "folder"
        case .delete: "trash"
        }
    }

    /// 渲染顺序（= 对照图里的自上而下）。
    static let ordered: [SectionMenuEntry] = [.rename, .addAbove, .addBelow, .moveTo, .delete]
}
