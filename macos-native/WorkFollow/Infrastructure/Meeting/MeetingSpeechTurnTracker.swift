import Foundation

/// 音频可靠性策略常量（MEETING-AUDIO-002）。数字集中在这里，不散落在代码里；
/// 调整时改一处，测试金标联动。
enum MeetingAudioReliabilityPolicy {
    /// `speech_stopped` 之后等待 realtime final 的宽限期；超过即判 missingFinal
    /// （"有人讲话但文字没出来"）。003 据此触发 Repair Buffer 补转写。
    static let finalGracePeriod: TimeInterval = 4
}

/// 一段被 VAD 识别的讲话（turn）及其转写生命周期。
struct MeetingSpeechTurn: Equatable {
    enum Status: Equatable {
        /// VAD 已识别讲话开始，还没有结束。
        case recording
        /// 讲话已结束，等待 realtime final。
        case awaitingFinal
        /// final 已到达。
        case completed
        /// 宽限期内没有等到 final（003 补转写的输入）。
        case missingFinal
    }

    let id: String
    let start: TimeInterval
    var end: TimeInterval?
    var status: Status
}

/// VAD 生命周期状态机（MEETING-AUDIO-002）：
///
///     speech_started → recording
///     speech_stopped → awaitingFinal
///     final          → completed
///     awaitingFinal 超过 finalGracePeriod → missingFinal（sweep 时判定）
///
/// 这是"真正用户感知的少了一句话"（VAD 检测到了讲话、ASR 没给 Final）的
/// 检测层；检测在 002 落地，恢复（Repair）与失败段 UI 在 003。
/// 迟到的 final 仍然会把 turn 归位为 completed（文字由原有 final 路径落账）。
final class MeetingSpeechTurnTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var turns: [MeetingSpeechTurn] = []
    private var indexByID: [String: Int] = [:]
    /// awaitingFinal 的宽限计时基准（墙钟，注入便于测试）。
    private var stoppedAt: [String: Date] = [:]
    private let clock: @Sendable () -> Date

    init(clock: @escaping @Sendable () -> Date = Date.init) {
        self.clock = clock
    }

    func speechStarted(itemID: String, at offset: TimeInterval) {
        lock.withLock {
            guard indexByID[itemID] == nil else { return } // 重复 started 幂等
            indexByID[itemID] = turns.count
            turns.append(MeetingSpeechTurn(id: itemID, start: offset, end: nil, status: .recording))
        }
    }

    /// speech_stopped：没有 started 的也宽容建档（start=end），避免丢 turn。
    func speechStopped(itemID: String, at offset: TimeInterval) {
        lock.withLock {
            if let index = indexByID[itemID] {
                turns[index].end = offset
                guard turns[index].status == .recording else { return }
                turns[index].status = .awaitingFinal
            } else {
                indexByID[itemID] = turns.count
                turns.append(MeetingSpeechTurn(id: itemID, start: offset, end: offset,
                                               status: .awaitingFinal))
            }
            stoppedAt[itemID] = clock()
        }
    }

    /// realtime final 到达：任何未完成状态都归位为 completed（幂等）。
    func finalize(itemID: String) {
        lock.withLock {
            guard let index = indexByID[itemID] else { return }
            if turns[index].status != .completed {
                turns[index].status = .completed
                stoppedAt[itemID] = nil
            }
        }
    }

    /// 单个 turn 的生产延迟检查；Final 已到或已判缺失时不做修改。
    func expireFinal(itemID: String) {
        lock.withLock {
            guard let index = indexByID[itemID], turns[index].status == .awaitingFinal,
                  let stopped = stoppedAt[itemID],
                  clock().timeIntervalSince(stopped) >= MeetingAudioReliabilityPolicy.finalGracePeriod
            else { return }
            turns[index].status = .missingFinal
            stoppedAt[itemID] = nil
        }
    }

    /// 把超过宽限仍未完成的 awaitingFinal 标记为 missingFinal。
    /// `force = true` 用于会话已关闭：recording / awaitingFinal 都不可能再完成。
    func sweep(force: Bool = false) {
        lock.withLock {
            let now = clock()
            for (itemID, index) in indexByID {
                if force {
                    guard turns[index].status == .recording || turns[index].status == .awaitingFinal else { continue }
                    turns[index].status = .missingFinal
                    stoppedAt[itemID] = nil
                    continue
                }
                guard turns[index].status == .awaitingFinal else { continue }
                guard let stopped = stoppedAt[itemID],
                      now.timeIntervalSince(stopped) >= MeetingAudioReliabilityPolicy.finalGracePeriod
                else { continue }
                turns[index].status = .missingFinal
                stoppedAt[itemID] = nil
            }
        }
    }

    var missingFinalTurns: [MeetingSpeechTurn] {
        lock.withLock { turns.filter { $0.status == .missingFinal } }
    }

    /// 按讲话开始顺序的全量快照（003 的失败段 UI 与 Repair 输入）。
    var snapshot: [MeetingSpeechTurn] {
        lock.withLock { turns }
    }

    /// 新的流式会话（重连/重新录音）从干净状态开始。
    func reset() {
        lock.withLock {
            turns.removeAll(); indexByID.removeAll(); stoppedAt.removeAll()
        }
    }
}
