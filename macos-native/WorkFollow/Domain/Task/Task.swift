import Foundation

enum TaskPriority: Int, Equatable { case none = 0, low, medium, high }
enum TaskStatus: Equatable { case active, completed }

struct TaskList: Equatable {
    let name: String
    init(name: String) { self.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
    static let inbox = TaskList(name: "收集箱")
}

/// Schedule and deadline are intentionally distinct. Calendar is injected into projections.
struct TaskSchedule: Equatable {
    var dueAt: Date?
    var hasTime: Bool
    var deadlineAt: Date?
    init(dueAt: Date? = nil, hasTime: Bool = false, deadlineAt: Date? = nil) {
        self.dueAt = dueAt
        self.hasTime = dueAt != nil && hasTime
        self.deadlineAt = deadlineAt
    }
}

/// Value entity, independent of SwiftUI, AppKit, persistence and preview fixtures.
struct Task: Identifiable, Equatable {
    let id: UUID
    var title: String
    var document: NativeDocument = .empty
    var list: TaskList
    var priority: TaskPriority
    var schedule: TaskSchedule
    var status: TaskStatus = .active
    let parentID: UUID?
    let childOrder: Int
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var deletedAt: Date?
}
