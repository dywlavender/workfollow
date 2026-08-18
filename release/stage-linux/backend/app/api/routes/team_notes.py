from __future__ import annotations

from typing import NamedTuple

from fastapi import APIRouter, HTTPException, Query, Response, status
from sqlalchemy import select

from app.core.dependencies import CurrentSettings, CurrentUser, DbSession
from app.models.auth import User, UserStatus
from app.models.note import Attachment
from app.models.notification import NotificationType
from app.models.team import TeamMember, TeamMemberRole, TeamMemberStatus
from app.models.team_note import TeamNoteStatus, TeamNoteSubmission, TeamNoteSubmissionStatus
from app.schemas.note import NoteRead
from app.schemas.team import (
    NoteSubmissionRequest,
    TeamNoteCategoryCreate,
    TeamNoteCategoryRead,
    TeamNoteCategoryUpdate,
    TeamNoteCreate,
    TeamNotePermissions,
    TeamNoteRead,
    TeamNoteSubmissionCreate,
    TeamNoteSubmissionRead,
    TeamNoteSubmissionReview,
    TeamNoteUpdate,
    TeamNoteVersionRead,
)
from app.services import audit_service, note_permission_service, note_service, team_note_service, team_service
from app.services.notification_service import notify_user
from app.services.system_permission_service import audit_metadata, user_is_root


router = APIRouter(tags=["knowledge"])


class _TeamContext(NamedTuple):
    team_id: str
    member: TeamMember | None


def _current_team(db, user_id: str, requested_team_id: str | None = None) -> _TeamContext:  # noqa: ANN001
    """Resolve the selected team without turning ROOT into a team member.

    A normal user may omit ``teamId`` for backwards compatibility; the
    existing most-recent membership fallback is retained. ROOT must provide
    an explicit team because its account has no implicit team context.
    """
    if user_is_root(db, user_id):
        if requested_team_id is None:
            raise HTTPException(status_code=422, detail="系统管理员需要指定 teamId")
        team_service.get_team_or_404(db, requested_team_id)
        return _TeamContext(requested_team_id, None)

    member = note_permission_service.membership(db, user_id, requested_team_id)
    if member is None:
        raise HTTPException(status_code=404, detail="Team not found")
    return _TeamContext(member.team_id, member)


def _note_read(db, note, user_id: str, attachments_by_id=None) -> TeamNoteRead:  # noqa: ANN001
    attachments = (
        [attachments_by_id[item] for item in (note.attachment_ids or []) if item in attachments_by_id]
        if attachments_by_id is not None else team_note_service.attachment_reads(db, list(note.attachment_ids or []))
    )
    editable = note_permission_service.can_edit_team_note(db, note, user_id)
    return TeamNoteRead.model_validate(note).model_copy(update={
        "attachments": attachments,
        "permissions": TeamNotePermissions(
            can_edit=editable,
            can_copy=True,
            can_archive=editable,
        ),
    })


def _submit(db, team_id: str, user_id: str, payload: TeamNoteSubmissionCreate) -> TeamNoteSubmissionRead:  # noqa: ANN001
    submission = team_note_service.submit_note(db, team_id, user_id, payload)
    audit_service.record_audit(
        db, actor_user_id=user_id, action="KNOWLEDGE_SUBMITTED",
        resource_type="TEAM_NOTE_SUBMISSION", resource_id=submission.id, team_id=team_id,
        metadata_json=audit_metadata(db.get(User, user_id), {
            "sourceNoteId": submission.source_note_id,
            "type": submission.submission_type.value,
            "targetTeamNoteId": submission.target_team_note_id,
        }),
    )
    _notify_submission_reviewers(db, submission, user_id)
    return submission


def _notify_submission_reviewers(db, submission, applicant_id: str) -> None:  # noqa: ANN001
    reviewer_ids = db.scalars(
        select(TeamMember.user_id)
        .join(User, User.id == TeamMember.user_id)
        .where(
            TeamMember.team_id == submission.team_id,
            TeamMember.status == TeamMemberStatus.ACTIVE,
            TeamMember.role.in_((TeamMemberRole.OWNER, TeamMemberRole.ADMIN)),
            User.status == UserStatus.ACTIVE,
        )
    ).all()
    applicant_name = submission.applicant.nickname if submission.applicant else "成员"
    title = submission.snapshot_title
    for reviewer_id in set(reviewer_ids) - {applicant_id}:
        notify_user(
            db,
            reviewer_id,
            NotificationType.TEAM_NOTE_SUBMITTED,
            "有新的团队笔记投稿",
            f"{applicant_name} 投稿了“{title}”，请及时审核。",
            actor_user_id=applicant_id,
            data_json={
                "teamId": submission.team_id,
                "submissionId": submission.id,
                "applicantId": applicant_id,
                "title": title,
            },
        )


# Canonical knowledge APIs -------------------------------------------------

@router.get("/team/knowledge", response_model=list[TeamNoteRead])
def list_knowledge(
    db: DbSession,
    user: CurrentUser,
    q: str | None = Query(default=None),
    category_id: str | None = Query(default=None, alias="categoryId"),
    include_archived: bool = Query(default=False, alias="includeArchived"),
    team_id: str | None = Query(default=None, alias="teamId"),
) -> list[TeamNoteRead]:
    context = _current_team(db, user.id, team_id)
    if include_archived and context.member is not None and context.member.role == TeamMemberRole.MEMBER:
        include_archived = False
    notes = team_note_service.list_team_notes(
        db, context.team_id, q=q, category_id=category_id, include_archived=include_archived
    )
    attachment_map = team_note_service.attachment_read_map(
        db, [item for note in notes for item in (note.attachment_ids or [])]
    )
    return [_note_read(db, note, user.id, attachment_map) for note in notes]


@router.get("/team/knowledge/categories", response_model=list[TeamNoteCategoryRead])
def get_categories(
    db: DbSession, user: CurrentUser, team_id: str | None = Query(default=None, alias="teamId")
) -> list[TeamNoteCategoryRead]:
    context = _current_team(db, user.id, team_id)
    return team_note_service.list_categories(db, context.team_id)


@router.post("/team/knowledge/categories", response_model=TeamNoteCategoryRead, status_code=status.HTTP_201_CREATED)
def post_category(
    payload: TeamNoteCategoryCreate,
    db: DbSession,
    user: CurrentUser,
    team_id: str | None = Query(default=None, alias="teamId"),
) -> TeamNoteCategoryRead:
    context = _current_team(db, user.id, team_id)
    team_service.require_role(db, context.team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    return team_note_service.create_category(db, context.team_id, payload.name, payload.sort_order)


@router.put("/team/knowledge/categories/{category_id}", response_model=TeamNoteCategoryRead)
def put_category(
    category_id: str,
    payload: TeamNoteCategoryUpdate,
    db: DbSession,
    user: CurrentUser,
    team_id: str | None = Query(default=None, alias="teamId"),
) -> TeamNoteCategoryRead:
    context = _current_team(db, user.id, team_id)
    team_service.require_role(db, context.team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    category = team_note_service.get_category_or_404(db, context.team_id, category_id)
    return team_note_service.update_category(db, category, payload.name, payload.sort_order)


@router.delete("/team/knowledge/categories/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_category(
    category_id: str,
    db: DbSession,
    user: CurrentUser,
    team_id: str | None = Query(default=None, alias="teamId"),
) -> Response:
    context = _current_team(db, user.id, team_id)
    team_service.require_role(db, context.team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    category = team_note_service.get_category_or_404(db, context.team_id, category_id)
    team_note_service.delete_category(db, category)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/team/knowledge", response_model=TeamNoteRead, status_code=status.HTTP_201_CREATED)
def post_knowledge(
    payload: TeamNoteCreate,
    db: DbSession,
    user: CurrentUser,
    team_id: str | None = Query(default=None, alias="teamId"),
) -> TeamNoteRead:
    context = _current_team(db, user.id, team_id)
    team_service.require_role(db, context.team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    return _note_read(db, team_note_service.create_team_note(db, context.team_id, user.id, payload), user.id)


@router.get("/team/knowledge/{note_id}", response_model=TeamNoteRead)
def get_knowledge(
    note_id: str,
    db: DbSession,
    user: CurrentUser,
    team_id: str | None = Query(default=None, alias="teamId"),
) -> TeamNoteRead:
    context = _current_team(db, user.id, team_id)
    note = team_note_service.get_team_note_or_404(db, context.team_id, note_id)
    if note.status == TeamNoteStatus.ARCHIVED and context.member is not None and context.member.role == TeamMemberRole.MEMBER:
        raise HTTPException(status_code=404, detail="Team knowledge not found")
    return _note_read(db, note, user.id)


@router.put("/team/knowledge/{note_id}", response_model=TeamNoteRead)
def put_knowledge(
    note_id: str,
    payload: TeamNoteUpdate,
    db: DbSession,
    user: CurrentUser,
    team_id: str | None = Query(default=None, alias="teamId"),
) -> TeamNoteRead:
    context = _current_team(db, user.id, team_id)
    team_service.require_role(db, context.team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    note = team_note_service.get_team_note_or_404(db, context.team_id, note_id)
    return _note_read(db, team_note_service.update_team_note(db, note, user.id, payload), user.id)


@router.post("/team/knowledge/{note_id}/archive", response_model=TeamNoteRead)
def archive_knowledge(
    note_id: str,
    db: DbSession,
    user: CurrentUser,
    team_id: str | None = Query(default=None, alias="teamId"),
) -> TeamNoteRead:
    context = _current_team(db, user.id, team_id)
    team_service.require_role(db, context.team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    note = team_note_service.get_team_note_or_404(db, context.team_id, note_id)
    return _note_read(db, team_note_service.set_team_note_archived(db, note, user.id, True), user.id)


@router.post("/team/knowledge/{note_id}/restore", response_model=TeamNoteRead)
def restore_knowledge(
    note_id: str,
    db: DbSession,
    user: CurrentUser,
    team_id: str | None = Query(default=None, alias="teamId"),
) -> TeamNoteRead:
    context = _current_team(db, user.id, team_id)
    team_service.require_role(db, context.team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    note = team_note_service.get_team_note_or_404(db, context.team_id, note_id)
    return _note_read(db, team_note_service.set_team_note_archived(db, note, user.id, False), user.id)


@router.get("/team/knowledge/{note_id}/versions", response_model=list[TeamNoteVersionRead])
def knowledge_versions(
    note_id: str,
    db: DbSession,
    user: CurrentUser,
    team_id: str | None = Query(default=None, alias="teamId"),
) -> list[TeamNoteVersionRead]:
    context = _current_team(db, user.id, team_id)
    team_note_service.get_team_note_or_404(db, context.team_id, note_id)
    return team_note_service.list_versions(db, note_id)


@router.post("/team/knowledge/{note_id}/copy", response_model=NoteRead, status_code=status.HTTP_201_CREATED)
def copy_knowledge(
    note_id: str,
    db: DbSession,
    settings: CurrentSettings,
    user: CurrentUser,
    team_id: str | None = Query(default=None, alias="teamId"),
) -> NoteRead:
    context = _current_team(db, user.id, team_id)
    source = team_note_service.get_team_note_or_404(db, context.team_id, note_id, include_archived=False)
    attachment_ids = list(source.attachment_ids or [])
    attachments_by_id = {
        item.id: item for item in db.scalars(select(Attachment).where(Attachment.id.in_(attachment_ids)))
    } if attachment_ids else {}
    if len(attachments_by_id) != len(set(attachment_ids)):
        raise HTTPException(status_code=409, detail="知识附件记录不完整，无法复制")
    return note_service.copy_note_with_attachments(
        db,
        title=source.title,
        content_json=source.content_json,
        plain_text=source.plain_text,
        source_attachments=[attachments_by_id[item] for item in attachment_ids if item in attachments_by_id],
        owner_id=user.id,
        settings=settings,
        copied_from_team_note_id=source.id,
    )


@router.post("/notes/{note_id}/submissions", response_model=TeamNoteSubmissionRead, status_code=status.HTTP_201_CREATED)
def create_submission(
    note_id: str,
    payload: NoteSubmissionRequest,
    db: DbSession,
    user: CurrentUser,
    team_id: str | None = Query(default=None, alias="teamId"),
) -> TeamNoteSubmissionRead:
    context = _current_team(db, user.id, team_id)
    return _submit(db, context.team_id, user.id, TeamNoteSubmissionCreate(
        source_note_id=note_id,
        type=payload.submission_type,
        target_team_note_id=payload.target_team_note_id,
        categoryId=payload.proposed_category_id,
        tags=payload.proposed_tags_json,
        message=payload.submission_message,
    ))


@router.get("/note-submissions/mine", response_model=list[TeamNoteSubmissionRead])
def mine_submissions(
    db: DbSession,
    user: CurrentUser,
    team_id: str | None = Query(default=None, alias="teamId"),
) -> list[TeamNoteSubmissionRead]:
    context = _current_team(db, user.id, team_id)
    return team_note_service.list_submissions(db, context.team_id, user.id)


@router.get("/note-submissions/review", response_model=list[TeamNoteSubmissionRead])
def review_submissions(
    db: DbSession,
    user: CurrentUser,
    team_id: str | None = Query(default=None, alias="teamId"),
) -> list[TeamNoteSubmissionRead]:
    context = _current_team(db, user.id, team_id)
    team_service.require_role(db, context.team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    return team_note_service.list_submissions(db, context.team_id, statuses=[
        TeamNoteSubmissionStatus.PENDING, TeamNoteSubmissionStatus.NEEDS_REVISION
    ])


def _submission_for_user(db, submission_id: str, user_id: str):  # noqa: ANN001
    team_id = db.scalar(select(TeamNoteSubmission.team_id).where(TeamNoteSubmission.id == submission_id))
    if team_id is None:
        raise HTTPException(status_code=404, detail="Knowledge submission not found")
    team_service.get_team_or_404(db, team_id)
    if not user_is_root(db, user_id) and note_permission_service.membership(db, user_id, team_id) is None:
        raise HTTPException(status_code=404, detail="Knowledge submission not found")
    return team_id, team_note_service.get_submission_or_404(db, team_id, submission_id)


@router.post("/note-submissions/{submission_id}/withdraw", response_model=TeamNoteSubmissionRead)
def withdraw(submission_id: str, db: DbSession, user: CurrentUser) -> TeamNoteSubmissionRead:
    _member, submission = _submission_for_user(db, submission_id, user.id)
    return team_note_service.withdraw_submission(db, submission, user.id)


@router.post("/note-submissions/{submission_id}/resubmit", response_model=TeamNoteSubmissionRead)
def resubmit(submission_id: str, payload: NoteSubmissionRequest, db: DbSession, user: CurrentUser) -> TeamNoteSubmissionRead:
    _member, submission = _submission_for_user(db, submission_id, user.id)
    resubmitted = team_note_service.resubmit_note(db, submission, user.id, TeamNoteSubmissionCreate(
        source_note_id=submission.source_note_id,
        type=submission.submission_type,
        target_team_note_id=submission.target_team_note_id,
        categoryId=payload.proposed_category_id,
        tags=payload.proposed_tags_json,
        message=payload.submission_message,
    ))
    _notify_submission_reviewers(db, resubmitted, user.id)
    return resubmitted


def _require_reviewer(db, submission_id: str, user_id: str):  # noqa: ANN001
    team_id, submission = _submission_for_user(db, submission_id, user_id)
    team_service.require_role(db, team_id, user_id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    return team_id, submission


@router.post("/note-submissions/{submission_id}/approve", response_model=TeamNoteRead)
def approve(submission_id: str, payload: TeamNoteSubmissionReview, db: DbSession, user: CurrentUser) -> TeamNoteRead:
    team_id, submission = _require_reviewer(db, submission_id, user.id)
    note = team_note_service.approve_submission(db, submission, user.id, payload)
    notify_user(
        db, submission.applicant_id, NotificationType.TEAM_NOTE_APPROVED,
        "知识投稿已通过", f"“{note.title}”已发布到团队知识库。", actor_user_id=user.id,
        data_json={"teamId": team_id, "submissionId": submission.id, "teamNoteId": note.id},
    )
    return _note_read(db, note, user.id)


@router.post("/note-submissions/{submission_id}/request-revision", response_model=TeamNoteSubmissionRead)
def request_revision(
    submission_id: str, payload: TeamNoteSubmissionReview, db: DbSession, user: CurrentUser
) -> TeamNoteSubmissionRead:
    _member, submission = _require_reviewer(db, submission_id, user.id)
    revised = team_note_service.request_revision(db, submission, user.id, payload)
    notify_user(
        db, revised.applicant_id, NotificationType.TEAM_NOTE_REVIEWED,
        "知识投稿需要修改", payload.reason or "请根据审核意见修改后重新提交。", actor_user_id=user.id,
        data_json={"teamId": revised.team_id, "submissionId": revised.id},
    )
    return revised


@router.post("/note-submissions/{submission_id}/reject", response_model=TeamNoteSubmissionRead)
def reject(submission_id: str, payload: TeamNoteSubmissionReview, db: DbSession, user: CurrentUser) -> TeamNoteSubmissionRead:
    _member, submission = _require_reviewer(db, submission_id, user.id)
    rejected = team_note_service.reject_submission(db, submission, user.id, review=payload)
    notify_user(
        db, rejected.applicant_id, NotificationType.TEAM_NOTE_REJECTED,
        "知识投稿已拒绝", payload.reason or "投稿未通过审核。", actor_user_id=user.id,
        data_json={"teamId": rejected.team_id, "submissionId": rejected.id},
    )
    return rejected


@router.get("/note-submissions/{submission_id}/related", response_model=list[TeamNoteRead])
def related(submission_id: str, db: DbSession, user: CurrentUser) -> list[TeamNoteRead]:
    _member, submission = _require_reviewer(db, submission_id, user.id)
    return [_note_read(db, note, user.id) for note in team_note_service.related_knowledge(db, submission)]


# Legacy team-scoped aliases -----------------------------------------------

@router.get("/teams/{team_id}/notes", response_model=list[TeamNoteRead], include_in_schema=False)
def legacy_list_notes(team_id: str, db: DbSession, user: CurrentUser) -> list[TeamNoteRead]:
    team_service.require_team_access(db, team_id, user.id)
    return [_note_read(db, note, user.id) for note in team_note_service.list_team_notes(db, team_id)]


@router.post("/teams/{team_id}/notes", response_model=TeamNoteRead, status_code=status.HTTP_201_CREATED, include_in_schema=False)
def legacy_create_note(team_id: str, payload: TeamNoteCreate, db: DbSession, user: CurrentUser) -> TeamNoteRead:
    team_service.require_role(db, team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    note = team_note_service.create_team_note(db, team_id, user.id, payload)
    audit_service.record_audit(
        db, actor_user_id=user.id, action="TEAM_NOTE_CREATED", resource_type="TEAM_NOTE",
        resource_id=note.id, team_id=team_id,
    )
    return _note_read(db, note, user.id)


@router.get("/teams/{team_id}/notes/{note_id}", response_model=TeamNoteRead, include_in_schema=False)
def legacy_get_note(team_id: str, note_id: str, db: DbSession, user: CurrentUser) -> TeamNoteRead:
    member = team_service.require_team_access(db, team_id, user.id)
    note = team_note_service.get_team_note_or_404(db, team_id, note_id)
    if note.status == TeamNoteStatus.ARCHIVED and member is not None and member.role == TeamMemberRole.MEMBER:
        raise HTTPException(status_code=404, detail="Team knowledge not found")
    return _note_read(db, note, user.id)


@router.put("/teams/{team_id}/notes/{note_id}", response_model=TeamNoteRead, include_in_schema=False)
def legacy_update_note(team_id: str, note_id: str, payload: TeamNoteUpdate, db: DbSession, user: CurrentUser) -> TeamNoteRead:
    team_service.require_role(db, team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    return _note_read(db, team_note_service.update_team_note(
        db, team_note_service.get_team_note_or_404(db, team_id, note_id), user.id, payload
    ), user.id)


@router.delete("/teams/{team_id}/notes/{note_id}", status_code=status.HTTP_204_NO_CONTENT, include_in_schema=False)
def legacy_delete_note(team_id: str, note_id: str, db: DbSession, user: CurrentUser):  # noqa: ANN201
    team_service.require_role(db, team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    team_note_service.set_team_note_archived(
        db, team_note_service.get_team_note_or_404(db, team_id, note_id), user.id, True
    )
    from fastapi import Response
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/teams/{team_id}/note-submissions", response_model=TeamNoteSubmissionRead, status_code=status.HTTP_201_CREATED, include_in_schema=False)
def legacy_submit_note(
    team_id: str, payload: TeamNoteSubmissionCreate, db: DbSession, user: CurrentUser
) -> TeamNoteSubmissionRead:
    return _submit(db, team_id, user.id, payload)


@router.get("/teams/{team_id}/note-submissions", response_model=list[TeamNoteSubmissionRead], include_in_schema=False)
def legacy_list_submissions(team_id: str, db: DbSession, user: CurrentUser) -> list[TeamNoteSubmissionRead]:
    member = team_service.require_team_access(db, team_id, user.id)
    applicant_id = None if member is None or member.role in (TeamMemberRole.OWNER, TeamMemberRole.ADMIN) else user.id
    return team_note_service.list_submissions(db, team_id, applicant_id)


@router.post("/teams/{team_id}/note-submissions/{submission_id}/approve", response_model=TeamNoteRead, include_in_schema=False)
def legacy_approve(team_id: str, submission_id: str, db: DbSession, user: CurrentUser) -> TeamNoteRead:
    team_service.require_role(db, team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    note = team_note_service.approve_submission(
        db, team_note_service.get_submission_or_404(db, team_id, submission_id), user.id
    )
    submission = team_note_service.get_submission_or_404(db, team_id, submission_id)
    notify_user(
        db, submission.applicant_id, NotificationType.TEAM_NOTE_APPROVED,
        "知识投稿已通过", f"“{note.title}”已发布到团队知识库。", actor_user_id=user.id,
        data_json={"teamId": team_id, "submissionId": submission.id, "teamNoteId": note.id},
    )
    return _note_read(db, note, user.id)


@router.post("/teams/{team_id}/note-submissions/{submission_id}/reject", response_model=TeamNoteSubmissionRead, include_in_schema=False)
def legacy_reject(
    team_id: str, submission_id: str, payload: TeamNoteSubmissionReview, db: DbSession, user: CurrentUser
) -> TeamNoteSubmissionRead:
    team_service.require_role(db, team_id, user.id, TeamMemberRole.OWNER, TeamMemberRole.ADMIN)
    rejected = team_note_service.reject_submission(
        db, team_note_service.get_submission_or_404(db, team_id, submission_id), user.id, review=payload
    )
    notify_user(
        db, rejected.applicant_id, NotificationType.TEAM_NOTE_REJECTED,
        "知识投稿已拒绝", payload.reason or "投稿未通过审核。", actor_user_id=user.id,
        data_json={"teamId": team_id, "submissionId": rejected.id},
    )
    return rejected
