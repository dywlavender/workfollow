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

@MainActor
final class AppNavigation: ObservableObject {
    @Published var destination: NativeDestination = .today
}
