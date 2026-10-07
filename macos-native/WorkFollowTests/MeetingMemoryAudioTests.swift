import AVFoundation
import XCTest
@testable import WorkFollow

private actor MemoryAudioAI: MeetingAIClient {
    private var received: [MeetingAudioPacket] = []
    private let fail: Bool
    init(fail: Bool = false) { self.fail = fail }
    func transcribe(configuration: MeetingPiConfiguration, packet: MeetingAudioPacket,
                    speakers: [String]) async throws -> [MeetingTranscriptLine] {
        received.append(packet)
        try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        if fail { throw MeetingPiError.failed }
        return [MeetingTranscriptLine(speaker: "A", text: "合成转写", offset: packet.offset)]
    }
    func updateMinutes(configuration: MeetingPiConfiguration, minutes: String,
                       lines: [MeetingTranscriptLine]) async throws -> String { "合成纪要" }
    func packets() -> [MeetingAudioPacket] { received }
}

@MainActor
final class MeetingMemoryAudioTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-memory-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func settle(_ store: MeetingStore) async throws {
        for _ in 0..<200 {
            if !store.transcribing && !store.updatingMinutes { return }
            try await _Concurrency.Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Audio did not settle")
    }
    func testSegmentationAndFinalTailHaveContinuousOffsets() {
        var capture = MeetingPCMAccumulator(offset: 7, segmentSeconds: 1)
        XCTAssertTrue(capture.append(Data(repeating: 1, count: 16_000)).isEmpty)
        let packets = capture.append(Data(repeating: 2, count: 64_000))
        XCTAssertEqual(packets.map(\.offset), [7, 8])
        XCTAssertEqual(packets.map(\.duration), [1, 1])
        XCTAssertEqual(capture.finish()?.offset, 9)
        XCTAssertEqual(capture.duration, 2.5)
        XCTAssertNil(capture.finish())
    }
    func testQuietBoundarySplitsAfterSpeechInsteadOfAtFifteenSeconds() {
        var capture = MeetingPCMAccumulator(preferSpeechBoundaries: true)
        // 0x0101 = 257, above the conservative quiet-energy threshold.
        XCTAssertTrue(capture.append(Data(repeating: 1, count: 12 * 32_000)).isEmpty)
        XCTAssertTrue(capture.append(Data(repeating: 0, count: 8_000)).isEmpty)
        let packets = capture.append(Data(repeating: 0, count: 1_600))
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets.first?.duration ?? 0, 12.3, accuracy: 0.001)
        XCTAssertTrue(capture.append(Data(repeating: 1, count: 32_000)).isEmpty)
        XCTAssertEqual(capture.finish()?.offset ?? 0, 12.3, accuracy: 0.001)
    }
    func testContinuousSpeechHasBoundedPacketSizeAndNoLostBytes() {
        var capture = MeetingPCMAccumulator(preferSpeechBoundaries: true)
        let input = Data(repeating: 1, count: 21 * 32_000)
        let packets = capture.append(input)
        XCTAssertEqual(packets.first?.duration, 20)
        let tail = capture.finish()
        XCTAssertEqual(tail?.offset, 20)
        XCTAssertEqual(tail?.duration, 1)
        XCTAssertEqual((packets.first?.pcm.count ?? 0) + (tail?.pcm.count ?? 0), input.count)
    }
    func testResponsivePolicyPublishesAtShortPause() {
        var capture = MeetingPCMAccumulator(preferSpeechBoundaries: true, speechBoundaryPolicy: .responsive)
        XCTAssertTrue(capture.append(Data(repeating: 1, count: 2 * 32_000)).isEmpty)
        XCTAssertTrue(capture.append(Data(repeating: 0, count: 8_000)).isEmpty)
        let packets = capture.append(Data(repeating: 0, count: 1_600))
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets.first?.duration ?? 0, 2.3, accuracy: 0.001)
    }
    func testResponsiveContinuousSpeechHasFiveSecondCapAndExactTail() {
        var capture = MeetingPCMAccumulator(offset: 7, preferSpeechBoundaries: true,
                                            speechBoundaryPolicy: .responsive)
        let input = Data(repeating: 1, count: 11 * 32_000 + 160)
        let packets = capture.append(input)
        let tail = capture.finish()
        XCTAssertEqual(packets.map(\.duration), [5, 5])
        XCTAssertEqual(packets.map(\.offset), [7, 12])
        XCTAssertEqual(tail?.offset, 17)
        var output = packets.reduce(into: Data()) { $0.append($1.pcm) }
        output.append(tail?.pcm ?? Data())
        XCTAssertEqual(output, input)
        XCTAssertNil(capture.finish())
    }
    func testNativeConverterProcessesSyntheticStereoAndFlushesOnce() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                                channels: 2, interleaved: false))
        let capture = try MeetingPCMCapture(format: format, offset: 3)
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        input.frameLength = 4_800
        for channel in 0..<2 {
            for frame in 0..<4_800 { input.floatChannelData![channel][frame] = 0.1 }
        }
        for _ in 0..<10 { _ = try capture.consume(input) }
        let tail = try XCTUnwrap(capture.finish().first)
        XCTAssertEqual(tail.offset, 3)
        XCTAssertEqual(tail.duration, 1, accuracy: 0.02)
        XCTAssertTrue(capture.finish().isEmpty)
    }
    func testAudioNeverEntersSnapshotAndSelectionDoesNotRedirectResults() async throws {
        let directory = try root(), ai = MemoryAudioAI()
        let store = MeetingStore(directory: directory, ai: ai, automaticallyUpdate: false)
        store.create(); let first = try XCTUnwrap(store.selectedID)
        store.configuration.audioExtension = "synthetic-fixture"
        store.receiveChunk(MeetingAudioPacket(pcm: Data(repeating: 123, count: 32_000), offset: 0), meetingID: first)
        store.create()
        try await settle(store)
        let received = await ai.packets()
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(store.meetings.first { $0.id == first }?.transcript.count, 1)
        XCTAssertTrue(store.selected!.transcript.isEmpty)
        XCTAssertEqual(store.bufferedAudioBytes, 0)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.flush { _ in continuation.resume() }
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files, ["meetings.json"])
        let json = try String(contentsOf: directory.appendingPathComponent("meetings.json"), encoding: .utf8)
        XCTAssertFalse(json.contains("e3t7")) // synthetic PCM encoded as base64 must not appear
        let restored = MeetingStore(directory: directory, automaticallyUpdate: false)
        let meeting = try XCTUnwrap(restored.meetings.first { $0.id == first })
        XCTAssertEqual(meeting.duration, 1)
        XCTAssertTrue(meeting.audio.isEmpty)
        XCTAssertEqual(meeting.transcript.first?.speaker, "A")
    }
    func testFailureReleasesAudioAndStopsQueueWithoutErasingText() async throws {
        let ai = MemoryAudioAI(fail: true)
        let store = MeetingStore(directory: try root(), ai: ai, automaticallyUpdate: false)
        store.create(); store.configuration.audioExtension = "synthetic-fixture"
        store.appendTranscriptForTesting("保留的文字", speaker: "B")
        let id = try XCTUnwrap(store.selectedID)
        for i in 0..<3 {
            store.receiveChunk(MeetingAudioPacket(pcm: Data(repeating: 0, count: 32_000), offset: Double(i)), meetingID: id)
        }
        try await settle(store)
        let calls = await ai.packets()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(store.bufferedAudioBytes, 0)
        XCTAssertEqual(store.selected?.transcript.first?.text, "保留的文字")
        XCTAssertNotNil(store.error)
    }
    func testBackpressureRejectsOversizedAudioAndClearsQueue() async throws {
        let store = MeetingStore(directory: try root(), ai: MemoryAudioAI(), automaticallyUpdate: false)
        store.create(); store.configuration.audioExtension = "synthetic-fixture"
        store.receiveChunk(MeetingAudioPacket(pcm: Data(repeating: 0, count: MeetingStore.maximumAudioBytes + 2), offset: 0),
                           meetingID: try XCTUnwrap(store.selectedID))
        XCTAssertEqual(store.bufferedAudioBytes, 0)
        XCTAssertFalse(store.transcribing)
        XCTAssertNotNil(store.error)
    }
}
