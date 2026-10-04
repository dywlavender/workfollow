import Foundation

/// Reusable task templates ("保存为模板 / 从模板添加"), persisted as
/// modules/templates.json through JSONFileStore. Templates are kept sorted by
/// name; identity is the trimmed, case-insensitive template name.
@MainActor
final class TemplateStore: ObservableObject, ModuleStoreFlushable {
    struct Archive: Codable {
        var templates: [TaskTemplate] = []
    }

    /// App-wide shared instance. Views reference this directly; termination
    /// persistence works because AppEnvironment registers `shared` in its
    /// moduleStores list, flushing the debounced write below on quit.
    static let shared = TemplateStore()

    @Published private(set) var templates: [TaskTemplate] = []

    private let persistence: JSONFileStore<Archive>
    private let clock: () -> Date

    init(clock: @escaping () -> Date = Date.init, directory: URL? = nil) {
        self.clock = clock
        let store: JSONFileStore<Archive>
        if let directory {
            store = JSONFileStore(filename: "templates.json", directory: directory)
        } else {
            store = JSONFileStore(filename: "templates.json")
        }
        persistence = store
        templates = Self.sorted(store.load()?.templates ?? [])
    }

    func template(named name: String) -> TaskTemplate? {
        templates.first { Self.isSameName($0.name, name) }
    }

    func contains(name: String) -> Bool {
        template(named: name) != nil
    }

    /// Captures `task` content (and the given children's titles) as a template
    /// named `name`. Returns false when the name is empty or already taken and
    /// `forceReplace` is false; after the UI confirms the replacement with the
    /// user, call again with `forceReplace: true`.
    @discardableResult
    func save(name: String, from task: Task, includingChildren children: [Task] = [],
              forceReplace: Bool = false) -> Bool {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        let template = Self.makeTemplate(name: cleaned, from: task,
                                         includingChildren: children, now: clock())
        if let index = templates.firstIndex(where: { Self.isSameName($0.name, cleaned) }) {
            guard forceReplace else { return false }
            templates[index] = template
        } else {
            templates.append(template)
        }
        templates = Self.sorted(templates)
        persist()
        return true
    }

    /// Returns a user blueprint, or nil when missing. Actual task creation is
    /// owned by TaskWorkspaceModel.createFromTemplate / TaskActions.
    func apply(name: String) -> TaskTemplate? {
        template(named: name)
    }

    @discardableResult
    func delete(_ id: UUID) -> Bool {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return false }
        templates.remove(at: index)
        persist()
        return true
    }

    /// Returns false when the new name is empty or taken by another template.
    @discardableResult
    func rename(_ id: UUID, to name: String) -> Bool {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let index = templates.firstIndex(where: { $0.id == id }),
              !templates.contains(where: { $0.id != id && Self.isSameName($0.name, cleaned) })
        else { return false }
        templates[index].name = cleaned
        templates = Self.sorted(templates)
        persist()
        return true
    }

    func flush(_ completion: @escaping (Error?) -> Void) {
        persistence.flush(completion)
    }

    private func persist() {
        persistence.schedule(Archive(templates: templates))
    }

    // MARK: - Template extraction

    private static func makeTemplate(name: String, from task: Task,
                                     includingChildren children: [Task],
                                     now: Date) -> TaskTemplate {
        TaskTemplate(
            name: name,
            title: task.title.trimmingCharacters(in: .whitespacesAndNewlines),
            document: task.document,
            tags: task.tags,
            listName: task.list.name == TaskList.inbox.name ? nil : task.list.name,
            priority: task.priority == .none ? nil : task.priority,
            schedule: TaskTemplateScheduleOffset.match(task.schedule.dueAt,
                                                       against: now, calendar: .current),
            childTitles: children
                .filter { !$0.isAbandoned && !$0.isConverted }
                .sorted { $0.childOrder < $1.childOrder }
                .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            createdAt: now)
    }

    private static func isSameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private static func sorted(_ values: [TaskTemplate]) -> [TaskTemplate] {
        values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
