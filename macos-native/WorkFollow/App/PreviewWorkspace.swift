import Foundation
import Combine

/// Transitional shell fixtures, removed after Task UI moves to the Domain.
struct PreviewTask: Identifiable {
    let id: UUID
    var title: String
    var list: String
    var scheduledToday: Bool
    var completed: Bool
    var priority: Bool

    init(_ title: String, list: String = "收集箱", today: Bool = true,
         completed: Bool = false, priority: Bool = false) {
        id = UUID()
        self.title = title
        self.list = list
        scheduledToday = today
        self.completed = completed
        self.priority = priority
    }
}

@MainActor
final class PreviewWorkspace: ObservableObject {
    @Published private(set) var selectedTaskID: UUID?
    @Published private(set) var tasks: [PreviewTask] = [
        PreviewTask("整理本周用户反馈", list: "工作", priority: true),
        PreviewTask("阅读《设计心理学》第四章", list: "学习"),
        PreviewTask("准备季度复盘材料", list: "工作"),
        PreviewTask("记录下次旅行的想法", list: "个人", today: false),
        PreviewTask("确认本周安排", completed: true),
    ]

    var selectedTask: PreviewTask? { tasks.first { $0.id == selectedTaskID } }
    func projectedTasks(for destination: NativeDestination) -> [PreviewTask] {
        switch destination {
        case .today: return tasks.filter { $0.scheduledToday && !$0.completed }
        case .inbox: return tasks.filter { $0.list == "收集箱" && !$0.completed }
        case .completed: return tasks.filter(\.completed)
        default: return []
        }
    }

    func select(_ id: UUID?) { selectedTaskID = id }

    func selectAdjacent(_ offset: Int, in destination: NativeDestination) {
        let rows = projectedTasks(for: destination)
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selectedTaskID }
        let index = current.map { min(max($0 + offset, 0), rows.count - 1) }
            ?? (offset < 0 ? rows.count - 1 : 0)
        selectedTaskID = rows[index].id
    }

    func addTask(_ title: String, to destination: NativeDestination) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let task = PreviewTask(title, today: destination != .inbox)
        tasks.append(task)
    }

    func toggleCompletion(_ id: UUID, in destination: NativeDestination) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].completed.toggle()
        if selectedTaskID == id && !projectedTasks(for: destination).contains(where: { $0.id == id }) {
            selectedTaskID = nil
        }
    }
}
