# 快速新建的中文日期保存

## 问题与原因

用户在任务列表上方输入“明天下午3点开会”，识别提示有日期，回车后生成的“开会”任务却没有日期。中文日期由本地 `QuickAddParser` 规则解析，不调用 AI。

可复现路径是：快速添加草稿保留了手动选择的“无日期”，后续输入被解析出日期，但创建仍优先使用旧日程草稿，导致提示和实际保存不一致。

## 修复

当输入中的日期、时间或重复描述发生变化时，清除旧日程覆盖值，以新识别结果为准。仅修改普通标题文字不会清除手动选好的日期。恢复已保存草稿时保留原日程选择。列表和全局新建入口采用同一判断规则。

## 验证

原生窗口测试覆盖全部任务、收集箱、已有“无日期”草稿，以及恢复手选日期后仅修改标题。使用“明天下午3点开会”触发真实回车事件，验证任务日期与时间，并从 SQLite 重新读取确认保存结果。原有日期面板的两级提醒、重新打开和一次撤销检查继续通过。

相关 82 项 XCTest 全部通过，无跳过，日志位于 `/private/tmp/workfollow-date-and-minutes-final-tests.log`。未修改用户已有的任务记录。

## 2026-10-27：后续安装包未包含修复

用户再次反馈问题后，检查发现日用版已变为构建 33。它保留了快速添加解析器，但缺少构建 32 中的 `scheduleTextChanged`、`scheduleSourceText`，会议纪要顶部按钮对应的类型也缺失。因此不能仅依据构建号递增认定修复仍然存在。

已从当前工作区重新构建 34，并验证其中包含日期修复和会议纪要顶部按钮，完整签名检查通过。安装包位于 `/private/tmp/workfollow-quick-date-20261027-release/WorkFollow.app`，核对记录位于 `/private/tmp/workfollow-quick-date-20261027-package-verification.json`。构建日志独立保存为 `/private/tmp/workfollow-quick-date-20261027-build.log`，避免不同任务覆盖同一份日志。

用户明确批准后，27 项解析/日程测试及 2 项原生窗口测试全部通过。窗口测试覆盖中文日期回车创建、数据库重读、恢复草稿和手选日程提醒。构建 34 已安装至 `/Applications/WorkFollow.app` 并启动，CLI 正常响应；安装后的主程序与已批准安装包逐字节相同，确认日期修复和顶部纪要按钮仍在。旧版 33 与本地数据备份位于 `~/Library/Application Support/WorkFollowNativeUpdates/deploy-20261027-build34/`。

窗口测试日志：`/private/tmp/workfollow-quick-date-20261027-window-tests.log`；安装核对记录：`/private/tmp/workfollow-quick-date-20261027-installed-verification.json`。
