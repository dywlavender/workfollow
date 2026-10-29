# 滴答任务页：清单功能分析

2026-10-27 · 本机 TickTick 8.0.80（492）

范围为左侧清单及文件夹，以及进入普通清单后的内容区域。今天、明天等智能清单和过滤器用于汇集内容，不等同于普通清单。

## 证据与边界

- E1：REA 解码本机安装包中 21 份相关编译界面资源，得到 1,958 个节点与 949 条连接。21 份资源的识别层级均完整。这是所选资源范围内的静态界面证据。
- E2：直接读取同一安装包的简体中文本地化文案，核实选项和行为说明。文案可以说明产品设计，但不等同于本次实际执行。
- E3：读取当前滴答窗口，确认任务清单、笔记清单、文件夹层级、数量、归档入口和清单内容区。右键及顶栏弹层没有被自动化打开，未假装完成这些菜单的实际验收。
- 原生方法元数据读取存在记录预算和指针解析边界；没有据此判断某功能不存在。

## 功能清单

| 功能 | 内容 | 依据 |
|---|---|---|
| 新建、编辑清单 | 名称、颜色、Emoji、所属文件夹、清单类型、视图模式 | E1：TTNewProjectEditViewController、TTProjectEditViewController |
| 任务清单与笔记清单 | 清单类型决定后续新建内容的默认类型，已有内容不批量转换 | E1：kindPopUpButton；E2：project_type_change_message；E3：两种侧栏行 |
| 文件夹组织 | 新建、编辑名称和 Emoji、折叠展开、解散文件夹后清单回到侧栏 | E1：TTFolderEditViewController；E2；E3 |
| 置顶与数量 | 清单置顶、取消置顶，独立置顶区域；侧栏数量显示 | E1：TTProjectPinViewController、TTProjectListCellView；E2；E3 |
| 视图模式 | 列表、看板、时间线；新建和编辑清单时均有对应选择入口 | E1：viewModeListButton、viewModeKanbanButton、viewModeTimelineButton；E2 |
| 分组、排序 | 自定义分组、分组插入与移动；按时间、优先级、标题等排序及方向选择。拖动受当前分组、排序方式限制 | E1：TTSortOptionPickerViewController、TTListSectionMenuViewController；E2 |
| 列表显示设置 | 日期显示依据；窄窗口时详情采用侧栏或弹窗 | E1：TTListDisplaySettingsVC；E2：task_detail_layout 系列 |
| 看板显示设置 | 看板尺寸、输入框显示、检查事项显示、日期显示依据 | E1：TTKanbanDisplaySettingsVC |
| 智能清单展示 | 是否在今天、明天、最近 7 天中显示 | E1：showInSmartListPopUpButton、hideSwitchButton；E2：show_in_smart_list_hint |
| 清单提醒 | 清单级提醒选择、编辑时的不提醒开关；与智能清单展示分别设置 | E1：reminderPopUpButton、muteSwitchButton、hideSwitchButton |
| 复制清单 | 全部任务且保留已完成状态、全部任务但不保留已完成状态、只复制未完成任务 | E2：duplicate_list_alert 系列 |
| 归档、取消归档 | 进入已归档入口；归档后内容不进智能清单、不再到期提醒，且不可编辑；取消归档移回 | E2：archive_confirm_message、cannot_edit_archived_list、unarchive_confirm_message；E3：归档入口 |
| 删除清单 | 删除会连带删除清单内容，共享清单还影响共享成员 | E2：delete_list_%@、delete_all_tasks_in_list、delete_all_tasks_in_share_list |
| 默认清单机制 | 有默认清单设置及共享清单设为默认的确认，默认清单不能直接归档 | E2：Default_List、CannotArchiveDefault、set_shared_list_as_default_list_title；属于相关设置，未确认一定出现在清单右键菜单 |
| 共享与权限 | 邀请成员、共享链接、链接权限、只读与编辑权限、申请编辑 | E1：TTProjectSharingViewController；E2 |
| 共享变更通知 | 对新增、完成或撤销完成、删除或移动任务的通知分别设置 | E1：notiSwitchesAddedButton、notiSwitchesCompletedButton、notiSwitchesDeletedButton |
| 转让清单 | 转让给其他共享成员；对方成为所有者，原所有者成为普通成员 | E1：TTProjectTransferViewController；E2 |
| 清单动态 | 有专门的清单动态页面；资源文案提示高级会员能力 | E1：TTListActivitiesViewController；E2 |
| 视图内筛选 | 日期、清单、标签、状态条件，以及保存为过滤器入口 | E1：TTTaskListViewController；本次未确认普通清单中何时显示，不能称为所有清单常驻功能 |

## 对后续复刻最有影响的规则

1. 清单类型和内容类型分离。改成笔记清单，仅改变以后新建的默认行为，不能把已存在任务全部改成笔记。
2. 隐藏于智能清单、关闭提醒、归档是三种不同状态，不能用一个隐藏开关替代。
3. 文件夹、清单内分组、任务层级也要分开。文件夹组织清单，分组组织清单内内容，子任务属于任务本身。
4. 拖放需要服从当前排序和分组规则。资源文案明确存在“当前排序/分组不支持拖动”的反馈。
5. 复制清单有三种状态处理方案，不能简单等同于复制未完成任务。
6. 清单的视图、显示设置、智能清单参与规则和共享权限，是不同层次的配置。

## 尚未确认的边界

- 未实际执行新增、改类型、复制、归档、删除、邀请、转让，未更改账号数据。
- 未验证当前账号对时间线、清单动态、共享成员数等能力的具体授权。时间线编辑控件带有高级会员标识。
- 新建模板、打印、日历 URL、第三方集成相关文案或资源不足以确认其在当前清单菜单中的完整路径，未并入本次确定的菜单清单。
- 普通清单中筛选条的显示条件、各视图偏好的实际持久化作用域、文件夹最大嵌套层级仍需后续定向观察。

结构化来源摘录见 [observations.json](observations.json)。本次分析没有修改本项目的应用源码。

后续任务清单改造及验证范围见 [implementation.md](implementation.md)。
