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
    /// 目标已是该值，store 未发生任何改动（同值标题/正文回写）。仍带 taskID，
    /// 让调用方按“非失败”处理，但 didMutate 不据此递增 revision 或重建投影。
    case unchanged(UUID)
    case failure(TaskActionError)

    var taskID: UUID? {
        switch self {
        case let .success(id), let .unchanged(id): return id
        case .failure: return nil
        }
    }

    /// 是否真正改动了 store —— revision 只在此基础上递增。
    var didChangeStore: Bool {
        if case .success = self { return true }
        return false
    }
}
