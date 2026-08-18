"""Controlled one-time administrative initialization commands."""
from __future__ import annotations

import argparse
import sys

from sqlalchemy import select

from app.db.session import SessionLocal
from app.models.auth import SystemRole, User, UserStatus
from app.services.auth_service import normalize_username, password_hash
from app.models.todo import local_now


def init_root(args: argparse.Namespace) -> int:
    username = normalize_username(args.username)
    if not args.password:
        raise SystemExit("必须显式提供 --password；不会使用固定默认密码。")
    with SessionLocal() as db:
        if db.scalar(select(User.id).where(User.system_role == SystemRole.ROOT)) is not None:
            raise SystemExit("ROOT 账户已经存在，未执行任何修改。")
        if db.scalar(select(User.id).where(User.username == username)) is not None:
            raise SystemExit("用户名已经存在。")
        now = local_now()
        user = User(
            username=username,
            password_hash=password_hash.hash(args.password),
            nickname=args.nickname.strip() or username,
            status=UserStatus.ACTIVE,
            system_role=SystemRole.ROOT,
            can_create_team=True,
            created_at=now,
            updated_at=now,
        )
        db.add(user)
        db.commit()
    print(f"已创建 ROOT 账户：{username}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python -m app.cli")
    subparsers = parser.add_subparsers(dest="command", required=True)
    root = subparsers.add_parser("init-root", help="使用显式凭据创建第一个 ROOT 账户")
    root.add_argument("--username", required=True)
    root.add_argument("--password", required=True)
    root.add_argument("--nickname", default="系统管理员")
    root.set_defaults(handler=init_root)
    return parser


if __name__ == "__main__":
    try:
        parsed = build_parser().parse_args()
        raise SystemExit(parsed.handler(parsed))
    except KeyboardInterrupt:
        sys.exit(130)
