import XCTest
@testable import WorkFollow

private actor MeetingAITestDouble: MeetingAIClient {
    var inputs: [(String, [MeetingTranscriptLine])] = []
    var failure = false
    func failNext() { failure = true }
    func updateMinutes(configuration: MeetingPiConfiguration, minutes: String,
                       lines: [MeetingTranscriptLine]) async throws -> String {
        inputs.append((minutes, lines))
        try await _Concurrency.Task.sleep(nanoseconds: 30_000_000)
        if failure { failure = false; throw MeetingPiError.failed }
        return minutes + lines.map(\.text).joined(separator: "\n") + "\n"
    }
    func transcribe(configuration: MeetingPiConfiguration, packet: MeetingAudioPacket,
                    speakers: [String]) async throws -> [MeetingTranscriptLine] { [] }
    func calls() -> [(String, [MeetingTranscriptLine])] { inputs }
}

@MainActor
final class MeetingStoreTests: XCTestCase {
    func testNoNewTranscriptPreservesMinutesWithoutStartingPi() async throws {
        var configuration = MeetingPiConfiguration()
        configuration.executable = "/nonexistent-pi"
        let output = try await MeetingPiClient().updateMinutes(configuration: configuration,
                                                              minutes: "原纪要\n", lines: [])
        XCTAssertEqual(output, "原纪要\n")
    }

    func testAlreadySummarizedLinesDoNotTriggerAnotherUpdate() async throws {
        let ai = MeetingAITestDouble()
        let store = MeetingStore(directory: try directory(), ai: ai, automaticallyUpdate: false)
        store.create(); store.appendManual("已确认决定", speaker: "A")
        store.updateMinutesNow(); try await waitForSummary(store)
        let previous = store.selected?.minutes
        store.updateMinutesNow(); try await waitForSummary(store)
        let calls = await ai.calls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(store.selected?.minutes, previous)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func waitForSummary(_ store: MeetingStore) async throws {
        for _ in 0..<100 {
            if !store.updatingMinutes { return }
            try await _Concurrency.Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Summary did not settle")
    }

    func testRollingMinutesOnlySendNewLinesAndKeepExistingMinutes() async throws {
        let ai = MeetingAITestDouble()
        let store = MeetingStore(directory: try directory(), ai: ai, automaticallyUpdate: false)
        store.create(); store.appendManual("明确下周提交", speaker: "A")
        store.updateMinutesNow()
        for _ in 0..<100 {
            if await ai.calls().count > 0 { break }
            try await _Concurrency.Task.sleep(nanoseconds: 1_000_000)
        }
        store.appendManual("期限改为周五", speaker: "B")
        store.updateMinutesNow() // coalesces while first request is in flight
        try await waitForSummary(store)
        let calls = await ai.calls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].1.map(\.text), ["明确下周提交"])
        XCTAssertEqual(calls[1].1.map(\.text), ["期限改为周五"])
        XCTAssertTrue(calls[1].0.contains("明确下周提交"))
        XCTAssertEqual(store.selected?.summarizedLineCount, 2)
    }

    func testSelectionChangeDoesNotWriteMinutesIntoAnotherMeeting() async throws {
        let store = MeetingStore(directory: try directory(), ai: MeetingAITestDouble(), automaticallyUpdate: false)
        store.create(); let first = try XCTUnwrap(store.selectedID)
        store.appendManual("会议一的决议", speaker: "A"); store.updateMinutesNow()
        store.create(); let second = try XCTUnwrap(store.selectedID)
        try await waitForSummary(store)
        XCTAssertTrue(store.meetings.first { $0.id == first }?.minutes.contains("会议一") == true)
        XCTAssertEqual(store.meetings.first { $0.id == second }?.minutes, "")
    }

    func testFailureKeepsOldMinutesAndRetryDoesNotLoseNewSpeech() async throws {
        let ai = MeetingAITestDouble()
        let store = MeetingStore(directory: try directory(), ai: ai, automaticallyUpdate: false)
        store.create(); store.appendManual("旧决议", speaker: "A"); store.updateMinutesNow()
        try await waitForSummary(store)
        let previous = store.selected?.minutes
        await ai.failNext()
        store.appendManual("新决议", speaker: "B"); store.updateMinutesNow()
        try await waitForSummary(store)
        XCTAssertEqual(store.selected?.minutes, previous)
        XCTAssertEqual(store.selected?.summarizedLineCount, 1)
        XCTAssertNotNil(store.error)
        store.updateMinutesNow(); try await waitForSummary(store)
        XCTAssertEqual(store.selected?.summarizedLineCount, 2)
        let calls = await ai.calls()
        XCTAssertEqual(calls.last?.1.map(\.text), ["新决议"])
        XCTAssertEqual(calls.last?.0, previous)
    }

    func testManualEditStopsAutomaticMinutesAndResumeHandsItBack() async throws {
        let ai = MeetingAITestDouble()
        let store = MeetingStore(directory: try directory(), ai: ai, automaticallyUpdate: false)
        store.create()
        store.appendManual("原始发言", speaker: "A")

        store.editMinutes("我手写的纪要")
        XCTAssertEqual(store.selected?.minutes, "我手写的纪要")
        XCTAssertTrue(store.selected?.minutesIsManual == true)

        // 手动接管后 Pi 一个字都不该写，哪怕显式触发。
        store.updateMinutesNow()
        try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(store.selected?.minutes, "我手写的纪要")
        // ⚠️ `await` 不能写在 `XCTAssertEqual` 里（autoclosure 不支持并发），先取出来。
        let callsWhileManual = await ai.calls()
        XCTAssertEqual(callsWhileManual.count, 0)

        // 交回自动：用户写的内容成为下一次更新的基底，不被丢掉。
        store.resumeAutomaticMinutes()
        XCTAssertNil(store.selected?.minutesEditedByUser)
        try await waitForSummary(store)
        let calls = await ai.calls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].0, "我手写的纪要")
        XCTAssertTrue(store.selected?.minutes.contains("原始发言") == true)
    }

    /// 存量 `meetings.json` 里没有 `minutesEditedByUser` 这个键。
    /// 它必须是**可选**的：Swift 合成的 `Codable` 不会用属性默认值去填缺键，
    /// 声明成非可选 `Bool = false` 会让所有旧文件直接解码失败。
    func testLegacyRecordWithoutManualFlagStillDecodes() throws {
        let legacy = #"{"id":"6B29FC40-CA47-1067-B31D-00DD010662DA","title":"旧会议","#
            + #""createdAt":774000000,"audio":[],"transcript":[],"minutes":"旧纪要","summarizedLineIDs":[]}"#
        let record = try JSONDecoder().decode(MeetingRecord.self, from: Data(legacy.utf8))
        XCTAssertEqual(record.title, "旧会议")
        XCTAssertEqual(record.minutes, "旧纪要")
        XCTAssertNil(record.minutesEditedByUser)
        XCTAssertFalse(record.minutesIsManual)
    }

    func testPersistenceAndEmptyExtensionAreExplicit() async throws {
        let root = try directory()
        let store = MeetingStore(directory: root, ai: MeetingAITestDouble(), automaticallyUpdate: false)
        store.create(); store.rename("项目例会"); store.appendManual("讨论预算", speaker: "手动记录")
        await store.startRecording()
        XCTAssertFalse(store.audioConfigured)
        XCTAssertNotNil(store.error)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.flush { _ in continuation.resume() }
        }
        let restored = MeetingStore(directory: root, automaticallyUpdate: false)
        XCTAssertEqual(restored.selected?.title, "项目例会")
        XCTAssertEqual(restored.selected?.transcript.first?.text, "讨论预算")
    }

    func testAudioProtocolOffsetsAndUnknownSpeakers() throws {
        let lines = try MeetingPiClient.decodeAudioResult(
            #"{"version":1,"segments":[{"speaker":"B","text":"第二句","start":3},{"text":"第一句","start":0}]}"#,
            offset: 15)
        XCTAssertEqual(lines.map(\.offset), [15, 18])
        XCTAssertEqual(lines.map(\.speaker), ["未区分", "B"])
        XCTAssertThrowsError(try MeetingPiClient.decodeAudioResult("{}", offset: 0))
    }
}
