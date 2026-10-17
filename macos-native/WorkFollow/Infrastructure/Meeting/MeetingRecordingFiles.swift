import AVFoundation
import Foundation

/// File writes use one utility queue. The microphone callback only copies buffers.
final class MeetingRecordingWriter: @unchecked Sendable {
    struct Result: Sendable {
        let sourceDuration: TimeInterval
        let transcriptionDuration: TimeInterval
    }
    private final class BufferCopy: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    }
    private let queue = DispatchQueue(label: "workfollow.meeting.recording.files", qos: .utility)
    private let lock = NSLock()
    private let sourceFormat: AVAudioFormat
    private let pcmFormat: AVAudioFormat
    private var sourceFile: AVAudioFile?
    private var transcriptionFile: AVAudioFile?
    private var sourceFrames: AVAudioFramePosition = 0
    private var writtenSourceFrames: AVAudioFramePosition = 0
    private var writtenTranscriptionFrames: AVAudioFramePosition = 0
    private var failure: Error?
    private var finishing = false
    var onError: (@Sendable (Error) -> Void)?
    var currentDuration: TimeInterval { lock.withLock { Double(sourceFrames) / sourceFormat.sampleRate } }

    init(sourceURL: URL, transcriptionURL: URL, format: AVAudioFormat) throws {
        sourceFormat = format
        guard let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                           channels: 1, interleaved: true) else { throw CocoaError(.coderInvalidValue) }
        self.pcmFormat = pcmFormat
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        sourceFile = try AVAudioFile(forWriting: sourceURL, settings: format.settings,
                                    commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        transcriptionFile = try AVAudioFile(forWriting: transcriptionURL, settings: pcmFormat.settings,
                                           commonFormat: .pcmFormatInt16, interleaved: true)
    }

    func appendSource(_ input: AVAudioPCMBuffer) throws {
        guard let copy = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: input.frameLength) else {
            throw CocoaError(.coderInvalidValue)
        }
        copy.frameLength = input.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input.audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in source.indices {
            if let from = source[index].mData, let to = destination[index].mData {
                memcpy(to, from, Int(source[index].mDataByteSize))
            }
        }
        let buffer = BufferCopy(copy)
        lock.withLock {
            guard !finishing else { return }
            sourceFrames += AVAudioFramePosition(input.frameLength)
            queue.async { [self] in
                guard failure == nil else { return }
                do {
                    try sourceFile?.write(from: buffer.buffer)
                    writtenSourceFrames += AVAudioFramePosition(buffer.buffer.frameLength)
                }
                catch { recordFailure(error) }
            }
        }
    }

    func appendPCM(_ packets: [MeetingAudioPacket]) {
        guard !packets.isEmpty else { return }
        lock.withLock {
            guard !finishing else { return }
            queue.async { [self] in
                guard failure == nil else { return }
                do {
                    for packet in packets {
                        let frames = AVAudioFrameCount(packet.pcm.count / 2)
                        guard let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frames),
                              let target = buffer.int16ChannelData?.pointee else { throw CocoaError(.coderInvalidValue) }
                        buffer.frameLength = frames
                        packet.pcm.withUnsafeBytes { bytes in
                            if let source = bytes.baseAddress { memcpy(target, source, bytes.count) }
                        }
                        try transcriptionFile?.write(from: buffer)
                        writtenTranscriptionFrames += AVAudioFramePosition(frames)
                    }
                } catch { recordFailure(error) }
            }
        }
    }

    private func recordFailure(_ error: Error) {
        guard failure == nil else { return }
        failure = error; onError?(error)
    }

    func finish() async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                finishing = true
                queue.async { [self] in
                    // AVAudioFile.length can lag while its output buffer is open.
                    let result = Result(sourceDuration: Double(writtenSourceFrames) / sourceFormat.sampleRate,
                                        transcriptionDuration: Double(writtenTranscriptionFrames) / 16_000)
                    sourceFile = nil; transcriptionFile = nil
                    if let failure { continuation.resume(throwing: failure) }
                    else { continuation.resume(returning: result) }
                }
            }
        }
    }
}

/// Local recording outlives an unavailable or failed transcription transport.
final class MeetingRecordingCapture: @unchecked Sendable {
    let writer: MeetingRecordingWriter
    private let capture: MeetingPCMCapture
    private let lock = NSLock()
    private var transport: MeetingAudioTransport?
    private var closed = false
    private var conversionFailed = false

    init(writer: MeetingRecordingWriter, format: AVAudioFormat, offset: TimeInterval,
         streaming: Bool, transport: MeetingAudioTransport?) throws {
        self.writer = writer; self.transport = transport
        capture = try MeetingPCMCapture(format: format, offset: offset, streaming: streaming)
    }
    /// Returns a transcription error while continuing to preserve source audio.
    func consume(_ buffer: AVAudioPCMBuffer) throws -> Error? {
        try lock.withLock {
            guard !closed else { return nil }
            try writer.appendSource(buffer)
            guard !conversionFailed else { return nil }
            do {
                _ = try capture.consume(buffer)
                let packets = capture.drain()
                writer.appendPCM(packets)
                if let transport, transport.enqueue(packets) == .overflow {
                    self.transport = nil
                    return MeetingPiError.audioBackpressure
                }
            } catch {
                conversionFailed = true; transport = nil; return error
            }
            return nil
        }
    }
    func detachTranscription() { lock.withLock { transport = nil } }
    func finishCapture() {
        lock.withLock {
            guard !closed else { return }
            closed = true
            let packets = capture.finish()
            writer.appendPCM(packets)
            transport?.enqueue(packets); transport = nil
        }
    }
}
