import XCTest
@testable import WorkFollow

@MainActor
final class FilterEvaluatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var startOfToday: Date { calendar.startOfDay(for: now) }
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: startOfToday)!
    }

    // MARK: - Helpers

    private func makeFilter(name: String = "过滤器",
                            listNames: [String] = [],
                            tags: [String] = [],
                            priorities: [TaskPriority] = [],
                            dateRange: SavedFilterDateRange = .any,
                            keywords: [String] = []) -> SavedFilter {
        SavedFilter(name: name, listNames: listNames, tags: tags,
                    priorities: priorities, dateRange: dateRange, keywords: keywords)
    }

    private func makeTask(title: String = "任务", list: String = "收集箱", tags: [String] = [],
                          priority: TaskPriority = .none,
                          dueAt: Date? = nil, deadlineAt: Date? = nil,
                          document: NativeDocument = .empty,
                          completed: Bool = false, parent: Task? = nil) -> Task {
        Task(id: UUID(), title: title, document: document, tags: tags, list: TaskList(name: list),
             priority: priority, schedule: TaskSchedule(dueAt: dueAt, deadlineAt: deadlineAt),
             status: completed ? .completed : .active, parentID: parent?.id,
             childOrder: 0, createdAt: now, updatedAt: now)
    }

    private func matches(_ task: Task, _ filter: SavedFilter) -> Bool {
        FilterEvaluator.matches(task, filter: filter, now: now, calendar: calendar)
    }

    private func makeStore() -> (store: FilterStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FilterEvaluatorTests-\(UUID().uuidString)", isDirectory: true)
        return (FilterStore(clock: { self.now }, directory: directory), directory)
    }

    private func makeWorkspace(tasks: [Task]) -> TaskWorkspaceModel {
        TaskWorkspaceModel(clock: { self.now }, calendar: calendar,
                           seedDemoData: false, initialTasks: tasks)
    }

    // MARK: - 空过滤器

    func testEmptyFilterMatchesEveryTaskIncludingClosedOnes() {
        let filter = makeFilter()
        let samples = [
            makeTask(list: "工作", tags: ["紧急"], priority: .high, dueAt: day(-3)),
            makeTask(),
            makeTask(dueAt: day(9), completed: true)
        ]
        for task in samples {
            XCTAssertTrue(matches(task, filter), "未启用任何维度时应匹配所有任务")
        }
    }

    // MARK: - 关键词维度（滴答「普通筛选」的按关键词做内容筛选）

    func testKeywordMatchesTitleCaseInsensitively() {
        let task = makeTask(title: "季度报告 Review")
        XCTAssertTrue(matches(task, makeFilter(keywords: ["报告"])))
        XCTAssertTrue(matches(task, makeFilter(keywords: ["review"])), "大小写不敏感")
        XCTAssertFalse(matches(task, makeFilter(keywords: ["周报"])))
    }

    func testKeywordMatchesDocumentPlainText() {
        let task = makeTask(document: NativeDocument(plainText: "会议纪要：下周三之前给财务留底"))
        XCTAssertTrue(matches(task, makeFilter(keywords: ["财务"])))
        XCTAssertTrue(matches(task, makeFilter(keywords: ["会议纪要"])))
        XCTAssertFalse(matches(task, makeFilter(keywords: ["法务"])))
    }

    func testMultipleKeywordsAreAllRequired() {
        let task = makeTask(document: NativeDocument(plainText: "报告 财务 复核"))
        XCTAssertTrue(matches(task, makeFilter(keywords: ["报告", "财务"])))
        XCTAssertFalse(matches(task, makeFilter(keywords: ["报告", "法务"])), "多关键词是 AND")
    }

    func testKeywordCombinesWithOtherDimensions() {
        let task = makeTask(tags: ["工作"], document: NativeDocument(plainText: "报告"))
        XCTAssertTrue(matches(task, makeFilter(tags: ["工作"], keywords: ["报告"])))
        XCTAssertFalse(matches(task, makeFilter(tags: ["私人"], keywords: ["报告"])), "跨维度 AND")
    }

    func testEmptyKeywordListDoesNotFilter() {
        XCTAssertTrue(matches(makeTask(), makeFilter(keywords: [])))
    }

    func testParseKeywordsSplitsOnSpacesCommasAndDeduplicates() {
        XCTAssertEqual(SavedFilter.parseKeywords("报告 财务，法务、复核"), ["报告", "财务", "法务", "复核"])
        XCTAssertEqual(SavedFilter.parseKeywords("  报告   报告 "), ["报告"], "去重且忽略空 token")
        XCTAssertEqual(SavedFilter.parseKeywords(""), [])
    }

    func testOldArchiveWithoutKeywordsDecodesToEmpty() throws {
        let json = """
        [{"id":"11111111-1111-1111-1111-111111111111","name":"旧过滤器",
          "listNames":["收集箱"],"tags":["紧急"],"priorities":[],"dateRange":"any"}]
        """
        let decoded = try JSONDecoder().decode([SavedFilter].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.first?.keywords, [], "旧 filters.json 缺 keywords 键必须能解码")
        XCTAssertEqual(decoded.first?.listNames, ["收集箱"], "其余维度照旧")
    }

    func testKeywordsRoundTripThroughCodable() throws {
        let filter = makeFilter(keywords: ["报告", "财务"])
        let data = try JSONEncoder().encode([filter])
        let decoded = try JSONDecoder().decode([SavedFilter].self, from: data)
        XCTAssertEqual(decoded, [filter])
    }

    // MARK: - 日期维度（对齐 TaskListProjection 口径）

    func testTodayRangeFollowsTodayScopePredicate() {
        let filter = makeFilter(dateRange: .today)
        XCTAssertTrue(matches(makeTask(dueAt: startOfToday), filter))
        XCTAssertTrue(matches(makeTask(dueAt: startOfToday.addingTimeInterval(8 * 3600)), filter),
                      "同一天带时间也算今天（按 startOfDay 比较）")
        XCTAssertTrue(matches(makeTask(dueAt: day(-1)), filter),
                      "今天视图包含已过期任务（due 不晚于今天）")
        XCTAssertTrue(matches(makeTask(deadlineAt: startOfToday), filter),
                      "今天视图把不晚于今天的截止时间算进来")
        XCTAssertFalse(matches(makeTask(dueAt: day(1)), filter))
        XCTAssertFalse(matches(makeTask(deadlineAt: day(1)), filter))
        XCTAssertFalse(matches(makeTask(), filter))
    }

    func testNextSevenDaysRangeFollowsNextSevenDaysScopePredicate() {
        let filter = makeFilter(dateRange: .nextSevenDays)
        XCTAssertTrue(matches(makeTask(dueAt: day(-1)), filter),
                      "与最近 7 天视图一致：包含已过期")
        XCTAssertTrue(matches(makeTask(dueAt: day(0)), filter))
        XCTAssertTrue(matches(makeTask(dueAt: day(6)), filter))
        XCTAssertFalse(matches(makeTask(dueAt: day(7)), filter),
                       "边界日 today+7 被排除（startOfDay(due) < today+7）")
        XCTAssertFalse(matches(makeTask(dueAt: day(8)), filter))
        XCTAssertFalse(matches(makeTask(), filter))
    }

    func testOverdueRangeMatchesDueDatesBeforeTodayOnly() {
        let filter = makeFilter(dateRange: .overdue)
        XCTAssertTrue(matches(makeTask(dueAt: day(-1)), filter))
        XCTAssertTrue(matches(makeTask(dueAt: day(-30)), filter))
        XCTAssertFalse(matches(makeTask(dueAt: day(0)), filter))
        XCTAssertFalse(matches(makeTask(dueAt: day(1)), filter))
        XCTAssertFalse(matches(makeTask(deadlineAt: day(-1)), filter),
                       "已逾期分桶只看到期日，截止时间不算（对齐所有任务分桶口径）")
        XCTAssertFalse(matches(makeTask(), filter))
    }

    func testNoDateRangeMatchesUndatedTasksOnly() {
        let filter = makeFilter(dateRange: .noDate)
        XCTAssertTrue(matches(makeTask(), filter))
        XCTAssertTrue(matches(makeTask(deadlineAt: day(2)), filter),
                      "只有截止时间的任务落在无日期桶（dueAt == nil）")
        XCTAssertFalse(matches(makeTask(dueAt: day(0)), filter))
        XCTAssertFalse(matches(makeTask(dueAt: day(-1)), filter))
    }

    // MARK: - 清单 / 标签 / 优先级

    func testListNamesMatchAnyValueAndSkipEmptyDimension() {
        let filter = makeFilter(listNames: ["工作", "学习"])
        XCTAssertTrue(matches(makeTask(list: "工作"), filter))
        XCTAssertTrue(matches(makeTask(list: "学习"), filter))
        XCTAssertFalse(matches(makeTask(list: "个人"), filter))
        XCTAssertTrue(matches(makeTask(list: "个人"), makeFilter()),
                      "清单维度未启用时不限制清单")
    }

    func testTagsMatchAnyValueExactlyAndSkipEmptyDimension() {
        let filter = makeFilter(tags: ["紧急", "专注"])
        XCTAssertTrue(matches(makeTask(tags: ["紧急"]), filter))
        XCTAssertTrue(matches(makeTask(tags: ["其他", "专注"]), filter))
        XCTAssertFalse(matches(makeTask(tags: ["其他"]), filter))
        XCTAssertFalse(matches(makeTask(), filter))
        XCTAssertFalse(matches(makeTask(tags: ["work"]), makeFilter(tags: ["Work"])),
                       "标签为精确匹配，与 TaskListQuery 的 contains 一致")
        XCTAssertTrue(matches(makeTask(), makeFilter()), "标签维度未启用时不要求有标签")
    }

    func testPrioritiesMatchAnyValueAndSkipEmptyDimension() {
        let filter = makeFilter(priorities: [.high, .medium])
        XCTAssertTrue(matches(makeTask(priority: .high), filter))
        XCTAssertTrue(matches(makeTask(priority: .medium), filter))
        XCTAssertFalse(matches(makeTask(priority: .low), filter))
        XCTAssertFalse(matches(makeTask(priority: .none), filter))
        XCTAssertTrue(matches(makeTask(priority: .low), makeFilter()), "优先级维度未启用时不限制")
    }

    // MARK: - 组合 AND

    func testAllEnabledDimensionsCombineWithAnd() {
        let filter = makeFilter(listNames: ["工作"], tags: ["紧急"],
                                priorities: [.high], dateRange: .today)
        XCTAssertTrue(matches(makeTask(list: "工作", tags: ["紧急"],
                                       priority: .high, dueAt: startOfToday), filter))
        XCTAssertFalse(matches(makeTask(list: "个人", tags: ["紧急"],
                                        priority: .high, dueAt: startOfToday), filter),
                       "清单不匹配即整体不匹配")
        XCTAssertFalse(matches(makeTask(list: "工作", tags: ["其他"],
                                        priority: .high, dueAt: startOfToday), filter),
                       "标签不匹配即整体不匹配")
        XCTAssertFalse(matches(makeTask(list: "工作", tags: ["紧急"],
                                        priority: .low, dueAt: startOfToday), filter),
                       "优先级不匹配即整体不匹配")
        XCTAssertFalse(matches(makeTask(list: "工作", tags: ["紧急"],
                                        priority: .high, dueAt: day(1)), filter),
                       "日期不匹配即整体不匹配")
    }

    func testCompletedTasksStillMatchFilterLikeTagQueries() {
        let combined = makeFilter(listNames: ["工作"], tags: ["紧急"],
                                  priorities: [.high], dateRange: .today)
        let completedToday = makeTask(list: "工作", tags: ["紧急"], priority: .high,
                                      dueAt: startOfToday, completed: true)
        XCTAssertTrue(matches(completedToday, combined),
                      "已完成任务与 activeTag 口径一致：TaskListQuery 不排除 isClosed，"
                      + "匹配的已完成任务继续留在视图的已完成分组中")
        let overdueFilter = makeFilter(dateRange: .overdue)
        XCTAssertTrue(matches(makeTask(dueAt: day(-1), completed: true), overdueFilter))
        XCTAssertTrue(matches(makeTask(completed: true), makeFilter()))
    }

    // MARK: - Codable 往返

    func testSavedFilterCodableRoundTripKeepsEveryDimension() throws {
        let filter = makeFilter(name: "工作高优先级", listNames: ["工作", "学习"],
                                tags: ["紧急"], priorities: [.none, .high],
                                dateRange: .nextSevenDays)
        let data = try JSONEncoder().encode(filter)
        let decoded = try JSONDecoder().decode(SavedFilter.self, from: data)
        XCTAssertEqual(decoded, filter)
    }

    // MARK: - FilterStore

    func testStoreRejectsEmptyAndDuplicateNamesButUpdatesAndRenames() {
        let (store, _) = makeStore()
        let first = SavedFilter(name: "工作", listNames: ["工作"])
        XCTAssertTrue(store.add(first))
        XCTAssertFalse(store.add(SavedFilter(name: "  工作  ")), "重名（含首尾空白）应拒绝")
        XCTAssertFalse(store.add(SavedFilter(name: "   ")), "空白名应拒绝")
        XCTAssertTrue(store.add(SavedFilter(name: "学习")))

        XCTAssertTrue(store.rename(first.id, to: "紧急工作"))
        XCTAssertEqual(store.filter(withID: first.id)?.name, "紧急工作")
        XCTAssertFalse(store.rename(first.id, to: "学习"), "与其他过滤器重名应失败")
        XCTAssertFalse(store.rename(UUID(), to: "不存在"), "未知 id 返回 false")

        XCTAssertTrue(store.update(SavedFilter(id: first.id, name: "紧急工作",
                                               listNames: ["工作"], tags: ["紧急"],
                                               priorities: [.high], dateRange: .today)))
        XCTAssertEqual(store.filter(withID: first.id)?.tags, ["紧急"])
        XCTAssertFalse(store.update(SavedFilter(id: UUID(), name: "任意")), "未知 id 返回 false")

        XCTAssertTrue(store.delete(first.id))
        XCTAssertFalse(store.delete(first.id))
        XCTAssertEqual(store.filters.map(\.name), ["学习"])
    }

    func testFiltersStaySortedByName() {
        let (store, _) = makeStore()
        XCTAssertTrue(store.add(SavedFilter(name: "b 过滤器")))
        XCTAssertTrue(store.add(SavedFilter(name: "A 过滤器")))
        XCTAssertTrue(store.add(SavedFilter(name: "c 过滤器")))
        XCTAssertEqual(store.filters.map(\.name), ["A 过滤器", "b 过滤器", "c 过滤器"])
    }

    func testStorePersistsFiltersForTheNextInstance() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FilterEvaluatorTests-\(UUID().uuidString)", isDirectory: true)
        let store = FilterStore(clock: { self.now }, directory: directory)
        XCTAssertTrue(store.add(SavedFilter(name: "工作高优先级", listNames: ["工作"],
                                            priorities: [.high])))
        XCTAssertTrue(store.add(SavedFilter(name: "无日期", dateRange: .noDate)))
        let done = expectation(description: "flush")
        store.flush { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)

        let reloaded = FilterStore(clock: { self.now }, directory: directory)
        XCTAssertEqual(reloaded.filters.map(\.name), ["工作高优先级", "无日期"])
        XCTAssertEqual(reloaded.filters.map(\.dateRange), [.any, .noDate])
        XCTAssertEqual(reloaded.filters.first?.priorities, [.high])
        XCTAssertEqual(reloaded.filters.first?.listNames, ["工作"])
    }

    // MARK: - TaskWorkspaceModel 集成

    func testWorkspaceAppliesSavedFilterOnTopOfScopesWithoutTouchingBadges() {
        let workTask = makeTask(list: "工作", dueAt: day(-1))
        let personalTask = makeTask(list: "个人", dueAt: day(0))
        let workspace = makeWorkspace(tasks: [workTask, personalTask])
        let (store, _) = makeStore()
        workspace.attachFilterStore(store)
        let filter = SavedFilter(name: "工作", listNames: ["工作"])
        XCTAssertTrue(store.add(filter))

        XCTAssertEqual(workspace.groups(for: .allTasks).flatMap(\.tasks).count, 2)
        workspace.openFilter(filter.id)
        XCTAssertEqual(workspace.activeFilterID, filter.id)
        XCTAssertEqual(workspace.groups(for: .allTasks).flatMap(\.tasks).map(\.id), [workTask.id],
                       "过滤器把个人清单的任务过滤掉，并丢弃变空的分组")
        XCTAssertEqual(workspace.groups(for: .today).flatMap(\.tasks).map(\.id), [workTask.id])
        XCTAssertEqual(workspace.count(for: TaskListScope.today), 1, "当前视图计数应用过滤器")
        XCTAssertEqual(workspace.count(for: NativeDestination.today), 2, "侧栏徽标不受过滤器影响")

        workspace.openFilter(nil)
        XCTAssertNil(workspace.activeFilterID)
        XCTAssertEqual(workspace.groups(for: .allTasks).flatMap(\.tasks).count, 2, "openFilter(nil) 取消过滤")
    }

    func testWorkspaceKeepsMatchedChildrenReachableUnderFilteredParent() throws {
        let parent = makeTask(list: "工作")
        let child = makeTask(list: "工作", tags: ["紧急"], parent: parent)
        let workspace = makeWorkspace(tasks: [parent, child])
        let (store, _) = makeStore()
        workspace.attachFilterStore(store)
        XCTAssertTrue(store.add(makeFilter(tags: ["紧急"])))
        workspace.openFilter(store.filters[0].id)

        let group = try XCTUnwrap(workspace.groups(for: .allTasks).first)
        let ids = workspace.nodes(for: group, scope: .allTasks).map(\.task.id)
        XCTAssertEqual(ids, [parent.id, child.id],
                       "父任务因匹配子任务而保留，子任务通过匹配集继续显示（对齐标签查询的可见性口径）")
    }

    func testWorkspaceClearsActiveFilterWhenFilterIsDeleted() {
        let workspace = makeWorkspace(tasks: [makeTask()])
        let (store, _) = makeStore()
        workspace.attachFilterStore(store)
        XCTAssertTrue(store.add(SavedFilter(name: "临时", dateRange: .today)))
        XCTAssertTrue(store.add(SavedFilter(name: "另一个")))
        let temporary = store.filter(named: "临时")!

        workspace.openFilter(temporary.id)
        XCTAssertTrue(workspace.deleteFilter(temporary.id))
        XCTAssertNil(workspace.activeFilterID, "删除正在使用的过滤器应清空 activeFilterID")
        XCTAssertEqual(store.filters.map(\.name), ["另一个"], "只删除目标过滤器，其余保留")

        XCTAssertTrue(store.add(SavedFilter(name: "临时", dateRange: .today)))
        let again = store.filter(named: "临时")!
        workspace.openFilter(again.id)
        XCTAssertEqual(workspace.activeFilterID, again.id)
        XCTAssertTrue(store.delete(again.id))
        XCTAssertNil(workspace.activeFilterID, "通过 store 直接删除也应通过 $filters 通知清理")
    }
}
