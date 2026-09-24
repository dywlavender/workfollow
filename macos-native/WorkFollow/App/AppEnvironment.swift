import SwiftUI
import Combine

enum NativeAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppEnvironment: ObservableObject {
    let navigation = AppNavigation()
    let taskWorkspace: TaskWorkspaceModel
    let notesWorkspace: NotesWorkspaceModel
    let reminders = NativeReminderService()
    @Published private(set) var storageError: String?
    private let repository = NativePreviewRepository()
    private var subscriptions = Set<AnyCancellable>()
    private var loadFailed = false
    @Published var commandPalettePresented = false
    @Published private(set) var quickAddRequest = 0
    @Published var appearance: NativeAppearance {
        didSet { preferences.set(appearance.rawValue, forKey: "appearance") }
    }
    // Preferences and window restoration use the Native bundle's own domain.
    // Only the separate WorkFollowNativePreview directory is opened.
    private let preferences: UserDefaults

    init() {
        let preferences = UserDefaults.standard
        self.preferences = preferences
        appearance = NativeAppearance(rawValue:
            preferences.string(forKey: "appearance") ?? "system") ?? .system
        var snapshot: NativeWorkspaceSnapshot?
        var failure: Error?
        do { snapshot = try repository.load() } catch { failure = error }
        taskWorkspace = TaskWorkspaceModel(initialTasks: snapshot?.tasks)
        notesWorkspace = NotesWorkspaceModel(initialNotes: snapshot?.notes ?? [])
        if let failure { loadFailed = true; storageError = "预览数据读取失败，自动保存已停用：\(failure.localizedDescription)" }
        taskWorkspace.$revision.dropFirst().sink { [weak self] _ in
            self?.savePreview()
            if let self, !self.loadFailed { self.reminders.reconcile(self.taskWorkspace.allTasks) }
        }.store(in: &subscriptions)
        notesWorkspace.$revision.dropFirst().sink { [weak self] _ in self?.savePreview() }.store(in: &subscriptions)
        if !loadFailed { reminders.reconcile(taskWorkspace.allTasks) }
    }

    private func savePreview() {
        guard !loadFailed else { return }
        do {
            try repository.save(NativeWorkspaceSnapshot(tasks: taskWorkspace.allTasks, notes: notesWorkspace.notes))
            storageError = nil
        } catch { storageError = "预览数据保存失败：\(error.localizedDescription)" }
    }

    func newTask() {
        if navigation.destination.isNotes {
            navigation.destination = .notes
            notesWorkspace.create()
            return
        }
        if ![.today, .inbox].contains(navigation.destination) {
            navigation.destination = .today
        }
        taskWorkspace.select(nil)
        quickAddRequest += 1
    }

    func navigate(to destination: NativeDestination) {
        navigation.destination = destination
        taskWorkspace.select(nil)
    }
}
