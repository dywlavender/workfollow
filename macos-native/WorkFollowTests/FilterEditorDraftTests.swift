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
        XCTAssertEqual(draft.tagOptions(tagNames: ["Zebra", "Apple", "Zebra"]), ["Zebra", "Apple", "暂未使用"])
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

    func testNameOnlyEditPreservesOrdinaryOrganizationIdentity() {
        var original = SavedFilter(name: "原名", listNames: ["工作"], tags: ["重点"])
        original.listIDs = [UUID()]
        original.tagIDs = [UUID()]
        var draft = FilterEditorDraft(initial: original)
        draft.name = "新名"
        XCTAssertEqual(draft.filter.listIDs, original.listIDs)
        XCTAssertEqual(draft.filter.tagIDs, original.tagIDs)
        XCTAssertNil(draft.filter.expression)
    }

    func testOrdinaryToAdvancedAndBackPreservesAllConditionsWithoutPairingLegacyArrays() {
        var original = SavedFilter(name: "已有条件", listNames: ["工作", "学习"], tags: ["重点", "评审"],
                                   priorities: [.high, .none], dateRange: .today, keywords: ["报告", "review"])
        original.listIDs = [UUID(), UUID()]
        original.tagIDs = [UUID(), UUID()]
        var draft = FilterEditorDraft(initial: original)
        XCTAssertTrue(draft.switchMode(to: .advanced))
        XCTAssertEqual(draft.rules.map(\.kind), [.lists, .tags, .priorities, .date, .keywords])
        XCTAssertTrue(draft.rules.allSatisfy { $0.connector == .and })
        XCTAssertTrue(draft.rules[0].organizationSelections.allSatisfy { $0.id == nil })
        XCTAssertTrue(draft.rules[1].organizationSelections.allSatisfy { $0.id == nil })
        XCTAssertEqual(draft.rules[0].condition.legacyOrganizationIDs, original.listIDs)
        XCTAssertEqual(draft.rules[1].condition.legacyOrganizationIDs, original.tagIDs)
        XCTAssertTrue(draft.switchMode(to: .basic))
        XCTAssertEqual(draft.filter, original)
    }

    func testAdvancedRowsComposeFromLeftToRightAndPreviewUsesTheSavedExpression() {
        var list = FilterEditorRule(kind: .lists)
        list.organizationNames = ["工作"]
        var tag = FilterEditorRule(connector: .or, kind: .tags)
        tag.organizationNames = ["重点"]
        var priority = FilterEditorRule(connector: .and, kind: .priorities)
        priority.selectedPriorities = [.high]
        var draft = FilterEditorDraft(initial: nil)
        draft.name = "明确的顺序"
        draft.switchMode(to: .advanced)
        draft.rules = [list, tag, priority]
        let lowWork = task("低优先级工作", list: "工作", priority: .low)
        let highTag = task("高优先级重点", list: "个人", tags: ["重点"], priority: .high)
        let highWork = task("高优先级工作", list: "工作", priority: .high)
        let samples = [lowWork, highTag, highWork]
        let filter = draft.filter
        XCTAssertFalse(FilterEvaluator.matches(lowWork, filter: filter, now: now, calendar: calendar),
                       "工作 OR 标签 AND 高优先级明确解释为（工作 OR 标签）AND 高优先级")
        let preview = FilterEditorPreview.project(tasks: samples, filter: filter, now: now, calendar: calendar)
        XCTAssertEqual(preview.tasks.map(\.id), [highTag.id, highWork.id])
        let reopened = FilterEditorDraft(initial: filter)
        XCTAssertEqual(reopened.filter.expression, filter.expression)
        XCTAssertEqual(reopened.expressionSummary, draft.expressionSummary)
        XCTAssertTrue(draft.expressionSummary.hasPrefix("（（"))
        XCTAssertEqual(draft.rules.map(\.id), [list.id, tag.id, priority.id])
    }

    func testAdvancedSelectionEditsKeepExistingIDsAndNewSelectionsRemainUnbound() {
        let originalID = UUID()
        let original = SavedFilter(name: "组织选择", expression: .condition(FilterCondition(
            kind: .lists, organizationSelections: [FilterOrganizationSelection(id: originalID, name: "工作") ])))
        var draft = FilterEditorDraft(initial: original)
        let ruleID = draft.rules[0].id
        draft.rules[0].organizationNames = ["工作", "学习"]
        XCTAssertEqual(draft.rules[0].organizationSelections.first { $0.name == "工作" }?.id, originalID)
        XCTAssertNil(draft.rules[0].organizationSelections.first { $0.name == "学习" }?.id)
        draft.name = "只修改过滤器名称"
        XCTAssertEqual(draft.rules[0].id, ruleID)
        XCTAssertEqual(draft.filter.id, original.id)
        XCTAssertEqual(draft.rules[0].organizationSelections.first { $0.name == "工作" }?.id, originalID)
        draft.rules[0].organizationNames = ["学习"]
        XCTAssertNil(draft.rules[0].organizationSelections[0].id)
    }

    func testChoosingAllTagsAfterOrdinaryConversionReplacesTheLegacyAnyPredicate() {
        var original = SavedFilter(name: "改为全部标签", tags: ["重点", "评审"])
        original.tagIDs = [UUID(), UUID()]
        var draft = FilterEditorDraft(initial: original)
        draft.switchMode(to: .advanced)
        draft.rules[0].tagMatch = .all
        XCTAssertNil(draft.rules[0].condition.legacyOrganizationIDs)
        XCTAssertFalse(FilterEvaluator.matches(task("仅一个标签", tags: ["重点"]),
                                               filter: draft.filter, now: now, calendar: calendar))
        XCTAssertTrue(FilterEvaluator.matches(task("两个标签", tags: ["重点", "评审"]),
                                              filter: draft.filter, now: now, calendar: calendar))
    }

    func testSwitchingToOrdinaryRejectsOrAndTagAllWithoutChangingTheDraft() {
        let first = FilterExpression.condition(FilterCondition(kind: .lists,
            organizationSelections: [FilterOrganizationSelection(name: "工作")]))
        let second = FilterExpression.condition(FilterCondition(kind: .tags,
            organizationSelections: [FilterOrganizationSelection(name: "重点")]))
        var draft = FilterEditorDraft(initial: SavedFilter(name: "保留或", expression: .any([first, second])))
        let before = draft.filter
        XCTAssertFalse(draft.switchMode(to: .basic))
        XCTAssertEqual(draft.mode, .advanced)
        XCTAssertEqual(draft.filter, before)
        XCTAssertNotNil(draft.basicConversionIssue)

        let allTags = FilterCondition(kind: .tags, organizationSelections: [
            FilterOrganizationSelection(name: "重点"), FilterOrganizationSelection(name: "评审")], tagMatch: .all)
        draft = FilterEditorDraft(initial: SavedFilter(name: "保留全部标签", expression: .condition(allTags)))
        XCTAssertFalse(draft.switchMode(to: .basic))
        XCTAssertEqual(draft.filter.expression, .condition(allTags))
    }

    func testAdvancedAllConditionsCanSwitchBackWithoutLosingReferences() {
        let listID = UUID(), tagID = UUID()
        let original = SavedFilter(name: "可转换", expression: .all([
            .condition(FilterCondition(kind: .lists, organizationSelections: [
                FilterOrganizationSelection(id: listID, name: "工作")])),
            .condition(FilterCondition(kind: .tags, organizationSelections: [
                FilterOrganizationSelection(id: tagID, name: "重点")])),
            .condition(FilterCondition(kind: .date, dateRange: .today))
        ]))
        var draft = FilterEditorDraft(initial: original)
        XCTAssertNil(draft.basicConversionIssue)
        XCTAssertTrue(draft.switchMode(to: .basic))
        XCTAssertEqual(draft.filter.listIDs, [listID])
        XCTAssertEqual(draft.filter.tagIDs, [tagID])
        XCTAssertEqual(draft.filter.dateRange, .today)
        XCTAssertNil(draft.filter.expression)
    }

    func testGroupedExpressionIsRetainedWhenItCannotBePresentedAsSequentialRows() {
        let list = FilterExpression.condition(FilterCondition(kind: .lists,
            organizationSelections: [FilterOrganizationSelection(id: UUID(), name: "工作")]))
        let tag = FilterExpression.condition(FilterCondition(kind: .tags,
            organizationSelections: [FilterOrganizationSelection(id: UUID(), name: "重点")]))
        let priority = FilterExpression.condition(FilterCondition(kind: .priorities, priorities: [.high]))
        let expression = FilterExpression.all([list, .any([tag, priority])])
        var draft = FilterEditorDraft(initial: SavedFilter(name: "已有分组", expression: expression))
        XCTAssertFalse(draft.canEditAdvancedRules)
        XCTAssertNotNil(draft.advancedEditingIssue)
        draft.name = "仅改名"
        XCTAssertEqual(draft.filter.expression, expression)
        XCTAssertFalse(draft.switchMode(to: .basic))
    }

    func testUnconfiguredAdvancedRowsDoNotWidenOrConditions() {
        var draft = FilterEditorDraft(initial: nil)
        draft.switchMode(to: .advanced)
        var list = FilterEditorRule(kind: .lists)
        list.organizationNames = ["工作"]
        draft.rules = [list, FilterEditorRule(connector: .or, kind: .tags)]
        let matching = task("工作", list: "工作")
        let preview = FilterEditorPreview.project(tasks: [matching, task("个人", list: "个人")],
                                                 filter: draft.filter, now: now, calendar: calendar)
        XCTAssertEqual(preview.matchingCount, 1)
        XCTAssertEqual(preview.tasks.map(\.id), [matching.id])
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
