from fastapi.testclient import TestClient
from datetime import date
import pytest
from sqlalchemy import select

from app.models.auth import User
from app.models.note import Note
from app.models.resource_relation import RelationType, ResourceRelation, ResourceType
from app.models.todo import Todo
from app.services import onboarding_service


def test_register_login_me_and_logout(client: TestClient) -> None:
    registered = client.post(
        "/api/auth/register",
        json={
            "username": "alice",
            "password": "alice-password",
        },
    )
    assert registered.status_code == 201
    assert registered.json()["user"]["username"] == "alice"

    assert client.get("/api/auth/me").json()["username"] == "alice"
    assert client.post("/api/auth/logout").status_code == 204
    assert client.get("/api/auth/me").status_code == 401

    logged_in = client.post(
        "/api/auth/login",
        json={"identifier": "alice", "password": "alice-password"},
    )
    assert logged_in.status_code == 200


def test_update_current_user_nickname(client: TestClient, db) -> None:
    updated = client.patch("/api/auth/me", json={"nickname": "系统管理员"})

    assert updated.status_code == 200
    assert updated.json()["nickname"] == "系统管理员"
    assert client.get("/api/auth/me").json()["nickname"] == "系统管理员"
    assert db.scalar(select(User).where(User.username == "tester")).nickname == "系统管理员"


def test_update_current_user_rejects_blank_nickname(client: TestClient) -> None:
    response = client.patch("/api/auth/me", json={"nickname": "   "})

    assert response.status_code == 422


def test_protected_personal_api_requires_login(unauthed_client: TestClient) -> None:
    assert unauthed_client.get("/api/todos").status_code == 401
    assert unauthed_client.get("/api/notes").status_code == 401


def test_migrated_user_does_not_receive_onboarding_on_login(client: TestClient, db) -> None:
    assert client.post("/api/auth/logout").status_code == 204
    logged_in = client.post(
        "/api/auth/login", json={"identifier": "tester", "password": "tester-password"}
    )
    assert logged_in.status_code == 200
    assert logged_in.json()["isFirstRun"] is False
    assert db.scalar(select(Note).where(Note.title == "使用指南")) is None


def test_registration_creates_one_guide_task_and_note_relation(client: TestClient, db) -> None:
    registered = client.post(
        "/api/auth/register",
        json={"username": "first-run", "password": "first-run-password"},
    )
    assert registered.status_code == 201, registered.text
    body = registered.json()
    assert body["isFirstRun"] is True
    assert body["guideNoteId"]
    assert body["starterTaskId"]

    guide = db.scalar(select(Note).where(Note.id == body["guideNoteId"]))
    task = db.scalar(select(Todo).where(Todo.id == body["starterTaskId"]))
    relation = db.scalar(select(ResourceRelation).where(ResourceRelation.target_id == body["starterTaskId"]))
    assert guide is not None and guide.title == "使用指南"
    assert task is not None and task.title == "阅读《使用指南》并完成首次设置"
    assert task.due_at is not None and task.due_at.date() == date.today()
    assert task.team_id is None and task.owner_id == guide.owner_id
    assert relation is not None
    assert relation.source_type == ResourceType.PERSONAL_NOTE
    assert relation.source_id == guide.id
    assert relation.target_type == ResourceType.TASK
    assert relation.relation_type == RelationType.CREATED_FROM

    assert client.post("/api/auth/logout").status_code == 204
    logged_in = client.post(
        "/api/auth/login", json={"identifier": "first-run", "password": "first-run-password"}
    )
    assert logged_in.status_code == 200
    assert logged_in.json()["isFirstRun"] is False
    assert db.scalar(select(User.onboarding_version).where(User.id == guide.owner_id)) == 1
    assert len(list(db.scalars(select(Note).where(Note.owner_id == guide.owner_id)))) == 1
    assert len(list(db.scalars(select(Todo).where(Todo.owner_id == guide.owner_id)))) == 1


def test_deleted_guide_is_not_recreated_and_personal_onboarding_is_private(client: TestClient) -> None:
    registered = client.post(
        "/api/auth/register", json={"username": "guide-owner", "password": "guide-password"}
    )
    guide_id = registered.json()["guideNoteId"]
    assert client.delete(f"/api/notes/{guide_id}").status_code == 204
    assert client.post("/api/auth/logout").status_code == 204
    logged_in = client.post(
        "/api/auth/login", json={"identifier": "guide-owner", "password": "guide-password"}
    )
    assert logged_in.status_code == 200 and logged_in.json()["isFirstRun"] is False
    assert all(note["id"] != guide_id for note in client.get("/api/notes").json())

    other = TestClient(client.app)
    created = other.post(
        "/api/auth/register", json={"username": "other-owner", "password": "other-password"}
    )
    assert created.status_code == 201
    assert all(note["id"] != guide_id for note in other.get("/api/notes").json())
    assert all(task["id"] != registered.json()["starterTaskId"] for task in other.get("/api/tasks").json())


def test_registration_onboarding_failure_rolls_back_user_and_data(client: TestClient, db, monkeypatch) -> None:
    def fail(*args, **kwargs):
        raise RuntimeError("onboarding failed")

    monkeypatch.setattr(onboarding_service.todo_service, "create_todo", fail)
    with pytest.raises(RuntimeError):
        client.post(
            "/api/auth/register", json={"username": "rollback-user", "password": "rollback-password"}
        )

    assert db.scalar(select(User).where(User.username == "rollback-user")) is None
    assert db.scalar(select(Note).where(Note.title == "使用指南")) is None
