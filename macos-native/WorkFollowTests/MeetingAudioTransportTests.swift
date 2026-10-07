import AVFoundation
import XCTest
@testable import WorkFollow

/// MEETING-AUDIO-001 的故障注入测试。正常说一句话识别成功没有意义——
/// 这里主动制造故障：主线程卡顿、ACK 慢、队列超限、发送失败、账本缺口，
/// 验证的都是同一件事：**采集过的 PCM 不静默丢失，状态不撒谎**。
final class MeetingAudioTransportTests: XCTestCase {
    private func packet(_ sequence: UInt64, bytes: Int = 8_000, offset: TimeInterval) -> MeetingAudioPacket {
        MeetingAudioPacket(pcm: Data(repeating: UInt8(sequence % 127 + 1), count: bytes),
                           offset: offset, sequence: sequence)
    }

    /// 等待账本确认水位追上采集水位（或到达指定值）。
    private func waitForAcknowledgement(_ transport: MeetingAudioTransport,
                                        atLeast target: TimeInterval) async {
        var snapshot = transport.snapshot()
        var rounds = 0
        while snapshot.acknowledgedUntil < target, rounds < 400 {
            try? await _Concurrency.Task.sleep(nanoseconds: 10_000_000)
            snapshot = transport.snapshot()
            rounds += 1
        }
    }

    /// 主线程被故意占用 2 秒（比采集侧旧的 1 秒积压上限更长），采集线程照常
    /// enqueue：所有包必须全部入队、全部确认、sequence 连续。
    func testEnqueueSurvivesBlockedMainActorWithoutLoss() async throws {
        let transport = MeetingAudioTransport(maximumBytes: 60 * 32_000) { _ in
            try await _Concurrency.Task.sleep(nanoseconds: 10_000_000)
        }
        let total = 40
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // 故意把主线程占住 2 秒；采集在另一条线程上继续投递。
            DispatchQueue.main.async { Thread.sleep(forTimeInterval: 2) }
            DispatchQueue(label: "meeting-capture-sim").async {
                for index in 0..<total {
                    transport.enqueue([self.packet(UInt64(index), offset: Double(index) * 0.25)])
                }
                continuation.resume()
            }
        }
        await waitForAcknowledgement(transport, atLeast: Double(total) * 0.25)
        let snapshot = transport.snapshot()
        XCTAssertEqual(snapshot.entries.count, total, "入队的包一个都不能少")
        XCTAssertNil(snapshot.firstMissingSequence, "sequence 必须连续（无缺口）")
        XCTAssertEqual(snapshot.acknowledgedUntil, snapshot.capturedUntil,
                       "主线程卡 2 秒期间采集的音频必须全部送达并确认")
        XCTAssertEqual(transport.pendingByteCount, 0)
    }

    /// Pi 每包 ACK 都拖 200ms：包进入 pending 排队，不丢、不重、顺序保持。
    func testSlowAcknowledgementsQueueUpWithoutLoss() async throws {
        let counter = SendableCounter()
        let transport = MeetingAudioTransport(maximumBytes: 60 * 32_000) { _ in
            _ = await counter.increment()
            try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        }
        let total = 10
        for index in 0..<total {
            transport.enqueue([packet(UInt64(index), offset: Double(index) * 0.25)])
        }
        await waitForAcknowledgement(transport, atLeast: Double(total) * 0.25)
        let sends = await counter.value
        XCTAssertEqual(sends, total, "每个包恰好发送一次（幂等去重在 Pi 侧，重试是下一阶段）")
        let snapshot = transport.snapshot()
        XCTAssertEqual(snapshot.entries.map(\.sequence), Array(0..<UInt64(total)))
        XCTAssertEqual(snapshot.acknowledgedUntil, snapshot.capturedUntil)
    }

    /// 队列超限：超限包显式拒绝（不入队、不静默丢），已排队包照常送完。
    /// 验收修正（P0）：overflow 之后 transport 立即 latch 拒收——后续包哪怕
    /// 泵已消化出空间也不得再入队，杜绝"100、[101 丢]、102、103"式中间缺口。
    func testOverflowRejectsOnlyTheOverflowingPacketAndDrainsTheRest() async throws {
        var overflowed = false
        let transport = MeetingAudioTransport(maximumBytes: 3 * 8_000) { _ in
            try await _Concurrency.Task.sleep(nanoseconds: 5_000_000)
        }
        transport.onOverflow = { overflowed = true }
        transport.enqueue([packet(0, offset: 0), packet(1, offset: 0.25), packet(2, offset: 0.5)])
        let rejected = transport.enqueue([packet(3, offset: 0.75)])
        XCTAssertEqual(rejected, .overflow)
        // latch 之后的包：全部拒收，只进账本。
        let afterLatch = transport.enqueue([packet(4, offset: 1.0), packet(5, offset: 1.25)])
        XCTAssertEqual(afterLatch, .rejectedAfterFailure)
        await waitForAcknowledgement(transport, atLeast: 0.75)
        XCTAssertTrue(overflowed, "超限必须显式通知，不能悄悄吞掉")
        let snapshot = transport.snapshot()
        XCTAssertEqual(snapshot.entries.count, 6, "被拒的包也进账本（captured but rejected）")
        XCTAssertEqual(snapshot.entries.last?.state, .captured)
        XCTAssertEqual(snapshot.acknowledgedUntil, 0.75, "已排队的包照常送完")
        XCTAssertEqual(snapshot.capturedUntil, 1.5, "latch 后的包仍被采集账本如实记录")
        XCTAssertEqual(snapshot.acknowledgedLag, 0.75, accuracy: 0.0001,
                       "账本明确指出 0.75s 之后的内容没有被确认")
    }

    /// 发送失败：排队包清空（与旧行为一致），但账本保留 captured/acknowledged 差额。
    func testSendFailureStopsTransportButKeepsTheLossVisible() async throws {
        struct Exploded: Error {}
        let transport = MeetingAudioTransport(maximumBytes: 60 * 32_000) { packet in
            if packet.sequence == 1 { throw Exploded() }
        }
        transport.enqueue([packet(0, offset: 0), packet(1, offset: 0.25), packet(2, offset: 0.5)])
        var rounds = 0
        while transport.pendingByteCount != 0, rounds < 400 {
            try? await _Concurrency.Task.sleep(nanoseconds: 10_000_000)
            rounds += 1
        }
        XCTAssertEqual(transport.pendingByteCount, 0)
        let snapshot = transport.snapshot()
        XCTAssertEqual(snapshot.entries[0].state, .acknowledged)
        XCTAssertGreaterThanOrEqual(snapshot.entries[1].state, .sent)
        XCTAssertEqual(snapshot.acknowledgedUntil, 0.25, "账本如实记录：只有第一段被确认")
        XCTAssertGreaterThan(snapshot.acknowledgedLag, 0)
    }
}

/// 测试辅助：跨执行器计数的极小计数器。
private final class SendableCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    @discardableResult
    func increment() -> Int { lock.withLock { count += 1; return count } }
}

/// Ledger 单元测试：水位必须按"最长连续前缀"推进，缺口要被钉出来。
final class MeetingAudioLedgerTests: XCTestCase {
    func testWatermarksOnlyAdvanceOverContiguousPrefix() {
        let ledger = MeetingAudioLedger()
        var cursor: TimeInterval = 0
        var nextSequence: UInt64 = 0
        func record(seconds: TimeInterval) -> TimeInterval {
            let packet = MeetingAudioPacket(pcm: Data(repeating: 1, count: Int(seconds * 32_000)),
                                            offset: cursor, sequence: nextSequence)
            ledger.recordCaptured(packet)
            cursor += seconds; nextSequence += 1
            return packet.endOffset
        }
        for _ in 0..<3 { record(seconds: 0.25) }

        ledger.markSent(1); ledger.markAcknowledged(1)
        var snapshot = ledger.snapshot()
        XCTAssertEqual(snapshot.sentUntil, 0, "前面还有未发送的包，水位不能跳")
        XCTAssertEqual(snapshot.acknowledgedUntil, 0)

        ledger.markSent(0)
        snapshot = ledger.snapshot()
        XCTAssertEqual(snapshot.sentUntil, 0.5, "补上 0 之后水位推进到 1（2 还没发）")

        ledger.markSent(2); ledger.markAcknowledged(0); ledger.markAcknowledged(2)
        snapshot = ledger.snapshot()
        XCTAssertEqual(snapshot.sentUntil, 0.75)
        XCTAssertEqual(snapshot.acknowledgedUntil, 0.5, "acknowledged 水位卡在未确认的 1")
        ledger.markAcknowledged(1)
        snapshot = ledger.snapshot()
        XCTAssertEqual(snapshot.acknowledgedUntil, 0.75)
        XCTAssertEqual(snapshot.acknowledgedLag, 0, accuracy: 0.0001)
    }

    func testSequenceGapIsPinnedInsteadOfSilentlyIgnored() {
        let ledger = MeetingAudioLedger()
        ledger.recordCaptured(MeetingAudioPacket(pcm: Data(repeating: 1, count: 8),
                                                 offset: 0, sequence: 0))
        ledger.recordCaptured(MeetingAudioPacket(pcm: Data(repeating: 1, count: 8),
                                                 offset: 0.5, sequence: 2))
        let snapshot = ledger.snapshot()
        // entries [0, 2]：缺的是 1 本身（验收修正 P1），不是实际收到的 2。
        XCTAssertEqual(snapshot.firstMissingSequence, 1, "102→103→105 必须报出缺失的 104")
    }
}

/// 采集器分配的 sequence 必须连续（含收尾包），时间位置以累计 PCM 为基准。
final class MeetingCaptureSequenceTests: XCTestCase {
    func testCaptureAssignsContinuousSequencesAcrossBatchesAndTail() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                 sampleRate: 48_000, channels: 1, interleaved: false))
        let capture = try MeetingPCMCapture(format: format, offset: 0, streaming: true)
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        input.frameLength = 48_000
        for frame in 0..<48_000 { input.floatChannelData![0][frame] = 0.1 }
        var sequences: [UInt64] = []
        // 48k×1s 输入 ≈ 16k×1s 输出 = 4 个 0.25s 包；多次 consume 模拟多轮回调。
        for _ in 0..<6 {
            _ = try capture.consume(input)
            sequences.append(contentsOf: capture.drain().map(\.sequence))
        }
        sequences.append(contentsOf: capture.finish().map(\.sequence))
        XCTAssertEqual(sequences, Array(0..<UInt64(sequences.count)), "sequence 必须从 0 连续递增，无缺口")
        XCTAssertTrue(sequences.count >= 24, "0.25s 分段下 6 秒输入至少应有 24 个包")
    }
}
