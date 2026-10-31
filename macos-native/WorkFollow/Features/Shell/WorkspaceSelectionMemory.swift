import Combine
import Foundation

/// Page hosts already retain their scroll views. Keep the list context
/// (active list, tag, filter) belonging to each task destination, so returning
/// restores the same view — but not the selected task/note: switching scopes
/// closes the detail pane, which both matches TickTick and avoids rebuilding
/// the inspector on every return.
@MainActor
final class WorkspaceSelectionMemory: ObservableObject {
    private struct TaskContext {
        var list: String?
        var tag: String?
        var filter: UUID?
    }
    private var tasks: [NativeDestination: TaskContext] = [:]
    private var subscriptions: Set<AnyCancellable> = []

    func connect(workspace: TaskWorkspaceModel, notes noteWorkspace: NotesWorkspaceModel,
                 navigation: AppNavigation) {
        guard subscriptions.isEmpty else { return }
        navigation.$destination.dropFirst().sink { [weak self, weak navigation, weak workspace, weak noteWorkspace] destination in
            guard let self, let navigation, let workspace, let noteWorkspace,
                  destination != navigation.destination else { return }
            let old = navigation.destination
            // Links carry an explicit target and select it after navigating;
            // don't clear what they are about to open.
            guard navigation.taskSelectionToPreserveOnNextNavigation == nil else { return }
            if TaskWorkspaceModel.scope(for: old) != nil {
                self.tasks[old] = TaskContext(list: workspace.activeList, tag: workspace.activeTag,
                                              filter: workspace.activeFilterID)
            }
            let saved = self.tasks[destination]
            workspace.activeList = saved?.list
            workspace.activeTag = saved?.tag
            workspace.openFilter(saved?.filter)
            workspace.select(nil)
            if destination.isNotes { noteWorkspace.selectedID = nil }
        }.store(in: &subscriptions)
    }
}
