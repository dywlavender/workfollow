import Foundation

enum TaskActionError: Error, Equatable {
    case missingTask, deletedTask, childCannotHaveChildren, invalidList
    case alreadyCompleted, alreadyActive, notDeleted
}

enum TaskActionResult: Equatable {
    case success(UUID)
    case failure(TaskActionError)

    var taskID: UUID? {
        if case let .success(id) = self { return id }
        return nil
    }
}
