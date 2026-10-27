import XCTest
@testable import WorkFollow

@MainActor
final class AITaskDraftTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private func request(_ source: AITaskRequest.Source = .note(UUID()), existing: [String] = []) -> AITaskRequest {
        AITaskRequest(source: source, title: "项目周会", content: "周五前核对成本。下周二发送报价。", referenceDate: date, existingTitles: existing)
    }

    func testExtractionUsesEvidenceAndDeduplicatesWithoutInventingDates() throws {
        let input = request(existing: ["发送报价"])
        let rows = try AITaskDraft.decode("""
        {"tasks":[
          {"title":"核对成本","quote":"周五前核对成本。","due":"2026-10-30","priority":"high"},
          {"title":"核对成本","quote":"周五前核对成本。"},
          {"title":"发送报价","quote":"下周二发送报价。"},
          {"title":"没有依据的任务","quote":"这句原文不存在"}
        ]}
        """, request: input)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].title, "核对成本")
        XCTAssertNil(rows[0].schedule.dueAt, "截止日期不能变成安排日期")
        XCTAssertNotNil(rows[0].schedule.deadlineAt)
        XCTAssertEqual(rows[0].priority, .high)
        XCTAssertTrue(rows[0].document(for: input).plainText.contains("周五前核对成本。"))
        XCTAssertTrue(rows[0].document(for: input).blocks.flatMap(\.runs).contains {
            $0.marks.contains(.link(input.sourceURL.absoluteString))
        })
    }

    func testBreakdownAllowsSuggestedStepsAndHandlesEmptyAndInvalidResults() throws {
        let input = request(.task(UUID()), existing: ["收集客户需求"])
        let rows = try AITaskDraft.decode("""
        ```json
        {"tasks":[{"title":"收集客户需求"},{"title":"整理报价项目"}]}
        ```
        """, request: input)
        XCTAssertEqual(rows.map(\.title), ["整理报价项目"])
        XCTAssertNil(rows[0].schedule.dueAt)
        XCTAssertEqual(rows[0].priority, .none)
        XCTAssertTrue(try AITaskDraft.decode("{\"tasks\":[]}", request: input).isEmpty)
        XCTAssertThrowsError(try AITaskDraft.decode("不是完整结果", request: input))
        XCTAssertThrowsError(try AITaskDraft.decode("{\"tasks\":[{\"title\":\"核对\",\"date\":\"2026-02-30\"}]}", request: input))
    }

    func testNoteTasksAreOneUndoStepAndKeepCurrentSelectionAndRichSource() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false, initialTasks: [])
        let notes = NotesWorkspaceModel(taskWorkspace: workspace)
        let noteID = notes.create()
        let input = request(.note(noteID))
        let selected = try XCTUnwrap(workspace.createTask(title: "当前任务", in: .inbox).taskID)
        workspace.select(selected)
        let drafts = [AITaskDraft(title: "核对成本", quote: "周五前核对成本。"), AITaskDraft(title: "发送报价")]
        let ids = try workspace.createAITasks(drafts, request: input)
        XCTAssertEqual(ids.count, 2)
        XCTAssertTrue(ids.allSatisfy { workspace.task(for: $0)?.sourceNoteID == noteID })
        XCTAssertEqual(workspace.selectedTaskID, selected)
        XCTAssertEqual(notes.selectedID, noteID)
        XCTAssertTrue(try workspace.createAITasks(drafts, request: input).isEmpty, "重复采用不再创建同名任务")
        workspace.undo()
        XCTAssertTrue(ids.allSatisfy { workspace.task(for: $0) == nil })
        XCTAssertNotNil(workspace.task(for: selected))
        XCTAssertEqual(notes.notes.count, 1)
        workspace.redo()
        XCTAssertNotNil(workspace.task(for: ids[0]))
    }

    func testBreakdownAddsOnlySelectedChildrenAndPreservesParent() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false, initialTasks: [])
        let parentID = try XCTUnwrap(workspace.createDraft(title: "准备报价", list: "收集箱", schedule: TaskSchedule(),
            priority: .high, tags: [], reminder: nil, repeatFrequency: .never, document: NativeDocument(plainText: "已有正文")).taskID)
        let parent = try XCTUnwrap(workspace.task(for: parentID))
        workspace.select(parentID)
        let input = request(.task(parentID))
        var skipped = AITaskDraft(title: "不采用的建议"); skipped.selected = false
        let ids = try workspace.createAITasks([AITaskDraft(title: "核对成本"), AITaskDraft(title: "整理明细"), skipped], request: input)
        XCTAssertEqual(ids.count, 2)
        XCTAssertTrue(ids.allSatisfy { workspace.task(for: $0)?.parentID == parentID })
        XCTAssertEqual(workspace.task(for: parentID), parent)
        XCTAssertEqual(workspace.selectedTaskID, parentID)
        workspace.undo()
        XCTAssertEqual(workspace.allTasks.count, 1)
        XCTAssertEqual(workspace.task(for: parentID), parent)
    }

    func testMeetingProvenanceAndDatePrioritySurviveSQLiteRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ai-drafts-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = TaskWorkspaceModel(seedDemoData: false, initialTasks: [])
        XCTAssertTrue(workspace.saveList("项目 A"))
        XCTAssertTrue(workspace.addListSection("项目 A", title: "待处理"))
        let section = try XCTUnwrap(workspace.listSections.first)
        let meetingID = UUID(), input = request(.meeting(meetingID))
        let draft = AITaskDraft(title: "核对成本", schedule: TaskSchedule(dueAt: date, hasTime: true,
            deadlineAt: date.addingTimeInterval(86_400)), priority: .high, quote: "周五前核对成本。")
        let id = try XCTUnwrap(workspace.createAITasks([draft], request: input, list: "项目 A", sectionID: section.id).first)
        let repository = NativePreviewRepository(directory: root)
        try repository.save(NativeWorkspaceSnapshot(tasks: workspace.allTasks, notes: [], taskLists: workspace.allListNames,
            taskListMeta: workspace.listMetas, taskListSections: workspace.listSections))
        let saved = try XCTUnwrap(repository.load()?.tasks.first { $0.id == id })
        XCTAssertEqual(saved.sourceMeetingID, meetingID)
        XCTAssertEqual(saved.sectionID, section.id)
        XCTAssertEqual(saved.schedule, draft.schedule)
        XCTAssertEqual(saved.priority, .high)
        XCTAssertTrue(saved.document.blocks.flatMap(\.runs).contains { $0.marks.contains(.link(input.sourceURL.absoluteString)) })
    }

    func testGenerationDoesNotMutateTasksAndCancellationDoesNotPublishResult() async throws {
        let session = AITaskDraftSession(), input = request(.task(UUID()))
        await session.generate(request: input) { prompt in
            XCTAssertTrue(prompt.contains("不调用工具"))
            return "{\"tasks\":[{\"title\":\"整理报价项目\"}]}"
        }
        XCTAssertEqual(session.selectedCount, 1)
        session.drafts[0].selected = false
        XCTAssertEqual(session.selectedCount, 0)
        let cancelled = AITaskDraftSession()
        let job = _Concurrency.Task { await cancelled.generate(request: input) { _ in
            try await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
            return "{\"tasks\":[{\"title\":\"不应出现\"}]}"
        } }
        job.cancel()
        await job.value
        XCTAssertTrue(cancelled.drafts.isEmpty)
    }

    func testMeetingSourceLinksOpenTheOriginalMeeting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ai-meeting-link-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let meetings = MeetingStore(directory: root, automaticallyUpdate: false)
        meetings.create()
        let id = try XCTUnwrap(meetings.selectedID)
        let link = NativeResourceLink.meeting(id)
        XCTAssertEqual(NativeResourceLink(url: link.url), link)
        let workspace = TaskWorkspaceModel(seedDemoData: false, initialTasks: [])
        let navigation = AppNavigation()
        XCTAssertTrue(NativeResourceLinkRouter.open(link, tasks: workspace, notes: NotesWorkspaceModel(taskWorkspace: workspace),
            navigation: navigation, meetings: meetings))
        XCTAssertEqual(navigation.destination, .meetings)
        XCTAssertEqual(meetings.selectedID, id)
    }

    func testRealPiExtractionWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["AITASK_AI_INTEGRATION"] == "1" else {
            throw XCTSkip("Enable AITASK_AI_INTEGRATION=1 for a synthetic-text model check")
        }
        var client = SummaryPiOptimizer()
        client.model = ProcessInfo.processInfo.environment["AITASK_AI_MODEL"] ?? ""
        let input = request()
        let text = try await client.generate(prompt: input.prompt)
        let drafts = try AITaskDraft.decode(text, request: input)
        XCTAssertGreaterThanOrEqual(drafts.count, 2)
        XCTAssertTrue(drafts.contains { $0.title.contains("成本") })
        XCTAssertTrue(drafts.contains { $0.title.contains("报价") })
        XCTAssertTrue(drafts.allSatisfy { !$0.quote.isEmpty })
    }

    func testProviderFailureShowsActionableMessageWithoutChangingDrafts() async {
        let session = AITaskDraftSession()
        session.drafts = [AITaskDraft(title: "已编辑的标题")]
        await session.generate(request: request()) { _ in
            throw NSError(domain: "fixture", code: 503, userInfo: [NSLocalizedDescriptionKey: "503: 无可用渠道"])
        }
        guard case let .failed(message) = session.phase else { return XCTFail("缺少失败提示") }
        XCTAssertTrue(message.contains("AI 模型"))
        XCTAssertEqual(session.drafts.first?.title, "已编辑的标题")
    }
}
