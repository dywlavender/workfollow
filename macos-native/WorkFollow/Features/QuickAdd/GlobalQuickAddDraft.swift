import Combine
import Foundation

/// 草稿随输入保存；收起、退出和重新启动都可继续，成功提交后清除。
@MainActor
final class GlobalQuickAddDraft: ObservableObject {
    @Published var text = "" { didSet { persist() } }
    @Published var description = "" { didSet { persist() } }
    @Published var dismissedTokens: Set<String> = [] { didSet { persist() } }
    @Published var schedule: QuickAddScheduleDraft? { didSet { persist() } }
    @Published var priority: TaskPriority? { didSet { persist() } }
    @Published var list: String? { didSet { persist() } }
    @Published var tags: [String]? { didSet { persist() } }
    @Published var attachments: [NativeAttachment] = [] { didSet { persist() } }

    struct Snapshot: Codable, Equatable {
        var text: String
        var description: String
        var dismissedTokens: Set<String>
        var schedule: QuickAddScheduleDraft?
        var priority: TaskPriority?
        var list: String?
        var tags: [String]?
        var attachments: [NativeAttachment]
    }
    static let storageKey = "globalQuickAddDraft.v1"
    private let defaults: UserDefaults
    private let key: String
    private var restoring = false

    init(defaults: UserDefaults = .standard, storageKey: String = GlobalQuickAddDraft.storageKey) {
        self.defaults = defaults
        self.key = storageKey
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            restoring = true
            text = saved.text; description = saved.description; dismissedTokens = saved.dismissedTokens
            schedule = saved.schedule; priority = saved.priority; list = saved.list
            tags = saved.tags; attachments = saved.attachments
            restoring = false
        }
    }

    var snapshot: Snapshot {
        Snapshot(text: text, description: description, dismissedTokens: dismissedTokens,
            schedule: schedule, priority: priority, list: list, tags: tags, attachments: attachments)
    }

    func replace(with value: Snapshot) {
        restoring = true
        text = value.text; description = value.description; dismissedTokens = value.dismissedTokens
        schedule = value.schedule; priority = value.priority; list = value.list
        tags = value.tags; attachments = value.attachments
        restoring = false
        persist()
    }

    private func persist() {
        guard !restoring else { return }
        guard hasContent else { defaults.removeObject(forKey: key); return }
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: key) }
    }

    var hasContent: Bool {
        !text.isEmpty || !description.isEmpty || schedule != nil || priority != nil
            || list != nil || tags != nil || !attachments.isEmpty
    }

    func clear() {
        text = ""; description = ""; dismissedTokens = []
        schedule = nil; priority = nil; list = nil; tags = nil; attachments = []
    }
}
