# MEETING-AUDIO-RELIABILITY-001 · 语音不遗漏

> 2026-10-07 更新：以下为阶段历史记录，不能作为整体最终 PASS。
> 同批 overflow 返回优先级、生产 4 秒 missing-final 调度、关闭流中的 recording 判缺失已在 002-fix 修正。
> 最新构建本机 42 项 XCTest 与 5 项 Node 协议测试通过；003 仍未开始。
> 详见 [本轮验收记录](meeting-audio-002-fix-2026-10-07.md)。

目标只有一句：

> **麦克风已经采集到的语音，要么最终产生文字，要么系统明确告诉用户哪一段失败；绝不能静默消失。**

> **验收记录**：001 经外部验收判定"方向正确、主体完成"，提出 2 个修正后冻结——
> ①（P0）overflow 后 transport 未同步停收，存在"100、[101 丢]、102、103"窗口；
> ②（P1）`firstMissingSequence` 返回的是实际收到的序号而非缺失的序号。
> 另提前收紧 Pi 幂等：不允许向前跳号。三项已在验收修正提交中修完并补测试；
> 同时按产品决定断开纪要自动生成（心跳/转写完成/停止录音三处触发，保留手动
> 按钮与历史数据）。**001 状态：冻结。002 是下一步。**

范围约束：本轮**不碰**转写纠错、说话人区分，也**不调** VAD 参数（threshold 0.2 /
prefix 500ms / silence 800ms 先原样观测）。任何内存策略的失败都是真丢失（音频不落盘是
产品约束）；"零丢失"的终极方案（会议期间临时加密落盘、会话结束即焚）是产品决策，未拍板前
本轮目标定为"尽力而为 + 损失可观测 + 显式失败"。

## 三笔提交拆分

| Commit | 内容 | 状态 |
|---|---|---|
| `MEETING-AUDIO-001` | Capture 脱离 MainActor + packet sequence + Pending Queue + AudioLedger + 扩展幂等去重 | ✅ 已完成 |
| `MEETING-AUDIO-002` | ACK 丢失安全重试（会话超时存活 + 扩展幂等去重）+ speech start/stop 生命周期事件（VAD turn 状态机 `MeetingSpeechTurnTracker`，宽限期判 missingFinal）+ 尾静音修复（语义化 `finishSilenceMs=1200 > vadSilenceDurationMs=800`，node 测试锁死） | ✅ 已完成 |
| `MEETING-AUDIO-003` | Repair Buffer（最近 120s 已 ACK PCM 保留供漏转写重试）+ missing-final 检测与自动补转写 + Stop Drain 生命周期（Recording→StoppingCapture→完成转写→结束）+ 失败段 UI（`⚠ 此处检测到讲话，但转写失败 [重试]`） | 待做 |

## 001 已落地的事实

- **采集路径不经过 MainActor**：`MeetingRecorder` 的 tap 在音频渲染线程转码、分段后
  直接 `MeetingAudioTransport.enqueue`；主线程只收通知（onCapture/onOverflow/onError/
  onIdle/onSettled，全部 `Task { @MainActor }`），不在关键路径。
- **packet sequence**：`MeetingPCMAccepture`（`MeetingPCMCapture`）按包连续分配、每次
  录音从 0 起；时间位置继续以累计 PCM 字节数为基准。102→103→105 立刻知道 104 丢。
- **MeetingAudioTransport**（新）：pending 队列串行泵送；超限只拒绝超限包本身并显式
  通知（已排队包在停止流程里照常送完）；发送失败清空队列（与旧行为一致）但 ledger
  保留差额；流式路径 finisher = `session.finish()` + Store 收尾。
- **MeetingAudioLedger**（新）：每包 captured → sent → acknowledged；水位按最长连续
  前缀推进；`firstMissingSequence` 钉缺口；`acknowledgedLag` = "Pi 已跟不上"的直接判据。
- **扩展幂等接收**：`wf-meeting-stream.mjs` 按 sequence 高水位去重（迟到的旧包重发只
  ACK 不再 append；无 sequence 的旧调用方退化为不去重），ACK 带 `{sequence, duplicate}`。
  at-least-once 传输 + 幂等接收 = 不丢也不重的底座；**Native 侧重试在 002**（需要会话
  在超时后存活，当前超时即取消会话）。

## 行为差异（有意收紧，与旧行为对照）

| 场景 | 旧行为 | 001 行为 |
|---|---|---|
| 队列超限 | 丢光全部排队包 + 停录音 | 只拒绝超限包；已排队包照常送完；ledger 记录未确认差额 |
| 发送失败 | `removeAll()` 无账 | 排队包照旧清空，但 ledger 保留 captured/acknowledged 差额 |
| 主线程卡顿 | >1s 即可能采集侧 backpressure 中断 | 与主线程无关（tap 直达 transport） |
| 重复投递 | 会重复 append（重复转写） | 扩展按 sequence 去重，只 ACK 不重放 |

## 故障注入测试（本轮验收）

| 故障 | 断言 | 测试 |
|---|---|---|
| 主线程卡 2 秒 | sequence 连续、全部确认 | `testEnqueueSurvivesBlockedMainActorWithoutLoss` |
| 每包 ACK 拖 200ms | 排队不丢、每包恰好一次 | `testSlowAcknowledgementsQueueUpWithoutLoss` |
| 队列超限 | 超限包显式拒绝 + 已排队送完 + lag 可见 | `testOverflowRejectsOnlyTheOverflowingPacketAndDrainsTheRest` |
| 发送失败 | 队列清空 + 差额留账 | `testSendFailureStopsTransportButKeepsTheLossVisible` |
| 水位/缺口 | 前缀推进、缺口钉出 | `MeetingAudioLedgerTests` |
| 采集 sequence | 跨批次与收尾连续 | `MeetingCaptureSequenceTests` |
| 同 seq 重发/迟到重排 | 只 ACK 不重放 | node `append is idempotent per sequence` |

回归：会议全部套件 31 项 + node 3 项通过；唯一失败 `testPersistenceAndEmptyExtension
AreExplicit` 是在途 WIP 的既有语义冲突（`audioConfigured` 内置兜底后恒真），见 086dd18。

## Done Definition（本轮）

麦克风采集过的 PCM 不静默丢失；传输缺口可检测；有讲话但没有 Final 可检测（002/003
落地后）；能恢复时自动恢复（003）；不能恢复时明确显示失败位置（003）；停止录音不丢
最后一句（003）；任何情况下不写录音文件（始终）。
