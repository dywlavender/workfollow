import AVFoundation
import XCTest
@testable import WorkFollow

@MainActor
final class AIProductIterationTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ai-product-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func service(_ root: URL) -> NativeAutomationService {
        let tasks = TaskWorkspaceModel(initialTasks: [])
        return NativeAutomationService(tasks: tasks, notes: NotesWorkspaceModel(taskWorkspace: tasks), directory: root,
                                       meetings: MeetingStore(directory: root, ai: ReplayAI(), automaticallyUpdate: false))
    }
    private func call(_ service: NativeAutomationService, _ operation: String, _ arguments: [String: String] = [:]) throws -> AutomationValue {
        try service.execute(AutomationRequest(operation: operation, arguments: arguments))
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<400 { if condition() { return }; try await _Concurrency.Task.sleep(for: .milliseconds(10)) }
        XCTFail("AI iteration did not settle")
    }
    func testReminderRecurrenceReadbackAndAtomicUndo() throws {
        let service = service(try directory())
        let created = try call(service, "task.add", ["title": "虚构周报", "date": "2026-11-02T09:00:00+08:00",
            "reminder-offsets": "-10,0", "repeat": "weekly", "repeat-weekdays": "2", "repeat-count": "4"])
        let id = try XCTUnwrap(created["id"]?.string)
        let task = try XCTUnwrap(service.tasks.task(for: XCTUnwrap(UUID(uuidString: id))))
        XCTAssertEqual(task.reminderOffsets, [-10, 0]); XCTAssertEqual(task.recurrence, .weekly)
        XCTAssertEqual(task.recurrenceRule?.weekdays, [2]); XCTAssertEqual(task.recurrenceRule?.remainingCount, 4)
        let updated = try call(service, "task.update", ["id": id, "version": try XCTUnwrap(created["version"]?.string),
                                                       "clear-reminder": "true", "clear-repeat": "true"])
        XCTAssertEqual(updated["repeat"]?.string, "never")
        _ = try call(service, "operation.undo", ["id": try XCTUnwrap(updated["undoID"]?.string)])
        XCTAssertEqual(service.tasks.task(for: task.id)?.reminderOffsets, [-10, 0])
        XCTAssertEqual(service.tasks.task(for: task.id)?.recurrence, .weekly)
        _ = try call(service, "operation.undo", ["id": try XCTUnwrap(created["undoID"]?.string)])
        XCTAssertNil(service.tasks.task(for: task.id))
    }
    func testDateCountIsIndependentOfPagination() throws {
        let service = service(try directory())
        for date in ["2026-11-02", "2026-11-02", "2026-11-03"] { _ = try call(service, "task.add", ["title": "虚构任务", "date": date]) }
        let args = ["from": "2026-11-02", "to": "2026-11-02", "completed": "false"]
        let count = try call(service, "task.count", args)
        XCTAssertEqual(count["total"], .number(2))
        let page = try call(service, "task.list", args.merging(["limit": "1"]) { _, new in new })
        XCTAssertEqual(page["total"], .number(2))
        guard case let .array(items)? = page["items"] else { return XCTFail("Missing page") }
        XCTAssertEqual(items.count, 1)
    }
    func testNoteCreationAndContentUndoAreOneOperation() throws {
        let service = service(try directory())
        let note = try call(service, "note.create", ["title": "虚构笔记", "content": "内容必须一起撤销"])
        XCTAssertEqual(service.notes.notes.count, 1)
        _ = try call(service, "operation.undo", ["id": try XCTUnwrap(note["undoID"]?.string)])
        XCTAssertTrue(service.notes.notes.isEmpty)
    }
    func testMeetingQueryReturnsEvidenceAndTimestampLink() throws {
        let service = service(try directory()), meetings = try XCTUnwrap(service.meetings)
        meetings.create(); let id = try XCTUnwrap(meetings.selectedID)
        meetings.rename("虚构松竹评审"); meetings.appendTranscriptForTesting("松竹项目周五验收。", speaker: "甲")
        let value = try call(service, "meeting.get", ["id": id.uuidString, "query": "验收"])
        guard case let .array(lines)? = value["transcript"] else { return XCTFail("Missing transcript") }
        XCTAssertTrue(try XCTUnwrap(lines.first?["url"]?.string).contains("?line="))
        let found = try call(service, "knowledge.search", ["query": "松竹会议验收"])
        guard case let .array(sources)? = found["sources"] else { return XCTFail("Missing sources") }
        XCTAssertFalse(sources.isEmpty)
    }
    func testRetryUsesItsOwnQuestionAndPreservesSuccessfulActions() async throws {
        let first = AIConversationMessage(role: .user, text: "第一问")
        let failed = AIConversationMessage(role: .assistant, text: "", state: .failed, error: "中断",
            actions: [AIActionReceipt(title: "已创建", details: "虚构待办已保存")])
        let model = AIConversationModel(record: .init(messages: [first, failed, .init(role: .user, text: "第二问"), .init(role: .assistant, text: "第二答")]))
        var sent = "", context = ""
        model.retry(failed.id) { _, _, value, message, _ in sent = message; context = value; return "第一答" }
        try await wait { !model.isRunning }
        XCTAssertEqual(sent, "第一问"); XCTAssertTrue(context.contains("不要再次创建"))
    }
    func testReferenceIsSentAndReceiptCanBeMarkedUndone() async throws {
        let root = try directory(), store = AIChatStore(directory: root), id = UUID()
        store.current.setReferences([.init(id: id, kind: "note", title: "虚构来源")])
        XCTAssertTrue(store.records.isEmpty)
        var context = ""
        store.current.input = "整理这篇笔记"; store.current.send { _, _, value, _, _ in context = value; return "结果" }
        try await wait { !store.current.isRunning }
        XCTAssertTrue(context.contains(id.uuidString))
        let token = UUID()
        store.recordAction(.init(title: "虚构待办", details: "明天九点", undoID: token), conversationID: store.current.record.id)
        store.markUndone(token)
        XCTAssertTrue(store.current.record.messages.last?.actions?.first?.undone == true)
    }
    func testTranscriptCorrectionAndUndoPreserveLineIdentity() throws {
        let store = try XCTUnwrap(service(directory()).meetings)
        store.create(); store.appendTranscriptForTesting("错误句子", speaker: "片段 1.0s · 甲"); store.appendTranscriptForTesting("另一句", speaker: "片段 1.0s · 甲")
        let meeting = try XCTUnwrap(store.selected), line = try XCTUnwrap(meeting.transcript.first)
        store.correctTranscript(meetingID: meeting.id, lineID: line.id, text: "先只改文字", speaker: "甲", renameAll: false)
        XCTAssertEqual(store.selected?.transcript.first?.speaker, "片段 1.0s · 甲")
        store.restoreTranscript(meeting.id)
        store.correctTranscript(meetingID: meeting.id, lineID: line.id, text: "正确句子", speaker: "小林", renameAll: true)
        XCTAssertEqual(store.selected?.transcript.first?.id, line.id)
        XCTAssertEqual(store.selected?.transcript.map(\.speaker), ["小林", "小林"])
        store.restoreTranscript(meeting.id)
        XCTAssertEqual(store.selected?.transcript, meeting.transcript)
    }
    private func recording(_ root: URL) throws -> URL {
        let url = root.appendingPathComponent("fictional.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_000)); buffer.frameLength = 32_000
        memset(buffer.floatChannelData![0], 0, 32_000 * MemoryLayout<Float>.size)
        let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer)
        return url
    }
    func testRecordingReaderPreservesDurationOffsetAndSequence() throws {
        let reader = try MeetingRecordingReader(url: recording(directory()), offset: 12, streaming: true)
        var packets: [MeetingAudioPacket] = []
        while let packet = try reader.next() { packets.append(packet) }
        XCTAssertEqual(packets.reduce(0) { $0 + $1.pcm.count }, 64_000)
        XCTAssertEqual(packets.first?.offset, 12); XCTAssertEqual(packets.last?.endOffset, 14)
        XCTAssertEqual(packets.map(\.sequence), Array(0..<UInt64(packets.count)))
    }
    func testRecordingRetranscriptionKeepsPreviousTranscriptForUndo() async throws {
        let root = try directory(), audio = try recording(root)
        var meeting = MeetingRecord(); meeting.transcript = [.init(speaker: "甲", text: "原对话", offset: 0)]
        meeting.audio = [.init(filename: audio.lastPathComponent, offset: 0, duration: 2)]; meeting.capturedDuration = 2
        struct Snapshot: Encodable { var meetings: [MeetingRecord]; var configuration: MeetingPiConfiguration }
        var configuration = MeetingPiConfiguration(); configuration.transcriptionModel = "qwen-audio-3.1-asr-flash"
        try JSONEncoder().encode(Snapshot(meetings: [meeting], configuration: configuration)).write(to: root.appendingPathComponent("meetings.json"))
        let store = MeetingStore(directory: root, ai: ReplayAI(), automaticallyUpdate: false)
        store.retranscribe(meeting.id); try await wait { store.retranscribingID == nil }
        XCTAssertNil(store.error); XCTAssertEqual(store.selected?.transcript.first?.text, "虚构重新转写结果")
        store.restoreTranscript(meeting.id); XCTAssertEqual(store.selected?.transcript, meeting.transcript)
    }
}

private struct ReplayAI: MeetingAIClient {
    func updateMinutes(configuration: MeetingPiConfiguration, minutes: String, lines: [MeetingTranscriptLine]) async throws -> String { "虚构纪要" }
    func transcribe(configuration: MeetingPiConfiguration, packet: MeetingAudioPacket, speakers: [String]) async throws -> [MeetingTranscriptLine] {
        [.init(speaker: "未区分", text: "虚构重新转写结果", offset: packet.offset)]
    }
}
