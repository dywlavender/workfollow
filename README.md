# 打勾（WorkFollow）

打勾（WorkFollow）是一个本地优先的工作工具，在同一个工作空间内统一处理个人任务、协作任务和笔记。本仓库采用前后端独立工程：Vue 3 前端通过 REST API 访问 FastAPI 后端，业务数据存入 SQLite，附件存入 `data/files/`。

## 当前进度

- Phase 1–6：基础工程、待办、日历与快捷入口、笔记和笔记联动
- Phase 7+：账户体系、任务成员指派、团队笔记与审批、笔记分享、通知、审计日志
- 信息架构参考：仓库上级目录的 HTML 原型（不作为最终视觉约束）
- 最终视觉：统一 Card Layout；深紫用于导航与主要操作，青绿用于核心数据，背景与容器采用灰白和中性色

主题开发规范：[`docs/theme-development-guide.md`](docs/theme-development-guide.md)

## macOS 个人版桌面端

仓库同时提供一套不依赖网页容器的 Flutter macOS 个人版原型，定位为单用户、本地优先的任务与笔记工作台，不包含团队协同、账号和实时在线能力。Web 端可以从“设置 → 数据迁移”导出个人任务、清单、笔记和文件夹，再由 macOS 版离线导入。设计基线见 [`docs/macos-personal-app-design.md`](docs/macos-personal-app-design.md)，代码与运行说明见 [`desktop/README.md`](desktop/README.md)。

## 统一任务与团队协作

- **单一事实源**：个人任务和协作任务都存放在 `todos`；创建者、团队来源和执行成员分别由 `creator_id`、`team_id`、`task_assignments` 表达，不复制任务正文。
- **统一入口**：首页、任务页和日历都读取 `/api/tasks`。任务页的“分配给我的”和“我分配的”只是服务端过滤视图，不是第二套任务页面。
- **成员指派**：个人任务默认只指派自己；团队 OWNER / ADMIN 可以一次选择多个当前团队成员。执行人只能更新自己的 Assignment 状态，创建者维护任务正文和成员范围。
- **进度聚合**：任务完成进度由有效 Assignment 实时计算；全部执行人完成后，Task 自动完成。
- **数据隔离**：个人资源按用户隔离；协作任务、团队笔记和附件同时校验成员关系与资源授权。非参与者和离队成员访问返回 403 / 404。
- **个人 → 团队流转**：个人笔记可快照提交团队审批（TeamNoteSubmission），个人附件需显式授权（TeamFileAccess）后才可被团队引用，个人笔记可只读分享给指定用户（NoteShare）。
- **横切能力**：Cookie 会话认证、团队通知、团队操作审计日志、Yjs 协同编辑和安全回归测试。

## 环境要求

- Node.js 22+
- Python 3.12+

## 一键启动

macOS 可直接双击项目根目录的 `start.command`，或在终端执行：

```bash
./start.command
```

脚本会在首次运行时安装缺失的依赖、更新数据库、启动前端、FastAPI 和 Yjs 协同服务并打开浏览器。关闭脚本窗口或按 `Control+C` 会同时停止这三个服务。

## 启动后端

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/alembic upgrade head
.venv/bin/uvicorn app.main:app --reload --port 8123
```

后端健康检查：<http://127.0.0.1:8123/api/health>

## Agent / MCP 接入

打勾可以通过本地 MCP Server 向 Codex、Claude Code 和 Tencent WorkBuddy 提供个人笔记的搜索、读取、速记和新建能力。在“设置 → 账号 → Agent 接入”生成唯一 Token，然后参考 [`docs/mcp-integration.md`](docs/mcp-integration.md) 配置所需客户端。

## 启动前端

```bash
cd frontend
npm install
npm run dev
```

前端默认地址：<http://127.0.0.1:5173>

任务正文和可编辑元数据的多人实时编辑由 `collaboration/` 下的 Hocuspocus 服务提供。任务正文使用 `task:<id>` 文档，标题、截止时间、优先级、提醒、重复规则和标签使用独立的 `task-meta:<id>` 文档；个人笔记正文和标题使用 `note:<id>` 文档；管理员编辑团队知识时使用仅管理员可访问的 `knowledge-draft:<id>` 工作文档。团队知识只有点击“保存修改”后才写入已发布版本并生成版本记录，普通成员始终读取已发布内容。手动启动后端和前端时，还需要另开终端运行协同服务，但内部令牌只需在根目录 `.env` 配置一次：

```text
WORKFOLLOW_COLLABORATION_INTERNAL_TOKEN=请替换为内部令牌
```

协同服务会自动读取根目录 `.env`，不需要再在命令行重复传入令牌：

```bash
cd collaboration
npm ci
npm start
```

服务默认监听 `127.0.0.1:8124`，后端默认使用 `http://127.0.0.1:8123`；如果修改了后端地址，只需额外设置 `WORKFOLLOW_BACKEND_URL`。一键脚本会自动生成并共享本次启动使用的内部令牌，同时管理三个进程。前端会根据服务端返回的权限控制编辑入口，Hocuspocus 和后端投影接口还会再次校验权限，不能只依赖前端按钮的禁用状态。任务字段、个人笔记正文/标题已经没有通用 HTTP 更新入口，统一由 Yjs 文档维护；HTTP 仅保留创建、移动文件夹、收藏、完成、指派、发布/审核、附件上传和资源关联等事务接口，以及协同服务到 SQL 的内部投影。

外部 HTTP 通知（任务、每日待办和知识审核结果）会携带 `url` 参数，并在正文中附上同一个业务深链。部署时请将
`WORKFOLLOW_SERVER_URL` 设置为用户实际打开 WorkFollow 的地址（例如
`https://workfollow.example.com`）；使用 `start.command` 本地启动时会自动使用前端端口。
未配置时仍会生成相对地址（任务为 `/todos?...`，知识投稿为 `/notes?...`），仅适合与 WorkFollow 同源的通知接收端。
访问深链时如果没有登录，前端会先进入登录页，登录成功后自动回到原业务地址。

## 验证

```bash
cd backend && .venv/bin/pytest
cd frontend && npm run type-check && npm run build
```
