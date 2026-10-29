import XCTest
@testable import WorkFollow

final class KnowledgeRetrievalTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_232_000)
    private func task(_ title: String, body: String = "", list: String = "工作") -> Task {
        Task(id: UUID(), title: title, document: NativeDocument(plainText: body), list: TaskList(name: list),
             priority: .high, schedule: TaskSchedule(), parentID: nil, childOrder: 0, createdAt: now, updatedAt: now)
    }
    private func corpus(tasks: [Task] = [], notes: [Note] = [], meetings: [MeetingRecord] = []) -> KnowledgeCorpus {
        KnowledgeCorpus(tasks: tasks, notes: notes, meetings: meetings, currentList: nil, now: now)
    }

    func testChineseQuestionFindsDifferentResourcesAndRetainsRealTaskState() throws {
        let task = task("客户 Alpha 报价", body: "周五提交方案。")
        let note = Note(id: UUID(), title: "客户 Alpha 讨论", document: NativeDocument(plainText: "方案需要核对成本。"), folder: "工作", updatedAt: now)
        var meeting = MeetingRecord(title: "客户 Alpha 沟通", createdAt: now)
        meeting.transcript = [.init(speaker: "未区分", text: "方案改为周五提交。", offset: 42)]
        let result = try corpus(tasks: [task], notes: [note], meetings: [meeting]).search("客户 Alpha 的方案进展")
        XCTAssertEqual(Set(result.sources.map(\.kind)), [.task, .note, .meeting])
        XCTAssertTrue(result.sources.first { $0.kind == .task }?.content.contains("状态：未完成") == true)
        XCTAssertEqual(result.sources.first { $0.kind == .meeting }?.lineID, meeting.transcript[0].id)
        XCTAssertEqual(result.sources.first { $0.kind == .meeting }?.location, "00:42")
    }

    func testMatchingTextInLongNoteTailIsNotClippedToItsBeginning() throws {
        let text = String(repeating: "背景材料，没有本次问题的答案。", count: 500) + "最终确认：海鸥计划周五验收。"
        let note = Note(id: UUID(), title: "项目记录", document: NativeDocument(plainText: text), folder: "工作", updatedAt: now)
        let result = try corpus(notes: [note]).search("海鸥计划什么时候验收")
        XCTAssertFalse(result.sources.isEmpty)
        XCTAssertTrue(result.sources.contains { $0.content.contains("海鸥计划周五验收") })
        XCTAssertTrue(result.sources.allSatisfy { $0.content.count <= 2400 })
    }

    func testUnfinishedAndThisWeekUseActualScheduleAndStatus() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.firstWeekday = 2
        var open = task("海鸥验收"); open.schedule.dueAt = now
        var closed = task("海鸥签约"); closed.status = .completed; closed.schedule.dueAt = now
        var later = task("海鸥复盘"); later.schedule.dueAt = calendar.date(byAdding: .day, value: 10, to: now)
        var value = corpus(tasks: [open, closed, later]); value.calendar = calendar
        let result = try value.search("海鸥本周有哪些未完成任务")
        XCTAssertEqual(result.sources.map(\.resourceID), [open.id])
    }

    func testLatestMeetingIsLatestRelevantMeetingRatherThanUnrelatedNewest() throws {
        var old = MeetingRecord(title: "海鸥方案会议", createdAt: now.addingTimeInterval(-1000))
        old.transcript = [.init(speaker: "未区分", text: "改为周一。", offset: 1)]
        var recent = MeetingRecord(title: "海鸥方案会议", createdAt: now)
        recent.transcript = [.init(speaker: "未区分", text: "改为周五。", offset: 10)]
        var other = MeetingRecord(title: "燕子例会", createdAt: now.addingTimeInterval(1000))
        other.transcript = [.init(speaker: "未区分", text: "下月再议。", offset: 20)]
        let result = try corpus(meetings: [old, recent, other]).search("海鸥上次会议定了什么")
        XCTAssertFalse(result.sources.isEmpty)
        XCTAssertTrue(result.sources.allSatisfy { $0.resourceID == recent.id })
    }

    func testDeletedAndConvertedResourcesAreExcludedAndContextIsBounded() throws {
        var removed = task("海鸥删除任务"); removed.deletedAt = now
        var converted = task("海鸥转换任务"); converted.convertedNoteID = UUID()
        var tasks = (0..<20).map { task("海鸥任务 \($0)") }; tasks += [removed, converted]
        let deletedNote = Note(id: UUID(), title: "海鸥旧笔记", document: NativeDocument(plainText: "已移除"), folder: "工作", updatedAt: now, deletedAt: now)
        let result = try corpus(tasks: tasks, notes: [deletedNote]).search("海鸥")
        XCTAssertEqual(result.matchingPassages, 20)
        XCTAssertEqual(result.sources.count, 8)
        XCTAssertEqual(result.sources.map(\.id), (1...8).map { "S\($0)" })
        XCTAssertFalse(result.sources.contains { [removed.id, converted.id, deletedNote.id].contains($0.resourceID) })
    }

    func testCurrentProjectResolvesAgainstActiveListAndNoMatchStaysEmpty() throws {
        let a = task("核对成本", list: "海鸥计划"), b = task("核对成本", list: "燕子计划")
        var value = corpus(tasks: [a, b]); value.currentList = "海鸥计划"
        XCTAssertEqual(try value.search("这个项目还有哪些未完成任务").sources.map(\.resourceID), [a.id])
        XCTAssertTrue(try value.search("橡树合同").sources.isEmpty)
    }

    func testStatusQuestionCanRetrieveUnfinishedTaskAndMixedKindsStayInScope() throws {
        let open = task("海鸥验收", body: "周五验收。")
        var completed = task("海鸥签约"); completed.status = .completed
        let note = Note(id: UUID(), title: "海鸥方案", document: NativeDocument(plainText: "核对成本。"), folder: "工作", updatedAt: now)
        var meeting = MeetingRecord(title: "海鸥沟通", createdAt: now)
        meeting.transcript = [.init(speaker: "未区分", text: "周五验收。", offset: 30)]
        let value = corpus(tasks: [open, completed], notes: [note], meetings: [meeting])
        XCTAssertEqual(try value.search("海鸥验收任务是否已完成").sources.map(\.resourceID), [open.id])
        XCTAssertEqual(try value.search("海鸥已完成的待办").sources.map(\.resourceID), [completed.id])
        XCTAssertEqual(Set(try value.search("海鸥相关笔记和会议").sources.map(\.kind)), [.note, .meeting])
    }

    func testTranscriptSearchMatchesSpeakerTextAndRecordingTime() {
        let line = MeetingTranscriptLine(speaker: "片段 1 · 讲话人1", text: "海鸥方案周五验收。", offset: 81)
        XCTAssertTrue(MeetingTranscriptSearch.matches(line, query: "周五"))
        XCTAssertTrue(MeetingTranscriptSearch.matches(line, query: "讲话人1"))
        XCTAssertTrue(MeetingTranscriptSearch.matches(line, query: "01:21"))
        XCTAssertFalse(MeetingTranscriptSearch.matches(line, query: "不存在的文字"))
    }

    func testCompoundQuestionRetrievesTaskStateAndMeetingBudgetCorrection() throws {
        let open = task("海鸥验收", body: "验收负责人尚未指定。")
        let old = Note(id: UUID(), title: "海鸥旧计划", document: NativeDocument(plainText: "2026-10-23：原计划11月2日周一验收。"), folder: "工作", updatedAt: now.addingTimeInterval(-86400))
        var meeting = MeetingRecord(title: "海鸥验收会议", createdAt: now)
        meeting.transcript = [.init(speaker: "未区分", text: "11月2日周一验收取消，改为10月30日周五15点验收。18000元只是备选报价，预算尚未批准。", offset: 50)]
        let unrelated = Note(id: UUID(), title: "燕子预算", document: NativeDocument(plainText: "燕子预算已经批准。"), folder: "工作", updatedAt: now)
        let result = try corpus(tasks: [open], notes: [old, unrelated], meetings: [meeting])
            .search("海鸥项目最终何时验收，验收任务是否已经完成？预算是否获批？")
        XCTAssertEqual(Set(result.sources.map(\.kind)), [.task, .note, .meeting])
        XCTAssertTrue(result.sources.contains { $0.content.contains("预算尚未批准") })
        XCTAssertFalse(result.sources.contains { $0.resourceID == unrelated.id })
    }
}
