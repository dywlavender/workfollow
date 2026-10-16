import Foundation

/// The list and global window keep the same input contract. Explicit fields
/// survive text reparsing; only a confirmed capture reaches TaskActions.
struct QuickCaptureSession {
    var text: String
    var description: String = ""
    var selection: NSRange?
    var dismissedTokenIDs: Set<String> = []
    var scheduleOverride: QuickAddScheduleDraft?
    var priorityOverride: TaskPriority?
    var listOverride: String?
    var tagsOverride: [String]?

    func parse(now: Date, calendar: Calendar, knownLists: Set<String>) -> QuickAddParseResult {
        QuickAddParser.parse(text, now: now, calendar: calendar, knownLists: knownLists,
                             dismissedTokenIDs: dismissedTokenIDs)
    }

    func drafts(now: Date, calendar: Calendar, knownLists: Set<String>,
                contextList: String?, contextTag: String?, defaultDueAt: Date?) -> [QuickCaptureDraft] {
        let lines = QuickAddComposition.batchLines(in: text)
        let batch = lines.count > 1
        return lines.compactMap { line in
            let parsed = QuickAddParser.parse(batch ? line : text, now: now, calendar: calendar,
                knownLists: knownLists, dismissedTokenIDs: batch ? [] : dismissedTokenIDs)
            guard !parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let dismissedDate = !batch && QuickAddParser.hasDismissedScheduleToken(
                in: text, now: now, calendar: calendar, knownLists: knownLists,
                dismissedTokenIDs: dismissedTokenIDs)
            let timing = scheduleOverride ?? QuickAddScheduleDraft(parsed: parsed,
                defaultDueAt: dismissedDate ? nil : defaultDueAt)
            var tags = contextTag.map { [$0] } ?? []
            for tag in tagsOverride ?? parsed.tags where !tags.contains(tag) { tags.append(tag) }
            return QuickCaptureDraft(title: parsed.title,
                list: listOverride ?? parsed.listName ?? contextList ?? TaskList.inbox.name,
                plan: SchedulePlan(schedule: timing.schedule, reminder: timing.reminderAt,
                    reminderOffsets: timing.reminderOffsets, frequency: timing.repeatFrequency,
                    recurrenceRule: timing.recurrenceRule),
                priority: priorityOverride ?? parsed.priority, tags: tags,
                document: batch ? .empty : NativeDocument(plainText: description.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }
}

struct QuickCaptureDraft {
    var title: String
    var list: String
    var plan: SchedulePlan
    var priority: TaskPriority
    var tags: [String]
    var document: NativeDocument
}
