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
    let reminders: NativeReminderService
    @Published private(set) var storageError: String?
    private let repository = NativePreviewRepository()
    private let persistence = PersistenceCoordinator()
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

    init(clock: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        reminders = NativeReminderService(clock: clock, calendar: calendar)
        let preferences = UserDefaults.standard
        self.preferences = preferences
        appearance = NativeAppearance(rawValue:
            preferences.string(forKey: "appearance") ?? "system") ?? .system
        var snapshot: NativeWorkspaceSnapshot?
        var failure: Error?
        do { snapshot = try repository.load() } catch { failure = error }
        taskWorkspace = TaskWorkspaceModel(clock: clock, calendar: calendar, initialTasks: snapshot?.tasks)
        notesWorkspace = NotesWorkspaceModel(initialNotes: snapshot?.notes ?? [], clock: clock)
        persistence.onResult = { [weak self] error in
            DispatchQueue.main.async { self?.storageError = error.map { "预览数据保存失败：\($0.localizedDescription)" } }
        }
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
        persistence.schedule(NativeWorkspaceSnapshot(tasks: taskWorkspace.allTasks, notes: notesWorkspace.notes))
    }

    func flush(completion: @escaping (Error?) -> Void) {
        persistence.flush(completion: completion)
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
