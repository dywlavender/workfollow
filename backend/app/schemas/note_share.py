from datetime import datetime

from pydantic import Field

from app.models.note_share import NoteSharePermission, NoteShareStatus
from app.schemas.auth import UserRead
from app.schemas.base import ApiModel
from app.schemas.note import AttachmentRead, NoteRead


class NoteShareCreate(ApiModel):
    identifier: str | None = Field(default=None, min_length=1, max_length=320)
    user_ids: list[str] | None = Field(default=None, max_length=100)
    permission: NoteSharePermission = NoteSharePermission.READ_ONLY


class NoteSharesSync(ApiModel):
    user_ids: list[str] = Field(default_factory=list, max_length=100)


class NoteShareRead(ApiModel):
    id: str
    note_id: str
    team_id: str | None
    shared_by_user_id: str
    shared_with_user_id: str
    permission: NoteSharePermission
    status: NoteShareStatus
    created_at: datetime
    revoked_at: datetime | None
    shared_with: UserRead


class SharedNoteRead(NoteRead):
    attachments: list[AttachmentRead] = Field(default_factory=list)
    shared_by_user_id: str
    shared_by: UserRead
    permission: NoteSharePermission
