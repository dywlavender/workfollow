import Foundation

/// Summary status uses existing task facts; reading a report never mutates tasks.
struct SummaryTaskFacts {
    let status: SummaryFilter.Status
    let completedSteps: Int
    let totalSteps: Int
    let focusSeconds: Int
    let pomodoros: Int

    /// 滴答只把「有完成度」的未完成任务算进行中；专注/番茄不改变状态。
    static func index(tasks: [Task], focusRecords: [PomodoroRecord], range: SummaryDateRange) -> [UUID: Self] {
        let children = Dictionary(grouping: tasks.filter { $0.parentID != nil && !$0.isAbandoned }, by: { $0.parentID! })
        let records = Dictionary(grouping: focusRecords.filter { $0.taskID != nil }, by: { $0.taskID! })
        return Dictionary(uniqueKeysWithValues: tasks.map { task in
            let steps = children[task.id] ?? []
            let checks = task.document.blocks.compactMap { block -> Bool? in
                if case .checklist(let done) = block.kind { return done }; return nil
            }
            let total = steps.isEmpty ? checks.count : steps.count
            let done = steps.isEmpty ? checks.filter { $0 }.count : steps.filter { $0.status == .completed }.count
            let taskRecords = records[task.id] ?? []
            let periodRecords = taskRecords.filter { range.contains($0.startedAt) }
            let status: SummaryFilter.Status
            if task.status == .completed { status = .completed }
            else if task.isAbandoned { status = .abandoned }
            else if done > 0 { status = .inProgress }
            else { status = .uncompleted }
            return (task.id, Self(status: status, completedSteps: done, totalSteps: total,
                focusSeconds: periodRecords.reduce(0) { $0 + $1.activeSeconds },
                pomodoros: periodRecords.reduce(0) { $0 + $1.creditedPomodoros }))
        })
    }
}
