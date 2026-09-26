import Foundation

/// Where a templated task lands on the calendar. Offsets are resolved against
/// the day the template is applied, never stored as absolute dates.
enum TaskTemplateScheduleOffset: String, Codable, Equatable, CaseIterable {
    case none, today, tomorrow, nextMonday

    var title: String {
        switch self {
        case .none: "无日期"
        case .today: "今天"
        case .tomorrow: "明天"
        case .nextMonday: "下周一"
        }
    }

    /// Resolves the offset to an all-day date relative to `day`; nil for .none.
    func date(from day: Date, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: day)
        switch self {
        case .none: return nil
        case .today: return start
        case .tomorrow: return calendar.date(byAdding: .day, value: 1, to: start)
        case .nextMonday:
            // Gregorian weekday numbers: 1 = Sunday, 2 = Monday.
            let weekday = calendar.component(.weekday, from: start)
            let daysAhead = (2 - weekday + 6) % 7 + 1
            return calendar.date(byAdding: .day, value: daysAhead, to: start)
        }
    }

    /// Reverse mapping used when saving a task as a template. Only the day
    /// offsets the model can represent are kept; any other date (including
    /// past days) drops to nil so applying the template leaves it unscheduled.
    static func match(_ date: Date?, against day: Date,
                      calendar: Calendar) -> TaskTemplateScheduleOffset? {
        guard let date else { return nil }
        let start = calendar.startOfDay(for: day)
        let target = calendar.startOfDay(for: date)
        guard let days = calendar.dateComponents([.day], from: start, to: target).day,
              days >= 0 else { return nil }
        if days >= 1, calendar.component(.weekday, from: target) == 2 { return .nextMonday }
        if days == 1 { return .tomorrow }
        if days == 0 { return .today }
        return nil
    }
}

/// A reusable task blueprint: everything needed to spawn a task plus its child
/// title sequence. `listName == nil` means the inbox, `priority == nil` means
/// the default (无) priority, and `schedule == nil` leaves the task unscheduled.
struct TaskTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var title: String
    var document: NativeDocument
    var tags: [String]
    var listName: String?
    var priority: TaskPriority?
    var schedule: TaskTemplateScheduleOffset?
    var childTitles: [String]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, title: String,
         document: NativeDocument = .empty, tags: [String] = [],
         listName: String? = nil, priority: TaskPriority? = nil,
         schedule: TaskTemplateScheduleOffset? = nil,
         childTitles: [String] = [], createdAt: Date) {
        self.id = id
        self.name = name
        self.title = title
        self.document = document
        self.tags = tags
        self.listName = listName
        self.priority = priority
        self.schedule = schedule
        self.childTitles = childTitles
        self.createdAt = createdAt
    }
}

// Templates live in their own archive file and must survive additive model
// changes, so every aspect except the name decodes to its neutral default.
extension TaskTemplate {
    private enum CodingKeys: String, CodingKey {
        case id, name, title, document, tags, listName, priority, schedule, childTitles, createdAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        document = try values.decodeIfPresent(NativeDocument.self, forKey: .document) ?? .empty
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        listName = try values.decodeIfPresent(String.self, forKey: .listName)
        priority = try values.decodeIfPresent(TaskPriority.self, forKey: .priority)
        schedule = try values.decodeIfPresent(TaskTemplateScheduleOffset.self, forKey: .schedule)
        childTitles = try values.decodeIfPresent([String].self, forKey: .childTitles) ?? []
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(title, forKey: .title)
        try values.encode(document, forKey: .document)
        try values.encode(tags, forKey: .tags)
        try values.encodeIfPresent(listName, forKey: .listName)
        try values.encodeIfPresent(priority, forKey: .priority)
        try values.encodeIfPresent(schedule, forKey: .schedule)
        try values.encode(childTitles, forKey: .childTitles)
        try values.encode(createdAt, forKey: .createdAt)
    }
}
