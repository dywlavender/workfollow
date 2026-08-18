#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
mkdir -p logs run data/files data/uploads

if [ -f run/workfollow.pid ] && kill -0 "$(cat run/workfollow.pid)" 2>/dev/null; then
  echo "WorkFollow 已在运行，PID $(cat run/workfollow.pid)。"
  exit 0
fi

HOST="${WORKFOLLOW_HOST:-0.0.0.0}"
PORT="${WORKFOLLOW_PORT:-8123}"
.venv/bin/alembic -c backend/alembic.ini upgrade head
nohup .venv/bin/uvicorn app.main:app --app-dir backend --host "$HOST" --port "$PORT" \
  >>logs/workfollow.log 2>&1 &
echo $! > run/workfollow.pid
sleep 2

if kill -0 "$(cat run/workfollow.pid)" 2>/dev/null; then
  echo "WorkFollow 已启动：http://<服务器IP>:$PORT"
  echo "日志：$ROOT_DIR/logs/workfollow.log"
else
  echo "启动失败，请检查 logs/workfollow.log。" >&2
  exit 1
fi
