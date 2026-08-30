#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
mkdir -p logs run data/files data/uploads

pid_running() {
  local pid_file="$1"
  [ -s "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null
}

BACKEND_RUNNING=0
COLLABORATION_RUNNING=0
pid_running run/workfollow.pid && BACKEND_RUNNING=1
pid_running run/workfollow-collaboration.pid && COLLABORATION_RUNNING=1
if [ "$BACKEND_RUNNING" -eq 1 ] && [ "$COLLABORATION_RUNNING" -eq 1 ]; then
  echo "WorkFollow 后端和协同服务均已运行。"
  exit 0
fi

command -v node >/dev/null 2>&1 || { echo "缺少 Node.js 22+。" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "缺少 curl，无法执行健康检查。" >&2; exit 1; }
[ -x .venv/bin/uvicorn ] || { echo "缺少后端虚拟环境，请先运行 deploy/linux/install.sh。" >&2; exit 1; }
[ -f collaboration/node_modules/@hocuspocus/server/package.json ] || {
  echo "协同服务依赖不完整，请重新安装完整离线发布包。" >&2
  exit 1
}
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 22 ] || { echo "需要 Node.js 22+，当前为 $(node --version)。" >&2; exit 1; }

HOST="${WORKFOLLOW_HOST:-0.0.0.0}"
PORT="${WORKFOLLOW_PORT:-8123}"
COLLABORATION_PORT="${WORKFOLLOW_COLLABORATION_PORT:-8124}"
COLLABORATION_BIND="${WORKFOLLOW_COLLABORATION_BIND:-$HOST}"
export WORKFOLLOW_BACKEND_URL="${WORKFOLLOW_BACKEND_URL:-http://127.0.0.1:$PORT}"
export WORKFOLLOW_COLLABORATION_BIND="$COLLABORATION_BIND"
export WORKFOLLOW_COLLABORATION_PORT="$COLLABORATION_PORT"
export WORKFOLLOW_COLLABORATION_HTTP_URL="${WORKFOLLOW_COLLABORATION_HTTP_URL:-http://127.0.0.1:$COLLABORATION_PORT}"
export WORKFOLLOW_COLLABORATION_DATA_DIR="${WORKFOLLOW_COLLABORATION_DATA_DIR:-$ROOT_DIR/data/collaboration}"
if [ -z "${WORKFOLLOW_COLLABORATION_INTERNAL_TOKEN+x}" ] || [ -z "$WORKFOLLOW_COLLABORATION_INTERNAL_TOKEN" ]; then
  TOKEN_FILE="$ROOT_DIR/run/workfollow-collaboration-token"
  if [ -s "$TOKEN_FILE" ]; then
    export WORKFOLLOW_COLLABORATION_INTERNAL_TOKEN="$(cat "$TOKEN_FILE")"
  else
    export WORKFOLLOW_COLLABORATION_INTERNAL_TOKEN="$(.venv/bin/python -c 'import secrets; print(secrets.token_urlsafe(32))')"
    (umask 077 && printf '%s' "$WORKFOLLOW_COLLABORATION_INTERNAL_TOKEN" > "$TOKEN_FILE")
  fi
fi

NEW_BACKEND=0
NEW_COLLABORATION=0
cleanup_started() {
  if [ "$NEW_COLLABORATION" -eq 1 ] && pid_running run/workfollow-collaboration.pid; then
    kill "$(cat run/workfollow-collaboration.pid)" 2>/dev/null || true
  fi
  if [ "$NEW_BACKEND" -eq 1 ] && pid_running run/workfollow.pid; then
    kill "$(cat run/workfollow.pid)" 2>/dev/null || true
  fi
}

if [ "$BACKEND_RUNNING" -eq 0 ]; then
  .venv/bin/alembic -c backend/alembic.ini upgrade head
  nohup .venv/bin/uvicorn app.main:app --app-dir backend --host "$HOST" --port "$PORT" \
    >>logs/workfollow.log 2>&1 &
  echo $! > run/workfollow.pid
  NEW_BACKEND=1
  sleep 2
  if ! pid_running run/workfollow.pid || ! curl -fsS "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
    echo "WorkFollow 后端尚未就绪，请检查 logs/workfollow.log。" >&2
    cleanup_started
    exit 1
  fi
fi

if [ "$COLLABORATION_RUNNING" -eq 0 ]; then
  nohup node collaboration/server.mjs \
    >>logs/workfollow-collaboration.log 2>&1 &
  echo $! > run/workfollow-collaboration.pid
  NEW_COLLABORATION=1
  sleep 2
  if ! pid_running run/workfollow-collaboration.pid || ! curl -fsS "http://127.0.0.1:$COLLABORATION_PORT/health" >/dev/null 2>&1; then
    echo "WorkFollow 协同服务启动失败，请检查 logs/workfollow-collaboration.log。" >&2
    cleanup_started
    exit 1
  fi
fi

echo "WorkFollow 已启动：http://<服务器IP>:$PORT"
echo "协同服务端口：$COLLABORATION_PORT（需与业务端口一并放行）"
echo "日志：$ROOT_DIR/logs/workfollow.log 和 logs/workfollow-collaboration.log"
