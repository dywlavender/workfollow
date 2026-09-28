import SwiftUI

/// Self-drawn month calendar for the date popover: year/month header with
/// navigation, weekday row and a 6×7 day grid. Day cells show the day number
/// plus a festival label; the selected day is a filled accent disc, today gets
/// a ring, and range mode highlights the span between start and end.
struct LunarMonthGridView: View {
    let calendar: Calendar
    @Binding var displayedMonth: Date
    let today: Date
    var selection: Date?
    var range: ClosedRange<Date>?
    let onSelect: (Date) -> Void

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    /// Fixed Chinese labels: the app copy is zh, and symbols from the user
    /// calendar would localize the weekday row (and repeat letters break ForEach ids).
    private static let weekdayLabels = ["日", "一", "二", "三", "四", "五", "六"]

    /// The reference design always starts weeks on Sunday, regardless of the
    /// user's system preference; only layout uses this, date math is unchanged.
    private var layoutCalendar: Calendar {
        var value = calendar
        value.firstWeekday = 1
        return value
    }

    var body: some View {
        VStack(spacing: 4) {
            header
            weekdayRow
            LazyVGrid(columns: Self.columns, spacing: 2) {
                ForEach(MonthGridCalculator.cells(displayedMonth: displayedMonth, calendar: layoutCalendar)) { cell in
                    GridDayCell(
                        day: calendar.component(.day, from: cell.date),
                        inMonth: cell.inMonth,
                        festival: cell.inMonth ? LunarCalendarService.festivalLabel(for: cell.date, calendar: calendar) : nil,
                        isToday: calendar.isDate(cell.date, inSameDayAs: today),
                        isSelected: isFilled(cell.date),
                        isRangeMiddle: isRangeMiddle(cell.date),
                        action: { onSelect(cell.date) }
                    )
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(WFColors.text)
            Spacer()
            navButton("chevron.left", "上个月") { changeMonth(-1) }
            navButton("circle", "回到今天") {
                onSelect(calendar.startOfDay(for: today))
            }
            navButton("chevron.right", "下个月") { changeMonth(1) }
        }
    }

    private var weekdayRow: some View {
        LazyVGrid(columns: Self.columns, spacing: 0) {
            ForEach(Array(orderedWeekdayLabels.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(WFColors.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 15)
            }
        }
    }

    private var title: String {
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        return "\(components.year ?? 0)年\(components.month ?? 0)月"
    }

    private var orderedWeekdayLabels: [String] {
        let start = layoutCalendar.firstWeekday - 1
        return Array(Self.weekdayLabels[start...] + Self.weekdayLabels[..<start])
    }

    /// 月历头部的三个导航控件。它们是只有图标的按钮，所以要自己带功能名称——
    /// 原版这三个按钮（`task_schedule_panel.dart:314/321/326`）都带 tooltip。
    private func navButton(_ symbol: String, _ help: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(help)
    }

    private func changeMonth(_ delta: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
    }

    private func isFilled(_ date: Date) -> Bool {
        if let range {
            // Range mode: only the endpoints get the solid disc; the span
            // between is covered by isRangeMiddle.
            return date == range.lowerBound || date == range.upperBound
        }
        return selection.map { calendar.isDate($0, inSameDayAs: date) } ?? false
    }

    private func isRangeMiddle(_ date: Date) -> Bool {
        guard let range, range.lowerBound != range.upperBound else { return false }
        return range.lowerBound < date && date < range.upperBound
    }
}

private struct GridDayCell: View {
    let day: Int
    let inMonth: Bool
    let festival: String?
    let isToday: Bool
    let isSelected: Bool
    let isRangeMiddle: Bool
    let action: () -> Void

    var body: some View {
        ZStack {
            if isSelected {
                Circle().fill(WFColors.accent)
                    .frame(width: 26, height: 26)
            } else if isRangeMiddle {
                RoundedRectangle(cornerRadius: 8).fill(WFColors.selection)
                    .frame(height: 26)
                    .padding(.horizontal, 1)
            } else if isToday {
                Circle().strokeBorder(WFColors.accent.opacity(0.5), lineWidth: 1)
                    .frame(width: 26, height: 26)
            }
            VStack(spacing: 0) {
                Text("\(day)")
                    // 原版日期数字取 `body`（14）regular：今天/选中由上面那个圆圈
                    // 表达，字重不再重复说一遍。
                    .font(WFType.body)
                    .foregroundStyle(numberColor)
                if let festival {
                    Text(festival)
                        // 原版节日小字 `calendarAnnotation` = 6。
                        .font(.system(size: 6))
                        .foregroundStyle(festivalColor)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private var numberColor: Color {
        isSelected ? .white : inMonth ? WFColors.text : WFColors.tertiaryText
    }

    private var festivalColor: Color {
        isSelected ? Color.white.opacity(0.9) : WFColors.secondaryText
    }
}
