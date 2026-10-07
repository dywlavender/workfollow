import AVFoundation
import Combine
import Foundation

@MainActor
final class MeetingStore: ObservableObject, ModuleStoreFlushable {
    private struct Snapshot: Codable {
        var meetings: [MeetingRecord]
        var configuration: MeetingPiConfiguration
    }
    @Published private(set) var meetings: [MeetingRecord] = []
    @Published var selectedID: UUID?
    @Published private(set) var recordingID: UUID?
    @Published private(set) var requestingPermission = false
    @Published private(set) var transcribing = false
    @Published private(set) var updatingMinutes = false
    @Published private(set) var streamDrafts: [UUID: [String: MeetingTranscriptLine]] = [:]
    @Published var error: String?
    @Published var configuration = MeetingPiConfiguration() { didSet { save() } }
    private let persistence: JSONFileStore<Snapshot>
    private let ai: MeetingAIClient
    private let recorder = MeetingRecorder()
    private var permissionGeneration = 0
    private var audioTask: _Concurrency.Task<Void, Never>?
    private var inputStream: (meetingID: UUID, session: any MeetingAudioStream)?
    private var streamStopping = false
    private var streamToken = UUID()
    private var streamFinalIDs: Set<String> = []
    private var minutesTask: _Concurrency.Task<Void, Never>?
    private var pendingAudio: [(UUID, MeetingAudioPacket)] = []
    private var recordingOffset: TimeInterval = 0
    private var inFlightBytes = 0
    /// At most 60 seconds, including the request currently being processed.
    static let maximumAudioBytes = 60 * 32_000
    var bufferedAudioBytes: Int { inFlightBytes + pendingAudio.reduce(0) { $0 + $1.1.pcm.count } }
    private var pendingMinutes: Set<UUID> = []
    private var blockedMinutes: Set<UUID> = []
    private var blockedAudio: Set<UUID> = []
    private var heartbeat: AnyCancellable?

    init(directory: URL = JSONFileStore<MeetingRecord>.moduleDirectory,
         ai: MeetingAIClient = MeetingPiClient(), automaticallyUpdate: Bool = true) {
        self.ai = ai
        persistence = JSONFileStore(filename: "meetings.json", directory: directory)
        if let snapshot = persistence.load() {
            meetings = snapshot.meetings
            configuration = snapshot.configuration
        }
        selectedID = meetings.first?.id
        recorder.onError = { [weak self] error in
            self?.stopRecording()
            self?.pendingAudio.removeAll()
            self?.error = "录音中断：\(error.localizedDescription)"
        }
        if automaticallyUpdate {
            heartbeat = Timer.publish(every: 25, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in
                    guard let self else { return }
                    for meeting in self.meetings where !meeting.minutesIsManual &&
                        meeting.summarizedLineCount < meeting.transcript.count &&
                        !self.blockedMinutes.contains(meeting.id) {
                        self.pendingMinutes.insert(meeting.id)
                    }
                    self.pumpMinutes()
                }
        }
    }

    var selected: MeetingRecord? { meetings.first { $0.id == selectedID } }
    var audioConfigured: Bool { !configuration.resolvedAudioExtension.isEmpty }
    func recordedSeconds(_ meeting: MeetingRecord) -> Int {
        Int(recordingID == meeting.id ? max(meeting.duration, recordingOffset + recorder.currentDuration) : meeting.duration)
    }

    func create() {
        let meeting = MeetingRecord()
        meetings.insert(meeting, at: 0); selectedID = meeting.id; save()
    }

    func rename(_ title: String) {
        guard let id = selectedID else { return }
        change(id) { $0.title = title }
    }

    func startRecording() async {
        guard recordingID == nil, !requestingPermission, let id = selectedID else { return }
        guard audioConfigured else { error = MeetingPiError.audioNotConfigured.localizedDescription; return }
        guard audioTask == nil, inputStream == nil else { error = "正在处理最后一段音频，请稍后继续。"; return }
        permissionGeneration += 1
        let generation = permissionGeneration
        requestingPermission = true; error = nil
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: allowed = true
        case .notDetermined:
            allowed = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
        default: allowed = false
        }
        guard generation == permissionGeneration else { return }
        requestingPermission = false
        guard allowed else { error = "麦克风权限未开启，请在系统设置 → 隐私与安全性 → 麦克风中允许 WorkFollow。"; return }
        guard let meeting = meetings.first(where: { $0.id == id }) else { return }
        recorder.onChunk = { [weak self] chunk in self?.receiveChunk(chunk, meetingID: id) }
        do {
            blockedAudio.remove(id)
            recordingOffset = meeting.duration
            requestingPermission = true
            let streaming = try await connectInputStream(for: id, offset: recordingOffset)
            guard generation == permissionGeneration else { closeInputStream(); return }
            requestingPermission = false
            try recorder.start(offset: recordingOffset, streaming: streaming)
            recordingID = id
        } catch {
            guard generation == permissionGeneration else { return }
            requestingPermission = false; closeInputStream(); self.error = "无法开始录音：\(error.localizedDescription)"
        }
    }

    func stopRecording() {
        if requestingPermission && inputStream == nil { streamToken = UUID() }
        permissionGeneration += 1; requestingPermission = false
        let id = recordingID
        recordingID = nil
        recorder.stop()
        if inputStream != nil { streamStopping = true; pumpAudio(); return }
        if let id, !blockedMinutes.contains(id) { pendingMinutes.insert(id); pumpMinutes() }
    }

    /// Separate connection lifecycle from microphone capture; also permits deterministic transport tests.
    func connectInputStream(for id: UUID, offset: Double) async throws -> Bool {
        guard configuration.audioExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let client = ai as? any MeetingStreamingAIClient else { return false }
        let token = UUID(); streamToken = token
        let session = try await client.openStream(configuration: configuration, offset: offset) { [weak self] event in
            guard let self, self.streamToken == token else { return }
            self.receiveStreamEvent(event, meetingID: id)
        }
        guard streamToken == token else { session.cancel(); throw CancellationError() }
        inputStream = (id, session); streamStopping = false; streamFinalIDs.removeAll(); transcribing = true
        return true
    }

    private func closeInputStream() {
        if let stream = inputStream { streamDrafts.removeValue(forKey: stream.meetingID); stream.session.cancel() }
        inputStream = nil; streamToken = UUID(); streamStopping = false
        if audioTask == nil { transcribing = false }
    }

    func receiveStreamEvent(_ event: MeetingStreamEvent, meetingID: UUID) {
        guard inputStream?.meetingID == meetingID else { return }
        if event.kind == "error" {
            error = event.message ?? "Pi 流式转写失败。"
            blockedAudio.insert(meetingID); pendingAudio.removeAll(); closeInputStream(); stopRecording(); return
        }
        guard let item = event.itemID, let text = event.text,
              let offset = event.offset, offset.isFinite, offset >= 0, !streamFinalIDs.contains(item) else { return }
        let previous = streamDrafts[meetingID]?[item]
        let line = MeetingTranscriptLine(id: previous?.id ?? UUID(), speaker: "未区分", text: text, offset: offset)
        if event.kind == "preview" {
            streamDrafts[meetingID, default: [:]][item] = line
        } else if event.kind == "final" {
            streamFinalIDs.insert(item); streamDrafts[meetingID]?.removeValue(forKey: item)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                change(meetingID) { $0.transcript.append(line); $0.transcript.sort { $0.offset < $1.offset } }
            }
        }
    }

    #if DEBUG
    /// 测试缝：往当前会议塞一行转写。
    ///
    /// 原来这里是个产品能力 `appendManual`，给转写栏底部的「手动补充对话」输入框用。
    /// 2026-10-06 用户明确不要这条路——**不录音就不该让 Pi 组织文字**，UI 与能力一并删掉。
    ///
    /// 之所以还留着这个方法：`change(_:_:)` 是 `private`、`meetings` 是 `private(set)`，
    /// 测试没有别的入口造出转写数据，而「Pi 只总结新增行」这类行为必须喂进真实转写才测得动。
    /// 只进 Debug 构建，不随发布版出去。
    func appendTranscriptForTesting(_ text: String, speaker: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let id = selectedID else { return }
        change(id) { meeting in
            meeting.transcript.append(MeetingTranscriptLine(
                speaker: speaker, text: value,
                offset: TimeInterval(recordedSeconds(meeting))))
        }
    }
    #endif

    func updateMinutesNow() {
        guard let id = selectedID else { return }
        error = nil; blockedMinutes.remove(id); pendingMinutes.insert(id); pumpMinutes()
    }

    /// 用户在纪要栏里直接编辑。第一笔输入就把这条会议标成「手动」，
    /// 之后 Pi 不再写它——否则下一次心跳（25 秒）就会把刚敲的字冲掉。
    func editMinutes(_ text: String) {
        guard let id = selectedID else { return }
        pendingMinutes.remove(id)
        change(id) {
            $0.minutes = text
            $0.minutesEditedByUser = true
        }
    }

    /// 把手动编辑过的纪要交回给 Pi。
    ///
    /// 交回时**不清空**用户写的内容：它会作为「已有纪要」成为下一次更新的基底
    /// （`MeetingMinutesPrompt.make(minutes:lines:)` 就是这么用的），
    /// 所以手动补充的事实不会被丢掉。
    ///
    /// 也要 `blockedMinutes.remove`：之前 Pi 失败过一次的话这一条是被封住的，
    /// 光清标记它也不会再跑——「交回自动更新」就会变成一个点了没反应的按钮。
    func resumeAutomaticMinutes() {
        guard let id = selectedID else { return }
        error = nil
        blockedMinutes.remove(id)
        change(id) { $0.minutesEditedByUser = nil }
        // 只有还有没进纪要的发言时才需要立刻跑一次；否则交给心跳即可。
        if let meeting = meetings.first(where: { $0.id == id }),
           meeting.summarizedLineCount < meeting.transcript.count {
            pendingMinutes.insert(id); pumpMinutes()
        }
    }

    func receiveChunk(_ packet: MeetingAudioPacket, meetingID: UUID) {
        guard meetings.contains(where: { $0.id == meetingID }) else { return }
        change(meetingID) { $0.capturedDuration = max($0.duration, packet.offset + packet.duration) }
        guard (inputStream?.meetingID == meetingID || audioConfigured), !blockedAudio.contains(meetingID) else { return }
        guard bufferedAudioBytes + packet.pcm.count <= Self.maximumAudioBytes else {
            blockedAudio.insert(meetingID)
            pendingAudio.removeAll()
            stopRecording()
            error = MeetingPiError.audioBackpressure.localizedDescription
            return
        }
        pendingAudio.append((meetingID, packet)); pumpAudio()
    }

    private func pumpAudio() {
        guard audioTask == nil, !pendingAudio.isEmpty || streamStopping else { return }
        transcribing = true
        audioTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            defer { self.audioTask = nil; self.transcribing = self.inputStream != nil; self.inFlightBytes = 0 }
            while !self.pendingAudio.isEmpty {
                let (id, packet) = self.pendingAudio.removeFirst()
                self.inFlightBytes = packet.pcm.count
                guard let meeting = self.meetings.first(where: { $0.id == id }) else { continue }
                do {
                    if let stream = self.inputStream, stream.meetingID == id {
                        try await stream.session.append(packet)
                        self.inFlightBytes = 0
                        continue
                    }
                    let lines = try await self.ai.transcribe(configuration: self.configuration,
                        packet: packet,
                        speakers: Array(Set(meeting.transcript.map(\.speaker))).sorted())
                    self.change(id) {
                        $0.transcript.append(contentsOf: lines)
                        $0.transcript.sort { $0.offset < $1.offset }
                    }
                    if self.recordingID != id, !self.blockedMinutes.contains(id) {
                        self.pendingMinutes.insert(id); self.pumpMinutes()
                    }
                } catch {
                    self.error = error.localizedDescription
                    self.blockedAudio.insert(id)
                    self.pendingAudio.removeAll()
                    self.closeInputStream()
                    self.stopRecording()
                    return
                }
                self.inFlightBytes = 0
            }
            if self.streamStopping, let stream = self.inputStream {
                do {
                    try await stream.session.finish()
                    self.closeInputStream()
                    if !self.blockedMinutes.contains(stream.meetingID) {
                        self.pendingMinutes.insert(stream.meetingID); self.pumpMinutes()
                    }
                } catch { self.error = error.localizedDescription; self.closeInputStream() }
            }
        }
    }

    private func pumpMinutes() {
        guard minutesTask == nil, !pendingMinutes.isEmpty else { return }
        updatingMinutes = true
        minutesTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            defer { self.minutesTask = nil; self.updatingMinutes = false }
            while let id = self.pendingMinutes.first {
                self.pendingMinutes.remove(id)
                // 手动编辑过的纪要不由 Pi 覆盖。守卫放在这里而不是各个调用点，
                // 心跳 / 停止录音 / 转写完成 / 手动触发四条路径就都覆盖到了。
                guard let meeting = self.meetings.first(where: { $0.id == id }),
                      !meeting.minutesIsManual,
                      meeting.summarizedLineCount < meeting.transcript.count else { continue }
                let done = Set(meeting.summarizedLineIDs)
                let newLines = meeting.transcript.filter { !done.contains($0.id) }
                do {
                    let minutes = try await self.ai.updateMinutes(configuration: self.configuration,
                                                                  minutes: meeting.minutes, lines: newLines)
                    guard !minutes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MeetingPiError.invalidResult }
                    // 请求在飞行途中用户可能已经动手编辑了：那种情况下这一份结果作废，
                    // 否则会把刚敲的字盖回去。
                    guard self.meetings.first(where: { $0.id == id })?.minutesIsManual != true else { continue }
                    self.change(id) {
                        $0.minutes = minutes
                        $0.summarizedLineIDs.append(contentsOf: newLines.map(\.id))
                        $0.minutesUpdatedAt = Date()
                    }
                } catch {
                    self.error = error.localizedDescription; self.blockedMinutes.insert(id)
                }
            }
        }
    }

    private func change(_ id: UUID, _ mutation: (inout MeetingRecord) -> Void) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        mutation(&meetings[index]); save()
    }
    private func save() { persistence.schedule(Snapshot(meetings: meetings, configuration: configuration)) }
    func flush(_ completion: @escaping (Error?) -> Void) {
        if recordingID != nil { stopRecording() }
        _Concurrency.Task { [self] in
            while audioTask != nil || inputStream != nil {
                try? await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
            }
            persistence.flush(completion)
        }
    }
}
