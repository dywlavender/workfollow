import Foundation

/// 把日程面板的提交结果**回写进输入框文字**。
///
/// 背景：快速添加条上本来就有两套值——文字解析出来的 token，和用户在面板里
/// 改过的 `QuickAddScheduleDraft`。面板改完只更新后者时，chip 仍显示文字里的
/// 旧值（「提前3分钟」改成了 30 分钟，chip 还写 3 分钟），用户看不出到底建了
/// 哪个。这里把面板结果写成等价文字，让文字、chip、最终任务三者一致。
///
/// 两条硬约束：
/// 1. **只动日程类片段**，标题、标签、清单、优先级一律原样保留。
/// 2. 生成的文字必须能被 `QuickAddParser` 原样解析回同一个值，
///    否则「写回去」会引入一轮新的漂移。`roundTripVerified` 就是这条守卫。
enum QuickAddScheduleTextSync {
    /// 可回写的日程维度。
    enum Dimension: String, CaseIterable {
        case date, recurrence, reminder
    }

    /// 文字里是否存在可改写的日程片段。没有的话面板改完也没处落笔
    /// （例如用户只打了标题、靠面板设了日期），此时宿主保留 override 即可。
    static func hasScheduleTokens(in text: String, now: Date, calendar: Calendar,
                                  knownLists: Set<String>,
                                  dismissedTokenIDs: Set<String> = []) -> Bool {
        !dimensions(in: text, now: now, calendar: calendar, knownLists: knownLists,
                    dismissedTokenIDs: dismissedTokenIDs).isEmpty
    }

    static func dimensions(in text: String, now: Date, calendar: Calendar,
                           knownLists: Set<String>,
                           dismissedTokenIDs: Set<String> = []) -> Set<Dimension> {
        let tokens = QuickAddParser.parse(text, now: now, calendar: calendar,
                                          knownLists: knownLists,
                                          dismissedTokenIDs: dismissedTokenIDs).tokens
        var result: Set<Dimension> = []
        for token in tokens where !token.retainsInTitle {
            switch token.kind {
            case .date: result.insert(.date)
            case .time: result.insert(.date)          // 时刻属于日期维度
            case .recurrence: result.insert(.recurrence)
            case .reminder: result.insert(.reminder)
            case .tag, .list, .priority: break
            }
        }
        return result
    }

    /// 用面板结果改写文字。
    ///
    /// - Returns: 新文字；`nil` 表示这段文字没有可落的日程片段，调用方应保留 override。
    static func rewrite(_ text: String, to draft: QuickAddScheduleDraft,
                        now: Date, calendar: Calendar, knownLists: Set<String>,
                        dismissedTokenIDs: Set<String> = []) -> String? {
        let parsed = QuickAddParser.parse(text, now: now, calendar: calendar,
                                          knownLists: knownLists,
                                          dismissedTokenIDs: dismissedTokenIDs)
        let editable = parsed.tokens.filter { !$0.retainsInTitle && isSchedule($0.kind) }
        guard !editable.isEmpty else { return nil }

        // 逐维度取「已有片段」和「新值」。
        let dateTokens = editable.filter { $0.kind == .date || $0.kind == .time }
        let recurrenceTokens = editable.filter { $0.kind == .recurrence }
        let reminderTokens = editable.filter { $0.kind == .reminder }

        var replacements: [(range: NSRange, text: String)] = []
        /// 文字里原本没有的维度（新增重复/新增提前提醒）：追加到末尾。
        var appends: [String] = []

        // ── 日期/时间 ─────────────────────────────────────────────
        if !dateTokens.isEmpty {
            let wantsDate = draft.dueAt != nil
            let dateText = wantsDate ? datePhrase(draft, now: now, calendar: calendar) : ""
            // 重新赋日期时把面板的「结束时间」也一并写出来，否则区间会丢。
            let combined: String
            if wantsDate, let end = draft.dueEndAt, let start = draft.dueAt, end > start {
                combined = dateText + "至" + timePhrase(end, calendar: calendar)
            } else {
                combined = dateText
            }
            replacements.append(contentsOf: merge(dateTokens, into: combined))
        }

        // ── 重复 ──────────────────────────────────────────────────
        // 重复要能**新增**：用户先在面板里选了「每天」，文字里原本没有重复片段，
        // 此时只靠「替换已有片段」会无处落笔，chips 就会和面板不一致。
        let recurrenceText = recurrencePhrase(draft, calendar: calendar) ?? ""
        if !recurrenceTokens.isEmpty {
            replacements.append(contentsOf: merge(recurrenceTokens, into: recurrenceText))
        } else if !recurrenceText.isEmpty {
            appends.append(recurrenceText)
        }

        // ── 提前提醒 ──────────────────────────────────────────────
        let reminderText = reminderPhrase(draft)
        if !reminderTokens.isEmpty {
            replacements.append(contentsOf: merge(reminderTokens, into: reminderText))
        } else if !reminderText.isEmpty {
            appends.append(reminderText)
        }

        guard !replacements.isEmpty || !appends.isEmpty else { return nil }
        var rewritten = apply(replacements, to: text)
        if !appends.isEmpty {
            rewritten = ([rewritten] + appends).filter { !$0.isEmpty }.joined(separator: " ")
        }
        // 守卫：写回的文字必须解析回同一个值，否则宁可放弃回写（让 override 继续生效），
        // 也不要把用户的文字改成一个意思不同的句子。
        guard roundTripVerified(rewritten, equals: draft, now: now, calendar: calendar,
                                knownLists: knownLists, dismissedTokenIDs: dismissedTokenIDs) else {
            return nil
        }
        return rewritten
    }

    // MARK: - 片段替换

    /// 把一组旧片段折成**一个**新片段：保留第一个片段的位置，其余片段删掉。
    /// 这样「下午3点」这种被拆成日期+时刻的两段不会各自写一份日期。
    private static func merge(_ tokens: [QuickAddToken],
                              into text: String) -> [(range: NSRange, text: String)] {
        guard let first = tokens.min(by: { $0.range.location < $1.range.location }) else { return [] }
        if text.isEmpty {
            // 整类被清空：所有片段都删掉。
            return tokens.map { ($0.range, "") }
        }
        // 前后补空格：中文片段直接相邻会粘在一起（「15:00提前1小时」读不回）。
        var result: [(range: NSRange, text: String)] = [(first.range, " " + text + " ")]
        for token in tokens where token.range.location != first.range.location {
            result.append((token.range, " "))
        }
        return result
    }

    /// 从后往前替换，避免前面的替换让后面的 range 失效。
    private static func apply(_ replacements: [(range: NSRange, text: String)],
                              to text: String) -> String {
        let mutable = NSMutableString(string: text)
        for item in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            guard item.range.location >= 0, NSMaxRange(item.range) <= mutable.length else { continue }
            mutable.replaceCharacters(in: item.range, with: item.text)
        }
        // 片段删掉后可能留下孤立标点（「15:00，」／「，开会」），一并收干净：
        // 连续标点折成一个、去首尾、标点两侧不留空格。
        var text = (mutable as String)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        text = text.replacingOccurrences(of: "([，,、；;])\\1+", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s*([，,、；;])\\s*", with: "$1", options: .regularExpression)
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " ，,、。;；-—"))
    }

    private static func isSchedule(_ kind: QuickAddToken.Kind) -> Bool {
        switch kind {
        case .date, .time, .recurrence, .reminder: true
        case .tag, .list, .priority: false
        }
    }

    // MARK: - 各维度生成文字

    /// 日期（含时刻）的等价文字：`2026年9月15日 09:00` / `9月15日` / `15:00`。
    /// 用**完整年月日**而非常见短词（明天/周三）：重新生成时不知道用户的「今天」
    /// 是哪天，绝对日期在任何时刻解析都稳定。
    static func datePhrase(_ draft: QuickAddScheduleDraft,
                           now: Date, calendar: Calendar) -> String {
        guard let due = draft.dueAt else { return "" }
        return datePhrase(due, hasTime: draft.hasTime, calendar: calendar)
    }

    static func datePhrase(_ date: Date, hasTime: Bool, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = "\(parts.year ?? 0)年\(parts.month ?? 1)月\(parts.day ?? 1)日"
        guard hasTime else { return day }
        return day + String(format: " %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func timePhrase(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 重复的等价文字。优先用解析器**已经认识**的写法，避免写出自己能写不能读的词。
    /// 返回 nil 表示「不重复」，调用方会清掉文字里的重复片段。
    static func recurrencePhrase(_ draft: QuickAddScheduleDraft, calendar: Calendar) -> String? {
        let rule = draft.recurrenceRule
        let interval = rule?.interval ?? 1
        func every(_ unit: String, _ base: String) -> String {
            interval <= 1 ? base : "每\(interval)\(unit)"
        }
        switch draft.repeatFrequency {
        case .never: return nil
        case .daily: return every("天", "每天")
        case .weekly:
            if let weekdays = rule?.weekdays, !weekdays.isEmpty {
                // Calendar 口径 1=周日 … 7=周六 → 中文序。
                let names = ["日", "一", "二", "三", "四", "五", "六"]
                let text = weekdays.sorted().compactMap { value -> String? in
                    guard value >= 1, value <= 7 else { return nil }
                    return names[value - 1]
                }.joined()
                if interval <= 1, !text.isEmpty { return "每周\(text)" }
            }
            if let weekday = rule?.weekday, interval <= 1, (1...7).contains(weekday) {
                return "每周" + ["日", "一", "二", "三", "四", "五", "六"][weekday - 1]
            }
            return every("周", "每周")
        case .monthly:
            if interval <= 1 {
                if rule?.monthlyOrdinal == -1 { return "每月最后一天" }
                if let day = rule?.monthDay, (1...31).contains(day) { return "每月\(day)日" }
            }
            return every("月", "每月")
        case .yearly:
            if interval <= 1, let month = rule?.month, (1...12).contains(month) {
                let day = rule?.monthDay ?? 1
                return "每年\(month)月\(day)日"
            }
            return "每年"
        case .workdays: return "每个工作日"
        case .weekends: return "每周末"
        case .weekdays: return "每周一至周五"
        // 农历/法定休息日/艾宾浩斯没有解析器识别得到的简短写法：
        // 不生成文字，让 override 继续承担（宁可文字不动，也不要写出读不回的词）。
        case .lunarYearly, .lunarMonthly, .ebbinghaus, .holidays: return nil
        }
    }

    /// 提前提醒的等价文字：`提前30分钟`。多级提醒里取**最靠前**的一档
    /// （负得最多），因为解析器只产出一档提前；准时项不写进文字。
    static func reminderPhrase(_ draft: QuickAddScheduleDraft) -> String {
        let early = draft.reminderOffsets.filter { $0 < 0 }.min()
        guard let early else { return "" }
        let minutes = abs(early)
        if minutes % (60 * 24) == 0 { return "提前\(minutes / (60 * 24))天" }
        if minutes % 60 == 0 { return "提前\(minutes / 60)小时" }
        return "提前\(minutes)分钟"
    }

    // MARK: - 写回守卫

    /// 写回后的文字是否仍解析成同一份日程（日期/时刻/重复/提前提醒）。
    private static func roundTripVerified(_ text: String, equals draft: QuickAddScheduleDraft,
                                          now: Date, calendar: Calendar,
                                          knownLists: Set<String>,
                                          dismissedTokenIDs: Set<String>) -> Bool {
        let reparsed = QuickAddParser.parse(text, now: now, calendar: calendar,
                                           knownLists: knownLists,
                                           dismissedTokenIDs: dismissedTokenIDs)
        // 日期：允许面板值在「无文字片段」时缺省，一旦写了就必须对得上。
        if let wanted = draft.dueAt {
            guard let got = reparsed.dueAt,
                  calendar.isDate(wanted, equalTo: got, toGranularity: draft.hasTime ? .minute : .day)
            else { return false }
        } else if reparsed.dueAt != nil {
            return false
        }
        if draft.hasTime != reparsed.hasTime { return false }
        if draft.repeatFrequency != reparsed.recurrence { return false }
        if draft.repeatFrequency != .never,
           (draft.recurrenceRule?.interval ?? 1) != (reparsed.recurrenceRule?.interval ?? 1) {
            return false
        }
        // 提前提醒：只比「最早的提前档」，解析器只表达一档。
        let wantedEarly = draft.reminderOffsets.filter { $0 < 0 }.min()
        let gotEarly = reparsed.reminderOffsets.filter { $0 < 0 }.min()
        return wantedEarly == gotEarly
    }
}
