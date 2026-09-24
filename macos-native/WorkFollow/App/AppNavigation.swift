import Combine

enum NativeDestination: String, CaseIterable, Identifiable {
    case today, inbox, allTasks, nextSevenDays, overdue, completed, trash, notes, notesTrash, calendar, matrix
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "今天"
        case .inbox: return "收集箱"
        case .allTasks: return "所有任务"
        case .nextSevenDays: return "最近 7 天"
        case .overdue: return "过期"
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
        case .allTasks: return "list.bullet.rectangle"
        case .nextSevenDays: return "calendar.badge.clock"
        case .overdue: return "clock.badge.exclamationmark"
        case .completed: return "checkmark.circle"
        case .trash, .notesTrash: return "trash"
        case .notes: return "text.alignleft"
        case .calendar: return "calendar"
        case .matrix: return "square.grid.2x2"
        }
    }
    var isTaskList: Bool { [.today, .inbox, .allTasks, .nextSevenDays, .overdue, .completed, .trash].contains(self) }
    var isNotes: Bool { self == .notes || self == .notesTrash }
}

@MainActor
final class AppNavigation: ObservableObject {
    @Published var destination: NativeDestination = .today
}
