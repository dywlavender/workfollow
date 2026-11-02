import Combine
import Foundation

/// Page hosts already retain their scroll views. Keep the list context
/// (active list, tag, filter) belonging to each task destination, so returning
/// restores the same view — but not the selected task/note: switching scopes
/// closes the detail pane, which both matches TickTick and avoids rebuilding
/// the inspector on every return.
///
/// 清单/标签上下文只属于「所有任务」：它们与今天、明天这些智能清单同级、
/// 一次只能激活一个（用户要求）。离开智能清单时不记录清单上下文，回到
/// 智能清单时也一律清空——否则侧栏会出现两个选中态，快速添加还会把
/// 新任务落进旧清单。过滤条件与智能清单可以叠加，仍按目的地逐页记忆。
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
                if old == .allTasks {
                    self.tasks[old] = TaskContext(list: workspace.activeList, tag: workspace.activeTag,
                                                  filter: workspace.activeFilterID)
                } else {
                    self.tasks[old] = TaskContext(list: nil, tag: nil, filter: workspace.activeFilterID)
                }
            }
            let saved = self.tasks[destination]
            if destination == .allTasks {
                if workspace.activeList != saved?.list { workspace.activeList = saved?.list }
                if workspace.activeTag != saved?.tag { workspace.activeTag = saved?.tag }
            } else {
                if workspace.activeList != nil { workspace.activeList = nil }
                if workspace.activeTag != nil { workspace.activeTag = nil }
            }
            if workspace.activeFilterID != saved?.filter { workspace.openFilter(saved?.filter) }
            workspace.select(nil)
            if destination.isNotes, noteWorkspace.selectedID != nil { noteWorkspace.selectedID = nil }
        }.store(in: &subscriptions)
    }
}
