import Combine
import Foundation

/// 草稿跟随控制器，而不是弹出窗口；收起窗口只结束本次输入，不丢弃内容。
@MainActor
final class GlobalQuickAddDraft: ObservableObject {
    @Published var text = ""
    @Published var description = ""
    @Published var dismissedTokens: Set<String> = []
    @Published var schedule: QuickAddScheduleDraft?
    @Published var priority: TaskPriority?
    @Published var list: String?
    @Published var tags: [String]?
    @Published var attachments: [NativeAttachment] = []

    var hasContent: Bool {
        !text.isEmpty || !description.isEmpty || schedule != nil || priority != nil
            || list != nil || tags != nil || !attachments.isEmpty
    }

    func clear() {
        text = ""; description = ""; dismissedTokens = []
        schedule = nil; priority = nil; list = nil; tags = nil; attachments = []
    }
}
