import Foundation

/// 摘要的分组方式（对齐滴答「显示设置 → 分组」）。
///
/// 只决定**自动生成段**的二级标题怎么切；用户手写的部分不受影响。
enum SummaryGrouping: String, CaseIterable, Codable {
    case completion = "按完成状态"
    case list = "按清单"
    case completedTime = "按完成时间"
    case taskTime = "按任务时间"
    case tag = "按标签"
    case priority = "按优先级"
    case assignee = "按指派人"

    var isAvailable: Bool { self != .assignee }
}

/// 摘要里的一段：二级标题 + 条目。
struct SummarySection: Equatable {
    let title: String
    let items: [ReviewItem]
}
