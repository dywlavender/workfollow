import AVFoundation
import Foundation

/// Read saved audio through the same conversion and packet boundaries as capture.
final class MeetingRecordingReader: @unchecked Sendable {
    private let file: AVAudioFile
    private let capture: MeetingPCMCapture
    private var pending: [MeetingAudioPacket] = []
    private var finished = false
    init(url: URL, offset: TimeInterval, streaming: Bool) throws {
        file = try AVAudioFile(forReading: url)
        capture = try MeetingPCMCapture(format: file.processingFormat, offset: offset, streaming: streaming)
    }
    func next() throws -> MeetingAudioPacket? {
        while pending.isEmpty && !finished {
            let remaining = file.length - file.framePosition
            if remaining <= 0 { pending += capture.finish(); finished = true; break }
            let frames = AVAudioFrameCount(min(remaining, max(1, AVAudioFramePosition(file.processingFormat.sampleRate / 4))))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { throw MeetingPiError.invalidResult }
            try file.read(into: buffer, frameCount: frames)
            _ = try capture.consume(buffer); pending += capture.drain()
        }
        return pending.isEmpty ? nil : pending.removeFirst()
    }
    func nextBatch(seconds: TimeInterval) throws -> MeetingAudioPacket? {
        guard var value = try next() else { return nil }
        while value.duration < seconds, let additional = try next() { value.pcm.append(additional.pcm) }
        return value
    }
}
