# Quick Add 属性与任务模板合同

产品基线：2026-10-01 用户提供的滴答属性菜单、三列任务模板 Gallery、创建模板说明截图及附带方案。
本阶段只覆盖任务模板；不扩展 Notes 模板、附件、输入框设置或 Slash。

## 职责与状态

| 合同 | 规则 | 回归证据 |
| --- | --- | --- |
| QA-TPL-001 | 属性菜单仅优先级、清单、标签、从模板添加；提醒与重复走单独日期入口 | QuickAddTemplateRenderTests |
| QA-TPL-002 | 清单与标签子菜单互斥；子层 Escape 优先；父菜单消失清理子状态 | activeChild 单一枚举、PopupEscapeRouter |
| QA-TPL-003 | 从模板添加先关闭属性菜单，下一 UI turn 打开 Gallery；此时不创建任务 | TaskListView 呈现边界、菜单点击测试 |
| TPL-001 | 系统模板只读 Catalog，用户模板继续 templates.json；两者不混写 | TaskTemplateCatalogTests |
| TPL-002 | 工作准备与旅行物品是正文 Checklist；每日记录是 paragraph；真实 childTitles 能力保留 | Catalog 与 TaskTemplateTests |
| TPL-003 | 应用生成完整 parent + document + tags + list + priority + schedule + children，一次 commit、一次 revision、一次 undo | TaskTemplateTests |
| TPL-004 | Gallery 三列、右上搜索、整卡点击；搜索名称、标题、正文；无匹配不修改数据 | TaskTemplateGalleryRenderTests |
| TPL-005 | 成功才关闭 Gallery、清空 Quick Add 全部草稿并收起，选中新任务；失败/取消不清草稿、不创建 | Gallery guard 与 TaskListView onApplied |
| TPL-006 | 无用户模板：管理入口显示小教育卡；有用户模板：仅用户模板重命名/删除 | TemplateManagementView；不宣称管理页像素复刻 |

## 几何与输入规则

- Gallery 属于模态选择工作区，不是 Quick Add 属性子菜单；关闭属性父层以后才呈现。
- 主体首选 1000×700pt，按所属窗口 screen.visibleFrame 有界收缩；卡片数量与搜索结果不改变外框。
- 卡片使用静态正文预览，不嵌入可编辑 DocumentEditor。
- 教育层380pt宽、内容自然高度，确认按钮42pt并铺满内部宽度；不参与 Gallery fitting size。首个 Escape 关闭教育/管理层，随后 Escape 关闭 Gallery；接入窗口级 PopupEscapeRouter，不能只依赖 View 的 onExitCommand。
- Quick Add 保持既有解析与日期草稿能力，本轮不改变 Parser 或日期面板。

## 验收边界

自动化覆盖存储分离、块类型、模板创建与撤销、实际 NSWindow/NSHostingView 几何和导出的 PNG。
实际 App 的菜单→Gallery→创建→Quick Add 清空、Escape、教育层须另记录实机结果，不能以常量测试替代。
教育文案仅说明已实现的任务路径，本轮不据此宣称 Notes 已具备保存模板入口。

渲染产物目录：`/tmp/workfollow-template-renders/`。验收完成后才可冻结；未验证的项目必须保留边界说明。

实机已验证（退出旧进程，从本轮 `/tmp/workfollow-native-derived-data/Build/Products/Debug/WorkFollow.app` 启动）：属性菜单仅声明入口；菜单关闭后 Gallery 打开；搜索过滤；教育首个 Escape 仅关子层，第二个关 Gallery；取消后“模板验收草稿”保留；重新打开整卡应用工作准备模板后，Quick Add 为空且显示⌘N，Inspector 显示今天与7个正文Checklist。
用户模板 rename/delete 继续由既有 Store 测试覆盖，未做破坏用户模板的实机删除验收。Light 渲染图已复核；不宣称 Dark 与小窗口逐像素复刻。

最终自动验收：76项、0失败（TaskTemplateTests、TaskTemplateCatalogTests、QuickAddTemplateRenderTests、TaskTemplateGalleryRenderTests、QuickAddCompositionTests、QuickAddParserTests、PopupEscapeRoutingTests）。实际截图发现教育按钮未铺满后，已修成380pt小卡与整宽胶囊按钮，重新构建、重启并再次截图复核。实机示例任务通过一次撤销清理。
