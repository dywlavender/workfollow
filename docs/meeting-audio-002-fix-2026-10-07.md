# MEETING-AUDIO-002-fix 验收记录

## 结论与范围

本轮三个源码问题已修复，并使用最新构建执行本机测试。未进入 003；没有实现 Repair Buffer、自动补转写、失败段 UI 或完整 Stop Drain 状态机。不能据此宣称“录音不会遗漏”。

## 修复与实际验证

| 问题 | 修改 | 回归证据 |
|---|---|---|
| 同批后续拒收覆盖 overflow | enqueue 独立保存 didOverflow，本批发生过超限就返回 overflow 并通知 | `testOverflowWinsOverLaterRejectionsInTheSameBatch`：一批 seq 0 接受、1 超限、2 拒收，返回 overflow、回调一次；只有 0 送达，后续仍 latch 拒收且记账 |
| 4 秒宽限未接生产调度 | 每个 speechStopped 安排独立 Task，Final 到达则取消；重复 stopped 不重置计时；关闭取消任务并用 session token 隔离 | `testProductionDeadlineDetectsMissingWhileStreamRemainsOpen`：不手动 sweep、不关闭流，实际等待 4.2 秒后判 missingFinal；提前 Final 保持 completed、重复 stopped 不延后、切换所选会议不干扰；迟到 Final 可归位 |
| 断流中 recording 永远不完结 | 已关闭会话 force sweep 将 recording / awaitingFinal 都转 missingFinal；recording 的 end 保持 nil | `testLifecycleEventsDriveTurnTrackerAndCloseSweepsMissing`：注入异常断流，两个状态都判缺失；`testClosedSessionDeadlineCannotExpireReusedIDInNewSession`：旧 deadline 不影响新会话 |

Task 在 MainActor 恢复后执行状态检查；4 秒是宽限阈值，不是主线程阻塞时仍保证准点的实时调度承诺。

## 执行结果

- 最新 `build-for-testing`：TEST BUILD SUCCEEDED。
- 10 个会议相关 XCTest 套件：42 项实际执行，0 失败。包含已安装 Pi 的本机 RPC fixture 集成测试，不调用外部模型。
- `node --test macos-native/scripts/tests/meeting-stream.test.mjs`：5 项实际执行，0 失败。覆盖幂等去重、跳号拒绝和尾静音门限等已有协议。
- `git diff --check`：通过。

首次编译时，新测试误用了旧 async flush 调用形式；已改为当前 completion 接口并重建。首次成功构建后的回归发现旧 Ledger 测试构造矛盾：先 ACK seq 1，却随后断言 seq 1 未确认。修正构造，未修改 Ledger 业务代码；最终重新构建并完整执行上述 42 项全部通过。

复现命令（仓库根目录）：

```sh
MEETING_PI_INTEGRATION=1 \
WORKFOLLOW_DERIVED_DATA=/private/tmp/wf-meeting-pi-adapter-build \
WORKFOLLOW_DISABLE_SWIFT_SANDBOX=1 \
macos-native/scripts/run-tests.sh \
  MeetingAudioTransportTests MeetingAudioLedgerTests MeetingCaptureSequenceTests \
  MeetingSpeechTurnTrackerTests MeetingSpeechTurnStoreWiringTests \
  MeetingStreamingTests MeetingMemoryAudioTests MeetingStoreTests \
  MeetingPiBridgeIntegrationTests MeetingPiOwnershipTests
```

## 未完成验收

这是本机运行证据，不是 CI 证据；本轮没有真人录音、长会议或 UI 端到端验收。ACK-only loss 集成测试仍待补充，已有 fixture 仍是吞掉首次命令；本轮没有把它算作“已 append 但仅丢 ACK”的证明。

自动纪要触发保持断开；录音内存传输和 Pi 所有权不变。代码未提交、未推送。
