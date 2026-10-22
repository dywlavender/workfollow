import SwiftUI

extension TaskPriority {
    var menuColor: Color {
        switch self {
        case .high: WFColors.danger
        case .medium: WFColors.warning
        case .low: WFColors.accent
        case .none: WFColors.secondaryText
        }
    }
}
