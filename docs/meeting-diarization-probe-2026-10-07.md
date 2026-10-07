# 新模型讲话人区分 · Pi 实际服务探测

## 结论

会议设置和 Pi 注册表均已配置 `qwen-audio-3.1-asr-flash`。通过 Pi 扩展调用 HTTP 转写，开启 `speaker_diarization_enabled` 后，模型实际返回文字、时间戳和讲话人编号。两个合成双声样本在各自请求内正确识别重复讲话的同一声音。

但当前 App 使用 WebSocket realtime，直接换这个模型的连接探测返回“Pi 音频连接提前关闭”。本轮仅新增测试适配，未修改生产音频链路，不能宣布 App 已支持这个模型或整场会议讲话人识别。

## 实测结果

语音由 macOS Tingting / Eddy 合成，仅虚构的项目交付讨论。29.094375 秒音频在内存中封装 WAV，未保存音频文件。音频与凭据交互全部发生在 Pi 扩展，Native 未直接连接模型；Pi 使用 no-session 模式。

| 请求 | 预期声音顺序 | 服务端编号 | 处理耗时 | 内容校验 |
|---|---|---|---|---|
| 正序 | A → B → A → B | 0 → 1 → 0 → 1 | 1725ms | 通过 |
| 倒序独立请求 | B → A → B → A | 0 → 1 → 0 → 1 | 1825ms | 通过 |

内容校验忽略标点、空白及中文数字与阿拉伯数字表示差异，不忽略词语差异。声音归属根据合成输入的时间范围与服务端句子时间范围重叠核对，而不是用转写文字猜说话人。

第二个请求说明：相同声音 A 在第一请求为 0，第二请求为 1。因此这些编号仅表示请求内身份，不能直接作为跨请求的会议全局身份。

处理耗时从提交完整 HTTP 请求开始，不包含先采集完 29 秒音频所需的等待；不是麦克风首字实时延迟。

原始文字结果：[正序 JSON](meeting-diarization-probe-2026-10-07.json)、[倒序 JSON](meeting-diarization-reverse-probe-2026-10-07.json)。均不包含音频数据或凭据。

## 接口限制与后续接入

[官方 HTTP API](https://help.aliyun.com/zh/model-studio/fun-asr-flash-recorded-speech-recognition-http-api) 明确：通过 `speaker_diarization_enabled=true` 开启讲话人分离，读取 `output.sentences[].speaker_id`。该接口输入完整音频；SSE 中间结果仅在音频不少于 1 分钟时分多次返回，不能当成当前持续 PCM 输入的 WebSocket 协议。

建议保留实时文字链路，再通过 Pi 内 HTTP 适配延后修正讲话人；或者明确接受完整片段输入的延迟。两者都需要跨请求身份对齐，不应直接拼接 speaker_id。适配完成后才能进行真人录音和 App 界面流程验收。

本轮没有验证多人重叠讲话、真人声音、长会议或跨请求声纹匹配。测试脚本语法检查及 git diff --check 通过。新增实验文件未提交、未推送。

## 复现

```sh
WF_MEETING_MODEL=qwen-audio-3.1-asr-flash node macos-native/scripts/accept-meeting-diarization.mjs docs/meeting-diarization-probe-2026-10-07.json
WF_MEETING_MODEL=qwen-audio-3.1-asr-flash node macos-native/scripts/accept-meeting-diarization.mjs docs/meeting-diarization-reverse-probe-2026-10-07.json --reverse
```
