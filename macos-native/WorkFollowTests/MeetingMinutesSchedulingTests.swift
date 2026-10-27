import AppKit
import Combine
import SwiftUI
import XCTest
@testable import WorkFollow

private actor ControlledMinutesAI: MeetingAIClient {
    private var inputs: [(String, [MeetingTranscriptLine])] = []
    private var reply: CheckedContinuation<String, Error>?

    func updateMinutes(configuration: MeetingPiConfiguration, minutes: String,
                       lines: [MeetingTranscriptLine]) async throws -> String {
        inputs.append((minutes, lines))
        return try await withCheckedThrowingContinuation { reply = $0 }
    }
    func transcribe(configuration: MeetingPiConfiguration, packet: MeetingAudioPacket,
                    speakers: [String]) async throws -> [MeetingTranscriptLine] { [] }
    func calls() -> [(String, [MeetingTranscriptLine])] { inputs }
    func complete(_ text: String = "# 完整会议纪要") {
        let continuation = reply; reply = nil
        continuation?.resume(returning: text)
    }
    func fail() {
        let continuation = reply; reply = nil
        continuation?.resume(throwing: MeetingPiError.failed)
    }
}

@MainActor
private final class MinutesTestClock {
    private var now: TimeInterval = 0
    private var timers: [(deadline: TimeInterval, subject: PassthroughSubject<Date, Never>)] = []
    private(set) var intervals: [TimeInterval] = []

    func publisher(after interval: TimeInterval) -> AnyPublisher<Date, Never> {
        intervals.append(interval)
        let subject = PassthroughSubject<Date, Never>()
        timers.append((now + interval, subject))
        return subject.eraseToAnyPublisher()
    }
    func advance(by interval: TimeInterval) {
        now += interval
        let due = timers.filter { $0.deadline <= now }
        timers.removeAll { $0.deadline <= now }
        for timer in due { timer.subject.send(Date(timeIntervalSinceReferenceDate: now)) }
    }
}

@MainActor
final class MeetingMinutesSchedulingTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-minutes-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func wait(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await _Concurrency.Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Minutes generation did not settle")
    }

    func testManualMinutesButtonIsVisibleAndTriggersTheSharedGenerationSlot() async throws {
        for size in [CGSize(width: 1280, height: 800), CGSize(width: 900, height: 600)] {
            let ai = ControlledMinutesAI(), clock = MinutesTestClock()
            let store = MeetingStore(directory: try directory(), ai: ai, minutesTimer: clock.publisher)
            store.create()
            var buttonFrame = CGRect.zero
            let root = MeetingWorkspaceView(store: store)
                .environmentObject(AppEnvironment(directory: try directory()))
                .frame(width: size.width, height: size.height)
                .onPreferenceChange(MeetingMinutesButtonFrameKey.self) { buttonFrame = $0 }
            let host = NSHostingView(rootView: AnyView(root))
            let owner = InspectorPanelTestSupport.ownerWindow(for: host, width: size.width, height: size.height)
            defer { owner.contentView = nil; owner.close() }
            XCTAssertFalse(buttonFrame.isEmpty)
            XCTAssertTrue(host.bounds.contains(buttonFrame), "编写按钮必须在窗口内")
            XCTAssertLessThan(buttonFrame.midY, host.bounds.midY, "编写按钮应固定在纪要栏顶部")
            try InspectorPanelTestSupport.click(buttonFrame, in: host, window: owner)
            let emptyCalls = await ai.calls()
            XCTAssertTrue(emptyCalls.isEmpty, "没有定稿时按钮保持可见但不可提交")
            store.appendTranscriptForTesting("周五完成验收", speaker: "A")
            InspectorPanelTestSupport.settle(owner)
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to:
                    URL(fileURLWithPath: "/private/tmp/workfollow-meeting-minutes-\(Int(size.width)).png"))
            }
            try InspectorPanelTestSupport.click(buttonFrame, in: host, window: owner)
            try await wait { await ai.calls().count == 1 }
            XCTAssertTrue(store.updatingMinutes)
            XCTAssertFalse(store.canGenerateMinutes(for: try XCTUnwrap(store.selected)))
            try InspectorPanelTestSupport.click(buttonFrame, in: host, window: owner)
            let busyCalls = await ai.calls()
            XCTAssertEqual(busyCalls.count, 1)
            await ai.complete()
            try await wait { !store.updatingMinutes }
            InspectorPanelTestSupport.settle(owner)
            XCTAssertEqual(store.selected?.minutes, "# 完整会议纪要")
            XCTAssertTrue(store.canGenerateMinutes(for: try XCTUnwrap(store.selected)))
        }
    }

    func testAutomaticRegenerationWaitsFiveMinutesAndUsesAllFinalizedSpeech() async throws {
        let ai = ControlledMinutesAI(), clock = MinutesTestClock()
        let store = MeetingStore(directory: try directory(), ai: ai, minutesTimer: clock.publisher)
        store.create(); let id = try XCTUnwrap(store.selectedID)
        store.appendTranscriptForTesting("周一讨论", speaker: "A")
        store.appendTranscriptForTesting("周五交付", speaker: "B")
        store.startAutomaticMinutes(for: id)

        clock.advance(by: 299)
        XCTAssertFalse(store.updatingMinutes)
        let before = await ai.calls(); XCTAssertTrue(before.isEmpty)
        clock.advance(by: 1)
        XCTAssertTrue(store.updatingMinutes)
        XCTAssertFalse(store.canGenerateMinutes(for: try XCTUnwrap(store.selected)))
        try await wait { await ai.calls().count == 1 }
        store.appendTranscriptForTesting("新增验收要求", speaker: "A")
        await ai.complete()
        try await wait { !store.updatingMinutes }
        XCTAssertEqual(store.selected?.summarizedLineCount, 2)

        clock.advance(by: 299)
        XCTAssertFalse(store.updatingMinutes)
        clock.advance(by: 1)
        try await wait { await ai.calls().count == 2 }
        let calls = await ai.calls()
        XCTAssertEqual(calls[0].1.map(\.text), ["周一讨论", "周五交付"])
        XCTAssertEqual(calls[1].1.map(\.text), ["周一讨论", "周五交付", "新增验收要求"])
        XCTAssertTrue(calls.allSatisfy { $0.0.isEmpty })
        XCTAssertTrue(clock.intervals.allSatisfy { $0 == 300 })
        await ai.complete()
        try await wait { !store.updatingMinutes }
        XCTAssertEqual(store.selected?.summarizedLineIDs, store.selected?.transcript.map(\.id))
    }

    func testManualGenerationSuspendsTimerAndDoesNotQueueBusyTriggers() async throws {
        let ai = ControlledMinutesAI(), clock = MinutesTestClock()
        let store = MeetingStore(directory: try directory(), ai: ai, minutesTimer: clock.publisher)
        store.create(); store.appendTranscriptForTesting("明确决议", speaker: "A")
        store.startAutomaticMinutes(for: try XCTUnwrap(store.selectedID))
        clock.advance(by: 299)
        store.updateMinutesNow()
        store.updateMinutesNow()
        XCTAssertTrue(store.updatingMinutes)
        try await wait { await ai.calls().count == 1 }
        clock.advance(by: 600)
        let busyCalls = await ai.calls(); XCTAssertEqual(busyCalls.count, 1)
        await ai.complete()
        try await wait { !store.updatingMinutes }
        let completedCalls = await ai.calls(); XCTAssertEqual(completedCalls.count, 1)

        clock.advance(by: 299)
        XCTAssertFalse(store.updatingMinutes)
        clock.advance(by: 1)
        try await wait { await ai.calls().count == 2 }
        await ai.complete()
        try await wait { !store.updatingMinutes }
    }

    func testAutomaticGenerationBlocksManualAndStaysWithRecordingMeeting() async throws {
        let ai = ControlledMinutesAI(), clock = MinutesTestClock()
        let store = MeetingStore(directory: try directory(), ai: ai, minutesTimer: clock.publisher)
        store.create(); let recording = try XCTUnwrap(store.selectedID)
        store.appendTranscriptForTesting("正在录音的会议", speaker: "A")
        store.startAutomaticMinutes(for: recording)
        clock.advance(by: 300)
        try await wait { await ai.calls().count == 1 }

        store.create(); let other = try XCTUnwrap(store.selectedID)
        store.appendTranscriptForTesting("另一场历史会议", speaker: "B")
        XCTAssertFalse(store.canGenerateMinutes(for: try XCTUnwrap(store.selected)))
        store.updateMinutesNow()
        clock.advance(by: 900)
        let busyCalls = await ai.calls(); XCTAssertEqual(busyCalls.count, 1)
        await ai.complete("录音会议的纪要")
        try await wait { !store.updatingMinutes }
        XCTAssertEqual(store.meetings.first { $0.id == recording }?.minutes, "录音会议的纪要")
        XCTAssertEqual(store.meetings.first { $0.id == other }?.minutes, "")
        XCTAssertTrue(store.canGenerateMinutes(for: try XCTUnwrap(store.selected)))

        clock.advance(by: 300)
        try await wait { await ai.calls().count == 2 }
        let calls = await ai.calls()
        XCTAssertEqual(calls[1].1.map(\.text), ["正在录音的会议"])
        await ai.complete()
        try await wait { !store.updatingMinutes }
    }

    func testStoppingRecordingCancelsFutureRunsEvenWhenGenerationIsBusy() async throws {
        let ai = ControlledMinutesAI(), clock = MinutesTestClock()
        let store = MeetingStore(directory: try directory(), ai: ai, minutesTimer: clock.publisher)
        store.create(); store.appendTranscriptForTesting("会议内容", speaker: "A")
        store.startAutomaticMinutes(for: try XCTUnwrap(store.selectedID))
        clock.advance(by: 300)
        try await wait { await ai.calls().count == 1 }
        store.stopRecording()
        await ai.complete()
        try await wait { !store.updatingMinutes }
        clock.advance(by: 900)
        let calls = await ai.calls(); XCTAssertEqual(calls.count, 1)
        XCTAssertFalse(store.updatingMinutes)
    }

    func testEditingWhileGeneratingKeepsEditsUntilExplicitRegeneration() async throws {
        let ai = ControlledMinutesAI(), clock = MinutesTestClock()
        let store = MeetingStore(directory: try directory(), ai: ai, minutesTimer: clock.publisher)
        store.create(); store.appendTranscriptForTesting("已确认对话", speaker: "A")
        store.startAutomaticMinutes(for: try XCTUnwrap(store.selectedID))
        clock.advance(by: 300)
        try await wait { await ai.calls().count == 1 }
        store.editMinutes("用户在等待中修改的文字")
        await ai.complete("旧请求的输出")
        try await wait { !store.updatingMinutes }
        XCTAssertEqual(store.selected?.minutes, "用户在等待中修改的文字")
        clock.advance(by: 600)
        let editedCalls = await ai.calls(); XCTAssertEqual(editedCalls.count, 1)

        store.updateMinutesNow()
        try await wait { await ai.calls().count == 2 }
        await ai.complete("重新编写的纪要")
        try await wait { !store.updatingMinutes }
        XCTAssertEqual(store.selected?.minutes, "重新编写的纪要")
        XCTAssertFalse(store.selected?.minutesIsManual ?? true)
        clock.advance(by: 300)
        try await wait { await ai.calls().count == 3 }
        await ai.complete()
        try await wait { !store.updatingMinutes }
    }

    func testEmptyTranscriptSkipsRequestAndFailureReleasesGenerationSlot() async throws {
        let ai = ControlledMinutesAI(), clock = MinutesTestClock()
        let store = MeetingStore(directory: try directory(), ai: ai, minutesTimer: clock.publisher)
        store.create(); store.startAutomaticMinutes(for: try XCTUnwrap(store.selectedID))
        clock.advance(by: 300)
        XCTAssertFalse(store.updatingMinutes)
        XCTAssertFalse(store.canGenerateMinutes(for: try XCTUnwrap(store.selected)))
        let emptyCalls = await ai.calls(); XCTAssertTrue(emptyCalls.isEmpty)
        store.appendTranscriptForTesting("首次对话", speaker: "A")
        clock.advance(by: 300)
        try await wait { await ai.calls().count == 1 }
        await ai.fail()
        try await wait { !store.updatingMinutes }
        XCTAssertNotNil(store.error)
        XCTAssertTrue(store.canGenerateMinutes(for: try XCTUnwrap(store.selected)))
        clock.advance(by: 300)
        try await wait { await ai.calls().count == 2 }
        await ai.complete()
        try await wait { !store.updatingMinutes }
        XCTAssertNil(store.error)
    }
}
