from datetime import datetime
from typing import Any

from pydantic import Field, field_validator, model_validator

from app.models.todo import RecurrenceType, TodoAssignmentStatus, TodoPriority, TodoSourceType, TodoStatus
from app.schemas.base import ApiModel
from app.schemas.auth import UserRead
from app.schemas.resource_relation import TaskSourceCreate, TaskSourceRead


class TodoPermissions(ApiModel):
    editable: bool = False
    content_editable: bool = False
    deletable: bool = False
    assignable: bool = False
    completable: bool = False


class TodoListCreate(ApiModel):
    name: str = Field(min_length=1, max_length=120)

    @field_validator("name")
    @classmethod
    def normalize_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("清单名称不能为空")
        return value


class TodoListUpdate(TodoListCreate):
    pass


class TodoListRead(ApiModel):
    id: str | None
    name: str
    sort_order: int
    protected: bool = False


class TodoListDeleteResult(ApiModel):
    name: str
    fallback_list_name: str
    moved_task_count: int


class TodoAssignmentRead(ApiModel):
    id: str
    user_id: str
    assigned_by_id: str | None
    status: TodoAssignmentStatus
    active: bool
    assigned_at: datetime
    completed_at: datetime | None
    removed_at: datetime | None
    user: UserRead


class TodoCreate(ApiModel):
    title: str = Field(min_length=1, max_length=500)
    description: str | None = None
    content_json: dict[str, Any] | None = None
    attachment_ids: list[str] = Field(default_factory=list, max_length=100)
    priority: TodoPriority = TodoPriority.NONE
    due_at: datetime | None = None
    due_end_at: datetime | None = None
    reminder_at: datetime | None = None
    recurrence_type: RecurrenceType = RecurrenceType.NONE
    recurrence_config: dict[str, Any] | None = None
    list_name: str = Field(default="收集箱", min_length=1, max_length=120)
    tags: list[str] = Field(default_factory=list, max_length=20)
    source_type: TodoSourceType = TodoSourceType.MANUAL
    source_note_id: str | None = None
    source_excerpt: str | None = None
    source: TaskSourceCreate | None = None
    team_id: str | None = Field(default=None, min_length=1, max_length=36)
    assignee_ids: list[str] | None = Field(default=None, max_length=100)

    @model_validator(mode="after")
    def validate_schedule(self) -> "TodoCreate":
        self.title = self.title.strip()
        if not self.title:
            raise ValueError("待办标题不能为空")
        if self.reminder_at is not None and self.due_at is None:
            raise ValueError("设置提醒前必须先设置截止时间")
        if self.reminder_at is not None and self.due_at is not None and self.reminder_at > self.due_at:
            raise ValueError("提醒时间不能晚于截止时间")
        if self.recurrence_type != RecurrenceType.NONE and self.due_at is None:
            raise ValueError("重复待办必须设置首次执行时间")
        if self.recurrence_type == RecurrenceType.NONE:
            self.recurrence_config = None
        if self.due_end_at is not None and (self.due_at is None or self.due_end_at < self.due_at):
            raise ValueError("结束时间不能早于开始时间")
        self.list_name = self.list_name.strip() or "收集箱"
        self.tags = list(dict.fromkeys(tag.strip() for tag in self.tags if tag.strip()))
        if self.assignee_ids is not None:
            self.assignee_ids = list(dict.fromkeys(self.assignee_ids))
        self.attachment_ids = list(dict.fromkeys(self.attachment_ids))
        return self


class TodoUpdate(ApiModel):
    title: str | None = Field(default=None, min_length=1, max_length=500)
    description: str | None = None
    content_json: dict[str, Any] | None = None
    attachment_ids: list[str] | None = Field(default=None, max_length=100)
    priority: TodoPriority | None = None
    due_at: datetime | None = None
    due_end_at: datetime | None = None
    reminder_at: datetime | None = None
    recurrence_type: RecurrenceType | None = None
    recurrence_config: dict[str, Any] | None = None
    list_name: str | None = Field(default=None, min_length=1, max_length=120)
    tags: list[str] | None = Field(default=None, max_length=20)


class TodoAssigneesUpdate(ApiModel):
    assignee_ids: list[str] = Field(default_factory=list, max_length=100)

    @model_validator(mode="after")
    def normalize_assignees(self) -> "TodoAssigneesUpdate":
        self.assignee_ids = list(dict.fromkeys(self.assignee_ids))
        if not self.assignee_ids:
            raise ValueError("任务至少需要一名执行成员")
        return self


class TodoMyStatusUpdate(ApiModel):
    status: TodoAssignmentStatus


class TodoRead(ApiModel):
    id: str
    title: str
    description: str | None
    content_json: dict[str, Any] | None
    attachment_ids: list[str]
    status: TodoStatus
    priority: TodoPriority
    due_at: datetime | None
    due_end_at: datetime | None
    reminder_at: datetime | None
    reminded_at: datetime | None
    recurrence_type: RecurrenceType
    recurrence_config: dict[str, Any] | None
    list_name: str
    tags: list[str]
    source_type: TodoSourceType
    source_note_id: str | None
    source_excerpt: str | None
    sources: list[TaskSourceRead] = Field(default_factory=list)
    recurring_series_id: str | None
    generated_from_id: str | None
    creator_id: str
    team_id: str | None
    creator: UserRead
    assignments: list[TodoAssignmentRead] = Field(default_factory=list)
    my_assignment: TodoAssignmentRead | None = None
    completed_assignments: int = 0
    total_assignments: int = 0
    permissions: TodoPermissions = Field(default_factory=TodoPermissions)
    completed_at: datetime | None
    created_at: datetime
    updated_at: datetime


class TodoTransfer(ApiModel):
    team_id: str = Field(min_length=1, max_length=36)
    assignee_ids: list[str] = Field(default_factory=list, max_length=100)

    @model_validator(mode="after")
    def validate_transfer(self) -> "TodoTransfer":
        self.assignee_ids = list(dict.fromkeys(self.assignee_ids))
        return self


class TodoCompleteResult(ApiModel):
    todo: TodoRead
    next_todo: TodoRead | None = None


class ReminderAcknowledge(ApiModel):
    reminded_at: datetime | None = None
