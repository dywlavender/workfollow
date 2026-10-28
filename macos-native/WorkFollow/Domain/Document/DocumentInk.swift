import Foundation

/// Semantic colors survive editing and copy/paste without freezing a theme.
enum DocumentInk: Hashable, Codable {
    case accent, danger, argb(UInt32)

    var token: String {
        switch self {
        case .accent: "accent"
        case .danger: "danger"
        case .argb(let value): "argb:\(value)"
        }
    }
    init?(token: String) {
        switch token {
        case "accent": self = .accent
        case "danger": self = .danger
        default:
            guard token.hasPrefix("argb:"), let value = UInt32(token.dropFirst(5)) else { return nil }
            self = .argb(value)
        }
    }
}
