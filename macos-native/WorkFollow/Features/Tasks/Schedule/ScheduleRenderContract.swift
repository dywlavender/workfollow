import SwiftUI

enum ScheduleRenderAnchor: Hashable {
    case panel, calendarSection, propertyViewport, shortcut(String)
    case row(TaskDatePopoverV2.InlineSheet), icon(TaskDatePopoverV2.InlineSheet)
    case trailing(TaskDatePopoverV2.InlineSheet)
    case expandedRow(TaskDatePopoverV2.InlineSheet), expandedContent(TaskDatePopoverV2.InlineSheet)
    case mainFooter, editorFooter(TaskDatePopoverV2.InlineSheet), option(String)
}
struct ScheduleRenderValue: Equatable {
    var frame: CGRect
    var label: String
    var active: Bool
}
struct ScheduleFramesKey: PreferenceKey {
    static let defaultValue: [ScheduleRenderAnchor: ScheduleRenderValue] = [:]
    static func reduce(value: inout [ScheduleRenderAnchor: ScheduleRenderValue],
                       nextValue: () -> [ScheduleRenderAnchor: ScheduleRenderValue]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
extension View {
    @ViewBuilder
    func scheduleRenderAnchor(_ anchor: ScheduleRenderAnchor, label: String = "", active: Bool = false) -> some View {
        #if DEBUG
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: ScheduleFramesKey.self, value: [anchor: ScheduleRenderValue(
                    frame: geometry.frame(in: .named("schedule-render")), label: label, active: active)])
            }
        }
        #else
        self
        #endif
    }
}
