import SwiftUI

enum SchedulePopoverLayoutV2 {
    static let panelWidth: CGFloat = ScheduleMetrics.panelWidth
    static let panelHeight: CGFloat = 506
    static let screenMargin: CGFloat = 32

    /// Resolve once when opening, never from expanded content's intrinsic size.
    static func height(availableHeight: CGFloat, repeating: Bool = false, period: Bool = false) -> CGFloat {
        let contentHeight = panelHeight + (repeating ? ScheduleMetrics.rowHeight : 0)
            + (period ? ScheduleMetrics.rowHeight + 24 : 0)
        return min(contentHeight, max(440, availableHeight - screenMargin))
    }
}

/// Fixed calendar region and bounded property viewport. Child editors live in
/// separate anchored windows, never in this viewport's layout.
struct SchedulePopoverContainer<CalendarSection: View, PropertyContent: View, Footer: View>: View {
    let height: CGFloat
    @ViewBuilder let calendarSection: () -> CalendarSection
    @ViewBuilder let propertyContent: () -> PropertyContent
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 12) {
            calendarSection()
                .fixedSize(horizontal: false, vertical: true)
                .scheduleRenderAnchor(.calendarSection)
            ScrollView(.vertical) {
                propertyContent()
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .scheduleRenderAnchor(.propertyViewport)
            footer()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ScheduleMetrics.horizontalPadding)
        .frame(width: SchedulePopoverLayoutV2.panelWidth, height: height, alignment: .top)
        .clipped()
        .scheduleRenderAnchor(.panel)
    }
}
