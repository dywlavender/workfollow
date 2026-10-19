import Combine
import Foundation
import XCTest
@testable import WorkFollow

@MainActor
final class TaskTagDirectoryTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 28_800)!
        return value
    }
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 12))!
    }

    private func task(_ title: String = "标签任务", tags: [String] = []) -> Task {
        Task(id: UUID(), title: title, tags: tags, list: .inbox, priority: .none,
             schedule: TaskSchedule(dueAt: now), parentID: nil, childOrder: 0,
             createdAt: now, updatedAt: now)
    }

    private func workspace(_ tasks: [Task] = [], tags: [TaskTag]? = nil) -> TaskWorkspaceModel {
        TaskWorkspaceModel(clock: { self.now }, calendar: calendar, seedDemoData: false,
                           initialTasks: tasks, initialTags: tags)
    }

    func testTagCodableKeepsIdentityAndDefaultsOptionalMetadata() throws {
        let id = UUID()
        let data = try JSONSerialization.data(withJSONObject: ["id": id.uuidString, "name": "工作"])
        let tag = try JSONDecoder().decode(TaskTag.self, from: data)
        XCTAssertEqual(tag, TaskTag(id: id, name: "工作"))
        let parent = UUID()
        let styled = TaskTag(id: id, name: "工作", colorARGB: 0xFF123456, sortOrder: 3, parentID: parent)
        XCTAssertEqual(try JSONDecoder().decode(TaskTag.self, from: JSONEncoder().encode(styled)), styled)
    }

    func testEmptyTagCreationAndColorUndoRedoDoNotPublishTaskChanges() throws {
        let workspace = workspace()
        var taskEvents = 0
        let subscription = workspace.taskChanges.sink { _ in taskEvents += 1 }
        defer { subscription.cancel() }
        let initialRevision = workspace.revision
        let id = try XCTUnwrap(workspace.createTag(" #空标签# "))
        XCTAssertEqual(workspace.tagNames, ["空标签"])
        XCTAssertEqual(workspace.tag(for: id)?.id, id)
        XCTAssertTrue(workspace.setTagColor(id, colorARGB: 0xFF61A559))
        XCTAssertEqual(workspace.tag(for: id)?.colorARGB, 0xFF61A559)
        XCTAssertEqual(workspace.revision, initialRevision + 2)
        XCTAssertTrue(workspace.allTasks.isEmpty)
        XCTAssertEqual(taskEvents, 0)

        workspace.undo()
        XCTAssertNil(workspace.tag(for: id)?.colorARGB)
        workspace.undo()
        XCTAssertTrue(workspace.taskTags.isEmpty)
        XCTAssertFalse(workspace.canUndo)
        workspace.redo()
        XCTAssertEqual(workspace.tag(named: "空标签")?.id, id)
        workspace.redo()
        XCTAssertEqual(workspace.tag(for: id)?.colorARGB, 0xFF61A559)
        XCTAssertEqual(taskEvents, 0)
    }

    func testTaskAssignmentCreatesDirectoryInTheSameUndoStepAndLastUseCanBeRemoved() throws {
        let source = task()
        let workspace = workspace([source])
        let original = workspace.allTasks
        workspace.setTags(source.id, ["新增标签"])
        let tag = try XCTUnwrap(workspace.tag(named: "新增标签"))
        XCTAssertEqual(workspace.task(for: source.id)?.tagReferences,
                       [TaskTagReference(id: tag.id, name: tag.name)])
        workspace.undo()
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertTrue(workspace.taskTags.isEmpty)
        XCTAssertFalse(workspace.canUndo)
        workspace.redo()
        XCTAssertEqual(workspace.tag(named: "新增标签")?.id, tag.id)
        workspace.setTags(source.id, [])
        XCTAssertEqual(workspace.tag(named: "新增标签"), tag)
        XCTAssertEqual(workspace.task(for: source.id)?.tags, [])
    }

    func testLegacyTaskAndSeriesReferencesSeedDirectoryWithoutChangingIDs() throws {
        let taskTag = TaskTagReference(id: UUID(), name: "已有标签")
        let templateTag = TaskTagReference(id: UUID(), name: "模板专用")
        var source = task(tags: [taskTag.name])
        source.tagReferences = [taskTag]
        source.recurrence = .daily
        var series = TaskSeries(task: source, calendar: calendar, now: now)
        series.template.tags = [templateTag.name]
        series.template.tagReferences = [templateTag]
        source.series = series
        let workspace = workspace([source])

        XCTAssertEqual(workspace.tag(named: taskTag.name)?.id, taskTag.id)
        XCTAssertEqual(workspace.tag(named: templateTag.name)?.id, templateTag.id)
        XCTAssertEqual(workspace.task(for: source.id)?.tagReferences, [taskTag])
        XCTAssertEqual(workspace.task(for: source.id)?.series?.template.tagReferences, [templateTag])
        XCTAssertFalse(workspace.canUndo)
    }

    func testExplicitDirectoryIdentityAndMetadataTakePriorityDuringHydration() {
        let tag = TaskTag(name: "项目", colorARGB: 0xFFAF6655, sortOrder: 7)
        var source = task(tags: [tag.name])
        source.tagReferences = [TaskTagReference(id: UUID(), name: tag.name)]
        let workspace = workspace([source], tags: [tag])

        XCTAssertEqual(workspace.taskTags, [tag])
        XCTAssertEqual(workspace.tagReferenceID(for: tag.name), tag.id)
        XCTAssertEqual(workspace.task(for: source.id)?.tagReferences,
                       [TaskTagReference(id: tag.id, name: tag.name)])
    }

    func testRenameKeepsPrimaryPositionReferencesAndSeriesTemplateInOneUndoStep() throws {
        var source = task(tags: ["主标签", "次标签"])
        source.recurrence = .daily
        let workspace = workspace([source])
        let original = workspace.allTasks
        let originalReferences = try XCTUnwrap(workspace.task(for: source.id)?.tagReferences)
        let id = try XCTUnwrap(workspace.tag(named: "主标签")?.id)
        workspace.activeTag = "主标签"

        XCTAssertTrue(workspace.renameTag(id, to: "交付"))
        XCTAssertEqual(workspace.task(for: source.id)?.tags, ["交付", "次标签"])
        XCTAssertEqual(workspace.task(for: source.id)?.tagReferences?.map(\.id), originalReferences.map(\.id))
        XCTAssertEqual(workspace.task(for: source.id)?.series?.template.tags, ["交付", "次标签"])
        XCTAssertEqual(workspace.activeTag, "交付")
        let renamed = workspace.allTasks
        workspace.undo()
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertEqual(workspace.activeTag, "主标签")
        XCTAssertFalse(workspace.canUndo)
        workspace.redo()
        XCTAssertEqual(workspace.allTasks, renamed)
        XCTAssertEqual(workspace.tag(named: "交付")?.id, id)
    }

    func testEmptyTagRenameUpdatesFilterAndViewScopeThroughUndoRedo() throws {
        let tag = TaskTag(name: "空标签")
        let workspace = workspace(tags: [tag])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let filters = FilterStore(directory: directory)
        workspace.attachFilterStore(filters)
        XCTAssertTrue(filters.add(SavedFilter(name: "空标签视图", tags: [tag.name])))
        let preferences = TaskViewPreferenceStore(directory: directory)
        preferences.setViewMode(.kanban, for: "tag:空标签")
        workspace.activeTag = tag.name

        XCTAssertTrue(workspace.renameTag(tag.id, to: "等待"))
        XCTAssertEqual(filters.filters.first?.tags, ["等待"])
        XCTAssertEqual(filters.filters.first?.tagIDs, [tag.id])
        XCTAssertEqual(preferences.viewMode(for: "tag:等待"), .kanban)
        XCTAssertEqual(workspace.activeTag, "等待")
        workspace.undo()
        XCTAssertEqual(filters.filters.first?.tags, [tag.name])
        XCTAssertEqual(preferences.viewMode(for: "tag:空标签"), .kanban)
        XCTAssertEqual(workspace.activeTag, tag.name)
        XCTAssertFalse(workspace.canUndo)
        workspace.redo()
        XCTAssertEqual(filters.filters.first?.tags, ["等待"])
        XCTAssertEqual(filters.filters.first?.tagIDs, [tag.id])
    }

    func testColorReparentAndSiblingOrderParticipateInOneTransaction() throws {
        let first = TaskTag(name: "甲", sortOrder: 0)
        let last = TaskTag(name: "乙", sortOrder: 1)
        let child = TaskTag(name: "子", parentID: first.id)
        let store = WorkspaceStore()
        store.commit([], tags: [first, last, child]); store.clearUndo()
        let actions = TaskActions(store: store, clock: { self.now })
        let original = store.tags
        store.transaction {
            XCTAssertTrue(actions.setTagColor(first.id, colorARGB: 0xFF447799))
            XCTAssertTrue(actions.reparentTag(child.id, parentID: last.id))
            XCTAssertTrue(actions.reorderTag(last.id, before: first.id))
        }
        XCTAssertEqual(TaskTag.ordered(store.tags).map(\.id), [last.id, child.id, first.id])
        XCTAssertEqual(store.tag(child.id)?.parentID, last.id)
        XCTAssertEqual(store.tag(first.id)?.colorARGB, 0xFF447799)
        let changed = store.tags
        actions.undo()
        XCTAssertEqual(store.tags, original)
        XCTAssertFalse(store.canUndo)
        actions.redo()
        XCTAssertEqual(store.tags, changed)
    }

    func testSaveTagCreatesCompleteRecordAndUnchangedSaveAddsNoHistory() throws {
        let parent = TaskTag(name: "项目")
        let workspace = workspace(tags: [parent])
        let initialRevision = workspace.revision
        var taskEvents = 0
        let subscription = workspace.taskChanges.sink { _ in taskEvents += 1 }
        defer { subscription.cancel() }

        let id = try XCTUnwrap(workspace.saveTag(name: " #交付# ", colorARGB: 0xFF559988, parentID: parent.id))
        let created = try XCTUnwrap(workspace.tag(for: id))
        XCTAssertEqual(created.name, "交付")
        XCTAssertEqual(created.colorARGB, 0xFF559988)
        XCTAssertEqual(created.parentID, parent.id)
        XCTAssertEqual(workspace.revision, initialRevision + 1)
        XCTAssertEqual(workspace.saveTag(id, name: created.name, colorARGB: created.colorARGB, parentID: parent.id), id)
        XCTAssertEqual(workspace.revision, initialRevision + 1)
        XCTAssertEqual(taskEvents, 0)
        workspace.undo()
        XCTAssertEqual(workspace.taskTags, [parent])
        XCTAssertFalse(workspace.canUndo)
        workspace.redo()
        XCTAssertEqual(workspace.tag(for: id), created)
    }

    func testSaveTagEditsNameColorAndParentWithOnePublicationRevisionAndUndo() throws {
        let parent = TaskTag(name: "项目")
        let tag = TaskTag(name: "原名", colorARGB: 0xFF112233, sortOrder: 1)
        let source = task(tags: [tag.name, parent.name])
        let workspace = workspace([source], tags: [parent, tag])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let filters = FilterStore(directory: directory)
        workspace.attachFilterStore(filters)
        XCTAssertTrue(filters.add(SavedFilter(name: "关联过滤器", tags: [tag.name])))
        let originalTasks = workspace.allTasks
        let originalTags = workspace.taskTags
        let initialRevision = workspace.revision
        var taskEvents = 0
        let subscription = workspace.taskChanges.sink { _ in taskEvents += 1 }
        defer { subscription.cancel() }

        XCTAssertEqual(workspace.saveTag(tag.id, name: "交付", colorARGB: 0xFF559988, parentID: parent.id), tag.id)
        XCTAssertEqual(workspace.tag(for: tag.id)?.name, "交付")
        XCTAssertEqual(workspace.tag(for: tag.id)?.colorARGB, 0xFF559988)
        XCTAssertEqual(workspace.tag(for: tag.id)?.parentID, parent.id)
        XCTAssertEqual(workspace.task(for: source.id)?.tags, ["交付", parent.name])
        XCTAssertEqual(workspace.task(for: source.id)?.tagReferences?.first?.id, tag.id)
        XCTAssertEqual(filters.filters.first?.tags, ["交付"])
        XCTAssertEqual(workspace.revision, initialRevision + 1)
        XCTAssertEqual(taskEvents, 1)
        let changedTasks = workspace.allTasks
        let changedTags = workspace.taskTags
        workspace.undo()
        XCTAssertEqual(workspace.allTasks, originalTasks)
        XCTAssertEqual(workspace.taskTags, originalTags)
        XCTAssertEqual(filters.filters.first?.tags, [tag.name])
        XCTAssertFalse(workspace.canUndo)
        workspace.redo()
        XCTAssertEqual(workspace.allTasks, changedTasks)
        XCTAssertEqual(workspace.taskTags, changedTags)
    }

    func testSaveTagValidatesWholeDraftBeforeWritingAnyField() {
        let tag = TaskTag(name: "原名", colorARGB: 0xFF112233)
        let child = TaskTag(name: "子标签", parentID: tag.id)
        let other = TaskTag(name: "另一个标签", sortOrder: 1)
        let source = task(tags: [tag.name])
        let workspace = workspace([source], tags: [tag, child, other])
        let originalTasks = workspace.allTasks
        let originalTags = workspace.taskTags
        let initialRevision = workspace.revision
        var taskEvents = 0
        let subscription = workspace.taskChanges.sink { _ in taskEvents += 1 }
        defer { subscription.cancel() }

        XCTAssertNil(workspace.saveTag(tag.id, name: "新名", colorARGB: 0xFF559988, parentID: child.id))
        XCTAssertNil(workspace.saveTag(tag.id, name: other.name, colorARGB: 0xFF559988, parentID: other.id))
        XCTAssertEqual(workspace.allTasks, originalTasks)
        XCTAssertEqual(workspace.taskTags, originalTags)
        XCTAssertEqual(workspace.revision, initialRevision)
        XCTAssertEqual(taskEvents, 0)
        XCTAssertFalse(workspace.canUndo)
    }

    func testHierarchyRejectsCyclesAndReorderingCannotChangeParent() {
        let root = TaskTag(name: "根")
        let child = TaskTag(name: "子", parentID: root.id)
        let descendant = TaskTag(name: "孙", parentID: child.id)
        let workspace = workspace(tags: [root, child, descendant])
        let original = workspace.taskTags
        let revision = workspace.revision

        XCTAssertFalse(workspace.reparentTag(root.id, parentID: descendant.id))
        XCTAssertFalse(workspace.reparentTag(child.id, parentID: child.id))
        XCTAssertFalse(workspace.reorderTag(child.id, before: root.id))
        XCTAssertFalse(workspace.setTagColor(root.id, colorARGB: nil))
        XCTAssertFalse(workspace.reorderTag(child.id, before: nil))
        XCTAssertEqual(workspace.taskTags, original)
        XCTAssertEqual(workspace.revision, revision)
        XCTAssertFalse(workspace.canUndo)
    }

    func testGlobalNamesStayUniqueAndCaseSensitiveAcrossParents() throws {
        let workspace = workspace()
        let root = try XCTUnwrap(workspace.createTag("项目"))
        let child = try XCTUnwrap(workspace.createTag("子标签", parentID: root))
        XCTAssertNil(workspace.createTag(" #项目# ", parentID: root))
        XCTAssertFalse(workspace.renameTag(child, to: "项目"))
        XCTAssertNotNil(workspace.createTag("Work"))
        XCTAssertNotNil(workspace.createTag("work"))
        XCTAssertEqual(workspace.tagNames, ["项目", "子标签", "Work", "work"].sorted())
    }

    func testDeletePromotesChildrenInPlaceAndRemovesTaskAndTemplateReferences() throws {
        let root = TaskTag(name: "组")
        let first = TaskTag(name: "前", sortOrder: 0, parentID: root.id)
        let parent = TaskTag(name: "父", sortOrder: 1, parentID: root.id)
        let last = TaskTag(name: "后", sortOrder: 2, parentID: root.id)
        let child = TaskTag(name: "子甲", sortOrder: 0, parentID: parent.id)
        let otherChild = TaskTag(name: "子乙", sortOrder: 1, parentID: parent.id)
        let descendant = TaskTag(name: "孙", parentID: child.id)
        var source = task(tags: [first.name, parent.name, child.name])
        source.recurrence = .daily
        let workspace = workspace([source], tags: [root, first, parent, last, child, otherChild, descendant])
        let originalTasks = workspace.allTasks
        let originalTags = workspace.taskTags
        workspace.activeTag = parent.name

        XCTAssertTrue(workspace.removeTag(parent.id))
        XCTAssertNil(workspace.tag(for: parent.id))
        XCTAssertEqual(workspace.tag(for: child.id)?.parentID, root.id)
        XCTAssertEqual(workspace.tag(for: otherChild.id)?.parentID, root.id)
        XCTAssertEqual(workspace.tag(for: descendant.id)?.parentID, child.id)
        XCTAssertEqual(workspace.orderedTags.map(\.name), ["组", "前", "子甲", "孙", "子乙", "后"])
        XCTAssertEqual(workspace.task(for: source.id)?.tags, [first.name, child.name])
        XCTAssertEqual(workspace.task(for: source.id)?.tagReferences?.map(\.id), [first.id, child.id])
        XCTAssertEqual(workspace.task(for: source.id)?.series?.template.tags, [first.name, child.name])
        XCTAssertNil(workspace.activeTag)
        let changedTasks = workspace.allTasks
        let changedTags = workspace.taskTags
        workspace.undo()
        XCTAssertEqual(workspace.allTasks, originalTasks)
        XCTAssertEqual(workspace.taskTags, originalTags)
        XCTAssertFalse(workspace.canUndo)
        workspace.redo()
        XCTAssertEqual(workspace.allTasks, changedTasks)
        XCTAssertEqual(workspace.taskTags, changedTags)
    }

    func testTemplateAndDuplicateAssignmentsUseTheExistingDirectoryIdentity() throws {
        let tag = TaskTag(name: "模板标签")
        let workspace = workspace(tags: [tag])
        let template = TaskTemplate(name: "模板", title: "模板任务", tags: [tag.name], createdAt: now)
        let id = try XCTUnwrap(workspace.createFromTemplate(template))
        XCTAssertEqual(workspace.task(for: id)?.tagReferences, [TaskTagReference(id: tag.id, name: tag.name)])
        workspace.duplicate(id)
        XCTAssertEqual(workspace.allTasks.count, 2)
        XCTAssertTrue(workspace.allTasks.allSatisfy { $0.tagReferences == [TaskTagReference(id: tag.id, name: tag.name)] })
        XCTAssertEqual(workspace.taskTags, [tag])
    }
}
