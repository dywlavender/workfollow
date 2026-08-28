from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from fastapi import HTTPException
from sqlalchemy import String, and_, delete, func, or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, aliased, joinedload, load_only

from app.core.config import Settings
from app.models.note import Attachment, Note
from app.models.note_share import NoteShare, NoteShareStatus
from app.models.resource_relation import ResourceRelation, ResourceType
from app.models.team import Team, TeamMember, TeamMemberRole, TeamMemberStatus, TeamStatus
from app.models.team_note import (
    SubmissionFileAccess,
    TeamFileAccess,
    TeamNote,
    TeamNoteCategory,
    TeamNoteSourceType,
    TeamNoteStatus,
    TeamNoteSubmission,
    TeamNoteSubmissionStatus,
    TeamNoteSubmissionType,
    TeamNoteVersion,
)
from app.models.todo import TaskFileAccess, Todo, local_now
from app.schemas.note import AttachmentRead
from app.schemas.team import TeamNoteCreate, TeamNoteSubmissionCreate, TeamNoteSubmissionReview, TeamNoteUpdate
from app.services import note_permission_service, note_service, resource_relation_service, team_service
from app.services import search_index_service
from app.services.content_projection import content_json_semantically_equal
from app.services.note_service import content_to_plain_text, get_note_or_404
from app.services.system_permission_service import user_is_root


TERMINAL_SUBMISSION_STATUSES = {
    TeamNoteSubmissionStatus.APPROVED,
    TeamNoteSubmissionStatus.REJECTED,
    TeamNoteSubmissionStatus.WITHDRAWN,
}


def get_team_note_or_404(db: Session, team_id: str, note_id: str, include_archived: bool = True) -> TeamNote:
    statement = select(TeamNote).options(
        joinedload(TeamNote.category), joinedload(TeamNote.source_author)
    ).where(TeamNote.team_id == team_id, TeamNote.id == note_id)
    if not include_archived:
        statement = statement.where(TeamNote.status == TeamNoteStatus.PUBLISHED)
    note = db.scalar(statement)
    if note is None:
        raise HTTPException(status_code=404, detail="Team knowledge not found")
    return note


def list_team_notes(
    db: Session,
    team_id: str,
    limit: int = 100,
    offset: int = 0,
    q: str | None = None,
    category_id: str | None = None,
    include_archived: bool = False,
    summary: bool = False,
) -> list[TeamNote]:
    options = [joinedload(TeamNote.category), joinedload(TeamNote.source_author)]
    if summary:
        options.append(load_only(
            TeamNote.id,
            TeamNote.team_id,
            TeamNote.title,
            TeamNote.category_id,
            TeamNote.tags,
            TeamNote.source_type,
            TeamNote.source_note_id,
            TeamNote.source_author_id,
            TeamNote.source_submission_id,
            TeamNote.status,
            TeamNote.published_at,
            TeamNote.archived_at,
            TeamNote.created_at,
            TeamNote.updated_at,
        ))
    statement = select(TeamNote).options(*options).where(TeamNote.team_id == team_id)
    if not include_archived:
        statement = statement.where(TeamNote.status == TeamNoteStatus.PUBLISHED)
    if category_id:
        statement = statement.where(TeamNote.category_id == category_id)
    if q and q.strip():
        pattern = f"%{q.strip()}%"
        statement = statement.outerjoin(TeamNoteCategory).where(or_(
            TeamNote.title.like(pattern),
            TeamNote.plain_text.like(pattern),
            TeamNoteCategory.name.like(pattern),
            func.cast(TeamNote.tags, String).like(pattern),
        ))
    return list(db.scalars(
        statement.order_by(TeamNote.updated_at.desc()).limit(limit).offset(offset)
    ).unique())


def list_categories(db: Session, team_id: str) -> list[TeamNoteCategory]:
    return list(db.scalars(select(TeamNoteCategory).where(
        TeamNoteCategory.team_id == team_id
    ).order_by(TeamNoteCategory.sort_order, TeamNoteCategory.name)))


def create_category(db: Session, team_id: str, name: str, sort_order: int) -> TeamNoteCategory:
    category = TeamNoteCategory(team_id=team_id, name=name, sort_order=sort_order)
    db.add(category)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(status_code=409, detail="知识分类名称已存在") from exc
    db.refresh(category)
    return category


def get_category_or_404(db: Session, team_id: str, category_id: str) -> TeamNoteCategory:
    category = db.scalar(select(TeamNoteCategory).where(
        TeamNoteCategory.id == category_id, TeamNoteCategory.team_id == team_id
    ))
    if category is None:
        raise HTTPException(status_code=404, detail="知识分类不存在")
    return category


def update_category(
    db: Session, category: TeamNoteCategory, name: str | None = None, sort_order: int | None = None
) -> TeamNoteCategory:
    if name is not None:
        category.name = name
    if sort_order is not None:
        category.sort_order = sort_order
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(status_code=409, detail="知识分类名称已存在") from exc
    db.refresh(category)
    search_index_service.sync_team_category(db, category.team_id, category.id)
    db.commit()
    return category


def delete_category(db: Session, category: TeamNoteCategory) -> None:
    affected_notes = list(db.scalars(select(TeamNote).where(TeamNote.category_id == category.id)))
    db.execute(update(TeamNote).where(
        TeamNote.team_id == category.team_id,
        TeamNote.category_id == category.id,
    ).values(category_id=None))
    db.execute(update(TeamNoteSubmission).where(
        TeamNoteSubmission.team_id == category.team_id,
        TeamNoteSubmission.proposed_category_id == category.id,
    ).values(proposed_category_id=None))
    db.delete(category)
    for note in affected_notes:
        note.category_id = None
        search_index_service.upsert_team_note(db, note)
    db.commit()


def _validate_category(db: Session, team_id: str, category_id: str | None) -> str | None:
    if category_id is None:
        return None
    exists = db.scalar(select(TeamNoteCategory.id).where(
        TeamNoteCategory.id == category_id, TeamNoteCategory.team_id == team_id
    ))
    if exists is None:
        raise HTTPException(status_code=422, detail="知识分类不属于当前团队")
    return category_id


def _extract_attachment_ids(value: Any) -> set[str]:
    found: set[str] = set()
    if isinstance(value, dict):
        attrs = value.get("attrs")
        if isinstance(attrs, dict):
            for key in ("fileId", "attachmentId", "file_id", "attachment_id"):
                candidate = attrs.get(key)
                if isinstance(candidate, str) and candidate:
                    found.add(candidate)
            src = attrs.get("src")
            if isinstance(src, str) and "/api/attachments/" in src:
                found.add(src.rsplit("/api/attachments/", 1)[-1].split("?", 1)[0].split("#", 1)[0])
        for child in value.values():
            found.update(_extract_attachment_ids(child))
    elif isinstance(value, list):
        for child in value:
            found.update(_extract_attachment_ids(child))
    return found


def _snapshot_attachment_ids(db: Session, source: Note) -> list[str]:
    attachments = list(db.scalars(select(Attachment).where(
        Attachment.note_id == source.id, Attachment.owner_id == source.owner_id
    ).order_by(Attachment.created_at)))
    owned = {attachment.id for attachment in attachments}
    referenced = _extract_attachment_ids(source.content_json)
    if not referenced.issubset(owned):
        raise HTTPException(status_code=403, detail="笔记正文引用了无权访问的文件")
    return [attachment.id for attachment in attachments]


def _snapshot_hash(title: str, content: dict[str, Any], attachment_ids: list[str]) -> str:
    payload = json.dumps(
        {"title": title, "content": content, "attachments": attachment_ids},
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def team_note_version_info(db: Session, note: TeamNote) -> tuple[int, str]:
    """Return the latest persisted version and its current content fingerprint."""

    version_no = db.scalar(select(func.max(TeamNoteVersion.version_no)).where(
        TeamNoteVersion.team_note_id == note.id
    )) or 1
    return version_no, _snapshot_hash(note.title, note.content_json, list(note.attachment_ids or []))


def _latest_update_submission(
    db: Session,
    team_id: str,
    applicant_id: str,
    target_team_note_id: str,
    source_note_id: str | None = None,
) -> TeamNoteSubmission | None:
    statement = select(TeamNoteSubmission).where(
        TeamNoteSubmission.team_id == team_id,
        TeamNoteSubmission.applicant_id == applicant_id,
        TeamNoteSubmission.submission_type == TeamNoteSubmissionType.UPDATE,
        TeamNoteSubmission.target_team_note_id == target_team_note_id,
    )
    if source_note_id is not None:
        statement = statement.where(TeamNoteSubmission.source_note_id == source_note_id)
    return db.scalar(statement.order_by(TeamNoteSubmission.updated_at.desc()))


def update_state_for_team_note(db: Session, note: TeamNote, user_id: str) -> dict[str, Any]:
    """Expose only the current user's update draft/submission state for a team note."""

    submission = db.scalar(select(TeamNoteSubmission).where(
        TeamNoteSubmission.team_id == note.team_id,
        TeamNoteSubmission.applicant_id == user_id,
        TeamNoteSubmission.submission_type == TeamNoteSubmissionType.UPDATE,
        TeamNoteSubmission.target_team_note_id == note.id,
        TeamNoteSubmission.status.in_(
            (TeamNoteSubmissionStatus.PENDING, TeamNoteSubmissionStatus.NEEDS_REVISION)
        ),
    ).order_by(TeamNoteSubmission.updated_at.desc()))
    draft_id = submission.source_note_id if submission is not None else db.scalar(
        select(Note.id).where(
            Note.owner_id == user_id,
            Note.copied_from_team_note_id == note.id,
            Note.is_knowledge_update_draft.is_(True),
            Note.deleted_at.is_(None),
        ).order_by(Note.updated_at.desc())
    )
    return {
        "my_update_draft_note_id": draft_id,
        "my_update_submission_id": submission.id if submission else None,
        "my_update_submission_status": submission.status if submission else None,
    }


def team_note_version_numbers(db: Session, note_ids: list[str]) -> dict[str, int]:
    unique_ids = list(dict.fromkeys(note_ids))
    if not unique_ids:
        return {}
    rows = db.execute(
        select(TeamNoteVersion.team_note_id, func.max(TeamNoteVersion.version_no))
        .where(TeamNoteVersion.team_note_id.in_(unique_ids))
        .group_by(TeamNoteVersion.team_note_id)
    ).all()
    return {note_id: int(version_no or 1) for note_id, version_no in rows}


def update_states_for_team_notes(
    db: Session, notes: list[TeamNote], user_id: str
) -> dict[str, dict[str, Any]]:
    """Read update workflow state for a list in two set-based queries."""

    if not notes:
        return {}
    note_ids = [note.id for note in notes]
    submissions = db.scalars(select(TeamNoteSubmission).where(
        TeamNoteSubmission.team_id == notes[0].team_id,
        TeamNoteSubmission.applicant_id == user_id,
        TeamNoteSubmission.submission_type == TeamNoteSubmissionType.UPDATE,
        TeamNoteSubmission.target_team_note_id.in_(note_ids),
        TeamNoteSubmission.status.in_(
            (TeamNoteSubmissionStatus.PENDING, TeamNoteSubmissionStatus.NEEDS_REVISION)
        ),
    )).all()
    latest_submission: dict[str, TeamNoteSubmission] = {}
    for submission in submissions:
        target_id = submission.target_team_note_id
        if target_id is None or (
            target_id in latest_submission
            and latest_submission[target_id].updated_at >= submission.updated_at
        ):
            continue
        latest_submission[target_id] = submission

    draft_rows = db.execute(select(Note.id, Note.copied_from_team_note_id).where(
        Note.owner_id == user_id,
        Note.copied_from_team_note_id.in_(note_ids),
        Note.is_knowledge_update_draft.is_(True),
        Note.deleted_at.is_(None),
    ).order_by(Note.updated_at.desc())).all()
    latest_draft: dict[str, str] = {}
    for draft_id, target_id in draft_rows:
        if target_id is not None and target_id not in latest_draft:
            latest_draft[target_id] = draft_id

    return {
        note.id: {
            "my_update_draft_note_id": latest_submission.get(note.id).source_note_id
            if latest_submission.get(note.id) is not None else latest_draft.get(note.id),
            "my_update_submission_id": latest_submission.get(note.id).id
            if latest_submission.get(note.id) is not None else None,
            "my_update_submission_status": latest_submission.get(note.id).status
            if latest_submission.get(note.id) is not None else None,
        }
        for note in notes
    }


def copy_team_note_to_personal(
    db: Session,
    note: TeamNote,
    owner_id: str,
    settings: Settings,
    *,
    is_update_draft: bool = False,
) -> Note:
    """Copy a published team note and remember the exact version it came from."""

    attachment_ids = list(note.attachment_ids or [])
    attachments_by_id = {
        item.id: item for item in db.scalars(select(Attachment).where(Attachment.id.in_(attachment_ids)))
    } if attachment_ids else {}
    if len(attachments_by_id) != len(set(attachment_ids)):
        raise HTTPException(status_code=409, detail="知识附件记录不完整，无法复制")
    version_no, snapshot_hash = team_note_version_info(db, note)
    return note_service.copy_note_with_attachments(
        db,
        title=note.title,
        content_json=note.content_json,
        plain_text=note.plain_text,
        source_attachments=[attachments_by_id[item] for item in attachment_ids if item in attachments_by_id],
        owner_id=owner_id,
        settings=settings,
        copied_from_team_note_id=note.id,
        is_knowledge_update_draft=is_update_draft,
        copied_from_team_note_version_no=version_no,
        copied_from_team_note_snapshot_hash=snapshot_hash,
    )


def get_or_create_update_draft(
    db: Session,
    note: TeamNote,
    owner_id: str,
    settings: Settings,
) -> Note:
    """Reuse one safe update draft per user/target, otherwise create one."""

    current_version_no, current_hash = team_note_version_info(db, note)
    active_submission = _latest_update_submission(db, note.team_id, owner_id, note.id)
    if active_submission and active_submission.status in {
        TeamNoteSubmissionStatus.PENDING,
        TeamNoteSubmissionStatus.NEEDS_REVISION,
    }:
        source = db.get(Note, active_submission.source_note_id)
        if source is None or source.owner_id != owner_id or source.deleted_at is not None:
            raise HTTPException(status_code=409, detail="已有更新投稿，但原笔记已不可用")
        return source

    draft = db.scalar(select(Note).where(
        Note.owner_id == owner_id,
        Note.copied_from_team_note_id == note.id,
        Note.is_knowledge_update_draft.is_(True),
        Note.deleted_at.is_(None),
    ).order_by(Note.updated_at.desc()))
    if draft is not None:
        latest = _latest_update_submission(db, note.team_id, owner_id, note.id, draft.id)
        if latest is None and (
            draft.copied_from_team_note_version_no == current_version_no
            and draft.copied_from_team_note_snapshot_hash == current_hash
        ):
            return draft
        if latest is not None and latest.status == TeamNoteSubmissionStatus.NEEDS_REVISION and (
            latest.base_team_note_version_no == current_version_no
            and latest.base_team_note_snapshot_hash == current_hash
        ):
            return draft
        draft.is_knowledge_update_draft = False
        db.flush()

    # A manually copied note can become the update draft if it still represents
    # the same team-note version and has not already been used for an update.
    candidate = db.scalar(select(Note).where(
        Note.owner_id == owner_id,
        Note.copied_from_team_note_id == note.id,
        Note.is_knowledge_update_draft.is_(False),
        Note.deleted_at.is_(None),
        ~select(TeamNoteSubmission.id).where(
            TeamNoteSubmission.source_note_id == Note.id,
            TeamNoteSubmission.submission_type == TeamNoteSubmissionType.UPDATE,
            TeamNoteSubmission.target_team_note_id == note.id,
        ).exists(),
        Note.copied_from_team_note_version_no == current_version_no,
        Note.copied_from_team_note_snapshot_hash == current_hash,
    ).order_by(Note.updated_at.desc()))
    if candidate is not None:
        candidate.is_knowledge_update_draft = True
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            draft = db.scalar(select(Note).where(
                Note.owner_id == owner_id,
                Note.copied_from_team_note_id == note.id,
                Note.is_knowledge_update_draft.is_(True),
                Note.deleted_at.is_(None),
            ).order_by(Note.updated_at.desc()))
            if draft is not None:
                return draft
            raise
        return candidate

    try:
        return copy_team_note_to_personal(db, note, owner_id, settings, is_update_draft=True)
    except IntegrityError:
        db.rollback()
        draft = db.scalar(select(Note).where(
            Note.owner_id == owner_id,
            Note.copied_from_team_note_id == note.id,
            Note.is_knowledge_update_draft.is_(True),
            Note.deleted_at.is_(None),
        ).order_by(Note.updated_at.desc()))
        if draft is not None:
            return draft
        raise


def _validate_attachment_ids(
    db: Session,
    attachment_ids: list[str],
    owner_id: str,
    existing_team_note_id: str | None = None,
    team_id: str | None = None,
) -> list[str]:
    unique_ids = list(dict.fromkeys(attachment_ids))
    if not unique_ids:
        return []
    valid_ids = set(db.scalars(select(Attachment.id).where(
        Attachment.id.in_(unique_ids), Attachment.owner_id == owner_id
    )))
    if existing_team_note_id:
        valid_ids.update(db.scalars(select(TeamFileAccess.attachment_id).where(
            TeamFileAccess.team_note_id == existing_team_note_id,
            TeamFileAccess.attachment_id.in_(unique_ids),
        )))
    if team_id and user_is_root(db, owner_id):
        # ROOT may reuse an attachment that is already exposed through the
        # selected team, but must not gain a blanket path into private notes.
        valid_ids.update(db.scalars(
            select(TeamFileAccess.attachment_id)
            .join(Team, Team.id == TeamFileAccess.team_id)
            .where(
                TeamFileAccess.team_id == team_id,
                TeamFileAccess.attachment_id.in_(unique_ids),
                Team.status == TeamStatus.ACTIVE,
            )
        ))
        valid_ids.update(db.scalars(
            select(SubmissionFileAccess.attachment_id)
            .join(TeamNoteSubmission, TeamNoteSubmission.id == SubmissionFileAccess.submission_id)
            .join(Team, Team.id == TeamNoteSubmission.team_id)
            .where(
                TeamNoteSubmission.team_id == team_id,
                TeamNoteSubmission.status.in_(
                    (
                        TeamNoteSubmissionStatus.PENDING,
                        TeamNoteSubmissionStatus.NEEDS_REVISION,
                        TeamNoteSubmissionStatus.APPROVED,
                    )
                ),
                SubmissionFileAccess.attachment_id.in_(unique_ids),
                Team.status == TeamStatus.ACTIVE,
            )
        ))
    if valid_ids != set(unique_ids):
        raise HTTPException(status_code=422, detail="只能引用当前用户有权访问的附件")
    return unique_ids


def attachment_reads(db: Session, attachment_ids: list[str]) -> list[AttachmentRead]:
    if not attachment_ids:
        return []
    by_id = {
        attachment.id: AttachmentRead.model_validate(attachment).model_copy(
            update={"url": f"/api/attachments/{attachment.id}"}
        )
        for attachment in db.scalars(select(Attachment).where(Attachment.id.in_(attachment_ids)))
    }
    return [by_id[item] for item in attachment_ids if item in by_id]


def attachment_read_map(db: Session, attachment_ids: list[str]) -> dict[str, AttachmentRead]:
    unique_ids = list(dict.fromkeys(attachment_ids))
    if not unique_ids:
        return {}
    return {
        attachment.id: AttachmentRead.model_validate(attachment).model_copy(
            update={"url": f"/api/attachments/{attachment.id}"}
        )
        for attachment in db.scalars(select(Attachment).where(Attachment.id.in_(unique_ids)))
    }


def _grant_file_access(db: Session, note: TeamNote, attachment_ids: list[str], granted_by_id: str) -> None:
    existing = set(db.scalars(select(TeamFileAccess.attachment_id).where(TeamFileAccess.team_note_id == note.id)))
    for attachment_id in set(attachment_ids) - existing:
        db.add(TeamFileAccess(
            team_id=note.team_id,
            attachment_id=attachment_id,
            team_note_id=note.id,
            granted_by_id=granted_by_id,
        ))


def _reconcile_file_access(db: Session, note: TeamNote, old_ids: list[str], new_ids: list[str], actor_id: str) -> None:
    removed = set(old_ids) - set(new_ids)
    if removed:
        db.execute(delete(TeamFileAccess).where(
            TeamFileAccess.team_note_id == note.id,
            TeamFileAccess.attachment_id.in_(removed),
        ))
    _grant_file_access(db, note, new_ids, actor_id)


def _record_version(
    db: Session,
    note: TeamNote,
    changed_by_id: str,
    change_type: str,
    source_submission_id: str | None = None,
) -> TeamNoteVersion:
    version_no = (db.scalar(select(func.max(TeamNoteVersion.version_no)).where(
        TeamNoteVersion.team_note_id == note.id
    )) or 0) + 1
    version = TeamNoteVersion(
        team_note_id=note.id,
        version_no=version_no,
        title=note.title,
        content_json=note.content_json,
        plain_text=note.plain_text,
        attachment_ids=list(note.attachment_ids or []),
        category_id=note.category_id,
        tags=list(note.tags or []),
        change_type=change_type,
        changed_by_id=changed_by_id,
        source_submission_id=source_submission_id,
    )
    db.add(version)
    return version


def create_team_note(db: Session, team_id: str, actor_id: str, payload: TeamNoteCreate) -> TeamNote:
    attachment_ids = _validate_attachment_ids(db, payload.attachment_ids, actor_id, team_id=team_id)
    note = TeamNote(
        team_id=team_id,
        title=payload.title,
        content_json=payload.content_json,
        plain_text=payload.plain_text.strip() or content_to_plain_text(payload.content_json),
        attachment_ids=attachment_ids,
        category_id=_validate_category(db, team_id, payload.category_id),
        tags=payload.tags,
        source_type=TeamNoteSourceType.ADMIN_CREATED,
        source_author_id=actor_id,
        status=TeamNoteStatus.PUBLISHED,
        published_at=local_now(),
        created_by_id=actor_id,
        updated_by_id=actor_id,
    )
    db.add(note)
    db.flush()
    _grant_file_access(db, note, attachment_ids, actor_id)
    resource_relation_service.sync_team_note_relations(
        db,
        note.id,
        actor_id,
        resource_relation_service.resource_references_in_document(note.content_json),
    )
    _record_version(db, note, actor_id, "ADMIN_CREATE")
    search_index_service.upsert_team_note(db, note)
    db.commit()
    return get_team_note_or_404(db, team_id, note.id)


def update_team_note(db: Session, note: TeamNote, actor_id: str, payload: TeamNoteUpdate) -> TeamNote:
    changes = payload.model_dump(exclude_unset=True)
    expected_version = changes.pop("base_version_no", None)
    if expected_version is not None:
        current_version, _ = team_note_version_info(db, note)
        if expected_version != current_version:
            raise HTTPException(status_code=409, detail="团队知识已被其他管理员更新，请刷新后重试")
    old_ids = list(note.attachment_ids or [])
    content_provided = "content_json" in changes
    explicit_attachment_ids = "attachment_ids" in changes
    new_ids = changes.pop("attachment_ids", old_ids)
    validated_ids = old_ids
    if not explicit_attachment_ids and content_provided:
        # The collaborative document is authoritative for embedded file
        # references. Keep the SQL access projection in lockstep when an
        # administrator removes or inserts a file node before committing,
        # while preserving standalone attachments that have no node in the
        # editor document. ``attachment_ids`` is an aggregate-level list, so
        # treating it as exactly equal to the document references would drop
        # ordinary downloadable files every time the body is edited.
        referenced_ids = _extract_attachment_ids(changes["content_json"])
        previous_content_ids = _extract_attachment_ids(note.content_json)
        old_id_set = set(old_ids)
        new_ids = [
            item for item in old_ids
            if item not in previous_content_ids or item in referenced_ids
        ]
        new_ids.extend(sorted(referenced_ids - old_id_set))
    if "category_id" in changes:
        changes["category_id"] = _validate_category(db, note.team_id, changes["category_id"])
    if "content_json" in changes and not (changes.get("plain_text") or "").strip():
        changes["plain_text"] = content_to_plain_text(changes["content_json"])
    if explicit_attachment_ids or content_provided:
        validated_ids = _validate_attachment_ids(db, new_ids, actor_id, note.id, team_id=note.team_id)
        changes["attachment_ids"] = validated_ids

    # The body carries the relation identity. Reconcile it before the no-op
    # decision as well: an editor-only block-id change is intentionally ignored
    # for version/notification purposes, but the backlink anchor still needs
    # to follow the current collaborative document.
    projected_content = changes.get("content_json", note.content_json)
    resource_relation_service.sync_team_note_relations(
        db,
        note.id,
        actor_id,
        resource_relation_service.resource_references_in_document(projected_content),
    )

    # A collaborative editor can emit a document snapshot while it is
    # mounting, adding only editor-owned noise such as block ids or null
    # attributes.  Treat that snapshot as a no-op after all derived values
    # (plain text, attachment access and category validation) are resolved.
    # This keeps the version history, updated timestamp, search index and
    # notifications tied to actual administrator changes.
    comparable_changes: dict[str, object] = {}
    for field, value in changes.items():
        current = getattr(note, field)
        equal = (
            content_json_semantically_equal(value, current)
            if field == "content_json" and isinstance(value, dict)
            else value == current
        )
        if not equal:
            comparable_changes[field] = value
    if not comparable_changes:
        db.commit()
        return get_team_note_or_404(db, note.team_id, note.id)
    changes = comparable_changes
    changes["updated_by_id"] = actor_id
    for field, value in changes.items():
        setattr(note, field, value)
    _reconcile_file_access(db, note, old_ids, validated_ids, actor_id)
    # Relation rows were reconciled against the same projected body above.
    _record_version(db, note, actor_id, "ADMIN_EDIT")
    search_index_service.upsert_team_note(db, note)
    db.commit()
    return get_team_note_or_404(db, note.team_id, note.id)


def set_team_note_archived(db: Session, note: TeamNote, actor_id: str, archived: bool) -> TeamNote:
    note.status = TeamNoteStatus.ARCHIVED if archived else TeamNoteStatus.PUBLISHED
    note.archived_at = local_now() if archived else None
    note.updated_by_id = actor_id
    _record_version(db, note, actor_id, "ARCHIVE" if archived else "RESTORE")
    search_index_service.upsert_team_note(db, note)
    db.commit()
    return get_team_note_or_404(db, note.team_id, note.id)


def _attachment_is_referenced_after_team_note_delete(
    db: Session, attachment_id: str, deleted_note_id: str
) -> bool:
    """Keep a binary if any remaining record can still reference it."""
    if db.scalar(select(TeamFileAccess.id).where(TeamFileAccess.attachment_id == attachment_id).limit(1)):
        return True
    if db.scalar(select(SubmissionFileAccess.id).where(SubmissionFileAccess.attachment_id == attachment_id).limit(1)):
        return True
    if db.scalar(select(TaskFileAccess.id).where(TaskFileAccess.attachment_id == attachment_id).limit(1)):
        return True
    # JSON array containment is not consistent between SQLite and PostgreSQL;
    # these deletes are rare, so scan the small reference collections in Python
    # instead of risking an incomplete database-specific predicate.
    if any(attachment_id in (item.attachment_ids or []) for item in db.scalars(
        select(TeamNote).where(TeamNote.id != deleted_note_id)
    )):
        return True
    if any(attachment_id in (item.attachment_ids or []) for item in db.scalars(
        select(TeamNoteVersion).where(TeamNoteVersion.team_note_id != deleted_note_id)
    )):
        return True
    if any(attachment_id in (item.snapshot_attachment_ids or []) for item in db.scalars(
        select(TeamNoteSubmission)
    )):
        return True
    if any(attachment_id in (item.attachment_ids or []) for item in db.scalars(select(Todo))):
        return True
    return False


def delete_archived_team_note(db: Session, note: TeamNote, settings: Settings) -> None:
    """Permanently remove an archived knowledge entry and its team-owned history."""
    if note.status != TeamNoteStatus.ARCHIVED:
        raise HTTPException(status_code=409, detail="只有已归档的团队知识可以彻底删除")
    deleted_note_id = note.id

    active_submission = db.scalar(select(TeamNoteSubmission.id).where(
        TeamNoteSubmission.team_id == note.team_id,
        TeamNoteSubmission.status.in_((
            TeamNoteSubmissionStatus.PENDING,
            TeamNoteSubmissionStatus.NEEDS_REVISION,
        )),
        or_(
            TeamNoteSubmission.target_team_note_id == deleted_note_id,
            TeamNoteSubmission.approved_team_note_id == deleted_note_id,
        ),
    ).limit(1))
    if active_submission is not None:
        raise HTTPException(status_code=409, detail="该知识还有待处理的更新申请，请先处理后再删除")

    # Team knowledge is physically removed below. Retire every graph edge in
    # the same transaction first so references from tasks/notes cannot survive
    # as dangling backlinks after the target row is gone.
    deleted_at = local_now()
    db.execute(update(ResourceRelation).where(
        ResourceRelation.deleted_at.is_(None),
        or_(
            and_(
                ResourceRelation.source_type == ResourceType.TEAM_NOTE,
                ResourceRelation.source_id == deleted_note_id,
            ),
            and_(
                ResourceRelation.target_type == ResourceType.TEAM_NOTE,
                ResourceRelation.target_id == deleted_note_id,
            ),
        ),
    ).values(deleted_at=deleted_at))

    versions = list(db.scalars(select(TeamNoteVersion).where(TeamNoteVersion.team_note_id == deleted_note_id)))
    attachment_ids = set(note.attachment_ids or []) | _extract_attachment_ids(note.content_json)
    for version in versions:
        attachment_ids.update(version.attachment_ids or [])
        attachment_ids.update(_extract_attachment_ids(version.content_json))

    # Keep historical submission records, but remove references to the deleted
    # knowledge so the submission list cannot expose a dangling target.
    db.execute(update(TeamNoteSubmission).where(or_(
        TeamNoteSubmission.target_team_note_id == deleted_note_id,
        TeamNoteSubmission.approved_team_note_id == deleted_note_id,
    )).values(target_team_note_id=None, approved_team_note_id=None))
    db.execute(delete(TeamFileAccess).where(TeamFileAccess.team_note_id == deleted_note_id))
    db.execute(delete(TeamNoteVersion).where(TeamNoteVersion.team_note_id == deleted_note_id))
    search_index_service.remove_source(db, search_index_service.TEAM_SOURCE, deleted_note_id)
    db.delete(note)
    db.flush()

    paths_to_remove: list[Path] = []
    for attachment_id in attachment_ids:
        attachment = db.get(Attachment, attachment_id)
        if attachment is None or attachment.note_id is not None:
            continue
        if _attachment_is_referenced_after_team_note_delete(db, attachment_id, deleted_note_id):
            continue
        paths_to_remove.append(settings.files_dir.parent.parent / attachment.file_path)
        db.delete(attachment)

    db.commit()
    for path in paths_to_remove:
        path.unlink(missing_ok=True)


def _snapshot_submission(db: Session, submission: TeamNoteSubmission, source: Note) -> None:
    attachment_ids = _snapshot_attachment_ids(db, source)
    submission.snapshot_title = source.title
    submission.snapshot_content_json = json.loads(json.dumps(source.content_json))
    submission.snapshot_plain_text = source.plain_text
    submission.snapshot_attachment_ids = attachment_ids
    submission.snapshot_hash = _snapshot_hash(source.title, source.content_json, attachment_ids)
    db.execute(delete(SubmissionFileAccess).where(SubmissionFileAccess.submission_id == submission.id))
    for attachment_id in attachment_ids:
        db.add(SubmissionFileAccess(submission_id=submission.id, attachment_id=attachment_id))


def _assert_submission_target_current(db: Session, submission: TeamNoteSubmission, target: TeamNote) -> None:
    if submission.base_team_note_version_no is None or not submission.base_team_note_snapshot_hash:
        raise HTTPException(status_code=409, detail="更新投稿缺少目标版本，请重新基于最新知识创建草稿")
    current_version_no, current_hash = team_note_version_info(db, target)
    if (
        submission.base_team_note_version_no != current_version_no
        or submission.base_team_note_snapshot_hash != current_hash
    ):
        raise HTTPException(status_code=409, detail="团队知识已更新，请重新基于最新版本创建更新草稿")


def submit_note(
    db: Session,
    team_id: str,
    applicant_id: str,
    payload: TeamNoteSubmissionCreate | str,
) -> TeamNoteSubmission:
    if isinstance(payload, str):
        payload = TeamNoteSubmissionCreate(source_note_id=payload)
    source = get_note_or_404(db, payload.source_note_id, applicant_id)
    if not note_permission_service.can_submit_to_knowledge(db, source, applicant_id, team_id):
        raise HTTPException(status_code=403, detail="没有投稿权限")
    _validate_category(db, team_id, payload.proposed_category_id)
    target: TeamNote | None = None
    base_version_no: int | None = None
    base_hash: str | None = None
    if payload.submission_type == TeamNoteSubmissionType.UPDATE:
        target = get_team_note_or_404(db, team_id, payload.target_team_note_id or "", include_archived=False)
        if source.is_knowledge_update_draft:
            if source.copied_from_team_note_id != target.id:
                raise HTTPException(status_code=409, detail="更新草稿的目标知识已改变")
            base_version_no = source.copied_from_team_note_version_no
            base_hash = source.copied_from_team_note_snapshot_hash
            if base_version_no is None or not base_hash:
                raise HTTPException(status_code=409, detail="更新草稿缺少目标版本，请重新创建更新草稿")
        else:
            base_version_no, base_hash = team_note_version_info(db, target)
        current_version_no, current_hash = team_note_version_info(db, target)
        if base_version_no != current_version_no or base_hash != current_hash:
            raise HTTPException(status_code=409, detail="团队知识已更新，请重新基于最新版本创建更新草稿")
    existing_statement = select(TeamNoteSubmission.id).where(
        TeamNoteSubmission.team_id == team_id,
        TeamNoteSubmission.applicant_id == applicant_id,
        TeamNoteSubmission.submission_type == payload.submission_type,
        TeamNoteSubmission.target_team_note_id == (target.id if target else None),
        TeamNoteSubmission.status.in_((
            TeamNoteSubmissionStatus.PENDING,
            TeamNoteSubmissionStatus.NEEDS_REVISION,
        )),
    )
    if payload.submission_type == TeamNoteSubmissionType.CREATE:
        existing_statement = existing_statement.where(TeamNoteSubmission.source_note_id == source.id)
    existing = db.scalar(existing_statement)
    if existing is not None:
        raise HTTPException(status_code=409, detail="该笔记已有未完成投稿")
    submission = TeamNoteSubmission(
        team_id=team_id,
        submission_type=payload.submission_type,
        source_note_id=source.id,
        applicant_id=applicant_id,
        source_author_id=source.owner_id,
        target_team_note_id=target.id if target else None,
        base_team_note_version_no=base_version_no,
        base_team_note_snapshot_hash=base_hash,
        snapshot_title=source.title,
        snapshot_content_json=source.content_json,
        snapshot_plain_text=source.plain_text,
        snapshot_attachment_ids=[],
        snapshot_hash="",
        proposed_category_id=payload.proposed_category_id,
        proposed_tags_json=payload.proposed_tags_json,
        submission_message=payload.submission_message.strip() if payload.submission_message else None,
        status=TeamNoteSubmissionStatus.PENDING,
        revision_no=1,
    )
    db.add(submission)
    db.flush()
    _snapshot_submission(db, submission, source)
    db.commit()
    return get_submission_or_404(db, team_id, submission.id)


def resubmit_note(
    db: Session,
    submission: TeamNoteSubmission,
    applicant_id: str,
    payload: TeamNoteSubmissionCreate | None = None,
) -> TeamNoteSubmission:
    if submission.applicant_id != applicant_id:
        raise HTTPException(status_code=403, detail="只能重新提交自己的投稿")
    if submission.status != TeamNoteSubmissionStatus.NEEDS_REVISION:
        raise HTTPException(status_code=409, detail="只有需要修改的投稿可以重新提交")
    source = get_note_or_404(db, submission.source_note_id, applicant_id)
    if submission.submission_type == TeamNoteSubmissionType.UPDATE:
        target = get_team_note_or_404(
            db, submission.team_id, submission.target_team_note_id or "", include_archived=False
        )
        _assert_submission_target_current(db, submission, target)
        if source.is_knowledge_update_draft and source.copied_from_team_note_id != target.id:
            raise HTTPException(status_code=409, detail="更新草稿的目标知识已改变")
    if payload is not None:
        submission.proposed_category_id = _validate_category(db, submission.team_id, payload.proposed_category_id)
        submission.proposed_tags_json = payload.proposed_tags_json
        submission.submission_message = payload.submission_message
    _snapshot_submission(db, submission, source)
    submission.status = TeamNoteSubmissionStatus.PENDING
    submission.revision_no += 1
    submission.reviewer_id = None
    submission.reviewed_at = None
    submission.review_reason = None
    submission.review_reason_code = None
    submission.review_comment = None
    db.commit()
    return get_submission_or_404(db, submission.team_id, submission.id)


def get_submission_or_404(db: Session, team_id: str, submission_id: str) -> TeamNoteSubmission:
    submission = db.scalar(select(TeamNoteSubmission).options(
        joinedload(TeamNoteSubmission.applicant)
    ).where(
        TeamNoteSubmission.id == submission_id, TeamNoteSubmission.team_id == team_id
    ).execution_options(populate_existing=True))
    if submission is None:
        raise HTTPException(status_code=404, detail="Knowledge submission not found")
    return submission


def list_submissions(
    db: Session,
    team_id: str,
    applicant_id: str | None = None,
    limit: int = 100,
    offset: int = 0,
    statuses: list[TeamNoteSubmissionStatus] | None = None,
) -> list[TeamNoteSubmission]:
    statement = select(TeamNoteSubmission).options(joinedload(TeamNoteSubmission.applicant)).where(
        TeamNoteSubmission.team_id == team_id
    )
    if applicant_id is not None:
        statement = statement.where(TeamNoteSubmission.applicant_id == applicant_id)
    if statuses:
        statement = statement.where(TeamNoteSubmission.status.in_(statuses))
    return list(db.scalars(statement.order_by(TeamNoteSubmission.created_at.desc()).limit(limit).offset(offset)))


def count_submissions(
    db: Session,
    team_id: str,
    applicant_id: str | None = None,
    statuses: list[TeamNoteSubmissionStatus] | None = None,
) -> int:
    statement = select(func.count(TeamNoteSubmission.id)).where(TeamNoteSubmission.team_id == team_id)
    if applicant_id is not None:
        statement = statement.where(TeamNoteSubmission.applicant_id == applicant_id)
    if statuses:
        statement = statement.where(TeamNoteSubmission.status.in_(statuses))
    return int(db.scalar(statement) or 0)


def withdraw_submission(db: Session, submission: TeamNoteSubmission, applicant_id: str) -> TeamNoteSubmission:
    if submission.applicant_id != applicant_id:
        raise HTTPException(status_code=403, detail="只能撤回自己的投稿")
    if submission.status != TeamNoteSubmissionStatus.PENDING:
        raise HTTPException(status_code=409, detail="只有待审核投稿可以撤回")
    result = db.execute(update(TeamNoteSubmission).where(
        TeamNoteSubmission.id == submission.id,
        TeamNoteSubmission.status == TeamNoteSubmissionStatus.PENDING,
    ).values(status=TeamNoteSubmissionStatus.WITHDRAWN, updated_at=local_now()))
    if result.rowcount != 1:
        db.rollback()
        raise HTTPException(status_code=409, detail="投稿状态已变化")
    db.commit()
    return get_submission_or_404(db, submission.team_id, submission.id)


def _review_transition(
    db: Session,
    submission: TeamNoteSubmission,
    reviewer_id: str,
    target_status: TeamNoteSubmissionStatus,
    review: TeamNoteSubmissionReview,
) -> TeamNoteSubmission:
    if submission.status != TeamNoteSubmissionStatus.PENDING:
        raise HTTPException(status_code=409, detail="该投稿当前不可审核")
    reviewed_at = local_now()
    result = db.execute(update(TeamNoteSubmission).where(
        TeamNoteSubmission.id == submission.id,
        TeamNoteSubmission.status == TeamNoteSubmissionStatus.PENDING,
    ).values(
        status=target_status,
        reviewer_id=reviewer_id,
        reviewed_at=reviewed_at,
        review_reason=review.reason.strip() if review.reason else None,
        review_reason_code=review.reason_code,
        review_comment=review.reason.strip() if review.reason else None,
        updated_at=reviewed_at,
    ).execution_options(synchronize_session=False))
    if result.rowcount != 1:
        db.rollback()
        raise HTTPException(status_code=409, detail="该投稿已经被其他管理员处理")
    db.commit()
    return get_submission_or_404(db, submission.team_id, submission.id)


def request_revision(
    db: Session, submission: TeamNoteSubmission, reviewer_id: str, review: TeamNoteSubmissionReview
) -> TeamNoteSubmission:
    if not review.reason or not review.reason.strip():
        raise HTTPException(status_code=422, detail="请填写需要修改的内容")
    return _review_transition(db, submission, reviewer_id, TeamNoteSubmissionStatus.NEEDS_REVISION, review)


def reject_submission(
    db: Session,
    submission: TeamNoteSubmission,
    reviewer_id: str,
    reason: str | None = None,
    review: TeamNoteSubmissionReview | None = None,
) -> TeamNoteSubmission:
    review = review or TeamNoteSubmissionReview(reason=reason)
    return _review_transition(db, submission, reviewer_id, TeamNoteSubmissionStatus.REJECTED, review)


def approve_submission(
    db: Session,
    submission: TeamNoteSubmission,
    reviewer_id: str,
    review: TeamNoteSubmissionReview | None = None,
) -> TeamNote:
    review = review or TeamNoteSubmissionReview()
    if submission.status != TeamNoteSubmissionStatus.PENDING:
        raise HTTPException(status_code=409, detail="该投稿当前不可审核")
    title = review.title.strip() if review.title else submission.snapshot_title
    category_id = _validate_category(
        db, submission.team_id,
        review.category_id if "category_id" in review.model_fields_set else submission.proposed_category_id,
    )
    tags = review.tags if review.tags is not None else list(submission.proposed_tags_json or [])
    target: TeamNote | None = None
    if submission.submission_type == TeamNoteSubmissionType.UPDATE:
        target = get_team_note_or_404(
            db, submission.team_id, submission.target_team_note_id or "", include_archived=False
        )
        _assert_submission_target_current(db, submission, target)
    reviewed_at = local_now()
    claimed = db.execute(update(TeamNoteSubmission).where(
        TeamNoteSubmission.id == submission.id,
        TeamNoteSubmission.status == TeamNoteSubmissionStatus.PENDING,
    ).values(
        status=TeamNoteSubmissionStatus.APPROVED,
        reviewer_id=reviewer_id,
        reviewed_at=reviewed_at,
        review_reason=review.reason,
        review_reason_code=review.reason_code,
        review_comment=review.reason,
        updated_at=reviewed_at,
    ).execution_options(synchronize_session=False))
    if claimed.rowcount != 1:
        db.rollback()
        raise HTTPException(status_code=409, detail="该投稿已经被其他管理员处理")
    try:
        if submission.submission_type == TeamNoteSubmissionType.CREATE:
            note = TeamNote(
                team_id=submission.team_id,
                title=title,
                content_json=submission.snapshot_content_json,
                plain_text=submission.snapshot_plain_text,
                attachment_ids=list(submission.snapshot_attachment_ids or []),
                category_id=category_id,
                tags=tags,
                source_type=TeamNoteSourceType.MEMBER_SUBMISSION,
                source_note_id=submission.source_note_id,
                source_author_id=submission.source_author_id,
                source_submission_id=submission.id,
                status=TeamNoteStatus.PUBLISHED,
                published_at=reviewed_at,
                created_by_id=reviewer_id,
                updated_by_id=reviewer_id,
            )
            db.add(note)
            db.flush()
            change_type = "SUBMISSION_CREATE"
        else:
            note = target
            assert note is not None
            old_ids = list(note.attachment_ids or [])
            note.title = title
            note.content_json = submission.snapshot_content_json
            note.plain_text = submission.snapshot_plain_text
            note.attachment_ids = list(submission.snapshot_attachment_ids or [])
            note.category_id = category_id
            note.tags = tags
            # Keep the original personal-note association when this is an
            # update to member-created knowledge. For admin-created knowledge,
            # the first accepted member update becomes its source.
            if note.source_note_id is None:
                note.source_type = TeamNoteSourceType.MEMBER_SUBMISSION
                note.source_note_id = submission.source_note_id
                note.source_author_id = submission.source_author_id
                note.source_submission_id = submission.id
            note.updated_by_id = reviewer_id
            _reconcile_file_access(db, note, old_ids, note.attachment_ids, reviewer_id)
            change_type = "SUBMISSION_UPDATE"
        source_note = db.get(Note, submission.source_note_id)
        if source_note is not None and source_note.is_knowledge_update_draft:
            source_note.is_knowledge_update_draft = False
        _grant_file_access(db, note, list(submission.snapshot_attachment_ids or []), reviewer_id)
        resource_relation_service.sync_team_note_relations(
            db,
            note.id,
            reviewer_id,
            resource_relation_service.resource_references_in_document(note.content_json),
        )
        _record_version(db, note, reviewer_id, change_type, submission.id)
        search_index_service.upsert_team_note(db, note)
        db.flush()
        db.execute(update(TeamNoteSubmission).where(
            TeamNoteSubmission.id == submission.id
        ).values(approved_team_note_id=note.id))
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(status_code=409, detail="该投稿已经被其他管理员处理") from exc
    return get_team_note_or_404(db, submission.team_id, note.id)


def list_versions(db: Session, team_note_id: str) -> list[TeamNoteVersion]:
    return list(db.scalars(select(TeamNoteVersion).where(
        TeamNoteVersion.team_note_id == team_note_id
    ).order_by(TeamNoteVersion.version_no.desc())))


def related_knowledge(db: Session, submission: TeamNoteSubmission, limit: int = 5) -> list[TeamNote]:
    terms = [term for term in submission.snapshot_title.replace("/", " ").split() if len(term) >= 2]
    statement = select(TeamNote).options(joinedload(TeamNote.category), joinedload(TeamNote.source_author)).where(
        TeamNote.team_id == submission.team_id,
        TeamNote.status == TeamNoteStatus.PUBLISHED,
    )
    filters = []
    if submission.proposed_category_id:
        filters.append(TeamNote.category_id == submission.proposed_category_id)
    for term in terms[:4]:
        filters.append(TeamNote.title.like(f"%{term}%"))
    for tag in (submission.proposed_tags_json or [])[:4]:
        filters.append(func.cast(TeamNote.tags, String).like(f"%{tag}%"))
    if filters:
        statement = statement.where(or_(*filters))
    else:
        return []
    if submission.target_team_note_id:
        statement = statement.where(TeamNote.id != submission.target_team_note_id)
    return list(db.scalars(statement.order_by(TeamNote.updated_at.desc()).limit(limit)).unique())


def can_access_attachment(db: Session, attachment: Attachment, user_id: str) -> bool:
    if attachment.owner_id == user_id and attachment.note_id is not None:
        note = db.get(Note, attachment.note_id)
        if note is not None and note.deleted_at is None:
            return True
    share_owner_membership = aliased(TeamMember)
    share_target_membership = aliased(TeamMember)
    if attachment.note_id is not None and db.scalar(
        select(NoteShare.id)
        .join(Team, Team.id == NoteShare.team_id)
        .join(share_target_membership, share_target_membership.team_id == NoteShare.team_id)
        .join(share_owner_membership, share_owner_membership.team_id == NoteShare.team_id)
        .where(
            NoteShare.note_id == attachment.note_id,
            NoteShare.shared_with_user_id == user_id,
            NoteShare.status == NoteShareStatus.ACTIVE,
            share_target_membership.user_id == user_id,
            share_target_membership.status == TeamMemberStatus.ACTIVE,
            share_owner_membership.user_id == NoteShare.shared_by_user_id,
            share_owner_membership.status == TeamMemberStatus.ACTIVE,
            Team.status == TeamStatus.ACTIVE,
        )
    ) is not None:
        return True
    if user_is_root(db, user_id):
        # A system administrator can access team-scoped binaries without a
        # TeamMember row. Keep the scope explicit so private personal-note
        # attachments are not exposed merely because the actor is ROOT.
        if db.scalar(
            select(TeamFileAccess.id)
            .join(Team, Team.id == TeamFileAccess.team_id)
            .where(
                TeamFileAccess.attachment_id == attachment.id,
                Team.status == TeamStatus.ACTIVE,
            )
        ) is not None:
            return True
        if db.scalar(
            select(SubmissionFileAccess.id)
            .join(TeamNoteSubmission, TeamNoteSubmission.id == SubmissionFileAccess.submission_id)
            .join(Team, Team.id == TeamNoteSubmission.team_id)
            .where(
                SubmissionFileAccess.attachment_id == attachment.id,
                TeamNoteSubmission.status.in_(
                    (
                        TeamNoteSubmissionStatus.PENDING,
                        TeamNoteSubmissionStatus.NEEDS_REVISION,
                    )
                ),
                Team.status == TeamStatus.ACTIVE,
            )
        ) is not None:
            return True
    if db.scalar(
        select(TeamFileAccess.id)
        .join(TeamMember, TeamMember.team_id == TeamFileAccess.team_id)
        .join(Team, Team.id == TeamFileAccess.team_id)
        .where(
            TeamFileAccess.attachment_id == attachment.id,
            TeamMember.user_id == user_id,
            TeamMember.status == TeamMemberStatus.ACTIVE,
            Team.status == TeamStatus.ACTIVE,
        )
    ) is not None:
        return True
    if db.scalar(
        select(SubmissionFileAccess.id)
        .join(TeamNoteSubmission, TeamNoteSubmission.id == SubmissionFileAccess.submission_id)
        .join(TeamMember, TeamMember.team_id == TeamNoteSubmission.team_id)
        .where(
            SubmissionFileAccess.attachment_id == attachment.id,
            TeamNoteSubmission.status.in_((
                TeamNoteSubmissionStatus.PENDING,
                TeamNoteSubmissionStatus.NEEDS_REVISION,
            )),
            TeamMember.user_id == user_id,
            TeamMember.status == TeamMemberStatus.ACTIVE,
            TeamMember.role.in_((TeamMemberRole.OWNER, TeamMemberRole.ADMIN)),
        )
    ) is not None:
        return True
    task_access = db.scalar(select(TaskFileAccess).where(TaskFileAccess.attachment_id == attachment.id))
    if task_access is not None:
        from app.services import todo_service

        task = db.get(Todo, task_access.task_id)
        if task is not None and todo_service.can_view(db, task, user_id):
            return True
    return False
