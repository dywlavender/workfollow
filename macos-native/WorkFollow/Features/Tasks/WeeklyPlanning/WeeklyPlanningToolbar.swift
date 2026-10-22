import SwiftUI

struct WeeklyPlanningToolbar: View {
    @ObservedObject var context: WeeklyPlanningContext
    let listNames: [String]

    var body: some View {
        HStack(spacing: 10) {
            Button { context.shift(-1) } label: { Image(systemName: "chevron.left") }
                .help("上一周").accessibilityLabel("上一周")
            BusinessMenu {
                ForEach(-12...4, id: \.self) { offset in
                    let current = SummaryReviewBuilder.weekStart(of: context.clock(), calendar: context.calendar)
                    let week = context.calendar.date(byAdding: .day, value: offset * 7, to: current)!
                    BusinessMenuOption(SummaryReviewBuilder.weekTitle(for: week, calendar: context.calendar),
                                       selected: context.calendar.isDate(context.weekStart, inSameDayAs: week)) { context.weekStart = week }
                }
            } label: {
                Text(context.title).font(WFType.section).foregroundStyle(WFColors.text)
            }
            .fixedSize()
            Button { context.shift(1) } label: { Image(systemName: "chevron.right") }
                .help("下一周").accessibilityLabel("下一周")
            if !context.isCurrent { Button("回到本周") { context.goCurrent() }.font(WFType.supporting) }
            Spacer(minLength: 8)
            BusinessMenu {
                BusinessMenuOption("所有清单", selected: context.listName == nil) { context.listName = nil }
                Divider()
                ForEach(listNames, id: \.self) { name in
                    BusinessMenuOption(name, selected: context.listName == name, symbol: "tray") { context.listName = name }
                }
            } label: {
                Label(context.listName ?? "所有清单", systemImage: "line.3.horizontal.decrease")
                    .lineLimit(1).frame(maxWidth: 160)
            }
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .foregroundStyle(WFColors.secondaryText)
        .padding(.horizontal, 24).padding(.vertical, 12)
    }
}
