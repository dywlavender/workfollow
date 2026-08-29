"""Bridge trusted Agent operations into the authoritative Yjs documents."""

from __future__ import annotations

from typing import Any

import httpx
from fastapi import HTTPException, status

from app.core.config import Settings


def document_request(
    settings: Settings,
    *,
    document_name: str,
    seed: dict[str, Any],
    actor_id: str,
    operation: str = "read",
    expected_version: str | None = None,
    content_json: dict[str, Any] | None = None,
    title: str | None = None,
    metadata: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if not settings.collaboration_internal_token:
        raise HTTPException(status_code=503, detail="协同服务内部凭据未配置")
    payload: dict[str, Any] = {
        "documentName": document_name,
        "seed": seed,
        "actorId": actor_id,
        "operation": operation,
    }
    if expected_version is not None:
        payload["expectedVersion"] = expected_version
    if content_json is not None:
        payload["contentJson"] = content_json
    if title is not None:
        payload["title"] = title
    if metadata is not None:
        payload["metadata"] = metadata

    try:
        response = httpx.post(
            f"{settings.collaboration_http_url.rstrip('/')}/internal/agent-document",
            headers={"X-WorkFollow-Collaboration-Token": settings.collaboration_internal_token},
            json=payload,
            timeout=30.0,
        )
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail=f"协同服务不可用：{exc}") from exc
    if response.status_code == status.HTTP_409_CONFLICT:
        raise HTTPException(status_code=409, detail="文档已被其他编辑者修改，请重新读取后再提交")
    if not response.is_success:
        try:
            detail = response.json().get("detail")
        except (ValueError, AttributeError):
            detail = None
        raise HTTPException(status_code=502, detail=detail or f"协同服务返回 {response.status_code}")
    return response.json()
