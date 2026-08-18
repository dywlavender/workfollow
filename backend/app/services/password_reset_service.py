from sqlalchemy import update
from sqlalchemy.orm import Session

from app.models.auth import AuthSession, User
from app.models.todo import local_now
from app.services.auth_service import password_hash


INITIAL_PASSWORD = "11111111"


def reset_user_password(db: Session, target: User) -> None:
    """Reset the password and revoke every existing session in one transaction."""

    target.password_hash = password_hash.hash(INITIAL_PASSWORD)
    db.execute(
        update(AuthSession)
        .where(AuthSession.user_id == target.id, AuthSession.revoked_at.is_(None))
        .values(revoked_at=local_now())
    )
    db.flush()
