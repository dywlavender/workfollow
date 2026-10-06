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
    @Published var error: String?
    @Published var configuration = MeetingPiConfiguration() { didSet { save() } }
    private let persistence: JSONFileStore<Snapshot>
    private let ai: MeetingAIClient
    private let recorder = MeetingRecorder()
    private var permissionGeneration = 0
    private var audioTask: _Concurrency.Task<Void, Never>?
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
        guard audioTask == nil else { error = "正在处理最后一段音频，请稍后继续。"; return }
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
            try recorder.start(offset: recordingOffset)
            recordingID = id
        } catch { self.error = "无法开始录音：\(error.localizedDescription)" }
    }

    func stopRecording() {
        permissionGeneration += 1; requestingPermission = false
        let id = recordingID
        recordingID = nil
        recorder.stop()
        if let id, !blockedMinutes.contains(id) { pendingMinutes.insert(id); pumpMinutes() }
    }

    /// Explicit manual notes are useful even before an audio-capable model is configured.
    /// They are labelled as manual, never presented as automatic transcription.
    func appendManual(_ text: String, speaker: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let id = selectedID else { return }
        change(id) { meeting in
            meeting.transcript.append(MeetingTranscriptLine(
                speaker: speaker.isEmpty ? "手动记录" : speaker, text: value,
                offset: TimeInterval(recordedSeconds(meeting))))
        }
    }

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
        guard audioConfigured, !blockedAudio.contains(meetingID) else { return }
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
        guard audioTask == nil, !pendingAudio.isEmpty else { return }
        transcribing = true
        audioTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            defer { self.audioTask = nil; self.transcribing = false; self.inFlightBytes = 0 }
            while !self.pendingAudio.isEmpty {
                let (id, packet) = self.pendingAudio.removeFirst()
                self.inFlightBytes = packet.pcm.count
                guard let meeting = self.meetings.first(where: { $0.id == id }) else { continue }
                do {
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
                    self.stopRecording()
                    return
                }
                self.inFlightBytes = 0
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
    func flush(_ completion: @escaping (Error?) -> Void) { persistence.flush(completion) }
}
