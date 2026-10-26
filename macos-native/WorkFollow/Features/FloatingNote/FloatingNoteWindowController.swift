import AppKit
import Combine

/// Note-specific creation, deletion and navigation; the window and editor are shared.
@MainActor
final class FloatingNoteWindowController: ObservableObject {
    static let shared = FloatingNoteWindowController()
    @Published private(set) var openNoteIDs: Set<UUID> = []
    private let windows: FloatingEditorWindowController
    private weak var environment: AppEnvironment?
    private var createdNoteIDs: Set<UUID> = []
    private var windowSubscription: AnyCancellable?
    private var revisionSubscription: AnyCancellable?
    private var appearanceSubscription: AnyCancellable?

    init(windows: FloatingEditorWindowController = .shared) {
        self.windows = windows
        windowSubscription = windows.$openIDs.sink { [weak self] ids in
            self?.openNoteIDs = Set(ids.compactMap {
                if case .note(let id) = $0 { return id }
                return nil
            })
        }
    }

    func attach(environment: AppEnvironment) {
        guard self.environment !== environment else { return }
        closeAll()
        self.environment = environment
        revisionSubscription = environment.notesWorkspace.$revision.dropFirst()
            .sink { [weak self] _ in self?.pruneClosedNotes() }
        appearanceSubscription = environment.$appearance.dropFirst()
            .sink { [weak self] appearance in
                guard let self else { return }
                self.windows.applyAppearance(appearance, to: Set(self.openNoteIDs.map(FloatingEditorID.note)))
            }
    }

    func isOpen(_ noteID: UUID) -> Bool { openNoteIDs.contains(noteID) }

    @discardableResult
    func openNewFloatingNote(folder: String? = nil) -> UUID? {
        guard let environment else { return nil }
        let id = environment.notesWorkspace.create(folder: folder, select: false)
        createdNoteIDs.insert(id)
        open(noteID: id)
        return id
    }

    func open(noteID: UUID) {
        guard let environment,
              environment.notesWorkspace.notes.contains(where: { $0.id == noteID && $0.deletedAt == nil })
        else { return }
        windows.open(id: .note(noteID), title: "悬浮笔记", appearance: environment.appearance,
            onClose: { [weak self] in self?.didClose(noteID) }) { handle in
                FloatingNoteView(noteID: noteID, notes: environment.notesWorkspace,
                    tasks: environment.taskWorkspace, editorHandle: handle,
                    focusAtEnd: createdNoteIDs.contains(noteID),
                    onClose: { [weak self] in self?.close(noteID: noteID) },
                    onOpenInMain: { [weak self] in self?.openInMain(noteID: noteID) })
            }
    }

    func bringToFront(noteID: UUID) { windows.bringToFront(.note(noteID)) }
    func close(noteID: UUID) { windows.close(.note(noteID)) }
    func closeAll() { for id in Array(openNoteIDs) { close(noteID: id) } }

    private func didClose(_ id: UUID) {
        if createdNoteIDs.remove(id) != nil { environment?.notesWorkspace.discardEmptyNote(id) }
    }

    private func openInMain(noteID: UUID) {
        guard let environment else { return }
        createdNoteIDs.remove(noteID)
        close(noteID: noteID)
        environment.navigation.destination = .notes
        environment.navigation.noteRevealRequest = noteID
        NativeMainWindowPresenter.activate()
    }

    private func pruneClosedNotes() {
        guard let environment else { return }
        for id in Array(openNoteIDs) where !environment.notesWorkspace.notes.contains(where: {
            $0.id == id && $0.deletedAt == nil
        }) { close(noteID: id) }
    }
}
