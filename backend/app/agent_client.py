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

    @staticmethod
    def _task_summary(task: dict[str, Any]) -> dict[str, Any]:
        return {
            key: task.get(key)
            for key in (
                "id", "title", "status", "priority", "dueAt", "dueEndAt",
                "listName", "tags", "teamId", "bodyVersion", "metadataVersion",
            )
            if key in task
        }

    def list_notes(self, *, limit: int = 50, offset: int = 0) -> list[dict[str, Any]]:
        return self._request("GET", "/notes", params={"limit": limit, "offset": offset})

    def search_notes(self, query: str, *, limit: int = 20) -> dict[str, Any]:
        return self._request(
            "GET", "/search", params={"q": query, "scope": "personal", "limit": limit}
        )

    def get_note(self, note_id: str) -> dict[str, Any]:
        return self._request("GET", f"/agent/notes/{note_id}")

    def append_note(self, note_id: str, markdown: str, *, expected_version: str) -> dict[str, Any]:
        return self._request(
            "POST",
            f"/agent/notes/{note_id}/append",
            json={"markdown": markdown, "expectedVersion": expected_version},
        )

    def replace_note(
        self,
        note_id: str,
        markdown: str,
        *,
        expected_version: str,
        title: str | None = None,
    ) -> dict[str, Any]:
        payload: dict[str, str] = {"markdown": markdown, "expectedVersion": expected_version}
        if title is not None:
            payload["title"] = title
        return self._request("PUT", f"/agent/notes/{note_id}", json=payload)

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

    def list_tasks(
        self,
        *,
        q: str | None = None,
        list_name: str | None = None,
        due_on: str | None = None,
        completed: bool | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict[str, Any]]:
        params: dict[str, Any] = {"limit": limit, "offset": offset}
        if q:
            params["q"] = q
        if list_name:
            params["list"] = list_name
        if due_on:
            params["dueOn"] = due_on
        if completed is not None:
            params["completed"] = completed
        return self._request("GET", "/agent/tasks", params=params)

    def get_task(self, task_id: str) -> dict[str, Any]:
        return self._request("GET", f"/agent/tasks/{task_id}")

    def create_task(self, title: str, **fields: Any) -> dict[str, Any]:
        result = self._request("POST", "/agent/tasks", json={"title": title, **fields})
        return self._task_summary(result)

    def replace_task_body(
        self, task_id: str, markdown: str, *, expected_version: str,
    ) -> dict[str, Any]:
        return self._request(
            "PUT",
            f"/agent/tasks/{task_id}/body",
            json={"markdown": markdown, "expectedVersion": expected_version},
        )

    def update_task_metadata(
        self, task_id: str, *, expected_version: str, fields: dict[str, Any],
    ) -> dict[str, Any]:
        return self._request(
            "PATCH",
            f"/agent/tasks/{task_id}/metadata",
            json={"expectedVersion": expected_version, **fields},
        )

    def set_task_completed(self, task_id: str, *, completed: bool) -> dict[str, Any]:
        action = "complete" if completed else "restore"
        result = self._request("POST", f"/tasks/{task_id}/{action}")
        task = result.get("todo", result)
        return self._task_summary(task)
