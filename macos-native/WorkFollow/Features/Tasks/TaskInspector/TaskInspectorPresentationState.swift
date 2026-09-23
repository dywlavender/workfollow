import Foundation

enum InspectorEditingTarget: Equatable {
    case none
    case title
    case body
}

enum InspectorPopover: Equatable {
    case schedule
    case deadline
}

enum InspectorEscapeEffect: Equatable {
    case dismissPopover
    case endEditing
    case returnToList
    case keepInspector
}

/// Tracks only transient Inspector presentation state; task values remain in the Domain store.
struct TaskInspectorPresentationState: Equatable {
    var editingTarget: InspectorEditingTarget = .none
    var activePopover: InspectorPopover? = nil
    var titleDraftTaskID: UUID?
    var titleDraft = ""

    mutating func synchronizeTitle(taskID: UUID?, title: String) {
        guard titleDraftTaskID != taskID else { return }
        titleDraftTaskID = taskID
        titleDraft = title
    }

    mutating func handleEscape(isNarrow: Bool) -> InspectorEscapeEffect {
        if activePopover != nil {
            activePopover = nil
            return .dismissPopover
        }
        if editingTarget != .none {
            editingTarget = .none
            return .endEditing
        }
        return isNarrow ? .returnToList : .keepInspector
    }
}
