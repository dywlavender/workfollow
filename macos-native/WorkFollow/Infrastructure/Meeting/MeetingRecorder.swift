import AVFoundation
import Foundation

/// No file writer or recording URL. Only in-memory PCM packets leave capture.
@MainActor
final class MeetingRecorder {
    private var engine: AVAudioEngine?
    private var capture: MeetingPCMCapture?
    private var generation = UUID()
    var onChunk: ((MeetingAudioPacket) -> Void)?
    var onError: ((Error) -> Void)?
    var currentDuration: TimeInterval { capture?.duration ?? 0 }

    func start(offset: TimeInterval, streaming: Bool = false) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let capture = try MeetingPCMCapture(format: format, offset: offset, streaming: streaming)
        let token = UUID()
        generation = token
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            do {
                if try capture.consume(buffer) {
                    _Concurrency.Task { @MainActor [weak self] in
                        guard let self, self.generation == token else { return }
                        capture.drain().forEach { self.onChunk?($0) }
                    }
                }
            } catch {
                _Concurrency.Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.stop(); self.onError?(error)
                }
            }
        }
        do { try engine.start() }
        catch { input.removeTap(onBus: 0); throw error }
        self.engine = engine; self.capture = capture
    }

    func stop() {
        guard let engine, let capture else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil; self.capture = nil
        generation = UUID()
        // Includes undelivered complete packets and the final partial packet.
        capture.finish().forEach { onChunk?($0) }
    }
}

final class MeetingPCMCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private var accumulator: MeetingPCMAccumulator
    private var pending: [MeetingAudioPacket] = []
    private var closed = false
    var duration: TimeInterval { lock.withLock { accumulator.duration } }

    init(format: AVAudioFormat, offset: TimeInterval, streaming: Bool = false) throws {
        guard format.sampleRate > 0, format.channelCount > 0,
              let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                         channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: format, to: output) else {
            throw CocoaError(.coderInvalidValue)
        }
        self.converter = converter; outputFormat = output
        // Keep the existing capture policy until the shorter candidate passes
        // real-model acceptance; its protocol failures currently stop recording.
        accumulator = MeetingPCMAccumulator(offset: offset, segmentSeconds: streaming ? 0.25 : 15,
                                            preferSpeechBoundaries: !streaming)
    }
    func consume(_ input: AVAudioPCMBuffer) throws -> Bool {
        try lock.withLock {
            guard !closed else { return false }
            let wasEmpty = pending.isEmpty
            let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 16_000 / input.format.sampleRate) + 64)
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
                throw CocoaError(.coderInvalidValue)
            }
            var supplied = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return input
            }
            if let error { throw error }
            if let bytes = output.int16ChannelData?.pointee, output.frameLength > 0 {
                pending.append(contentsOf: accumulator.append(Data(bytes: bytes, count: Int(output.frameLength) * 2)))
            }
            guard pending.count <= 4 else { closed = true; throw MeetingPiError.audioBackpressure }
            return wasEmpty && !pending.isEmpty
        }
    }
    func drain() -> [MeetingAudioPacket] {
        lock.withLock { let result = pending; pending.removeAll(); return result }
    }
    func finish() -> [MeetingAudioPacket] {
        lock.withLock {
            closed = true
            if let tail = accumulator.finish() { pending.append(tail) }
            let result = pending; pending.removeAll(); return result
        }
    }
}

/// Continuous capture, bounded memory-only segmentation; no stop/start gap.
enum MeetingSpeechBoundaryPolicy {
    case contextual, responsive
    var minimumBytes: Int { (self == .responsive ? 2 : 10) * 32_000 }
    var maximumBytes: Int { (self == .responsive ? 5 : 20) * 32_000 }
}

struct MeetingPCMAccumulator {
    private var bytes = Data()
    private var delivered: TimeInterval = 0
    private let offset: TimeInterval
    private let segmentBytes: Int
    private let preferSpeechBoundaries: Bool
    private let speechBoundaryPolicy: MeetingSpeechBoundaryPolicy
    private var scannedBytes = 0
    private var quietBytes = 0
    var duration: TimeInterval { delivered + Double(bytes.count) / 32_000 }
    init(offset: TimeInterval = 0, segmentSeconds: Double = 15, preferSpeechBoundaries: Bool = false,
         speechBoundaryPolicy: MeetingSpeechBoundaryPolicy = .contextual) {
        self.offset = offset; segmentBytes = max(2, Int(segmentSeconds * 32_000) / 2 * 2)
        self.preferSpeechBoundaries = preferSpeechBoundaries
        self.speechBoundaryPolicy = speechBoundaryPolicy
    }
    mutating func append(_ data: Data) -> [MeetingAudioPacket] {
        bytes.append(data)
        var packets: [MeetingAudioPacket] = []
        if preferSpeechBoundaries {
            // 10ms PCM frames. Prefer a 300ms quiet boundary after the minimum;
            // the experimental responsive policy has a 2s minimum and 5s cap.
            // Conservative energy gate, not a speaker recognition/VAD model.
            while bytes.count - scannedBytes >= 320 {
                let quiet = bytes.withUnsafeBytes { raw -> Bool in
                    var energy: Double = 0
                    for i in stride(from: scannedBytes, to: scannedBytes + 320, by: 2) {
                        let sample = Int16(bitPattern: UInt16(raw[i]) | (UInt16(raw[i + 1]) << 8))
                        energy += Double(sample) * Double(sample)
                    }
                    return energy / 160 < 80 * 80
                }
                scannedBytes += 320
                quietBytes = quiet ? quietBytes + 320 : 0
                if (scannedBytes >= speechBoundaryPolicy.minimumBytes && quietBytes >= 9_600) ||
                    scannedBytes >= speechBoundaryPolicy.maximumBytes {
                    packets.append(packet(Data(bytes.prefix(scannedBytes))))
                    bytes.removeFirst(scannedBytes)
                    scannedBytes = 0; quietBytes = 0
                }
            }
            return packets
        }
        while bytes.count >= segmentBytes {
            packets.append(packet(Data(bytes.prefix(segmentBytes))))
            bytes.removeFirst(segmentBytes)
        }
        return packets
    }
    mutating func finish() -> MeetingAudioPacket? {
        guard !bytes.isEmpty else { return nil }
        let tail = bytes; bytes.removeAll()
        scannedBytes = 0; quietBytes = 0
        return packet(tail)
    }
    private mutating func packet(_ data: Data) -> MeetingAudioPacket {
        let result = MeetingAudioPacket(pcm: data, offset: offset + delivered)
        delivered += result.duration; return result
    }
}
