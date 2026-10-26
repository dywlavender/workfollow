import Foundation

/// 列表「⋯ → 显示设置」的日期显示口径（滴答：任务时间 / 倒数日）。
enum TaskDateDisplayMode: String, CaseIterable, Identifiable {
    case taskTime
    case countdown

    static let defaultsKey = "taskDateDisplayMode"
    /// 菜单顺序与滴答截图一致，声明顺序不参与 UI。
    static let menuOrder: [TaskDateDisplayMode] = [.taskTime, .countdown]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .taskTime: "任务时间"
        case .countdown: "倒数日"
        }
    }
}

/// 窗口宽度不足时任务详情的容器形态（滴答：侧边栏 / 弹窗）。
enum TaskDetailLayout: String, CaseIterable, Identifiable {
    case sidePeek
    case popup

    static let defaultsKey = "taskDetailLayout"
    static let menuOrder: [TaskDetailLayout] = [.sidePeek, .popup]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sidePeek: "侧边栏"
        case .popup: "弹窗"
        }
    }
}
