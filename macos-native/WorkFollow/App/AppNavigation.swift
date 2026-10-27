import Combine
import Foundation

enum NativeDestination: String, CaseIterable, Identifiable {
    case today, tomorrow, inbox, allTasks, nextSevenDays, completed, abandoned, trash, notes, notesTrash, calendar, matrix
    case focus, summary, countdown, meetings
    static let taskDestinations: [NativeDestination] = [
        .nextSevenDays, .today, .tomorrow, .inbox, .summary, .allTasks, .completed, .abandoned, .trash
    ]
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "今天"
        case .tomorrow: return "明天"
        case .inbox: return "收集箱"
        case .allTasks: return "所有任务"
        case .nextSevenDays: return "最近 7 天"
        case .completed: return "已完成"
        case .abandoned: return "已放弃"
        case .trash, .notesTrash: return "垃圾桶"
        case .notes: return "全部笔记"
        case .calendar: return "日历"
        case .matrix: return "四象限"
        case .focus: return "专注"
        case .summary: return "摘要"
        case .countdown: return "倒数纪念日"
        case .meetings: return "会议纪要"
        }
    }
    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .tomorrow: return "sunrise"
        case .inbox: return "tray"
        case .allTasks: return "list.bullet.rectangle"
        case .nextSevenDays: return "calendar.badge.clock"
        case .completed: return "checkmark.circle"
        case .abandoned: return "xmark.square"
        case .trash, .notesTrash: return "trash"
        case .notes: return "text.alignleft"
        case .calendar: return "calendar"
        case .matrix: return "square.grid.2x2"
        case .focus: return "timer"
        case .summary: return "square.and.pencil"
        case .countdown: return "hourglass"
        case .meetings: return "mic.fill"
        }
    }
    var isTaskList: Bool { Self.taskDestinations.contains(self) }
    var isNotes: Bool { self == .notes || self == .notesTrash }
}

@MainActor
final class AppNavigation: ObservableObject {
    @Published var destination: NativeDestination = .today
    /// 跨窗口“在主页打开笔记”的请求。NotesWorkspaceView 消费后清空，
    /// 同时清搜索与筛选，避免目标笔记被当前过滤条件挡在列表外。
    @Published var noteRevealRequest: UUID?
    /// 从摘要或小组件“在日历中查看”时携带的一次性日期：日历消费后清空，
    /// 切到周视图并定位到该日期所在周。
    @Published var calendarRevealRequest: Date?
    init(destination: NativeDestination = .today) { self.destination = destination }

    var taskSelectionToPreserveOnNextNavigation: UUID?
}
