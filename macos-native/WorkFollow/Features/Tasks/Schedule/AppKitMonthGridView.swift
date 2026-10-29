import AppKit
import SwiftUI

/// 日期面板月历网格的 AppKit 渲染（滴答日期面板日历区）。
///
/// 自绘标题栏（年月 + 上/下月/回到今天）+ 星期行 + 6×7 日期格：
/// 选中实心圆、今天描边环、区间高亮、节日小字；点击格选日期、点击箭头翻月。
/// 日期面板所有宿主的月历都走这一个实现（原 SwiftUI 版已删除）。
struct AppKitMonthGridView: View {
    let calendar: Calendar
    @Binding var displayedMonth: Date
    let today: Date
    var selection: Date?
    var range: ClosedRange<Date>?
    var minimumDate: Date?
    var showsTodayButton = true
    let onSelect: (Date) -> Void

    static let contentHeight: CGFloat = MonthGridCanvas.preferredHeight

    private var layoutCalendar: Calendar { PlanningProjection.mondayFirstWeek(calendar) }

    private var monthTitle: String {
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        return "\(components.year ?? 0)年\(components.month ?? 0)月"
    }

    var body: some View {
        MonthGridDrawing(calendar: calendar, displayedMonth: displayedMonth, today: today,
                         selection: selection, range: range, minimumDate: minimumDate,
                         showsTodayButton: showsTodayButton)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        navigation("上个月", delta: -1)
                        if showsTodayButton {
                            Button { select(calendar.startOfDay(for: today)) } label: {
                                Color.clear.contentShape(Rectangle())
                            }
                            .frame(width: 18, height: 22)
                            .accessibilityLabel("回到今天")
                            .hoverTip("回到今天")
                            .scheduleRenderAnchor(.option("回到今天"))
                        }
                        navigation("下个月", delta: 1)
                    }
                    .buttonStyle(.plain)
                    .frame(height: 22)
                    Color.clear.frame(height: 23).accessibilityHidden(true)
                    dayButtons
                }
            }
            .frame(height: Self.contentHeight)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(monthTitle)
            .scheduleRenderAnchor(.option("month-title"), label: monthTitle)
    }

    private func navigation(_ title: String, delta: Int) -> some View {
        Button {
            displayedMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
        } label: { Color.clear.contentShape(Rectangle()) }
            .frame(width: 18, height: 22)
            .accessibilityLabel(title)
            .hoverTip(title)
            .scheduleRenderAnchor(.option(title))
    }

    private var dayButtons: some View {
        let cells = MonthGridCalculator.cells(displayedMonth: displayedMonth, calendar: layoutCalendar)
        return VStack(spacing: 0) {
            ForEach(0..<6) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7) { column in
                        let day = cells[row * 7 + column].date
                        let components = calendar.dateComponents([.year, .month, .day], from: day)
                        let label = "\(components.year ?? 0)年\(components.month ?? 0)月\(components.day ?? 0)日"
                        Button { select(day) } label: { Color.clear.contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .disabled(!canSelect(day))
                            .accessibilityLabel(label)
                            .accessibilityValue(isSelected(day) ? "已选择" : "未选择")
                            .scheduleRenderAnchor(.option(label), label: label, active: isSelected(day))
                    }
                }
            }
        }
    }

    private func isSelected(_ day: Date) -> Bool {
        if let range {
            return calendar.isDate(day, inSameDayAs: range.lowerBound)
                || calendar.isDate(day, inSameDayAs: range.upperBound)
        }
        return selection.map { calendar.isDate(day, inSameDayAs: $0) } ?? false
    }

    private func select(_ day: Date) {
        guard canSelect(day) else { return }
        displayedMonth = day
        onSelect(day)
    }

    private func canSelect(_ day: Date) -> Bool {
        minimumDate.map { calendar.startOfDay(for: day) >= calendar.startOfDay(for: $0) } ?? true
    }
}

/// 绘制与命中区域使用相同的固定网格；按钮保留辅助功能、键盘与浮层事件路由。
private struct MonthGridDrawing: NSViewRepresentable {
    let calendar: Calendar
    let displayedMonth: Date
    let today: Date
    let selection: Date?
    let range: ClosedRange<Date>?
    let minimumDate: Date?
    let showsTodayButton: Bool

    func makeNSView(context: Context) -> MonthGridCanvas {
        let view = MonthGridCanvas()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: MonthGridCanvas, context: Context) {
        apply(to: view)
        view.needsDisplay = true
    }

    private func apply(to view: MonthGridCanvas) {
        view.calendar = calendar
        view.displayedMonth = displayedMonth
        view.today = today
        view.selection = selection
        view.range = range
        view.minimumDate = minimumDate
        view.showsTodayButton = showsTodayButton
    }
}

/// 月历画布：顶部原点坐标，固定 6 周高度。
final class MonthGridCanvas: NSView {
    static let preferredHeight: CGFloat = 22 + 4 + 15 + 4 + 6 * 30

    var calendar = Calendar.current
    var displayedMonth = Date()
    var today = Date()
    var selection: Date?
    var range: ClosedRange<Date>?
    var minimumDate: Date?
    var showsTodayButton = true

    private static let weekdayLabels = ["日", "一", "二", "三", "四", "五", "六"]
    private let headerHeight: CGFloat = 22
    private let weekdayHeight: CGFloat = 15
    private let rowHeight: CGFloat = 30
    private let sectionGap: CGFloat = 4
    private let navSize: CGFloat = 18

    override var isFlipped: Bool { true }

    private var layoutCalendar: Calendar { PlanningProjection.mondayFirstWeek(calendar) }

    private var gridTop: CGFloat { headerHeight + sectionGap + weekdayHeight + sectionGap }

    /// 直接构造动态 accent（SwiftUI 动态 Color 转 NSColor 会固定成某个外观值，
    /// 亮色下文字被转成白）；绘制时由 AppKit 按当前外观解析。
    private var accentColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.494, green: 0.533, blue: 1, alpha: 1)
                : NSColor(red: 0.357, green: 0.361, blue: 0.922, alpha: 1)
        }
    }

    private var selectionColor: NSColor { accentColor.withAlphaComponent(0.10) }

    /// 非本月日期：参考滴答的浅灰（≈ #C0C4CB），比 `tertiaryLabelColor` 更浅一档，
    /// 避免上/下月的日期抢走本月的视觉重点。
    private var outOfMonthColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.42, green: 0.44, blue: 0.48, alpha: 1)
                : NSColor(red: 0.753, green: 0.769, blue: 0.796, alpha: 1)
        }
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        let width = bounds.width
        guard width > 0 else { return }

        drawTitle(width: width)
        drawNavButtons(width: width)
        drawWeekdays(width: width)
        drawGrid(width: width)
    }

    private func drawTitle(width: CGFloat) {
        let title = monthTitle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        let rect = NSRect(x: 0, y: (headerHeight - size.height) / 2, width: width - 70, height: size.height)
        (title as NSString).draw(in: rect, withAttributes: attributes)
    }

    /// 导航按钮按「回到今天 / 下月」从右往左排，与 SwiftUI 版的右对齐一致。
    private var navActions: [(rect: NSRect, action: NavAction)] {
        var items: [(NSRect, NavAction)] = []
        var x = bounds.width - navSize
        items.append((NSRect(x: x, y: 0, width: navSize, height: headerHeight), .nextMonth))
        x -= navSize + 8
        if showsTodayButton {
            items.append((NSRect(x: x, y: 0, width: navSize, height: headerHeight), .today))
            x -= navSize + 8
        }
        items.append((NSRect(x: x, y: 0, width: navSize, height: headerHeight), .previousMonth))
        return items
    }

    private func drawNavButtons(width: CGFloat) {
        let color = NSColor.secondaryLabelColor
        for (rect, action) in navActions {
            let symbol: String
            switch action {
            case .previousMonth: symbol = "chevron.left"
            case .today: symbol = "circle"
            case .nextMonth: symbol = "chevron.right"
            }
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                let configured = image.withSymbolConfiguration(config) ?? image
                let tinted = configured.tinted(with: color)
                let size = tinted.size
                let target = NSRect(x: rect.midX - size.width / 2,
                                    y: rect.midY - size.height / 2,
                                    width: size.width, height: size.height)
                tinted.draw(in: target)
            }
        }
    }

    private func drawWeekdays(width: CGFloat) {
        let labels = orderedWeekdayLabels
        let cellWidth = width / 7
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        for (index, symbol) in labels.enumerated() {
            let size = (symbol as NSString).size(withAttributes: attributes)
            let rect = NSRect(x: CGFloat(index) * cellWidth + (cellWidth - size.width) / 2,
                              y: headerHeight + sectionGap + (weekdayHeight - size.height) / 2,
                              width: size.width, height: size.height)
            (symbol as NSString).draw(in: rect, withAttributes: attributes)
        }
    }

    private func drawGrid(width: CGFloat) {
        let cells = MonthGridCalculator.cells(displayedMonth: displayedMonth, calendar: layoutCalendar)
        let cellWidth = width / 7
        for (index, cell) in cells.enumerated() {
            let column = index % 7
            let row = index / 7
            let rect = NSRect(x: CGFloat(column) * cellWidth,
                              y: gridTop + CGFloat(row) * rowHeight,
                              width: cellWidth, height: rowHeight)
            drawDayCell(cell: cell, in: rect)
        }
    }

    private func drawDayCell(cell: MonthGridCalculator.Cell, in rect: NSRect) {
        let disabled = isDisabled(cell.date)
        let filled = isFilled(cell.date)
        let middle = isRangeMiddle(cell.date)
        let isToday = calendar.isDate(cell.date, inSameDayAs: today)

        let disc = NSRect(x: rect.midX - 13, y: rect.midY - 13, width: 26, height: 26)
        if filled {
            accentColor.setFill()
            NSBezierPath(ovalIn: disc).fill()
        } else if middle {
            selectionColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.midY - 13, width: rect.width, height: 26),
                         xRadius: 8, yRadius: 8).fill()
        } else if isToday {
            accentColor.withAlphaComponent(0.5).setStroke()
            let path = NSBezierPath(ovalIn: disc.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
        }

        let day = calendar.component(.day, from: cell.date)
        let numberColor: NSColor
        if filled {
            numberColor = .white
        } else if !cell.inMonth {
            numberColor = outOfMonthColor
        } else {
            numberColor = NSColor.labelColor
        }
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: numberColor.withAlphaComponent(numberColor.alphaComponent * (disabled ? 0.4 : 1)),
        ]
        let number = "\(day)"
        let numberSize = (number as NSString).size(withAttributes: numberAttributes)
        let festival = cell.inMonth
            ? LunarCalendarService.festivalLabel(for: cell.date, calendar: calendar)
            : nil
        var textTop = rect.midY - 14
        if festival == nil {
            textTop = rect.midY - numberSize.height / 2
        }
        (number as NSString).draw(
            in: NSRect(x: rect.midX - numberSize.width / 2, y: textTop,
                       width: numberSize.width, height: numberSize.height),
            withAttributes: numberAttributes)

        if let festival {
            let color = filled ? NSColor.white.withAlphaComponent(0.9) : NSColor.secondaryLabelColor
            let festivalAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 6),
                .foregroundColor: color.withAlphaComponent(color.alphaComponent * (disabled ? 0.4 : 1)),
            ]
            let size = (festival as NSString).size(withAttributes: festivalAttributes)
            (festival as NSString).draw(
                in: NSRect(x: rect.midX - size.width / 2, y: textTop + numberSize.height,
                           width: size.width, height: size.height),
                withAttributes: festivalAttributes)
        }
    }

    // MARK: 状态判定

    private var monthTitle: String {
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        return "\(components.year ?? 0)年\(components.month ?? 0)月"
    }

    private var orderedWeekdayLabels: [String] {
        let start = layoutCalendar.firstWeekday - 1
        return Array(Self.weekdayLabels[start...] + Self.weekdayLabels[..<start])
    }

    private func isFilled(_ date: Date) -> Bool {
        if let range {
            return calendar.isDate(date, inSameDayAs: range.lowerBound)
                || calendar.isDate(date, inSameDayAs: range.upperBound)
        }
        return selection.map { calendar.isDate($0, inSameDayAs: date) } ?? false
    }

    private func isRangeMiddle(_ date: Date) -> Bool {
        guard let range, range.lowerBound != range.upperBound else { return false }
        return range.lowerBound < date && date < range.upperBound
    }

    private func isDisabled(_ date: Date) -> Bool {
        guard let minimumDate else { return false }
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: minimumDate)
    }
}

private enum NavAction {
    case previousMonth, today, nextMonth
}

private extension NSImage {
    /// 用模板渲染把 SF Symbol 染成指定颜色。
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as? NSImage ?? self
        image.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: image.size)
        rect.fill(using: .sourceIn)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
