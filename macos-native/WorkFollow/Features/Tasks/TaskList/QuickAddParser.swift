import Foundation

struct QuickAddToken: Identifiable, Equatable {
    enum Kind: String {
        case date, time, recurrence, reminder, tag, list, priority

        /// 这一项是否由日程面板托管：能点开面板对应页去改值。
        /// 标签/清单/优先级走属性面板，不在这里。
        var isEditableScheduleToken: Bool {
            switch self {
            case .date, .time, .reminder, .recurrence: true
            case .tag, .list, .priority: false
            }
        }
    }
    let kind: Kind
    let label: String
    let range: NSRange
    let raw: String
    /// Unknown `@list` markers still render as removable chips but remain part
    /// of the title, matching Flutter's list-marker projection.
    let retainsInTitle: Bool
    var id: String { "\(kind.rawValue):\(range.location):\(range.length):\(raw)" }
}

struct QuickAddParseResult {
    let title: String
    let listName: String?
    let dueAt: Date?
    /// 时间段（「9点至11点」）的结束时刻；只有识别到区间时才有值。
    let dueEndAt: Date?
    let hasTime: Bool
    let reminderAt: Date?
    /// 多级提醒（分钟，0 = 准时，负数 = 提前）。空数组 = 未识别到多级提醒，
    /// 此时沿用单值 `reminderAt`。只有「提前 N 分钟/小时/天/周」这类写法会产出
    /// 组合（0 + (-N)），对齐滴答「准时 + 提前 N」的双提醒语义。
    let reminderOffsets: [Int]
    let recurrence: TaskRepeat
    let recurrenceRule: RecurrenceRule?
    let tags: [String]
    let priority: TaskPriority
    let tokens: [QuickAddToken]
    /// 原始输入文本：token 的 range 以它为基准，供 chip 删除等文本投影使用。
    let sourceText: String

    var summary: String { tokens.map(\.label).joined(separator: " · ") }

    /// 删除某个识别 chip 后的等价文本：该片段退出结构化识别、退化为普通标题
    /// 文字而非消失（对齐 Flutter 掩码重解析的最终效果），其余识别片段仍被剥离。
    /// 属性的重解析仍走 `QuickAddParser.parse(dismissedTokenIDs:)`。
    func text(removing token: QuickAddToken) -> String {
        QuickAddParser.title(sourceText, removing: tokens.filter { $0.id != token.id })
    }
}

/// A focused native port of the Flutter smart-capture vocabulary. Parsing is
/// pure and injects both `now` and `calendar`, making relative dates testable.
enum QuickAddParser {
    private struct Candidate {
        let token: QuickAddToken
        var dueAt: Date?
        var dueEndAt: Date?
        var hasTime = false
        var recurrence: TaskRepeat?
        var recurrenceRule: RecurrenceRule?
        var tag: String?
        var list: String?
        var priority: TaskPriority?
        /// 「提前 N 分钟/小时/天/周」或「提前提醒我」：产出 0 + (-N) 组合提醒。
        var reminderOffsets: [Int]?
    }

    static func hasDismissedScheduleToken(in input: String, now: Date, calendar: Calendar,
                                          knownLists: Set<String>, dismissedTokenIDs: Set<String>) -> Bool {
        guard !dismissedTokenIDs.isEmpty else { return false }
        let allTokens = parse(input, now: now, calendar: calendar, knownLists: knownLists).tokens
        return allTokens.contains { token in
            dismissedTokenIDs.contains(token.id)
                && (token.kind == .date || token.kind == .time || token.kind == .reminder)
        }
    }

    /// Transitional overload for existing views that still own list names as an array.
    /// New call sites should pass `knownLists` as a set.
    static func hasDismissedScheduleToken(in input: String, now: Date, calendar: Calendar,
                                          availableLists: [String], dismissedTokenIDs: Set<String>) -> Bool {
        hasDismissedScheduleToken(in: input, now: now, calendar: calendar,
                                  knownLists: Set(availableLists), dismissedTokenIDs: dismissedTokenIDs)
    }

    /// 识别摘要行："→ 9月27日 09:00 · 每天 · #工作 · @个人 · 高优先级"式。
    /// 各成分依次为 日期(含时间) · 提醒 · 重复 · 标签 · 清单 · 优先级，
    /// 缺省成分直接省略；没有任何识别项时返回空串。
    /// @ 清单只在命中已知清单时进入摘要（未知 @ 名仍留在标题里）。
    static func summaryLine(for text: String, knownLists: Set<String>,
                            dismissedTokenIDs: Set<String> = [],
                            now: Date = Date(), calendar: Calendar = .current) -> String {
        let result = parse(text, now: now, calendar: calendar, knownLists: knownLists,
                           dismissedTokenIDs: dismissedTokenIDs)
        var parts: [String] = []
        if let due = result.dueAt {
            parts.append(dateLabel(due, hasTime: result.hasTime, calendar: calendar))
        }
        if let reminder = result.reminderAt, reminder != result.dueAt {
            parts.append("提醒")
        }
        if !result.reminderOffsets.isEmpty {
            parts.append(Self.reminderOffsetsLabel(result.reminderOffsets))
        }
        if result.recurrence != .never { parts.append(result.recurrence.title) }
        if !result.tags.isEmpty {
            parts.append(result.tags.map { "#\($0)" }.joined(separator: " "))
        }
        if let list = result.listName { parts.append("@\(list)") }
        switch result.priority {
        case .high: parts.append("高优先级")
        case .medium: parts.append("中优先级")
        case .low: parts.append("低优先级")
        case .none: break
        }
        guard !parts.isEmpty else { return "" }
        return "→ " + parts.joined(separator: " · ")
    }

    /// Flutter `titleFromSpans` 的移植：把给定 token 的源文本区间替换为空格，
    /// 再折叠空白、去除首尾标点，得到干净标题。删除 chip 时被删片段不参与
    /// 替换，因此保留为普通标题文字。
    static func title(_ input: String, removing tokens: [QuickAddToken]) -> String {
        let mutable = NSMutableString(string: input)
        for token in tokens.filter({ !$0.retainsInTitle })
            .sorted(by: { $0.range.location > $1.range.location }) {
            guard token.range.location >= 0, NSMaxRange(token.range) <= mutable.length else { continue }
            mutable.replaceCharacters(in: token.range, with: " ")
        }
        return (mutable as String)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "，,、。;；-— "))
    }

    private static func dateLabel(_ date: Date, hasTime: Bool, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        let label = "\(parts.month ?? 1)月\(parts.day ?? 1)日"
        guard hasTime else { return label }
        return label + String(format: " %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 多级提醒的摘要文案：「准时 + 提前5分钟」。
    static func reminderOffsetsLabel(_ offsets: [Int]) -> String {
        let parts = offsets.sorted().map { minutes -> String in
            if minutes == 0 { return "准时" }
            let value = abs(minutes)
            if value % (60 * 24 * 7) == 0 { return "提前\(value / (60 * 24 * 7))周" }
            if value % (60 * 24) == 0 { return "提前\(value / (60 * 24))天" }
            if value % 60 == 0 { return "提前\(value / 60)小时" }
            return "提前\(value)分钟"
        }
        return parts.joined(separator: " + ")
    }

    /// - Parameters:
    ///   - knownLists: 已存在的清单名。@ 片段只有命中其中之一才识别为清单
    ///     token，未知名保持原样留在标题里。
    static func parse(_ input: String, now: Date, calendar: Calendar,
                      knownLists: Set<String>, dismissedTokenIDs: Set<String> = []) -> QuickAddParseResult {
        let source = input as NSString
        let today = calendar.startOfDay(for: now)
        var candidates: [Candidate] = []

        func append(_ pattern: String, _ build: (NSTextCheckingResult) -> Candidate?) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for match in regex.matches(in: input, range: NSRange(location: 0, length: source.length)) {
                if let candidate = build(match) { candidates.append(candidate) }
            }
        }
        func capture(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            guard index < match.numberOfRanges else { return nil }
            let range = match.range(at: index)
            guard range.location != NSNotFound else { return nil }
            return source.substring(with: range)
        }
        func token(_ match: NSTextCheckingResult, kind: QuickAddToken.Kind,
                   label: String, range: NSRange? = nil,
                   retainsInTitle: Bool = false) -> QuickAddToken {
            let tokenRange = range ?? match.range
            return QuickAddToken(kind: kind, label: label, range: tokenRange,
                                 raw: source.substring(with: tokenRange),
                                 retainsInTitle: retainsInTitle)
        }
        func makeDate(_ day: Date, hour: Int? = nil, minute: Int = 0) -> Date {
            var parts = calendar.dateComponents([.year, .month, .day], from: day)
            parts.hour = hour ?? 0
            parts.minute = minute
            return calendar.date(from: parts) ?? day
        }
        func dateForWord(_ raw: String) -> Date? {
            let offset: Int
            switch raw {
            case "今天", "今日", "今晚", "今早": offset = 0
            case "明天", "明日", "明早", "明晨", "明晚": offset = 1
            case "后天": offset = 2
            case "大后天": offset = 3
            default: return nil
            }
            return calendar.date(byAdding: .day, value: offset, to: today)
        }
        /// 阿拉伯数字与中文小写数字统一取值（支持「十」「十一」「二十三」「三十一」）。
        func integer(_ raw: String?) -> Int? {
            guard let raw, !raw.isEmpty else { return nil }
            if let value = Int(raw) { return value }
            let digits: [Character: Int] = ["零": 0, "一": 1, "两": 2, "二": 2,
                                             "三": 3, "四": 4, "五": 5, "六": 6,
                                             "七": 7, "八": 8, "九": 9]
            // 逐字扫描：「X十Y」按 10 进制进位，裸「十」按 10。
            var total = 0
            var pending = 0
            var sawTen = false
            for char in raw {
                if char == "十" {
                    total += (pending == 0 ? 1 : pending) * 10
                    pending = 0
                    sawTen = true
                } else if let digit = digits[char] {
                    pending = digit
                } else {
                    return nil
                }
            }
            guard sawTen || pending > 0 else { return nil }
            return total + pending
        }
        /// 时段词单独出现时的**默认钟点**（对齐滴答「智能识别」表：
        /// 早上 7 点、上午 9 点、中午 12 点、下午 1 点、傍晚 5 点、晚上 8 点）。
        /// 带数字时钟时（`下午3点`）由 `clockValue` 负责，不走这里。
        func periodDefaultHour(_ raw: String) -> Int? {
            switch raw {
            case "凌晨", "清晨": return 5
            case "早上", "早晨": return 7
            case "上午": return 9
            case "中午": return 12
            case "下午": return 13
            case "傍晚": return 17
            case "晚上", "夜里": return 20
            default: return nil
            }
        }
        func clockValue(_ hourText: String?, _ period: String?, _ minuteText: String?) -> (Int, Int)? {
            guard var hour = integer(hourText), hour <= 23 else { return nil }
            var minute = 0
            if minuteText == "半" { minute = 30 }
            else if let minuteText {
                let digits = minuteText.replacingOccurrences(of: "分", with: "").trimmingCharacters(in: .whitespaces)
                if !digits.isEmpty { guard let value = Int(digits), value <= 59 else { return nil }; minute = value }
            }
            // 下午/傍晚/晚上（含「今」「明」「后」组合）都把 12 小时制推到 24 小时制。
            let isAfternoonish: Set<String> = ["下午", "傍晚", "晚上", "夜里",
                                               "明晚", "今晚", "明夜"]
            if let period, isAfternoonish.contains(period), hour < 12 { hour += 12 }
            if period == "中午" && hour < 11 { hour += 12 }
            return (hour, minute)
        }
        func nextClock(_ hour: Int, _ minute: Int) -> Date {
            let candidate = makeDate(today, hour: hour, minute: minute)
            return candidate > now ? candidate : (calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate)
        }
        func formatted(_ date: Date, time: Bool) -> String {
            dateLabel(date, hasTime: time, calendar: calendar)
        }

        // 时间段：「9点至11点」「09:00至10:30」「下午2点到4点」。必须整段优先于
        // 单点时钟，否则会被拆成两个独立时间点、只保留开始。
        // 结束早于开始时按跨天处理（「23点至1点」= 次日 01:00）。
        append("(\\d{1,2}|[零一两二三四五六七八九十]{1,4})\\s*(点|时|[:：])\\s*(半|[0-5]?\\d\\s*分?)?\\s*[-–—~～至到]+\\s*(\\d{1,2}|[零一两二三四五六七八九十]{1,4})\\s*(点|时|[:：])\\s*(半|[0-5]?\\d\\s*分?)?") { match in
            guard let start = clockValue(capture(match, 1), nil, capture(match, 3)),
                  let finish = clockValue(capture(match, 4), nil, capture(match, 6)) else { return nil }
            var begin = nextClock(start.0, start.1)
            var end = makeDate(calendar.startOfDay(for: begin), hour: finish.0, minute: finish.1)
            if end <= begin { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
            if end <= begin { return nil }
            return Candidate(token: token(match, kind: .time,
                                          label: formatted(begin, time: true) + "–" + formatted(end, time: true)),
                             dueAt: begin, dueEndAt: end, hasTime: true)
        }

        // Combined forms such as “明早9点” and “明天 下午3点” take precedence
        // over their overlapping date-only and clock-only matches.
        append("(今天|今日|明天|明日|后天|大后天|今晚|今早|明早|明晨|明晚)?\\s*(凌晨|清晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里)?\\s*(\\d{1,2}|[零一两二三四五六七八九十]{1,4})\\s*(点|时|[:：])\\s*(半|[0-5]?\\d\\s*分?)?") { match in
            guard let clock = clockValue(capture(match, 3), capture(match, 2) ?? capture(match, 1), capture(match, 5)) else { return nil }
            let dayWord = capture(match, 1)
            let explicitDay = dayWord.flatMap(dateForWord)
            var due = explicitDay.map { makeDate($0, hour: clock.0, minute: clock.1) } ?? nextClock(clock.0, clock.1)
            if let explicitDay, calendar.isDate(explicitDay, inSameDayAs: today), due <= now {
                due = calendar.date(byAdding: .day, value: 1, to: due) ?? due
            }
            // A period such as 上午 is a clock qualifier, not a separate day.
            let isDateTime = explicitDay != nil
            return Candidate(token: token(match, kind: isDateTime ? .date : .time,
                                           label: formatted(due, time: true)),
                             dueAt: due, hasTime: true)
        }

        // 组合时长：「1小时30分钟后」。必须排在单单位规则之前，否则会被
        // 「1小时」抢先匹配、把「30分钟后」留在标题里（实测过的错误结果）。
        append("(半|\\d+|\\d+小时半?)?\\s*(?:个)?小时\\s*(半|\\d+)\\s*(?:分钟|分)\\s*(?:之|以)?后") { match in
            guard let hourText = capture(match, 1), let minuteText = capture(match, 2) else { return nil }
            let hours: Double = hourText == "半" ? 0.5
                : hourText.hasSuffix("半") ? Double(Int(hourText.dropLast()) ?? 0) + 0.5
                : Double(Int(hourText) ?? 0)
            let minutes: Double = minuteText == "半" ? 30 : Double(Int(minuteText) ?? 0)
            let seconds = hours * 3600 + minutes * 60
            // 整分钟才算「有时刻」，否则会显示成 ??:00 的假钟点。
            let exact = seconds.truncatingRemainder(dividingBy: 60) < 0.5
            let due = now.addingTimeInterval(seconds)
            return Candidate(token: token(match, kind: exact ? .time : .date,
                                           label: formatted(due, time: exact)),
                             dueAt: due, hasTime: exact)
        }

        // Relative intervals support the same common capture forms as Flutter.
        append("(半|\\d+)\\s*(?:个)?(小时|分钟|天|周|星期|礼拜|个月|月|年|钟头)(?:之|以)?后") { match in
            guard let amountText = capture(match, 1), let unit = capture(match, 2) else { return nil }
            func amount(_ text: String) -> Int? { text == "半" ? nil : Int(text) }
            let due: Date
            let exact: Bool
            switch unit {
            case "周", "星期", "礼拜":
                guard let value = amount(amountText) else { return nil }
                due = calendar.date(byAdding: .day, value: value * 7, to: today) ?? today
                exact = false
            case "个月", "月":
                guard let value = amount(amountText) else { return nil }
                due = calendar.date(byAdding: .month, value: value, to: today) ?? today
                exact = false
            case "年":
                guard let value = amount(amountText) else { return nil }
                due = calendar.date(byAdding: .year, value: value, to: today) ?? today
                exact = false
            case "天":
                guard let value = amount(amountText) else { return nil }
                due = calendar.date(byAdding: .day, value: value, to: today) ?? today
                exact = false
            default:
                let value = amountText == "半" ? 0 : (Int(amountText) ?? 0)
                let seconds = amountText == "半" ? 30 * 60
                    : unit == "小时" || unit == "钟头" ? value * 3600 : value * 60
                due = now.addingTimeInterval(TimeInterval(seconds))
                exact = true
            }
            return Candidate(token: token(match, kind: exact ? .time : .date,
                                           label: formatted(due, time: exact)),
                             dueAt: due, hasTime: exact)
        }

        // 时段词单独出现（不带数字）：按滴答表格的默认钟点落到最近的有效时刻。
        // 必须在「日期词」之前追加，避免「明晚」这类词被拆开误判。
        //
        // 边界很重要：这些词也可能只是普通名词的一部分（「下午茶」「早上好」
        // 「晚上市」）。因此要求**后面不是文字**，或紧跟常见动词/助词收尾，
        // 避免把「下午茶时间」吃掉「下午」。
        append("(凌晨|清晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里)(?=$|[\\s，,。、；;！!]|开会|提交|见|出发|回来|提醒|吃饭|办理|处理|开始|结束|[点 　])") { match in
            guard let raw = capture(match, 1), let hour = periodDefaultHour(raw) else { return nil }
            let due = nextClock(hour, 0)
            return Candidate(token: token(match, kind: .time, label: formatted(due, time: true)),
                             dueAt: due, hasTime: true)
        }

        append("(今天|今日|明天|明日|后天|大后天|今晚|今早|明早|明晨|明晚)") { match in
            guard let raw = capture(match, 1), let date = dateForWord(raw) else { return nil }
            return Candidate(token: token(match, kind: .date, label: formatted(date, time: false)), dueAt: date)
        }

        append("(下下?|本)?(周|星期|礼拜)([一二三四五六日天])") { match in
            guard let char = capture(match, 3) else { return nil }
            let normalized = char == "天" ? "日" : char
            guard let index = ["一", "二", "三", "四", "五", "六", "日"].firstIndex(of: normalized) else { return nil }
            let calendarWeekday = (index + 1) % 7 + 1 // Swift: Sunday=1, Monday=2.
            let todayWeekday = calendar.component(.weekday, from: today)
            var delta = (calendarWeekday - todayWeekday + 7) % 7
            let prefix = capture(match, 1)
            // 下周 is the following natural Monday–Sunday week, not another
            // seven days added to the next matching weekday.
            let elapsedSinceMonday = (todayWeekday + 5) % 7
            if prefix == "下" { delta = 7 - elapsedSinceMonday + index }
            if prefix == "下下" { delta = 14 - elapsedSinceMonday + index }
            if prefix == "本" { delta = index - elapsedSinceMonday }
            let date = calendar.date(byAdding: .day, value: delta, to: today) ?? today
            return Candidate(token: token(match, kind: .date, label: formatted(date, time: false)), dueAt: date)
        }

        // 带年份的绝对日期：「2026年9月15日」。日程面板回写文字时用完整年月日
        // （重新生成时不知道用户的「今天」，绝对日期在任何时刻解析都稳定），
        // 所以这条规则是回写能成立的**前提**，不只是便利。
        append("(\\d{4})\\s*年\\s*(\\d{1,2})\\s*月\\s*(\\d{1,2})\\s*[日号]") { match in
            guard let year = Int(capture(match, 1) ?? ""),
                  let month = Int(capture(match, 2) ?? ""), (1...12).contains(month),
                  let day = Int(capture(match, 3) ?? ""), (1...31).contains(day) else { return nil }
            let parts = DateComponents(year: year, month: month, day: day)
            guard let date = calendar.date(from: parts),
                  calendar.component(.day, from: date) == day else { return nil }
            return Candidate(token: token(match, kind: .date, label: formatted(date, time: false)),
                             dueAt: date)
        }
        append("(\\d{1,2})\\s*月\\s*(\\d{1,2})\\s*[日号]") { match in
            guard let month = Int(capture(match, 1) ?? ""), let day = Int(capture(match, 2) ?? ""),
                  (1...12).contains(month), (1...31).contains(day) else { return nil }
            let year = calendar.component(.year, from: today)
            var parts = DateComponents(year: year, month: month, day: day)
            guard var date = calendar.date(from: parts), calendar.component(.day, from: date) == day else { return nil }
            if date < today { parts.year = year + 1; date = calendar.date(from: parts) ?? date }
            return Candidate(token: token(match, kind: .date, label: formatted(date, time: false)), dueAt: date)
        }
        append("(\\d{1,2})/(\\d{1,2})") { match in
            guard let month = Int(capture(match, 1) ?? ""), let day = Int(capture(match, 2) ?? ""),
                  (1...12).contains(month), (1...31).contains(day) else { return nil }
            let year = calendar.component(.year, from: today)
            var parts = DateComponents(year: year, month: month, day: day)
            guard var date = calendar.date(from: parts), calendar.component(.day, from: date) == day else { return nil }
            if date < today { parts.year = year + 1; date = calendar.date(from: parts) ?? date }
            return Candidate(token: token(match, kind: .date, label: formatted(date, time: false)), dueAt: date)
        }

        // 重复词表。顺序即优先级：更具体的写法（工作日/周末/最后一天/每年X月）
        // 必须排在泛化写法（每周/每月）之前，否则会被抢先匹配成错误语义。
        // 1) 每周一至周五 / 每个工作日 / 法定工作日
        append("每(?:个)?(?:法定)?工作日|每(?:周|星期|礼拜)一?至(?:周|星期|礼拜)?五") { match in
            let label = "每周一至周五"
            return Candidate(token: token(match, kind: .recurrence, label: label), recurrence: .workdays)
        }
        // 2) 每周末 / 每周六日
        append("每(?:个)?(?:周|星期|礼拜)末|每(?:周|星期|礼拜)([六日天]{2})") { match in
            let label = "每周六、周日"
            return Candidate(token: token(match, kind: .recurrence, label: label),
                             recurrence: .weekends,
                             recurrenceRule: RecurrenceRule(weekday: 7, weekdays: [7, 1]))
        }
        // 3) 每月最后一天 / 每月第1天 / 每月1日 / 每月15号
        append("每(?:个)?月\\s*(最后|末|第)?\\s*(\\d{1,2}|[一二三四五六七八九十]{1,3})?\\s*[天日号]") { match in
            let marker = capture(match, 1)
            if marker == "最后" || marker == "末" {
                // 「每月最后一天」：面板回写用这个写法，必须能读回来。
                return Candidate(token: token(match, kind: .recurrence, label: "每月最后一天"),
                                 recurrence: .monthly,
                                 recurrenceRule: RecurrenceRule(monthlyOrdinal: -1))
            }
            guard let dayText = capture(match, 2), let day = integer(dayText),
                  (1...31).contains(day) else { return nil }
            return Candidate(token: token(match, kind: .recurrence, label: "每月\(day)日"),
                             recurrence: .monthly, recurrenceRule: RecurrenceRule(monthDay: day))
        }
        // 4) 每年3月 / 每年3月6日 / 每年
        append("每年\\s*(?:(\\d{1,2})\\s*月)?\\s*(?:(\\d{1,2})\\s*[日号])?") { match in
            let monthText = capture(match, 1)
            let dayText = capture(match, 2)
            guard monthText != nil || dayText != nil else {
                // 裸「每年」：锚定到当天。
                return Candidate(token: token(match, kind: .recurrence, label: "每年"), recurrence: .yearly)
            }
            guard let month = Int(monthText ?? ""), (1...12).contains(month) else { return nil }
            let day = Int(dayText ?? "") ?? 1
            let label = dayText == nil ? "每年\(month)月1日" : "每年\(month)月\(day)日"
            return Candidate(token: token(match, kind: .recurrence, label: label),
                             recurrence: .yearly,
                             recurrenceRule: RecurrenceRule(monthDay: day, month: month))
        }
        // 5) 每 N 天/周/月（含省略「一」的「每天」形态）与 N 倍间隔
        append("每\\s*(\\d+|[一两二三四五六七八九十]{1,3})?\\s*(天|日|周|星期|礼拜|个月|月)") { match in
            let amountText = capture(match, 1)
            guard let unit = capture(match, 2) else { return nil }
            let raw = source.substring(with: match.range)
            if raw == "每周" || raw == "每星期" || raw == "每礼拜" {
                return Candidate(token: token(match, kind: .recurrence, label: "每周"), recurrence: .weekly)
            }
            if raw == "每月" {
                return Candidate(token: token(match, kind: .recurrence, label: "每月"), recurrence: .monthly)
            }
            guard let amountText, let amount = integer(amountText), amount >= 1, amount <= 99 else { return nil }
            let intervalLabel = amount == 1 ? "" : "\(amount)"
            switch unit {
            case "天", "日":
                let label = amount == 1 ? "每天" : "每\(amount)天"
                return Candidate(token: token(match, kind: .recurrence, label: label),
                                 recurrence: .daily, recurrenceRule: RecurrenceRule(interval: amount))
            case "周", "星期", "礼拜":
                return Candidate(token: token(match, kind: .recurrence, label: "每\(intervalLabel)周"),
                                 recurrence: .weekly, recurrenceRule: RecurrenceRule(interval: amount))
            default:
                return Candidate(token: token(match, kind: .recurrence, label: "每\(intervalLabel)月"),
                                 recurrence: .monthly, recurrenceRule: RecurrenceRule(interval: amount))
            }
        }

        append("每天|每日|每(周|星期|礼拜)([一二三四五六日天]+)|每月\\s*(\\d{1,2})\\s*[日号]?") { match in
            let raw = source.substring(with: match.range)
            if raw == "每天" || raw == "每日" {
                return Candidate(token: token(match, kind: .recurrence, label: "每天"), recurrence: .daily)
            }
            if let weekdayText = capture(match, 2) {
                let map = ["一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1]
                let weekdays = Array(Set(weekdayText.compactMap { map[String($0)] })).sorted()
                guard let weekday = weekdays.first else { return nil }
                return Candidate(token: token(match, kind: .recurrence, label: "每周\(weekdayText.replacingOccurrences(of: "天", with: "日"))"),
                                 recurrence: .weekly, recurrenceRule: RecurrenceRule(weekday: weekday,
                                     weekdays: weekdays.count > 1 ? weekdays : nil))
            }
            if let day = Int(capture(match, 3) ?? ""), (1...31).contains(day) {
                return Candidate(token: token(match, kind: .recurrence, label: "每月\(day)号"),
                                 recurrence: .monthly, recurrenceRule: RecurrenceRule(monthDay: day))
            }
            return nil
        }

        // 「提前提醒」：滴答语义是**准时 + 提前 N** 两条提醒。产出的 offset 组合
        // 是 [0, -N]（分钟，负数 = 提前），由 SchedulePlan.reminderOffsets 承接。
        // 单独出现的「提前提醒我」按表格默认 5 分钟；带数量时走下一条。
        append("(?:提前|提早)提醒我?") { match in
            return Candidate(token: token(match, kind: .reminder, label: "提前5分钟"),
                             reminderOffsets: [0, -5])
        }
        append("(?:提前|提早)\\s*(半|\\d+)\\s*(?:个)?\\s*(分钟|分|小时|钟头|天|周)?\\s*(?:提醒我?)?") { match in
            let amountText = capture(match, 1)
            let unit = capture(match, 2) ?? "分钟"
            let minutes: Int
            if let amountText {
                let value = amountText == "半" ? 0 : (Int(amountText) ?? 0)
                let factor: Int
                switch unit {
                case "小时", "钟头": factor = 60
                case "天": factor = 60 * 24
                case "周": factor = 60 * 24 * 7
                default: factor = 1
                }
                minutes = amountText == "半" ? 30 : value * factor
            } else {
                return nil
            }
            guard minutes > 0 else { return nil }
            return Candidate(token: token(match, kind: .reminder, label: "提前\(amountText!)\(unit)"),
                             reminderOffsets: [0, -minutes])
        }

        // The full quoted marker starts before any date, clock or priority
        // text inside its name, so overlap resolution keeps that text literal.
        append(#"([#@])("(?:[^"\\]|\\.)*")"#) { match in
            guard let symbol = capture(match, 1), let quoted = capture(match, 2),
                  let name = try? JSONDecoder().decode(String.self, from: Data(quoted.utf8)),
                  !name.isEmpty else { return nil }
            if symbol == "#" {
                return Candidate(token: token(match, kind: .tag, label: "#\(name)"), tag: name)
            }
            let known = knownLists.contains(name)
            return Candidate(token: token(match, kind: .list, label: "@\(name)", retainsInTitle: !known),
                             list: known ? name : nil)
        }
        append("#([^\\s#@，,。;；！!]+)") { match in
            guard let name = capture(match, 1), !name.isEmpty else { return nil }
            return Candidate(token: token(match, kind: .tag, label: "#\(name)"), tag: name)
        }
        append("@([^\\s#@，,。;；！!]+)") { match in
            guard let name = capture(match, 1), !name.isEmpty else { return nil }
            let isKnownList = knownLists.contains(name)
            return Candidate(token: token(match, kind: .list, label: "@\(name)",
                                           retainsInTitle: !isKnownList),
                             list: isKnownList ? name : nil)
        }
        append("(?m)(^|\\s)(!!!|!!)(?=\\S|\\s|$)") { match in
            let range = match.range(at: 2)
            let marks = source.substring(with: range)
            let priority: TaskPriority = marks.count == 3 ? .high : .medium
            return Candidate(token: token(match, kind: .priority,
                                           label: priority == .high ? "高优先级" : "中优先级", range: range),
                             priority: priority)
        }
        append("(?m)(^|\\s)(!)(?=\\s|$)") { match in
            let range = match.range(at: 2)
            return Candidate(token: token(match, kind: .priority, label: "低优先级", range: range), priority: .low)
        }

        let dismissedRanges = candidates
            .filter { dismissedTokenIDs.contains($0.token.id) }
            .map(\.token.range)
        let activeCandidates = candidates.filter { candidate in
            guard !dismissedTokenIDs.contains(candidate.token.id) else { return false }
            return !dismissedRanges.contains { NSIntersectionRange($0, candidate.token.range).length > 0 }
        }
        let ordered = activeCandidates.sorted {
            if $0.token.range.location != $1.token.range.location {
                return $0.token.range.location < $1.token.range.location
            }
            return $0.token.range.length > $1.token.range.length
        }
        // 整段区间（自带 dueEndAt）的起点可能被单点时钟规则「提前」吃掉
        // （前导空格算进单点 range），于是单点先占位、把区间整段排除。
        // 这里显式跳过与某个区间重叠的单点时钟，让区间自己接手。
        let rangeSpans = activeCandidates.filter { $0.dueEndAt != nil }.map(\.token.range)
        var accepted: [Candidate] = []
        var end = 0
        for candidate in ordered where candidate.token.range.location >= end {
            if candidate.dueEndAt == nil, candidate.hasTime,
               rangeSpans.contains(where: { NSIntersectionRange($0, candidate.token.range).length > 0 }) {
                continue
            }
            // The observed desktop parser recognizes the first clock in a
            // range string; the trailing clock stays as ordinary task text.
            // 例外：整段区间（`9点至11点`）由专用规则一次吃掉，它自带 dueEndAt，
            // 不能按这条「只留第一个时钟」的规则拆散，否则结束时间会丢。
            if candidate.dueEndAt == nil, candidate.hasTime,
               let prior = accepted.last(where: { $0.hasTime }),
               NSMaxRange(prior.token.range) <= candidate.token.range.location {
                let between = source.substring(with: NSRange(location: NSMaxRange(prior.token.range),
                    length: candidate.token.range.location - NSMaxRange(prior.token.range)))
                if between.trimmingCharacters(in: .whitespaces).range(of: "^[-–—~～至]+$", options: .regularExpression) != nil {
                    continue
                }
            }
            accepted.append(candidate)
            end = NSMaxRange(candidate.token.range)
        }

        var dueAt: Date?
        var dueEndAt: Date?
        var dateOnly: Date?
        var timeOnly: Date?
        var hasTime = false
        var reminderAt: Date?
        var recurrence: TaskRepeat = .never
        var recurrenceRule: RecurrenceRule?
        var tags: [String] = []
        var listName: String?
        var priority: TaskPriority = .none
        var reminderOffsets: [Int] = []
        for candidate in accepted {
            if let value = candidate.dueAt {
                dueAt = value
                dueEndAt = candidate.dueEndAt
                hasTime = candidate.hasTime
                if candidate.token.kind == .time { timeOnly = value }
                else if !candidate.hasTime { dateOnly = value }
                if candidate.hasTime { reminderAt = value }
            }
            if let offsets = candidate.reminderOffsets { reminderOffsets = offsets }
            if let value = candidate.recurrence { recurrence = value; recurrenceRule = candidate.recurrenceRule }
            if let tag = candidate.tag, !tags.contains(tag) { tags.append(tag) }
            if let list = candidate.list { listName = list }
            if let value = candidate.priority { priority = value }
        }

        if let dateOnly, let timeOnly {
            let parts = calendar.dateComponents([.hour, .minute], from: timeOnly)
            var merged = calendar.dateComponents([.year, .month, .day], from: dateOnly)
            merged.hour = parts.hour; merged.minute = parts.minute
            var result = calendar.date(from: merged) ?? dateOnly
            if calendar.isDate(dateOnly, inSameDayAs: today), result <= now {
                result = calendar.date(byAdding: .day, value: 1, to: result) ?? result
            }
            dueAt = result; hasTime = true; reminderAt = result
            // 区间：把结束时刻搬到合并后的日期上，并保持「结束晚于开始」。
            if let rangeEnd = dueEndAt {
                let endParts = calendar.dateComponents([.hour, .minute], from: rangeEnd)
                var endMerged = calendar.dateComponents([.year, .month, .day], from: result)
                endMerged.hour = endParts.hour; endMerged.minute = endParts.minute
                var end = calendar.date(from: endMerged) ?? rangeEnd
                if end <= result { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
                dueEndAt = end
            }
        } else if let timeOnly, recurrence == .weekly, let weekday = recurrenceRule?.weekday {
            let current = calendar.component(.weekday, from: now)
            let targets = recurrenceRule?.weekdays ?? [weekday]
            let delta = targets.map { ($0 - current + 7) % 7 }.min() ?? 0
            var target = calendar.date(byAdding: .day, value: delta, to: today) ?? today
            let parts = calendar.dateComponents([.hour, .minute], from: timeOnly)
            var dayParts = calendar.dateComponents([.year, .month, .day], from: target)
            dayParts.hour = parts.hour; dayParts.minute = parts.minute
            target = calendar.date(from: dayParts) ?? target
            if target <= now { target = calendar.date(byAdding: .day, value: 7, to: target) ?? target }
            dueAt = target; hasTime = true; reminderAt = target
        }

        let tokens = accepted.map(\.token).sorted { $0.range.location < $1.range.location }
        let cleanedTitle = title(input, removing: tokens)

        return QuickAddParseResult(title: cleanedTitle, listName: listName, dueAt: dueAt,
                                   dueEndAt: dueEndAt,
                                   hasTime: hasTime, reminderAt: reminderAt,
                                   reminderOffsets: reminderOffsets.isEmpty ? [] : reminderOffsets.sorted(),
                                   recurrence: recurrence, recurrenceRule: recurrenceRule,
                                   tags: tags, priority: priority, tokens: tokens,
                                   sourceText: input)
    }

    /// Transitional overload for existing views that still own list names as an array.
    /// New call sites should pass `knownLists` as a set.
    static func parse(_ input: String, now: Date, calendar: Calendar,
                      availableLists: [String], dismissedTokenIDs: Set<String> = []) -> QuickAddParseResult {
        parse(input, now: now, calendar: calendar, knownLists: Set(availableLists),
              dismissedTokenIDs: dismissedTokenIDs)
    }
}
