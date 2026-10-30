import AppKit
import Combine

/// Task adapter for the shared native floating editor. There is no plain-text
/// conversion or separate delayed write queue; existing task transactions save edits.
@MainActor
final class StickyNoteWindowController: ObservableObject {
    static let shared = StickyNoteWindowController()
    @Published private(set) var openTaskIDs: [UUID] = []
    private let windows: FloatingEditorWindowController
    private weak var workspace: TaskWorkspaceModel?
    private weak var environment: AppEnvironment?
    private var windowSubscription: AnyCancellable?
    private var revisionSubscription: AnyCancellable?
    private var appearanceSubscription: AnyCancellable?

    init(windows: FloatingEditorWindowController = .shared) {
        self.windows = windows
        windowSubscription = windows.$openIDs.sink { [weak self] ids in
            self?.openTaskIDs = ids.compactMap {
                if case .task(let id) = $0 { return id }
                return nil
            }
        }
    }

    func attach(workspace: TaskWorkspaceModel) {
        guard self.workspace !== workspace else { return }
        closeAll()
        self.workspace = workspace
        environment = nil
        appearanceSubscription = nil
        revisionSubscription = workspace.$revision.dropFirst().sink { [weak self] _ in
            guard let self, let workspace = self.workspace else { return }
            for id in self.openTaskIDs where workspace.task(for: id)?.deletedAt != nil
                || workspace.task(for: id) == nil { self.close(taskID: id) }
        }
    }

    func attach(environment: AppEnvironment) {
        attach(workspace: environment.taskWorkspace)
        self.environment = environment
        appearanceSubscription = environment.$appearance.dropFirst().sink { [weak self] appearance in
            guard let self else { return }
            self.windows.applyAppearance(appearance, to: Set(self.openTaskIDs.map(FloatingEditorID.task)))
        }
    }

    func isOpen(_ taskID: UUID) -> Bool { openTaskIDs.contains(taskID) }

    func open(taskID: UUID) {
        guard let workspace, let task = workspace.task(for: taskID), task.deletedAt == nil else { return }
        windows.open(id: .task(taskID), title: "任务浮窗", appearance: environment?.appearance ?? .system) { handle in
            FloatingTaskView(taskID: taskID, workspace: workspace, environment: environment,
                editorHandle: handle, onClose: { [weak self] in self?.close(taskID: taskID) },
                onOpenInMain: { [weak self] in self?.openInMain(taskID) })
                .environment(\.workfollowBackgroundTheme, environment?.backgroundTheme ?? .none)
                .environment(\.workfollowBackgroundIntensity, environment?.backgroundIntensity ?? .medium)
        }
    }

    func bringToFront(taskID: UUID) { windows.bringToFront(.task(taskID)) }
    func close(taskID: UUID) { windows.close(.task(taskID)) }
    func closeAll() { for id in openTaskIDs { close(taskID: id) } }

    private func openInMain(_ id: UUID) {
        close(taskID: id)
        if let environment { environment.openTask(id) }
        else { workspace?.select(id) }
        NativeMainWindowPresenter.activate()
    }
}
