import XCTest
@testable import WorkFollow

final class MigrationSnapshotTests: XCTestCase {
    private var directory: URL!
    private var repository: NativePreviewRepository!

    private let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigrationSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        repository = NativePreviewRepository(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Helpers

    private var fixedDate: Date { stampFormatter.date(from: "2026-09-26 08:00:00")! }

    private func write(_ text: String, to relativePath: String) throws {
        let url = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func makeTask(id: UUID,
                          title: String,
                          list: String = "收集箱",
                          status: TaskStatus = .active,
                          parent: UUID? = nil,
                          childOrder: Int = 0) -> Task {
        Task(id: id, title: title, list: TaskList(name: list), priority: .none,
             schedule: TaskSchedule(), status: status, parentID: parent, childOrder: childOrder,
             createdAt: fixedDate, updatedAt: fixedDate)
    }

    private func makeNote(id: UUID, title: String, folder: String = "未归档") -> Note {
        Note(id: id, title: title, document: NativeDocument(plainText: title), folder: folder,
             updatedAt: fixedDate)
    }

    /// 一份最小 v3 数据：父任务 + 子任务 + 笔记 + 清单 + 文件夹 + base64 附件。
    private var v3JSON: String {
        """
        {
          "format": "workfollow-personal-migration",
          "schemaVersion": 3,
          "exportedAt": "2026-09-25T18:00:00",
          "lists": [
            {"id": null, "name": "收集箱", "sortOrder": 0, "protected": true},
            {"id": null, "name": "读书", "sortOrder": 1, "protected": false}
          ],
          "folders": [
            {"id": "folder-1", "parentId": null, "name": "工作笔记", "sortOrder": 0,
             "createdAt": null, "updatedAt": null}
          ],
          "tasks": [
            {"id": "task-01", "title": "写周报", "description": "周五整理",
             "contentJson": null, "status": "TODO", "priority": "HIGH",
             "dueAt": "2026-09-28T09:30:00", "dueEndAt": null, "deadlineAt": null,
             "hasDueTime": true, "reminderAt": null, "recurrenceType": "WEEKLY",
             "recurrenceConfig": {"weekday": 2}, "listName": "读书", "tags": ["工作"],
             "parentTaskId": null, "childOrder": 0, "sourceNoteId": null,
             "attachments": ["a.txt"], "createdAt": "2026-09-25T08:00:00",
             "updatedAt": "2026-09-25T08:00:00", "completedAt": null, "deletedAt": null,
             "skippedAt": null, "isPinned": false, "abandonedAt": null, "convertedNoteId": null},
            {"id": "sub-1", "title": "收集数据", "description": null,
             "contentJson": null, "status": "DONE", "priority": "NONE",
             "dueAt": null, "dueEndAt": null, "deadlineAt": null,
             "hasDueTime": null, "reminderAt": null, "recurrenceType": "NONE",
             "recurrenceConfig": null, "listName": "读书", "tags": [],
             "parentTaskId": "task-01", "childOrder": 1, "sourceNoteId": null,
             "attachments": [], "createdAt": "2026-09-25T08:00:00",
             "updatedAt": "2026-09-25T08:00:00", "completedAt": null, "deletedAt": null,
             "skippedAt": null, "isPinned": false, "abandonedAt": null, "convertedNoteId": null}
          ],
          "notes": [
            {"id": "note-01", "folderId": "folder-1", "title": "读书笔记",
             "contentJson": {"type": "doc", "content": []}, "plainText": "正文第一行",
             "isFavorite": true, "createdAt": null, "updatedAt": "2026-09-25T08:00:00",
             "deletedAt": null}
          ],
          "attachmentFiles": {"a.txt": "aGVsbG8="}
        }
        """
    }

    // MARK: v3 解析与导出往返

    func testParseV3MapsTasksNotesListsAndAttachments() throws {
        let bundle = try MigrationSnapshot.parse(Data(v3JSON.utf8))
        XCTAssertEqual(bundle.schemaVersion, 3)
        XCTAssertEqual(bundle.tasks.count, 2)
        XCTAssertEqual(bundle.notes.count, 1)
        XCTAssertEqual(bundle.lists.count, 2)
        XCTAssertEqual(bundle.folders.count, 1)
        XCTAssertEqual(bundle.embeddedFiles["a.txt"], "aGVsbG8=")

        let (snapshot, summary) = MigrationSnapshot.replaced(bundle, attachmentNames: ["a.txt"])
        XCTAssertEqual(summary.importedTasks, 2)
        XCTAssertEqual(summary.importedNotes, 1)
        XCTAssertEqual(summary.importedFolders, 1)
        XCTAssertEqual(summary.importedLegacyChildren, 0)
        XCTAssertEqual(snapshot.taskLists, ["收集箱", "读书"])

        let parent = try XCTUnwrap(snapshot.tasks.first { $0.title == "写周报" })
        XCTAssertEqual(parent.id, MigrationSnapshot.uuid(forRawID: "task-01"))
        XCTAssertEqual(parent.list.name, "读书")
        XCTAssertEqual(parent.priority, .high)
        XCTAssertEqual(parent.status, .active)
        XCTAssertEqual(parent.schedule.dueAt, MigrationSnapshot.parseDate("2026-09-28T09:30:00"))
        XCTAssertTrue(parent.schedule.hasTime)
        XCTAssertEqual(parent.recurrence, .weekly)
        XCTAssertEqual(parent.recurrenceRule?.weekday, 2)
        XCTAssertEqual(parent.tags, ["工作"])
        XCTAssertEqual(parent.attachments.map(\.storedName), ["a.txt"])
        XCTAssertEqual(parent.attachments.first?.name, "a.txt")

        let child = try XCTUnwrap(snapshot.tasks.first { $0.title == "收集数据" })
        XCTAssertEqual(child.parentID, parent.id)
        XCTAssertEqual(child.childOrder, 1)
        XCTAssertEqual(child.status, .completed)
        XCTAssertEqual(child.list.name, "读书")

        let note = try XCTUnwrap(snapshot.notes.first)
        XCTAssertEqual(note.id, MigrationSnapshot.uuid(forRawID: "note-01"))
        XCTAssertEqual(note.folder, "工作笔记")
        XCTAssertTrue(note.favorite)
        XCTAssertEqual(note.document.plainText, "正文第一行")
    }

    func testExportV3RoundTripsSnapshotWithEmbeddedAttachments() throws {
        let attachments = directory.appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: attachments.appendingPathComponent("a.txt"))

        let parent = makeTask(id: MigrationSnapshot.uuid(forRawID: "task-01"), title: "写周报", list: "读书")
        let child = makeTask(id: MigrationSnapshot.uuid(forRawID: "sub-1"), title: "收集数据",
                             list: "读书", status: .completed, parent: parent.id, childOrder: 1)
        let note = makeNote(id: MigrationSnapshot.uuid(forRawID: "note-01"), title: "读书笔记", folder: "工作笔记")
        let snapshot = NativeWorkspaceSnapshot(
            tasks: [parent, child], notes: [note], taskLists: ["收集箱", "读书"])

        let now = stampFormatter.date(from: "2026-09-26 14:30:00")!
        let data = try MigrationSnapshot.exportJSON(from: snapshot, attachmentDirectory: attachments, now: now)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""format" : "workfollow-personal-migration""#)
                      || text.contains(#""format":"workfollow-personal-migration""#))
        // v3 只写 parentTaskId/childOrder，绝不写 subtasks。
        XCTAssertFalse(text.contains("subtasks"))

        let reparsed = try MigrationSnapshot.parse(data)
        XCTAssertEqual(reparsed.schemaVersion, 3)
        XCTAssertEqual(reparsed.embeddedFiles["a.txt"], Data("hello".utf8).base64EncodedString())
        XCTAssertEqual(reparsed.tasks.count, 2)
        XCTAssertEqual(reparsed.notes.count, 1)

        // 导出的 v3：id 为 UUID 字符串；dueEndAt/contentJson 置空；无 subtasks 键。
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let records = try XCTUnwrap(object["tasks"] as? [[String: Any]])
        let parentRecord = try XCTUnwrap(
            records.first { ($0["id"] as? String) == MigrationSnapshot.uuid(forRawID: "task-01").uuidString })
        XCTAssertTrue(parentRecord["dueEndAt"] is NSNull)
        XCTAssertTrue(parentRecord["contentJson"] is NSNull)
        XCTAssertNil(parentRecord["subtasks"])
        let childRecord = try XCTUnwrap(
            records.first { ($0["id"] as? String) == MigrationSnapshot.uuid(forRawID: "sub-1").uuidString })
        XCTAssertEqual(childRecord["parentTaskId"] as? String, MigrationSnapshot.uuid(forRawID: "task-01").uuidString)
        XCTAssertEqual(childRecord["childOrder"] as? Int, 1)
        XCTAssertEqual(childRecord["status"] as? String, "DONE")

        let (rebuilt, summary) = MigrationSnapshot.replaced(reparsed, attachmentNames: ["a.txt"])
        XCTAssertEqual(summary.importedTasks, 2)
        XCTAssertEqual(rebuilt.tasks.map(\.id), snapshot.tasks.map(\.id))
        XCTAssertEqual(rebuilt.notes.map(\.id), snapshot.notes.map(\.id))
        XCTAssertEqual(rebuilt.taskLists, ["收集箱", "读书"])
        let rebuiltNote = try XCTUnwrap(rebuilt.notes.first)
        XCTAssertEqual(rebuiltNote.folder, "工作笔记")
        XCTAssertEqual(rebuiltNote.document.plainText, "读书笔记")
    }

    // MARK: v1/v2 旧格式读取 + legacy 子任务展开

    func testParseV1ExpandsLegacySubtasksToDeterministicRealTasks() throws {
        let v1 = """
        {
          "format": "workfollow-personal-migration",
          "schemaVersion": 1,
          "exportedAt": null,
          "lists": [{"id": null, "name": "收集箱", "sortOrder": 0, "protected": true}],
          "folders": [],
          "tasks": [
            {"id": "task-01", "title": "搬家准备", "description": null, "contentJson": null,
             "status": "TODO", "priority": "NONE", "dueAt": null, "dueEndAt": null,
             "deadlineAt": null, "hasDueTime": null, "reminderAt": null,
             "recurrenceType": "NONE", "recurrenceConfig": null, "listName": "收集箱",
             "tags": [], "sourceNoteId": null, "attachments": [], "createdAt": null,
             "updatedAt": null, "completedAt": null, "deletedAt": null, "isPinned": false,
             "subtasks": [
               {"id": "s1", "title": "订纸箱", "completed": true},
               {"id": "", "title": "约搬家车", "completed": false}
             ]}
          ],
          "notes": []
        }
        """
        let bundle = try MigrationSnapshot.parse(Data(v1.utf8))
        XCTAssertEqual(bundle.schemaVersion, 1)
        XCTAssertEqual(bundle.tasks.first?.subtasks.count, 2)

        let (snapshot, summary) = MigrationSnapshot.replaced(bundle, attachmentNames: [])
        XCTAssertEqual(summary.importedLegacyChildren, 2)
        XCTAssertEqual(snapshot.tasks.count, 3)

        let parent = try XCTUnwrap(snapshot.tasks.first { $0.title == "搬家准备" })
        let first = try XCTUnwrap(snapshot.tasks.first { $0.title == "订纸箱" })
        let second = try XCTUnwrap(snapshot.tasks.first { $0.title == "约搬家车" })

        // 确定性 id：legacy-child-{parent}-{sub} / legacy-child-{parent}-index-{i}
        XCTAssertEqual(first.id, MigrationSnapshot.uuid(forRawID: "legacy-child-task-01-s1"))
        XCTAssertEqual(second.id, MigrationSnapshot.uuid(forRawID: "legacy-child-task-01-index-1"))
        XCTAssertEqual(first.parentID, parent.id)
        XCTAssertEqual(second.parentID, parent.id)
        XCTAssertEqual(first.childOrder, 0)
        XCTAssertEqual(second.childOrder, 1)
        XCTAssertEqual(first.status, .completed)
        XCTAssertEqual(second.status, .active)
        XCTAssertNil(first.completedAt, "旧记录没有完成时间，不编造")
        XCTAssertEqual(first.list.name, "收集箱")
    }

    func testParseV2AcceptsPinnedListsAndUnknownTaskFieldsCounted() throws {
        let v2 = """
        {
          "format": "workfollow-local-snapshot",
          "schemaVersion": 2,
          "lists": [
            {"id": null, "name": "收集箱", "sortOrder": 0, "protected": true},
            {"id": null, "name": "读书", "sortOrder": 1, "protected": false,
             "color": "#123456", "pinned": true}
          ],
          "folders": [],
          "tasks": [
            {"id": "task-01", "title": "带 bucket 的旧任务", "status": "TODO",
             "priority": "NONE", "listName": "读书", "bucket": "today",
             "timeLabel": "今天 14:00", "dueEndAt": "2026-09-29T00:00:00",
             "reminderOffsets": [30, 60], "tags": []}
          ],
          "notes": []
        }
        """
        let bundle = try MigrationSnapshot.parse(Data(v2.utf8))
        XCTAssertEqual(bundle.format, MigrationBundle.localSnapshotFormat)
        XCTAssertTrue(bundle.lists.first { $0.name == "读书" }?.isPinned ?? false)

        let (snapshot, summary) = MigrationSnapshot.replaced(bundle, attachmentNames: [])
        // 无对应字段被计数：bucket / timeLabel / dueEndAt / reminderOffsets。
        for key in ["bucket", "timeLabel", "dueEndAt", "reminderOffsets"] {
            XCTAssertEqual(summary.ignoredFieldCounts[key], 1, "字段 \(key) 应被计数一次")
        }
        let task = try XCTUnwrap(snapshot.tasks.first)
        XCTAssertEqual(task.recurrence, .never)
        XCTAssertNil(task.schedule.dueAt, "无对应字段的日期不落盘")
    }

    // MARK: merge / replace 语义

    func testMergeSkipsSameIDsAndCreatesUnknownLists() throws {
        let localID = MigrationSnapshot.uuid(forRawID: "task-01")
        let local = NativeWorkspaceSnapshot(
            tasks: [makeTask(id: localID, title: "本地版本")],
            notes: [makeNote(id: MigrationSnapshot.uuid(forRawID: "note-01"), title: "本地笔记")],
            taskLists: ["收集箱"])

        let bundle = try MigrationSnapshot.parse(Data(v3JSON.utf8))
        let (merged, summary) = MigrationSnapshot.merged(bundle, into: local, attachmentNames: ["a.txt"])

        XCTAssertEqual(summary.skippedTasks, 1, "同 ID 任务跳过")
        XCTAssertEqual(summary.skippedNotes, 1, "同 ID 笔记跳过")
        XCTAssertEqual(summary.importedTasks, 1, "新 ID 的 v3 子任务照常导入")
        XCTAssertEqual(summary.importedLists, 1, "未知清单「读书」自动创建")
        XCTAssertEqual(merged.taskLists, ["收集箱", "读书"])

        // 本机版本保留，导入版本不覆盖。
        let kept = try XCTUnwrap(merged.tasks.first { $0.id == localID })
        XCTAssertEqual(kept.title, "本地版本")
        XCTAssertEqual(merged.notes.first?.title, "本地笔记")
        // 导入的 v3 子任务挂在本地同名父任务上；本机任务排在导入内容之后。
        let importedChild = try XCTUnwrap(merged.tasks.first { $0.title == "收集数据" })
        XCTAssertEqual(importedChild.parentID, localID)
        XCTAssertEqual(merged.tasks.last?.id, localID)
    }

    func testReplaceClearsLocalAndImportsBundleContentOnly() throws {
        let local = NativeWorkspaceSnapshot(
            tasks: [makeTask(id: UUID(), title: "旧任务")],
            notes: [makeNote(id: UUID(), title: "旧笔记")],
            taskLists: ["收集箱", "将被清掉"])

        let bundle = try MigrationSnapshot.parse(Data(v3JSON.utf8))
        let (replaced, summary) = MigrationSnapshot.replaced(bundle, attachmentNames: [])

        XCTAssertEqual(summary.importedTasks, 2)
        XCTAssertEqual(summary.importedNotes, 1)
        XCTAssertEqual(summary.skippedTasks, 0)
        XCTAssertEqual(replaced.tasks.count, 2)
        XCTAssertEqual(replaced.notes.count, 1)
        XCTAssertEqual(replaced.taskLists, ["收集箱", "读书"])
        XCTAssertFalse(replaced.notes.first?.folder.isEmpty ?? true)
        XCTAssertEqual(replaced.notes.first?.folder, "工作笔记")
    }

    // MARK: 解析错误

    func testParseRejectsBadFilesWithChineseErrors() {
        XCTAssertThrowsError(try MigrationSnapshot.parse(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? MigrationFormatError, .invalidJSON)
        }
        XCTAssertThrowsError(try MigrationSnapshot.parse(Data("[]".utf8))) { error in
            XCTAssertEqual(error as? MigrationFormatError, .notJSONObject)
        }
        let unknownFormat = "{\"format\":\"other\",\"schemaVersion\":3}"
        XCTAssertThrowsError(try MigrationSnapshot.parse(Data(unknownFormat.utf8))) { error in
            XCTAssertEqual(error as? MigrationFormatError, .unknownFormat)
        }
        let unsupported = "{\"format\":\"workfollow-personal-migration\",\"schemaVersion\":9}"
        XCTAssertThrowsError(try MigrationSnapshot.parse(Data(unsupported.utf8))) { error in
            XCTAssertEqual(error as? MigrationFormatError, .unsupportedVersion(9))
        }
        let missingTitle = "{\"format\":\"workfollow-personal-migration\",\"schemaVersion\":3," +
            "\"tasks\":[{\"id\":\"task-01\",\"status\":\"TODO\"}]}"
        XCTAssertThrowsError(try MigrationSnapshot.parse(Data(missingTitle.utf8))) { error in
            XCTAssertEqual(error as? MigrationFormatError, .missingField("title"))
        }
    }

    func testCorruptSourcesNeverOverwriteExistingWorkspaceFile() throws {
        // 本机已有有效快照。
        let snapshot = NativeWorkspaceSnapshot(
            tasks: [makeTask(id: UUID(), title: "宝贵数据")], notes: [], taskLists: ["收集箱"])
        try repository.save(snapshot)
        let original = try read("workspace.json")

        // 损坏的导入文件：解析报错即可，绝不写盘。
        XCTAssertThrowsError(try MigrationSnapshot.parse(Data("nope".utf8)))
        XCTAssertEqual(try read("workspace.json"), original)

        // 损坏的备份文件：恢复报错，workspace.json 原样保留。
        try write("garbage", to: "backups/workspace-bad.json")
        XCTAssertThrowsError(try repository.restoreBackup(
            at: directory.appendingPathComponent("backups/workspace-bad.json")))
        XCTAssertEqual(try read("workspace.json"), original)
        let stillIntact = try XCTUnwrap(try repository.load())
        XCTAssertEqual(stillIntact.tasks.first?.title, "宝贵数据")
    }

    // MARK: 附件还原

    func testRestoreEmbeddedFilesWritesSkipsExistingAndRejectsUnsafeNames() throws {
        let attachments = directory.appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: attachments.appendingPathComponent("a.txt"))

        let restored = try MigrationSnapshot.restoreEmbeddedFiles(
            ["a.txt": "aGVsbG8=", "b.bin": "AAEC"], into: attachments)
        XCTAssertEqual(restored, 1, "同名文件跳过，只写入新文件")
        XCTAssertEqual(try Data(contentsOf: attachments.appendingPathComponent("a.txt")), Data("old".utf8))
        XCTAssertEqual(try Data(contentsOf: attachments.appendingPathComponent("b.bin")), Data([0x00, 0x01, 0x02]))
        XCTAssertEqual(MigrationSnapshot.attachmentNames(in: attachments), ["a.txt", "b.bin"])

        XCTAssertThrowsError(try MigrationSnapshot.restoreEmbeddedFiles(
            ["a/b.txt": "aGVsbG8="], into: attachments)) { error in
            XCTAssertEqual(error as? MigrationFormatError, .invalidAttachmentName("a/b.txt"))
        }
        XCTAssertThrowsError(try MigrationSnapshot.restoreEmbeddedFiles(
            ["broken.txt": "!!!not-base64!!!"], into: attachments)) { error in
            XCTAssertEqual(error as? MigrationFormatError, .corruptAttachment("broken.txt"))
        }
    }

    // MARK: 确定性 ID 与日期

    func testUUIDMappingIsDeterministicAndPassesUUIDThrough() {
        let first = MigrationSnapshot.uuid(forRawID: "task-01")
        XCTAssertEqual(first, MigrationSnapshot.uuid(forRawID: "task-01"))
        XCTAssertNotEqual(first, MigrationSnapshot.uuid(forRawID: "task-02"))

        let raw = "6F2A2B0C-1111-4222-8333-ABCDEF012345"
        XCTAssertEqual(MigrationSnapshot.uuid(forRawID: raw), UUID(uuidString: raw)!)

        let legacy = MigrationSnapshot.legacyChildRawID(parentID: "task-01", subtaskID: "s1", index: 3)
        XCTAssertEqual(legacy, "legacy-child-task-01-s1")
        let emptySub = MigrationSnapshot.legacyChildRawID(parentID: "task-01", subtaskID: "", index: 3)
        XCTAssertEqual(emptySub, "legacy-child-task-01-index-3")
    }

    func testDateParsingHandlesLocalAndZonedFormats() throws {
        let local = MigrationSnapshot.parseDate("2026-09-28T09:30:00")
        XCTAssertEqual(local, stampFormatter.date(from: "2026-09-28 09:30:00"))
        XCTAssertEqual(MigrationSnapshot.formatDate(try XCTUnwrap(local)), "2026-09-28T09:30:00")

        XCTAssertNotNil(MigrationSnapshot.parseDate("2026-09-28T01:30:00Z"), "UTC 字符串可解析")
        XCTAssertNotNil(MigrationSnapshot.parseDate("2026-09-28T01:30:00.123456Z"), "带微秒可解析")
        XCTAssertNotNil(MigrationSnapshot.parseDate("2026-09-28"))
        XCTAssertNil(MigrationSnapshot.parseDate(""))
        XCTAssertNil(MigrationSnapshot.parseDate(nil))
        XCTAssertNil(MigrationSnapshot.parseDate("不是日期"))
    }

    // MARK: 每日备份

    func testDailyBackupRunsOncePerDayAndPrunesToSevenDays() throws {
        let snapshot = NativeWorkspaceSnapshot(
            tasks: [makeTask(id: UUID(), title: "任务")], notes: [], taskLists: nil)
        try repository.save(snapshot)

        let day1 = stampFormatter.date(from: "2026-09-20 10:00:00")!
        repository.maintainDailyBackup(now: day1)
        var backups = repository.listBackups()
        XCTAssertEqual(backups.map(\.lastPathComponent), ["workspace-2026-09-20.json"])

        // 同一天再次写入不再复制。
        try repository.save(snapshot)
        repository.maintainDailyBackup(now: stampFormatter.date(from: "2026-09-20 18:00:00")!)
        XCTAssertEqual(repository.listBackups().count, 1)

        // 再来 8 天的历史备份（09-04 到 09-11），清理后只保留最近 7 份。
        for day in 4...11 {
            try write("{}", to: String(format: "backups/workspace-2026-09-%02d.json", day))
        }
        repository.maintainDailyBackup(now: stampFormatter.date(from: "2026-09-21 09:00:00")!)
        backups = repository.listBackups()
        XCTAssertEqual(backups.count, NativePreviewRepository.backupRetentionDays)
        XCTAssertEqual(backups.last?.lastPathComponent, "workspace-2026-09-21.json")

        let info = repository.backupInfo()
        XCTAssertEqual(info.count, 7)
        XCTAssertEqual(info.latestName, "workspace-2026-09-21.json")
        XCTAssertEqual(info.latestDateStamp, "2026-09-21")
    }

    func testBackupNowUsesTimestampedNameAndRestoreBacksUpCurrentFirst() throws {
        let snapshot = NativeWorkspaceSnapshot(
            tasks: [makeTask(id: UUID(), title: "第一版")], notes: [], taskLists: nil)
        try repository.save(snapshot)

        let now = stampFormatter.date(from: "2026-09-26 14:30:25")!
        let backup = try XCTUnwrap(repository.backupNow(now: now))
        XCTAssertEqual(backup.lastPathComponent, "workspace-2026-09-26-143025.json")
        XCTAssertEqual(repository.backupDateStamp(of: backup), "2026-09-26")

        // 当前内容变化后恢复，恢复前会先把"当前内容"备份一份。
        let newer = NativeWorkspaceSnapshot(
            tasks: [makeTask(id: UUID(), title: "第二版")], notes: [], taskLists: nil)
        try repository.save(newer)
        try repository.restoreBackup(at: backup, now: now.addingTimeInterval(60))

        let restored = try XCTUnwrap(try repository.load())
        XCTAssertEqual(restored.tasks.first?.title, "第一版")
        let backups = repository.listBackups()
        XCTAssertEqual(backups.count, 2)
        XCTAssertEqual(backups.last?.lastPathComponent, "workspace-2026-09-26-143125.json",
                       "恢复前自动备份当前内容（时刻戳命名）")

        // 没有 workspace.json 时立即备份是空操作。
        try FileManager.default.removeItem(at: directory.appendingPathComponent("workspace.json"))
        XCTAssertNil(try repository.backupNow(now: now))
    }
}
