import Foundation

/// 搜索面板打开任务/笔记后，编辑器据此滚动到第一处命中并闪一下查找指示。
/// 每次请求带新 token：同一目标反复搜索同一关键词也会重新定位。
struct SearchRevealRequest: Equatable {
    let targetID: UUID
    let query: String
    let token: UUID

    init(targetID: UUID, query: String) {
        self.targetID = targetID
        self.query = query
        token = UUID()
    }
}
