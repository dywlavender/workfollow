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
    let focusStore: FocusStore
    let habitStore: HabitStore
    let summaryStore: SummaryStore
    let filterStore: FilterStore
    /// 全应用唯一的瞬态结果通道：任务动作经 workspace.feedbackSink 上报到这里。
    let feedback: FeedbackCenter
    private let moduleStores: [ModuleStoreFlushable]
    @Published private(set) var storageError: String?
    @Published var sidebarVisible = true
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
        let feedback = FeedbackCenter(
            completionSoundEnabled: preferences.object(forKey: "completionSoundEnabled") as? Bool ?? true,
            playSound: { Self.playFeedbackSound($0) })
        self.feedback = feedback
        taskWorkspace = TaskWorkspaceModel(clock: clock, calendar: calendar, initialTasks: snapshot?.tasks, initialLists: snapshot?.taskLists ?? [], initialListMeta: snapshot?.taskListMeta)
        notesWorkspace = NotesWorkspaceModel(initialNotes: snapshot?.notes ?? [], clock: clock)
        focusStore = FocusStore(clock: clock)
        habitStore = HabitStore(clock: clock)
        summaryStore = SummaryStore(clock: clock)
        filterStore = FilterStore(clock: clock)
        taskWorkspace.attachFilterStore(filterStore)
        taskWorkspace.feedbackSink = feedback
        moduleStores = [focusStore, habitStore, summaryStore, filterStore, TemplateStore.shared]
        persistence.onResult = { [weak self] error in
            DispatchQueue.main.async { self?.storageError = error.map { "预览数据保存失败：\($0.localizedDescription)" } }
        }
        if let failure { loadFailed = true; storageError = "预览数据读取失败，自动保存已停用：\(failure.localizedDescription)" }
        // B2 笔记↔任务联动：笔记详情展示/勾选/打开 sourceNoteID 关联的任务。
        notesWorkspace.taskProvider = { [weak taskWorkspace] in taskWorkspace?.allTasks ?? [] }
        notesWorkspace.openTask = { [weak self] id in
            self?.taskWorkspace.select(id)
        }
        applyAcceptanceDestination()
        taskWorkspace.$revision.dropFirst().sink { [weak self] _ in
            self?.savePreview()
            if let self, !self.loadFailed { self.reminders.reconcile(self.taskWorkspace.allTasks) }
        }.store(in: &subscriptions)
        notesWorkspace.$revision.dropFirst().sink { [weak self] _ in self?.savePreview() }.store(in: &subscriptions)
        if !loadFailed { reminders.reconcile(taskWorkspace.allTasks) }
    }

    /// Acceptance harness: `--wf-destination <rawValue>` opens that view directly
    /// so screenshots can be taken without UI automation.
    private func applyAcceptanceDestination() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--wf-destination"),
              arguments.indices.contains(index + 1),
              let destination = NativeDestination(rawValue: arguments[index + 1]) else { return }
        navigation.destination = destination
    }

    private func savePreview() {
        guard !loadFailed else { return }
        persistence.schedule(NativeWorkspaceSnapshot(tasks: taskWorkspace.allTasks, notes: notesWorkspace.notes, taskLists: taskWorkspace.listNames, taskListMeta: taskWorkspace.listMetas))
    }

    /// ⌘\ 显示或隐藏侧栏。
    func toggleSidebar() {
        sidebarVisible.toggle()
    }

    /// 完成提示音（对齐 Flutter FeedbackSoundPlayer）：系统 Tink 短音、0.4 音量，
    /// 新音替换旧音而非叠加；缺音时静默降级，不视为错误。
    private static func playFeedbackSound(_ sound: FeedbackSound) {
        guard sound == .completion, let tone = NSSound(named: NSSound.Name("Tink")) else { return }
        tone.stop()
        tone.volume = 0.4
        tone.play()
    }

    func flush(completion: @escaping (Error?) -> Void) {
        persistence.flush { first in
            // Module stores flush on their own queues; aggregate the errors.
            let group = DispatchGroup()
            let box = ErrorBox()
            for store in self.moduleStores {
                group.enter()
                store.flush { error in
                    if let error { box.add(error) }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                completion(first ?? box.error)
            }
        }
    }

    private final class ErrorBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Error?
        var error: Error? { lock.withLock { stored } }
        func add(_ error: Error) { lock.withLock { stored = stored ?? error } }
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
        taskWorkspace.activeList = nil
        taskWorkspace.activeTag = nil
        navigation.destination = destination
        taskWorkspace.select(nil)
    }

    @discardableResult
    func convertTaskToNote(_ id: UUID) -> UUID? {
        guard let task = taskWorkspace.task(for: id), !task.isConverted else { return nil }
        let children = taskWorkspace.allTasks
            .filter { $0.parentID == id && $0.deletedAt == nil && $0.skippedAt == nil }
            .sorted { $0.childOrder < $1.childOrder }
        let noteID = notesWorkspace.createFromTask(task, children: children, clock: taskWorkspace.clock)
        let result = taskWorkspace.convertToNote(id, noteID: noteID) { [weak notes = notesWorkspace] in
            MainActor.assumeIsolated { notes?.discardCreatedNoteForUndo(noteID) }
        }
        guard result.taskID != nil else {
            notesWorkspace.discardCreatedNoteForUndo(noteID)
            return nil
        }
        navigation.destination = .notes
        notesWorkspace.selectedID = noteID
        return noteID
    }
}
