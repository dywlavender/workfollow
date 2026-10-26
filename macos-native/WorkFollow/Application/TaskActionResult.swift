import Foundation

enum TaskActionError: Error, Equatable {
    case missingTask, deletedTask, circularReference, childListMoveNotSupported, invalidList
    case alreadyCompleted, alreadyActive, alreadyConverted, notDeleted
    case cannotParentToSelf, skippedTask, invalidSchedule
    /// 清单任务还有未勾选的检查事项，不能手动完成。
    case checklistItemsIncomplete
    /// 清单任务的检查事项仍全部勾选，不能直接取消完成。
    case checklistItemsCompleted
}

enum TaskActionResult: Equatable {
    case success(UUID)
    case failure(TaskActionError)

    var taskID: UUID? {
        if case let .success(id) = self { return id }
        return nil
    }
}
