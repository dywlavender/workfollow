from fastapi.testclient import TestClient

from app.models.auth import User, UserStatus
from app.models.team import TeamMemberRole
from app.services.auth_service import password_hash


def add_user(db, user_id: str, username: str) -> User:
    user = User(
        id=user_id,
        username=username,
        password_hash=password_hash.hash("member-password"),
        nickname=username.title(),
        status=UserStatus.ACTIVE,
    )
    db.add(user)
    db.commit()
    return user


def test_create_team_add_member_and_role_permissions(client: TestClient, db, user_id: str) -> None:
    other = add_user(db, "20000000-0000-0000-0000-000000000002", "member")
    created = client.post("/api/teams", json={"name": "产品小组", "description": "协作"})
    assert created.status_code == 201, created.text
    team = created.json()
    assert team["ownerId"] == user_id
    assert team["role"] == TeamMemberRole.OWNER

    listed = client.get("/api/teams")
    assert listed.status_code == 200
    assert listed.json()[0]["id"] == team["id"]

    members = client.get(f"/api/teams/{team['id']}/members")
    assert members.status_code == 200
    assert [item["userId"] for item in members.json()] == [user_id]

    candidates = client.get(f"/api/teams/{team['id']}/member-candidates", params={"q": "mem"})
    assert candidates.status_code == 200
    assert candidates.json() == [{
        "id": other.id,
        "username": "member",
        "nickname": "Member",
        "avatarUrl": None,
    }]

    added = client.post(
        f"/api/teams/{team['id']}/members",
        json={"identifier": other.username, "role": "MEMBER"},
    )
    assert added.status_code == 201, added.text
    assert added.json()["user"]["username"] == "member"
    assert client.get(f"/api/teams/{team['id']}/member-candidates", params={"q": "member"}).json() == []
    assert client.post(
        f"/api/teams/{team['id']}/members",
        json={"identifier": other.username, "role": "MEMBER"},
    ).status_code == 409

    changed = client.put(
        f"/api/teams/{team['id']}/members/{other.id}/role",
        json={"role": "ADMIN"},
    )
    assert changed.status_code == 200, changed.text
    assert changed.json()["role"] == "ADMIN"

    # A deleted/removed membership cannot read a team or its members.
    assert client.delete(f"/api/teams/{team['id']}/members/{other.id}").status_code == 204
    assert client.get(f"/api/teams/{team['id']}/members").status_code == 200


def test_team_is_not_visible_to_non_member(client: TestClient, db) -> None:
    add_user(db, "20000000-0000-0000-0000-000000000003", "outsider")
    created = client.post("/api/teams", json={"name": "仅成员可见"})
    assert created.status_code == 201
    team_id = created.json()["id"]

    outsider = TestClient(client.app)
    login = outsider.post(
        "/api/auth/login",
        json={"identifier": "outsider", "password": "member-password"},
    )
    assert login.status_code == 200
    assert outsider.get(f"/api/teams/{team_id}").status_code == 404
    assert outsider.get(f"/api/teams/{team_id}/members").status_code == 404
    assert outsider.get(f"/api/teams/{team_id}/member-candidates").status_code == 404


def test_multiple_teams_member_leave_and_owner_dissolve(client: TestClient, db) -> None:
    member = add_user(
        db,
        "20000000-0000-0000-0000-000000000013",
        "multi-member",
    )
    first = client.post("/api/teams", json={"name": "第一团队"}).json()
    second_response = client.post("/api/teams", json={"name": "第二团队"})
    assert second_response.status_code == 201, second_response.text
    second = second_response.json()
    assert {team["id"] for team in client.get("/api/teams").json()} == {first["id"], second["id"]}

    for team in (first, second):
        assert client.post(
            f"/api/teams/{team['id']}/members",
            json={"identifier": member.username, "role": "MEMBER"},
        ).status_code == 201

    member_client = TestClient(client.app)
    assert member_client.post(
        "/api/auth/login", json={"identifier": member.username, "password": "member-password"}
    ).status_code == 200
    assert len(member_client.get("/api/teams").json()) == 2
    assert client.put(
        f"/api/teams/{first['id']}/members/{member.id}/role", json={"role": "ADMIN"}
    ).status_code == 200
    team_task = member_client.post(
        "/api/tasks", json={"title": "离开后不可见", "assigneeIds": [first["ownerId"]]}
    )
    assert team_task.status_code == 201, team_task.text
    assert team_task.json()["teamId"] == first["id"]
    assert member_client.post(f"/api/teams/{first['id']}/leave").status_code == 204
    assert member_client.get(f"/api/teams/{first['id']}").status_code == 404
    assert member_client.get(f"/api/tasks/{team_task.json()['id']}").status_code == 404
    assert member_client.get(f"/api/teams/{second['id']}").status_code == 200

    assert client.post(f"/api/teams/{first['id']}/leave").status_code == 422
    assert client.delete(f"/api/teams/{first['id']}").status_code == 204
    assert client.get(f"/api/teams/{first['id']}").status_code == 404
    assert [team["id"] for team in client.get("/api/teams").json()] == [second["id"]]


def test_admin_can_manage_team_but_cannot_change_roles(client: TestClient, db) -> None:
    admin = add_user(db, "20000000-0000-0000-0000-000000000004", "admin")
    member = add_user(db, "20000000-0000-0000-0000-000000000005", "worker")
    created = client.post("/api/teams", json={"name": "权限测试"})
    team_id = created.json()["id"]
    assert client.post(
        f"/api/teams/{team_id}/members", json={"identifier": admin.username, "role": "ADMIN"}
    ).status_code == 201

    admin_client = TestClient(client.app)
    assert admin_client.post(
        "/api/auth/login", json={"identifier": "admin", "password": "member-password"}
    ).status_code == 200
    assert admin_client.post(
        f"/api/teams/{team_id}/members", json={"identifier": member.username, "role": "MEMBER"}
    ).status_code == 201
    assert admin_client.put(
        f"/api/teams/{team_id}/members/{member.id}/role", json={"role": "ADMIN"}
    ).status_code == 403


def test_team_password_reset_respects_role_hierarchy_and_revokes_sessions(client: TestClient, db, user_id: str) -> None:
    admin = add_user(db, "20000000-0000-0000-0000-000000000020", "reset-admin")
    peer_admin = add_user(db, "20000000-0000-0000-0000-000000000021", "peer-admin")
    member = add_user(db, "20000000-0000-0000-0000-000000000022", "reset-member")
    outsider = add_user(db, "20000000-0000-0000-0000-000000000023", "reset-outsider")
    team = client.post("/api/teams", json={"name": "密码权限测试"}).json()
    team_id = team["id"]
    for target, role in ((admin, "ADMIN"), (peer_admin, "ADMIN"), (member, "MEMBER")):
        assert client.post(
            f"/api/teams/{team_id}/members", json={"identifier": target.username, "role": role}
        ).status_code == 201

    admin_client = TestClient(client.app)
    member_client = TestClient(client.app)
    assert admin_client.post(
        "/api/auth/login", json={"identifier": admin.username, "password": "member-password"}
    ).status_code == 200
    assert member_client.post(
        "/api/auth/login", json={"identifier": member.username, "password": "member-password"}
    ).status_code == 200

    reset_member = admin_client.post(f"/api/teams/{team_id}/members/{member.id}/reset-password")
    assert reset_member.status_code == 200, reset_member.text
    assert reset_member.json()["initialPassword"] == "11111111"
    assert member_client.get("/api/auth/me").status_code == 401
    assert TestClient(client.app).post(
        "/api/auth/login", json={"identifier": member.username, "password": "11111111"}
    ).status_code == 200

    assert admin_client.post(f"/api/teams/{team_id}/members/{user_id}/reset-password").status_code == 403
    assert admin_client.post(f"/api/teams/{team_id}/members/{peer_admin.id}/reset-password").status_code == 403
    assert admin_client.post(f"/api/teams/{team_id}/members/{outsider.id}/reset-password").status_code == 404
    member_with_new_password = TestClient(client.app)
    assert member_with_new_password.post(
        "/api/auth/login", json={"identifier": member.username, "password": "11111111"}
    ).status_code == 200
    assert member_with_new_password.post(
        f"/api/teams/{team_id}/members/{member.id}/reset-password"
    ).status_code == 403

    owner_reset_admin = client.post(f"/api/teams/{team_id}/members/{peer_admin.id}/reset-password")
    assert owner_reset_admin.status_code == 200
    reset_self = admin_client.post(f"/api/teams/{team_id}/members/{admin.id}/reset-password")
    assert reset_self.status_code == 200
    assert admin_client.get("/api/auth/me").status_code == 401
    assert TestClient(client.app).post(
        "/api/auth/login", json={"identifier": admin.username, "password": "11111111"}
    ).status_code == 200
