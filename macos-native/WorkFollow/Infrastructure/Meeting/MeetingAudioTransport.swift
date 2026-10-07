import Foundation

/// 音频传输总线（MEETING-AUDIO-001）：采集线程只管 enqueue，这里串行地送出去
/// 并记账。**采集路径上绝不等待 MainActor / 网络 / Pi** —— 主线程再卡，也不影响
/// 已经采集到的 PCM；主线程只接收状态通知，不在关键路径上。
///
/// 可靠性模型：
/// - Pending 队列里的包**绝不覆盖**。超过 `maximumBytes` 走显式失败（`onOverflow`，
///   Store 停止录音并提示）；超限那一刻**已排队的包继续送完**，只有超限包不入队。
/// - 每个包带单调 sequence；Pi 扩展按 sequence 幂等去重（同一 seq 只 append
///   一次），为下一阶段的"ACK 丢失自动重试"提供不丢也不重的底座。
/// - `MeetingAudioLedger` 记录每个包 captured → sent → acknowledged 的水位。
///
/// 与旧行为的差异（有意，均为收紧）：①超限只拒绝超限包本身、不再"丢光全部
/// 排队包"，排队包在停止流程里照常送完；②发送失败时排队包照旧清空（行为
/// 不变），但 ledger 保留 captured/acknowledged 的差额记录，损失范围可观测。
/// Repair Buffer 与停止排空的重设计属 MEETING-AUDIO-003。
final class MeetingAudioTransport: @unchecked Sendable {
    enum EnqueueResult: Equatable {
        case accepted
        /// 队列已满：这个包**没有**入队，进入显式失败态。
        case overflow
        /// 已处于失败态：包只记入 ledger（captured 但永不发送），不再排队。
        case rejectedAfterFailure
    }

    /// 把一个包送出去并等它被确认。流式路径是 `session.append`（ACK 即扩展
    /// 幂等落地），批量路径是 `transcribe`（返回即该包已产生文字）。
    typealias Sender = @Sendable (MeetingAudioPacket) async throws -> Void

    private let lock = NSLock()
    private var pending: [MeetingAudioPacket] = []
    private var pendingBytes = 0
    private var inFlightBytes = 0
    private var pumping = false
    /// 验收修正（P0）：overflow 必须**同步** latch——不等 MainActor 回调链
    /// （onOverflow → Store → stopRecording）回来才停。否则泵消化出空间的窗口
    /// 里，后续包会重新入队，形成"100、[101 丢]、102、103"的中间缺口。latch
    /// 之后：新包只记账（captured but rejected）不再入队；pending 照常送完。
    /// 与 `failed`（发送失败，清队列停泵）是两个独立状态。
    private var accepting = true
    private var stopping = false
    private var failed = false
    private var settleStarted = false
    private var settled = false
    private var finisher: Sender?
    private let maximumBytes: Int
    private let send: Sender
    private let ledger = MeetingAudioLedger()

    /// 回调统一在 MainActor 上触发（Store 是 MainActor）；触发是普通
    /// `Task { @MainActor }`，不阻塞传输，也不要求主线程空闲。
    var onCapture: (@MainActor @Sendable (TimeInterval) -> Void)?
    var onOverflow: (@MainActor @Sendable () -> Void)?
    var onError: (@MainActor @Sendable (Error) -> Void)?
    /// 队列排空（无论是否处于停止流程）。Store 用它回收 transcribing 状态。
    var onIdle: (@MainActor @Sendable () -> Void)?
    /// 停止流程完全落定（排队包送完 + finisher 完成）。
    var onSettled: (@MainActor @Sendable () -> Void)?

    init(maximumBytes: Int, send: @escaping Sender) {
        self.maximumBytes = maximumBytes
        self.send = send
    }

    /// 停止流程中，队列排空后要做的收尾（流式路径 = `session.finish()` +
    /// Store 收尾）。批量路径没有 finisher，排空即结束。
    func bindFinisher(_ finisher: Sender?) {
        lock.withLock { self.finisher = finisher }
    }

    /// 从采集线程调用：非阻塞、无 MainActor 依赖。按传入顺序入队。
    @discardableResult
    func enqueue(_ packets: [MeetingAudioPacket]) -> EnqueueResult {
        var result = EnqueueResult.accepted
        var capturedUntil: TimeInterval = 0
        lock.withLock {
            for packet in packets {
                ledger.recordCaptured(packet)
                capturedUntil = packet.endOffset
                if failed || !accepting {
                    // 失败态或超限已 latch：包只记账（captured but rejected），
                    // 不再入队——缺口之后不允许再有音频进入 Pi。
                    result = .rejectedAfterFailure
                } else if pendingBytes + packet.pcm.count > maximumBytes {
                    // 显式失败：同步 latch 接收（见 accepting 注释），只拒绝
                    // 超限包本身；已排队包在停止流程里照常送完。
                    accepting = false
                    result = .overflow
                } else {
                    pending.append(packet)
                    pendingBytes += packet.pcm.count
                }
            }
            if !pending.isEmpty { startPumpIfNeeded() }
        }
        if capturedUntil > 0 { notify(onCapture, capturedUntil) }
        if result == .overflow { notify(onOverflow) }
        return result
    }

    /// 录音已停止：不再接受新包（采集侧在此之前已把最后一块 PCM enqueue 进来），
    /// 排空后执行 finisher。
    func stopAccepting() {
        var startSettle = false
        lock.withLock {
            stopping = true
            if !pumping && !settleStarted { startSettle = true }
        }
        if startSettle { _Concurrency.Task { await self.settleAfterDrain() } }
    }

    /// 等待发送的字节数（排队 + 在途）。Store 的 bufferedAudioBytes 用它。
    var pendingByteCount: Int {
        lock.withLock { pendingBytes + inFlightBytes }
    }

    /// 传输还有没走完的事（泵在跑 / 有存货 / 停止收尾未完成）。
    var isBusy: Bool {
        lock.withLock {
            pumping || pendingBytes > 0 || inFlightBytes > 0 || (stopping && !settled)
        }
    }

    func snapshot() -> MeetingAudioLedger.Snapshot {
        ledger.snapshot()
    }

    // MARK: - 泵

    /// 必须在持有 lock 时调用。
    private func startPumpIfNeeded() {
        guard !pumping, !failed else { return }
        pumping = true
        _Concurrency.Task { [weak self] in await self?.pumpLoop() }
    }

    private func pumpLoop() async {
        while true {
            let next: MeetingAudioPacket? = lock.withLock {
                guard !failed, !pending.isEmpty else {
                    pumping = false
                    return nil
                }
                let packet = pending.removeFirst()
                pendingBytes -= packet.pcm.count
                inFlightBytes += packet.pcm.count
                ledger.markSent(packet.sequence)
                return packet
            }
            guard let packet = next else { break }
            do {
                try await send(packet)
            } catch {
                // 发送失败：与旧行为一致清空队列（bytes 归零），但 ledger 保留
                // captured/acknowledged 的差额，损失可观测。会话本身由 Store 收尾。
                lock.withLock {
                    pending.removeAll()
                    pendingBytes = 0
                    inFlightBytes = 0
                    pumping = false
                    failed = true
                }
                notify(onError, error)
                return
            }
            lock.withLock {
                inFlightBytes -= packet.pcm.count
                ledger.markAcknowledged(packet.sequence)
            }
        }
        let shouldSettle = lock.withLock { stopping }
        if shouldSettle {
            await settleAfterDrain()
        } else {
            notify(onIdle)
        }
    }

    private func settleAfterDrain() async {
        let finish: Sender? = lock.withLock {
            guard !settleStarted else { return nil }
            settleStarted = true
            pumping = false
            return finisher
        }
        guard let finish else { return }
        do {
            try await finish(MeetingAudioPacket(pcm: Data(), offset: 0))
        } catch {
            notify(onError, error)
        }
        lock.withLock { settled = true }
        notify(onSettled)
    }

    private func notify(_ callback: (@MainActor @Sendable (TimeInterval) -> Void)?, _ value: TimeInterval) {
        guard let callback else { return }
        _Concurrency.Task { @MainActor in callback(value) }
    }

    private func notify(_ callback: (@MainActor @Sendable () -> Void)?) {
        guard let callback else { return }
        _Concurrency.Task { @MainActor in callback() }
    }

    private func notify(_ callback: (@MainActor @Sendable (Error) -> Void)?, _ error: Error) {
        guard let callback else { return }
        _Concurrency.Task { @MainActor in callback(error) }
    }
}
