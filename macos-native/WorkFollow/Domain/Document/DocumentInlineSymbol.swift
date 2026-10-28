import Foundation

/// A one-character text fallback keeps generated annotations readable outside
/// the native editor. The editor and image/PDF export draw the matching symbol.
enum DocumentInlineSymbol: String, Codable, Hashable {
    case completed = "checkmark.circle"
    case pending = "circle"
    case inProgress = "circle.lefthalf.filled"
    case abandoned = "xmark.circle"
    case calendar = "calendar"
    case list = "list.bullet.rectangle"
    case inbox = "tray"
    case tag = "tag"
    case parent = "arrow.turn.up.left"
    case focus = "timer"
    case progress = "chart.pie"

    var textFallback: String {
        switch self {
        case .completed: "✓"
        case .pending: "○"
        case .inProgress, .progress: "◐"
        case .abandoned: "×"
        case .calendar: "◷"
        case .list, .inbox: "▤"
        case .tag: "#"
        case .parent: "↳"
        case .focus: "◴"
        }
    }
}
