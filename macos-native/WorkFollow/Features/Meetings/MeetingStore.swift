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
    @Published private(set) var savingRecordingIDs: Set<UUID> = []
    @Published private(set) var streamDrafts: [UUID: [String: MeetingTranscriptLine]] = [:]
    @Published var error: String?
    @Published var configuration = MeetingPiConfiguration() { didSet { save() } }
    private let persistence: JSONFileStore<Snapshot>
    private let storageDirectory: URL
    private let ai: MeetingAIClient
    private let recorder = MeetingRecorder()
    private var permissionGeneration = 0
    /// 音频传输总线（MEETING-AUDIO-001）：采集线程 → transport → Pi/ASR，
    /// 全程不经过 MainActor。每次录音会话建一个新实例；批量路径（自定义扩展）
    /// 在首次收包时建。`pendingAudio`/`audioTask`/`pumpAudio` 由此取代。
    private var transport: MeetingAudioTransport?
    private var transportMeetingID: UUID?
    private var inputStream: (meetingID: UUID, session: any MeetingAudioStream)?
    private var streamStopping = false
    private var streamToken = UUID()
    private var streamFinalIDs: Set<String> = []
    /// VAD turn 状态机（MEETING-AUDIO-002）："有讲话但没有 Final"的检测层。
    private let turnTracker = MeetingSpeechTurnTracker()
    private var finalDeadlineTasks: [String: _Concurrency.Task<Void, Never>] = [:]
    private var minutesTask: _Concurrency.Task<Void, Never>?
    static let automaticMinutesInterval: TimeInterval = 5 * 60
    private let automaticallyUpdateMinutes: Bool
    private let minutesTimer: (TimeInterval) -> AnyPublisher<Date, Never>
    private var automaticMinutesMeetingID: UUID?
    private var minutesEditRevisions: [UUID: Int] = [:]
    private var recordingOffset: TimeInterval = 0
    private var localRecording: (meetingID: UUID, chunkID: UUID)?
    /// At most 60 seconds, including the request currently being processed.
    static let maximumAudioBytes = 60 * 32_000
    var bufferedAudioBytes: Int { transport?.pendingByteCount ?? 0 }
    private var blockedAudio: Set<UUID> = []
    private var heartbeat: AnyCancellable?

    init(directory: URL = JSONFileStore<MeetingRecord>.moduleDirectory,
         ai: MeetingAIClient = MeetingPiClient(), automaticallyUpdate: Bool = true,
         minutesTimer: @escaping (TimeInterval) -> AnyPublisher<Date, Never> = { interval in
             Timer.publish(every: interval, on: .main, in: .common).autoconnect().eraseToAnyPublisher()
         }) {
        self.ai = ai
        automaticallyUpdateMinutes = automaticallyUpdate
        self.minutesTimer = minutesTimer
        storageDirectory = directory
        persistence = JSONFileStore(filename: "meetings.json", directory: directory)
        if let snapshot = persistence.load() {
            meetings = snapshot.meetings
            configuration = snapshot.configuration
        }
        selectedID = meetings.first?.id
        recorder.onError = { [weak self] error in
            self?.stopRecording()
            self?.error = "录音中断：\(error.localizedDescription)"
        }
        recorder.onTranscriptionError = { [weak self] error in
            guard let self, let id = self.recordingID else { return }
            self.pauseTranscription(meetingID: id, message: error.localizedDescription)
        }
    }

    var selected: MeetingRecord? { meetings.first { $0.id == selectedID } }
    func recordingFiles(for meeting: MeetingRecord) -> [URL] {
        meeting.audio.flatMap { chunk in [chunk.filename, chunk.transcriptionFilename].compactMap { $0 } }
            .map { storageDirectory.appendingPathComponent($0).standardizedFileURL }
            .filter { $0.path.hasPrefix(storageDirectory.standardizedFileURL.path + "/") && FileManager.default.fileExists(atPath: $0.path) }
    }
    var audioConfigured: Bool { !configuration.resolvedAudioExtension.isEmpty }
    func recordedSeconds(_ meeting: MeetingRecord) -> Int {
        Int(recordingID == meeting.id ? max(meeting.duration, recordingOffset + recorder.currentDuration) : meeting.duration)
    }

    func create() {
        let meeting = MeetingRecord()
        meetings.insert(meeting, at: 0); selectedID = meeting.id; save()
    }

    func canDelete(_ id: UUID) -> Bool {
        meetings.contains { $0.id == id } && !requestingPermission && recordingID != id && !savingRecordingIDs.contains(id) &&
            inputStream?.meetingID != id && !(transportMeetingID == id && transport?.isBusy == true)
    }

    @discardableResult
    func delete(_ id: UUID) -> Bool {
        guard let index = meetings.firstIndex(where: { $0.id == id }), canDelete(id) else { return false }
        meetings.remove(at: index)
        streamDrafts.removeValue(forKey: id)
        if automaticMinutesMeetingID == id { stopAutomaticMinutes() }
        minutesEditRevisions.removeValue(forKey: id); blockedAudio.remove(id)
        if selectedID == id {
            selectedID = meetings.isEmpty ? nil : meetings[min(index, meetings.count - 1)].id
        }
        save()
        return true
    }

    func rename(_ title: String) {
        guard let id = selectedID else { return }
        change(id) { $0.title = title }
    }

    func startRecording() async {
        guard recordingID == nil, !requestingPermission, let id = selectedID else { return }
        guard savingRecordingIDs.isEmpty else { error = "正在保存本地录音，请稍后继续。"; return }
        guard transport?.isBusy != true, inputStream == nil else { error = "正在处理最后一段音频，请稍后继续。"; return }
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
        do {
            blockedAudio.remove(id)
            recordingOffset = meeting.duration
            requestingPermission = true
            var streaming = false
            do {
                guard audioConfigured else { throw MeetingPiError.audioNotConfigured }
                streaming = try await connectInputStream(for: id, offset: recordingOffset)
                if !streaming {
                    try await ai.prepareTranscription(configuration: configuration)
                    guard generation == permissionGeneration else { return }
                    createBatchTransport(for: id)
                }
            } catch {
                guard generation == permissionGeneration else { return }
                closeInputStream(); transport?.cancel(); transport = nil; transportMeetingID = nil
                self.error = "转写未连接，将仅保存本地录音：\(error.localizedDescription)"
            }
            guard generation == permissionGeneration else {
                closeInputStream(); return
            }
            requestingPermission = false
            let chunkID = UUID()
            let base = "meeting-audio/\(id.uuidString)/\(chunkID.uuidString)"
            let chunk = MeetingAudioChunk(id: chunkID, filename: base + ".caf", offset: recordingOffset,
                                          duration: 0, transcriptionFilename: base + "-asr.wav",
                                          transcriptionModel: configuration.resolvedTranscriptionModel)
            try recorder.start(offset: recordingOffset, streaming: streaming, transport: transport,
                               sourceURL: storageDirectory.appendingPathComponent(chunk.filename),
                               transcriptionURL: storageDirectory.appendingPathComponent(chunk.transcriptionFilename!))
            localRecording = (id, chunkID)
            change(id) { $0.audio.append(chunk) }
            recordingID = id
            startAutomaticMinutes(for: id)
        } catch {
            guard generation == permissionGeneration else { return }
            requestingPermission = false; closeInputStream(); transport?.cancel(); transport = nil; transportMeetingID = nil
            self.error = "无法开始录音：\(error.localizedDescription)"
        }
    }

    func stopRecording() {
        stopAutomaticMinutes()
        if requestingPermission && inputStream == nil { streamToken = UUID() }
        permissionGeneration += 1; requestingPermission = false
        let saved = localRecording; localRecording = nil
        let duration = recorder.currentDuration
        recordingID = nil
        if let writer = recorder.stop(), let saved {
            savingRecordingIDs.insert(saved.meetingID)
            change(saved.meetingID) { meeting in
                meeting.capturedDuration = max(meeting.duration, recordingOffset + duration)
                if let index = meeting.audio.firstIndex(where: { $0.id == saved.chunkID }) { meeting.audio[index].duration = duration }
            }
            _Concurrency.Task { [self] in
                defer { savingRecordingIDs.remove(saved.meetingID) }
                do {
                    let result = try await writer.finish()
                    change(saved.meetingID) { meeting in
                        if let index = meeting.audio.firstIndex(where: { $0.id == saved.chunkID }) {
                            meeting.audio[index].duration = result.sourceDuration
                        }
                    }
                } catch { self.error = "本地录音保存失败：\(error.localizedDescription)" }
            }
        }
        transport?.stopAccepting()
        if inputStream != nil { streamStopping = true; transport?.stopAccepting(); return }
    }

    /// Separate connection lifecycle from microphone capture; also permits deterministic transport tests.
    func connectInputStream(for id: UUID, offset: Double) async throws -> Bool {
        guard configuration.audioExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !configuration.usesHTTPTranscription,
              let client = ai as? any MeetingStreamingAIClient else { return false }
        let token = UUID(); streamToken = token
        let session = try await client.openStream(configuration: configuration, offset: offset) { [weak self] event in
            guard let self, self.streamToken == token else { return }
            self.receiveStreamEvent(event, meetingID: id)
        }
        guard streamToken == token else { session.cancel(); throw CancellationError() }
        inputStream = (id, session); streamStopping = false; streamFinalIDs.removeAll(); transcribing = true
        cancelFinalDeadlines()
        turnTracker.reset()
        createStreamingTransport(meetingID: id, session: session)
        return true
    }

    /// 当前流的 turn 快照（按讲话开始顺序）。003 的 Repair 输入与失败段 UI 用。
    var speechTurns: [MeetingSpeechTurn] { turnTracker.snapshot }

    private func cancelFinalDeadlines() {
        for task in finalDeadlineTasks.values { task.cancel() }
        finalDeadlineTasks.removeAll()
    }

    private func scheduleFinalDeadline(itemID: String) {
        guard finalDeadlineTasks[itemID] == nil,
              turnTracker.snapshot.contains(where: { $0.id == itemID && $0.status == .awaitingFinal })
        else { return }
        let token = streamToken
        finalDeadlineTasks[itemID] = _Concurrency.Task { @MainActor [weak self] in
            do {
                try await _Concurrency.Task.sleep(nanoseconds: UInt64(MeetingAudioReliabilityPolicy.finalGracePeriod * 1_000_000_000))
            } catch { return }
            guard let self, self.streamToken == token, self.inputStream != nil else { return }
            self.finalDeadlineTasks[itemID] = nil
            self.turnTracker.expireFinal(itemID: itemID)
        }
    }

    private func closeInputStream() {
        cancelFinalDeadlines()
        if let stream = inputStream { streamDrafts.removeValue(forKey: stream.meetingID); stream.session.cancel() }
        inputStream = nil; streamToken = UUID(); streamStopping = false
        // 会话关闭后不会再有 final：包含缺少 stopped 的讲话中 turn。
        turnTracker.sweep(force: true)
        if transport?.isBusy != true { transcribing = false }
    }

    func receiveStreamEvent(_ event: MeetingStreamEvent, meetingID: UUID) {
        guard inputStream?.meetingID == meetingID else { return }
        if event.kind == "error" {
            pauseTranscription(meetingID: meetingID, message: event.message ?? "Pi 流式转写失败。"); return
        }
        // VAD 生命周期（MEETING-AUDIO-002）：start/stop 不带文字，先进 turn
        // 状态机；"有讲话但没有 Final"由 tracker 按宽限期判定 missingFinal。
        if event.kind == MeetingStreamKind.speechStarted || event.kind == MeetingStreamKind.speechStopped {
            if event.kind == MeetingStreamKind.speechStarted {
                turnTracker.speechStarted(itemID: event.itemID ?? "", at: event.offset ?? 0)
            } else {
                turnTracker.speechStopped(itemID: event.itemID ?? "", at: event.offset ?? 0)
                scheduleFinalDeadline(itemID: event.itemID ?? "")
            }
            return
        }
        guard let item = event.itemID, let text = event.text,
              let offset = event.offset, offset.isFinite, offset >= 0, !streamFinalIDs.contains(item) else { return }
        if event.kind == MeetingStreamKind.finalText {
            finalDeadlineTasks.removeValue(forKey: item)?.cancel()
            turnTracker.finalize(itemID: item)
        }
        let previous = streamDrafts[meetingID]?[item]
        let line = MeetingTranscriptLine(id: previous?.id ?? UUID(), speaker: "未区分", text: text, offset: offset)
        if event.kind == MeetingStreamKind.preview {
            streamDrafts[meetingID, default: [:]][item] = line
        } else if event.kind == MeetingStreamKind.finalText {
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
        generateMinutes(for: id, automatically: false)
    }

    func canGenerateMinutes(for meeting: MeetingRecord) -> Bool {
        !updatingMinutes && !meeting.transcript.isEmpty
    }

    /// Recording owns the automatic schedule; historical meetings remain manual.
    func startAutomaticMinutes(for id: UUID) {
        guard automaticallyUpdateMinutes, meetings.contains(where: { $0.id == id }) else { return }
        automaticMinutesMeetingID = id
        scheduleAutomaticMinutes()
    }

    private func stopAutomaticMinutes() {
        automaticMinutesMeetingID = nil
        heartbeat?.cancel(); heartbeat = nil
    }

    private func scheduleAutomaticMinutes() {
        heartbeat?.cancel(); heartbeat = nil
        guard !updatingMinutes, let id = automaticMinutesMeetingID,
              let meeting = meetings.first(where: { $0.id == id }), !meeting.minutesIsManual else { return }
        heartbeat = minutesTimer(Self.automaticMinutesInterval).prefix(1).sink { [weak self] _ in
            guard let self, self.automaticMinutesMeetingID == id else { return }
            self.heartbeat = nil
            if !self.generateMinutes(for: id, automatically: true) { self.scheduleAutomaticMinutes() }
        }
    }

    /// Editing pauses automatic replacement. An explicit AI request can regenerate it.
    func editMinutes(_ text: String) {
        guard let id = selectedID else { return }
        minutesEditRevisions[id, default: 0] += 1
        if automaticMinutesMeetingID == id { heartbeat?.cancel(); heartbeat = nil }
        change(id) {
            $0.minutes = text
            $0.minutesEditedByUser = true
        }
    }

    /// Compatibility for callers that explicitly hand edited minutes back to AI.
    func resumeAutomaticMinutes() {
        updateMinutesNow()
    }

    /// 测试注入缝与批量路径入口。实时录音的采集数据**不经过这里**——
    /// tap 直接 enqueue 进 transport（不经主线程，见 `MeetingRecorder`）。
    func receiveChunk(_ packet: MeetingAudioPacket, meetingID: UUID) {
        guard meetings.contains(where: { $0.id == meetingID }) else { return }
        change(meetingID) { $0.capturedDuration = max($0.duration, packet.endOffset) }
        guard (inputStream?.meetingID == meetingID || audioConfigured),
              !blockedAudio.contains(meetingID) else { return }
        if transport == nil || transportMeetingID != meetingID {
            if inputStream?.meetingID == meetingID {
                guard let stream = inputStream else { return }
                createStreamingTransport(meetingID: meetingID, session: stream.session)
            } else {
                createBatchTransport(for: meetingID)
            }
        }
        transcribing = true
        guard let transport, transport.enqueue([packet]) != .overflow else {
            // 超限包被拒：没有东西入队就谈不上"转写中"，按传输实际忙闲复位。
            transcribing = transport?.isBusy ?? false
            handleTransportOverflow(meetingID: meetingID); return
        }
    }

    // MARK: - 传输总线组装（MEETING-AUDIO-001）

    private func wireTransportCallbacks(_ transport: MeetingAudioTransport, meetingID: UUID) {
        transport.onCapture = { [weak self, weak transport] until in
            _Concurrency.Task { @MainActor [weak self, weak transport] in
                guard let self, let transport, self.transport === transport else { return }
                self.change(meetingID) { $0.capturedDuration = max($0.duration, until) }
                self.transcribing = self.inputStream != nil || self.transport?.isBusy == true
            }
        }
        transport.onOverflow = { [weak self, weak transport] in
            guard let self, let transport, self.transport === transport else { return }
            self.handleTransportOverflow(meetingID: meetingID)
        }
        transport.onError = { [weak self, weak transport] error in
            guard let self, let transport, self.transport === transport else { return }
            self.handleTransportError(meetingID: meetingID, error)
        }
        transport.onIdle = { [weak self, weak transport] in
            _Concurrency.Task { @MainActor [weak self, weak transport] in
                guard let self, let transport, self.transport === transport else { return }
                self.transcribing = self.inputStream != nil
            }
        }
        transport.onSettled = { [weak self, weak transport] in
            _Concurrency.Task { @MainActor [weak self, weak transport] in
                guard let self, let transport, self.transport === transport else { return }
                self.transcribing = false
            }
        }
    }

    private func createStreamingTransport(meetingID: UUID, session: any MeetingAudioStream) {
        let token = streamToken
        let transport = MeetingAudioTransport(maximumBytes: Self.maximumAudioBytes) { packet in
            try await session.append(packet)
        }
        transport.bindFinisher { [weak self] _ in
            try await session.finish()
            await MainActor.run { [weak self] in
                guard let self, self.streamToken == token else { return }
                self.closeInputStream()
            }
        }
        wireTransportCallbacks(transport, meetingID: meetingID)
        self.transport = transport
        transportMeetingID = meetingID
    }

    private func createBatchTransport(for meetingID: UUID) {
        let ai = self.ai
        let configuration = self.configuration
        let transport = MeetingAudioTransport(maximumBytes: Self.maximumAudioBytes) { [weak self] packet in
            let speakers = await MainActor.run { [weak self] () -> [String] in
                guard let meeting = self?.meetings.first(where: { $0.id == meetingID }) else { return [] }
                return Array(Set(meeting.transcript.map(\.speaker))).sorted()
            }
            let lines = try await ai.transcribe(configuration: configuration, packet: packet, speakers: speakers)
            await MainActor.run { [weak self] in
                self?.receiveTranscribed(lines: lines, packet: packet, meetingID: meetingID)
            }
        }
        wireTransportCallbacks(transport, meetingID: meetingID)
        self.transport = transport
        transportMeetingID = meetingID
    }

    /// 批量路径：一次性转写返回的文字行落进对话记录（原 pumpAudio 成功分支）。
    private func receiveTranscribed(lines: [MeetingTranscriptLine], packet: MeetingAudioPacket,
                                    meetingID: UUID) {
        change(meetingID) {
            $0.transcript.append(contentsOf: lines)
            $0.transcript.sort { $0.offset < $1.offset }
        }
        // 产品决定：转写完成不再自动触发纪要（见 init 里的心跳断开说明）。
    }

    /// 队列超限：显式失败（原 backpressure 分支）。已排队的包照常送完。
    private func handleTransportOverflow(meetingID: UUID) {
        guard !blockedAudio.contains(meetingID) else { return }
        pauseTranscription(meetingID: meetingID, message: MeetingPiError.audioBackpressure.localizedDescription)
    }

    /// 发送失败：与原 pumpAudio catch 同语义（错误 + 停采集），ledger 已留下
    /// captured/acknowledged 差额，损失可观测。
    private func handleTransportError(meetingID: UUID, _ error: Error) {
        pauseTranscription(meetingID: meetingID, message: error.localizedDescription)
    }

    private func pauseTranscription(meetingID: UUID, message: String) {
        blockedAudio.insert(meetingID)
        recorder.detachTranscription()
        closeInputStream()
        transport?.cancel(); transport = nil; transportMeetingID = nil; transcribing = false
        error = recordingID == meetingID ? "实时转写已暂停，本地录音继续保存。\(message)" : message
    }

    @discardableResult
    private func generateMinutes(for id: UUID, automatically: Bool) -> Bool {
        guard minutesTask == nil, !updatingMinutes,
              let meeting = meetings.first(where: { $0.id == id }), !meeting.transcript.isEmpty,
              !automatically || !meeting.minutesIsManual else { return false }
        let lines = meeting.transcript
        let revision = minutesEditRevisions[id, default: 0]
        let configuration = configuration
        // Both triggers acquire the same slot immediately. Busy ticks/clicks are
        // discarded instead of queued, and the five-minute interval restarts on completion.
        heartbeat?.cancel(); heartbeat = nil
        error = nil
        updatingMinutes = true
        minutesTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            defer {
                self.minutesTask = nil; self.updatingMinutes = false
                self.scheduleAutomaticMinutes()
            }
            do {
                let minutes = try await self.ai.updateMinutes(configuration: configuration, minutes: "", lines: lines)
                guard !minutes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MeetingPiError.invalidResult }
                // Keep edits made while the model request was running.
                guard self.minutesEditRevisions[id, default: 0] == revision else { return }
                self.change(id) {
                    $0.minutes = minutes
                    $0.summarizedLineIDs = lines.map(\.id)
                    $0.minutesUpdatedAt = Date()
                    $0.minutesEditedByUser = nil
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
        return true
    }

    private func change(_ id: UUID, _ mutation: (inout MeetingRecord) -> Void) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        mutation(&meetings[index]); save()
    }
    private func save() { persistence.schedule(Snapshot(meetings: meetings, configuration: configuration)) }
    func flush(_ completion: @escaping (Error?) -> Void) {
        if recordingID != nil { stopRecording() }
        _Concurrency.Task { [self] in
            while transport?.isBusy == true || inputStream != nil || !savingRecordingIDs.isEmpty {
                try? await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
            }
            persistence.flush(completion)
        }
    }
}
