# Native 弹框优化执行计划

基线：2026-10-01；同分支 `experiment/macos-native`。依据 `native-popup-architecture-audit.md`，不扩大到业务迁移。

## 施工约束

- 每笔1～3个微契约，先测试再换入口，完成后独立提交并推送。
- 保留Domain、Draft、已验证几何；不是全部换成Overlay，也不是全部固定一个尺寸。
- 共享契约/几何/输入路由，业务Session自己管理数据；采用审计中的A～F六类策略。
- 自动测试与实机验收分别记录，未验收不得宣称全部闭环。每笔留入口清单和证据，避免后续页面重构丢掉修复。

## 分阶段交付

| 阶段 | 微契约 / 范围 | 验收 | 禁止同时改 |
| --- | --- | --- | --- |
| 1 输入归属 | POP-001；共享window-scoped Escape；先接日期Router、格式picker | 无owner不吞键、不同窗口不吞键、系统modal不被后台抢键、同窗只最深层消费；保留日程先收起后关闭测试 | 格式命令、日程数据、布局 |
| 2 外部点击 / viewport | POP-002/003；先Focus时长、InspectorFooter | Overview外点关闭；声明点穿透规则；中窄/Planning宿主内按钮可达；菜单展示不推动原内容 | Focus计时/统计、TaskActions |
| 3 Repeat同源 | POP-004；主日期和更多属性Repeat共享编辑逻辑 | 初值同源、取消无写入、复杂规则往返不丢；独立入口只提交自己声明的字段 | 全新重复类型、提醒Domain |
| 4 子菜单生命周期 | POP-005；Quick Add/Context | 同级互斥、子Esc保留父、parent消失取消hover任务、重开无幽灵状态 | Parser、创建、排序 |
| 5 呈现Adapter收敛 | POP-006；统一尺寸来源/Geometry/入口声明 | 日期子行同合同；上下边缘格式picker可见；开场按实际宿主可用区；保留Slash跟caret、Quick Add顶边增长 | 全局外观、系统模态替换 |
| 6 模态 / 回归冻结 | POP-007；垃圾桶确认合同、文档同步、入口回归矩阵 | Cancel无危险动作，Confirm一次；owner焦点恢复；四条跨模块链验收并登记 | Trash数据语义、批量删除操作 |

阶段2～6开始前重新核对代码；不以当前风险推测替代真实复现。复杂阶段仍拆小提交，不把整个阶段塞进一次重构。

## 测试与手工矩阵

- 保留ScheduleContainer/Expanded/Atomic、FocusDuration/Picker、PlanningGeometry、InspectorPresentation、SlashSession既有断言。
- 共享层测试：窗口归属、active child、dismiss reason、边缘避让、owner移除后清理。
- Adapter测试：NSWindow + 实际Popover/Overlay/Panel，验证状态变化后真实frame与focus。
- 必测链：Inspector更多→Repeat；Quick Add属性→Tags取消；Planning编辑→日期/格式→Esc；Focus时长→右Overview点击。
- 窗口档位选当前支持的宽/窄与Planning浮动宿主；不穷举不相关边界。

## 执行记录

- 审计完成并在远端；现有五组基线合同通过。
- 阶段1：第一批 **IMPLEMENTED / PARTIALLY VERIFIED**。新增`PopupEscapeRegistry`（单一monitor，window归属、显式depth、同depth最近注册优先）和`PopupEscapeRouter`；日期Router与格式picker接入，移除旧无窗口归属monitor和日期任意keyWindow兜底。无宿主/不可见owner/其他窗口/系统modal期间不消费；卸载移除registration与monitor。只覆盖已接入的两类，不声称全局所有弹框已入栈。
- 自动验收：`PopupEscapeRoutingTests`、`ScheduleExpandedSectionTests`、`ScheduleContainerRenderTests`、`TaskInspectorPresentationTests`、`DocumentEditorStateTests` 定向通过；覆盖同窗深层优先、不同窗口、隐藏/卸载、系统模态退让；真实NSPopover首Esc收起、第二个关闭的原有测试保留通过。
- 实机：退出旧进程后启动`/tmp/workfollow-native-derived-data/Build/Products/Debug/WorkFollow.app`。格式标题picker首Esc仅关闭子菜单、第二个关闭格式栏，文本无改动。日期展开Repeat后，电脑控制工具的首Esc仍关闭整个Popover，与自动事件路径不同；**未验收通过，不关闭DATE-GAP-ESCAPE-REAL-WINDOW**。
- 阶段1下一笔：确定实机Escape是否在发送前激活owner造成transient关闭，还是原生responder先关闭；再决定是否调整Popover adapter。禁止恢复“任意keyWindow都吞Escape”的兜底来掩盖问题。
- 阶段2～6：未开始。不把计划当成完成记录。
