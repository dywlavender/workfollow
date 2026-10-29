import Foundation

struct MeetingStreamEvent: Decodable, Sendable {
    let kind: String
    let itemID: String?
    let text: String?
    let offset: Double?
    let message: String?
}

protocol MeetingAudioStream: Sendable {
    func append(_ packet: MeetingAudioPacket) async throws
    func finish() async throws
    func cancel()
}

protocol MeetingStreamingAIClient: MeetingAIClient {
    func openStream(configuration: MeetingPiConfiguration, offset: Double,
                    onEvent: @escaping @MainActor @Sendable (MeetingStreamEvent) -> Void) async throws -> any MeetingAudioStream
}

extension MeetingPiClient: MeetingStreamingAIClient {
    func openStream(configuration: MeetingPiConfiguration, offset: Double,
                    onEvent: @escaping @MainActor @Sendable (MeetingStreamEvent) -> Void) async throws -> any MeetingAudioStream {
        let session = try MeetingPiStreamingSession(configuration: configuration, extensionPath: "",
            onEvent: onEvent, backend: backend)
        do { try await session.command(["op": "start", "offset": offset]); return session }
        catch { session.cancel(); throw error }
    }
}

/// The backend owns the Pi session and ACK retries. This object only forwards
/// captured packets and delivers events in order to the native meeting store.
final class MeetingPiStreamingSession: MeetingAudioStream, @unchecked Sendable {
    private let backend: AIBackendBridge
    private let configuration: MeetingPiConfiguration
    private let extensionPath: String
    private let channel = UUID().uuidString
    private let lock = NSLock()
    private var streamID: String?
    private var closed = false
    private let appendTimeout: TimeInterval
    private let appendAttempts: Int

    init(configuration: MeetingPiConfiguration, extensionPath: String,
         onEvent: @escaping @MainActor @Sendable (MeetingStreamEvent) -> Void,
         appendAttempts: Int = 3, appendTimeout: TimeInterval = 12,
         backend: AIBackendBridge = .shared) throws {
        self.configuration = configuration; self.extensionPath = extensionPath
        self.backend = backend; self.appendTimeout = appendTimeout; self.appendAttempts = appendAttempts
        backend.subscribe(channel) { [weak self] data in
            guard let self, !self.lock.withLock({ self.closed }),
                  let event = try? JSONDecoder().decode(MeetingStreamEvent.self, from: data) else { return }
            DispatchQueue.main.async { onEvent(event) }
        }
    }

    func append(_ packet: MeetingAudioPacket) async throws {
        try await command(["op": "append", "version": 2, "format": "pcm16", "sampleRate": 16_000,
                           "channels": 1, "offset": packet.offset, "duration": packet.duration,
                           "sequence": Int(clamping: Int64(bitPattern: packet.sequence)),
                           "audio": packet.pcm.base64EncodedString()])
    }
    func finish() async throws {
        defer { cancel() }
        try await command(["op": "stop"])
        // The event was enqueued before the stop response. Drain the main queue
        // before the recorder finalizes its last sentence and saves the meeting.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
    func command(_ payload: [String: Any], timeoutSeconds: TimeInterval = 30) async throws {
        guard !lock.withLock({ closed }) else { throw CancellationError() }
        if payload["op"] as? String == "start" {
            struct Response: Decodable { let streamID: String }
            var params = configuration.backendParameters(transcription: true)
            params["channel"] = channel; params["offset"] = payload["offset"] ?? 0
            params["streamExtension"] = extensionPath
            let response: Response = try await backend.call("stream.open", params: params, timeout: timeoutSeconds)
            let accepted = lock.withLock { () -> Bool in
                guard !closed else { return false }; streamID = response.streamID; return true
            }
            if !accepted {
                let _: EmptyAIResponse = try await backend.call("stream.command", params: ["streamID": response.streamID, "op": "cancel"])
                throw CancellationError()
            }
        } else {
            guard let id = lock.withLock({ streamID }) else { throw MeetingPiError.failed }
            var params = payload; params["streamID"] = id
            params["appendTimeout"] = appendTimeout; params["appendAttempts"] = appendAttempts
            let _: EmptyAIResponse = try await backend.call("stream.command", params: params,
                timeout: payload["op"] as? String == "append" ? appendTimeout * Double(appendAttempts) + 5 : timeoutSeconds + 5)
        }
    }
    func cancel() {
        let id = lock.withLock { () -> String? in
            guard !closed else { return nil }; closed = true; return streamID
        }
        backend.unsubscribe(channel)
        if let id { _Concurrency.Task { [backend] in
            let _: EmptyAIResponse? = try? await backend.call("stream.command", params: ["streamID": id, "op": "cancel"], timeout: 5)
        } }
    }
    deinit { cancel() }
}
