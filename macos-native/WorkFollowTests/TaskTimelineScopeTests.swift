import XCTest
@testable import WorkFollow

@MainActor
final class TaskTimelineScopeTests: XCTestCase {
    func testTimelineIsAvailableForOrdinaryListsAndSavedFilters() {
        XCTAssertEqual(TaskListViewMode.availableOptions(destination: .allTasks, activeList: "工作", activeTag: nil),
                       [.list, .kanban, .timeline])
        XCTAssertEqual(TaskListViewMode.availableOptions(destination: .allTasks, activeList: nil, activeTag: nil, activeFilterID: UUID()),
                       [.list, .kanban, .timeline])
        XCTAssertEqual(TaskListViewMode.availableOptions(destination: .allTasks, activeList: nil, activeTag: nil), [.list, .kanban])
        XCTAssertEqual(TaskListViewMode.availableOptions(destination: .today, activeList: "工作", activeTag: nil), [.list, .kanban])
        XCTAssertEqual(TaskListViewMode.availableOptions(destination: .allTasks, activeList: nil, activeTag: "项目"), [.list, .kanban])
        XCTAssertEqual(TaskListViewMode.availableOptions(destination: .inbox, activeList: nil, activeTag: nil), [.list, .kanban])
    }

    func testEachFilterHasIndependentPreferenceAndUnavailableStoredModeFallsBack() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = TaskViewScopeKey.key(destination: .allTasks, activeList: nil, activeTag: nil, activeFilterID: UUID())
        let second = TaskViewScopeKey.key(destination: .allTasks, activeList: nil, activeTag: nil, activeFilterID: UUID())
        let root = TaskViewScopeKey.key(destination: .allTasks, activeList: nil, activeTag: nil)
        let store = TaskViewPreferenceStore(directory: directory)
        store.setViewMode(.timeline, for: first)
        XCTAssertEqual(store.viewMode(for: first, availableModes: [.list, .kanban, .timeline]), .timeline)
        XCTAssertEqual(store.viewMode(for: first), .list)
        XCTAssertEqual(store.viewMode(for: second, availableModes: [.list, .kanban, .timeline]), .list)
        XCTAssertEqual(store.viewMode(for: root), .list)
    }

    func testProjectionIncludesMatchingChildrenAndUsesSameFilterForUnscheduledPool() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func task(_ title: String, parent: UUID? = nil, tags: [String] = [], due: Date? = nil, list: TaskList = TaskList(name: "工作")) -> Task {
            Task(id: UUID(), title: title, tags: tags, list: list, priority: .none,
                 schedule: TaskSchedule(dueAt: due), parentID: parent, childOrder: 0, createdAt: now, updatedAt: now)
        }
        let parent = task("仅用于树形上下文")
        let child = task("匹配子任务", parent: parent.id, tags: ["项目"], due: now)
        let unplanned = task("待安排", tags: ["项目"])
        let otherList = task("其他清单", tags: ["项目"], list: .inbox)
        var closed = task("已完成", tags: ["项目"], due: now)
        closed.status = .completed
        let filter = SavedFilter(name: "高级标签", expression: .condition(FilterCondition(kind: .tags,
            organizationSelections: [FilterOrganizationSelection(name: "项目")])))
        let source = [parent, child, unplanned, otherList, closed]
        let result = TaskTimelineProjection.tasks(in: .allTasks, source: source, now: now,
            calendar: Calendar(identifier: .gregorian), query: TaskListQuery(list: "工作"),
            filter: filter, hidesCompleted: true)
        XCTAssertEqual(result.map(\.id), [child.id, unplanned.id])
        XCTAssertEqual(result.filter { $0.schedule.dueAt == nil }.map(\.id), [unplanned.id])
        XCTAssertEqual(source[0], parent)
    }
}
