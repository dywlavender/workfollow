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
        XCTAssertEqual(tracker.snapshot.first { $0.id == "t5" }?.status, .recording,
                       "还在讲话中的 turn 不是缺失，留给停止排空流程（003）处理")
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
        // 流关闭：awaitingFinal 判缺失，recording 不受影响（003 的停止排空处理）。
        store.receiveStreamEvent(MeetingStreamEvent(kind: MeetingStreamKind.error,
                                                    itemID: nil, text: nil, offset: nil, message: "x"), meetingID: id)
        XCTAssertEqual(store.speechTurns.first { $0.id == "turn-a" }?.status, .missingFinal)
        XCTAssertEqual(store.speechTurns.first { $0.id == "turn-b" }?.status, .recording)
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
