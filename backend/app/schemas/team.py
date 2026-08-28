from datetime import datetime
from typing import Any, Literal

from pydantic import Field, model_validator

from app.models.team import TeamMemberRole, TeamMemberStatus, TeamStatus
from app.models.team_note import (
    TeamNoteSourceType,
    TeamNoteStatus,
    TeamNoteSubmissionStatus,
    TeamNoteSubmissionType,
)
from app.models.team_task import TeamTaskAssignmentStatus, TeamTaskStatus
from app.models.todo import RecurrenceType, TodoPriority
from app.schemas.auth import UserRead
from app.schemas.base import ApiModel
from app.schemas.note import AttachmentRead


class TeamCreate(ApiModel):
    name: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=2000)


class TeamUpdate(ApiModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=2000)


class TeamRead(ApiModel):
    id: str
    name: str
    description: str | None
    avatar_url: str | None
    owner_id: str
    status: TeamStatus
    created_at: datetime
    updated_at: datetime
    role: TeamMemberRole | None = None


class TeamMemberCreate(ApiModel):
    identifier: str = Field(min_length=1, max_length=320)
    role: TeamMemberRole = TeamMemberRole.MEMBER


class TeamMemberRoleUpdate(ApiModel):
    role: TeamMemberRole


class TeamMemberRead(ApiModel):
    id: str
    team_id: str
    user_id: str
    role: TeamMemberRole
    status: TeamMemberStatus
    joined_at: datetime
    created_at: datetime
    updated_at: datetime
    user: UserRead


class TeamMemberCandidateRead(ApiModel):
    id: str
    username: str
    nickname: str
    avatar_url: str | None


class TeamTaskCreate(ApiModel):
    title: str = Field(min_length=1, max_length=500)
    description: str | None = None
    content_json: dict[str, Any] | None = None
    priority: TodoPriority = TodoPriority.NONE
    due_at: datetime | None = None
    due_end_at: datetime | None = None
    reminder_at: datetime | None = None
    recurrence_type: RecurrenceType = RecurrenceType.NONE
    recurrence_config: dict[str, Any] | None = None
    attachment_ids: list[str] = Field(default_factory=list, max_length=100)
    list_name: str = Field(default="收集箱", min_length=1, max_length=120)
    tags: list[str] = Field(default_factory=list, max_length=20)
    client_request_id: str | None = Field(default=None, min_length=8, max_length=64)
    assignee_ids: list[str] = Field(default_factory=list, max_length=100)

    @model_validator(mode="after")
    def validate_task(self) -> "TeamTaskCreate":
        self.title = self.title.strip()
        if not self.title:
            raise ValueError("团队任务标题不能为空")
        self.assignee_ids = list(dict.fromkeys(self.assignee_ids))
        self.attachment_ids = list(dict.fromkeys(self.attachment_ids))
        if self.due_end_at is not None and (self.due_at is None or self.due_end_at < self.due_at):
            raise ValueError("结束时间不能早于开始时间")
        if self.reminder_at is not None and (self.due_at is None or self.reminder_at > self.due_at):
            raise ValueError("提醒时间不能晚于截止时间")
        if self.recurrence_type != RecurrenceType.NONE and self.due_at is None:
            raise ValueError("重复任务必须设置截止时间")
        if self.recurrence_type == RecurrenceType.NONE:
            self.recurrence_config = None
        self.list_name = self.list_name.strip() or "收集箱"
        self.tags = list(dict.fromkeys(tag.strip() for tag in self.tags if tag.strip()))
        return self


class TeamTaskAssignmentRead(ApiModel):
    id: str
    team_task_id: str
    user_id: str
    assigned_by_id: str | None
    status: TeamTaskAssignmentStatus
    assigned_at: datetime
    completed_at: datetime | None
    created_at: datetime
    updated_at: datetime
    user: UserRead


class TeamTaskRead(ApiModel):
    id: str
    team_id: str
    creator_id: str
    title: str
    description: str | None
    content_json: dict[str, Any] | None
    priority: TodoPriority
    due_at: datetime | None
    due_end_at: datetime | None
    reminder_at: datetime | None
    recurrence_type: RecurrenceType
    recurrence_config: dict[str, Any] | None
    attachment_ids: list[str]
    attachments: list[AttachmentRead] = Field(default_factory=list)
    list_name: str
    tags: list[str]
    status: TeamTaskStatus
    completed_at: datetime | None
    cancelled_at: datetime | None
    created_at: datetime
    updated_at: datetime
    assignments: list[TeamTaskAssignmentRead] = Field(default_factory=list)
    total_assignments: int = 0
    completed_assignments: int = 0
    progress: int = 0


class MyTaskRead(ApiModel):
    source_type: Literal["PERSONAL", "TEAM"]
    id: str
    title: str
    description: str | None
    priority: TodoPriority
    due_at: datetime | None
    due_end_at: datetime | None
    status: str
    task_status: str | None = None
    team_id: str | None = None
    team_name: str | None = None
    team_task_id: str | None = None
    assignment_id: str | None = None
    list_name: str | None = None
    tags: list[str] = Field(default_factory=list)


class TeamTaskAssignmentStatusUpdate(ApiModel):
    status: TeamTaskAssignmentStatus


class TeamNoteCreate(ApiModel):
    title: str = Field(min_length=1, max_length=500)
    content_json: dict[str, Any] = Field(default_factory=lambda: {"type": "doc", "content": [{"type": "paragraph"}]})
    plain_text: str = ""
    attachment_ids: list[str] = Field(default_factory=list, max_length=100)
    category_id: str | None = None
    tags: list[str] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def validate_note(self) -> "TeamNoteCreate":
        self.title = self.title.strip()
        if not self.title:
            raise ValueError("团队笔记标题不能为空")
        self.attachment_ids = list(dict.fromkeys(self.attachment_ids))
        self.tags = list(dict.fromkeys(tag.strip() for tag in self.tags if tag.strip()))
        return self


class TeamNoteUpdate(ApiModel):
    title: str | None = Field(default=None, min_length=1, max_length=500)
    content_json: dict[str, Any] | None = None
    plain_text: str | None = None
    attachment_ids: list[str] | None = Field(default=None, max_length=100)
    category_id: str | None = None
    tags: list[str] | None = Field(default=None, max_length=20)
    base_version_no: int | None = Field(default=None, ge=1, alias="baseVersion")

    @model_validator(mode="after")
    def validate_note(self) -> "TeamNoteUpdate":
        if self.title is not None:
            self.title = self.title.strip()
            if not self.title:
                raise ValueError("团队笔记标题不能为空")
        if self.attachment_ids is not None:
            self.attachment_ids = list(dict.fromkeys(self.attachment_ids))
        if self.tags is not None:
            self.tags = list(dict.fromkeys(tag.strip() for tag in self.tags if tag.strip()))
        return self


class TeamNoteCollaborationAccess(ApiModel):
    can_view: bool
    can_edit: bool
    # The collaboration bridge needs the team context when the authenticated
    # user is ROOT.  ROOT is deliberately not an implicit team member, so the
    # normal ``GET /team/knowledge/{id}`` route requires this query parameter.
    team_id: str | None = None
    version_no: int = 1


class TeamNotePermissions(ApiModel):
    can_edit: bool = False
    can_copy: bool = True
    can_archive: bool = False
    can_delete: bool = False


class TeamNoteCategoryCreate(ApiModel):
    name: str = Field(min_length=1, max_length=120)
    sort_order: int = 0

    @model_validator(mode="after")
    def normalize(self) -> "TeamNoteCategoryCreate":
        self.name = self.name.strip()
        if not self.name:
            raise ValueError("知识分类名称不能为空")
        return self


class TeamNoteCategoryUpdate(ApiModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    sort_order: int | None = None

    @model_validator(mode="after")
    def normalize(self) -> "TeamNoteCategoryUpdate":
        if self.name is not None:
            self.name = self.name.strip()
            if not self.name:
                raise ValueError("知识分类名称不能为空")
        return self


class TeamNoteCategoryRead(ApiModel):
    id: str
    team_id: str
    name: str
    sort_order: int
    created_at: datetime
    updated_at: datetime


class TeamNoteRead(ApiModel):
    id: str
    team_id: str
    title: str
    content_json: dict[str, Any]
    plain_text: str
    attachment_ids: list[str]
    attachments: list[AttachmentRead] = Field(default_factory=list)
    category_id: str | None
    category: TeamNoteCategoryRead | None = None
    tags: list[str]
    source_type: TeamNoteSourceType
    source_note_id: str | None
    source_author_id: str | None
    source_author: UserRead | None = None
    source_submission_id: str | None
    status: TeamNoteStatus
    published_at: datetime
    archived_at: datetime | None
    created_by_id: str | None
    updated_by_id: str | None
    created_at: datetime
    updated_at: datetime
    version_no: int = 1
    my_update_draft_note_id: str | None = None
    my_update_submission_id: str | None = None
    my_update_submission_status: TeamNoteSubmissionStatus | None = None
    permissions: TeamNotePermissions = Field(default_factory=TeamNotePermissions)


class TeamNoteListItem(ApiModel):
    """Knowledge list projection;正文、附件和个人更新状态按详情读取。"""

    id: str
    team_id: str
    title: str
    category_id: str | None
    category: TeamNoteCategoryRead | None = None
    tags: list[str]
    source_type: TeamNoteSourceType
    source_note_id: str | None
    source_author_id: str | None
    source_author: UserRead | None = None
    source_submission_id: str | None
    status: TeamNoteStatus
    published_at: datetime
    archived_at: datetime | None
    created_at: datetime
    updated_at: datetime
    permissions: TeamNotePermissions = Field(default_factory=TeamNotePermissions)


class TeamNoteSubmissionCreate(ApiModel):
    source_note_id: str
    submission_type: TeamNoteSubmissionType = Field(default=TeamNoteSubmissionType.CREATE, alias="type")
    target_team_note_id: str | None = None
    proposed_category_id: str | None = Field(default=None, alias="categoryId")
    proposed_tags_json: list[str] = Field(default_factory=list, alias="tags")
    submission_message: str | None = Field(default=None, max_length=2000, alias="message")

    @model_validator(mode="after")
    def validate_submission(self) -> "TeamNoteSubmissionCreate":
        self.proposed_tags_json = list(dict.fromkeys(tag.strip() for tag in self.proposed_tags_json if tag.strip()))
        if self.submission_type == TeamNoteSubmissionType.UPDATE and not self.target_team_note_id:
            raise ValueError("更新投稿必须选择目标团队知识")
        if self.submission_type == TeamNoteSubmissionType.CREATE and self.target_team_note_id:
            raise ValueError("新建投稿不能指定目标团队知识")
        return self


class NoteSubmissionRequest(ApiModel):
    submission_type: TeamNoteSubmissionType = Field(default=TeamNoteSubmissionType.CREATE, alias="type")
    target_team_note_id: str | None = None
    proposed_category_id: str | None = Field(default=None, alias="categoryId")
    proposed_tags_json: list[str] = Field(default_factory=list, alias="tags")
    submission_message: str | None = Field(default=None, max_length=2000, alias="message")

    @model_validator(mode="after")
    def validate_submission(self) -> "NoteSubmissionRequest":
        self.proposed_tags_json = list(dict.fromkeys(tag.strip() for tag in self.proposed_tags_json if tag.strip()))
        if self.submission_type == TeamNoteSubmissionType.UPDATE and not self.target_team_note_id:
            raise ValueError("更新投稿必须选择目标团队知识")
        if self.submission_type == TeamNoteSubmissionType.CREATE and self.target_team_note_id:
            raise ValueError("新建投稿不能指定目标团队知识")
        return self


class TeamNoteSubmissionReview(ApiModel):
    reason: str | None = Field(default=None, max_length=2000)
    reason_code: str | None = Field(default=None, max_length=64)
    title: str | None = Field(default=None, min_length=1, max_length=500)
    category_id: str | None = None
    tags: list[str] | None = Field(default=None, max_length=20)


class TeamNoteSubmissionRead(ApiModel):
    id: str
    team_id: str
    source_note_id: str
    applicant_id: str
    source_author_id: str
    applicant: UserRead
    submission_type: TeamNoteSubmissionType
    target_team_note_id: str | None
    base_team_note_version_no: int | None
    base_team_note_snapshot_hash: str | None
    snapshot_title: str
    snapshot_content_json: dict[str, Any]
    snapshot_plain_text: str
    snapshot_attachment_ids: list[str]
    snapshot_attachments: list[AttachmentRead] = Field(default_factory=list)
    snapshot_hash: str
    proposed_category_id: str | None
    proposed_tags_json: list[str]
    submission_message: str | None
    status: TeamNoteSubmissionStatus
    reviewer_id: str | None
    reviewed_at: datetime | None
    review_reason: str | None
    review_reason_code: str | None
    review_comment: str | None
    revision_no: int
    approved_team_note_id: str | None
    created_at: datetime
    updated_at: datetime


class TeamNoteVersionRead(ApiModel):
    id: str
    team_note_id: str
    version_no: int
    title: str
    content_json: dict[str, Any]
    plain_text: str
    attachment_ids: list[str]
    category_id: str | None
    tags: list[str]
    change_type: str
    changed_by_id: str | None
    source_submission_id: str | None
    created_at: datetime
