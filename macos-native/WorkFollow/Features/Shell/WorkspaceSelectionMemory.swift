import Combine
import Foundation

/// Page hosts already retain their scroll views. Keep the selection and filter
/// belonging to each page, so returning restores the same reading context.
@MainActor
final class WorkspaceSelectionMemory: ObservableObject {
    private struct TaskContext {
        var selected: UUID?
        var list: String?
        var tag: String?
        var filter: UUID?
    }
    private var tasks: [NativeDestination: TaskContext] = [:]
    private var notes: [NativeDestination: UUID] = [:]
    private var subscriptions: Set<AnyCancellable> = []
    private var restoring = false

    func connect(workspace: TaskWorkspaceModel, notes noteWorkspace: NotesWorkspaceModel,
                 navigation: AppNavigation) {
        guard subscriptions.isEmpty else { return }
        workspace.$selectedTaskID.sink { [weak self, weak navigation, weak workspace] id in
            guard let self, let navigation, let workspace, !self.restoring,
                  navigation.taskSelectionToPreserveOnNextNavigation == nil,
                  TaskWorkspaceModel.scope(for: navigation.destination) != nil else { return }
            self.tasks[navigation.destination] = TaskContext(selected: id, list: workspace.activeList, tag: workspace.activeTag, filter: workspace.activeFilterID)
        }.store(in: &subscriptions)
        navigation.$destination.dropFirst().sink { [weak self, weak navigation, weak workspace, weak noteWorkspace] destination in
            guard let self, let navigation, let workspace, let noteWorkspace,
                  destination != navigation.destination else { return }
            let old = navigation.destination
            self.restoring = true
            defer { self.restoring = false }
            if old.isNotes, let id = noteWorkspace.selectedID { self.notes[old] = id }
            // Links carry an explicit target; the outgoing selection was already
            // remembered before the link selected that target.
            guard navigation.taskSelectionToPreserveOnNextNavigation == nil else { return }
            if TaskWorkspaceModel.scope(for: old) != nil {
                self.tasks[old] = TaskContext(selected: workspace.selectedTaskID, list: workspace.activeList, tag: workspace.activeTag, filter: workspace.activeFilterID)
            }
            let saved = self.tasks[destination]
            workspace.activeList = saved?.list
            workspace.activeTag = saved?.tag
            workspace.openFilter(saved?.filter)
            if destination.isNotes {
                workspace.select(nil)
                if let id = self.notes[destination],
                   noteWorkspace.rows(trash: destination == .notesTrash, query: "",
                       folder: noteWorkspace.folderFilter, favorites: noteWorkspace.favoritesOnly).contains(where: { $0.id == id }) {
                    noteWorkspace.selectedID = id
                } else if let note = noteWorkspace.selected,
                          (note.deletedAt != nil) != (destination == .notesTrash) {
                    noteWorkspace.selectedID = nil
                }
            } else if let id = saved?.selected, let task = workspace.task(for: id),
                      task.deletedAt == nil, !task.isConverted {
                if let scope = TaskWorkspaceModel.scope(for: destination),
                   !workspace.groups(for: scope, query: TaskListQuery(list: saved?.list, tag: saved?.tag))
                    .flatMap(\.tasks).contains(where: { $0.id == id || $0.id == task.parentID }) {
                    workspace.select(nil)
                } else { workspace.select(id) }
            } else { workspace.select(nil) }
        }.store(in: &subscriptions)
    }
}
