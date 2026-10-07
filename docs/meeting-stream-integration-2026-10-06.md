# 会议对话流式转写验收

## 实现范围

- Native 每 250 毫秒提交一块内存 PCM，复用同一个 Pi RPC 进程和音频会话。
- WebSocket、模型配置与认证由 Pi 扩展 `wf-meeting-stream.mjs` 管理，Native 不直接连接模型。
- 使用 Qwen 输入音频转写事件，不等待模型生成整段 JSON。增量事件的 `text + stash` 是当前草稿快照；completed 的 transcript 才是定稿。
- 会话模型与 `input_audio_transcription` 的 ASR 子模型都取自会议设置里的「模型标识」（2026-10-06 起不再写死 `qwen3-asr-flash-realtime`）。
- 草稿覆盖同一条记录，不逐字追加成重复行；草稿不持久化、不参与纪要。定稿替换草稿，保存并参与原有滚动纪要更新。
- 停止录音后等待尾段定稿；中断清理草稿，但保留已定稿文字。切换所选会议不会改变结果归属。
- 音频仅在内存中传递，不保存录音文件。讲话人目前标为“未区分”，没有实现可靠的讲话人区分。
- 自定义旧 Pi 音频扩展仍走原分段协议；默认内置扩展走流式协议。

## 实际服务验收

使用最新构建 App 内的扩展，通过已安装 Pi 将两种合成声音的虚构内容按实时速度发送。没有上传真实会议录音。

证据：`meeting-stream-bundled-2026-10-06.json`。

- 输入时长：10.335125 秒。
- 首条草稿：会话建立后 489 毫秒；不包含连接准备时间，也不是 UI 绘制延迟测量。
- 定稿：今天讨论项目交付，确认下周一提交。同意，预算两千五百元，我负责校对。
- 草稿在输入结束前出现、最终文本与样本一致、停止正常完成。
- 2026-10-06 改为「模型由会议设置决定」后重跑：会话模型与 `input_audio_transcription` 都取自设置里的 `qwen3.8-omni-flash-realtime`，首条草稿 528 毫秒、定稿仍与样本逐字一致，四项检查全过。同一轮也重跑了分段路径的 `check-meeting-pi.mjs`（含合成测试音与纪要请求），全部成功。

过程中发现并修复两项真实问题：服务端 VAD 已提交音频后再次手动 commit，会触发空缓冲错误；较激进 VAD 参数会丢失短词。最终不重复手动 commit，并将 VAD threshold / prefix padding / silence duration 调整为 0.2 / 500ms / 800ms。此前失败报告保留，不能算作通过证据。

## 自动化验收

- 最新 Native 测试构建成功，24 项测试通过、0 失败。覆盖内存音频、Store、Native ↔ Pi、事件顺序、草稿修正、停止尾段和异常清理。
- Node 协议及相关测试共 16 项通过、0 失败。
- `git diff --check` 通过。

## 未验收范围

未完成真人麦克风到界面的端到端操作验收、长会议稳定性和真实场景识别准确率测试。合成双声测试不证明讲话人区分能力。

`input_audio_transcription` 的 ASR 槽位改用设置里的模型后，**已在真实服务上验证**：会话建立成功（`session.updated` 到达），且 10.34 秒合成双声输入的定稿文字与样本逐字一致。因此 omni 实时模型可以直接填在该槽位，不需要单独的 ASR 模型 id。

最新 App 位于 `/private/tmp/wf-meeting-pi-adapter-build/Build/Products/Debug/WorkFollow.app`。此前已经打开的进程仍需退出并重新打开才能加载新代码；本轮未自动结束用户可能进行中的录音。

本轮代码尚未提交或推送。

协议依据：[Qwen 服务端事件](https://help.aliyun.com/en/model-studio/server-events)、[客户端事件](https://help.aliyun.com/en/model-studio/client-events)。
