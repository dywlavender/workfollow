import AVFoundation
import Foundation

/// Synthetic speech only. PCM stays in memory and is returned via stdout pipe.
/// Compile alongside Meeting.swift / MeetingRecorder.swift to reuse conversion.
private struct SpeechLine: Decodable { let speaker: String; let voice: String; let text: String }
private struct SpeechResult: Encodable { let speaker: String; let text: String; let audio: String; let duration: Double }
private struct PacketResult: Encodable { let offset: Double; let duration: Double; let audio: String }

@MainActor
private final class Synthesizer {
    private let engine = AVSpeechSynthesizer()
    func render(_ line: SpeechLine) async throws -> Data {
        guard let voice = AVSpeechSynthesisVoice.speechVoices().first(where: {
            ($0.name == line.voice || $0.name.hasPrefix(line.voice + " ")) && $0.language.hasPrefix("zh-CN")
        }) else { throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local Chinese voice unavailable: \(line.voice)"]) }
        let utterance = AVSpeechUtterance(string: line.text)
        utterance.voice = voice
        utterance.rate = 0.45
        return try await withCheckedThrowingContinuation { continuation in
            let collector = SpeechCollector(continuation: continuation)
            engine.write(utterance) { collector.receive($0) }
        }
    }
}

private final class SpeechCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var capture: MeetingPCMCapture?
    private var bytes = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    init(continuation: CheckedContinuation<Data, Error>) { self.continuation = continuation }
    func receive(_ buffer: AVAudioBuffer) {
        lock.withLock {
            guard let continuation else { return }
            do {
                guard let pcm = buffer as? AVAudioPCMBuffer else { throw CocoaError(.coderInvalidValue) }
                if pcm.frameLength == 0 {
                    capture?.finish().forEach { bytes.append($0.pcm) }
                    self.continuation = nil
                    guard !bytes.isEmpty else { throw CocoaError(.coderInvalidValue) }
                    continuation.resume(returning: bytes)
                } else {
                    if capture == nil { capture = try MeetingPCMCapture(format: pcm.format, offset: 0) }
                    if try capture!.consume(pcm) { capture!.drain().forEach { bytes.append($0.pcm) } }
                }
            } catch {
                self.continuation = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

@main
private struct MeetingSpeechFixture {
    @MainActor static func main() async throws {
        if CommandLine.arguments.contains("--segment") {
            let pcm = FileHandle.standardInput.readDataToEndOfFile()
            var accumulator = MeetingPCMAccumulator(preferSpeechBoundaries: true,
                speechBoundaryPolicy: CommandLine.arguments.contains("--responsive") ? .responsive : .contextual)
            var packets = accumulator.append(pcm)
            if let tail = accumulator.finish() { packets.append(tail) }
            let result = packets.map { PacketResult(offset: $0.offset, duration: $0.duration, audio: $0.pcm.base64EncodedString()) }
            try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(result))
            return
        }
        let lines = try JSONDecoder().decode([SpeechLine].self, from: FileHandle.standardInput.readDataToEndOfFile())
        let synth = Synthesizer()
        var results: [SpeechResult] = []
        for line in lines {
            let pcm = try await synth.render(line)
            results.append(SpeechResult(speaker: line.speaker, text: line.text,
                                        audio: pcm.base64EncodedString(), duration: Double(pcm.count) / 32000))
        }
        try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(results))
    }
}
