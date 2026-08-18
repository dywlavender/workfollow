from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, time

from sqlalchemy.orm import Session

from app.models.auth import User
from app.models.todo import local_now
from app.models.resource_relation import ResourceType
from app.schemas.note import NoteCreate
from app.schemas.resource_relation import TaskSourceCreate
from app.schemas.todo import TodoCreate
from app.services import note_service, todo_service


ONBOARDING_VERSION = 1
GUIDE_TITLE = "使用指南"
STARTER_TASK_TITLE = "阅读《使用指南》并完成首次设置"


@dataclass(frozen=True)
class OnboardingResult:
    guide_note_id: str
    starter_task_id: str


def _text(value: str) -> dict[str, object]:
    return {"type": "text", "text": value}


def _paragraph(value: str) -> dict[str, object]:
    return {"type": "paragraph", "content": [_text(value)]}


def _heading(value: str, level: int = 2) -> dict[str, object]:
    return {"type": "heading", "attrs": {"level": level}, "content": [_text(value)]}


def _guide_content() -> dict[str, object]:
    return {
        "type": "doc",
        "content": [
            _heading("欢迎使用 WorkFollow", 1),
            _paragraph("这是一份简短的上手指南。完成右侧的新手任务后，你就可以开始管理自己的工作。"),
            _heading("任务", 2),
            _paragraph("在任务页面创建、编辑任务；勾选任务即可完成。日期、负责人和优先级都可以在任务详情中调整。"),
            _heading("日期与提醒", 2),
            _paragraph("给任务设置日期后，它会出现在首页、日历和对应的任务视图中；需要提醒时再设置提醒时间。"),
            _heading("笔记", 2),
            _paragraph("在笔记页面创建和管理个人笔记，可以使用文件夹整理内容，也可以从笔记创建任务。"),
            _heading("常用", 2),
            _paragraph("常用页面集中展示系统管理员配置的网站。点击网站卡片会在新标签页打开。"),
            _heading("通知", 2),
            _paragraph("通知页面用于查看任务、团队投稿和审核结果提醒；标记已读与删除通知是两个独立操作。"),
            _heading("团队与权限", 2),
            _paragraph("团队任务和团队笔记只对有权限的成员开放。OWNER、ADMIN、MEMBER 是团队内部角色，系统 ROOT 是全局权限。"),
        ],
    }


def ensure_onboarding(db: Session, user: User) -> OnboardingResult | None:
    """Create the first-run note and task without committing the transaction.

    Registration and login own the outer transaction. Keeping this service
    commit-free ensures a failure in any one of the three records rolls back
    the user/session together with the onboarding data.
    """

    if user.onboarding_version >= ONBOARDING_VERSION:
        return None

    guide_note = note_service.create_note(
        db,
        NoteCreate(
            title=GUIDE_TITLE,
            content_json=_guide_content(),
            plain_text=(
                "欢迎使用 WorkFollow\n\n"
                "任务\n在任务页面创建、编辑和完成任务。\n\n"
                "日期与提醒\n给任务设置日期和提醒时间。\n\n"
                "笔记\n创建和管理个人笔记。\n\n"
                "常用\n查看系统管理员配置的网站。\n\n"
                "通知\n查看任务、团队投稿和审核结果提醒。\n\n"
                "团队与权限\n了解团队角色和系统 ROOT 权限。"
            ),
        ),
        user.id,
        commit=False,
    )
    starter_task = todo_service.create_todo(
        db,
        TodoCreate(
            title=STARTER_TASK_TITLE,
            due_at=datetime.combine(local_now().date(), time.min),
            assignee_ids=[user.id],
            source=TaskSourceCreate(
                resource_type=ResourceType.PERSONAL_NOTE,
                resource_id=guide_note.id,
                excerpt="注册后的首次设置指南",
            ),
        ),
        user.id,
        commit=False,
    )
    user.onboarding_version = ONBOARDING_VERSION
    db.flush()
    return OnboardingResult(guide_note_id=guide_note.id, starter_task_id=starter_task.id)
