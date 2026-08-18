from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.db.base import Base
from app.db.session import get_db
from app.main import app
from app import models  # noqa: F401
from app.models.auth import User, UserStatus
from app.services.auth_service import password_hash
from app.services.template_service import seed_builtin_templates


engine = create_engine(
    "sqlite://",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSession = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
TEST_USER_ID = "20000000-0000-0000-0000-000000000001"


@pytest.fixture(autouse=True)
def reset_database() -> Generator[None, None, None]:
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    with TestingSession() as session:
        session.add(
            User(
                id=TEST_USER_ID,
                username="tester",
                password_hash=password_hash.hash("tester-password"),
                nickname="测试用户",
                can_create_team=True,
                status=UserStatus.ACTIVE,
            )
        )
        seed_builtin_templates(session)
    yield
    Base.metadata.drop_all(bind=engine)


@pytest.fixture
def db() -> Generator[Session, None, None]:
    with TestingSession() as session:
        yield session


@pytest.fixture
def user_id() -> str:
    return TEST_USER_ID


@pytest.fixture
def client() -> Generator[TestClient, None, None]:
    def override_get_db() -> Generator[Session, None, None]:
        with TestingSession() as session:
            yield session

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        login = test_client.post(
            "/api/auth/login",
            json={"identifier": "tester", "password": "tester-password"},
        )
        assert login.status_code == 200, login.text
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture
def unauthed_client() -> Generator[TestClient, None, None]:
    def override_get_db() -> Generator[Session, None, None]:
        with TestingSession() as session:
            yield session

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
