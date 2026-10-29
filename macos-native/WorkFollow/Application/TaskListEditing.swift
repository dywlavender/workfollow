import Foundation

struct TaskListEditingDraft: Equatable {
    var name = ""
    var icon: String?
    var colorIndex: Int?
    var colorARGB: UInt32?
    var folderName: String?
    var showsInSmartLists = true
    var remindersEnabled = true
    var isDefault = false

    init(meta: TaskListMeta? = nil) {
        guard let meta else { return }
        name = meta.name; icon = meta.icon; colorIndex = meta.colorIndex; colorARGB = meta.colorARGB
        folderName = meta.folderName; showsInSmartLists = !meta.hidesFromSmartLists
        remindersEnabled = !meta.remindersMuted; isDefault = meta.isDefault
    }

    static func nameError(_ raw: String, existing: [String], replacing old: String? = nil) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "请输入清单名称" }
        if name == TaskList.inbox.name || name == TaskList.notes.name { return "请使用其他清单名称" }
        if name != old && existing.contains(name) { return "清单名称已存在" }
        if name != old && name.rangeOfCharacter(from: CharacterSet(charactersIn: "\\/\"#：:*?<>|")) != nil {
            return "名称不能包含 \\ / \" # ： : * ? < > |"
        }
        return nil
    }
}

enum TaskListCopyScope: String, CaseIterable, Identifiable {
    case allPreservingStatus, allResettingStatus, incomplete
    var id: String { rawValue }
    var title: String {
        switch self {
        case .allPreservingStatus: "全部任务，保留已完成状态"
        case .allResettingStatus: "全部任务，不保留已完成状态"
        case .incomplete: "只复制未完成任务"
        }
    }
}
