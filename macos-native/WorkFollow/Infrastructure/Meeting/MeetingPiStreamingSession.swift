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
        guard let resource = Bundle.main.url(forResource: "wf-meeting-stream", withExtension: "mjs") else {
            throw MeetingPiError.extensionFailure("Pi 流式扩展未打包，请重新构建应用。")
        }
        let session = try await _Concurrency.Task.detached(priority: .utility) {
            try MeetingPiStreamingSession(configuration: configuration, extensionPath: resource.path, onEvent: onEvent)
        }.value
        do { try await session.command(["op": "start", "offset": offset]); return session }
        catch { session.cancel(); throw error }
    }
}

/// One Pi process per recording session. Socket/auth belong exclusively to Pi.
final class MeetingPiStreamingSession: MeetingAudioStream, @unchecked Sendable {
    private let child = Process()
    private let input = Pipe(), output = Pipe()
    private let lock = NSLock()
    private let writer = DispatchQueue(label: "workfollow.meeting.stream.writer")
    private let onEvent: @MainActor @Sendable (MeetingStreamEvent) -> Void
    private var pending: (String, CheckedContinuation<Void, Error>)?
    private var timeout: DispatchWorkItem?
    private var closed = false

    init(configuration: MeetingPiConfiguration, extensionPath: String,
         onEvent: @escaping @MainActor @Sendable (MeetingStreamEvent) -> Void) throws {
        self.onEvent = onEvent
        guard FileManager.default.isExecutableFile(atPath: configuration.executable) else { throw MeetingPiError.unavailable }
        child.executableURL = URL(fileURLWithPath: configuration.executable)
        child.arguments = ["--mode", "rpc", "--no-session", "--no-tools", "--no-extensions", "--no-skills",
                           "--no-prompt-templates", "--no-context-files", "--offline", "--extension", extensionPath]
        if !configuration.resolvedModel.isEmpty { child.arguments! += ["--model", configuration.resolvedModel] }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        child.environment = environment; child.currentDirectoryURL = FileManager.default.temporaryDirectory
        child.standardInput = input; child.standardOutput = output; child.standardError = FileHandle.nullDevice
        try child.run()
        _Concurrency.Task.detached(priority: .utility) { [self] in readEvents() }
    }

    func append(_ packet: MeetingAudioPacket) async throws {
        // sequence 随包透传：扩展按它幂等去重（同一 seq 只 append 一次），
        // ACK 原样带回 sequence——Native 侧将来据此做"ACK 丢失安全重试"。
        try await command(["op": "append", "version": 2, "format": "pcm16", "sampleRate": 16_000,
                           "channels": 1, "offset": packet.offset, "duration": packet.duration,
                           "sequence": Int(clamping: Int64(bitPattern: packet.sequence)),
                           "audio": packet.pcm.base64EncodedString()])
    }
    func finish() async throws {
        defer { cancel() }
        try await command(["op": "stop"])
    }
    func command(_ payload: [String: Any]) async throws {
        let id = UUID().uuidString
        var payload = payload; payload["id"] = id
        let message = "/wf-meeting-stream " + String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        let data = try JSONSerialization.data(withJSONObject: ["type": "prompt", "message": message]) + Data([10])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let accepted = lock.withLock {
                guard !closed, pending == nil else { return false }
                pending = (id, continuation)
                let timer = DispatchWorkItem { [weak self] in self?.fail(MeetingPiError.timeout) }
                timeout = timer
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30, execute: timer)
                return true
            }
            guard accepted else { continuation.resume(throwing: MeetingPiError.failed); return }
            writer.async { [self] in
                do { try input.fileHandleForWriting.write(contentsOf: data) }
                catch { fail(MeetingPiError.failed) }
            }
        }
    }
    private func settle(_ error: Error? = nil, id: String? = nil) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            guard let request = pending, id == nil || id == request.0 else { return nil }
            pending = nil; timeout?.cancel(); timeout = nil; return request.1
        }
        // Preserve event order: a final notification reaches the store before stop ACK resumes.
        if let continuation { DispatchQueue.main.async {
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        } }
    }
    private func readEvents() {
        defer { child.waitUntilExit(); try? output.fileHandleForReading.close() }
        var buffer = Data()
        while true {
            let bytes = output.fileHandleForReading.availableData
            if bytes.isEmpty { break }
            buffer.append(bytes)
            while let end = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if let message = event["message"] as? String, message.hasPrefix("WF_MEETING_STREAM_EVENT "),
                   let data = String(message.dropFirst("WF_MEETING_STREAM_EVENT ".count)).data(using: .utf8),
                   let update = try? JSONDecoder().decode(MeetingStreamEvent.self, from: data) {
                    DispatchQueue.main.async { [onEvent] in onEvent(update) }
                    if update.kind == "error" { fail(MeetingPiError.extensionFailure(update.message ?? "Pi 流式转写失败。")) }
                } else if let message = event["message"] as? String, message.hasPrefix("WF_MEETING_STREAM_ACK "),
                          let data = String(message.dropFirst("WF_MEETING_STREAM_ACK ".count)).data(using: .utf8),
                          let ack = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    settle(id: ack["id"] as? String)
                } else if event["type"] as? String == "extension_error" ||
                            (event["type"] as? String == "response" && event["success"] as? Bool == false) ||
                            (event["message"] as? String)?.hasPrefix("WF_MEETING_ERROR ") == true { fail(MeetingPiError.failed) }
            }
        }
        if !lock.withLock({ closed }) { fail(MeetingPiError.failed) }
    }
    private func fail(_ error: Error) { settle(error); cancel() }
    func cancel() {
        let shouldClose = lock.withLock { let wasOpen = !closed; closed = true; return wasOpen }
        if shouldClose {
            settle(MeetingPiError.failed)
            if child.isRunning { child.terminate() }
            try? input.fileHandleForWriting.close()
        }
    }
}
