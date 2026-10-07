import XCTest
@testable import WorkFollow

private actor StreamingAI: MeetingStreamingAIClient {
    private var calls: [[MeetingTranscriptLine]] = []
    func updateMinutes(configuration: MeetingPiConfiguration, minutes: String,
                       lines: [MeetingTranscriptLine]) async throws -> String {
        calls.append(lines); return "定稿纪要"
    }
    func transcribe(configuration: MeetingPiConfiguration, packet: MeetingAudioPacket,
                    speakers: [String]) async throws -> [MeetingTranscriptLine] { XCTFail("Must stream"); return [] }
    func openStream(configuration: MeetingPiConfiguration, offset: Double,
                    onEvent: @escaping @MainActor @Sendable (MeetingStreamEvent) -> Void) async throws -> any MeetingAudioStream {
        StreamingFixture(onEvent: onEvent, offset: offset)
    }
    func summaries() -> [[MeetingTranscriptLine]] { calls }
}
private actor StreamingFixture: MeetingAudioStream {
    let onEvent: @MainActor @Sendable (MeetingStreamEvent) -> Void
    let offset: Double
    var count = 0
    init(onEvent: @escaping @MainActor @Sendable (MeetingStreamEvent) -> Void, offset: Double) {
        self.onEvent = onEvent; self.offset = offset
    }
    func append(_ packet: MeetingAudioPacket) async throws {
        count += 1
        await onEvent(MeetingStreamEvent(kind: "preview", itemID: "turn", text: count == 1 ? "预算三千" : "预算两千五百", offset: offset, message: nil))
    }
    func finish() async throws {
        try await _Concurrency.Task.sleep(nanoseconds: 30_000_000)
        for _ in 0..<2 {
            await onEvent(MeetingStreamEvent(kind: "final", itemID: "turn", text: "预算两千五百元。", offset: offset, message: nil))
        }
    }
    nonisolated func cancel() {}
}

@MainActor
final class MeetingStreamingTests: XCTestCase {
    func testInstalledPiStreamDeliversFinalBeforeStopReturns() async throws {
        guard ProcessInfo.processInfo.environment["MEETING_PI_INTEGRATION"] == "1" else {
            throw XCTSkip("Enable MEETING_PI_INTEGRATION=1")
        }
        let root = try directory()
        let fixture = root.appendingPathComponent("stream-fixture.mjs")
        try """
        export default function(pi) {
          pi.registerCommand('wf-meeting-stream', {description:'Synthetic transport only',handler:async(args,ctx)=>{
            const input=JSON.parse(args);
            if(input.op==='append')ctx.ui.notify('WF_MEETING_STREAM_EVENT '+JSON.stringify({kind:'preview',itemID:'one',text:'草稿',offset:0}),'info');
            if(input.op==='stop')ctx.ui.notify('WF_MEETING_STREAM_EVENT '+JSON.stringify({kind:'final',itemID:'one',text:'最终文字',offset:0}),'info');
            ctx.ui.notify('WF_MEETING_STREAM_ACK '+JSON.stringify({id:input.id,op:input.op}),'info');
          }});
        }
        """.write(to: fixture, atomically: true, encoding: .utf8)
        var updates: [MeetingStreamEvent] = []
        let session = try MeetingPiStreamingSession(configuration: MeetingPiConfiguration(), extensionPath: fixture.path) { updates.append($0) }
        defer { session.cancel() }
        try await session.command(["op": "start", "offset": 0])
        try await session.append(MeetingAudioPacket(pcm: Data(repeating: 1, count: 8000), offset: 0))
        XCTAssertEqual(updates.map(\.kind), ["preview"])
        try await session.finish()
        XCTAssertEqual(updates.map(\.kind), ["preview", "final"])
        XCTAssertEqual(updates.last?.text, "最终文字")
    }

    /// ACK 丢失注入（MEETING-AUDIO-002）：fixture 吞掉 seq 0 的第一次命令
    /// （不 ACK、不 append），Native 必须自动重试；扩展幂等保证只 append 一次。
    /// 快超时参数让用例秒级完成，真实节奏由 appendTimeout=12s 兜底。
    func testLostAcknowledgementIsRetriedWithoutDuplicateAppend() async throws {
        guard ProcessInfo.processInfo.environment["MEETING_PI_INTEGRATION"] == "1" else {
            throw XCTSkip("Enable MEETING_PI_INTEGRATION=1")
        }
        let root = try directory()
        let fixture = root.appendingPathComponent("ack-drop-fixture.mjs")
        try """
        export default function(pi) {
          let dropped = false; const appended = new Set();
          pi.registerCommand('wf-meeting-stream', {description:'ACK-drop fixture',handler:async(args,ctx)=>{
            const input=JSON.parse(args);
            if(input.op==='append'){
              if(!dropped){dropped=true;return;}
              if(!appended.has(input.sequence)){
                appended.add(input.sequence);
                ctx.ui.notify('WF_MEETING_STREAM_EVENT '+JSON.stringify({kind:'preview',itemID:'one',text:'草稿'+input.sequence,offset:0}),'info');
              }
            }
            ctx.ui.notify('WF_MEETING_STREAM_ACK '+JSON.stringify({id:input.id,op:input.op,sequence:input.sequence??null}),'info');
          }});
        }
        """.write(to: fixture, atomically: true, encoding: .utf8)
        var updates: [MeetingStreamEvent] = []
        let session = try MeetingPiStreamingSession(configuration: MeetingPiConfiguration(),
                                                    extensionPath: fixture.path,
                                                    onEvent: { updates.append($0) },
                                                    appendAttempts: 3, appendTimeout: 0.5)
        defer { session.cancel() }
        try await session.command(["op": "start", "offset": 0])
        // 第一次 append 的 ACK 被 fixture 吞掉：session 内部重试后成功。
        try await session.append(MeetingAudioPacket(pcm: Data(repeating: 1, count: 8000), offset: 0, sequence: 0))
        try await session.append(MeetingAudioPacket(pcm: Data(repeating: 2, count: 8000), offset: 0.25, sequence: 1))
        try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(updates.filter { $0.kind == MeetingStreamKind.preview }.map(\.text),
                       ["草稿0", "草稿1"],
                       "重试必须成功，且扩展幂等保证同一包只 append 一次")
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-stream-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await _Concurrency.Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Streaming condition did not settle")
    }
    func testDraftCorrectionStaysEphemeralAndFinalizesInOriginatingMeetingOnce() async throws {
        let root = try directory(), ai = StreamingAI()
        let store = MeetingStore(directory: root, ai: ai, automaticallyUpdate: false)
        store.create(); let first = try XCTUnwrap(store.selectedID)
        let connected = try await store.connectInputStream(for: first, offset: 7)
        XCTAssertTrue(connected)
        store.receiveChunk(MeetingAudioPacket(pcm: Data(repeating: 1, count: 8000), offset: 7), meetingID: first)
        try await wait { store.streamDrafts[first]?["turn"]?.text == "预算三千" }
        let rowID = store.streamDrafts[first]?["turn"]?.id
        XCTAssertTrue(store.selected!.transcript.isEmpty)
        store.updateMinutesNow()
        let before = await ai.summaries(); XCTAssertTrue(before.isEmpty)
        store.create(); let second = try XCTUnwrap(store.selectedID)
        store.receiveChunk(MeetingAudioPacket(pcm: Data(repeating: 1, count: 8000), offset: 7.25), meetingID: first)
        try await wait { store.streamDrafts[first]?["turn"]?.text == "预算两千五百" }
        XCTAssertEqual(store.streamDrafts[first]?.count, 1)
        store.stopRecording()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in store.flush { _ in c.resume() } }
        let record = try XCTUnwrap(store.meetings.first { $0.id == first })
        XCTAssertEqual(record.transcript.map(\.text), ["预算两千五百元。"])
        XCTAssertEqual(record.transcript.first?.id, rowID)
        XCTAssertEqual(record.transcript.first?.speaker, "未区分")
        XCTAssertTrue(store.meetings.first { $0.id == second }!.transcript.isEmpty)
        XCTAssertTrue(store.streamDrafts[first]?.isEmpty ?? true)
        // 产品决定：纪要改为按钮点击生成，停止录音不再自动触发——
        // 用户选回这条会议再点按钮（updateMinutesNow 走 selectedID）。
        store.selectedID = first
        store.updateMinutesNow()
        try await wait { !store.updatingMinutes }
        let summaries = await ai.summaries()
        XCTAssertEqual(summaries.flatMap { $0 }.map(\.text), ["预算两千五百元。"])
        let saved = try String(contentsOf: root.appendingPathComponent("meetings.json"), encoding: .utf8)
        XCTAssertFalse(saved.contains("预算三千"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["meetings.json"])
    }
    func testQuarterSecondTransportPacketsPreserveEveryByteAndOffsets() {
        var capture = MeetingPCMAccumulator(offset: 3, segmentSeconds: 0.25)
        let input = Data(repeating: 17, count: 18402)
        var packets = capture.append(input)
        if let tail = capture.finish() { packets.append(tail) }
        XCTAssertEqual(packets.map(\.offset), [3, 3.25, 3.5])
        XCTAssertEqual(packets.reduce(into: Data()) { $0.append($1.pcm) }, input)
    }
    func testStreamFailureDiscardsOnlyDraftAndPreservesFinalizedSpeech() async throws {
        let store = MeetingStore(directory: try directory(), ai: StreamingAI(), automaticallyUpdate: false)
        store.create(); let id = try XCTUnwrap(store.selectedID)
        _ = try await store.connectInputStream(for: id, offset: 0)
        store.receiveStreamEvent(MeetingStreamEvent(kind: "final", itemID: "done", text: "已定稿", offset: 0, message: nil), meetingID: id)
        store.receiveStreamEvent(MeetingStreamEvent(kind: "preview", itemID: "draft", text: "未完成", offset: 1, message: nil), meetingID: id)
        store.receiveStreamEvent(MeetingStreamEvent(kind: "error", itemID: nil, text: nil, offset: nil, message: "测试中断"), meetingID: id)
        XCTAssertEqual(store.selected?.transcript.map(\.text), ["已定稿"])
        XCTAssertTrue(store.streamDrafts[id]?.isEmpty ?? true)
        XCTAssertFalse(store.transcribing)
        XCTAssertEqual(store.error, "测试中断")
        // A late message from the closed stream must not resurrect the draft.
        store.receiveStreamEvent(MeetingStreamEvent(kind: "preview", itemID: "draft", text: "迟到", offset: 1, message: nil), meetingID: id)
        XCTAssertTrue(store.streamDrafts[id]?.isEmpty ?? true)
    }
}
