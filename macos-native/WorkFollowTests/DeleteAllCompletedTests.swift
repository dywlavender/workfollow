import XCTest
@testable import WorkFollow

/// 「已完成」视图的「全部删除」：集合口径、软删语义、一步撤销、垃圾桶隔离。
///
/// 这些断言钉的是**行为**，不是实现：无论以后改成批量删除还是别的通道，
/// "删哪些、删到哪、能不能撤回、有没有误伤"都必须还是这几条。
@MainActor
final class DeleteAllCompletedTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("delete-all-completed-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// 建一个可预测的工作空间：`now` 固定，任务清单自己拼。
    private func makeEnvironment(now: Date = Date(timeIntervalSince1970: 1_800_000_000))
        -> AppEnvironment {
        AppEnvironment(clock: { now }, directory: directory)
    }

    /// 建一条任务并立刻完成它。返回任务 id。
    @discardableResult
    private func completedTask(_ workspace: TaskWorkspaceModel, _ title: String,
                               list: String = TaskList.inbox.name) -> UUID {
        let id = workspace.createDraft(title: title, list: list, schedule: TaskSchedule(),
                                       priority: .none, tags: [], reminder: nil,
                                       repeatFrequency: .never).taskID!
        _ = workspace.complete(id)
        return id
    }

    private func completedIDs(_ workspace: TaskWorkspaceModel) -> Set<UUID> {
        Set(workspace.allTasks.filter { $0.status == .completed && $0.deletedAt == nil }.map(\.id))
    }

    func testDeletesEveryCompletedTaskAndLeavesActiveOnesAlone() {
        let workspace = makeEnvironment().taskWorkspace
        let doneA = completedTask(workspace, "完成 A")
        let doneB = completedTask(workspace, "完成 B")
        let active = workspace.createDraft(title: "还在做", list: TaskList.inbox.name,
                                           schedule: TaskSchedule(), priority: .none, tags: [],
                                           reminder: nil, repeatFrequency: .never).taskID!

        XCTAssertEqual(workspace.completedDeletionCount(), 2)
        XCTAssertEqual(workspace.deleteAllCompleted(), 2)

        // 已完成的全进垃圾桶，未完成的原样留在列表里。
        XCTAssertTrue(completedIDs(workspace).isEmpty, "已完成视图应被清空")
        XCTAssertEqual(Set(workspace.deletedTasks.map(\.id)), [doneA, doneB])
        XCTAssertNotNil(workspace.task(for: active))
        XCTAssertNil(workspace.task(for: active)?.deletedAt)
    }

    func testDeleteIsSoftAndUndoableInOneStep() {
        let workspace = makeEnvironment().taskWorkspace
        let ids = (0..<4).map { completedTask(workspace, "完成 \($0)") }
        let before = workspace.allTasks

        XCTAssertEqual(workspace.deleteAllCompleted(), 4)
        XCTAssertEqual(workspace.deletedTasks.count, 4)

        workspace.undo()
        XCTAssertEqual(workspace.allTasks, before, "一次撤销必须把整批还原，不是一条一条退")
        XCTAssertTrue(workspace.deletedTasks.isEmpty)
        XCTAssertEqual(completedIDs(workspace), Set(ids))
    }

    func testAbandonedAndNoteTasksAreNotTouched() {
        let workspace = makeEnvironment().taskWorkspace
        let completed = completedTask(workspace, "完成")
        let abandoned = workspace.createDraft(title: "放弃", list: TaskList.inbox.name,
                                              schedule: TaskSchedule(), priority: .none, tags: [],
                                              reminder: nil, repeatFrequency: .never).taskID!
        _ = workspace.abandon(abandoned)
        // 笔记与任务共用实体；即使状态被改成完成，也不该被「已完成」页的按钮删掉。
        let note = workspace.createNote(title: "一条笔记")!
        _ = workspace.complete(note)

        XCTAssertEqual(workspace.completedDeletionCount(), 1,
                       "已完成投影排除已放弃与笔记，计数必须跟着走")
        XCTAssertEqual(workspace.deleteAllCompleted(), 1)

        XCTAssertNil(workspace.task(for: abandoned)?.deletedAt)
        XCTAssertNil(workspace.task(for: note)?.deletedAt)
        XCTAssertNotNil(workspace.task(for: completed)?.deletedAt)
    }

    func testSavedFilterNarrowsTheDeletionSet() throws {
        let environment = makeEnvironment()
        let workspace = environment.taskWorkspace
        let inWork = completedTask(workspace, "工作项", list: "工作")
        let inStudy = completedTask(workspace, "学习项", list: "学习")

        XCTAssertTrue(environment.filterStore.add(SavedFilter(name: "只看工作", listNames: ["工作"])))
        let filterID = try XCTUnwrap(environment.filterStore.filter(named: "只看工作")?.id)
        workspace.openFilter(filterID)

        // 页头计数与「全部删除」用的是同一份集合：过滤生效后计数就是 1。
        XCTAssertEqual(workspace.count(for: TaskListScope.completed), 1)
        XCTAssertEqual(workspace.deleteAllCompleted(), 1)

        XCTAssertNotNil(workspace.task(for: inWork)?.deletedAt)
        XCTAssertNil(workspace.task(for: inStudy)?.deletedAt,
                     "被过滤器挡在视图外的任务不能跟着一起删")
    }

    func testDeletingParentTakesChildrenAndCountsThem() {
        let workspace = makeEnvironment().taskWorkspace
        let parent = workspace.createDraft(title: "父任务", list: TaskList.inbox.name,
                                           schedule: TaskSchedule(), priority: .none, tags: [],
                                           reminder: nil, repeatFrequency: .never).taskID!
        let child = workspace.createChild(parent, title: "子任务").taskID!
        _ = workspace.complete(child)
        _ = workspace.complete(parent)

        // 父子都已完成：计数是 2，实际进桶的也是 2（子任务随父一起被软删）。
        XCTAssertEqual(workspace.completedDeletionCount(), 2)
        XCTAssertEqual(workspace.deleteAllCompleted(), 2)
        XCTAssertNotNil(workspace.task(for: parent)?.deletedAt)
        XCTAssertNotNil(workspace.task(for: child)?.deletedAt)
    }

    func testEmptyCompletedViewDeletesNothingAndDoesNotPushUndo() {
        let workspace = makeEnvironment().taskWorkspace
        _ = workspace.createDraft(title: "还在做", list: TaskList.inbox.name, schedule: TaskSchedule(),
                                  priority: .none, tags: [], reminder: nil, repeatFrequency: .never)
        let before = workspace.allTasks

        XCTAssertEqual(workspace.completedDeletionCount(), 0)
        XCTAssertEqual(workspace.deleteAllCompleted(), 0)
        XCTAssertEqual(workspace.allTasks, before)

        // 没有改动就不该产生撤销步：空跑一次后按撤销，不能把之前的状态退掉。
        let id = workspace.createDraft(title: "新任务", list: TaskList.inbox.name,
                                       schedule: TaskSchedule(), priority: .none, tags: [],
                                       reminder: nil, repeatFrequency: .never).taskID!
        workspace.undo()
        XCTAssertNil(workspace.task(for: id), "撤销应回到建任务之前")
    }

    func testTaskTrashAndNoteTrashStayIndependent() {
        let workspace = makeEnvironment().taskWorkspace
        let done = completedTask(workspace, "完成")
        let note = workspace.createNote(title: "笔记")!
        _ = workspace.delete(note)

        XCTAssertEqual(workspace.deleteAllCompleted(), 1)
        // 任务垃圾桶只认任务；笔记垃圾桶里的那条不该被算进来。
        XCTAssertEqual(workspace.deletedTasks.map(\.id), [done])
        XCTAssertNotNil(workspace.task(for: note)?.deletedAt)

        workspace.emptyTrash()
        XCTAssertNotNil(workspace.task(for: note), "清空任务垃圾桶不能连笔记一起清掉")
    }
}
