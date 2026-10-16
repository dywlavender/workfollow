import Foundation

/// Unsaved conditions shared by the editor's preview and save action.
/// Identity references are resolved by FilterStore when the draft is saved;
/// retaining the original IDs here would preview an old selection after edits.
struct FilterEditorDraft {
    let id: UUID
    var name: String
    var selectedLists: Set<String>
    var selectedTags: Set<String>
    var selectedPriorities: Set<TaskPriority>
    var dateRange: SavedFilterDateRange
    var keywordText: String

    init(initial: SavedFilter?) {
        id = initial?.id ?? UUID()
        name = initial?.name ?? ""
        selectedLists = Set(initial?.listNames ?? [])
        selectedTags = Set(initial?.tags ?? [])
        selectedPriorities = Set(initial?.priorities ?? [])
        dateRange = initial?.dateRange ?? .any
        keywordText = (initial?.keywords ?? []).joined(separator: " ")
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var filter: SavedFilter {
        SavedFilter(id: id, name: trimmedName, listNames: selectedLists.sorted(),
                    tags: selectedTags.sorted(),
                    priorities: TaskPriority.menuOrder.filter { selectedPriorities.contains($0) },
                    dateRange: dateRange, keywords: SavedFilter.parseKeywords(keywordText))
    }

    func listOptions(allListNames: [String]) -> [String] {
        let inbox = TaskList.inbox.name
        let others = Set(allListNames).union(selectedLists).subtracting([inbox]).sorted()
        return [inbox] + others
    }

    func tagOptions(tagNames: [String]) -> [String] {
        Array(Set(tagNames).union(selectedTags)).sorted()
    }
}

/// Counts real unfinished matches without changing the active filter or store.
/// Parent rows retained for navigation by the task list are not extra matches.
struct FilterEditorPreview {
    let matchingCount: Int
    let tasks: [Task]

    static func project(tasks: [Task], filter: SavedFilter,
                        now: Date, calendar: Calendar, limit: Int = 3) -> Self {
        let matching = tasks.filter {
            $0.deletedAt == nil && $0.skippedAt == nil && !$0.isConverted && !$0.isClosed
                && FilterEvaluator.matches($0, filter: filter, now: now, calendar: calendar)
        }
        return Self(matchingCount: matching.count, tasks: Array(matching.prefix(max(0, limit))))
    }
}
