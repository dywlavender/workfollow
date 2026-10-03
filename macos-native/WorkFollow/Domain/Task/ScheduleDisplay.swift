import Foundation

/// 日程的**显示投影**：文案只在这里生成，各宿主通过风格参数选择。
///
/// 以前同一件事在不同地方各写一份实现：
/// - 日期：`TaskDateLabel`（列表行）+ `TaskInspectorSchedulePresentation`（编辑栏）
///   + 面板里的 `dayText`，三套 grammar；
/// - 提醒："准时 / 提前N天"（草稿预设）与"当天 / 提前N周"（面板）两套，后者再回落前者；
/// - 重复：`TaskRepeat.title`（菜单、摘要）与面板 `repeatLabel`（带锚定日）两套。
///
/// grammar 各写一份，就只能靠"改一处、记得改另一处"维持一致。这里收成一份：
/// 风格差异一律变成**显式的风格参数**，不再是隐式的实现分歧。
enum ScheduleDisplay {

    // MARK: - 重复

    /// 上下文无关的重复名（菜单、摘要行）。
    static func repeatTitle(_ value: TaskRepeat) -> String {
        switch value {
        case .never: return "不重复"
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .yearly: return "每年"
        case .weekdays: return "每周一至周五"
        case .weekends: return "每周六、周日"
        case .workdays: return "法定工作日"
        case .holidays: return "法定休息日"
        case .lunarYearly: return "农历每年"
        case .lunarMonthly: return "农历每月"
        }
    }

    /// 锚定日上下文：让"每周"这类重复显示成"每周 (周二)"。
    struct RepeatContext: Equatable {
        /// Calendar 口径：1 = 周日 … 7 = 周六。
        var weekday: Int
        var monthDay: Int
        var month: Int
        /// 农历名称（农历重复用），非农历重复可省。
        var lunarName: String?
        var lunarDayText: String?

        init(weekday: Int, monthDay: Int, month: Int,
             lunarName: String? = nil, lunarDayText: String? = nil) {
            self.weekday = weekday
            self.monthDay = monthDay
            self.month = month
            self.lunarName = lunarName
            self.lunarDayText = lunarDayText
        }
    }

    /// 带上锚定日的重复文案（滴答口径）：`每周 (周二)` / `每月 (15日)` / `农历每年 (正月初一)`。
    static func repeatText(_ value: TaskRepeat, context: RepeatContext) -> String {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        let index = max(1, min(7, context.weekday)) - 1
        switch value {
        case .never: return "重复"
        case .daily: return "每天"
        case .weekly: return "每周 (周\(symbols[index]))"
        case .monthly: return "每月 (\(context.monthDay)日)"
        case .yearly: return "每年 (\(context.month)月\(context.monthDay)日)"
        case .weekdays: return "每周一至周五"
        case .weekends: return "每周六、周日"
        case .workdays: return "法定工作日"
        case .holidays: return "法定休息日"
        case .lunarYearly: return "农历每年 (\(context.lunarName ?? ""))"
        case .lunarMonthly: return "农历每月 (\(context.lunarDayText ?? ""))"
        }
    }

    // MARK: - 提醒偏移

    /// 偏移文案的两套**显式**风格（不是两份实现）：
    /// - `.panel`：滴答面板行（`当天`、`提前1周`、`提前1天`，分钟级回落到预设口径）；
    /// - `.preset`：编辑器预设（`准时`、`提前1天`、`提前1小时`、`提前N分钟`）。
    ///
    /// `minutes` 约定：0 = 准时，负数 = 提前。
    enum ReminderStyle { case panel, preset }

    static func reminderOffsetText(minutes: Int, style: ReminderStyle) -> String {
        switch style {
        case .preset:
            return presetOffsetText(minutes)
        case .panel:
            if minutes == 0 { return "当天" }
            if minutes % 10_080 == 0 { return "提前\(-minutes / 10_080)周" }
            if minutes % 1_440 == 0 { return "提前\(-minutes / 1_440)天" }
            return presetOffsetText(minutes)
        }
    }

    private static func presetOffsetText(_ minutes: Int) -> String {
        guard minutes != 0 else { return "准时" }
        let value = abs(minutes)
        if value % 1_440 == 0 { return "提前\(value / 1_440)天" }
        if value % 60 == 0 { return "提前\(value / 60)小时" }
        return "提前\(value)分钟"
    }

    // MARK: - 日期

    /// 日期文案风格：
    /// - `.compact`：列表行 / 子任务行（`今天 20:30`、`9月27日`）；
    /// - `.full`：编辑栏 chip（`上周日, 9月27日, 20:30`）。
    enum DateStyle { case compact, full }

    static func dateText(_ date: Date, hasTime: Bool, now: Date, calendar: Calendar,
                         style: DateStyle) -> String {
        switch style {
        case .compact:
            return compactDateText(date, hasTime: hasTime, now: now, calendar: calendar)
        case .full:
            return fullDateText(date, hasTime: hasTime, now: now, calendar: calendar)
        }
    }

    /// 面板用的短日期：`9月26日`。
    static func dayText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)月\(components.day ?? 0)日"
    }

    private static func compactDateText(_ date: Date, hasTime: Bool, now: Date,
                                        calendar: Calendar) -> String {
        let distance = dayDistance(from: now, to: date, calendar: calendar)
        let day = distance == 0 ? "今天" : distance == 1 ? "明天" : distance == -1 ? "昨天"
            : dateFormatter(calendar: calendar, now: now, date: date).string(from: date)
        guard hasTime else { return day }
        return day + " " + clockFormatter(calendar: calendar).string(from: date)
    }

    private static func fullDateText(_ date: Date, hasTime: Bool, now: Date,
                                     calendar: Calendar) -> String {
        var parts: [String] = []
        let distance = dayDistance(from: now, to: date, calendar: calendar)
        if distance == 0 {
            parts.append("今天")
        } else if distance == 1 {
            parts.append("明天")
        } else if distance == -1 {
            parts.append("昨天")
        } else if let week = calendar.dateInterval(of: .weekOfYear, for: now) {
            // 同一周内不标、相邻周标"上周X / 下周X"，再远直接给月日。
            let relativeWeek = date < week.start ? -1 : date >= week.end ? 1 : 0
            if let adjacent = calendar.date(byAdding: .weekOfYear, value: relativeWeek, to: now),
               let interval = calendar.dateInterval(of: .weekOfYear, for: adjacent),
               interval.contains(date) {
                let prefix = relativeWeek < 0 ? "上" : relativeWeek > 0 ? "下" : ""
                let weekday = ["日", "一", "二", "三", "四", "五", "六"][calendar.component(.weekday, from: date) - 1]
                parts.append("\(prefix)周\(weekday)")
            }
        }
        parts.append(dateFormatter(calendar: calendar, now: now, date: date).string(from: date))
        if hasTime { parts.append(clockFormatter(calendar: calendar).string(from: date)) }
        return parts.joined(separator: ", ")
    }

    private static func dayDistance(from now: Date, to date: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// 同年不带年、跨年带年（`M月d日` / `yyyy年M月d日`）。
    private static func dateFormatter(calendar: Calendar, now: Date, date: Date) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            ? "M月d日" : "yyyy年M月d日"
        return formatter
    }

    private static func clockFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }
}
