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

    /// append 重试（MEETING-AUDIO-002）：ACK 丢失时同一包原样重发。扩展按
    /// sequence 幂等去重（重发不产生第二次 append），迟到 ACK 因命令 id 不同
    /// 被忽略——所以重试是安全的。超时后**会话存活**（旧实现一次超时即杀会话）。
    /// 注入便于测试（ACK 丢失用例不必等 12 秒）。
    private static let defaultAppendAttempts = 3
    private static let defaultAppendTimeout: TimeInterval = 12
    private let appendTimeout: TimeInterval
    private let appendAttempts: Int

    init(configuration: MeetingPiConfiguration, extensionPath: String,
         onEvent: @escaping @MainActor @Sendable (MeetingStreamEvent) -> Void,
         appendAttempts: Int = MeetingPiStreamingSession.defaultAppendAttempts,
         appendTimeout: TimeInterval = MeetingPiStreamingSession.defaultAppendTimeout) throws {
        self.appendAttempts = max(1, appendAttempts)
        self.appendTimeout = appendTimeout
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
        // ACK 原样带回 sequence。
        let payload: [String: Any] = ["op": "append", "version": 2, "format": "pcm16",
                                      "sampleRate": 16_000, "channels": 1,
                                      "offset": packet.offset, "duration": packet.duration,
                                      "sequence": Int(clamping: Int64(bitPattern: packet.sequence)),
                                      "audio": packet.pcm.base64EncodedString()]
        // ACK 丢失安全重试：同一包原样重发（扩展幂等），最后一次仍失败才上抛。
        var lastError: Error = MeetingPiError.timeout
        for _ in 0..<max(1, appendAttempts) {
            do { try await command(payload, timeoutSeconds: appendTimeout); return }
            catch is CancellationError { throw CancellationError() }
            catch { lastError = error }
        }
        throw lastError
    }
    func finish() async throws {
        defer { cancel() }
        try await command(["op": "stop"])
    }
    /// `timeout` 内未收到 ACK 时，命令以超时失败结束但**会话保持存活**
    /// （MEETING-AUDIO-002）：迟到 ACK 因 id 不匹配被忽略，重试命令安全。
    /// 会话级失败（extension_error / 流关闭 / cancel）仍走 `fail`。
    func command(_ payload: [String: Any], timeoutSeconds: TimeInterval = 30) async throws {
        let id = UUID().uuidString
        var payload = payload; payload["id"] = id
        let message = "/wf-meeting-stream " + String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        let data = try JSONSerialization.data(withJSONObject: ["type": "prompt", "message": message]) + Data([10])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let accepted = lock.withLock {
                guard !closed, pending == nil else { return false }
                pending = (id, continuation)
                let timer = DispatchWorkItem { [weak self] in self?.commandTimedOut() }
                timeout = timer
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: timer)
                return true
            }
            guard accepted else { continuation.resume(throwing: MeetingPiError.failed); return }
            writer.async { [self] in
                do { try input.fileHandleForWriting.write(contentsOf: data) }
                catch { fail(MeetingPiError.failed) }
            }
        }
    }
    /// 命令超时：只作废当前命令（恢复其 continuation），会话与泵保持存活。
    private func commandTimedOut() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            guard let request = pending else { return nil }
            pending = nil; timeout?.cancel(); timeout = nil
            return request.1
        }
        continuation?.resume(throwing: MeetingPiError.timeout)
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
