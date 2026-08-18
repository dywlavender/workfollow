from fastapi.testclient import TestClient
from sqlalchemy import select

from app.models.audit import AuditLog
from app.models.auth import SystemRole, User, UserStatus
from app.services.auth_service import password_hash


def add_user(db, user_id: str, username: str, *, role: SystemRole = SystemRole.NORMAL) -> User:
    user = User(
        id=user_id,
        username=username,
        password_hash=password_hash.hash("member-password"),
        nickname=username,
        system_role=role,
        can_create_team=role == SystemRole.ROOT,
        status=UserStatus.ACTIVE,
    )
    db.add(user)
    db.commit()
    return user


def login(app, username: str) -> TestClient:
    result = TestClient(app)
    response = result.post("/api/auth/login", json={"identifier": username, "password": "member-password"})
    assert response.status_code == 200, response.text
    return result


def test_quick_link_crud_and_sorting(client: TestClient) -> None:
    later = client.post(
        "/api/quick-links",
        json={"name": "GitLab", "url": "https://gitlab.example.com", "sortOrder": 20},
    )
    earlier = client.post(
        "/api/quick-links",
        json={"name": "Jira", "url": "https://jira.example.com", "sortOrder": 10},
    )

    assert later.status_code == 201
    assert later.json()["icon"] == "GI"
    assert [item["name"] for item in client.get("/api/quick-links").json()] == ["Jira", "GitLab"]

    link_id = earlier.json()["id"]
    updated = client.put(f"/api/quick-links/{link_id}", json={"name": "Jira Cloud", "sortOrder": 30})
    assert updated.json()["name"] == "Jira Cloud"
    assert [item["name"] for item in client.get("/api/quick-links").json()] == ["GitLab", "Jira Cloud"]

    assert client.delete(f"/api/quick-links/{link_id}").status_code == 204
    assert client.delete(f"/api/quick-links/{link_id}").status_code == 404


def test_quick_links_are_limited_to_twelve(client: TestClient) -> None:
    for index in range(12):
        response = client.post(
            "/api/quick-links",
            json={"name": f"入口 {index}", "url": f"https://example.com/{index}"},
        )
        assert response.status_code == 201

    response = client.post(
        "/api/quick-links",
        json={"name": "第十三个", "url": "https://example.com/13"},
    )
    assert response.status_code == 409


def test_system_quick_links_are_public_to_read_and_root_only_to_write(client: TestClient, db) -> None:
    root = add_user(db, "22000000-0000-0000-0000-000000000001", "links-root", role=SystemRole.ROOT)
    normal = add_user(db, "22000000-0000-0000-0000-000000000002", "links-normal")
    root_client = login(client.app, root.username)
    normal_client = login(client.app, normal.username)
    anonymous = TestClient(client.app)

    assert anonymous.get("/api/quick-links/system").status_code == 401
    created = root_client.post(
        "/api/quick-links/system",
        json={
            "name": "开发平台",
            "url": "https://dev.example.com",
            "description": "团队开发入口",
            "groupName": "工作平台",
        },
    )
    assert created.status_code == 201, created.text
    system_link = created.json()
    assert system_link["scope"] == "SYSTEM"
    assert system_link["createdById"] == root.id

    second = root_client.post(
        "/api/quick-links/system",
        json={"name": "资料查询", "url": "https://docs.example.com", "groupName": "工作平台"},
    )
    assert second.status_code == 201
    second_link = second.json()
    updated = root_client.put(
        f"/api/quick-links/system/{system_link['id']}",
        json={"name": "开发平台（统一入口）", "description": "更新后的说明"},
    )
    assert updated.status_code == 200
    assert updated.json()["name"] == "开发平台（统一入口）"
    reordered = root_client.put(
        "/api/quick-links/system/reorder", json={"ids": [second_link["id"], system_link["id"]]}
    )
    assert reordered.status_code == 200
    assert [item["id"] for item in reordered.json()][:2] == [second_link["id"], system_link["id"]]
    assert root_client.delete(f"/api/quick-links/system/{second_link['id']}").status_code == 204

    assert normal_client.get("/api/quick-links/system").json()[0]["id"] == system_link["id"]
    assert normal_client.post(
        "/api/quick-links/system", json={"name": "越权", "url": "https://bad.example.com"}
    ).status_code == 403
    assert normal_client.put(
        f"/api/quick-links/system/{system_link['id']}", json={"name": "越权"}
    ).status_code == 403
    assert normal_client.delete(f"/api/quick-links/system/{system_link['id']}").status_code == 403
    assert normal_client.put(
        "/api/quick-links/system/reorder", json={"ids": [system_link["id"]]}
    ).status_code == 403

    assert root_client.post(
        "/api/quick-links/system", json={"name": "非法", "url": "javascript:alert(1)"}
    ).status_code == 422
    personal = normal_client.post(
        "/api/quick-links", json={"name": "个人网址", "url": "https://personal.example.com"}
    )
    assert personal.status_code == 201
    assert all(item["id"] != personal.json()["id"] for item in root_client.get("/api/quick-links/system").json())
    audit_logs = list(db.scalars(select(AuditLog).where(AuditLog.actor_user_id == root.id)))
    audit_actions = {item.action for item in audit_logs}
    assert {
        "QUICK_LINK_SYSTEM_CREATED",
        "QUICK_LINK_SYSTEM_UPDATED",
        "QUICK_LINK_SYSTEM_REORDERED",
        "QUICK_LINK_SYSTEM_DELETED",
    } <= audit_actions
    assert all(item.metadata_json.get("source") == "SYSTEM_ADMIN" for item in audit_logs)
