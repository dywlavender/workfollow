import Foundation

protocol MeetingAIClient {
    func prepareTranscription(configuration: MeetingPiConfiguration) async throws
    func updateMinutes(configuration: MeetingPiConfiguration, minutes: String,
                       lines: [MeetingTranscriptLine]) async throws -> String
    func transcribe(configuration: MeetingPiConfiguration, packet: MeetingAudioPacket,
                    speakers: [String]) async throws -> [MeetingTranscriptLine]
}

extension MeetingAIClient {
    func prepareTranscription(configuration: MeetingPiConfiguration) async throws {}
}

/// Native owns audio capture and storage; the backend owns all AI work.
struct MeetingPiClient: MeetingAIClient {
    var backend: AIBackendBridge = .shared
    var textModel: (@MainActor @Sendable () throws -> AITextModelRequest?)?

    func prepareTranscription(configuration: MeetingPiConfiguration) async throws {
        let _: EmptyAIResponse = try await backend.call("meeting.prepare", params: configuration.backendParameters(transcription: true))
    }
    func updateMinutes(configuration: MeetingPiConfiguration, minutes: String,
                       lines: [MeetingTranscriptLine]) async throws -> String {
        guard !lines.isEmpty else { return minutes }
        let selected = try await textModel?()
        guard selected != nil || !configuration.minutesUsesASR else {
            throw MeetingPiError.extensionFailure("纪要模型需要支持文字生成，请选择文字模型。")
        }
        var params = configuration.backendParameters(transcription: false)
        if let selected { params.merge(selected.parameters) { _, new in new } }
        params["minutes"] = minutes
        params["lines"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(lines))
        let result: AITextResponse = try await backend.call("meeting.minutes", params: params)
        return result.text
    }
    func transcribe(configuration: MeetingPiConfiguration, packet: MeetingAudioPacket,
                    speakers: [String]) async throws -> [MeetingTranscriptLine] {
        var params = configuration.backendParameters(transcription: true)
        params["audio"] = packet.pcm.base64EncodedString()
        params["offset"] = packet.offset; params["duration"] = packet.duration
        params["knownSpeakers"] = speakers
        let result: AITextResponse = try await backend.call("meeting.transcribe", params: params)
        return try Self.decodeAudioResult(result.text, offset: packet.offset)
    }

    static func decodeAudioResult(_ json: String, offset: TimeInterval) throws -> [MeetingTranscriptLine] {
        struct Result: Decodable {
            struct Segment: Decodable { let speaker: String?; let text: String; let start: Double }
            let version: Int
            let segments: [Segment]
        }
        guard let data = json.data(using: .utf8), let result = try? JSONDecoder().decode(Result.self, from: data),
              result.version == 1, result.segments.allSatisfy({ $0.start.isFinite && $0.start >= 0 }) else {
            throw MeetingPiError.invalidResult
        }
        return result.segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
            .map { MeetingTranscriptLine(speaker: $0.speaker?.isEmpty == false ? $0.speaker! : "未区分",
                                         text: $0.text, offset: offset + $0.start) }
    }

}

struct EmptyAIResponse: Decodable {}
struct AITextResponse: Decodable { let text: String }

extension MeetingPiConfiguration {
    func backendParameters(transcription: Bool) -> [String: Any] {
        ["model": transcription ? resolvedTranscriptionModel : resolvedMinutesModel,
         "piExecutable": executable, "audioExtension": audioExtension]
    }
}
