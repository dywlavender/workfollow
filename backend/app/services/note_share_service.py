from __future__ import annotations

from fastapi import HTTPException
from sqlalchemy import Text as SqlText
from sqlalchemy import cast, or_, select
from sqlalchemy.orm import Session, aliased, joinedload, selectinload

from app.models.auth import User, UserStatus
from app.models.note import Note
from app.models.note_share import NoteShare, NoteSharePermission, NoteShareStatus
from app.models.team import Team, TeamMember, TeamMemberStatus, TeamStatus
from app.models.todo import local_now
from app.schemas.note_share import NoteShareCreate
from app.services import team_service


def get_share_or_404(db: Session, note_id: str, share_id: str, owner_id: str) -> NoteShare:
    share = db.scalar(
        select(NoteShare)
        .options(joinedload(NoteShare.shared_with))
        .where(
            (NoteShare.id == share_id) | (NoteShare.shared_with_user_id == share_id),
            NoteShare.note_id == note_id,
            NoteShare.shared_by_user_id == owner_id,
            NoteShare.status == NoteShareStatus.ACTIVE,
        )
    )
    if share is None:
        raise HTTPException(status_code=404, detail="Note share not found")
    return share


def list_note_shares(
    db: Session, note_id: str, owner_id: str, *, include_revoked: bool = False
) -> list[NoteShare]:
    statement = (
        select(NoteShare)
        .options(joinedload(NoteShare.shared_with))
        .where(
            NoteShare.note_id == note_id,
            NoteShare.shared_by_user_id == owner_id,
        )
    )
    if not include_revoked:
        statement = statement.where(NoteShare.status == NoteShareStatus.ACTIVE)
    return list(db.scalars(statement.order_by(NoteShare.created_at.desc())))


def create_note_share(db: Session, note: Note, owner_id: str, payload: NoteShareCreate) -> NoteShare:
    if payload.permission != NoteSharePermission.READ_ONLY:
        raise HTTPException(status_code=422, detail="目前只支持只读共享")
    if not payload.identifier:
        raise HTTPException(status_code=422, detail="缺少分享成员")
    target = team_service.find_user(db, payload.identifier)
    if target.id == owner_id:
        raise HTTPException(status_code=422, detail="不能共享给自己")
    team_id = _common_active_team(db, owner_id, target.id)
    if team_id is None:
        raise HTTPException(status_code=422, detail="只能分享给当前团队成员")
    existing = db.scalar(
        select(NoteShare).where(NoteShare.note_id == note.id, NoteShare.shared_with_user_id == target.id)
    )
    if existing is not None and existing.status == NoteShareStatus.ACTIVE:
        raise HTTPException(status_code=409, detail="该用户已经拥有共享权限")
    if existing is None:
        share = NoteShare(
            note_id=note.id,
            team_id=team_id,
            shared_by_user_id=owner_id,
            shared_with_user_id=target.id,
            permission=NoteSharePermission.READ_ONLY,
            status=NoteShareStatus.ACTIVE,
        )
        db.add(share)
    else:
        share = existing
        share.status = NoteShareStatus.ACTIVE
        share.revoked_at = None
        share.permission = NoteSharePermission.READ_ONLY
        share.team_id = team_id
    db.commit()
    db.refresh(share)
    return get_share_or_404(db, note.id, share.id, owner_id)


def revoke_note_share(db: Session, share: NoteShare) -> None:
    share.status = NoteShareStatus.REVOKED
    share.revoked_at = local_now()
    db.commit()


def can_read_shared_note(db: Session, note_id: str, user_id: str) -> bool:
    owner_membership = aliased(TeamMember)
    target_membership = aliased(TeamMember)
    return (
        db.scalar(
            select(NoteShare.id)
            .join(Note, Note.id == NoteShare.note_id)
            .join(User, User.id == NoteShare.shared_with_user_id)
            .join(Team, Team.id == NoteShare.team_id)
            .join(target_membership, target_membership.team_id == NoteShare.team_id)
            .join(owner_membership, owner_membership.team_id == NoteShare.team_id)
            .where(
                NoteShare.note_id == note_id,
                NoteShare.shared_with_user_id == user_id,
                NoteShare.status == NoteShareStatus.ACTIVE,
                target_membership.user_id == user_id,
                target_membership.status == TeamMemberStatus.ACTIVE,
                owner_membership.user_id == NoteShare.shared_by_user_id,
                owner_membership.status == TeamMemberStatus.ACTIVE,
                Team.status == TeamStatus.ACTIVE,
                User.status == UserStatus.ACTIVE,
                Note.deleted_at.is_(None),
            )
        )
        is not None
    )


def get_shared_note_or_404(db: Session, note_id: str, user_id: str) -> tuple[Note, NoteShare]:
    owner_membership = aliased(TeamMember)
    target_membership = aliased(TeamMember)
    row = db.execute(
        select(Note, NoteShare)
        .options(selectinload(Note.attachments))
        .join(NoteShare, NoteShare.note_id == Note.id)
        .join(User, User.id == NoteShare.shared_with_user_id)
        .join(Team, Team.id == NoteShare.team_id)
        .join(target_membership, target_membership.team_id == NoteShare.team_id)
        .join(owner_membership, owner_membership.team_id == NoteShare.team_id)
        .where(
            Note.id == note_id,
            NoteShare.shared_with_user_id == user_id,
            NoteShare.status == NoteShareStatus.ACTIVE,
            target_membership.user_id == user_id,
            target_membership.status == TeamMemberStatus.ACTIVE,
            owner_membership.user_id == NoteShare.shared_by_user_id,
            owner_membership.status == TeamMemberStatus.ACTIVE,
            Team.status == TeamStatus.ACTIVE,
            User.status == UserStatus.ACTIVE,
            Note.deleted_at.is_(None),
        )
    ).first()
    if row is None:
        raise HTTPException(status_code=404, detail="Shared note not found")
    return row


def list_shared_notes(db: Session, user_id: str, q: str | None = None) -> list[tuple[Note, NoteShare]]:
    owner_membership = aliased(TeamMember)
    target_membership = aliased(TeamMember)
    statement = (
        select(Note, NoteShare)
        .join(NoteShare, NoteShare.note_id == Note.id)
        .join(User, User.id == NoteShare.shared_by_user_id)
        .join(Team, Team.id == NoteShare.team_id)
        .join(target_membership, target_membership.team_id == NoteShare.team_id)
        .join(owner_membership, owner_membership.team_id == NoteShare.team_id)
        .options(joinedload(NoteShare.shared_by), selectinload(Note.attachments))
        .where(
            NoteShare.shared_with_user_id == user_id,
            NoteShare.status == NoteShareStatus.ACTIVE,
            target_membership.user_id == user_id,
            target_membership.status == TeamMemberStatus.ACTIVE,
            owner_membership.user_id == NoteShare.shared_by_user_id,
            owner_membership.status == TeamMemberStatus.ACTIVE,
            Team.status == TeamStatus.ACTIVE,
            User.status == UserStatus.ACTIVE,
            Note.deleted_at.is_(None),
        )
    )
    if q and q.strip():
        pattern = f"%{q.strip()}%"
        statement = statement.where(or_(
            Note.title.like(pattern),
            Note.plain_text.like(pattern),
            cast(Note.tags, SqlText).like(pattern),
        ))
    return list(db.execute(statement.order_by(Note.updated_at.desc())))


def _common_active_team(db: Session, owner_id: str, target_id: str) -> str | None:
    owner_membership = TeamMember.__table__.alias("owner_membership")
    target_membership = TeamMember.__table__.alias("target_membership")
    return db.scalar(
        select(owner_membership.c.team_id)
        .join(Team, Team.id == owner_membership.c.team_id)
        .join(target_membership, target_membership.c.team_id == owner_membership.c.team_id)
        .where(
            owner_membership.c.user_id == owner_id,
            owner_membership.c.status == TeamMemberStatus.ACTIVE,
            target_membership.c.user_id == target_id,
            target_membership.c.status == TeamMemberStatus.ACTIVE,
            Team.status == TeamStatus.ACTIVE,
        )
        .order_by(owner_membership.c.joined_at.desc())
    )


def sync_note_shares(db: Session, note: Note, owner_id: str, user_ids: list[str]) -> list[NoteShare]:
    desired = set(dict.fromkeys(user_ids))
    if owner_id in desired:
        raise HTTPException(status_code=422, detail="不能共享给自己")
    targets = list(db.scalars(
        select(User).where(User.id.in_(desired), User.status == UserStatus.ACTIVE)
    )) if desired else []
    if len(targets) != len(desired):
        raise HTTPException(status_code=422, detail="分享成员不存在")
    team_by_user = {target.id: _common_active_team(db, owner_id, target.id) for target in targets}
    if any(team_id is None for team_id in team_by_user.values()):
        raise HTTPException(status_code=422, detail="只能分享给当前团队成员")

    existing = {
        share.shared_with_user_id: share
        for share in db.scalars(select(NoteShare).where(NoteShare.note_id == note.id))
    }
    now = local_now()
    for target_id, share in existing.items():
        if target_id not in desired and share.status == NoteShareStatus.ACTIVE:
            share.status = NoteShareStatus.REVOKED
            share.revoked_at = now
    for target in targets:
        share = existing.get(target.id)
        if share is None:
            db.add(NoteShare(
                note_id=note.id,
                team_id=team_by_user[target.id],
                shared_by_user_id=owner_id,
                shared_with_user_id=target.id,
                permission=NoteSharePermission.READ_ONLY,
                status=NoteShareStatus.ACTIVE,
            ))
        else:
            share.team_id = team_by_user[target.id]
            share.status = NoteShareStatus.ACTIVE
            share.revoked_at = None
    db.commit()
    return list_note_shares(db, note.id, owner_id)
