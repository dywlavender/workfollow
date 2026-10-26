# 滴答 Mac 小组件实现分析

分析日期：2026-10-24。对象为本机 `/Applications/TickTick.app`，版本 **8.0.80 (492)**。

## 结论

滴答把组件显示、后台动作、导航请求、主应用窗口分别处理。与 WorkFollow 当前问题最相关的是：**新增请求必须先经过主应用的启动与窗口分流，快速新增视图本身无法阻止主窗口出现。**

这次确认了安装包结构、动作声明、部分新增 URL 调用和界面资源。尚未通过真实组件操作确认滴答在“主应用完全退出后点击加号”时的窗口行为，不能将“存在独立快速新增视图”直接等同于“冷启动必定不显示主窗口”。

## 已确认的实现

| 部分 | 安装包事实 | 对用户体验的意义 |
| --- | --- | --- |
| 现代组件 | `TickTick.Widget.Extension.appex` 的扩展点为 `com.apple.widgetkit-extension`；依赖 SwiftUI、WidgetKit | 使用系统桌面组件容器展示内容 |
| 旧组件 | 同时保留 `TickTick.Today.Widget.appex`，扩展点为 `com.apple.widget-extension` | 旧 Today 组件与现代桌面组件需要分别分析 |
| 完成动作 | `CheckTaskIntent(taskID)`、`CheckChecklistItemIntent(itemID)`、`CheckHabitIntent(habitID, dayOff)` 均声明 `openAppWhenRun=false`、`isDiscoverable=false` | 动作不要求打开主应用界面；不能据此断言其实现绝不会唤醒主应用进程 |
| 组件配置 | 任务列表配置包含清单类型、清单、文件夹、标签、智能清单、逾期、仅任务、勾选框、主题、自动深色模式 | 组件承担筛选和展示配置，编辑仍由主应用承接 |
| 共享基础 | 主应用和相关扩展的嵌入权限声明包含相同 App Group；现代组件和主应用共用 TickTickKit、TTCoreDataPod，组件还依赖 CoreData | 具备共同访问数据和复用业务代码的基础；尚未确认完成动作直接写数据库还是通过通信交给主应用 |
| 新增入口相关代码 | 现代组件实际调用 `TTListIdentifier.urlForAddTaskInList`；该 getter 使用 AppestKit 的 `CreateTask`、`List` 和 `AnyGo.URLScheme.privateURL(Action)` | 新增请求携带当前清单上下文，而非只发送通用“打开应用”请求 |
| 快速新增界面 | REA 解码得到独立 `TTQuickAddViewController.nib`，连接日期、优先级、标签、清单、模式、取消、确认动作 | 新增可以复用独立编辑内容，无须加载整个任务主页面 |
| 窗口管理 | 主程序使用自定义 `TickTick.TTApplication` 和 MainMenu；主窗口在独立 `TTMainWindowController.nib`，其中 `NSWindowIsRestorable=false` | 主菜单、主窗口和快速新增内容分离；该字段仅描述这个窗口资源，不能代表应用没有其他恢复逻辑 |

任务列表配置的现代元数据默认开启“显示逾期”和“显示勾选框”，主题为蓝色，自动深色模式开启。清单、文件夹、标签和智能清单支持动态选项。

包内另有七种标记为可用于组件的旧配置定义：任务列表、周视图、月历网格、习惯、四象限、单个倒数日、倒数日列表。这是**配置定义清单**，不代表已实测当前 macOS 组件库一定展示七种组件。

## 新增入口追踪到哪里

已闭合的静态调用片段：

```mermaid
flowchart LR
    W[现代组件调用点] --> L[TTListIdentifier.urlForAddTaskInList]
    L --> A[AppestKit CreateTask 与 List]
    A --> U[AnyGo.URLScheme.privateURL]
    U --> R[返回新增 URL]
```

关键地址均为本机安装包 arm64 切片的静态地址：

- 组件调用点 `0x10000d850` → Objective-C stub `0x1000dd0c0`；选择器槽为 `0x100117208`。
- TickTickKit getter 的 Objective-C 包装入口为 `0x332ac4`，Swift 实现为 `0x332b98`。
- getter 的调用 stub `0x4a7a44` 经动态绑定对应 AppestKit 的 `AnyGo.URLScheme.privateURL(Action)`。
- 现代组件还包含 `SwiftUI.Link(destination:label:)` 的真实初始化调用和 `widgetURL` 引用。尚未完整闭合新增 URL 与全部视图闭包的映射，不将所有 Link 都归为加号。
- 主应用存在 `TTURLSchemeManager.handleWithUrl:`、`AppDelegate.handleGetURLEvent:withReplyEvent:`、`toggleQuickAdd`、`showMainWindowForExternalActivation` 等入口。它们的存在和部分调用已观察到，冷启动的完整条件分支尚未还原。

界面资源还确认：

- Base 与中文 MainMenu 解码分别得到 170、98 个对象，未发现已识别的窗口对象。
- `TTMainWindowController.nib` 含 `TTLegacyMainWindow` 模板，owner 连接窗口，窗口 delegate 指向 owner。
- `TTQuickAddViewController.nib` 含 128 个对象、27 条连接；它描述编辑内容，未包含窗口模板。
- 类元数据中，`TTAddTaskBarWindow` 继承 `NSPanel`；`TTQuickAddPopover` 继承 `NSObject`，不能仅凭名字将其视为 NSPopover。尚未证明组件加号最终使用哪一种承载容器。

## 对 WorkFollow 的具体建议

1. **先稳定启动分流。** 组件新增请求在主窗口自动创建或恢复前标明用途。新增入口只请求快速新增控制器；Dock、Finder 和显式“打开主窗口”继续走正常主窗口入口。
2. **保留独立快速新增。** 继续复用日历新增使用的编辑内容，默认日期与清单由组件上下文决定；保存后刷新组件，取消关闭卡片，已有主页面的选中任务和布局保持原状。
3. **完成与新增继续分开。** 完成动作使用后台 Intent，新增动作负责请求编辑界面。`openAppWhenRun=false` 不能替代主应用的窗口策略。
4. **沿用已验证的本地数据通道。** 滴答的 App Group 声明可作为架构参考；WorkFollow 本地使用场景继续沿用当前共享通道和主应用统一保存机制，避免为对齐外观额外迁移存储。
5. **配置后置。** 先完成今日待办的显示、勾选、新增、刷新闭环，再添加清单筛选、逾期和勾选框显示等高频选项。无需一次暴露滴答的全部主题和筛选项。

当前日用版曾经通过用户实际操作确认“冷启动点击加号同时出现完整主窗口”。后续源码的启动分流修复已通过 10 项定向测试并构建成功；这些结果不能代替安装后的桌面交互验收，本轮分析没有据此宣称问题已修复。

下一轮只回归相关场景：

- 主应用完全退出后点组件加号：仅出现快速新增卡片。
- 主应用已运行时点加号：复用快速新增入口，保留主窗口原有状态。
- 保存或取消：任务只创建一次，日期与清单正确，保存后组件更新。
- 关闭快速新增后通过 Dock 打开：正常显示完整主窗口。

## 证据与方法

使用现有 REA CLI 的 `inspect-macho`、`inspect-plist` 和 `decode-interface-builder`。本次没有可用的深度反编译引擎；Objective-C 元数据、动态绑定和反汇编由 Apple 工具补充，单独标明来源，没有将普通工具输出冒充 REA Evidence。

| 编号 | 文件 | 来源与范围 |
| --- | --- | --- |
| E1 | [widget-macho.json](widget-macho.json) | REA 现代组件 Mach-O 检查的精简投影 |
| E2 | [host-macho.json](host-macho.json) | REA 主程序 Mach-O 检查的精简投影 |
| E3 | [widget-plist.json](widget-plist.json) | REA 现代组件 Info.plist 检查的精简投影 |
| E4 | [nib-findings.json](nib-findings.json) | REA 编译后 nib 解码的关注字段投影 |
| E5 | [nib-input-provenance.json](nib-input-provenance.json) | 关注资源副本与原安装包逐字节相同的比较结果 |
| O1 | [package-observations.json](package-observations.json) | plist、App Intent 元数据及 Mach-O 嵌入权限声明；普通静态工具观察 |
| O2 | [add-route-anchors.json](add-route-anchors.json)、[widget-add-link-callers.json](widget-add-link-callers.json) | Apple 工具的新增 URL 与 Link 调用片段 |
| O3 | [quick-add-class-observations.json](quick-add-class-observations.json) | Apple 工具的新增承载类元数据 |

REA 全包 nib 遍历达到 64 文档上限后，另取五份关注 nib 和必要的包识别文件组成临时输入；E5 记录各文件与原包逐字节相同。E4 不能代表未复制资源或运行时创建的窗口。完整解码输出保留在系统临时分析目录，项目内记录是便于阅读的投影，不用于 canonical Evidence 重放。

嵌入权限声明是直接解析 arm64 代码签名中的 XML 槽所得。当前主代理环境的 codesign 未成功输出该 XML，因此记录只证明包内声明，不验证系统当前是否授予共享容器访问。导入与导出列表也受符号裁剪影响；缺少符号不作为缺少功能的证据。

本轮未启动滴答、未读写真实任务，也未执行滴答组件的新增或完成动作。
