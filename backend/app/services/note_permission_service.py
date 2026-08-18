from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.note import Note
from app.models.note_share import NoteShare, NoteShareStatus
from app.models.team import Team, TeamMember, TeamMemberRole, TeamMemberStatus, TeamStatus
from app.models.team_note import TeamNote
from app.services.system_permission_service import user_is_root


def _active_team_exists(db: Session, team_id: str) -> bool:
    return db.scalar(select(Team.id).where(Team.id == team_id, Team.status == TeamStatus.ACTIVE)) is not None


def membership(db: Session, user_id: str, team_id: str | None = None) -> TeamMember | None:
    statement = select(TeamMember).join(Team, Team.id == TeamMember.team_id).where(
        TeamMember.user_id == user_id,
        TeamMember.status == TeamMemberStatus.ACTIVE,
        Team.status == TeamStatus.ACTIVE,
    )
    if team_id is not None:
        statement = statement.where(TeamMember.team_id == team_id)
    return db.scalar(statement.order_by(TeamMember.joined_at.desc()))


def can_view_personal_note(db: Session, note: Note, user_id: str) -> bool:
    if note.deleted_at is not None:
        return False
    if note.owner_id == user_id:
        return True
    share = db.scalar(select(NoteShare).where(
        NoteShare.note_id == note.id,
        NoteShare.shared_with_user_id == user_id,
        NoteShare.status == NoteShareStatus.ACTIVE,
    ))
    if share is None or share.team_id is None:
        return False
    return membership(db, user_id, share.team_id) is not None


def can_edit_personal_note(note: Note, user_id: str) -> bool:
    return note.deleted_at is None and note.owner_id == user_id


def can_share_personal_note(note: Note, user_id: str) -> bool:
    return can_edit_personal_note(note, user_id)


def can_view_shared_note(db: Session, note_id: str, user_id: str) -> bool:
    note = db.get(Note, note_id)
    return note is not None and note.owner_id != user_id and can_view_personal_note(db, note, user_id)


def can_submit_to_knowledge(db: Session, note: Note, user_id: str, team_id: str) -> bool:
    return can_edit_personal_note(note, user_id) and (
        (user_is_root(db, user_id) and _active_team_exists(db, team_id))
        or membership(db, user_id, team_id) is not None
    )


def can_review_submission(db: Session, user_id: str, team_id: str) -> bool:
    if user_is_root(db, user_id):
        return _active_team_exists(db, team_id)
    member = membership(db, user_id, team_id)
    return member is not None and member.role in (TeamMemberRole.OWNER, TeamMemberRole.ADMIN)


def can_view_team_note(db: Session, note: TeamNote, user_id: str) -> bool:
    if user_is_root(db, user_id):
        return _active_team_exists(db, note.team_id)
    return membership(db, user_id, note.team_id) is not None


def can_edit_team_note(db: Session, note: TeamNote, user_id: str) -> bool:
    if user_is_root(db, user_id):
        return _active_team_exists(db, note.team_id)
    member = membership(db, user_id, note.team_id)
    return member is not None and member.role in (TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
