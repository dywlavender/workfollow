#!/bin/bash

set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$PROJECT_DIR/backend"
FRONTEND_DIR="$PROJECT_DIR/frontend"
BACKEND_PORT="${WORKFOLLOW_BACKEND_PORT:-8123}"
FRONTEND_PORT="${WORKFOLLOW_FRONTEND_PORT:-5173}"
BACKEND_PID=""
FRONTEND_PID=""

info() {
  printf '\033[1;35m[WorkFollow]\033[0m %s\n' "$1"
}

fail() {
  printf '\033[1;31m[启动失败]\033[0m %s\n' "$1" >&2
  printf '\n按回车键关闭窗口...'
  read -r _
  exit 1
}

cleanup() {
  trap - EXIT INT TERM
  info "正在关闭前后端服务..."
  if [ -n "$FRONTEND_PID" ] && kill -0 "$FRONTEND_PID" 2>/dev/null; then
    kill "$FRONTEND_PID" 2>/dev/null || true
  fi
  if [ -n "$BACKEND_PID" ] && kill -0 "$BACKEND_PID" 2>/dev/null; then
    kill "$BACKEND_PID" 2>/dev/null || true
  fi
  wait "$FRONTEND_PID" 2>/dev/null || true
  wait "$BACKEND_PID" 2>/dev/null || true
}

port_is_busy() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

stop_existing_processes_on_port() {
  local port="$1"
  local pids pid

  pids="$(lsof -nP -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  [ -n "$pids" ] || return 0

  info "正在关闭端口 $port 上的旧进程：$pids"
  for pid in $pids; do
    kill "$pid" 2>/dev/null || true
  done

  for _ in $(seq 1 20); do
    if ! port_is_busy "$port"; then
      return 0
    fi
    sleep 0.1
  done

  pids="$(lsof -nP -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  for pid in $pids; do
    info "旧进程未及时退出，强制终止进程 ${pid}。"
    kill -KILL "$pid" 2>/dev/null || true
  done
}

command -v python3 >/dev/null 2>&1 || fail "未找到 Python 3，请先安装 Python 3.12 或更高版本。"
command -v node >/dev/null 2>&1 || fail "未找到 Node.js，请先安装 Node.js 20 或更高版本。"
command -v npm >/dev/null 2>&1 || fail "未找到 npm，请重新安装 Node.js。"
command -v curl >/dev/null 2>&1 || fail "未找到 curl，无法执行健康检查。"
command -v lsof >/dev/null 2>&1 || fail "未找到 lsof，无法清理旧服务进程。"

stop_existing_processes_on_port "$BACKEND_PORT"
stop_existing_processes_on_port "$FRONTEND_PORT"

if port_is_busy "$BACKEND_PORT"; then
  fail "后端端口 $BACKEND_PORT 已被占用，请先关闭占用该端口的程序。"
fi
if port_is_busy "$FRONTEND_PORT"; then
  fail "前端端口 $FRONTEND_PORT 已被占用，请先关闭占用该端口的程序。"
fi

if [ ! -x "$BACKEND_DIR/.venv/bin/python" ]; then
  info "首次运行：创建 Python 虚拟环境..."
  python3 -m venv "$BACKEND_DIR/.venv"
fi

if ! "$BACKEND_DIR/.venv/bin/python" -c "import fastapi" >/dev/null 2>&1; then
  info "首次运行：安装后端依赖..."
  "$BACKEND_DIR/.venv/bin/pip" install -r "$BACKEND_DIR/requirements-dev.txt"
fi

if [ ! -d "$FRONTEND_DIR/node_modules" ]; then
  info "首次运行：安装前端依赖..."
  (cd "$FRONTEND_DIR" && npm install)
fi

info "更新本地数据库结构..."
(cd "$BACKEND_DIR" && .venv/bin/alembic upgrade head)

trap cleanup EXIT INT TERM

info "启动后端：http://127.0.0.1:$BACKEND_PORT"
(cd "$BACKEND_DIR" && .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port "$BACKEND_PORT") &
BACKEND_PID=$!

info "等待后端就绪..."
BACKEND_READY=0
for _ in $(seq 1 40); do
  if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
    fail "后端进程提前退出，请查看上方日志。"
  fi
  if curl -fsS "http://127.0.0.1:$BACKEND_PORT/api/health" >/dev/null 2>&1; then
    BACKEND_READY=1
    break
  fi
  sleep 0.5
done

if [ "$BACKEND_READY" -ne 1 ]; then
  fail "后端在 20 秒内未就绪，请查看上方日志。"
fi

info "启动前端：http://127.0.0.1:$FRONTEND_PORT"
(cd "$FRONTEND_DIR" && npm run dev -- --host 127.0.0.1 --port "$FRONTEND_PORT" --strictPort) &
FRONTEND_PID=$!

info "等待前端就绪..."
FRONTEND_READY=0
for _ in $(seq 1 40); do
  if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
    fail "后端进程在前端启动期间退出，请查看上方日志。"
  fi
  if ! kill -0 "$FRONTEND_PID" 2>/dev/null; then
    fail "前端进程提前退出，请查看上方日志。"
  fi
  if curl -fsS "http://127.0.0.1:$FRONTEND_PORT" >/dev/null 2>&1; then
    FRONTEND_READY=1
    break
  fi
  sleep 0.5
done

if [ "$FRONTEND_READY" -ne 1 ]; then
  fail "前端在 20 秒内未就绪，请查看上方日志。"
fi

info "启动成功，正在打开浏览器。"
if [ "${WORKFOLLOW_NO_OPEN:-0}" != "1" ] && command -v open >/dev/null 2>&1; then
  open "http://127.0.0.1:$FRONTEND_PORT"
fi

printf '\nWorkFollow 正在运行。关闭此窗口或按 Control+C 即可停止服务。\n\n'

while kill -0 "$BACKEND_PID" 2>/dev/null && kill -0 "$FRONTEND_PID" 2>/dev/null; do
  sleep 1
done

fail "某个服务意外退出，请查看上方日志。"
