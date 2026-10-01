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
        guard parent.parentID == nil else { return .childCannotHaveChildren }
        guard !tasks.contains(where: { $0.parentID == task.id }) else { return .taskHasChildren }
        return nil
    }
}
