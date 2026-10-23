import SwiftUI

extension TaskPriority {
    var menuColor: Color {
        switch self {
        // 与滴答截图取到的四个旗子色一致；全项目只有这一处定义。
        case .high: WFColors.priorityHigh
        case .medium: WFColors.priorityMedium
        case .low: WFColors.priorityLow
        case .none: WFColors.priorityNone
        }
    }
}
