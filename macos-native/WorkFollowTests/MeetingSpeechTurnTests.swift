import XCTest
@testable import WorkFollow

/// MEETING-AUDIO-002：VAD turn 生命周期状态机。正常流程只是地基——
/// 关键是"有讲话但没有 Final"必须在宽限期后被明确判定，而不是悄悄消失。
final class MeetingSpeechTurnTrackerTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000_000)
    private lazy var tracker = MeetingSpeechTurnTracker(clock: { self.now })

    func testNormalLifecycleCompletesAndIsIdempotent() {
        tracker.speechStarted(itemID: "t1", at: 31.25)
        XCTAssertEqual(tracker.snapshot.map(\.status), [.recording])
        tracker.speechStopped(itemID: "t1", at: 34.80)
        XCTAssertEqual(tracker.snapshot.first?.end, 34.80)
        XCTAssertEqual(tracker.snapshot.map(\.status), [.awaitingFinal])
        tracker.finalize(itemID: "t1")
        tracker.finalize(itemID: "t1") // 迟到/重复 final 幂等
        XCTAssertEqual(tracker.snapshot.map(\.status), [.completed])
        XCTAssertTrue(tracker.missingFinalTurns.isEmpty)
    }

    func testAwaitingFinalExpiresIntoMissingAfterGracePeriod() {
        tracker.speechStarted(itemID: "t2", at: 10)
        tracker.speechStopped(itemID: "t2", at: 13)
        now += MeetingAudioReliabilityPolicy.finalGracePeriod - 1
        tracker.sweep()
        XCTAssertEqual(tracker.snapshot.map(\.status), [.awaitingFinal], "宽限期内不该误判")
        now += 2
        tracker.sweep()
        XCTAssertEqual(tracker.snapshot.map(\.status), [.missingFinal],
                       "有讲话但没有 Final 必须被明确判定，而不是悄悄消失")
        // 迟到的 final 仍把 turn 归位为 completed（文字由 final 路径落账）。
        tracker.finalize(itemID: "t2")
        XCTAssertEqual(tracker.snapshot.map(\.status), [.completed])
    }

    func testSpeechStoppedWithoutStartedStillCreatesATurn() {
        tracker.speechStopped(itemID: "t3", at: 5)
        XCTAssertEqual(tracker.snapshot.first?.status, .awaitingFinal)
        XCTAssertEqual(tracker.snapshot.first?.start, 5)
    }

    func testCloseForceSweepsEveryAwaitingTurnRegardlessOfGrace() {
        tracker.speechStarted(itemID: "t4", at: 0)
        tracker.speechStopped(itemID: "t4", at: 2)
        tracker.speechStarted(itemID: "t5", at: 3) // 还在讲话
        tracker.sweep(force: true)
        XCTAssertEqual(tracker.snapshot.first { $0.id == "t4" }?.status, .missingFinal,
                       "会话已关闭，awaitingFinal 不可能再等来 final")
        XCTAssertEqual(tracker.snapshot.first { $0.id == "t5" }?.status, .missingFinal,
                       "会话已关闭，缺少 stopped 的讲话也不可能再收到 Final")
        XCTAssertNil(tracker.snapshot.first { $0.id == "t5" }?.end)
    }

    func testResetClearsEverythingForANewSession() {
        tracker.speechStarted(itemID: "t6", at: 0)
        tracker.reset()
        XCTAssertTrue(tracker.snapshot.isEmpty)
        XCTAssertTrue(tracker.missingFinalTurns.isEmpty)
    }
}

/// Store 侧接线：流式事件驱动 turn 状态机；流关闭强制 sweep。
@MainActor
final class MeetingSpeechTurnStoreWiringTests: XCTestCase {
    func testHTTPModelDoesNotOpenWebSocket() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-http-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(directory: root, ai: TurnFixture(), automaticallyUpdate: false)
        store.configuration.model = "qwen-audio-3.1-asr-flash"
        store.create()
        let opened = try await store.connectInputStream(for: try XCTUnwrap(store.selectedID), offset: 0)
        XCTAssertFalse(opened)
        XCTAssertFalse(store.transcribing)
    }
    func testActiveStreamCannotBeDeletedButOtherMeetingCan() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-delete-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(directory: root, ai: TurnFixture(), automaticallyUpdate: false)
        store.create(); let active = try XCTUnwrap(store.selectedID)
        _ = try await store.connectInputStream(for: active, offset: 0)
        store.create(); let other = try XCTUnwrap(store.selectedID)
        XCTAssertFalse(store.canDelete(active))
        XCTAssertFalse(store.delete(active))
        XCTAssertTrue(store.delete(other))
        store.stopRecording()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in store.flush { _ in c.resume() } }
        XCTAssertTrue(store.delete(active))
    }
    func testLifecycleEventsDriveTurnTrackerAndCloseSweepsMissing() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-turn-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(directory: root, ai: TurnFixture(), automaticallyUpdate: false)
        store.create()
        _ = try await store.connectInputStream(for: try XCTUnwrap(store.selectedID), offset: 0)
        let id = try XCTUnwrap(store.selectedID)
        store.receiveStreamEvent(MeetingStreamEvent(kind: MeetingStreamKind.speechStarted,
                                                    itemID: "turn-a", text: nil, offset: 1, message: nil), meetingID: id)
        store.receiveStreamEvent(MeetingStreamEvent(kind: MeetingStreamKind.speechStopped,
                                                    itemID: "turn-a", text: nil, offset: 4, message: nil), meetingID: id)
        store.receiveStreamEvent(MeetingStreamEvent(kind: MeetingStreamKind.speechStarted,
                                                    itemID: "turn-b", text: nil, offset: 6, message: nil), meetingID: id)
        XCTAssertEqual(store.speechTurns.map(\.status), [.awaitingFinal, .recording])
        // 异常断流：等待定稿与缺少 stopped 的讲话都必须成为 Repair 输入。
        store.receiveStreamEvent(MeetingStreamEvent(kind: MeetingStreamKind.error,
                                                    itemID: nil, text: nil, offset: nil, message: "x"), meetingID: id)
        XCTAssertEqual(store.speechTurns.first { $0.id == "turn-a" }?.status, .missingFinal)
        XCTAssertEqual(store.speechTurns.first { $0.id == "turn-b" }?.status, .missingFinal)
        XCTAssertNil(store.speechTurns.first { $0.id == "turn-b" }?.end)
    }

    func testProductionDeadlineDetectsMissingWhileStreamRemainsOpen() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-deadline-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(directory: root, ai: TurnFixture(), automaticallyUpdate: false)
        store.create()
        let id = try XCTUnwrap(store.selectedID)
        _ = try await store.connectInputStream(for: id, offset: 0)
        func event(_ kind: String, _ item: String, text: String? = nil) {
            store.receiveStreamEvent(MeetingStreamEvent(kind: kind, itemID: item, text: text,
                                                        offset: 1, message: nil), meetingID: id)
        }
        for item in ["missing", "completed", "duplicate-stop"] {
            event(MeetingStreamKind.speechStarted, item)
            event(MeetingStreamKind.speechStopped, item)
        }
        event(MeetingStreamKind.finalText, "completed", text: "已定稿")
        store.create() // 切换所选会议不能取消原会话的 deadline。
        try await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000)
        event(MeetingStreamKind.speechStopped, "duplicate-stop")
        XCTAssertEqual(store.speechTurns.first { $0.id == "missing" }?.status, .awaitingFinal)
        try await _Concurrency.Task.sleep(nanoseconds: 2_200_000_000)
        // 没有调用 sweep / stop / close：这是生产 Task 的实际调度。
        XCTAssertTrue(store.transcribing)
        XCTAssertEqual(store.speechTurns.map(\.status), [.missingFinal, .completed, .missingFinal])
        event(MeetingStreamKind.finalText, "missing", text: "迟到定稿")
        XCTAssertEqual(store.speechTurns.first { $0.id == "missing" }?.status, .completed)
        store.stopRecording()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            store.flush { _ in c.resume() }
        }
    }

    func testClosedSessionDeadlineCannotExpireReusedIDInNewSession() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-deadline-reset-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(directory: root, ai: TurnFixture(), automaticallyUpdate: false)
        store.create()
        let id = try XCTUnwrap(store.selectedID)
        _ = try await store.connectInputStream(for: id, offset: 0)
        store.receiveStreamEvent(MeetingStreamEvent(kind: MeetingStreamKind.speechStopped,
                                                    itemID: "same", text: nil, offset: 1, message: nil), meetingID: id)
        store.receiveStreamEvent(MeetingStreamEvent(kind: MeetingStreamKind.error,
                                                    itemID: nil, text: nil, offset: nil, message: "断流"), meetingID: id)
        _ = try await store.connectInputStream(for: id, offset: 2)
        store.receiveStreamEvent(MeetingStreamEvent(kind: MeetingStreamKind.speechStarted,
                                                    itemID: "same", text: nil, offset: 2, message: nil), meetingID: id)
        try await _Concurrency.Task.sleep(nanoseconds: 4_200_000_000)
        XCTAssertEqual(store.speechTurns.map(\.status), [.recording])
        store.stopRecording()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            store.flush { _ in c.resume() }
        }
    }
}

/// 不出网的流式测试替身：只为接通 connectInputStream 的类型门槛。
private actor TurnStream: MeetingAudioStream {
    func append(_ packet: MeetingAudioPacket) async throws {}
    func finish() async throws {}
    nonisolated func cancel() {}
}

private actor TurnFixture: MeetingStreamingAIClient {
    func updateMinutes(configuration: MeetingPiConfiguration, minutes: String,
                       lines: [MeetingTranscriptLine]) async throws -> String { "纪要" }
    func transcribe(configuration: MeetingPiConfiguration, packet: MeetingAudioPacket,
                    speakers: [String]) async throws -> [MeetingTranscriptLine] { [] }
    func openStream(configuration: MeetingPiConfiguration, offset: Double,
                    onEvent: @escaping @MainActor @Sendable (MeetingStreamEvent) -> Void) async throws -> any MeetingAudioStream {
        TurnStream()
    }
}
