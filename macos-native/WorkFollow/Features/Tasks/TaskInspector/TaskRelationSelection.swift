import Foundation

@MainActor
enum TaskRelationSelection {
    /// This is a document reference, not a parent command or a new relation graph.
    static func apply(_ target: TaskRelationTarget, sourceTaskID: UUID,
                      workspace: TaskWorkspaceModel, notes: [Note], handle: DocumentEditorHandle) -> Bool {
        guard workspace.selectedTaskID == sourceTaskID,
              let source = workspace.task(for: sourceTaskID), source.deletedAt == nil,
              !source.isConverted, source.skippedAt == nil,
              handle.textView?.documentIdentity == sourceTaskID,
              let current = TaskRelationProjection.targets(sourceTaskID: sourceTaskID,
                  tasks: workspace.allTasks, notes: notes, query: "").first(where: { $0.id == target.id }) else { return false }
        if case let .note(note) = current {
            workspace.setSourceNote(sourceTaskID, note.id)
        }
        handle.insertReference(current.reference)
        return true
    }
}
