"""Small HTTP client used by the local MCP adapter."""

from __future__ import annotations

import os
from typing import Any

import httpx


DEFAULT_API_URL = "http://127.0.0.1:8123/api"


class WorkFollowAgentClient:
    def __init__(
        self,
        *,
        base_url: str | None = None,
        token: str | None = None,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        resolved_token = token or os.environ.get("WORKFOLLOW_AGENT_TOKEN", "").strip()
        if not resolved_token:
            raise RuntimeError(
                "未配置 WORKFOLLOW_AGENT_TOKEN。请在打勾的“设置 → 账号 → Agent 接入”中生成。"
            )
        self._client = httpx.Client(
            base_url=(base_url or os.environ.get("WORKFOLLOW_API_URL") or DEFAULT_API_URL).rstrip("/"),
            headers={"Authorization": f"Bearer {resolved_token}", "Accept": "application/json"},
            timeout=20.0,
            transport=transport,
        )

    def close(self) -> None:
        self._client.close()

    def _request(self, method: str, path: str, **kwargs: Any) -> Any:
        try:
            response = self._client.request(method, path, **kwargs)
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            try:
                detail = exc.response.json().get("detail")
            except (ValueError, AttributeError):
                detail = None
            raise RuntimeError(detail or f"打勾 API 返回 {exc.response.status_code}") from exc
        except httpx.HTTPError as exc:
            raise RuntimeError(f"无法连接打勾 API：{exc}") from exc
        if response.status_code == 204:
            return None
        return response.json()

    def list_notes(self, *, limit: int = 50, offset: int = 0) -> list[dict[str, Any]]:
        return self._request("GET", "/notes", params={"limit": limit, "offset": offset})

    def search_notes(self, query: str, *, limit: int = 20) -> dict[str, Any]:
        return self._request(
            "GET", "/search", params={"q": query, "scope": "personal", "limit": limit}
        )

    def get_note(self, note_id: str) -> dict[str, Any]:
        return self._request("GET", f"/notes/{note_id}")

    def capture_note(self, text: str, *, title: str | None = None) -> dict[str, Any]:
        payload: dict[str, str] = {"text": text}
        if title:
            payload["title"] = title
        return self._request("POST", "/notes/capture", json=payload)

    def create_note(
        self,
        markdown: str,
        *,
        title: str | None = None,
        folder_id: str | None = None,
    ) -> dict[str, Any]:
        data: dict[str, str] = {}
        if title:
            data["title"] = title
        if folder_id:
            data["folderId"] = folder_id
        return self._request(
            "POST",
            "/notes/import-markdown",
            data=data,
            files={"file": ("agent-note.md", markdown.encode("utf-8"), "text/markdown")},
        )
