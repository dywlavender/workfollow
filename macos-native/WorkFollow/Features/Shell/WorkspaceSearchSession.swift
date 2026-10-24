import Combine
import Foundation

@MainActor
final class WorkspaceSearchSession: ObservableObject {
    enum Content: String, CaseIterable { case all = "全部类型", tasks = "任务", notes = "笔记" }
    enum Status: String, CaseIterable { case all = "全部状态", open = "未完成", completed = "已完成" }
    private struct Recent: Codable, Equatable { var id: UUID; var note: Bool }
    @Published var query = ""
    @Published var showAll = false
    @Published var content = Content.all
    @Published var status = Status.all
    @Published var list: String?
    @Published var selectedIndex = 0
    @Published private var recent: [Recent] = []
    private let defaults: UserDefaults
    private static let key = "recentWorkspaceResources.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let stored = try? JSONDecoder().decode([Recent].self, from: data) {
            recent = Array(stored.prefix(8))
        }
    }
    func recordTask(_ id: UUID) { record(.init(id: id, note: false)) }
    func recordNote(_ id: UUID) { record(.init(id: id, note: true)) }
    private func record(_ item: Recent) {
        guard recent.first != item else { return }
        recent.removeAll { $0 == item }; recent.insert(item, at: 0)
        recent = Array(recent.prefix(8))
        if let data = try? JSONEncoder().encode(recent) { defaults.set(data, forKey: Self.key) }
    }
    func recentEntries(tasks: [Task], notes: [Note]) -> [CommandPaletteEntry] {
        recent.compactMap { item in
            if item.note {
                guard let note = notes.first(where: { $0.id == item.id && $0.deletedAt == nil }) else { return nil }
                return .init(id: "note-" + item.id.uuidString, kind: .note,
                    title: note.title.isEmpty ? "未命名笔记" : note.title, subtitle: "最近打开 · 笔记 · " + note.folder,
                    symbol: "text.alignleft", action: .openNote(note.id))
            }
            guard let task = tasks.first(where: { $0.id == item.id && $0.deletedAt == nil && $0.skippedAt == nil && !$0.isConverted && !$0.isAbandoned }) else { return nil }
            return .init(id: "task-" + item.id.uuidString, kind: .task,
                title: task.title.isEmpty ? "无标题" : task.title, subtitle: "最近打开 · " + task.list.name,
                symbol: "clock", action: .openTask(task.id))
        }
    }
    @discardableResult
    func open(_ entry: CommandPaletteEntry, environment: AppEnvironment, navigation: AppNavigation) -> Bool {
        switch entry.action {
        case .createTask(let title):
            guard CommandPaletteProjection.createTask(title, workspace: environment.taskWorkspace,
                navigation: navigation).taskID != nil else { return false }
        case .openTask(let id):
            guard CommandPaletteProjection.openTask(id, workspace: environment.taskWorkspace,
                navigation: navigation) else { return false }
        case .openNote(let id):
            guard CommandPaletteProjection.openNote(id, workspace: environment.notesWorkspace,
                taskWorkspace: environment.taskWorkspace, navigation: navigation) else { return false }
        case .navigate(let destination): environment.navigate(to: destination)
        case .toggleAppearance: environment.appearance = CommandPaletteProjection.nextAppearance(after: environment.appearance)
        }
        environment.commandPalettePresented = false
        if entry.kind == .task || entry.kind == .note {
            environment.feedback.show(FeedbackEvent(kind: .info, message: "已打开「" + entry.title + "」",
                destinationTitle: "返回搜索", destinationAction: { [weak environment] in environment?.commandPalettePresented = true }))
        }
        return true
    }

    func entries(workspace: TaskWorkspaceModel, notes: [Note], destination: NativeDestination) -> [CommandPaletteEntry] {
        let tasks = workspace.allTasks.filter {
            (!showAll || list == nil || $0.list.name == list)
                && (!showAll || status == .all || (status == .completed ? $0.status == .completed : !$0.isClosed))
        }
        let values = CommandPaletteProjection.entries(query: query,
            tasks: showAll && content == .notes ? [] : tasks,
            notes: showAll && (content == .tasks || (content != .notes && (list != nil || status != .all))) ? [] : notes,
            creationList: workspace.activeList ?? TaskList.inbox.name,
            schedulesForToday: destination == .today, now: workspace.clock(), calendar: workspace.calendar,
            taskLimit: showAll ? .max : 7, noteLimit: showAll ? .max : 5, includeAllWhenEmpty: showAll)
        if showAll { return values.filter { $0.kind == .task || $0.kind == .note } }
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return values }
        return recentEntries(tasks: workspace.allTasks, notes: notes) + values
    }
}
