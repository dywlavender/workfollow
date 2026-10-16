import Foundation
@testable import WorkFollow

/// Compile against a Debug product to seed a separate acceptance workspace.
@main
struct PrepareReplicaFixture {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "ReplicaFixture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Usage: prepare-replica-fixture <new-storage-directory>"])
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let repository = NativePreviewRepository(directory: directory)
        guard try repository.load() == nil else {
            throw NSError(domain: "ReplicaFixture", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The acceptance workspace already contains tasks."])
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 1
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12))!
        func date(_ day: Int, _ minutes: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day,
                                               hour: minutes / 60, minute: minutes % 60))!
        }
        let workspace = TaskWorkspaceModel(clock: { now }, calendar: calendar, seedDemoData: false)
        let rows: [(String, String, TaskPriority, Int?, Int?, Int?, Int)] = [
            ("需求评审", "工作", .high, 13, 540, 600, 50),
            ("完善本周方案", "工作", .medium, 14, 600, 690, 90),
            ("阅读30分钟", "生活", .low, 15, 480, 510, 30),
            ("整理交付检查项", "工作", .none, nil, nil, nil, 25),
            ("联调与回归", "工作", .high, 16, 630, 690, 60),
            ("每周回顾", "工作", .medium, 17, nil, nil, 25),
            ("补充旅行计划", "生活", .none, nil, nil, nil, 0),
            ("整理上周笔记", "工作", .none, 12, nil, nil, 0)
        ]
        var identifiers: [UUID] = []
        for (title, list, priority, day, start, end, estimate) in rows {
            var schedule = TaskSchedule()
            schedule.dueAt = day.map { date($0, start ?? 0) }
            schedule.hasTime = start != nil
            schedule.dueEndAt = day.flatMap { day in end.map { date(day, $0) } }
            let result = workspace.createDraft(title: title, list: list, schedule: schedule,
                priority: priority, tags: list == "工作" ? ["本周"] : [], reminder: nil,
                repeatFrequency: title == "每周回顾" ? .weekly : .never,
                document: NativeDocument(plainText: title == "需求评审"
                    ? "确认交互与验收范围\n整理待决事项，评审后同步结论。" : "梳理计划，记录实际投入。"))
            guard let id = result.taskID else { throw NSError(domain: "ReplicaFixture", code: 3) }
            identifiers.append(id)
            if estimate > 0 { _ = workspace.setFocusEstimate(id, TaskFocusEstimate(minutes: estimate, pomodoros: nil)) }
        }
        _ = workspace.createChild(identifiers[0], title: "准备议程")
        _ = workspace.createChild(identifiers[0], title: "检查演示材料")
        if let old = workspace.task(for: identifiers[7]) { _ = workspace.changeStatus(old) }
        try repository.save(NativeWorkspaceSnapshot(tasks: workspace.allTasks, notes: [],
            taskLists: workspace.listNames, taskListMeta: workspace.listMetas,
            taskListFolders: workspace.listFolders, taskListSections: workspace.listSections))

        let focus = FocusStore(clock: { now }, calendar: calendar,
                               directory: directory.appendingPathComponent("modules"))
        guard focus.addTimer(name: "需求评审", emoji: "💼", stopwatch: false,
                             minutes: 25, taskID: identifiers[0]),
              focus.addTimer(name: "方案写作", emoji: "📚", stopwatch: true,
                             minutes: 0, taskID: identifiers[1]),
              focus.addTimer(name: "阅读计划", emoji: "📚", stopwatch: false,
                             minutes: 30, taskID: identifiers[2]) else {
            throw NSError(domain: "ReplicaFixture", code: 7)
        }
        let reviewPreset = focus.timers[0].id
        let writingPreset = focus.timers[1].id
        focus.archiveTimer(focus.timers[2].id)
        var first = FocusRecordDraft(now: now, taskID: identifiers[0], mode: .pomodoro,
                                     presetID: reviewPreset)
        first.startedAt = date(13, 510); first.endedAt = date(13, 535)
        first.note = "完成议程准备。"; first.creditedPomodoros = 1
        guard focus.saveRecordDraft(first) else { throw NSError(domain: "ReplicaFixture", code: 4) }
        var second = FocusRecordDraft(now: now, taskID: identifiers[1], mode: .stopwatch,
                                      presetID: writingPreset)
        second.startedAt = date(13, 600); second.endedAt = date(13, 640)
        second.note = "集中梳理交互。"
        guard focus.saveRecordDraft(second) else { throw NSError(domain: "ReplicaFixture", code: 5) }
        let finished = DispatchSemaphore(value: 0)
        var failure: Error?
        focus.flush { error in failure = error; finished.signal() }
        guard finished.wait(timeout: .now() + 10) == .success else {
            throw NSError(domain: "ReplicaFixture", code: 6,
                          userInfo: [NSLocalizedDescriptionKey: "Focus fixture flush did not finish."])
        }
        if let failure { throw failure }
        print("Acceptance fixture prepared: 8 tasks, 2 checklist children, 2 focus records, 2 active and 1 archived focus presets.")
    }
}
