import XCTest
@testable import WorkFollow

final class TaskTemplateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Codable round trip

    func testTemplateCodableRoundTripPreservesAllFields() throws {
        let template = TaskTemplate(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            name: "周会准备",
            title: "准备周会材料",
            document: NativeDocument(plainText: "第一段\n第二段"),
            tags: ["工作", "周会"],
            listName: "工作",
            priority: .high,
            schedule: .nextMonday,
            childTitles: ["收集议题", "预定会议室"],
            createdAt: now)
        let data = try JSONEncoder().encode(template)
        XCTAssertEqual(try JSONDecoder().decode(TaskTemplate.self, from: data), template)
    }

    func testTemplateDecodingFillsNeutralDefaultsForMissingKeys() throws {
        let data = Data(#"{"name":"只有名字"}"#.utf8)
        let template = try JSONDecoder().decode(TaskTemplate.self, from: data)
        XCTAssertEqual(template.name, "只有名字")
        XCTAssertEqual(template.title, "")
        // DocumentBlock 自带随机 id，按语义文本比较而不是 Equatable。
        XCTAssertEqual(template.document.plainText, "")
        XCTAssertEqual(template.tags, [])
        XCTAssertNil(template.listName)
        XCTAssertNil(template.priority)
        XCTAssertNil(template.schedule)
        XCTAssertEqual(template.childTitles, [])
    }

    // MARK: - Save semantics

    func testSaveCapturesTaskContentAndChildTitlesInChildOrder() async throws {
        let directory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let store = TemplateStore(clock: { self.now }, directory: directory)
            let parent = Self.makeTask(title: "  发布周报  ", list: TaskList(name: "工作"),
                                       document: NativeDocument(plainText: "数据看板链接"),
                                       tags: ["工作"], priority: .high,
                                       schedule: TaskSchedule(dueAt: Self.nextMonday(after: self.now)))
            let lateChild = Self.makeChild(of: parent, title: "收集议题", order: 1)
            let earlyChild = Self.makeChild(of: parent, title: "预定会议室", order: 0)

            XCTAssertTrue(store.save(name: " 周报模板 ", from: parent,
                                     includingChildren: [lateChild, earlyChild]))
            let template = try XCTUnwrap(store.template(named: "周报模板"))
            XCTAssertEqual(template.name, "周报模板")
            XCTAssertEqual(template.title, "发布周报")
            XCTAssertEqual(template.document.plainText, "数据看板链接")
            XCTAssertEqual(template.tags, ["工作"])
            XCTAssertEqual(template.listName, "工作")
            XCTAssertEqual(template.priority, .high)
            XCTAssertEqual(template.schedule, .nextMonday)
            XCTAssertEqual(template.childTitles, ["预定会议室", "收集议题"])
            XCTAssertEqual(template.createdAt, self.now)
        }
    }

    func testSaveNormalizesInboxNonePriorityAndUnscheduledTasks() async throws {
        let directory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let store = TemplateStore(clock: { self.now }, directory: directory)
            XCTAssertTrue(store.save(name: "随手记", from: Self.makeTask(title: "随手记")))
            let template = try XCTUnwrap(store.template(named: "随手记"))
            XCTAssertNil(template.listName)
            XCTAssertNil(template.priority)
            XCTAssertNil(template.schedule)
            XCTAssertEqual(template.childTitles, [])
        }
    }

    func testSaveRejectsDuplicateNameUnlessForced() async throws {
        let directory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let store = TemplateStore(clock: { self.now }, directory: directory)
            XCTAssertTrue(store.save(name: "站会", from: Self.makeTask(title: "第一次")))
            XCTAssertTrue(store.save(name: "Standup", from: Self.makeTask(title: "English")))
            XCTAssertEqual(store.templates.count, 2)

            // The same name (ignoring surrounding spaces and letter case) is
            // rejected without force, leaving the stored template untouched.
            XCTAssertFalse(store.save(name: " 站会 ", from: Self.makeTask(title: "第二次")))
            XCTAssertFalse(store.save(name: "standup", from: Self.makeTask(title: "Other")))
            XCTAssertEqual(store.templates.count, 2)
            XCTAssertEqual(store.template(named: "站会")?.title, "第一次")
            XCTAssertEqual(store.template(named: "Standup")?.title, "English")

            // Empty names are rejected outright.
            XCTAssertFalse(store.save(name: "   ", from: Self.makeTask(title: "占位")))
            XCTAssertEqual(store.templates.count, 2)

            // Forced replace overwrites the content in place.
            XCTAssertTrue(store.save(name: "站会", from: Self.makeTask(title: "替换后的标题",
                                                                     list: TaskList(name: "工作")),
                                     forceReplace: true))
            XCTAssertEqual(store.templates.count, 2)
            XCTAssertEqual(store.template(named: "站会")?.title, "替换后的标题")
            XCTAssertEqual(store.template(named: "站会")?.listName, "工作")
        }
    }

    func testRenameHandlesConflictsAndResorting() async throws {
        let directory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let store = TemplateStore(clock: { self.now }, directory: directory)
            XCTAssertTrue(store.save(name: "B模板", from: Self.makeTask(title: "b")))
            XCTAssertTrue(store.save(name: "A模板", from: Self.makeTask(title: "a")))
            XCTAssertEqual(store.templates.map(\.name), ["A模板", "B模板"])

            let bID = try XCTUnwrap(store.template(named: "B模板")).id
            let aID = try XCTUnwrap(store.template(named: "A模板")).id

            // Renaming onto an existing name, to an empty name, or an unknown
            // id is rejected without any change.
            XCTAssertFalse(store.rename(bID, to: "A模板"))
            XCTAssertFalse(store.rename(bID, to: "   "))
            XCTAssertFalse(store.rename(UUID(), to: "C模板"))
            XCTAssertEqual(store.templates.map(\.name), ["A模板", "B模板"])

            // Keeping its own name (case-insensitively) is allowed.
            XCTAssertTrue(store.rename(bID, to: "b模板"))

            // A unique rename re-sorts the published list.
            XCTAssertTrue(store.rename(aID, to: "C模板"))
            XCTAssertEqual(store.templates.map(\.name), ["b模板", "C模板"])
        }
    }

    // MARK: - Schedule offsets

    func testScheduleOffsetResolutionAndMatching() {
        let start = Calendar.current.startOfDay(for: now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let nextMonday = Self.nextMonday(after: now)

        XCTAssertNil(TaskTemplateScheduleOffset.none.date(from: now, calendar: .current))
        XCTAssertEqual(TaskTemplateScheduleOffset.today.date(from: now, calendar: .current), start)
        XCTAssertEqual(TaskTemplateScheduleOffset.tomorrow.date(from: now, calendar: .current), tomorrow)
        XCTAssertEqual(TaskTemplateScheduleOffset.nextMonday.date(from: now, calendar: .current), nextMonday)

        XCTAssertNil(TaskTemplateScheduleOffset.match(nil, against: now, calendar: .current))
        XCTAssertEqual(TaskTemplateScheduleOffset.match(start, against: now, calendar: .current), .today)
        XCTAssertEqual(TaskTemplateScheduleOffset.match(nextMonday, against: now, calendar: .current), .nextMonday)
        XCTAssertNil(TaskTemplateScheduleOffset.match(Self.unrepresentableDay(after: now),
                                                      against: now, calendar: .current))
        // Tomorrow only maps to .tomorrow when that day is not already Monday.
        let tomorrowOffset = TaskTemplateScheduleOffset.match(tomorrow, against: now, calendar: .current)
        if Calendar.current.component(.weekday, from: tomorrow) == 2 {
            XCTAssertEqual(tomorrowOffset, .nextMonday)
        } else {
            XCTAssertEqual(tomorrowOffset, .tomorrow)
        }
    }

    // MARK: - Applying through the workspace action path

    func testApplyCreatesTaskWithTemplateContentAndSelectsIt() async throws {
        let directory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let anchor = Self.makeTask(title: "占位", list: TaskList(name: "工作"))
            let model = TaskWorkspaceModel(clock: { self.now }, seedDemoData: false,
                                           initialTasks: [anchor])
            let store = TemplateStore(clock: { self.now }, directory: directory)
            let parent = Self.makeTask(title: "发布周报", list: TaskList(name: "工作"),
                                       document: NativeDocument(plainText: "链接见正文"),
                                       tags: ["工作"], priority: .high,
                                       schedule: TaskSchedule(dueAt: Self.nextMonday(after: self.now)))
            XCTAssertTrue(store.save(name: "周报模板", from: parent, includingChildren: [
                Self.makeChild(of: parent, title: "收集议题", order: 1),
                Self.makeChild(of: parent, title: "预定会议室", order: 0)
            ]))

            let template = try XCTUnwrap(store.apply(name: "周报模板"))
            let createdID = try XCTUnwrap(TemplateApplier.apply(template, to: model))
            XCTAssertEqual(model.selectedTaskID, createdID)

            let created = try XCTUnwrap(model.task(for: createdID))
            XCTAssertEqual(created.title, "发布周报")
            XCTAssertEqual(created.document.plainText, "链接见正文")
            XCTAssertEqual(created.tags, ["工作"])
            XCTAssertEqual(created.priority, .high)
            XCTAssertEqual(created.list, TaskList(name: "工作"))
            XCTAssertEqual(created.schedule.dueAt, Self.nextMonday(after: self.now))
            XCTAssertFalse(created.schedule.hasTime)
            XCTAssertEqual(created.status, .active)
            XCTAssertNil(created.reminderAt)
            XCTAssertEqual(created.recurrence, .never)

            let children = model.allTasks
                .filter { $0.parentID == createdID }
                .sorted { $0.childOrder < $1.childOrder }
            XCTAssertEqual(children.map(\.title), ["预定会议室", "收集议题"])

            XCTAssertNil(store.apply(name: "不存在的模板"))
        }
    }

    func testApplyFallsBackToInboxWhenTemplateListIsMissing() async throws {
        try await MainActor.run {
            let model = TaskWorkspaceModel(seedDemoData: false)
            var template = TaskTemplate(name: "自由模板", title: "随手记", createdAt: now)
            template.listName = "已消失的清单"
            let createdID = try XCTUnwrap(TemplateApplier.apply(template, to: model))
            let created = try XCTUnwrap(model.task(for: createdID))
            XCTAssertEqual(created.list, TaskList.inbox)
            XCTAssertNil(created.schedule.dueAt)
            XCTAssertEqual(model.selectedTaskID, createdID)
        }
    }

    // MARK: - Persistence

    func testFlushPersistsArchiveToInjectedDirectory() async throws {
        let directory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store: TemplateStore = try await MainActor.run {
            let store = TemplateStore(clock: { self.now }, directory: directory)
            let parent = Self.makeTask(title: "乙", list: TaskList(name: "个人"))
            XCTAssertTrue(store.save(name: "模板甲", from: Self.makeTask(title: "甲")))
            XCTAssertTrue(store.save(name: "模板乙", from: parent, includingChildren: [
                Self.makeChild(of: parent, title: "子步骤", order: 0)
            ]))
            return store
        }
        let flushed = expectation(description: "templates flushed")
        await MainActor.run {
            store.flush { error in
                XCTAssertNil(error)
                flushed.fulfill()
            }
        }
        await fulfillment(of: [flushed], timeout: 5)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("templates.json").path))

        let (first, second) = try await MainActor.run {
            let reloaded = TemplateStore(clock: { self.now }, directory: directory)
            return (reloaded.template(named: "模板甲"), reloaded.template(named: "模板乙"))
        }
        XCTAssertEqual(first?.title, "甲")
        XCTAssertEqual(second?.listName, "个人")
        XCTAssertEqual(second?.childTitles, ["子步骤"])
    }

    // MARK: - Helpers

    private static func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskTemplateTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func makeTask(id: UUID = UUID(), title: String,
                                 list: TaskList = .inbox,
                                 document: NativeDocument = .empty,
                                 tags: [String] = [],
                                 priority: TaskPriority = .none,
                                 schedule: TaskSchedule = TaskSchedule()) -> Task {
        let stamp = Date(timeIntervalSince1970: 1_000_000)
        return Task(id: id, title: title, document: document, tags: tags,
                    list: list, priority: priority, schedule: schedule,
                    parentID: nil, childOrder: 0, createdAt: stamp, updatedAt: stamp)
    }

    private static func makeChild(of parent: Task, title: String, order: Int) -> Task {
        Task(id: UUID(), title: title, list: parent.list, priority: .none,
             schedule: TaskSchedule(), parentID: parent.id, childOrder: order,
             createdAt: parent.createdAt, updatedAt: parent.createdAt)
    }

    private static func nextMonday(after date: Date, calendar: Calendar = .current) -> Date {
        var day = calendar.startOfDay(for: date)
        repeat {
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        } while calendar.component(.weekday, from: day) != 2
        return day
    }

    private static func unrepresentableDay(after date: Date, calendar: Calendar = .current) -> Date {
        for offset in 2...6 {
            let candidate = calendar.date(byAdding: .day, value: offset,
                                          to: calendar.startOfDay(for: date))!
            if calendar.component(.weekday, from: candidate) != 2 { return candidate }
        }
        preconditionFailure("Among the next 2...6 days there is always a non-Monday")
    }
}
