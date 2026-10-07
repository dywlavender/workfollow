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
    private var minutesTask: _Concurrency.Task<Void, Never>?
    private var recordingOffset: TimeInterval = 0
    /// At most 60 seconds, including the request currently being processed.
    static let maximumAudioBytes = 60 * 32_000
    var bufferedAudioBytes: Int { transport?.pendingByteCount ?? 0 }
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
            self?.error = "录音中断：\(error.localizedDescription)"
        }
        if automaticallyUpdate {
            // 产品决定（验收评审）：纪要不再自动生成，改为**按钮点击生成**
            // （`updateMinutesNow`）。25 秒心跳的自动触发在此断开——长录可靠
            // 性测试（MEETING-AUDIO-RELIABILITY）之前，录音中额外启动 Pi/模型
            // 请求会造成资源竞争，也不再符合产品定义。心跳代码保留在此，
            // 恢复自动生成时从这里接回；纪要 UI 与历史数据不动。
            // heartbeat = Timer.publish(every: 25, on: .main, in: .common).autoconnect()
            //     .sink { [weak self] _ in
            //         guard let self else { return }
            //         for meeting in self.meetings where !meeting.minutesIsManual &&
            //             meeting.summarizedLineCount < meeting.transcript.count &&
            //             !self.blockedMinutes.contains(meeting.id) {
            //             self.pendingMinutes.insert(meeting.id)
            //         }
            //         self.pumpMinutes()
            //     }
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
            let streaming = try await connectInputStream(for: id, offset: recordingOffset)
            if !streaming { createBatchTransport(for: id) }
            guard generation == permissionGeneration, let transport else {
                closeInputStream(); return
            }
            requestingPermission = false
            try recorder.start(offset: recordingOffset, streaming: streaming, transport: transport)
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
        _ = id // 恢复自动纪要时此绑定重新被下面的注释块使用
        recordingID = nil
        recorder.stop()
        if inputStream != nil { streamStopping = true; transport?.stopAccepting(); return }
        // 产品决定：停止录音不再自动生成纪要（见 init 里的心跳断开说明）。
        // if let id, !blockedMinutes.contains(id) { pendingMinutes.insert(id); pumpMinutes() }
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
        turnTracker.reset()
        createStreamingTransport(meetingID: id, session: session)
        return true
    }

    /// 当前流的 turn 快照（按讲话开始顺序）。003 的 Repair 输入与失败段 UI 用。
    var speechTurns: [MeetingSpeechTurn] { turnTracker.snapshot }

    private func closeInputStream() {
        if let stream = inputStream { streamDrafts.removeValue(forKey: stream.meetingID); stream.session.cancel() }
        inputStream = nil; streamToken = UUID(); streamStopping = false
        // 会话关闭后不会再有 final：仍未完成的 turn 直接判缺失（002 检测层）。
        turnTracker.sweep(force: true)
        if transport?.isBusy != true { transcribing = false }
    }

    func receiveStreamEvent(_ event: MeetingStreamEvent, meetingID: UUID) {
        guard inputStream?.meetingID == meetingID else { return }
        if event.kind == "error" {
            error = event.message ?? "Pi 流式转写失败。"
            blockedAudio.insert(meetingID); closeInputStream(); stopRecording(); return
        }
        // VAD 生命周期（MEETING-AUDIO-002）：start/stop 不带文字，先进 turn
        // 状态机；"有讲话但没有 Final"由 tracker 按宽限期判定 missingFinal。
        if event.kind == MeetingStreamKind.speechStarted || event.kind == MeetingStreamKind.speechStopped {
            if event.kind == MeetingStreamKind.speechStarted {
                turnTracker.speechStarted(itemID: event.itemID ?? "", at: event.offset ?? 0)
            } else {
                turnTracker.speechStopped(itemID: event.itemID ?? "", at: event.offset ?? 0)
            }
            return
        }
        guard let item = event.itemID, let text = event.text,
              let offset = event.offset, offset.isFinite, offset >= 0, !streamFinalIDs.contains(item) else { return }
        if event.kind == MeetingStreamKind.finalText { turnTracker.finalize(itemID: item) }
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
        transport.onCapture = { [weak self] until in
            _Concurrency.Task { @MainActor [weak self] in
                guard let self, self.transportMeetingID == meetingID else { return }
                self.change(meetingID) { $0.capturedDuration = max($0.duration, until) }
            }
        }
        transport.onOverflow = { [weak self] in
            _Concurrency.Task { @MainActor [weak self] in self?.handleTransportOverflow(meetingID: meetingID) }
        }
        transport.onError = { [weak self] error in
            _Concurrency.Task { @MainActor [weak self] in self?.handleTransportError(meetingID: meetingID, error) }
        }
        transport.onIdle = { [weak self] in
            _Concurrency.Task { @MainActor [weak self] in
                guard let self else { return }
                self.transcribing = self.inputStream != nil
            }
        }
        transport.onSettled = { [weak self] in
            _Concurrency.Task { @MainActor [weak self] in self?.transcribing = false }
        }
    }

    private func createStreamingTransport(meetingID: UUID, session: any MeetingAudioStream) {
        let transport = MeetingAudioTransport(maximumBytes: Self.maximumAudioBytes) { packet in
            try await session.append(packet)
        }
        transport.bindFinisher { [weak self] _ in
            try await session.finish()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.closeInputStream()
                // 产品决定：流式收尾不再自动生成纪要（见 init 里的心跳断开说明）。
                // if !self.blockedMinutes.contains(meetingID) {
                //     self.pendingMinutes.insert(meetingID); self.pumpMinutes()
                // }
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
        // if recordingID != meetingID, !blockedMinutes.contains(meetingID) {
        //     pendingMinutes.insert(meetingID); pumpMinutes()
        // }
    }

    /// 队列超限：显式失败（原 backpressure 分支）。已排队的包照常送完。
    private func handleTransportOverflow(meetingID: UUID) {
        guard !blockedAudio.contains(meetingID) else { return }
        blockedAudio.insert(meetingID)
        stopRecording()
        error = MeetingPiError.audioBackpressure.localizedDescription
    }

    /// 发送失败：与原 pumpAudio catch 同语义（错误 + 停采集），ledger 已留下
    /// captured/acknowledged 差额，损失可观测。
    private func handleTransportError(meetingID: UUID, _ error: Error) {
        blockedAudio.insert(meetingID)
        closeInputStream()
        stopRecording()
        self.error = error.localizedDescription
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
            while transport?.isBusy == true || inputStream != nil {
                try? await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
            }
            persistence.flush(completion)
        }
    }
}
