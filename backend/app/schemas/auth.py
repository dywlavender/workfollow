from datetime import datetime

from pydantic import Field, field_validator

from app.models.auth import SystemRole, UserStatus
from app.schemas.base import ApiModel


class UserCreate(ApiModel):
    username: str = Field(min_length=3, max_length=80)
    password: str = Field(min_length=8, max_length=128)
    nickname: str | None = Field(default=None, min_length=1, max_length=120)


class LoginRequest(ApiModel):
    identifier: str = Field(min_length=1, max_length=320)
    password: str = Field(min_length=1, max_length=128)


class UserProfileUpdate(ApiModel):
    nickname: str = Field(min_length=1, max_length=120)

    @field_validator("nickname")
    @classmethod
    def normalize_nickname(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("昵称不能为空")
        return normalized


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


class AgentTokenStatus(ApiModel):
    enabled: bool
    created_at: datetime | None = None
    last_used_at: datetime | None = None


class AgentTokenCreated(AgentTokenStatus):
    token: str


class AgentActionRead(ApiModel):
    id: str
    method: str
    path: str
    status_code: int
    resource_type: str | None
    resource_id: str | None
    created_at: datetime


class AdminUserPermissionsUpdate(ApiModel):
    can_create_team: bool


class AdminUserSystemRoleUpdate(ApiModel):
    system_role: SystemRole


class PasswordResetRead(ApiModel):
    user_id: str
    initial_password: str
