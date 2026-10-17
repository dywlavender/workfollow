# 会议实时转写实施计划

目标：在 `experiment/macos-native` 实现持续输入、持续显示和可靠收尾；会议纪要由独立文字模型按按钮生成。

## 实施步骤

1. **模型配置拆分**：新增转写模型与纪要模型字段。读取旧单模型配置时，内置 HTTP ASR 迁移为同 provider 的 `qwen-audio-3.1-asr-flash-streaming`；纪要默认使用 Pi 当前文字模型。自定义扩展保留其旧模型。显式选择 HTTP 转写仍可使用。
2. **Pi 实时 ASR 适配**：增加 `/api-ws/v1/inference`、`run-task`、二进制 PCM、`result-generated` 与 `finish-task`/`task-finished`。保留既有 Omni 协议，修正 Qwen ASR `.text` 中间事件。鉴权和网络连接继续由 Pi 管理。
3. **Native 接线与界面**：常驻 Pi 进程使用转写模型，纪要请求使用独立模型。复用 250ms 采集和草稿原位修正。设置展示两个模型；停止后明确显示尾段转写状态。补回生成/更新纪要按钮，纪要只消费定稿。
4. **可运行配置与验收**：确认 Pi 注册了 Streaming 模型，执行 Node 协议测试、本机 Pi RPC 集成与会议 XCTest，构建新 App；通过 Pi 上传虚构合成音按实际速度验证服务中间结果和尾句。

## 验收标准

- 语音尚未结束时出现中间文字；同一句修正不产生重复行。
- 开始到停止复用同一音频连接；HTTP 不参与默认实时路径。
- 完整 PCM、停止尾段和最终结果对应原会议；草稿不持久化、不进入纪要。
- ASR 模型与纪要模型分别传给 Pi；旧会议数据可读取。
- 服务失败明确显示；不把连接 ACK 当作转写完成。
- 记录实际首条非空中间结果耗时、输入时长、最终文字和停止耗时。

真人麦克风到屏幕的 20～30 分钟现场测试单独记录，合成音和协议测试不代替它。首字约 1 秒是体验目标，实际服务结果决定是否达到。

## 范围

2026-10-13 用户试录后调整方案：保存麦克风原始录音和转写输入 WAV，供回放与复测；转写故障不停止本地录音。详见 [本地录音方案](meeting-local-recording-2026-10-13.md)。当前实时模型不提供讲话人分离，界面显示“未区分”；自动纪要继续关闭。

### 实际样本反馈后的下一阶段

已用“新会议123”做三组服务对照，见 [实际样本复测](meeting-recording-diagnostics-2026-10-13.md)。这次语义断句没有明显改善，文件转写返回了讲话人编号但没有包含实时稿中的部分内容，不能直接替换原稿。

1. 增加麦克风/系统声音来源选择，分别保存，解决播放音视频仍经麦克风采集的问题；来源标签与真人身份区分。
2. 对曾有非空草稿、最终变为空的片段，保留待核对标记和本地回放入口；草稿不能直接进入纪要。
3. 保留实时文字，录音结束后生成完整文件转写候选，支持对照、选择采用和讲话人改名/合并；采用候选后纪要基于所选文字重新生成。
4. 用带正确原文及讲话人标注的样本检验内容和归属，避免只凭返回编号宣布分离成功。
5. 单独接入长会议：当前整段 Flash 接口只支持 5 分钟，长文件模型的提交方式及全局身份需另行实现，不能把短片段编号直接拼接。

## 依据

- [模型能力及选型](https://help.aliyun.com/zh/model-studio/asr-model)
- [Streaming WebSocket](https://help.aliyun.com/zh/model-studio/qwen-audio-asr-streaming-websocket-api)
- [客户端事件](https://help.aliyun.com/zh/model-studio/qwen-audio-asr-streaming-client-events)
- [服务端事件](https://help.aliyun.com/zh/model-studio/qwen-audio-asr-streaming-server-events)

## 执行状态

- [x] 模型配置拆分及兼容
- [x] Pi Streaming 协议适配
- [x] Native 接线和界面
- [x] 构建及自动化验收：含本地录音后共 30 项 Node、60 项会议 XCTest
- [x] 实际服务合成音测试：实时性通过，严格文本比对未通过，见验收记录
- [ ] 真人长会议验收
- [x] 实际音视频播放样本对照：静音断句、语义断句、完整文件讲话人分离
- [ ] 系统声音采集与完整转写候选接入
- [ ] 带参考标注的内容准确率和讲话人归属验收

本机已在现有 `ali-Pi` provider 登记 Streaming 模型。其他机器可运行：

```sh
node macos-native/scripts/register-meeting-asr.mjs --provider <百炼provider名称> --apply
```

[验收记录](meeting-realtime-acceptance-2026-10-13.md)
