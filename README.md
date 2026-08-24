# WorkFollow

WorkFollow 是一个本地优先的工作工具，在同一个工作空间内统一处理个人任务、协作任务和笔记。本仓库采用前后端独立工程：Vue 3 前端通过 REST API 访问 FastAPI 后端，业务数据存入 SQLite，附件存入 `data/files/`。

## 当前进度

- Phase 1–6：基础工程、待办、日历与快捷入口、笔记和笔记联动
- Phase 7+：账户体系、任务成员指派、团队笔记与审批、笔记分享、通知、审计日志
- 信息架构参考：仓库上级目录的 HTML 原型（不作为最终视觉约束）
- 最终视觉：统一 Card Layout；深紫用于导航与主要操作，青绿用于核心数据，背景与容器采用灰白和中性色

主题开发规范：[`docs/theme-development-guide.md`](docs/theme-development-guide.md)

## 统一任务与团队协作

- **单一事实源**：个人任务和协作任务都存放在 `todos`；创建者、团队来源和执行成员分别由 `creator_id`、`team_id`、`task_assignments` 表达，不复制任务正文。
- **统一入口**：首页、任务页和日历都读取 `/api/tasks`。任务页的“分配给我的”和“我分配的”只是服务端过滤视图，不是第二套任务页面。
- **成员指派**：个人任务默认只指派自己；团队 OWNER / ADMIN 可以一次选择多个当前团队成员。执行人只能更新自己的 Assignment 状态，创建者维护任务正文和成员范围。
- **进度聚合**：任务完成进度由有效 Assignment 实时计算；全部执行人完成后，Task 自动完成。
- **数据隔离**：个人资源按用户隔离；协作任务、团队笔记和附件同时校验成员关系与资源授权。非参与者和离队成员访问返回 403 / 404。
- **个人 → 团队流转**：个人笔记可快照提交团队审批（TeamNoteSubmission），个人附件需显式授权（TeamFileAccess）后才可被团队引用，个人笔记可只读分享给指定用户（NoteShare）。
- **横切能力**：Cookie 会话认证、团队通知、团队操作审计日志和安全回归测试。

## 环境要求

- Node.js 20+
- Python 3.12+

## 一键启动

macOS 可直接双击项目根目录的 `start.command`，或在终端执行：

```bash
./start.command
```

脚本会在首次运行时安装缺失的依赖、更新数据库、启动前后端并打开浏览器。关闭脚本窗口或按 `Control+C` 会同时停止两个服务。

## 启动后端

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/alembic upgrade head
.venv/bin/uvicorn app.main:app --reload --port 8123
```

后端健康检查：<http://127.0.0.1:8123/api/health>

## 启动前端

```bash
cd frontend
npm install
npm run dev
```

前端默认地址：<http://127.0.0.1:5173>

## 验证

```bash
cd backend && .venv/bin/pytest
cd frontend && npm run type-check && npm run build
```
