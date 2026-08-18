from datetime import datetime

from pydantic import Field

from app.models.auth import SystemRole, UserStatus
from app.schemas.base import ApiModel


class UserCreate(ApiModel):
    username: str = Field(min_length=3, max_length=80)
    password: str = Field(min_length=8, max_length=128)
    nickname: str | None = Field(default=None, min_length=1, max_length=120)


class LoginRequest(ApiModel):
    identifier: str = Field(min_length=1, max_length=320)
    password: str = Field(min_length=1, max_length=128)


class UserRead(ApiModel):
    id: str
    username: str
    nickname: str
    avatar_url: str | None
    system_role: SystemRole
    can_create_team: bool
    onboarding_version: int
    status: UserStatus
    created_at: datetime
    last_login_at: datetime | None


class AuthResponse(ApiModel):
    user: UserRead
    is_first_run: bool = False
    guide_note_id: str | None = None
    starter_task_id: str | None = None


class AdminUserPermissionsUpdate(ApiModel):
    can_create_team: bool


class PasswordResetRead(ApiModel):
    user_id: str
    initial_password: str
