import Foundation

struct MeetingTranscriptLine: Codable, Equatable, Identifiable {
    var id = UUID()
    var speaker: String
    var text: String
    var offset: TimeInterval
    /// Presentation only: preserve the persisted segment scope and identity.
    var speakerDisplayName: String {
        guard speaker.hasPrefix("片段 "), let separator = speaker.range(of: " · ") else { return speaker }
        return String(speaker[separator.upperBound...])
    }
}

struct MeetingAudioChunk: Codable, Equatable, Identifiable {
    var id = UUID()
    var filename: String
    var offset: TimeInterval
    var duration: TimeInterval
    var transcribed = false
    /// New recordings preserve the microphone source and normalized ASR input.
    var transcriptionFilename: String?
    var transcriptionModel: String?
}

/// 流式事件 kind 的常量（Native 与 `wf-meeting-stream.mjs` 双端约定，字符串
/// 保持同步）。单一事实源在这里，扩展侧没有 import 能力，靠 node 测试对齐。
enum MeetingStreamKind {
    static let preview = "preview"
    static let finalText = "final"
    static let speechStarted = "speechStarted"
    static let speechStopped = "speechStopped"
    static let error = "error"
    static let diagnostic = "diagnostic"
}

/// Deliberately not Codable: audio must never enter the persisted snapshot.
struct MeetingAudioPacket: Equatable, Sendable {
    var pcm: Data
    var offset: TimeInterval
    /// 采集侧分配的单调序号（每次录音从 0 连续递增）。传输与 Pi 扩展靠它做幂等
    /// 去重与缺口检测（MEETING-AUDIO-001）：出现 102/103/105 立刻知道 104 丢了，
    /// 而不是等用户听感上觉得"少了一句话"。缺省 0 只供测试直接构造。
    var sequence: UInt64 = 0
    var duration: TimeInterval { Double(pcm.count) / 32_000 }
    var endOffset: TimeInterval { offset + duration }
}

struct MeetingRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = "新会议"
    var createdAt = Date()
    var audio: [MeetingAudioChunk] = []
    /// Includes local recording sessions; older snapshots remain compatible.
    var capturedDuration: TimeInterval?
    var duration: TimeInterval { capturedDuration ?? audio.reduce(0) { $0 + $1.duration } }
    var transcript: [MeetingTranscriptLine] = []
    var minutes = ""
    var summarizedLineIDs: [UUID] = []
    var summarizedLineCount: Int { summarizedLineIDs.count }
    var minutesUpdatedAt: Date?
    /// 用户在纪要栏里直接改过之后就置 true：**Pi 不再覆盖这一条**。
    ///
    /// 手动编辑后暂停五分钟自动编写，点击 AI 编写可重新生成并恢复自动编写。
    ///
    /// ⚠️ 必须是**可选**：存量 `meetings.json` 里没有这个键，而 Swift 合成的 `Codable`
    /// **不会**用属性默认值去填缺键（会抛 `keyNotFound`），只能靠可选类型兼容。
    /// 与 `CountdownEvent.displayUnit` 同一个套路。
    var minutesEditedByUser: Bool?
    var minutesIsManual: Bool { minutesEditedByUser == true }
}

struct MeetingPiConfiguration: Codable, Equatable {
    static let defaultTranscriptionModel = "qwen-audio-3.1-asr-flash-streaming"
    var executable = ""
    /// Legacy shared model, retained when decoding existing snapshots.
    var model = ""
    /// Optional fields allow old snapshots to decode before role migration.
    var transcriptionModel: String?
    var minutesModel: String?
    /// Empty uses the bundled Pi extension. A path overrides the audio adapter.
    var audioExtension = ""
    var resolvedAudioExtension: String {
        let override = audioExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? (Bundle.main.url(forResource: "wf-meeting-audio", withExtension: "mjs")?.path ?? "") : override
    }
    /// Pi 的 `--model` 只认单个模型 id，多行会让 Pi 直接 `Error: Model "…" not found` 退出。
    ///
    /// 2026-10-07 实测：设置框里粘成三行重复值（从聊天记录里连选带粘很容易发生），
    /// 界面只报「Pi 调用失败，请检查 Pi 中的模型、登录和音频扩展配置。」——
    /// 把矛头指向 Pi 的配置，而真正要改的是本应用自己的设置框。这里统一取第一行非空内容，
    /// 让「粘多行」不再致命；`model` 本身保持原样，不偷偷改写用户输入。
    var resolvedModel: String {
        Self.normalizedModel(model)
    }
    private static func normalizedModel(_ value: String) -> String {
        value.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }
    var resolvedTranscriptionModel: String {
        if let transcriptionModel {
            let selected = Self.normalizedModel(transcriptionModel)
            return selected.isEmpty ? Self.defaultTranscriptionModel : selected
        }
        let legacy = resolvedModel
        if !audioExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return legacy }
        if legacy.isEmpty { return Self.defaultTranscriptionModel }
        if legacy.split(separator: "/").last == "qwen-audio-3.1-asr-flash" {
            let prefix = legacy.lastIndex(of: "/").map { String(legacy[...$0]) } ?? ""
            return prefix + Self.defaultTranscriptionModel
        }
        return legacy
    }
    var resolvedMinutesModel: String {
        if let minutesModel { return Self.normalizedModel(minutesModel) }
        return Self.isASRModel(resolvedModel) ? "" : resolvedModel
    }
    private static func isASRModel(_ value: String) -> Bool {
        let id = value.split(separator: "/").last.map(String.init) ?? ""
        return id.contains("-asr-") || id.hasPrefix("fun-asr") || id.hasPrefix("paraformer")
    }
    var minutesUsesASR: Bool { Self.isASRModel(resolvedMinutesModel) }
    var minutesUsesRealtimeOmni: Bool {
        let id = resolvedMinutesModel.split(separator: "/").last.map(String.init) ?? ""
        return id.contains("-omni-") && id.hasSuffix("-realtime")
    }
    /// Each Pi process receives exactly one model for its own job.
    func forTranscription() -> MeetingPiConfiguration {
        var selected = self; selected.model = resolvedTranscriptionModel; return selected
    }
    func forMinutes() -> MeetingPiConfiguration {
        var selected = self; selected.model = resolvedMinutesModel; return selected
    }
    var usesHTTPTranscription: Bool {
        audioExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            resolvedTranscriptionModel.split(separator: "/").last == "qwen-audio-3.1-asr-flash"
    }
}

enum MeetingPiError: LocalizedError {
    case unavailable, audioNotConfigured, audioBackpressure, failed, timeout, invalidResult, extensionFailure(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: return "内置 AI 引擎不可用，请重新安装完整应用。"
        case .audioNotConfigured: return "请配置 Pi 音频扩展以启用转写。录音可继续保存在本地。"
        case .audioBackpressure: return "转写跟不上录音，实时转写已暂停。本地录音继续保存，之后可用录音复测。"
        case .failed: return "Pi 调用失败，请检查 Pi 中的模型、登录和音频扩展配置。"
        case .timeout: return "Pi 请求超时。已有文字、纪要及本地录音保留。"
        case .invalidResult: return "Pi 返回的结果不符合会议协议，未覆盖已有内容。"
        case .extensionFailure(let message): return message
        }
    }
}
