import Foundation

/// Describes the task-level differences in one committed workspace snapshot.
struct TaskChangeSet: Equatable {
    enum Operation: Equatable {
        case insert
        case update
        case delete
    }

    enum Field: Hashable {
        case title
        case document
        case tags
        case recurrence
        case recurrenceRule
        case reminderAt
        case reminderOffsets
        case attachments
        case list
        case priority
        case schedule
        case status
        case parentID
        case childOrder
        case createdAt
        case updatedAt
        case completedAt
        case deletedAt
        case isPinned
        case abandonedAt
        case isAbandoned
        case skippedAt
        case convertedNoteID
        case sourceNoteID
        case sectionID
        case focusEstimate
        case occurrence
        case weeklyPlanning
    }

    struct Entry: Equatable {
        let operation: Operation
        let before: Task?
        let after: Task?
        let changedFields: Set<Field>

        var taskID: UUID { (after ?? before)!.id }
    }

    let entries: [Entry]
    let order: [UUID]?

    /// These fields can change reminder content, fire dates, or eligibility.
    /// Inserts and deletes also require a reminder reconciliation.
    var affectsReminders: Bool {
        let reminderFields: Set<Field> = [
            .title, .list, .schedule, .recurrence, .recurrenceRule,
            .reminderAt, .reminderOffsets, .status, .isAbandoned,
            .deletedAt, .skippedAt, .convertedNoteID
        ]
        return entries.contains { entry in
            switch entry.operation {
            case .insert, .delete:
                true
            case .update:
                !entry.changedFields.isDisjoint(with: reminderFields)
            }
        }
    }

    init(before: [Task], after: [Task]) {
        let beforeByID = Dictionary(before.map { ($0.id, $0) },
                                    uniquingKeysWith: { _, latest in latest })
        let afterByID = Dictionary(after.map { ($0.id, $0) },
                                   uniquingKeysWith: { _, latest in latest })
        var entries: [Entry] = []

        for current in after {
            guard let previous = beforeByID[current.id] else {
                entries.append(Entry(operation: .insert, before: nil, after: current,
                                     changedFields: []))
                continue
            }
            guard previous != current else { continue }
            let fields = Self.changedFields(from: previous, to: current)
            if !fields.isEmpty {
                entries.append(Entry(operation: .update, before: previous, after: current,
                                     changedFields: fields))
            }
        }

        for previous in before where afterByID[previous.id] == nil {
            entries.append(Entry(operation: .delete, before: previous, after: nil,
                                 changedFields: []))
        }
        self.entries = entries
        let previousOrder = before.map(\.id)
        let nextOrder = after.map(\.id)
        order = previousOrder == nextOrder ? nil : nextOrder
    }

    /// The command already knows the one task it updated. Reuse the same field
    /// comparison without constructing workspace-wide dictionaries.
    init(updatedFrom before: Task, to after: Task) {
        let fields = Self.changedFields(from: before, to: after)
        entries = fields.isEmpty ? [] : [Entry(operation: .update, before: before,
                                             after: after, changedFields: fields)]
        order = nil
    }

    private static func changedFields(from before: Task, to after: Task) -> Set<Field> {
        var fields = Set<Field>()
        if before.title != after.title { fields.insert(.title) }
        if before.document != after.document { fields.insert(.document) }
        if before.tags != after.tags || before.tagReferences != after.tagReferences { fields.insert(.tags) }
        if before.recurrence != after.recurrence { fields.insert(.recurrence) }
        if before.recurrenceRule != after.recurrenceRule { fields.insert(.recurrenceRule) }
        if before.reminderAt != after.reminderAt { fields.insert(.reminderAt) }
        if before.reminderOffsets != after.reminderOffsets { fields.insert(.reminderOffsets) }
        if before.attachments != after.attachments { fields.insert(.attachments) }
        if before.list != after.list || before.listID != after.listID { fields.insert(.list) }
        if before.priority != after.priority { fields.insert(.priority) }
        if before.schedule != after.schedule { fields.insert(.schedule) }
        if before.status != after.status { fields.insert(.status) }
        if before.parentID != after.parentID { fields.insert(.parentID) }
        if before.childOrder != after.childOrder { fields.insert(.childOrder) }
        if before.createdAt != after.createdAt { fields.insert(.createdAt) }
        if before.updatedAt != after.updatedAt { fields.insert(.updatedAt) }
        if before.completedAt != after.completedAt { fields.insert(.completedAt) }
        if before.deletedAt != after.deletedAt { fields.insert(.deletedAt) }
        if before.isPinned != after.isPinned { fields.insert(.isPinned) }
        if before.abandonedAt != after.abandonedAt { fields.insert(.abandonedAt) }
        if before.isAbandoned != after.isAbandoned { fields.insert(.isAbandoned) }
        if before.skippedAt != after.skippedAt { fields.insert(.skippedAt) }
        if before.convertedNoteID != after.convertedNoteID { fields.insert(.convertedNoteID) }
        if before.sourceNoteID != after.sourceNoteID { fields.insert(.sourceNoteID) }
        if before.sectionID != after.sectionID { fields.insert(.sectionID) }
        if before.focusEstimate != after.focusEstimate { fields.insert(.focusEstimate) }
        if before.weeklyPlanning != after.weeklyPlanning { fields.insert(.weeklyPlanning) }
        if before.series != after.series || before.occurrenceKey != after.occurrenceKey || before.occurrenceOverride != after.occurrenceOverride {
            fields.insert(.occurrence)
        }
        return fields
    }
}
