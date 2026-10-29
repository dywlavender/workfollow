import Foundation

enum SummaryContentField: String, CaseIterable, Codable {
    case status = "状态", progress = "进度", completedTime = "完成时间", taskTime = "任务时间"
    case taskName = "任务名称", parentTask = "主任务", tags = "标签", focus = "专注数据"
    case list = "所属清单", detail = "详细内容"

    static let standard: Set<Self> = [.progress, .completedTime, .taskName]

    /// 标题独立展示；此顺序决定辅助信息的先后，完成时间在辅助行开头，详细内容尾随。
    static let inlineOrder: [Self] = [
        .taskName, .status, .progress, .taskTime, .parentTask, .tags, .focus, .list,
    ]

    var isInline: Bool { Self.inlineOrder.contains(self) }

    var anchor: String {
        switch self {
        case .status: "status"
        case .progress: "progress"
        case .completedTime: "completedTime"
        case .taskTime: "taskTime"
        case .taskName: "taskName"
        case .parentTask: "parentTask"
        case .tags: "tags"
        case .focus: "focus"
        case .list: "list"
        case .detail: "detail"
        }
    }
}

enum SummaryDateStyle: String, CaseIterable, Codable {
    case date = "日期"
    case dateTime = "日期+时间"

    var anchor: String {
        switch self {
        case .date: "date"
        case .dateTime: "dateTime"
        }
    }
}

enum SummaryListStyle: String, CaseIterable, Codable {
    case list = "清单"
    case listGroup = "清单-分组"

    var anchor: String {
        switch self {
        case .list: "list"
        case .listGroup: "listGroup"
        }
    }
}

enum SummaryDetailStyle: String, CaseIterable, Codable {
    case formatted = "保留格式"
    case plain = "纯文本"

    var anchor: String {
        switch self {
        case .formatted: "formatted"
        case .plain: "plain"
        }
    }
}

/// 各字段的展示样式。默认值刻意对齐旧版输出：
/// 完成时间只带日期，任务时间在任务本身有具体时间时才带时间，
/// 所属清单只显示清单名，详细内容保留格式。
struct SummaryContentStyles: Codable, Equatable {
    var completedTime: SummaryDateStyle = .date
    var taskTime: SummaryDateStyle = .dateTime
    var list: SummaryListStyle = .list
    var detail: SummaryDetailStyle = .formatted

    static let standard = SummaryContentStyles()

    private enum CodingKeys: String, CodingKey {
        case completedTime, taskTime, list, detail
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        completedTime = try values.decodeIfPresent(SummaryDateStyle.self, forKey: .completedTime) ?? .date
        taskTime = try values.decodeIfPresent(SummaryDateStyle.self, forKey: .taskTime) ?? .dateTime
        list = try values.decodeIfPresent(SummaryListStyle.self, forKey: .list) ?? .list
        detail = try values.decodeIfPresent(SummaryDetailStyle.self, forKey: .detail) ?? .formatted
    }

    mutating func setDateStyle(_ style: SummaryDateStyle, for field: SummaryContentField) {
        switch field {
        case .completedTime: completedTime = style
        case .taskTime: taskTime = style
        default: break
        }
    }

    func styleLabel(for field: SummaryContentField) -> String? {
        switch field {
        case .completedTime: completedTime.rawValue
        case .taskTime: taskTime.rawValue
        case .list: list.rawValue
        case .detail: detail.rawValue
        default: nil
        }
    }
}
