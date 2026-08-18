from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.dependencies import CurrentUser, DbSession
from app.models.quick_link import QuickLink, QuickLinkScope
from app.schemas.quick_link import QuickLinkCreate, QuickLinkRead, QuickLinkReorder, QuickLinkUpdate
from app.services.audit_service import record_audit
from app.services.system_permission_service import audit_metadata, require_root


router = APIRouter(prefix="/quick-links", tags=["quick-links"])
MAX_QUICK_LINKS = 12


def get_or_404(db: Session, link_id: str) -> QuickLink:
    link = db.get(QuickLink, link_id)
    if link is None:
        raise HTTPException(status_code=404, detail="QuickLink not found")
    return link


def derive_icon(name: str) -> str:
    compact = "".join(name.split())
    return compact[:2].upper() or "↗"


def get_system_or_404(db: Session, link_id: str) -> QuickLink:
    link = db.scalar(select(QuickLink).where(QuickLink.id == link_id, QuickLink.scope == QuickLinkScope.SYSTEM))
    if link is None:
        raise HTTPException(status_code=404, detail="QuickLink not found")
    return link


def normalize_system_data(payload: QuickLinkCreate) -> dict[str, object]:
    data = payload.model_dump()
    data["icon"] = (data["icon"] or derive_icon(str(data["name"]))).strip()
    return data


@router.get("/system", response_model=list[QuickLinkRead])
def list_system_quick_links(db: DbSession, user: CurrentUser) -> list[QuickLinkRead]:
    return list(db.scalars(
        select(QuickLink)
        .where(QuickLink.scope == QuickLinkScope.SYSTEM)
        .order_by(QuickLink.group_name.is_(None), QuickLink.group_name, QuickLink.sort_order, QuickLink.created_at)
    ))


@router.post("/system", response_model=QuickLinkRead, status_code=status.HTTP_201_CREATED)
def create_system_quick_link(payload: QuickLinkCreate, db: DbSession, user: CurrentUser) -> QuickLinkRead:
    require_root(user)
    link = QuickLink(
        **normalize_system_data(payload),
        owner_id=user.id,
        scope=QuickLinkScope.SYSTEM,
        created_by_id=user.id,
        updated_by_id=user.id,
    )
    db.add(link)
    db.commit()
    db.refresh(link)
    record_audit(
        db,
        actor_user_id=user.id,
        action="QUICK_LINK_SYSTEM_CREATED",
        resource_type="QUICK_LINK",
        resource_id=link.id,
        metadata_json=audit_metadata(user, {"scope": QuickLinkScope.SYSTEM.value}),
    )
    return link


@router.put("/system/reorder", response_model=list[QuickLinkRead])
def reorder_system_quick_links(
    payload: QuickLinkReorder, db: DbSession, user: CurrentUser
) -> list[QuickLinkRead]:
    require_root(user)
    if payload.ids is not None and payload.items:
        raise HTTPException(status_code=422, detail="只能使用 ids 或 items 其中一种排序格式")
    if payload.ids is not None:
        requested_ids = payload.ids
        if not requested_ids or len(requested_ids) != len(set(requested_ids)):
            raise HTTPException(status_code=422, detail="排序 ID 列表不能为空且不能重复")
        links = list(db.scalars(select(QuickLink).where(
            QuickLink.scope == QuickLinkScope.SYSTEM,
            QuickLink.id.in_(requested_ids),
        )))
        by_id = {link.id: link for link in links}
        if len(by_id) != len(requested_ids):
            raise HTTPException(status_code=404, detail="QuickLink not found")
        for index, link_id in enumerate(requested_ids):
            by_id[link_id].sort_order = index * 10
        changed_ids = requested_ids
    elif payload.items:
        requested_ids = [item.id for item in payload.items]
        if len(requested_ids) != len(set(requested_ids)):
            raise HTTPException(status_code=422, detail="排序 ID 不能重复")
        links = list(db.scalars(select(QuickLink).where(
            QuickLink.scope == QuickLinkScope.SYSTEM,
            QuickLink.id.in_(requested_ids),
        )))
        by_id = {link.id: link for link in links}
        if len(by_id) != len(requested_ids):
            raise HTTPException(status_code=404, detail="QuickLink not found")
        for item in payload.items:
            by_id[item.id].sort_order = item.sort_order
        changed_ids = requested_ids
    else:
        raise HTTPException(status_code=422, detail="排序内容不能为空")
    for link in by_id.values():
        link.updated_by_id = user.id
    db.commit()
    record_audit(
        db,
        actor_user_id=user.id,
        action="QUICK_LINK_SYSTEM_REORDERED",
        resource_type="QUICK_LINK",
        metadata_json=audit_metadata(user, {"linkIds": changed_ids}),
    )
    return list(db.scalars(
        select(QuickLink)
        .where(QuickLink.scope == QuickLinkScope.SYSTEM)
        .order_by(QuickLink.group_name.is_(None), QuickLink.group_name, QuickLink.sort_order, QuickLink.created_at)
    ))


@router.put("/system/{link_id}", response_model=QuickLinkRead)
def update_system_quick_link(
    link_id: str, payload: QuickLinkUpdate, db: DbSession, user: CurrentUser
) -> QuickLinkRead:
    require_root(user)
    link = get_system_or_404(db, link_id)
    changes = payload.model_dump(exclude_unset=True)
    if "name" in changes and not (changes["name"] or "").strip():
        raise HTTPException(status_code=422, detail="名称不能为空")
    if "name" in changes:
        changes["name"] = changes["name"].strip()
    if "group_name" in changes:
        changes["group_name"] = (changes["group_name"] or "").strip() or None
    if "description" in changes:
        changes["description"] = (changes["description"] or "").strip() or None
    if "icon" in changes:
        changes["icon"] = (changes["icon"] or "").strip() or derive_icon(str(changes.get("name") or link.name))
    for field, value in changes.items():
        setattr(link, field, value)
    link.updated_by_id = user.id
    db.commit()
    db.refresh(link)
    record_audit(
        db,
        actor_user_id=user.id,
        action="QUICK_LINK_SYSTEM_UPDATED",
        resource_type="QUICK_LINK",
        resource_id=link.id,
        metadata_json=audit_metadata(user, {"fields": list(changes)}),
    )
    return link


@router.delete("/system/{link_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_system_quick_link(link_id: str, db: DbSession, user: CurrentUser) -> Response:
    require_root(user)
    link = get_system_or_404(db, link_id)
    db.delete(link)
    db.commit()
    record_audit(
        db,
        actor_user_id=user.id,
        action="QUICK_LINK_SYSTEM_DELETED",
        resource_type="QUICK_LINK",
        resource_id=link_id,
        metadata_json=audit_metadata(user),
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("", response_model=list[QuickLinkRead])
def list_quick_links(db: DbSession, user: CurrentUser) -> list[QuickLinkRead]:
    return list(
        db.scalars(
            select(QuickLink)
            .where(QuickLink.owner_id == user.id, QuickLink.scope == QuickLinkScope.PERSONAL)
            .order_by(QuickLink.sort_order, QuickLink.created_at)
        )
    )


@router.post("", response_model=QuickLinkRead, status_code=status.HTTP_201_CREATED)
def create_quick_link(payload: QuickLinkCreate, db: DbSession, user: CurrentUser) -> QuickLinkRead:
    total = db.scalar(select(func.count()).select_from(QuickLink).where(
        QuickLink.owner_id == user.id, QuickLink.scope == QuickLinkScope.PERSONAL
    )) or 0
    if total >= MAX_QUICK_LINKS:
        raise HTTPException(status_code=409, detail=f"常用网址最多只能添加 {MAX_QUICK_LINKS} 个")
    data = payload.model_dump()
    data["icon"] = (data["icon"] or derive_icon(data["name"])).strip()
    link = QuickLink(**data, owner_id=user.id)
    db.add(link)
    db.commit()
    db.refresh(link)
    return link


@router.put("/{link_id}", response_model=QuickLinkRead)
def update_quick_link(link_id: str, payload: QuickLinkUpdate, db: DbSession, user: CurrentUser) -> QuickLinkRead:
    link = get_or_404(db, link_id)
    if link.owner_id != user.id or link.scope != QuickLinkScope.PERSONAL:
        raise HTTPException(status_code=404, detail="QuickLink not found")
    changes = payload.model_dump(exclude_unset=True)
    if "name" in changes:
        changes["name"] = (changes["name"] or "").strip()
        if not changes["name"]:
            raise HTTPException(status_code=422, detail="名称不能为空")
    if "url" in changes:
        changes["url"] = (changes["url"] or "").strip()
        if not changes["url"].startswith(("http://", "https://")):
            raise HTTPException(status_code=422, detail="网址必须以 http:// 或 https:// 开头")
    for field, value in changes.items():
        setattr(link, field, value)
    if not link.icon:
        link.icon = derive_icon(link.name)
    db.commit()
    db.refresh(link)
    return link


@router.delete("/{link_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_quick_link(link_id: str, db: DbSession, user: CurrentUser) -> Response:
    link = get_or_404(db, link_id)
    if link.owner_id != user.id or link.scope != QuickLinkScope.PERSONAL:
        raise HTTPException(status_code=404, detail="QuickLink not found")
    db.delete(link)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
