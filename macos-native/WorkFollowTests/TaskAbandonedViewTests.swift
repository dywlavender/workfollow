import XCTest
@testable import WorkFollow

final class TaskAbandonedViewTests: XCTestCase {
    func testAbandonRestoreAndHistoryKeepDedicatedViewsAndBadgesConsistent() async throws {
        try await MainActor.run {
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let model = TaskWorkspaceModel(clock: { now }, seedDemoData: false)
            let abandonedID = try XCTUnwrap(model.createTask(title: "取消本次发布", in: .today).taskID)
            let completedID = try XCTUnwrap(model.createTask(title: "完成需求评审", in: .today).taskID)
            _ = model.changeStatus(try XCTUnwrap(model.task(for: completedID)))
            _ = model.abandon(abandonedID)

            XCTAssertEqual(TaskWorkspaceModel.scope(for: .abandoned), .abandoned)
            XCTAssertEqual(model.count(for: NativeDestination.abandoned), 1)
            XCTAssertEqual(model.count(for: NativeDestination.completed), 1)
            XCTAssertEqual(model.groups(for: .abandoned).flatMap(\.tasks).map(\.id), [abandonedID])
            XCTAssertEqual(model.groups(for: .completed).flatMap(\.tasks).map(\.id), [completedID])
            XCTAssertEqual(Set(model.groups(for: .allTasks).flatMap(\.tasks).map(\.id)), [abandonedID, completedID])

            _ = model.changeStatus(try XCTUnwrap(model.task(for: abandonedID)))
            XCTAssertEqual(model.count(for: NativeDestination.abandoned), 0)
            XCTAssertEqual(model.count(for: TaskListScope.today), 1)
            XCTAssertTrue(model.groups(for: .abandoned).isEmpty)
            model.undo()
            XCTAssertEqual(model.count(for: NativeDestination.abandoned), 1)
            XCTAssertEqual(model.count(for: TaskListScope.today), 0)
            model.redo()
            XCTAssertEqual(model.count(for: NativeDestination.abandoned), 0)
            XCTAssertEqual(model.count(for: NativeDestination.completed), 1)
        }
    }

    func testAbandonedPageGroupsByCloseDateAndRevealsSearchResult() async throws {
        try await MainActor.run {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
            var now = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
            let model = TaskWorkspaceModel(clock: { now }, calendar: calendar, seedDemoData: false)
            let first = try XCTUnwrap(model.createTask(title: "取消发布一", in: .inbox).taskID)
            _ = model.abandon(first)
            now = calendar.date(byAdding: .day, value: 1, to: now)!
            let second = try XCTUnwrap(model.createTask(title: "取消发布二", in: .inbox).taskID)
            _ = model.abandon(second)

            let groups = model.groups(for: .abandoned, hidesCompleted: true)
            XCTAssertEqual(groups.flatMap(\.tasks).map(\.id), [second, first])
            XCTAssertEqual(groups.count, 2)
            let searched = model.groups(for: .abandoned, query: TaskListQuery(search: "发布一"))
            XCTAssertEqual(searched.flatMap(\.tasks).map(\.id), [first])
            var folding = TaskGroupExpansionState()
            folding.toggle(try XCTUnwrap(searched.first))
            folding.reveal(try XCTUnwrap(model.task(for: first)), in: .abandoned, calendar: calendar)
            XCTAssertFalse(folding.isCollapsed(try XCTUnwrap(searched.first)))
        }
    }

    func testLeavingSavedFilterShowsTheWholeCompletedOrAbandonedView() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("task-state-navigation-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            try NativePreviewRepository(directory: directory).save(NativeWorkspaceSnapshot(tasks: [], notes: []))
            let environment = AppEnvironment(directory: directory)
            let model = environment.taskWorkspace
            let abandoned = try XCTUnwrap(model.createTask(title: "取消旧计划", in: .inbox).taskID)
            _ = model.abandon(abandoned)
            let completed = try XCTUnwrap(model.createTask(title: "完成当前计划", in: .inbox).taskID)
            _ = model.complete(completed)
            let filter = SavedFilter(name: "本周重点", tags: ["重点"])
            XCTAssertTrue(environment.filterStore.add(filter))

            for destination in [NativeDestination.completed, .abandoned] {
                model.openFilter(filter.id)
                let scope = try XCTUnwrap(TaskWorkspaceModel.scope(for: destination))
                XCTAssertTrue(model.groups(for: scope).isEmpty)
                environment.navigate(to: destination)
                XCTAssertNil(model.activeFilterID)
                XCTAssertEqual(environment.navigation.destination, destination)
                let expected = destination == .completed ? completed : abandoned
                XCTAssertEqual(model.groups(for: scope).flatMap(\.tasks).map(\.id), [expected])
            }
            XCTAssertEqual(environment.filterStore.filters.map(\.id), [filter.id],
                           "切换页面只清除活动筛选，不删除保存的过滤器")
        }
    }

}
