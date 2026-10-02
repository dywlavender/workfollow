import Foundation

enum TaskRelationTarget: Identifiable, Equatable {
    case task(Task)
    case note(Note)

    var id: String {
        switch self {
        case let .task(task): "task:\(task.id.uuidString)"
        case let .note(note): "note:\(note.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case let .task(task): task.title.isEmpty ? "无标题任务" : task.title
        case let .note(note): note.title.isEmpty ? "未命名笔记" : note.title
        }
    }

    var subtitle: String {
        switch self {
        case let .task(task): "任务 · \(task.list.name)"
        case let .note(note): "笔记 · \(note.folder)"
        }
    }

    var reference: EditorReference {
        switch self {
        case let .task(task):
            EditorReference(title: "任务：" + title,
                            target: NativeResourceLink.task(task.id).url.absoluteString)
        case let .note(note):
            TaskDocumentProfile.reference(to: note)
        }
    }

    var symbol: String {
        switch self {
        case .task: "checkmark.circle"
        case .note: "doc.text"
        }
    }
}

enum TaskRelationProjection {
    static func targets(sourceTaskID: UUID, tasks: [Task], notes: [Note], query: String) -> [TaskRelationTarget] {
        let tasksByID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let taskTargets = tasks.compactMap { task -> TaskRelationTarget? in
            guard task.id != sourceTaskID, isLinkable(task) else { return nil }
            if let parentID = task.parentID {
                guard let parent = tasksByID[parentID], isLinkable(parent) else { return nil }
            }
            let target = TaskRelationTarget.task(task)
            guard normalizedQuery.isEmpty
                    || target.title.localizedCaseInsensitiveContains(normalizedQuery)
                    || task.list.name.localizedCaseInsensitiveContains(normalizedQuery) else { return nil }
            return target
        }

        let noteTargets = notes.compactMap { note -> TaskRelationTarget? in
            guard note.deletedAt == nil else { return nil }
            let target = TaskRelationTarget.note(note)
            guard normalizedQuery.isEmpty
                    || target.title.localizedCaseInsensitiveContains(normalizedQuery)
                    || note.folder.localizedCaseInsensitiveContains(normalizedQuery) else { return nil }
            return target
        }

        return taskTargets + noteTargets
    }

    private static func isLinkable(_ task: Task) -> Bool {
        task.deletedAt == nil && task.skippedAt == nil && !task.isConverted
    }
}
