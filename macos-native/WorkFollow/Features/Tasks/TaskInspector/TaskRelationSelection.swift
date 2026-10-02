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
        let previousNoteID = source.sourceNoteID
        if case .task = current {
            let commit: (NativeDocument) -> Void = { [weak workspace] document in
                _ = workspace?.setDocument(sourceTaskID, document)
            }
            return handle.insertReference(current.reference, commit: commit, undoCommit: commit)
        }
        guard case let .note(note) = current else { return false }
        let nextNoteID = note.id
        return handle.insertReference(current.reference,
            commit: { [weak workspace] document in
                _ = workspace?.commitEditorReference(sourceTaskID, document: document, sourceNoteID: nextNoteID)
            }, undoCommit: { [weak workspace] document in
                _ = workspace?.commitEditorReference(sourceTaskID, document: document, sourceNoteID: previousNoteID)
            })
    }
}
