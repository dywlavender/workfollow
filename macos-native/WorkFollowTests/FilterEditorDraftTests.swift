import XCTest
@testable import WorkFollow

final class FilterEditorDraftTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func task(_ title: String, list: String = TaskList.inbox.name,
                      tags: [String] = [], priority: TaskPriority = .none,
                      dueAt: Date? = nil, document: String = "") -> Task {
        Task(id: UUID(), title: title, document: NativeDocument(plainText: document),
             tags: tags, list: TaskList(name: list), priority: priority,
             schedule: TaskSchedule(dueAt: dueAt), parentID: nil, childOrder: 0,
             createdAt: now, updatedAt: now)
    }

    func testListOptionsIncludeInboxAndKeepSelectedValuesWithoutTasks() {
        var draft = FilterEditorDraft(initial: nil)
        XCTAssertEqual(draft.listOptions(allListNames: []), [TaskList.inbox.name])
        draft.selectedLists = ["临时清单"]
        XCTAssertEqual(draft.listOptions(allListNames: ["工作", "工作", TaskList.inbox.name]),
                       [TaskList.inbox.name, "临时清单", "工作"])
        draft.selectedTags = ["暂未使用"]
        XCTAssertEqual(draft.tagOptions(tagNames: ["工作"]), ["工作", "暂未使用"])
    }

    func testEditingRebuildsConditionsWithoutKeepingOldIdentitySelections() {
        var original = SavedFilter(name: "原过滤器", listNames: ["工作"], tags: ["计划"],
                                   priorities: [.low], dateRange: .today, keywords: ["周报"])
        original.listIDs = [UUID()]
        original.tagIDs = [UUID()]
        var draft = FilterEditorDraft(initial: original)
        draft.name = "  本周收集箱  "
        draft.selectedLists = [TaskList.inbox.name]
        draft.selectedTags = ["评审"]
        draft.selectedPriorities = [.high, .none]
        draft.dateRange = .nextSevenDays
        draft.keywordText = "报告，评审 报告"

        let conditions = draft.filter
        XCTAssertEqual(conditions.id, original.id)
        XCTAssertEqual(conditions.name, "本周收集箱")
        XCTAssertEqual(conditions.listNames, [TaskList.inbox.name])
        XCTAssertEqual(conditions.tags, ["评审"])
        XCTAssertEqual(conditions.priorities, [.high, .none])
        XCTAssertEqual(conditions.dateRange, .nextSevenDays)
        XCTAssertEqual(conditions.keywords, ["报告", "评审"])
        XCTAssertNil(conditions.listIDs, "草稿应按新的清单选择预览，保存时再解析身份")
        XCTAssertNil(conditions.tagIDs)
        XCTAssertEqual(original.listNames, ["工作"], "构建草稿不能改写已保存的过滤器")
    }

    func testPreviewUsesTheSameCombinedConditionsAsSaving() {
        var draft = FilterEditorDraft(initial: nil)
        draft.selectedLists = [TaskList.inbox.name, "工作"]
        draft.selectedTags = ["评审", "待办"]
        draft.selectedPriorities = [.high, .medium]
        draft.dateRange = .today
        draft.keywordText = "报告 Review"
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let inboxMatch = task("报告", tags: ["评审"], priority: .high,
                              dueAt: today, document: "review")
        let workMatch = task("Review 报告", list: "工作", tags: ["待办"],
                             priority: .medium, dueAt: today)
        let tasks = [
            inboxMatch, workMatch,
            task("Review 报告", list: "个人", tags: ["评审"], priority: .high, dueAt: today),
            task("Review 报告", tags: ["其他"], priority: .high, dueAt: today),
            task("Review 报告", tags: ["评审"], priority: .low, dueAt: today),
            task("Review 报告", tags: ["评审"], priority: .high, dueAt: tomorrow),
            task("报告", tags: ["评审"], priority: .high, dueAt: today)
        ]

        let result = FilterEditorPreview.project(tasks: tasks, filter: draft.filter,
                                                 now: now, calendar: calendar)
        XCTAssertEqual(result.matchingCount, 2)
        XCTAssertEqual(result.tasks.map(\.id), [inboxMatch.id, workMatch.id])
    }

    func testPreviewCountsActiveMatchingChildrenAndExcludesClosedOrRemovedTasks() {
        let parent = task("项目")
        var child = task("匹配子任务")
        child.parentID = parent.id
        var completed = task("匹配已完成")
        completed.status = .completed
        var abandoned = task("匹配已放弃")
        abandoned.abandonedAt = now
        var deleted = task("匹配已删除")
        deleted.deletedAt = now
        var converted = task("匹配已转笔记")
        converted.convertedNoteID = UUID()
        var skipped = task("匹配已跳过")
        skipped.skippedAt = now

        let result = FilterEditorPreview.project(
            tasks: [parent, child, completed, abandoned, deleted, converted, skipped],
            filter: SavedFilter(name: "子任务", keywords: ["匹配"]), now: now, calendar: calendar)

        XCTAssertEqual(result.matchingCount, 1)
        XCTAssertEqual(result.tasks.map(\.id), [child.id],
                       "为定位子任务而保留的父行不能重复计为匹配任务")
    }

    func testPreviewLimitsTitlesWhileCountingEveryMatch() {
        let tasks = (1...5).map { task("任务 \($0)") }
        let result = FilterEditorPreview.project(tasks: tasks, filter: SavedFilter(name: "全部"),
                                                 now: now, calendar: calendar)
        XCTAssertEqual(result.matchingCount, 5)
        XCTAssertEqual(result.tasks.map(\.id), Array(tasks.prefix(3)).map(\.id))
    }
}
