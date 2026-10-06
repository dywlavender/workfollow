# 会议音频不落盘：方案、协议与验收

## 本轮范围

保留麦克风实时采集，但不保存新录音。只持久化会议标题、采集时长、对话文字、讲话人标签和滚动纪要。替换原来的 AAC 文件采集，不修改任务/编辑器模块。

链路：AVAudioEngine 连续采集 → 转换为 16 kHz / mono / signed PCM16 → 15 秒内存分段 → Pi RPC 扩展 → 对话文字 → 25 秒增量纪要。暂停提交最后一段，继续时沿用时间偏移。采集不再为每段停止/重新启动。

这仍是**连续采集、分段转写**，不是常驻 Pi + 持续 WebSocket 的低延迟转写。后续已新增 [Pi 内置 Qwen 音频扩展](meeting-pi-audio-adapter-2026-10-06.md)；下方记录的是不落盘改造当时的验收，不能据此声称真实讲话识别或跨片段身份一致性通过。

## 执行顺序

1. 内存采集和 PCM 转换：移除 AVAudioRecorder、文件 URL、目录创建、录音计时器。
2. 调度和协议：音频仅由非 Codable 的 MeetingAudioPacket 携带；待发送与在途数据总量最多 60 秒。失败暂停采集、清空待发送队列；在途请求结束后释放。没有磁盘重试队列。
3. UI：删除录音文件入口/补转写，显示已采集时长、不保存提示。未配置扩展时拒绝开始采集。
4. 验证：连续分段偏移、最后尾段、真实 AVAudioConverter 的合成 PCM、会议切换隔离、失败清理、背压、重启文字恢复、Pi RPC 合成扩展。

## Pi 音频输入协议 v2

显式加载扩展，仍通过 RPC prompt 调用 `/wf-meeting-audio`：

```json
{"version":2,"audio":"<base64 PCM>","format":"pcm16","sampleRate":16000,"channels":1,"offset":15,"duration":15,"knownSpeakers":["A","B"]}
```

音频数据从管道传输，不出现在进程参数或文件中。Pi 使用 `--no-session`，不保存会话；扩展必须只在内存处理音频，不写请求日志/音频文件，不把 base64 发到文字模型。

旧的 `file` 输入协议已停止使用。扩展须升级为 v2；仅填旧扩展路径并不代表支持新协议。

结果继续沿用文字协议 v1：

```typescript
ctx.ui.notify('WF_MEETING_RESULT ' + JSON.stringify({
  version: 1,
  segments: [{ speaker: 'A', text: '明确的会议发言', start: 0.8 }]
}), 'info');
```

未知说话人省略 `speaker`，显示「未区分」。`start` 是分段内偏移。`knownSpeakers` 不是声纹模型，不保证跨段身份一致。

## 存量与失败策略

- 旧 meetings.json 可以读取；旧 audio 字段仅作兼容元数据，新采集不往其中写音频。
- 不自动删除已有 meeting-audio 文件，避免把“不保存新录音”扩大成“删除历史文件”。历史录音如需删除应另行授权。
- 停止采集后等待已经提交的转写结束，再允许继续，避免错把上轮失败作用到新录音。
- 转写失败后没有“补转写”：释放的音频不可恢复。已有文字/纪要保留，可继续手动记录。
- 不保证第三方扩展/模型服务端不保存数据；本轮保证的是 WorkFollow 新录音不落盘和 Pi 不保存该 RPC 会话。

## 后续独立阶段

Pi 常驻音频扩展 → Qwen WebSocket → partial/final 事件；纪要只消费 final。该阶段还需验证麦克风实机连续采集、模型鉴权、两人交替发言、跨段标签一致性以及真实网络故障。

## 验收结果

- 最新代码 `build-for-testing` 成功，13 项 XCTest 全部通过，无跳过。
- 7 项原有 Store/协议测试，5 项内存音频测试，1 项真实安装 Pi + 合成扩展 RPC 集成测试。包含原生 AVAudioConverter 的 48 kHz 双声道 → 16 kHz mono PCM 转换。
- 隔离构建 `/private/tmp/wf-meeting-memory-build`，隔离数据 `/private/tmp/wf-meeting-memory-data`。实机新建会议、未配置扩展点击开始录音明确拒绝、配置合成扩展后启动麦克风、暂停、继续、再次暂停均验证。
- 累计实机采集 58 秒。合成扩展只验证非空 PCM/v2 参数，返回空对话，不调用模型、不联网、不写音频。最终清除了隔离数据中的合成扩展配置。
- 实机数据目录仅有 `modules/meetings.json`；`audio` 数组为空，采集时长正常保存。没有录音文件/录音目录。生产数据未变更，已有历史录音未删除。
- Qwen 实时转写、两人讲话人区分与跨段稳定性**未验收**；不把合成音频/合成扩展当作 ASR 通过证据。
