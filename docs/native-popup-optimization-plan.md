# Native 弹框优化执行计划

基线：2026-10-01；同分支 `experiment/macos-native`。依据 `native-popup-architecture-audit.md`，不扩大到业务迁移。

## 施工约束

- 每笔1～3个微契约，先测试再换入口，完成后独立提交并推送。
- 保留Domain、Draft、已验证几何；不是全部换成Overlay，也不是全部固定一个尺寸。
- 共享契约/几何/输入路由，业务Session自己管理数据；采用审计中的A～F六类策略。
- 自动测试与实机验收分别记录，未验收不得宣称全部闭环。每笔留入口清单和证据，避免后续页面重构丢掉修复。
- 新增/迁移属性行执行 [交互几何规范 GEO-001～003](native-interaction-geometry-contract.md)，同时验收宿主定位与控件内部列位置；不得为展开/hover改动内边距造成文字移动。

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
- 阶段1补充：日期Adapter显式捕获presenter window并传给共享Escape Router；不依赖系统Popover的`parent`关系。新增无parent的浮层向明确presenter路由、无关窗口不消费、隐藏后不消费测试。保留隐藏窗口退让规则。
- 实机诊断：最新构建的Escape事件属于主窗口，日期`_NSPopoverWindow`在事件monitor执行时已经`isVisible=false`，不是nil event，也不是系统modal抢键。该证据符合电脑控制激活主窗口导致transient面板先隐藏的路径；仍不能据此声称真人键盘路径通过。自动NSPopover层级关闭测试通过，`DATE-GAP-ESCAPE-REAL-WINDOW`继续保留；不让隐藏面板吞键来适配自动化。
- 阶段2第一批：Focus时长浮层移除TimerPane局部点击mask，改用实际浮层bounds与所属窗口观察鼠标事件。outside取消草稿、原事件透传；其他窗口不关闭；挂载/卸载清理监听。保持232×104与数字下方12pt，不改计时Domain。`FocusDurationOutsideClickTests`五项和`FocusDurationPopoverRenderTests`通过。
- 阶段2实机：退出旧进程后启动本轮构建，打开25:00、将草稿改为60、点击右Overview空白，浮层消失、时间仍25:00；浮层数字下方位置未变。InspectorFooter viewport尚未处理。
- 阶段3～6：未开始。不把计划当成完成记录。

## 日期子卡片合同纠偏（2026-10-01）

用户补充的两张滴答截图明确：时间选项卡片覆盖主面板后续属性，并伸出主卡片底边；不是主面板ScrollView内部展开。此前内部展开的验收合同作废，不能以frame稳定证明产品模型正确。

- 主卡片260pt宽、标准506pt高（与参考图520×1012像素的比例一致；不直接用像素作pt）；日历、全部属性行、清除/确定一直保留。
- 子卡片复用`AnchoredPropertyPanel`呈现Adapter，独立NSPanel，显式parent window和属性行anchor；不参与主卡片fittingSize。无箭头，优先行下方，屏幕底部不足才向上避让。
- 时间、结束时间、提醒、重复、重复结束只允许一个子层。子层仅改Date Draft；提醒内部取消/确定保留自己的临时草稿边界。关闭主面板时收起子层。
- 实机本轮新构建：顶部Inspector日期入口，时间子卡片覆盖下方属性并越过父卡片底边；选择12:00关闭子卡片、父面板时间变12:00，尚未提交Task。自动回归结果在完成后登记。
- 最终回归69项通过；覆盖父框/日历/Footer frame不变、真实childWindow行下方锚定/边缘翻转/越过父框、提醒子Draft、原子提交、子Escape先关闭、外点事件透传、父NSPopover将关闭时卸载子窗口与监听。子卡片宽252pt（每侧内收4pt），时间列表280pt高。可编辑子窗口key能力与父environment传递已纳入最终构建。
- 本轮后续Mac锁屏，提醒/重复最终鼠标链未复核；时间的结构与点击选择已实测。之前真人Escape缺口也不因自动测试通过而自动关闭。

## 日期属性行与重复结束补充验收（2026-10-01）

- GEO-BUG-001：重新构建并退出旧进程后，实际时间行点击前后截图未见原8pt右移；不据此宣布所有入口通过。
- GEO-BUG-002：截图复现重复结束第四行导致Footer裁切。修复为普通506pt、重复536pt，时间段按额外行增高；子卡片打开不参与该高度算法。Footer独立且可用屏幕不足时仅属性区滚动。
- 重复结束菜单：永不结束/按日期结束/按次数结束；日期卡片使用农历月历、隐藏今天按钮、早于安排日期的日子禁用，选择即更新外层Draft并关闭；次数卡片含数字输入/Stepper/取消/确定。日期卡片优先锚定行上方。
- 60项回归通过；真实窗口事件测试覆盖从不重复选择每天的增高、原顶边和日历不变、次数确认只改Draft、上方日历不改变主框。窗口测试截图目录：`/tmp/workfollow-schedule-panel-renders/`，包含`repeat-footer-visible.png`、`repeat-ending-options.png`、`repeat-ending-count.png`、`repeat-ending-date.png`。
- 最新App截图已复核重复主面板按钮完整、结束菜单出现。电脑控制对独立子NSPanel的点击定位未完成完整链，因此日期/次数后续证据为自动真实窗口测试与渲染截图，不声称真人链全部通过。
