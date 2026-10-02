import Foundation

/// 倒数纪念日的一条记录。四种类型（纪念日 / 倒数日 / 节日 / 生日）共用一套字段，
/// 差异只落在默认值与「显示岁数」这一项上——对齐参考实现的添加面板：切换「类型」
/// 会同时换掉图标、名称占位与默认重复，但不再多出别的字段。
struct CountdownEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var kind: CountdownKind
    /// 日期规则。`repeat`（重复）由它派生，不另存一份，避免两者漂移。
    var rule: CountdownRule
    /// SF Symbol 名，只从 `symbolOptions` 白名单里取。
    var symbol: String
    /// 固定色板下标（0..<`paletteSize`），具体颜色由界面侧映射。
    var colorIndex: Int
    /// 提前提醒的分钟数，0 = 当天。排序去重后存。
    var reminderOffsets: [Int]
    /// 「显示」行是否出现在智能清单里。**保留这个老字段**是为了让存量 JSON 继续能读，
    /// 写入时由 `smartListDisplay` 同步过来，界面只认 `effectiveSmartListDisplay`。
    var showsInSmartList: Bool
    /// 「显示」行的五选一。**可选**：存量 JSON 里没有这个键，解出来是 nil，
    /// 由 `effectiveSmartListDisplay` 回退到 `showsInSmartList`——加字段不能把
    /// 已有记录的「显示」读没了。
    var smartListDisplay: CountdownSmartListDisplay?
    /// 卡片中间那个大数字的显示单位（天 / 月 / 周），点卡片轮换。
    /// **可选**：存量 JSON 里没有这个键，解出来是 nil，由 `effectiveDisplayUnit` 回退到「天」。
    var displayUnit: CountdownDisplayUnit?
    /// 对应「显示岁数」开关，只对生日有意义。
    var showsAge: Bool
    var note: String
    var pinned: Bool
    /// nil 表示未归档。
    var archivedAt: Date?
    var sortOrder: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        kind: CountdownKind = .anniversary,
        rule: CountdownRule,
        symbol: String? = nil,
        colorIndex: Int? = nil,
        reminderOffsets: [Int] = CountdownEvent.defaultReminderOffsets,
        showsInSmartList: Bool = true,
        smartListDisplay: CountdownSmartListDisplay? = nil,
        displayUnit: CountdownDisplayUnit? = nil,
        showsAge: Bool = false,
        note: String = "",
        pinned: Bool = false,
        archivedAt: Date? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.rule = rule
        self.symbol = symbol ?? kind.defaultSymbol
        self.colorIndex = colorIndex ?? kind.defaultColorIndex
        self.reminderOffsets = CountdownEvent.normalizedReminderOffsets(reminderOffsets)
        self.smartListDisplay = smartListDisplay
        // 两个字段写的时候保持同步：新字段是准的，老字段是给存量读的。
        self.showsInSmartList = smartListDisplay?.showsInSmartList ?? showsInSmartList
        self.displayUnit = displayUnit
        self.showsAge = showsAge
        self.note = note
        self.pinned = pinned
        self.archivedAt = archivedAt
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    /// 未归档即为进行中。
    var isActive: Bool { archivedAt == nil }

    /// 展示用符号名：白名单外的历史数据回退到该类型的默认符号。
    var safeSymbol: String {
        Self.symbolOptions.contains(symbol) ? symbol : kind.defaultSymbol
    }

    /// 名称兜底（空名称不显示为空行）。
    var displayName: String { name.isEmpty ? "未命名" : name }

    /// 面板里「重复」行的选中项，由规则派生（不另存一份，避免两者漂移）。
    var repeatValue: CountdownRepeat { rule.repeatValue }

    /// 「显示」行实际生效的选择。存量记录没有 `smartListDisplay` 这个键，
    /// 用老字段 `showsInSmartList` 推导，界面一律读这个。
    var effectiveSmartListDisplay: CountdownSmartListDisplay {
        smartListDisplay ?? (showsInSmartList ? .sameDay : .never)
    }

    /// 卡片主数字实际生效的单位。存量记录没有 `displayUnit` 这个键，回退到「天」。
    var effectiveDisplayUnit: CountdownDisplayUnit { displayUnit ?? .day }

    /// 这条记录的日期是否走农历。副标题的农历前缀与「按月」的月长都用它，
    /// 两处必须一致，所以只留一份判断。
    var usesLunarCalendar: Bool {
        switch rule {
        case .lunarYearly, .lunarEve, .lunarOnce:
            return true
        case .daily(let lunar, _), .weekly(_, let lunar, _), .monthly(_, let lunar, _),
             .interval(_, let lunar, _):
            return lunar
        default:
            return false
        }
    }
}

// MARK: - 类型

enum CountdownKind: String, Codable, CaseIterable, Identifiable {
    /// 顺序即 `allCases` 的顺序，`+` 菜单和「类型」下拉都照它排。
    /// 参考实现的 `+` 菜单实测是 纪念日 / 倒数日 / **生日** / **节日**（生日在节日前）。
    /// 注意页头胶囊是**另一套**（所有 / 纪念日 / 倒数日 / 节日，没有生日）：
    /// 胶囊里的「纪念日」把生日一起收了，映射见 `CountdownFilter.kinds`。
    case anniversary, countdown, birthday, festival

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anniversary: return "纪念日"
        case .countdown: return "倒数日"
        case .festival: return "节日"
        case .birthday: return "生日"
        }
    }

    /// 新建面板里名称输入框的占位文字。
    ///
    /// 四张参考图各开了一种类型，占位文字**随类型变**：
    /// 纪念日 / 生日 → 「纪念」，倒数日 / 节日 → 「名称」。
    /// （`+` 在原版是个菜单，选哪个类型就直接开哪个类型的面板，所以这四个取值
    /// 都是「该类型的初始态」，不是切类型切出来的。）
    /// 语言包里查不到倒数纪念日专用的名称占位串，所以这里按观察到的样子写成表。
    var namePlaceholder: String {
        switch self {
        case .anniversary, .birthday: return "纪念"
        case .countdown, .festival: return "名称"
        }
    }

    /// 参考图的默认图标（圆形底色 + 白色字形）。
    var defaultSymbol: String {
        switch self {
        case .anniversary: return "heart"
        case .countdown: return "hourglass"
        case .festival: return "party.popper"
        case .birthday: return "birthday.cake"
        }
    }

    /// 参考图的默认色板下标（见 CountdownWorkspaceView 的调色板顺序）。
    var defaultColorIndex: Int {
        switch self {
        case .anniversary: return 1  // 橙
        case .countdown: return 4    // 蓝
        case .festival: return 0     // 红
        case .birthday: return 5     // 紫
        }
    }

    /// 参考图里新建时的默认重复：纪念日 / 倒数日为「无」，生日 / 节日为「每年」。
    var defaultRepeat: CountdownRepeat {
        switch self {
        case .anniversary, .countdown: return .never
        case .festival, .birthday: return .yearly
        }
    }

    /// 只有生日多出「显示岁数」一行。
    var hasAgeOption: Bool { self == .birthday }
}

// MARK: - 重复

/// 「重复」行的六个选项。顺序即参考图下拉的顺序：
/// 无 / 每天 / 每周（周二）/ 每月（初一）/ 每年（正月初一）/ 自定义。
enum CountdownRepeat: String, Codable, CaseIterable, Identifiable {
    case never, daily, weekly, monthly, yearly, custom

    var id: String { rawValue }

    /// 选项文字**不含括注**；带括注的行内文案见 `label(_:rule:asOf:calendar:)`。
    var title: String {
        switch self {
        case .never: return "无"
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .yearly: return "每年"
        case .custom: return "自定义"
        }
    }
}

extension CountdownRepeat {
    /// 参考图的「重复」选项带括注，而括注是**算出来的**，不是写死的字符串。
    ///
    /// 锚点分两处，这是照着图推的（**推理，不是实测**）：
    /// - 每周（周二）：取**今天**的星期。参考图截于 2026-09-29，那天正是周二；
    ///   而同屏「日期」选的农历正月初一落在 2027/2/6（周六）——周二 只可能来自今天。
    /// - 每月（初一）/ 每年（正月初一）：取「日期」那一行的月/日。
    ///   每周没有对应的「日」字段可用，所以它锚今天；月/年有，所以锚日期。
    static func label(_ value: CountdownRepeat, rule: CountdownRule?,
                      asOf today: Date, calendar: Calendar) -> String {
        switch value {
        case .never:
            return "无"
        case .daily:
            return "每天"
        case .weekly:
            let weekday = calendar.component(.weekday, from: today)
            return "每周（\(weekdayName(weekday))）"
        case .monthly:
            guard let day = rule?.monthlyAnchorLabel(calendar: calendar) else { return "每月" }
            return "每月（\(day)）"
        case .yearly:
            guard let text = rule?.yearlyAnchorLabel(calendar: calendar) else { return "每年" }
            return "每年（\(text)）"
        case .custom:
            return "自定义"
        }
    }

    /// `Calendar` 的星期序号（1 = 周日）转中文。
    static func weekdayName(_ weekday: Int) -> String {
        let names = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        guard (1...7).contains(weekday) else { return "周日" }
        return names[weekday]
    }
}

// MARK: - 显示（智能清单）

/// 「显示」行：这条记录什么时候出现在智能清单里。参考图下拉是一个
/// 「在智能清单中」分组标题 + 五个选项。
enum CountdownSmartListDisplay: String, Codable, CaseIterable, Identifiable {
    case sameDay, threeDaysBefore, sevenDaysBefore, always, never

    var id: String { rawValue }

    /// 下拉里的选项文字。
    var title: String {
        switch self {
        case .sameDay: return "当天显示"
        case .threeDaysBefore: return "提前 3 天显示"
        case .sevenDaysBefore: return "提前 7 天显示"
        case .always: return "一直显示"
        case .never: return "不显示"
        }
    }

    /// 「显示」行里显示的值。参考图实测是 `在智能清单中当天显示`——即分组标题
    /// 拼上选项文字。`不显示` 拼出来是「在智能清单中不显示」，读着别扭，这里
    /// 单独写成「不在智能清单中显示」（**取舍**，参考图只有「当天显示」那一态可见）。
    var rowText: String {
        self == .never ? "不在智能清单中显示" : "在智能清单中" + title
    }

    /// 是否出现在智能清单里；老字段 `showsInSmartList` 由它派生。
    var showsInSmartList: Bool { self != .never }

    /// 参考图里分组标题的写法。
    static let groupTitle = "在智能清单中"
}

// MARK: - 日期规则

/// 一条记录的日期语义。`repeatValue`（重复）是它的派生视图，不单独存。
///
/// 「日期」与「重复」在面板上是两行，但底层只有这一份规则：日期规则本身就把
/// 节奏带上了（`.once` = 无，`.solarYearly` = 每年……）。参考图的「重复」下拉
/// 比这多出 每天 / 每周 / 每月 / 自定义 四种，所以这里补了对应的 case，
/// 并且每个 case 都带上 `anchor`——「日期」那一行要能照原样回显。
enum CountdownRule: Equatable, Codable {
    /// 只发生一次的公历日期。
    case once(Date)
    /// 每年重复的公历月/日（元旦、国庆节……）。
    case solarYearly(month: Int, day: Int)
    /// 每年重复的农历月/日（春节、中秋……）。闰月不算。
    case lunarYearly(month: Int, day: Int)
    /// 农历**某一年**的某月/某日，只发生一次。
    ///
    /// 与 `.lunarYearly` 的区别只在年份：编辑器的「忽略年份」勾掉时走这条，
    /// 「农历 2027 年正月初一」要能原样回显成 `农历2027年正月初一`，而不是
    /// 被折算成一个公历日期（折算后就再也回不到农历写法了）。
    case lunarOnce(month: Int, day: Int, year: Int)
    /// 除夕：下一个正月初一的前一天。它的农历月/日随年份变（腊月廿九或三十），
    /// 所以不能写成固定的 `lunarYearly(12, 30)`。
    case lunarEve
    /// 生日：每年重复，但**额外记住出生年**——「显示岁数」要算周岁，
    /// 只留月/日是算不出来的。
    case birthday(month: Int, day: Int, birthYear: Int)
    /// 每天重复。`anchor` 只用于「日期」行的回显，不参与算落点。
    case daily(lunar: Bool, anchor: Date)
    /// 每周重复。`weekday` 用 `Calendar` 的 1=周日…7=周六。
    case weekly(weekday: Int, lunar: Bool, anchor: Date)
    /// 每月重复。`lunar` 为真时 `day` 是农历日（初一…），否则是公历日。
    case monthly(day: Int, lunar: Bool, anchor: Date)
    /// 自定义：每 `days` 天一次。
    case interval(days: Int, lunar: Bool, anchor: Date)

    var isRepeating: Bool {
        switch self {
        case .once, .lunarOnce: return false
        default: return true
        }
    }

    /// 「重复」行的选中项。
    var repeatValue: CountdownRepeat {
        switch self {
        case .once, .lunarOnce: return .never
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        case .interval: return .custom
        case .solarYearly, .lunarYearly, .lunarEve, .birthday: return .yearly
        }
    }

    /// 「日期」行显示的文本；还没选日期时为 nil。
    ///
    /// 照参考图的写法：农历规则带 `农历` 前缀（`农历正月初一`），公历规则写
    /// `yyyy/M/d` 或 `M月d日`。**不带「每年」**——节奏由「重复」那一行表达，
    /// 参考图里 `日期 = 农历正月初一` 与 `重复 = 每年（正月初一）` 是分开写的。
    var dateText: String? {
        switch self {
        case .once(let date):
            return CountdownEvent.solarText(date)
        case .solarYearly(let month, let day):
            return "\(month)月\(day)日"
        case .lunarYearly(let month, let day):
            return "农历" + CountdownLunar.label(month: month, day: day)
        case .lunarOnce(let month, let day, let year):
            // 「忽略年份」没勾时要把年份写出来——那正是它与 `.lunarYearly` 的可见差别。
            return "农历\(year)年" + CountdownLunar.label(month: month, day: day)
        case .lunarEve:
            return "农历除夕"
        case .birthday(let month, let day, _):
            return "\(month)月\(day)日"
        case .daily(let lunar, let anchor),
             .weekly(_, let lunar, let anchor),
             .interval(_, let lunar, let anchor):
            return Self.anchorText(anchor, lunar: lunar)
        case .monthly(let day, let lunar, _):
            return lunar ? "农历每月\(CountdownLunar.dayName(day))" : "每月 \(day) 日"
        }
    }

    /// 新节奏的 `anchor` 回显。
    private static func anchorText(_ anchor: Date, lunar: Bool) -> String {
        if lunar, let parts = CountdownLunar.lunarComponents(of: anchor, calendar: .current) {
            return "农历" + CountdownLunar.label(month: parts.month, day: parts.day)
        }
        return CountdownEvent.solarText(anchor)
    }
}

// MARK: - 「重复」括注的锚点

extension CountdownRule {
    /// 「每月（…）」里的括注：农历规则给农历日名（`初一`），公历给 `3 日`。
    func monthlyAnchorLabel(calendar: Calendar) -> String? {
        switch self {
        case .lunarYearly(_, let day), .lunarOnce(_, let day, _):
            return CountdownLunar.dayName(day)
        case .solarYearly(_, let day), .birthday(_, let day, _):
            return "\(day) 日"
        case .monthly(let day, let lunar, _):
            return lunar ? CountdownLunar.dayName(day) : "\(day) 日"
        case .once(let date):
            return calendar.dateComponents([.day], from: date).day.map { "\($0) 日" }
        case .daily(_, let anchor), .weekly(_, _, let anchor), .interval(_, _, let anchor):
            return calendar.dateComponents([.day], from: anchor).day.map { "\($0) 日" }
        case .lunarEve:
            return nil
        }
    }

    /// 「每年（…）」里的括注：农历规则给 `正月初一`，公历给 `10 月 3 日`。
    func yearlyAnchorLabel(calendar: Calendar) -> String? {
        switch self {
        case .lunarYearly(let month, let day), .lunarOnce(let month, let day, _):
            return CountdownLunar.label(month: month, day: day)
        case .lunarEve:
            return "除夕"
        case .solarYearly(let month, let day), .birthday(let month, let day, _):
            return "\(month) 月 \(day) 日"
        case .monthly(let day, let lunar, _):
            return lunar ? CountdownLunar.dayName(day) : "\(day) 日"
        case .once(let date):
            let parts = calendar.dateComponents([.month, .day], from: date)
            guard let month = parts.month, let day = parts.day else { return nil }
            return "\(month) 月 \(day) 日"
        case .daily(_, let anchor), .weekly(_, _, let anchor), .interval(_, _, let anchor):
            let parts = calendar.dateComponents([.month, .day], from: anchor)
            guard let month = parts.month, let day = parts.day else { return nil }
            return "\(month) 月 \(day) 日"
        }
    }
}

// MARK: - 调色板 / 符号白名单

extension CountdownEvent {
    /// 符号白名单（「样式」页按此顺序展示）。
    static let symbolOptions = [
        "heart", "gift", "hourglass", "flag", "star", "bell",
        "party.popper", "birthday.cake", "airplane", "graduationcap",
        "cross.case", "house",
    ]

    /// 固定色板数量；具体颜色映射在界面侧（Domain 不依赖 SwiftUI），需与
    /// `CountdownWorkspaceView.swift` 中的 `countdownPalette` 保持一致。
    static let paletteSize = 6

    /// 参考图里新建时的默认提醒：`当天, 提前 3 天`（**两条**，所以「提醒」是多选）。
    static let defaultReminderOffsets = [0, 3 * 24 * 60]

    /// 一天多少分钟。提醒按整天存。
    static let minutesPerDay = 24 * 60

    /// 「提醒」下拉里的预设项（分钟）。顺序照参考图：
    /// 当天 / 提前 1 天 / 提前 2 天 / 提前 3 天 / 提前 1 周。
    /// 下拉最上面还有一项「无」（= 空集），最下面隔一条分隔线是「自定义」，
    /// 这两项由界面拼，不在这个数组里。
    static let reminderChoices = [0, 1 * minutesPerDay, 2 * minutesPerDay,
                                 3 * minutesPerDay, 7 * minutesPerDay]

    /// 参考图里每个提醒选项后面都挂着同一个时刻（`当天 (09:00)`）。
    ///
    /// 说明：这一行的语义是**多选**（见 `defaultReminderOffsets`），而参考图下拉里
    /// 每一项都是 09:00，所以这里把 09:00 当作固定提醒时刻显示。
    /// 目前**没有**「每条提醒各带一个时刻」的字段——见交底里的未做项。
    static let reminderTimeText = "09:00"

    /// 「提醒」行里的文案（不带时刻）：`当天` / `提前 1 天` / `提前 1 周`。
    static func reminderLabel(_ minutes: Int) -> String {
        guard minutes > 0 else { return "当天" }
        let days = minutes / minutesPerDay
        // 整周的写成「周」，与参考图的「提前 1 周」一致。
        if days % 7 == 0 { return "提前 \(days / 7) 周" }
        return "提前 \(days) 天"
    }

    /// 下拉里的文案：参考图每个选项后面都挂着提醒时刻。
    static func reminderOptionLabel(_ minutes: Int) -> String {
        "\(reminderLabel(minutes)) (\(reminderTimeText))"
    }

    /// 提醒文案：`当天, 提前 3 天`；空集返回 nil（调用方显示占位）。
    static func reminderText(_ offsets: [Int]) -> String? {
        let sorted = normalizedReminderOffsets(offsets)
        guard !sorted.isEmpty else { return nil }
        return sorted.map(reminderLabel).joined(separator: ", ")
    }

    /// 归一化提醒集合：去重升序，丢掉不是整天的值。
    ///
    /// 这里**不再按 `reminderChoices` 名单过滤**：名单是可选项，而存量数据里可能
    /// 有名单外的整天值（比如旧的「提前 30 天」），按名单过滤会把它静默吃掉。
    static func normalizedReminderOffsets(_ offsets: [Int]) -> [Int] {
        let maxMinutes = 3650 * minutesPerDay
        return Array(Set(offsets.filter {
            $0 >= 0 && $0 % minutesPerDay == 0 && $0 <= maxMinutes
        })).sorted()
    }

    /// 公历日期文案 `yyyy/M/d`（参考图的 2026/10/3、2027/2/6 都不补零）。
    static func solarText(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)/\(parts.month ?? 0)/\(parts.day ?? 0)"
    }
}

// MARK: - 农历文案

/// 农历月/日的中文写法。`CountdownRule` 的日期文案与卡片副标题都从这里取，
/// 保证「正月初一」这类标签是**由实际日期算出来的**，而不是另存一份字符串。
enum CountdownLunar {
    private static let monthNames = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月",
    ]

    static func monthName(_ month: Int) -> String {
        guard (1...12).contains(month) else { return "\(month)月" }
        return monthNames[month - 1]
    }

    static func dayName(_ day: Int) -> String {
        // `digits` 只有 0…9 十个元素（下标 0 是空串）。「初十」不能写成
        // `"初" + digits[10]`——那是越界，会直接 SIGTRAP 崩掉。日期浮层里
        // 「日」下拉会把 1…30 逐个取名字，这条路径第一次被枚举到就炸了。
        let digits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        switch day {
        case 1...9: return "初" + digits[day]
        case 10: return "初十"
        case 11...19: return "十" + digits[day - 10]
        case 20: return "二十"
        case 21...29: return "廿" + digits[day - 20]
        case 30: return "三十"
        default: return "\(day)"
        }
    }

    /// `正月初一`。
    static func label(month: Int, day: Int) -> String {
        monthName(month) + dayName(day)
    }

    /// 共享一份 `Calendar(identifier: .chinese)`：打开它会分配 ICU 数据，
    /// 每次新建代价不小；农历日界跟随传入日历的时区。
    /// （与 `LunarCalendarService` 同样的缓存策略，这里给 Domain 用一份。）
    private static let lock = NSLock()
    private static var cached: (timeZoneID: String, calendar: Calendar)?

    static func chineseCalendar(timeZone: TimeZone) -> Calendar {
        lock.lock()
        defer { lock.unlock() }
        if let cached, cached.timeZoneID == timeZone.identifier { return cached.calendar }
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = timeZone
        cached = (timeZone.identifier, calendar)
        return calendar
    }

    /// 某公历日期对应的农历月/日；闰月返回 nil（节日不落在闰月）。
    static func lunarComponents(of date: Date, calendar: Calendar) -> (month: Int, day: Int)? {
        let chinese = chineseCalendar(timeZone: calendar.timeZone)
        let parts = chinese.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day, parts.isLeapMonth != true else { return nil }
        return (month, day)
    }
}

// MARK: - 卡片主数字的显示单位

/// 卡片中间那个大数字的单位。参考实现里点卡片在三种之间轮换：
/// `128` → `4月9天` → `18周2天`。**每张卡各记各的**（点一张只改那一张）。
enum CountdownDisplayUnit: String, Codable, CaseIterable, Identifiable {
    case day, month, week

    var id: String { rawValue }

    /// 点一下卡片轮到的下一个单位。顺序照参考图：天 → 月 → 周 → 天。
    var next: CountdownDisplayUnit {
        switch self {
        case .day: return .month
        case .month: return .week
        case .week: return .day
        }
    }
}

/// 卡片主数字的分段。数字与单位分开存，界面才能把数字放大、单位缩小
/// （参考图「4月9天」里 4 / 9 大，月 / 天 小）。
struct CountdownMagnitude: Equatable {
    struct Part: Equatable {
        let value: Int
        /// 空串 = 只有数字：按天那一档，以及不足一个更大单位时。
        let unit: String
    }

    let parts: [Part]

    /// `128` / `4月9天` / `18周2天`。无障碍标签与测试用。
    var text: String { parts.map { "\($0.value)\($0.unit)" }.joined() }

    /// 读屏用。按天那一档画面上只有光秃秃的数字（参考图就是 `128`），
    /// 念出来得补一个「天」，否则是个没有单位的数。
    var spokenText: String {
        if parts.count == 1, parts[0].unit.isEmpty { return "\(parts[0].value) 天" }
        return text
    }
}

// MARK: - 发生日与倒数投影

/// 一条记录在当前时刻的展示数据：天数、方向与副标题。纯值类型，便于测试。
struct CountdownProjection: Equatable {
    /// 天数差（绝对值）。未来的「还有 N 天」，过去的「已经 N 天」。
    let days: Int
    /// true = 还没到（还有），false = 已过去（已经）。
    let isFuture: Bool
    /// 用于计算的落点日期（当天零点）。
    let occurrence: Date
    /// 副标题的**前缀**：`距离 正月初一（2027/2/6）还有` / `距离 2026/8/8 已经`。
    ///
    /// 故意叫 `Prefix` 而不是 `caption`：它**不是一句完整的话**，句尾缺天数。
    /// 卡片把天数单独放大显示在它上面（见 `CountdownCardView.magnitudeRow`），
    /// 两者靠视觉拼起来才读得通——所以只有卡片能用它。
    ///
    /// **凡是只给一句话的地方（tooltip、已归档列表行），用 `sentence(with:)`。**
    /// 这两个落点当初就是直接拿了 `caption`，屏幕上出现「距离 2026/10/2 还有」
    /// 这种断在半句的文案；旧名字的注释里其实写了「这是前缀」，照样被误用两次，
    /// 所以改成把前缀写进名字里。
    let captionPrefix: String
}

extension CountdownProjection {
    /// 副标题的**完整句**：`距离 正月初一（2027/2/6）还有 4月9天`。
    ///
    /// 这是「只给一句话」的场合唯一该用的出口。前缀 + 天数拼在一起的活儿只此一处，
    /// 免得又有人自己拼一遍、拼漏了单位或空格。
    ///
    /// 用 `spokenText` 而不是 `text`：按天那一档画面上只有光秃秃的 `348`
    /// （参考图就是如此），但**读成一句话**要补上「天」，否则「还有 348」不成句。
    func sentence(with magnitude: CountdownMagnitude) -> String {
        "\(captionPrefix) \(magnitude.spokenText)"
    }
}

extension CountdownEvent {
    /// 下一次（或唯一一次）发生的日期，取当天零点。重复规则永远给未来落点，
    /// 单次规则原样返回（可能在过去，于是显示「已经」）。
    func occurrence(onOrAfter today: Date, calendar: Calendar = .current) -> Date {
        Self.occurrence(of: rule, onOrAfter: today, calendar: calendar)
    }

    /// 规则 → 下一次落点。实例方法与编辑器（还没有记录、只有一个待定规则时）共用，
    /// 免得两处各算一套。
    static func occurrence(of rule: CountdownRule, onOrAfter today: Date,
                           calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: today)
        switch rule {
        case .once(let date):
            return calendar.startOfDay(for: date)
        case .solarYearly(let month, let day):
            return Self.nextSolarYearly(month: month, day: day, onOrAfter: start, calendar: calendar)
        case .lunarYearly(let month, let day):
            return Self.nextLunar(month: month, day: day, onOrAfter: start, calendar: calendar)
        case .lunarOnce(let month, let day, let year):
            // 一次性：落点就是那一天本身，哪怕已经过去——与 `.once` 同一口径，
            // 卡片据此显示「已经 N 天」。
            return Self.lunarDate(year: year, month: month, day: day, calendar: calendar) ?? start
        case .lunarEve:
            let newYear = Self.nextLunar(month: 1, day: 1, onOrAfter: start, calendar: calendar)
            return calendar.date(byAdding: .day, value: -1, to: newYear) ?? newYear
        case .birthday(let month, let day, _):
            // 生日每年都过：落点永远是下一个生日，而不是出生那天。
            return Self.nextSolarYearly(month: month, day: day, onOrAfter: start, calendar: calendar)
        case .daily:
            // 每天都有一次，落点就是今天（0 天）。
            return start
        case .weekly(let weekday, _, _):
            return Self.nextWeekday(weekday, onOrAfter: start, calendar: calendar)
        case .monthly(let day, let lunar, _):
            return lunar
                ? Self.nextLunar(month: nil, day: day, onOrAfter: start, calendar: calendar)
                : Self.nextDayOfMonth(day, onOrAfter: start, calendar: calendar)
        case .interval(let days, _, let anchor):
            return Self.nextInterval(days: days, anchor: anchor, onOrAfter: start, calendar: calendar)
        }
    }

    /// 当前展示投影。
    func projection(asOf today: Date, calendar: Calendar = .current) -> CountdownProjection {
        let start = calendar.startOfDay(for: today)
        let occurrence = occurrence(onOrAfter: start, calendar: calendar)
        let delta = calendar.dateComponents([.day], from: start, to: occurrence).day ?? 0
        let isFuture = delta >= 0
        return CountdownProjection(
            days: abs(delta),
            isFuture: isFuture,
            occurrence: occurrence,
            captionPrefix: caption(occurrence: occurrence, isFuture: isFuture, calendar: calendar))
    }

    /// 卡片主数字，按 `unit` 分解。
    ///
    /// - 天：原样。
    /// - 周：固定 7 天一周，纯除法（128 天 → 18 周 2 天）。
    /// - 月：**按事件自己的历法**取自然月——农历事件用农历月，公历事件用公历月。
    ///   参考图实测：2026-10-01 → 正月初一（2027/2/6）共 128 天，显示「4月9天」；
    ///   同区间的农历月差正是 4 个月 9 天，而公历月差是 4 个月 5 天——对不上。
    func magnitude(asOf today: Date, unit: CountdownDisplayUnit,
                   calendar: Calendar = .current) -> CountdownMagnitude {
        let start = calendar.startOfDay(for: today)
        let projection = projection(asOf: start, calendar: calendar)
        let days = projection.days

        switch unit {
        case .day:
            return CountdownMagnitude(parts: [.init(value: days, unit: "")])

        case .week:
            let weeks = days / 7
            guard weeks > 0 else {
                return CountdownMagnitude(parts: [.init(value: days, unit: "")])
            }
            return CountdownMagnitude(parts: [
                .init(value: weeks, unit: "周"),
                .init(value: days % 7, unit: "天"),
            ])

        case .month:
            let monthCalendar = usesLunarCalendar
                ? CountdownLunar.chineseCalendar(timeZone: calendar.timeZone)
                : calendar
            // 已过去的记录落点早于今天，两个方向都要能算，所以按时间先后取。
            let earlier = min(start, projection.occurrence)
            let later = max(start, projection.occurrence)
            let parts = monthCalendar.dateComponents([.month, .day], from: earlier, to: later)
            let months = parts.month ?? 0
            guard months > 0 else {
                return CountdownMagnitude(parts: [.init(value: days, unit: "")])
            }
            return CountdownMagnitude(parts: [
                .init(value: months, unit: "月"),
                .init(value: parts.day ?? 0, unit: "天"),
            ])
        }
    }

    /// 副标题。农历节日在公历日期前补一段农历名（参考图：
    /// `距离 正月初一（2027/2/6）还有`），其余只有公历日期。
    private func caption(occurrence: Date, isFuture: Bool, calendar: Calendar) -> String {
        let solar = Self.solarText(occurrence, calendar: calendar)
        let tail = isFuture ? "还有" : "已经"
        guard usesLunarCalendar,
              let parts = CountdownLunar.lunarComponents(of: occurrence, calendar: calendar) else {
            return "距离 \(solar) \(tail)"
        }
        return "距离 \(CountdownLunar.label(month: parts.month, day: parts.day))（\(solar)）\(tail)"
    }

    /// 生日「显示岁数」：按周岁算（今年生日还没到就减一）。非生日、未开启
    /// 开关、或规则里没有出生年时返回 nil。
    func ageText(asOf today: Date, calendar: Calendar = .current) -> String? {
        guard kind == .birthday, showsAge else { return nil }
        let birth: (year: Int, month: Int, day: Int)
        switch rule {
        case .birthday(let month, let day, let year):
            birth = (year, month, day)
        case .once(let date):
            // 「重复 = 无」的生日：日期本身就是出生日。
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
            birth = (year, month, day)
        default:
            return nil
        }
        let todayStart = calendar.startOfDay(for: today)
        let currentYear = calendar.component(.year, from: todayStart)
        var age = currentYear - birth.year
        if let thisYearsBirthday = calendar.date(
            from: DateComponents(year: currentYear, month: birth.month, day: birth.day)),
           todayStart < calendar.startOfDay(for: thisYearsBirthday) {
            age -= 1
        }
        return age >= 0 ? "\(age) 岁" : nil
    }
}

// MARK: - 日期搜索（纯函数，Calendar 注入）

extension CountdownEvent {
    /// 下一个不早于 `start` 的公历月/日。2/29 在平年由 ICU 规范化到 3/1。
    static func nextSolarYearly(month: Int, day: Int, onOrAfter start: Date, calendar: Calendar) -> Date {
        let year = calendar.component(.year, from: start)
        for offset in 0...3 {
            guard let candidate = calendar.date(
                from: DateComponents(year: year + offset, month: month, day: day)) else { continue }
            let normalized = calendar.startOfDay(for: candidate)
            if normalized >= start { return normalized }
        }
        return start
    }

    /// 农历 `year` 年 `month` 月 `day` 日对应的公历日期；那一天不存在（如腊月三十
    /// 落在只有廿九的年份）时返回 nil。
    ///
    /// 从**公历** `year` 年 1 月 1 日起向上扫，取第一个月/日匹配的日子：农历年
    /// `year` 横跨公历 `year` 年 1 月到 `year+1` 年 2 月，所以第一个匹配就是它。
    ///
    /// 不能直接拿 `Calendar(identifier: .chinese)` 的 `.year` 组件去构造——那是
    /// 60 年一轮的干支年号，不是公历年，`DateComponents(year: 2027, …)` 落不到 2027。
    static func lunarDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard let first = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else {
            return nil
        }
        var cursor = calendar.startOfDay(for: first)
        for _ in 0...800 {
            if let parts = CountdownLunar.lunarComponents(of: cursor, calendar: calendar),
               parts.month == month, parts.day == day {
                return cursor
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = next
        }
        return nil
    }

    /// 下一个不早于 `start` 的农历月/日（闰月跳过）。`month` 传 nil 表示只看日
    /// （「每月（初一）」用）。一年最多 384 天，向上扫 800 天足够跨过一个完整农历年；
    /// 扫不到时退回 `start`（宁可显示 0 天，也不给出一个凭空的日期）。
    static func nextLunar(month: Int?, day: Int, onOrAfter start: Date, calendar: Calendar,
                          searchLimit: Int = 800) -> Date {
        var cursor = calendar.startOfDay(for: start)
        for _ in 0...searchLimit {
            if let parts = CountdownLunar.lunarComponents(of: cursor, calendar: calendar),
               parts.day == day, month == nil || parts.month == month {
                return cursor
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return calendar.startOfDay(for: start)
    }

    /// 下一个不早于 `start`、星期为 `weekday` 的日期（`Calendar` 的 1=周日…7=周六）。
    /// 今天正好是那一天就返回今天。
    static func nextWeekday(_ weekday: Int, onOrAfter start: Date, calendar: Calendar) -> Date {
        let current = calendar.component(.weekday, from: start)
        let delta = ((weekday - current) % 7 + 7) % 7
        return calendar.date(byAdding: .day, value: delta, to: start) ?? start
    }

    /// 下一个不早于 `start`、公历日为 `day` 的日期。当月没有这一天（比如 31 号）
    /// 就跳过，最多扫 430 天（够跨过任意一个 31 天缺失的月份）。
    static func nextDayOfMonth(_ day: Int, onOrAfter start: Date, calendar: Calendar) -> Date {
        var cursor = calendar.startOfDay(for: start)
        for _ in 0...430 {
            if calendar.component(.day, from: cursor) == day { return cursor }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return calendar.startOfDay(for: start)
    }

    /// 每 `days` 天一次：从 `anchor` 起按整数倍前进，取第一个不早于 `start` 的落点。
    static func nextInterval(days: Int, anchor: Date, onOrAfter start: Date,
                             calendar: Calendar) -> Date {
        let step = max(days, 1)
        let base = calendar.startOfDay(for: anchor)
        guard base < start else { return base }
        let elapsed = calendar.dateComponents([.day], from: base, to: start).day ?? 0
        let jumps = (elapsed + step - 1) / step
        return calendar.date(byAdding: .day, value: jumps * step, to: base) ?? start
    }
}

// MARK: - 节日目录

/// 「节日」类型的日期选项。与 `LunarCalendarService` 的节日表保持同一份口径
/// （农历那几张表按农历月/日走，公历那几个按公历月/日走）。
enum CountdownFestival {
    struct Option: Identifiable, Equatable {
        let name: String
        let rule: CountdownRule
        var id: String { name }
    }

    static let all: [Option] = [
        Option(name: "春节", rule: .lunarYearly(month: 1, day: 1)),
        Option(name: "元宵节", rule: .lunarYearly(month: 1, day: 15)),
        Option(name: "龙抬头", rule: .lunarYearly(month: 2, day: 2)),
        Option(name: "端午节", rule: .lunarYearly(month: 5, day: 5)),
        Option(name: "七夕", rule: .lunarYearly(month: 7, day: 7)),
        Option(name: "中元节", rule: .lunarYearly(month: 7, day: 15)),
        Option(name: "中秋节", rule: .lunarYearly(month: 8, day: 15)),
        Option(name: "重阳节", rule: .lunarYearly(month: 9, day: 9)),
        Option(name: "腊八节", rule: .lunarYearly(month: 12, day: 8)),
        Option(name: "除夕", rule: .lunarEve),
        Option(name: "元旦", rule: .solarYearly(month: 1, day: 1)),
        Option(name: "情人节", rule: .solarYearly(month: 2, day: 14)),
        Option(name: "妇女节", rule: .solarYearly(month: 3, day: 8)),
        Option(name: "植树节", rule: .solarYearly(month: 3, day: 12)),
        Option(name: "劳动节", rule: .solarYearly(month: 5, day: 1)),
        Option(name: "儿童节", rule: .solarYearly(month: 6, day: 1)),
        Option(name: "教师节", rule: .solarYearly(month: 9, day: 10)),
        Option(name: "国庆节", rule: .solarYearly(month: 10, day: 1)),
        Option(name: "圣诞节", rule: .solarYearly(month: 12, day: 25)),
    ]

    /// 与某条规则对应的节日名；自定义日期返回 nil。
    static func name(for rule: CountdownRule) -> String? {
        all.first { $0.rule == rule }?.name
    }
}
