import Foundation

enum TaskParentPolicy {
    static func canAssign(task: Task, parent: Task, tasks: [Task]) -> Bool {
        rejection(task: task, parent: parent, tasks: tasks) == nil
    }

    static func rejection(task: Task, parent: Task, tasks: [Task]) -> TaskActionError? {
        guard tasks.contains(where: { $0.id == task.id }),
              tasks.contains(where: { $0.id == parent.id }) else {
            return .missingTask
        }
        guard task.id != parent.id else { return .cannotParentToSelf }
        guard task.deletedAt == nil else { return .deletedTask }
        guard !task.isConverted else { return .alreadyConverted }
        guard !task.isClosed else { return .alreadyCompleted }
        guard task.skippedAt == nil else { return .skippedTask }
        guard parent.deletedAt == nil else { return .deletedTask }
        guard !parent.isConverted else { return .alreadyConverted }
        guard !parent.isClosed else { return .alreadyCompleted }
        guard parent.skippedAt == nil else { return .skippedTask }
        // 放开嵌套（2026-10-17）：子任务可再有子任务、有子任务的任务可再成为别人的
        // 子任务。仅禁止形成环——新父不能是任务自己的后代。
        guard !isDescendant(parent.id, of: task.id, in: tasks) else { return .circularReference }
        return nil
    }

    /// `candidate` 是否为 `ancestor` 的后代：沿 candidate 的父链向上，遇到 ancestor 即后代。
    private static func isDescendant(_ candidate: UUID, of ancestor: UUID, in tasks: [Task]) -> Bool {
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var current = candidate
        var visited = Set<UUID>()
        while visited.insert(current).inserted, let task = byID[current] {
            guard let parentID = task.parentID else { return false }
            if parentID == ancestor { return true }
            current = parentID
        }
        return false
    }
}
