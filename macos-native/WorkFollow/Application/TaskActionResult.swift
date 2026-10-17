import Foundation

enum TaskActionError: Error, Equatable {
    case missingTask, deletedTask, circularReference, childListMoveNotSupported, invalidList
    case alreadyCompleted, alreadyActive, alreadyConverted, notDeleted
    case cannotParentToSelf, skippedTask, invalidSchedule
}

enum TaskActionResult: Equatable {
    case success(UUID)
    case failure(TaskActionError)

    var taskID: UUID? {
        if case let .success(id) = self { return id }
        return nil
    }
}
