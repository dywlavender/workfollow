import Foundation

struct QuickAddToken: Identifiable, Equatable {
    enum Kind: String { case date, time, recurrence, tag, list, priority }
    let kind: Kind
    let label: String
    let range: NSRange
    let raw: String
    var id: String { "\(kind.rawValue):\(range.location):\(range.length):\(raw)" }
}

struct QuickAddParseResult {
    let title: String
    let listName: String?
    let dueAt: Date?
    let hasTime: Bool
    let reminderAt: Date?
    let recurrence: TaskRepeat
    let recurrenceRule: RecurrenceRule?
    let tags: [String]
    let priority: TaskPriority
    let tokens: [QuickAddToken]

    var summary: String { tokens.map(\.label).joined(separator: " · ") }
}

/// A focused native port of the Flutter smart-capture vocabulary. Parsing is
/// pure and injects both `now` and `calendar`, making relative dates testable.
enum QuickAddParser {
    private struct Candidate {
        let token: QuickAddToken
        var dueAt: Date?
        var hasTime = false
        var recurrence: TaskRepeat?
        var recurrenceRule: RecurrenceRule?
        var tag: String?
        var list: String?
        var priority: TaskPriority?
    }

    static func hasDismissedScheduleToken(in input: String, now: Date, calendar: Calendar,
                                          availableLists: [String], dismissedTokenIDs: Set<String>) -> Bool {
        guard !dismissedTokenIDs.isEmpty else { return false }
        let allTokens = parse(input, now: now, calendar: calendar, availableLists: availableLists).tokens
        return allTokens.contains { token in
            dismissedTokenIDs.contains(token.id) && (token.kind == .date || token.kind == .time)
        }
    }

    static func parse(_ input: String, now: Date, calendar: Calendar,
                      availableLists: [String], dismissedTokenIDs: Set<String> = []) -> QuickAddParseResult {
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
                   label: String, range: NSRange? = nil) -> QuickAddToken {
            let tokenRange = range ?? match.range
            return QuickAddToken(kind: kind, label: label, range: tokenRange,
                                 raw: source.substring(with: tokenRange))
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
        func integer(_ raw: String?) -> Int? {
            guard let raw else { return nil }
            if let value = Int(raw) { return value }
            let digits: [Character: Int] = ["零": 0, "一": 1, "两": 2, "二": 2,
                                             "三": 3, "四": 4, "五": 5, "六": 6,
                                             "七": 7, "八": 8, "九": 9, "十": 10]
            if raw == "十" { return 10 }
            if raw.hasPrefix("十"), let unit = digits[raw.last!] { return 10 + unit }
            if raw.hasSuffix("十"), let tens = digits[raw.first!] { return tens * 10 }
            return raw.reduce(0) { $0 * 10 + (digits[$1] ?? 0) }
        }
        func clockValue(_ hourText: String?, _ period: String?, _ minuteText: String?) -> (Int, Int)? {
            guard var hour = integer(hourText), hour <= 23 else { return nil }
            var minute = 0
            if minuteText == "半" { minute = 30 }
            else if let minuteText {
                let digits = minuteText.replacingOccurrences(of: "分", with: "").trimmingCharacters(in: .whitespaces)
                if !digits.isEmpty { guard let value = Int(digits), value <= 59 else { return nil }; minute = value }
            }
            if (period == "下午" || period == "晚上" || period == "明晚" || period == "今晚") && hour < 12 { hour += 12 }
            if period == "中午" && hour < 11 { hour += 12 }
            return (hour, minute)
        }
        func nextClock(_ hour: Int, _ minute: Int) -> Date {
            let candidate = makeDate(today, hour: hour, minute: minute)
            return candidate > now ? candidate : (calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate)
        }
        func formatted(_ date: Date, time: Bool) -> String {
            let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
            let dateLabel = "\(parts.month ?? 1)月\(parts.day ?? 1)日"
            guard time else { return dateLabel }
            return dateLabel + String(format: " %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }

        // Combined forms such as “明早9点” and “明天 下午3点” take precedence
        // over their overlapping date-only and clock-only matches.
        append("(今天|今日|明天|明日|后天|大后天|今晚|今早|明早|明晨|明晚)?\\s*(早上|上午|中午|下午|晚上)?\\s*(\\d{1,2}|[零一两二三四五六七八九十]{1,3})\\s*(点|时|[:：])\\s*(半|[0-5]?\\d\\s*分?)?") { match in
            guard let clock = clockValue(capture(match, 3), capture(match, 2) ?? capture(match, 1), capture(match, 5)) else { return nil }
            let dayWord = capture(match, 1)
            let explicitDay = dayWord.flatMap(dateForWord)
            var due = explicitDay.map { makeDate($0, hour: clock.0, minute: clock.1) } ?? nextClock(clock.0, clock.1)
            if let explicitDay, calendar.isDate(explicitDay, inSameDayAs: today), due <= now {
                due = calendar.date(byAdding: .day, value: 1, to: due) ?? due
            }
            let isDateTime = explicitDay != nil || capture(match, 2) != nil ||
                ["今晚", "今早", "明早", "明晨", "明晚"].contains(dayWord ?? "")
            return Candidate(token: token(match, kind: isDateTime ? .date : .time,
                                           label: formatted(due, time: true)),
                             dueAt: due, hasTime: true)
        }

        // Relative intervals support the same common capture forms as Flutter.
        append("(半|\\d+)\\s*(?:个)?(小时|分钟|天)(?:之|以)?后") { match in
            guard let amountText = capture(match, 1), let unit = capture(match, 2) else { return nil }
            let due: Date
            let exact: Bool
            if unit == "天" {
                guard let amount = Int(amountText) else { return nil }
                due = calendar.date(byAdding: .day, value: amount, to: today) ?? today
                exact = false
            } else {
                let amount = Int(amountText) ?? 0
                let seconds = amountText == "半" ? 30 * 60
                    : unit == "小时" ? amount * 3600 : amount * 60
                due = now.addingTimeInterval(TimeInterval(seconds))
                exact = true
            }
            return Candidate(token: token(match, kind: exact ? .time : .date,
                                           label: formatted(due, time: exact)),
                             dueAt: due, hasTime: exact)
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
            if prefix == "下" { delta += 7 }
            if prefix == "下下" { delta += 14 }
            let date = calendar.date(byAdding: .day, value: delta, to: today) ?? today
            return Candidate(token: token(match, kind: .date, label: formatted(date, time: false)), dueAt: date)
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

        append("每天|每日|每(周|星期|礼拜)([一二三四五六日天])|每月\\s*(\\d{1,2})\\s*[日号]?") { match in
            let raw = source.substring(with: match.range)
            if raw == "每天" || raw == "每日" {
                return Candidate(token: token(match, kind: .recurrence, label: "每天"), recurrence: .daily)
            }
            if let weekdayText = capture(match, 2) {
                let map = ["一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1]
                guard let weekday = map[weekdayText] else { return nil }
                return Candidate(token: token(match, kind: .recurrence, label: "每周\(weekdayText == "天" ? "日" : weekdayText)"),
                                 recurrence: .weekly, recurrenceRule: RecurrenceRule(weekday: weekday))
            }
            if let day = Int(capture(match, 3) ?? ""), (1...31).contains(day) {
                return Candidate(token: token(match, kind: .recurrence, label: "每月\(day)号"),
                                 recurrence: .monthly, recurrenceRule: RecurrenceRule(monthDay: day))
            }
            return nil
        }

        append("#([^\\s#@，,。;；！!]+)") { match in
            guard let name = capture(match, 1), !name.isEmpty else { return nil }
            return Candidate(token: token(match, kind: .tag, label: "#\(name)"), tag: name)
        }
        append("@([^\\s#@，,。;；！!]+)") { match in
            guard let name = capture(match, 1), availableLists.contains(name) else { return nil }
            return Candidate(token: token(match, kind: .list, label: "@\(name)"), list: name)
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
        var accepted: [Candidate] = []
        var end = 0
        for candidate in ordered where candidate.token.range.location >= end {
            accepted.append(candidate)
            end = NSMaxRange(candidate.token.range)
        }

        var dueAt: Date?
        var dateOnly: Date?
        var timeOnly: Date?
        var hasTime = false
        var reminderAt: Date?
        var recurrence: TaskRepeat = .never
        var recurrenceRule: RecurrenceRule?
        var tags: [String] = []
        var listName: String?
        var priority: TaskPriority = .none
        for candidate in accepted {
            if let value = candidate.dueAt {
                dueAt = value
                hasTime = candidate.hasTime
                if candidate.token.kind == .time { timeOnly = value }
                else if !candidate.hasTime { dateOnly = value }
                if candidate.hasTime { reminderAt = value }
            }
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
        } else if let timeOnly, recurrence == .weekly, let weekday = recurrenceRule?.weekday {
            let current = calendar.component(.weekday, from: now)
            let delta = (weekday - current + 7) % 7
            var target = calendar.date(byAdding: .day, value: delta, to: today) ?? today
            let parts = calendar.dateComponents([.hour, .minute], from: timeOnly)
            var dayParts = calendar.dateComponents([.year, .month, .day], from: target)
            dayParts.hour = parts.hour; dayParts.minute = parts.minute
            target = calendar.date(from: dayParts) ?? target
            if target <= now { target = calendar.date(byAdding: .day, value: 7, to: target) ?? target }
            dueAt = target; hasTime = true; reminderAt = target
        }

        let tokens = accepted.map(\.token).sorted { $0.range.location < $1.range.location }
        let titleParts = NSMutableString(string: input)
        for token in tokens.sorted(by: { $0.range.location > $1.range.location }) {
            titleParts.replaceCharacters(in: token.range, with: " ")
        }
        let title = titleParts as String
        let cleanedTitle = title.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "，,、。;；-— "))

        return QuickAddParseResult(title: cleanedTitle, listName: listName, dueAt: dueAt,
                                   hasTime: hasTime, reminderAt: reminderAt,
                                   recurrence: recurrence, recurrenceRule: recurrenceRule,
                                   tags: tags, priority: priority, tokens: tokens)
    }
}
