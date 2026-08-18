#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

if [ ! -f run/workfollow.pid ]; then
  echo "WorkFollow 未运行。"
  exit 0
fi
PID="$(cat run/workfollow.pid)"
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  for _ in $(seq 1 20); do
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.25
  done
fi
rm -f run/workfollow.pid
echo "WorkFollow 已停止。"
