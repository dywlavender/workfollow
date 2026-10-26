import AppKit

/// Compatibility entry for the task inspector's top window button. Window
/// ownership and document identity belong to the common floating editor.
@MainActor
final class TaskDetailWindowController {
    static let shared = TaskDetailWindowController()
    private var taskID: UUID?

    var window: NSWindow? {
        guard let taskID else { return nil }
        return FloatingEditorWindowController.shared.panel(for: .task(taskID))
    }
    var isShowing: Bool { window?.isVisible == true }

    func show(workspace: TaskWorkspaceModel, environment: AppEnvironment) {
        guard let id = workspace.selectedTask?.id else { return }
        if workspace === environment.taskWorkspace {
            StickyNoteWindowController.shared.attach(environment: environment)
        } else {
            StickyNoteWindowController.shared.attach(workspace: workspace)
        }
        taskID = id
        StickyNoteWindowController.shared.open(taskID: id)
    }
}
