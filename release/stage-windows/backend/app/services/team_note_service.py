from __future__ import annotations

import hashlib
import json
from typing import Any

from fastapi import HTTPException
from sqlalchemy import String, delete, func, or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, aliased, joinedload

from app.models.note import Attachment, Note
from app.models.note_share import NoteShare, NoteShareStatus
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
from app.services import note_permission_service, team_service
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
) -> list[TeamNote]:
    statement = select(TeamNote).options(
        joinedload(TeamNote.category), joinedload(TeamNote.source_author)
    ).where(TeamNote.team_id == team_id)
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
    return category


def delete_category(db: Session, category: TeamNoteCategory) -> None:
    db.execute(update(TeamNote).where(
        TeamNote.team_id == category.team_id,
        TeamNote.category_id == category.id,
    ).values(category_id=None))
    db.execute(update(TeamNoteSubmission).where(
        TeamNoteSubmission.team_id == category.team_id,
        TeamNoteSubmission.proposed_category_id == category.id,
    ).values(proposed_category_id=None))
    db.delete(category)
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
    _record_version(db, note, actor_id, "ADMIN_CREATE")
    db.commit()
    return get_team_note_or_404(db, team_id, note.id)


def update_team_note(db: Session, note: TeamNote, actor_id: str, payload: TeamNoteUpdate) -> TeamNote:
    changes = payload.model_dump(exclude_unset=True)
    old_ids = list(note.attachment_ids or [])
    new_ids = changes.pop("attachment_ids", old_ids)
    if "category_id" in changes:
        changes["category_id"] = _validate_category(db, note.team_id, changes["category_id"])
    if "content_json" in changes and not (changes.get("plain_text") or "").strip():
        changes["plain_text"] = content_to_plain_text(changes["content_json"])
    validated_ids = _validate_attachment_ids(db, new_ids, actor_id, note.id, team_id=note.team_id)
    changes["attachment_ids"] = validated_ids
    changes["updated_by_id"] = actor_id
    for field, value in changes.items():
        setattr(note, field, value)
    _reconcile_file_access(db, note, old_ids, validated_ids, actor_id)
    _record_version(db, note, actor_id, "ADMIN_EDIT")
    db.commit()
    return get_team_note_or_404(db, note.team_id, note.id)


def set_team_note_archived(db: Session, note: TeamNote, actor_id: str, archived: bool) -> TeamNote:
    note.status = TeamNoteStatus.ARCHIVED if archived else TeamNoteStatus.PUBLISHED
    note.archived_at = local_now() if archived else None
    note.updated_by_id = actor_id
    _record_version(db, note, actor_id, "ARCHIVE" if archived else "RESTORE")
    db.commit()
    return get_team_note_or_404(db, note.team_id, note.id)


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
    if payload.submission_type == TeamNoteSubmissionType.UPDATE:
        target = get_team_note_or_404(db, team_id, payload.target_team_note_id or "", include_archived=False)
    existing = db.scalar(select(TeamNoteSubmission.id).where(
        TeamNoteSubmission.team_id == team_id,
        TeamNoteSubmission.applicant_id == applicant_id,
        TeamNoteSubmission.source_note_id == source.id,
        TeamNoteSubmission.submission_type == payload.submission_type,
        TeamNoteSubmission.target_team_note_id == (target.id if target else None),
        TeamNoteSubmission.status.in_((
            TeamNoteSubmissionStatus.PENDING,
            TeamNoteSubmissionStatus.NEEDS_REVISION,
        )),
    ))
    if existing is not None:
        raise HTTPException(status_code=409, detail="该笔记已有未完成投稿")
    submission = TeamNoteSubmission(
        team_id=team_id,
        submission_type=payload.submission_type,
        source_note_id=source.id,
        applicant_id=applicant_id,
        source_author_id=source.owner_id,
        target_team_note_id=target.id if target else None,
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
            note = get_team_note_or_404(
                db, submission.team_id, submission.target_team_note_id or "", include_archived=False
            )
            old_ids = list(note.attachment_ids or [])
            note.title = title
            note.content_json = submission.snapshot_content_json
            note.plain_text = submission.snapshot_plain_text
            note.attachment_ids = list(submission.snapshot_attachment_ids or [])
            note.category_id = category_id
            note.tags = tags
            note.source_type = TeamNoteSourceType.MEMBER_SUBMISSION
            note.source_note_id = submission.source_note_id
            note.source_author_id = submission.source_author_id
            note.source_submission_id = submission.id
            note.updated_by_id = reviewer_id
            _reconcile_file_access(db, note, old_ids, note.attachment_ids, reviewer_id)
            change_type = "SUBMISSION_UPDATE"
        _grant_file_access(db, note, list(submission.snapshot_attachment_ids or []), reviewer_id)
        _record_version(db, note, reviewer_id, change_type, submission.id)
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
