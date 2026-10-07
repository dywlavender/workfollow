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

/// Native never calls a model endpoint. Both paths launch Pi with tools disabled.
struct MeetingPiClient: MeetingAIClient {
    func prepareTranscription(configuration: MeetingPiConfiguration) async throws {
        guard configuration.usesHTTPTranscription else { return }
        _ = try await request(configuration: configuration, prompt: "/wf-meeting-check", audio: true)
    }
    func updateMinutes(configuration: MeetingPiConfiguration, minutes: String,
                       lines: [MeetingTranscriptLine]) async throws -> String {
        guard !lines.isEmpty else { return minutes }
        let prompt = MeetingMinutesPrompt.make(minutes: minutes, lines: lines)
        // Built-in adapter also supports text through Qwen realtime. Other custom
        // audio extensions keep the normal Pi text-model summary path.
        if configuration.audioExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !configuration.resolvedAudioExtension.isEmpty {
            let payload = try JSONSerialization.data(withJSONObject: ["version": 1, "prompt": prompt])
            return try await request(configuration: configuration,
                prompt: "/wf-meeting-minutes " + String(decoding: payload, as: UTF8.self), audio: true)
        }
        return try await request(configuration: configuration,
                                 prompt: "/skill:meeting-minutes " + prompt, audio: false)
    }

    func transcribe(configuration: MeetingPiConfiguration, packet: MeetingAudioPacket,
                    speakers: [String]) async throws -> [MeetingTranscriptLine] {
        guard !configuration.resolvedAudioExtension.isEmpty else {
            throw MeetingPiError.audioNotConfigured
        }
        let payload: [String: Any] = ["version": 2, "audio": packet.pcm.base64EncodedString(),
            "format": "pcm16", "sampleRate": 16_000, "channels": 1,
            "offset": packet.offset, "duration": packet.duration, "knownSpeakers": speakers]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let result = try await request(configuration: configuration,
            prompt: "/wf-meeting-audio " + String(decoding: data, as: UTF8.self), audio: true)
        return try Self.decodeAudioResult(result, offset: packet.offset)
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

    private func request(configuration: MeetingPiConfiguration, prompt: String, audio: Bool) async throws -> String {
        let runner = MeetingPiProcess()
        return try await withTaskCancellationHandler {
            try await _Concurrency.Task.detached(priority: .utility) {
                try runner.run(configuration: configuration, prompt: prompt, audio: audio)
            }.value
        } onCancel: { runner.cancel() }
    }
}

/// Blocking pipe reads are confined to a worker, never the main actor. RPC avoids
/// exposing transcript text in process arguments, and authoritative final messages
/// avoid concatenating partial/retried summaries into a corrupt document.
private final class MeetingPiProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false

    func cancel() {
        lock.withLock {
            cancelled = true
            if process?.isRunning == true { process?.terminate() }
        }
    }

    func run(configuration: MeetingPiConfiguration, prompt: String, audio: Bool) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: configuration.executable) else {
            throw MeetingPiError.unavailable
        }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: configuration.executable)
        child.arguments = ["--mode", "rpc", "--no-session", "--no-tools", "--no-extensions",
                           "--no-skills", "--no-prompt-templates", "--no-context-files", "--offline"]
        if !configuration.resolvedModel.isEmpty { child.arguments! += ["--model", configuration.resolvedModel] }
        if audio { child.arguments! += ["--extension", configuration.resolvedAudioExtension] }
        else {
            guard let skill = Bundle.main.url(forResource: "SKILL", withExtension: "md") else {
                throw MeetingPiError.extensionFailure("纪要 skill 资源缺失，请重新构建应用。")
            }
            child.arguments! += ["--skill", skill.path]
        }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        child.environment = env
        // Do not load this repository's prompts/extensions or allow filesystem tools.
        child.currentDirectoryURL = FileManager.default.temporaryDirectory
        let input = Pipe(), output = Pipe()
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        try lock.withLock {
            if cancelled { throw CancellationError() }
            process = child
            try child.run()
        }
        defer {
            if child.isRunning { child.terminate() }
            child.waitUntilExit()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.withLock {
                self.timedOut = true
                if self.process?.isRunning == true { self.process?.terminate() }
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 120, execute: timeout)
        defer { timeout.cancel() }
        let command = try JSONSerialization.data(withJSONObject: ["id": "meeting", "type": "prompt", "message": prompt])
        try input.fileHandleForWriting.write(contentsOf: command + Data([10]))
        var buffer = Data(), finalText = "", failed = false
        while true {
            let bytes = output.fileHandleForReading.availableData
            if bytes.isEmpty { break }
            buffer.append(bytes)
            while let end = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let type = event["type"] as? String else { continue }
                if type == "response", event["success"] as? Bool == false { throw MeetingPiError.failed }
                if type == "extension_error" { throw MeetingPiError.failed }
                if audio, type == "extension_ui_request", event["notifyType"] as? String == "error" {
                    if let message = event["message"] as? String, message.hasPrefix("WF_MEETING_ERROR ") {
                        throw MeetingPiError.extensionFailure(String(message.dropFirst("WF_MEETING_ERROR ".count)).prefix(240).description)
                    }
                    throw MeetingPiError.failed
                }
                if audio, type == "extension_ui_request", event["method"] as? String == "notify",
                   let message = event["message"] as? String, message.hasPrefix("WF_MEETING_READY ") {
                    return String(message.dropFirst("WF_MEETING_READY ".count))
                }
                if audio, type == "extension_ui_request", event["method"] as? String == "notify",
                   let message = event["message"] as? String, message.hasPrefix("WF_MEETING_RESULT ") {
                    return String(message.dropFirst("WF_MEETING_RESULT ".count))
                }
                if audio, type == "extension_ui_request", event["method"] as? String == "notify",
                   let message = event["message"] as? String, message.hasPrefix("WF_MEETING_MINUTES ") {
                    return String(message.dropFirst("WF_MEETING_MINUTES ".count))
                }
                if type == "message_end", let message = event["message"] as? [String: Any],
                   message["role"] as? String == "assistant" {
                    failed = ["error", "aborted"].contains(message["stopReason"] as? String ?? "")
                    finalText = (message["content"] as? [[String: Any]] ?? [])
                        .filter { $0["type"] as? String == "text" }
                        .compactMap { $0["text"] as? String }.joined()
                }
                if type == "agent_settled" {
                    guard !audio, !failed, !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw MeetingPiError.invalidResult
                    }
                    return finalText
                }
            }
        }
        if lock.withLock({ cancelled }) { throw CancellationError() }
        throw lock.withLock({ timedOut }) ? MeetingPiError.timeout : MeetingPiError.failed
    }
}
