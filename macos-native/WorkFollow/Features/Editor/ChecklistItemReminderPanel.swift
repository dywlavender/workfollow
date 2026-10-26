import AppKit
import SwiftUI

/// 检查项的项级提醒面板。行尾铃铛点开，选项行/确认按钮沿用右键日期面板的
/// 提醒子卡片样式；草稿确认后才写入块元数据。
@MainActor
final class ChecklistItemReminderPanel: NSPanel {
    private let onSelect: (Date?) -> Void
    private let onDismiss: () -> Void
    private let now: Date
    private let anchorRect: NSRect
    private let screenBounds: NSRect
    private var hostView: NSView?
    private var interactionRegistration: UUID?
    private var isDismissing = false

    override var canBecomeKey: Bool { true }

    init(anchor: NSRect, owner: NSWindow, now: Date, calendar: Calendar,
         current: Date?, notice: String? = nil,
         onSelect: @escaping (Date?) -> Void,
         onDismiss: @escaping () -> Void = {}) {
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        self.now = now
        anchorRect = anchor
        screenBounds = owner.screen?.visibleFrame ?? EditorPopupGeometry.bounds(in: owner)
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        becomesKeyOnlyIfNeeded = true
        appearance = owner.effectiveAppearance
        title = "检查事项提醒"

        let card = ChecklistItemReminderCard(now: now, calendar: calendar, current: current,
            notice: notice,
            onResize: { [weak self] in self?.resizeToFit() },
            onSelect: { [weak self] date in self?.finish(date) },
            onClose: { [weak self] in self?.dismiss() })
        let host = NSHostingView(rootView: card)
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host
        hostView = host
        resizeToFit(animated: false)
        EditorPopupWindowLevel.apply(to: self, owner: owner)
        owner.addChildWindow(self, ordered: .above)
        orderFront(nil)
        makeKey()
        interactionRegistration = PopupInteractionRegistry.shared.register(window: self, contains: { [weak self] event in
            guard let self else { return false }
            var target = event.window
            while let window = target {
                if window === self { return true }
                target = window.parent
            }
            return false
        }, dismiss: { [weak self] in self?.dismiss() })
    }

    /// 预设页与日历页高度不同：切换后按新内容高度重新贴回铃铛上方。
    func resizeToFit(animated: Bool = true) {
        guard let host = hostView else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        let frame = EditorPopupGeometry.frame(anchor: anchorRect, size: size, bounds: screenBounds,
                                              preferredSide: .above, alignment: .trailing,
                                              gap: PopupMetrics.controlGap)
        setFrame(frame, display: true, animate: animated)
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    /// 面板里的固定时间点（测试与 UI 共用同一口径）。
    struct Preset: Hashable {
        let title: String
        let date: Date
    }

    static func presets(now: Date, calendar: Calendar) -> [Preset] {
        let start = calendar.startOfDay(for: now)
        var result: [Preset] = []
        for dayOffset in 0...3 {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: start) ?? start
            for hour in [9, 18] {
                guard let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                      date > now else { continue }
                result.append(Preset(
                    title: dayText(date, now: now, calendar: calendar) + " " + clockText(date, calendar: calendar),
                    date: date))
                if result.count == 3 { return result }
            }
        }
        return result
    }

    static func defaultCustomDate(now: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    /// 日期面板时间行的半小时候选（与日期面板同口径：0:00–23:30）。
    static func halfHourOptions(day: Date, calendar: Calendar) -> [Date] {
        let start = calendar.startOfDay(for: day)
        return (0..<48).compactMap { calendar.date(byAdding: .minute, value: $0 * 30, to: start) }
    }

    /// 只保留仍在未来的时段；非当天的所有时段都可用。
    static func availableHalfHourOptions(day: Date, now: Date, calendar: Calendar) -> [Date] {
        let options = halfHourOptions(day: day, calendar: calendar)
        guard calendar.isDate(day, inSameDayAs: now) else { return options }
        return options.filter { $0 > now }
    }

    static func clockText(_ date: Date, calendar: Calendar) -> String {
        String(format: "%02d:%02d", calendar.component(.hour, from: date),
               calendar.component(.minute, from: date))
    }

    /// 日历选的日 + 时间行选的时刻，合成一个提醒时间。
    static func combined(day: Date, time: Date, calendar: Calendar) -> Date? {
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = clock.hour
        components.minute = clock.minute
        components.second = 0
        return calendar.date(from: components)
    }

    static func dayText(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "今天" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "明天" }
        if let afterTomorrow = calendar.date(byAdding: .day, value: 2, to: now),
           calendar.isDate(date, inSameDayAs: afterTomorrow) { return "后天" }
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)月\(components.day ?? 0)日"
    }

    private func finish(_ date: Date?) {
        guard !isDismissing else { return }
        if let date, date <= now { return }
        onSelect(date)
        dismiss()
    }

    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        if let interactionRegistration {
            PopupInteractionRegistry.shared.unregister(interactionRegistration)
            self.interactionRegistration = nil
        }
        let owner = parent
        if isKeyWindow, let owner, owner.isVisible { owner.makeKey() }
        owner?.removeChildWindow(self)
        orderOut(nil)
        onDismiss()
    }
}

private struct ChecklistItemReminderCard: View {
    private enum Page: Equatable { case presets, calendar }

    let now: Date
    let calendar: Calendar
    let current: Date?
    let notice: String?
    let onResize: () -> Void
    let onSelect: (Date?) -> Void
    let onClose: () -> Void
    @State private var selected: Date?
    @State private var page: Page = .presets
    @State private var calendarDay: Date
    @State private var displayedMonth: Date
    @State private var customTime: Date

    init(now: Date, calendar: Calendar, current: Date?, notice: String?,
         onResize: @escaping () -> Void,
         onSelect: @escaping (Date?) -> Void, onClose: @escaping () -> Void) {
        self.now = now
        self.calendar = calendar
        self.current = current
        self.notice = notice
        self.onResize = onResize
        self.onSelect = onSelect
        self.onClose = onClose
        _selected = State(initialValue: current.flatMap { $0 > now ? $0 : nil })
        let seed = current ?? ChecklistItemReminderPanel.defaultCustomDate(now: now, calendar: calendar)
        _calendarDay = State(initialValue: seed)
        _displayedMonth = State(initialValue: seed)
        _customTime = State(initialValue: seed)
    }

    var body: some View {
        Group {
            switch page {
            case .presets: presetsPage
            case .calendar: calendarPage
            }
        }
        .padding(.vertical, 4)
        .frame(width: 252)
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
        .background(PopupEscapeRouter(depth: 2, onEscape: onClose))
        .onChange(of: page) { _, _ in
            // SwiftUI 布局要等这一拍结束才更新；下一拍再让宿主按新高度贴回铃铛上方。
            DispatchQueue.main.async { onResize() }
        }
        .onExitCommand(perform: onClose)
    }

    // MARK: 预设页

    private var presetsPage: some View {
        VStack(spacing: 0) {
            ForEach(ChecklistItemReminderPanel.presets(now: now, calendar: calendar), id: \.date) { preset in
                optionRow(preset.title, checked: isSelected(preset.date)) {
                    selected = preset.date
                }
            }
            Divider().padding(.vertical, 4)
            customRow
            if current != nil {
                Divider().padding(.vertical, 4)
                optionRow("清除提醒", checked: selected == nil, destructive: true) {
                    selected = nil
                }
            }
            if let notice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(WFColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            Divider()
                .padding(.top, 4)
            HStack(spacing: 8) {
                footerButton("取消", filled: false, action: onClose)
                    .keyboardShortcut(.cancelAction)
                footerButton("确定", filled: true) { onSelect(selected) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.map { $0 <= now } ?? false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var customRow: some View {
        Button(action: openCalendar) {
            HStack(spacing: 6) {
                Text("自定义")
                    .font(.system(size: 13))
                    .foregroundStyle(isCustomSelected ? WFColors.accent : WFColors.text)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(customDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(WFColors.secondaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WFColors.secondaryText)
            }
            .padding(.horizontal, 12)
            .frame(height: ScheduleMetrics.optionRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private var customDetail: String {
        guard let selected, !matchesPreset(selected) else { return "选择日期时间" }
        return ChecklistItemReminderPanel.dayText(selected, now: now, calendar: calendar)
            + " " + ChecklistItemReminderPanel.clockText(selected, calendar: calendar)
    }

    private func openCalendar() {
        let seed = (selected.flatMap { $0 > now ? $0 : nil })
            ?? ChecklistItemReminderPanel.defaultCustomDate(now: now, calendar: calendar)
        calendarDay = seed
        customTime = seed
        displayedMonth = seed
        page = .calendar
    }

    // MARK: 日历页

    private var calendarPage: some View {
        VStack(spacing: 0) {
            AppKitMonthGridView(calendar: calendar, displayedMonth: $displayedMonth,
                                today: now, selection: calendarDay,
                                minimumDate: calendar.startOfDay(for: now),
                                onSelect: selectCalendarDay)
                .frame(width: 228, height: AppKitMonthGridView.contentHeight)
                .overlay(alignment: .top) {
                    CalendarAnnotationOverlay(calendar: calendar,
                        displayedMonth: displayedMonth,
                        occurrenceDays: Set<Date>(), showBadges: true)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            Divider().padding(.top, 4)
            timeRow
            Divider().padding(.top, 4)
            HStack(spacing: 8) {
                footerButton("返回", filled: false) { page = .presets }
                footerButton("完成", filled: true) { applyCalendarSelection() }
                    .disabled(combinedSelection.map { $0 > now } != true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var combinedSelection: Date? {
        ChecklistItemReminderPanel.combined(day: calendarDay, time: customTime, calendar: calendar)
    }

    /// 选到今天时自动跳过已过去的时段；今天已没有更晚时段则顺延到明天 09:00。
    private func selectCalendarDay(_ day: Date) {
        calendarDay = day
        guard calendar.isDate(day, inSameDayAs: now) else { return }
        if let combined = ChecklistItemReminderPanel.combined(
            day: day, time: customTime, calendar: calendar), combined > now { return }
        let available = ChecklistItemReminderPanel.availableHalfHourOptions(
            day: day, now: now, calendar: calendar)
        if let first = available.first {
            customTime = first
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1,
                                               to: calendar.startOfDay(for: now)),
                  let tomorrowMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) {
            calendarDay = tomorrow
            customTime = tomorrowMorning
            displayedMonth = tomorrow
        }
    }

    /// 与日期面板同口径：时钟图标 + 「时间」+ 当前时刻 + 半小时候选。
    private var timeRow: some View {
        let options = ChecklistItemReminderPanel.availableHalfHourOptions(
            day: calendarDay, now: now, calendar: calendar)
        return BusinessMenu(width: 160, title: "提醒时间") {
            ForEach(options, id: \.self) { option in
                Button {
                    customTime = option
                } label: {
                    HStack(spacing: 8) {
                        Text(ChecklistItemReminderPanel.clockText(option, calendar: calendar))
                        Spacer(minLength: 8)
                        if isSameClock(option, customTime) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(WFColors.accent)
                        }
                    }
                }
            }
            if options.isEmpty {
                Text("今天没有更晚的时间").font(.system(size: 12))
                    .foregroundStyle(WFColors.secondaryText).padding(10)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 13))
                    .foregroundStyle(WFColors.secondaryText)
                Text("时间")
                    .font(.system(size: 13))
                    .foregroundStyle(WFColors.text)
                Spacer(minLength: 6)
                Text(ChecklistItemReminderPanel.clockText(customTime, calendar: calendar))
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(WFColors.text)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WFColors.secondaryText)
            }
            .padding(.horizontal, 12)
            .frame(height: ScheduleMetrics.optionRowHeight)
            .contentShape(Rectangle())
        }
    }

    private func isSameClock(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.component(.hour, from: lhs) == calendar.component(.hour, from: rhs)
            && calendar.component(.minute, from: lhs) == calendar.component(.minute, from: rhs)
    }

    private func applyCalendarSelection() {
        guard let value = combinedSelection, value > now else { return }
        selected = value
        page = .presets
    }

    private var isCustomSelected: Bool {
        guard let selected else { return false }
        return !matchesPreset(selected)
    }

    private func matchesPreset(_ date: Date) -> Bool {
        ChecklistItemReminderPanel.presets(now: now, calendar: calendar)
            .contains { abs($0.date.timeIntervalSince(date)) < 30 }
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let selected else { return false }
        return abs(selected.timeIntervalSince(date)) < 30
    }

    private func optionRow(_ title: String, checked: Bool, destructive: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(destructive ? WFColors.danger
                        : checked ? WFColors.accent : WFColors.text)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(destructive ? WFColors.danger : WFColors.accent)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: ScheduleMetrics.optionRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private func footerButton(_ title: String, filled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: filled ? .semibold : .medium))
                .foregroundStyle(filled ? Color.white : WFColors.text)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(filled ? WFColors.accent : WFColors.content,
                            in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(filled ? Color.clear : WFColors.border))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
