import Foundation

/// 摘要的筛选与展示条件（对齐滴答右侧配置的「筛选 / 显示内容 / 更多」）。
///
/// 只影响「自动生成段」的取样与条目内容，不改变已保存的正文；
/// 用户改动仍以独立保存的摘要文档为准。
struct SummaryFilter: Equatable, Codable {
    enum Status: String, CaseIterable, Codable {
        case all = "所有状态"
        case completed = "已完成"
        case inProgress = "进行中"
        case uncompleted = "未完成"
        case abandoned = "已放弃"
    }

    /// 清单筛选：nil = 所有清单。
    var listName: String?
    var status: Status = .all
    /// 「更多」里的标签筛选：nil = 不限标签。
    var tagName: String?
    var priority: TaskPriority?

    // MARK: 显示内容（对齐滴答「显示内容 N 项」）

    /// 条目是否带日期前缀（如「10月20日」）。
    var showsDate = true
    /// 条目是否带清单名。
    var showsList = false
    /// 条目是否带标签（形如「#紧急」）。
    var showsTags = false

    /// 「显示内容」当前开了几项（右栏文案用）。
    var contentOptionCount: Int {
        [showsDate, showsList, showsTags].filter { $0 }.count
    }

    static let all = SummaryFilter()

    // MARK: Codable

    /// `tagName` / `priority` / `shows*` 是后加的字段，旧档案里没有。
    /// 用逐字段 `decodeIfPresent` 回落默认值，否则合成解码会直接 keyNotFound。
    private enum CodingKeys: String, CodingKey {
        case listName, status, tagName, priority, showsDate, showsList, showsTags
    }

    init(listName: String? = nil, status: Status = .all, tagName: String? = nil,
         priority: TaskPriority? = nil, showsDate: Bool = true,
         showsList: Bool = false, showsTags: Bool = false) {
        self.listName = listName
        self.status = status
        self.tagName = tagName
        self.priority = priority
        self.showsDate = showsDate
        self.showsList = showsList
        self.showsTags = showsTags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        listName = try container.decodeIfPresent(String.self, forKey: .listName)
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .all
        tagName = try container.decodeIfPresent(String.self, forKey: .tagName)
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority)
        showsDate = try container.decodeIfPresent(Bool.self, forKey: .showsDate) ?? true
        showsList = try container.decodeIfPresent(Bool.self, forKey: .showsList) ?? false
        showsTags = try container.decodeIfPresent(Bool.self, forKey: .showsTags) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(listName, forKey: .listName)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(tagName, forKey: .tagName)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encode(showsDate, forKey: .showsDate)
        try container.encode(showsList, forKey: .showsList)
        try container.encode(showsTags, forKey: .showsTags)
    }
}
