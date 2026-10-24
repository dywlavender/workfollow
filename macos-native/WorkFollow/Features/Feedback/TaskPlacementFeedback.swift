import Foundation

/// Explains a successful edit when the task leaves the user's current scope.
enum TaskPlacementFeedback {
    @MainActor
    static func present(before: Task?, after: Task, count: Int = 1,
                        destination: NativeDestination, workspace: TaskWorkspaceModel,
                        center: FeedbackCenter, open: @escaping (UUID) -> Void) -> Bool {
        guard let scope = TaskWorkspaceModel.scope(for: destination) else { return false }
        func includes(_ task: Task) -> Bool {
            !TaskListProjection.matches(in: scope, tasks: [task], now: workspace.clock(),
                calendar: workspace.calendar,
                query: TaskListQuery(list: workspace.activeList, tag: workspace.activeTag),
                tags: workspace.taskTags).isEmpty
                && (workspace.activeFilter.map {
                    FilterEvaluator.matches(task, filter: $0, now: workspace.clock(), calendar: workspace.calendar)
                } ?? true)
        }
        guard !includes(after) else { return false }
        if let before {
            guard includes(before), before.schedule != after.schedule || before.list != after.list else { return false }
        }
        let day = after.schedule.dueAt.map {
            ScheduleDisplay.dateText($0, hasTime: false, now: workspace.clock(), calendar: workspace.calendar, style: .compact)
        } ?? "未安排日期"
        let prefix = before == nil ? (count > 1 ? "已添加 \(count) 项，最后一项" : "已添加") : "已调整"
        center.show(FeedbackEvent(kind: before == nil ? .success : .undoable,
            message: "\(prefix)至\(day) · \(after.list.name)",
            actionTitle: before == nil ? nil : "撤销",
            action: before == nil ? nil : { [weak workspace] in workspace?.undo() },
            destinationTitle: "查看", destinationAction: { open(after.id) }))
        return true
    }
}
