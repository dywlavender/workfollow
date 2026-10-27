# 会议纪要手动与定时编写

## 行为

- “AI 编写纪要”按钮固定在“滚动纪要”标题右侧。有已定稿对话即可触发，已生成过的内容也可重新编写。没有定稿时按钮仍然显示，处于禁用状态。
- 开始录音后，每 5 分钟自动编写正在录音会议的纪要；切换页面或查看其他会议不改变该目标。暂停录音后取消后续定时任务，历史会议通过按钮手动编写。
- 每次提交截至触发时的全部已定稿对话，重新生成完整纪要。草稿不参与；请求期间新产生的定稿留给下一次生成。
- 手动和自动使用同一个生成状态。开始请求立即禁用按钮，显示“AI 编写中…”并取消定时订阅；忙碌期间的重复点击和定时事件均不排队。
- 请求完成或失败后恢复按钮。若仍在录音，从此时重新计时 5 分钟，避免手动编写刚结束就补跑自动任务。失败保留已有纪要，显示错误，允许重试。
- 保留正文编辑功能及自动替换保护：直接编辑正文暂停自动编写；生成期间编辑正文时，迟到的 AI 输出不会覆盖这些修改。再次点击 AI 编写，根据全部对话重新编写，成功后恢复自动编写。

## 实现

`MeetingStore` 管理录音会议对应的单次定时订阅，间隔为 300 秒；两种入口统一进入 `generateMinutes`，不保留待执行队列。全量对话快照与原会议绑定，生成成功后替换纪要和已覆盖对话 ID，避免重复追加覆盖标记。

会议提示词和随应用打包的 `meeting-minutes` 规则同步改为全量重新编写。旧纪要不作为本次生成的事实来源。

## 验证范围

使用虚拟时钟检查完整的五分钟间隔，不依赖真实等待；通过受控异步响应模拟跨过定时点的长请求，验证双向互斥、完成后的重新计时、录音停止、切换会议、编辑和失败重试。

模型请求测试使用本地模拟响应。

Xcode 构建成功；31 项 XCTest（含 6 项新增调度测试）和 16 项 Node 测试全部通过，无跳过。

```sh
MEETING_PI_INTEGRATION=1 WORKFOLLOW_DERIVED_DATA=/private/tmp/wf-meeting-minutes-20261026-build WORKFOLLOW_DISABLE_SWIFT_SANDBOX=1 macos-native/scripts/run-tests.sh MeetingMinutesSchedulingTests MeetingStoreTests MeetingStreamingTests MeetingModelConfigurationTests MeetingPiBridgeIntegrationTests MeetingPiOwnershipTests
node --test macos-native/scripts/tests/meeting-persistent.test.mjs macos-native/scripts/tests/meeting-pi-audio.test.mjs
```

本机构建：`/private/tmp/wf-meeting-minutes-20261026-build/Build/Products/Debug/WorkFollow.app`。

## 日用版入口复查

用户反馈构建 31 找不到按钮。窗口截图确认原按钮位于纪要栏底部，现移到标题右侧。

新增原生窗口交互检查覆盖 1280×800 的左右布局和 900×600 的上下布局：按钮位于可见区域上半部；无定稿时不能发起请求；有定稿时点击会生成；忙碌期间再次点击不会增加请求；完成后恢复可用。与中文日期快速创建及既有日程回归合计 82 项 XCTest 全部通过，无跳过。窗口测试使用受控模型响应，不代表线上模型服务可用性或生成质量验收。

日志：`/private/tmp/workfollow-date-and-minutes-final-tests.log`。
