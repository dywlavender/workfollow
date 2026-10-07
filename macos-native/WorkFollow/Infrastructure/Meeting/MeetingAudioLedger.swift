import Foundation

/// 每个已采集音频包的状态账本（MEETING-AUDIO-001）。只记"这块音频走到了哪"，
/// **不保存音频内容**——它回答的是"captured 68.5s / acknowledged 41s"这类问题，
/// 让"Pi 已经跟不上"变成可观测的事实，而不是继续假装正常录音。
///
/// sequence 由采集侧从 0 连续递增（`MeetingPCMCapture` 保证），所以数组下标即
/// sequence、水位按"最长连续前缀"推进；一旦出现缺口（理论上是采集侧 bug），
/// `firstMissingSequence` 会把它钉出来，而不是让水位悄悄谎报。
///
/// 线程约定：自身带锁，可从任意线程读写；`MeetingAudioTransport` 在持有自身锁
/// 的情况下调用这里（单向嵌套 transport → ledger，绝不反向，无死锁）。
final class MeetingAudioLedger: @unchecked Sendable {
    enum State: Int, Comparable {
        case captured = 0
        case sent
        case acknowledged

        static func < (lhs: MeetingAudioLedger.State, rhs: MeetingAudioLedger.State) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct Entry: Equatable, Sendable {
        let sequence: UInt64
        let start: TimeInterval
        let end: TimeInterval
        let byteCount: Int
        var state: State
    }

    /// 只读快照：给测试、调试与未来的 UI 状态栏用。
    struct Snapshot: Equatable, Sendable {
        let entries: [Entry]
        /// 已采集到 / 已发出 / 已被 Pi 确认的音频末尾（秒，相对会议开头）。
        let capturedUntil: TimeInterval
        let sentUntil: TimeInterval
        let acknowledgedUntil: TimeInterval
        /// sequence 不连续时指向第一个缺口；连续采集下恒为 nil。
        let firstMissingSequence: UInt64?

        /// "Pi 已经跟不上"的直接判据：确认水位明显落后于采集水位。
        var acknowledgedLag: TimeInterval { capturedUntil - acknowledgedUntil }
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var sentWatermark = 0
    private var acknowledgedWatermark = 0

    func recordCaptured(_ packet: MeetingAudioPacket) {
        lock.withLock {
            entries.append(Entry(sequence: packet.sequence, start: packet.offset,
                                 end: packet.endOffset, byteCount: packet.pcm.count,
                                 state: .captured))
        }
    }

    func markSent(_ sequence: UInt64) {
        lock.withLock { advance(sequence, to: .sent) }
    }

    func markAcknowledged(_ sequence: UInt64) {
        lock.withLock { advance(sequence, to: .acknowledged) }
    }

    private func advance(_ sequence: UInt64, to state: State) {
        let index = Int(sequence)
        guard index < entries.count, state > entries[index].state else { return }
        entries[index].state = state
        // 水位只按最长连续前缀推进：中间有未确认的包，后面的确认不算数。
        switch state {
        case .captured: break
        case .sent:
            while sentWatermark < entries.count, entries[sentWatermark].state >= .sent { sentWatermark += 1 }
        case .acknowledged:
            while acknowledgedWatermark < entries.count,
                  entries[acknowledgedWatermark].state >= .acknowledged { acknowledgedWatermark += 1 }
        }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            let captured = entries.last?.end ?? 0
            let sent = sentWatermark > 0 ? entries[sentWatermark - 1].end : 0
            let acknowledged = acknowledgedWatermark > 0 ? entries[acknowledgedWatermark - 1].end : 0
            var gap: UInt64?
            for (index, entry) in entries.enumerated() where entry.sequence != UInt64(index) {
                // 缺的是"应该在的那个序号"：entries [0, 2] → 缺 1（验收修正 P1）。
                gap = UInt64(index)
                break
            }
            return Snapshot(entries: entries, capturedUntil: captured, sentUntil: sent,
                            acknowledgedUntil: acknowledged, firstMissingSequence: gap)
        }
    }
}
