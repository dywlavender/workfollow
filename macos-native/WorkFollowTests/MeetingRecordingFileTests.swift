import AVFoundation
import XCTest
@testable import WorkFollow

private actor RecordedPackets {
    private var bytes = Data()
    func append(_ packet: MeetingAudioPacket) { bytes.append(packet.pcm) }
    func read() -> Data { bytes }
}

@MainActor
final class MeetingRecordingFileTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-recording-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func input() throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                                channels: 2, interleaved: false))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        input.frameLength = 4_800
        for index in 0..<4_800 {
            input.floatChannelData![0][index] = 0.125
            input.floatChannelData![1][index] = 0.25
        }
        return input
    }

    func testSourcePreservesStereoSamplesAndWAVIncludesUnsentStopTail() async throws {
        let root = try directory(), buffer = try input()
        let source = root.appendingPathComponent("original.caf"), wav = root.appendingPathComponent("asr.wav")
        let writer = try MeetingRecordingWriter(sourceURL: source, transcriptionURL: wav, format: buffer.format)
        let capture = try MeetingRecordingCapture(writer: writer, format: buffer.format, offset: 0,
                                                 streaming: true, transport: nil)
        for _ in 0..<11 { XCTAssertNil(try capture.consume(buffer)) }
        // The engine reuses its input buffer after the callback returns.
        for channel in 0..<2 { for index in 0..<4_800 { buffer.floatChannelData![channel][index] = 0 } }
        capture.finishCapture()
        let result = try await writer.finish()
        let original = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        XCTAssertEqual(original.length, 52_800)
        XCTAssertEqual(original.processingFormat.sampleRate, 48_000)
        XCTAssertEqual(original.processingFormat.channelCount, 2)
        let samples = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: original.processingFormat, frameCapacity: 52_800))
        try original.read(into: samples)
        XCTAssertEqual(samples.floatChannelData![0][52_799], 0.125)
        XCTAssertEqual(samples.floatChannelData![1][52_799], 0.25)
        XCTAssertEqual(result.sourceDuration, 1.1, accuracy: 0.0001)
        let normalized = try AVAudioFile(forReading: wav)
        XCTAssertEqual(normalized.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(normalized.fileFormat.channelCount, 1)
        XCTAssertEqual(result.transcriptionDuration, Double(normalized.length) / 16_000)
        XCTAssertGreaterThan(result.transcriptionDuration, 1.05)
    }

    func testTranscriptionFailureDoesNotStopSavingSubsequentAudio() async throws {
        let root = try directory(), buffer = try input()
        let writer = try MeetingRecordingWriter(sourceURL: root.appendingPathComponent("original.caf"),
                                               transcriptionURL: root.appendingPathComponent("asr.wav"), format: buffer.format)
        let transport = MeetingAudioTransport(maximumBytes: 60 * 32_000) { _ in throw MeetingPiError.failed }
        let capture = try MeetingRecordingCapture(writer: writer, format: buffer.format, offset: 0,
                                                 streaming: true, transport: transport)
        var failed = false
        transport.onError = { _ in capture.detachTranscription(); failed = true }
        for _ in 0..<4 { XCTAssertNil(try capture.consume(buffer)) }
        for _ in 0..<100 {
            if failed { break }
            try await _Concurrency.Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(failed)
        for _ in 0..<16 { XCTAssertNil(try capture.consume(buffer)) }
        capture.finishCapture()
        let result = try await writer.finish()
        XCTAssertEqual(result.sourceDuration, 2, accuracy: 0.0001)
        XCTAssertGreaterThan(result.transcriptionDuration, 1.95)
        XCTAssertEqual(try AVAudioFile(forReading: root.appendingPathComponent("original.caf")).length, 96_000)
    }

    func testSavedASRWAVMatchesEveryDeliveredPacketIncludingTail() async throws {
        let root = try directory(), buffer = try input(), packets = RecordedPackets()
        let wav = root.appendingPathComponent("asr.wav")
        let writer = try MeetingRecordingWriter(sourceURL: root.appendingPathComponent("original.caf"),
                                               transcriptionURL: wav, format: buffer.format)
        let transport = MeetingAudioTransport(maximumBytes: 60 * 32_000) { await packets.append($0) }
        let capture = try MeetingRecordingCapture(writer: writer, format: buffer.format, offset: 0,
                                                 streaming: true, transport: transport)
        for _ in 0..<11 { _ = try capture.consume(buffer) }
        capture.finishCapture(); transport.stopAccepting(); _ = try await writer.finish()
        for _ in 0..<100 {
            if !transport.isBusy { break }
            try await _Concurrency.Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertFalse(transport.isBusy)
        let file = try AVAudioFile(forReading: wav, commonFormat: .pcmFormatInt16, interleaved: true)
        let samples = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: samples)
        let stored = Data(bytes: try XCTUnwrap(samples.int16ChannelData?.pointee), count: Int(samples.frameLength) * 2)
        let delivered = await packets.read()
        XCTAssertEqual(stored, delivered)
        XCTAssertGreaterThan(stored.count, 32_000)
    }

    func testRecordingReferencesSurvivePersistenceAndFilesCanBeLocated() async throws {
        struct Snapshot: Encodable { let meetings: [MeetingRecord]; let configuration: MeetingPiConfiguration }
        let root = try directory(), buffer = try input()
        var meeting = MeetingRecord()
        let base = "meeting-audio/\(meeting.id.uuidString)/test"
        let chunk = MeetingAudioChunk(filename: base + ".caf", offset: 0, duration: 0.1,
                                      transcriptionFilename: base + "-asr.wav", transcriptionModel: "test-model")
        let writer = try MeetingRecordingWriter(sourceURL: root.appendingPathComponent(chunk.filename),
            transcriptionURL: root.appendingPathComponent(chunk.transcriptionFilename!), format: buffer.format)
        let capture = try MeetingRecordingCapture(writer: writer, format: buffer.format, offset: 0,
                                                 streaming: true, transport: nil)
        _ = try capture.consume(buffer); capture.finishCapture(); _ = try await writer.finish()
        meeting.audio = [chunk]
        try JSONEncoder().encode(Snapshot(meetings: [meeting], configuration: MeetingPiConfiguration()))
            .write(to: root.appendingPathComponent("meetings.json"))
        let store = MeetingStore(directory: root, automaticallyUpdate: false)
        XCTAssertEqual(store.selected?.audio.first?.transcriptionModel, "test-model")
        XCTAssertEqual(store.recordingFiles(for: try XCTUnwrap(store.selected)).count, 2)
        store.rename("保存后的会议")
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in store.flush { _ in c.resume() } }
        let restored = MeetingStore(directory: root, automaticallyUpdate: false)
        XCTAssertEqual(restored.selected?.title, "保存后的会议")
        XCTAssertEqual(restored.selected?.audio.first?.transcriptionFilename, chunk.transcriptionFilename)
        XCTAssertEqual(restored.selected?.duration, 0.1)
    }
}
