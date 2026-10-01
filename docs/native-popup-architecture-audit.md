# Native 弹框架构审计与统一契约

日期：2026-10-01。范围：`experiment/macos-native` 当前本地代码。

## 结论与证据边界

问题不是“缺少所有中间层”，而是已有定位、状态、草稿、键盘路由没有形成跨入口契约。局部修复沉淀在不同 View 中，重构时确实容易丢失。

本次为代码与既有测试审计，不是全部弹框的实机验收。下文“已确认”指源码路径与结构事实；“风险”指可由代码推导、尚未复现实机症状；不把风险当作已发生的 bug。日期容器实机证据沿用本轮 `ticktick-task-surface-parity.md`，不能外推到其他弹框。

不新增正式 Task 属性模型，不重写 Domain，不用一个巨型 Controller 接管全部 UI。不把系统 Menu、确认框、光标命令面板、输入弹框当成同一种东西。

## 入口与宿主清单

以下为本轮逐项检查的主要产品路径；文件选择、Settings、习惯等系统模态路径只完成机制盘点，未逐按钮验收。

| 入口 | 实际宿主 / 状态 / 数据 | 当前约束与差异 |
| --- | --- | --- |
| Inspector Header、列表行、Quick Add、Matrix、TaskQuickComposer 日期 | `TaskDatePopoverV2` + `SchedulePopoverContainer`；通常 `.schedulePopover` | 260×标准560，日历固定、属性内滚动，Draft 确定后提交；已有真实 NSPopover frame 合同 |
| 子任务行日期 | `TaskDateButton`，直接 `.popover` | 复用同一日期内容，但绕过共用呈现修饰符 |
| Inspector 更多属性中的重复 | `TaskAttributesView` → `TaskRecurrenceEditor` → `RecurrenceDraftView` | 另一套 State、320宽、内容定高未约束、独立 `setRecurrence` 提交；不是新日期 Draft |
| Quick Add 属性菜单 → 清单 / 标签 | 系统父 Popover + 行上的子 `.popover` | 父270宽、自适应高；子清单250×300、标签264×320；两个独立开关；清单选择即更新创建草稿，标签确定才应用 |
| 任务右键 → 清单 / 标签 | `TaskContextMenuPresenter` 的 transient NSPopover + SwiftUI 子 Popover | 光标锚点、父264宽；局部220ms hover延迟；选择即动作或标签确认；父高度随任务菜单项不同 |
| Inspector Footer 更多 / 属性 / 标签 / 关联 / 截止 | Inspector内部 bottomTrailing Overlay | 遮罩仅覆盖 Inspector；用多个 Bool + 日期 enum组合；尺寸208×368、320×300或日期固定容器；无统一窗口安全区定位 |
| Calendar / Matrix 任务编辑与创建 | `PlanningWorkspaceChrome` → `PlanningOverlayLayer` | 页面坐标系、几何纯函数、页面遮罩、固定卡尺寸；锚点随布局更新 |
| Focus 任务选择 / Scope | 系统双层 Popover + `FocusTaskPickerSession` | 主312×460；Scope172宽、高度按清单数量上限420；已有真实双层窗口 Render 测试 |
| Focus 时长 | `FocusDurationEditorSession` + Timer Pane内部Overlay | 232×104，数字锚点、下方优先、边缘夹取；Draft确认；遮罩范围仅左 Pane |
| Focus补记 / 目标 / 节奏 | 系统 `.popover(arrowEdge: .bottom)` +各自 State | 补记330宽、错误文本条件出现；目标190宽；没有统一尺寸或错误区约束 |
| Slash | `NativeTextView` 子 NSPanel + `SlashSession` | 不抢文本焦点、跟随caret、按命令结果有界变高；window内安全区；不应强制冻结位置 |
| 选区工具栏 | `NativeTextView` 非激活子 NSPanel | 以选区定位，执行格式后恢复文本 responder；另一套定位代码 |
| 格式工具栏标题 / 时间 picker | `DocumentFormatToolbarView` 内Overlay | 自有hover桥、位置在toolbar上方、自己装本地Escape monitor |
| 全局 Quick Add | `GlobalQuickAddController` NSPanel | 测量内容后增高，`resizePanel`保留顶边；独立key window；这是一种合法的非固定尺寸策略 |
| 倒数日编辑下拉 | `CountdownEditorView` sheet内anchor Overlay | 已明确避免撑高sheet、使用自己的定位与状态；需保留并接入统一规则 |
| 任务垃圾桶确认 / 笔记垃圾桶确认 | 自绘Overlay / 系统alert | 同为不可逆操作确认，但宿主、焦点和关闭处理不同；不能仅凭API清单就机械替换 |
| 习惯、倒数日、模板、命令面板、设置导入 | sheet / confirmationDialog | 允许模态；应明确parent window、Draft取消、焦点恢复；本轮未完成完整行为审计 |
| 链接 / 附件 / 保存与错误提示 | `NSAlert.runModal` / NSOpenPanel等 | 系统模态独立策略；不要迁到普通属性Overlay中 |

## 风险清单与修复顺序

### POP-001 / P1：键盘事件归属不够严格

- 已确认：`Features/Editor/DocumentSelectionToolbar.swift:211` 中 `DocumentFormatToolbarView` 的 monitor 只检查Escape，没有检查event.window、editor identity、是否为最上层。
- 已确认：`ScheduleEscapeRouter.swift:23` 接受window为nil、event.window为nil及任意当前keyWindow的事件；注释的“仅此面板窗口”比实际守卫严格。
- 风险：弹框共存、系统链接/附件面板打开时，后台picker先消费Escape；多个monitor的注册顺序代替了明确关闭顺序。尚未实机复现。
- 修复目标：建立window-scoped输入路由，最深active child先处理；后台、失效、不可见owner不得吞键。只迁这两个入口，先做归属测试，不全局重写键盘。
- 验收：日期展开→首个Esc仅收起、第二个关闭；编辑picker→先关picker；系统模态打开时后台monitor不消费Escape。继续保留已记录的真实日期Escape缺口。

### POP-002 / P1：自绘遮罩的范围与“点击外部”产品语义不一致

- 已确认：`FocusTimerPane.swift:39` 把duration presenter挂在左Pane，`FocusDurationPopover.swift:153` 的遮罩只取该宿主GeometryReader尺寸。
- 已确认：`TaskInspectorShell.swift:59` 的Footer遮罩只覆盖Inspector，不包括列表；日期Header与Footer属于不同呈现路径。
- 风险：右Overview点击不关闭时长层；左列表点击可穿透Footer遮罩。任务选择切换已有清理（Shell:80），但不能覆盖所有外部点击。
- 修复目标：每个弹框声明outsideScope（workspace/window/editor）、以及consume或passThrough。提升遮罩宿主而不是再给右侧增加一个零散tap回调。
- 验收：点击所属范围内任意外部点按统一规则关闭；是否同时选中下方任务必须写清，不默认为所有外部点击都吞掉。

### POP-003 / P1：布局约束仍由各View临时决定

- 已确认：Focus补记 `FocusOverviewPane.swift:260` 条件错误提示参与VStack，外层:280只有宽度；Inspector Footer固定bottomTrailing卡未采用安全区几何；格式picker `DocumentSelectionToolbar.swift:249` 固定画在toolbar上方，没有纵向边缘翻转。
- 风险：错误出现导致系统Popover调整位置；中/窄Inspector或Planning浮动Inspector中Footer卡超出viewport；上边缘picker被裁切。未实机确认每个路径。
- 修复目标：声明尺寸策略和边缘策略；补记预留错误区或固定有界viewport；Footer采用可视viewport定位、内部滚动或指定窄屏替代呈现；格式picker做纵向避让。
- 验收：错误出现/消失宿主位置不变；Planning的400×356编辑宿主里Footer可达；标题picker贴上边缘不被裁。不能通过单纯加`.clipped()`让按钮不可达。

### POP-004 / P1：重复属性存在两套活跃编辑路径

- 已确认：`TaskAttributesView.swift:13`仍调用旧`TaskRecurrenceEditor`；`TaskDatePopover.swift:62`有独立frequency/interval/ending/count等State，:120调用`workspace.setRecurrence`。主日期路径使用`TaskDateDraftModel`和原子Timing提交。
- 风险：规则扩展、提醒联动、取消语义、展示文案与尺寸只修一边；不能仅因最终都调用Application就视为已统一。尚未证实当前存在数据丢失。
- 修复目标：复用同一编辑Session/Draft/校验与计划生成；可以保留独立Repeat入口，但明确它确认的是独立事务，不自动提交外层日期草稿。验证复杂现存规则打开再确认是否完整保留。
- 验收：同一任务分别从主日期/更多属性打开，初值一致；取消不写入；确认只改变声明字段；定时/提醒原值不被无意重置。

### POP-005 / P2：二级菜单生命周期与互斥缺少统一所有者

- 已确认：`QuickAddPropertiesPopover.swift:20`、`TaskContextMenuPopover.swift:9`以两个Bool管理同级子层；Context hover task没有对应onDisappear取消（仅下一次hover取消）。InspectorFooter也是多Bool，以if/else优先级选择显示。
- 风险：状态可同时为true、延迟回调落在已关闭owner、隐藏子状态重新冒出。不能仅凭Bool认定已经发生双窗口。
- 修复目标：每个父Session一个activeChild enum；parent关闭、target切换、view消失时取消延迟任务，关闭后focus返还有效owner；父子层可同时存在，不用一个全应用enum排斥合法嵌套。
- 验收：清单→标签只留标签子层；子Esc不关父；父关闭所有子层与hover任务失效；重新打开无旧query/selection，除非合同明确保留。

### POP-006 / P2：呈现包装与几何度量分散

- 已确认：子任务日期直接`.popover`；TaskList/Matrix/Composer走schedule modifier。FocusDuration面板尺寸在内容与presenter重复写；Planning已有可复用几何函数，其他模块仍手写。
- 修复目标：接入分类Adapter与共享Geometry，而非用一个PopoverModifier包所有内容。尺寸单一来源，实际所属window/viewport作为可用区域，不笼统取NSScreen.main。
- 日程目前开场高度取NSScreen.main，已解决展开跳动，但不能算跨屏/浮动Inspector宿主适配完整。

### POP-007 / P2：确认框合同和文档漂移

- 已确认：任务垃圾桶自绘Overlay，笔记垃圾桶系统alert。旧API盘点建议换系统确认框，但该文档也明确“未实测”。Schedule modifier注释仍称时间/提醒子浮层统一走modifier，与当前inline实现不符。
- 修复目标：危险操作走同一确认语义合同（owner、焦点、取消、单次确认），可按视觉产品要求选系统或自绘Adapter；文档标明适用范围、被替代合同，避免历史建议成为盲目替换依据。

## 统一规则：六类策略，而不是六套产品代码

| 策略 | 适用 | 尺寸与锚点 | 输入与提交 |
| --- | --- | --- | --- |
| A 固定工作面板 | 日期、标签、多选属性 | 开场确定有界外框；状态变化不重新定位，内容内滚动 | 自有Draft；取消丢弃；Confirm一次提交 |
| B 分级选择菜单 | 清单、Scope、优先级、Context子菜单 | 父frame不因child变化；child按行锚定、边缘翻转；子高度有上限 | 父子Session；通常选择即应用，标签确认类可选A语义；Esc先子后父 |
| C 页面/Workspace编辑卡 | Matrix/Calendar编辑、新建、Footer、时长 | viewport安全边距；跟随有效锚点；内部状态不推动宿主；遮罩范围显式 | 明确即时保存或Draft，不假定所有编辑器都取消回滚；focus归属同window |
| D 文本辅助层 | Slash、选区、格式picker、tooltip | caret/selection/控件锚点；允许按结果有界增高和跟随，不抢编辑器焦点 | 命令由editor处理；输入法期间不抢键；tooltip不进入modal/Escape栈 |
| E 独立输入面板 | 全局Quick Add | 允许测量增高，明确保留top edge；限定min/max，超出内滚动 | 可成为key；创建成功才关；取消保留或丢弃Draft按Session声明 |
| F 模态确认/系统工具 | 垃圾桶、导入、附件、链接、sheet | 指定owner window；系统适配或有界自绘；不是属性子菜单 | modal优先；后台不消费键；取消不执行危险动作，confirm只执行一次 |

每个入口必须声明：policy、owner/target、anchorSpace、sizePolicy、placement、outsideScope、outsideEventDisposition、focusPolicy、dismissPolicy、commitPolicy。不是给每个入口复制一份实现。

## 推荐共享层边界（待实现，不伪装成已有架构）

1. **PopupContract**：上述声明及稳定contract ID；业务View只选择策略。定义在Shared/Presentation，不能依赖Task Domain。
2. **PopupGeometry**：复用/提取`WFOverlayGeometryMath`；统一下方优先、翻转、安全区和bounded size。不把尺寸固定成一个全局360×600。
3. **PopupSession**：按window/owner管理target、activeChild、focusReturnTarget、关闭原因、延迟工作的取消。数据Draft仍由业务Session所有，不塞入全局Coordinator。
4. **PopupInputRouter**：决定topmost可处理层；由SwiftUI/AppKit Adapter转交，避免多个无归属monitor竞争。系统modal拥有输入时业务路由退让。
5. **三种Adapter**：系统Popover、同窗Overlay、AppKit辅助Panel；同一合同，不要求同一宿主。系统alert/sheet保留对应系统路径。
6. **业务提交**：Schedule/Tag/Duration等生成结果再调用Application；即时菜单动作直接调用Application。子Confirm可以只更新父Draft，不能偷用bulk API。

关闭原因明确区分confirm/cancel/Escape/outside/targetChanged/ownerGone；前者提交成功后关闭，其他按事务策略处理；恢复焦点前验证owner仍存在。不能用onDisappear兜底提交。

## 修复资产如何保住

本次复跑 `ScheduleContainerRenderTests`、`FocusDurationPopoverRenderTests`、`FocusTaskPickerInteractionTests`、`PlanningOverlayGeometryTests`、`TaskInspectorPresentationTests` 通过。它们是迁移基线，不代表上文未覆盖的跨窗口/外部点击路径已通过。

- 原有`ScheduleContainerRenderTests`、FocusDuration/Picker、Planning几何与Slash Session合同先保留，不能“抽象后重写测试”把原断言删掉。
- 建立入口→策略→已有合同测试→待验收的映射。迁移一个入口，先补其缺失合同，再换Adapter；每次1～3个微契约。
- 必须测试真实宿主的状态转换：打开→展开/出错→切换子层→关闭；记录anchor与window frame，不只测试Metrics或分别渲染静态state。
- 正常日程验证frame不变；Slash与全局Quick Add验证有界增长及保留边缘。不能统一写“任何弹框frame不变”的错误测试。
- 重点验收4条跨组件链：Inspector更多→属性→Repeat；Quick Add属性→标签→取消；Planning编辑→日期/格式→Esc；Focus时长→右Overview点击。
- 实机未完成的项明确保持未验收；跨入口测试通过不能替代人工hover和系统responder验证。

## 建议提交序列

逐阶段执行与验收进度见 [弹框优化执行计划](native-popup-optimization-plan.md)。审计中的发现保留为历史基线，不因为共享层已开始落地而把所有风险自动标为解决。

1. POP-001：window-scoped Escape归属及topmost合同，只迁格式picker和日期Router。
2. POP-002/003：workspace遮罩与viewport几何，只迁Focus时长和InspectorFooter，不改变Focus计时或Task业务。
3. POP-004：统一Repeat编辑Session，保留两个入口各自提交边界。
4. POP-005：Quick Add/Context activeChild与hover取消生命周期。
5. POP-006/007：逐入口Adapter收敛、确认语义和过期注释清理。

本次仅审计与制定合同，未实施上述序列。没有源码证据证明全项目需要整体推翻，也不将“所有弹框都有跳动”作为已验证结论。
