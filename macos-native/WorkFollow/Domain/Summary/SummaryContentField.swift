import Foundation

enum SummaryContentField: String, CaseIterable, Codable {
    case status = "状态", progress = "进度", completedTime = "完成时间", taskTime = "任务时间"
    case taskName = "任务名称", parentTask = "主任务", tags = "标签", focus = "专注数据"
    case list = "所属清单", detail = "详细内容"

    static let standard: Set<Self> = [.progress, .completedTime, .taskName]
}
