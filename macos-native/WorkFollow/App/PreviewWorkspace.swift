import Foundation
import Combine

enum NativeDestination: String, CaseIterable, Identifiable {
    case today, inbox, completed, trash, notes, notesTrash, calendar, matrix
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "今天"
        case .inbox: return "收集箱"
        case .completed: return "已完成"
        case .trash, .notesTrash: return "垃圾桶"
        case .notes: return "全部笔记"
        case .calendar: return "日历"
        case .matrix: return "四象限"
        }
    }
    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .inbox: return "tray"
        case .completed: return "checkmark.circle"
        case .trash, .notesTrash: return "trash"
        case .notes: return "text.alignleft"
        case .calendar: return "calendar"
        case .matrix: return "square.grid.2x2"
        }
    }
    var isTaskList: Bool { [.today, .inbox, .completed, .trash].contains(self) }
    var isNotes: Bool { self == .notes || self == .notesTrash }
}

/// Disposable shell fixtures. Full TaskItem/TaskActions migration belongs to
/// Phase 2; this type is deliberately not a production persistence schema.
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
    @Published private(set) var destination: NativeDestination = .today
    @Published private(set) var selectedTaskID: UUID?
    @Published private(set) var tasks: [PreviewTask] = [
        PreviewTask("整理本周用户反馈", list: "工作", priority: true),
        PreviewTask("阅读《设计心理学》第四章", list: "学习"),
        PreviewTask("准备季度复盘材料", list: "工作"),
        PreviewTask("记录下次旅行的想法", list: "个人", today: false),
        PreviewTask("确认本周安排", completed: true),
    ]

    var selectedTask: PreviewTask? { tasks.first { $0.id == selectedTaskID } }
    var visibleTasks: [PreviewTask] { projectedTasks(for: destination) }

    func projectedTasks(for destination: NativeDestination) -> [PreviewTask] {
        switch destination {
        case .today: return tasks.filter { $0.scheduledToday && !$0.completed }
        case .inbox: return tasks.filter { $0.list == "收集箱" && !$0.completed }
        case .completed: return tasks.filter(\.completed)
        default: return []
        }
    }

    func navigate(to destination: NativeDestination) {
        self.destination = destination
        selectedTaskID = nil
    }

    func select(_ id: UUID?) { selectedTaskID = id }

    func selectAdjacent(_ offset: Int) {
        let rows = visibleTasks
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selectedTaskID }
        let index = current.map { min(max($0 + offset, 0), rows.count - 1) }
            ?? (offset < 0 ? rows.count - 1 : 0)
        selectedTaskID = rows[index].id
    }

    func addTask(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let task = PreviewTask(title, today: destination != .inbox)
        tasks.append(task)
    }

    func toggleCompletion(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].completed.toggle()
        if selectedTaskID == id && !visibleTasks.contains(where: { $0.id == id }) {
            selectedTaskID = nil
        }
    }
}
