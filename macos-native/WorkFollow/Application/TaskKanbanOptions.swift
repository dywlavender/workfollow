import Foundation

enum TaskKanbanSize: String, CaseIterable, Codable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { switch self { case .small: "小"; case .medium: "中"; case .large: "大" } }
    var columnWidth: CGFloat { switch self { case .small: 216; case .medium: 264; case .large: 328 } }
}

struct TaskKanbanOptions: Equatable, Codable {
    var size: TaskKanbanSize = .medium
    var showsInput = true
    var showsChecklist = true
}

struct TaskKanbanChecklistItem: Identifiable {
    let id: UUID
    let text: String
    let checked: Bool

    static func items(in task: Task) -> [TaskKanbanChecklistItem] {
        guard task.kind == .checklist else { return [] }
        return task.document.blocks.compactMap { block in
            guard case .checklist(let checked) = block.kind else { return nil }
            return TaskKanbanChecklistItem(id: block.id, text: block.plainText, checked: checked)
        }
    }
}
